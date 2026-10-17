-- =====================================================================
-- 참조 구현: Boost 1건 처리 트랜잭션 (PL/pgSQL)
-- 작성일: 2026-10-17
-- 목적: 백엔드 Boost 서비스의 "정답 동작"을 실행 가능한 형태로 고정한다.
--       실제 서비스는 애플리케이션 코드로 구현해도 되지만, 결과는 이 함수와 같아야 한다
--       (handoff/db/test_boost.sql 의 케이스를 통과할 것)
-- 호출: SELECT rorr.send_boost(...)  — 한 트랜잭션 안에서 실행
-- 오류 코드(SQLSTATE P0001, MESSAGE = API 오류 코드와 동일):
--   amount_below_min, energy_not_allowed, moment_closed, milestone_closed,
--   not_partner_player, insufficient_balance
-- =====================================================================
SET search_path = rorr, public;

CREATE OR REPLACE FUNCTION send_boost(
  p_user       uuid,
  p_team       text,
  p_player     text,            -- NULL = 팀 대상
  p_moment     uuid,            -- NULL = 순간 미선택
  p_milestone  uuid,            -- 기념 Boost
  p_currency   currency_kind,
  p_amount     int,
  p_client     client_kind,
  p_entry      boost_entry,
  p_notice     text,            -- Energy면 필수(§1-2 고지 버전)
  p_idem       text
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_now        timestamptz := now();
  v_existing   boosts%ROWTYPE;
  v_min        int;
  v_partner    boolean;
  v_moment     moments%ROWTYPE;
  v_ms         milestones%ROWTYPE;
  v_match      text;
  v_boost      uuid;
  v_need       int := p_amount;
  v_take       int;
  v_lot        record;
  v_bal        int;
  v_tot        moment_totals%ROWTYPE;
  v_prev_badge smallint := 0;
  v_new_badge  smallint := 0;
  v_card       cards%ROWTYPE;
  v_is_new     boolean := false;
  v_star       text;
  v_rule       text;
  v_pts        jsonb := '{}'::jsonb;
  v_ptcfg      jsonb;
  v_streak     int;
  v_added      int;
  v_celebr     int;
BEGIN
  -- 0) 멱등: 같은 키면 처음 결과를 다시 돌려준다
  SELECT * INTO v_existing FROM boosts WHERE user_id = p_user AND idempotency_key = p_idem;
  IF FOUND THEN
    RETURN jsonb_build_object('boost_id', v_existing.id, 'replayed', true);
  END IF;

  -- 1) 최소 단가
  SELECT (value->>p_currency::text)::int INTO v_min FROM app_config WHERE key = 'boost_min';
  IF p_amount < v_min THEN RAISE EXCEPTION 'amount_below_min'; END IF;

  -- 2) 파트너 판정(현재 시점 협약)
  SELECT EXISTS (SELECT 1 FROM partner_agreements WHERE team_id = p_team AND valid @> v_now) INTO v_partner;
  IF p_currency = 'energy' AND NOT v_partner THEN RAISE EXCEPTION 'energy_not_allowed'; END IF;
  IF p_player IS NOT NULL AND NOT v_partner THEN RAISE EXCEPTION 'not_partner_player'; END IF;

  -- 3) 순간·기념일 창
  IF p_moment IS NOT NULL THEN
    SELECT * INTO v_moment FROM moments WHERE id = p_moment;
    IF NOT FOUND OR v_moment.status <> 'open' OR NOT (v_now >= v_moment.opens_at AND v_now < v_moment.closes_at) THEN
      RAISE EXCEPTION 'moment_closed';
    END IF;
    SELECT g.match_id INTO v_match FROM games g WHERE g.id = v_moment.game_id;
  END IF;
  IF p_milestone IS NOT NULL THEN
    SELECT * INTO v_ms FROM milestones WHERE id = p_milestone FOR UPDATE;
    IF NOT FOUND OR NOT (v_ms.celebrate_window @> v_now::date) OR NOT v_partner THEN
      RAISE EXCEPTION 'milestone_closed';
    END IF;
  END IF;

  -- 4) Boost 행(차감 전에 만들어 FK 확보)
  INSERT INTO boosts (user_id, match_id, moment_id, milestone_id, target, team_id, player_id,
                      currency, amount, is_partner, client, entry, notice_version, notice_shown_at,
                      idempotency_key, created_at)
  VALUES (p_user, v_match, p_moment, p_milestone,
          CASE WHEN p_player IS NULL THEN 'team' ELSE 'player' END::boost_target,
          p_team, p_player, p_currency, p_amount, v_partner, p_client, p_entry,
          p_notice, CASE WHEN p_notice IS NULL THEN NULL ELSE v_now END, p_idem, v_now)
  RETURNING id INTO v_boost;

  -- 5) 차감: Energy=유료 묶음만(v1.3), Spark=무료 묶음. 만료 빠른 순, 행 잠금
  FOR v_lot IN
    SELECT id, remaining, unit_price_krw, list_unit_price_krw FROM wallet_lots
    WHERE user_id = p_user AND currency = p_currency
      AND kind = CASE WHEN p_currency = 'energy' THEN 'paid' ELSE 'free' END::lot_kind
      AND status = 'active' AND remaining > 0 AND expires_at > v_now
    ORDER BY expires_at, acquired_at
    FOR UPDATE
  LOOP
    EXIT WHEN v_need = 0;
    v_take := LEAST(v_need, v_lot.remaining);
    UPDATE wallet_lots SET remaining = remaining - v_take,
                           status = CASE WHEN remaining - v_take = 0 THEN 'depleted' ELSE status END
    WHERE id = v_lot.id;
    INSERT INTO boost_lot_usage VALUES (v_boost, v_lot.id, v_take, v_lot.unit_price_krw, v_lot.list_unit_price_krw);
    v_need := v_need - v_take;
  END LOOP;
  IF v_need > 0 THEN RAISE EXCEPTION 'insufficient_balance'; END IF;  -- 트랜잭션 전체 롤백

  SELECT COALESCE(SUM(remaining),0) INTO v_bal FROM wallet_lots
   WHERE user_id = p_user AND currency = p_currency AND status = 'active' AND expires_at > v_now;
  INSERT INTO wallet_ledger (user_id, currency, lot_id, delta, reason, ref_type, ref_id, balance_after)
  SELECT p_user, p_currency, u.lot_id, -u.qty, 'boost', 'boost', v_boost::text, v_bal
  FROM boost_lot_usage u WHERE u.boost_id = v_boost;

  -- 6) 같은 순간 누적 → 배지
  IF p_moment IS NOT NULL THEN
    SELECT * INTO v_tot FROM moment_totals WHERE user_id = p_user AND moment_id = p_moment FOR UPDATE;
    IF FOUND THEN
      v_prev_badge := CASE WHEN p_currency = 'energy' THEN v_tot.energy_badge ELSE v_tot.spark_badge END;
    END IF;
    INSERT INTO moment_totals AS t (user_id, moment_id, team_id, energy_total, spark_total)
    VALUES (p_user, p_moment, p_team,
            CASE WHEN p_currency='energy' THEN p_amount ELSE 0 END,
            CASE WHEN p_currency='spark'  THEN p_amount ELSE 0 END)
    ON CONFLICT (user_id, moment_id) DO UPDATE SET
      energy_total = t.energy_total + EXCLUDED.energy_total,
      spark_total  = t.spark_total  + EXCLUDED.spark_total,
      updated_at   = v_now
    RETURNING * INTO v_tot;
    UPDATE moment_totals SET energy_badge = badge_level(energy_total,'energy'),
                             spark_badge  = badge_level(spark_total,'spark')
    WHERE user_id = p_user AND moment_id = p_moment RETURNING * INTO v_tot;
    v_new_badge := CASE WHEN p_currency = 'energy' THEN v_tot.energy_badge ELSE v_tot.spark_badge END;
  END IF;

  -- 7) 카드: 순간당 1장 / 기념일당 1장
  IF p_moment IS NOT NULL THEN
    SELECT * INTO v_card FROM cards WHERE user_id = p_user AND moment_id = p_moment;
    IF NOT FOUND THEN
      IF v_partner THEN
        SELECT CASE WHEN u.fav_player_id IS NOT NULL AND EXISTS
                     (SELECT 1 FROM moment_participants mp WHERE mp.moment_id = p_moment AND mp.player_id = u.fav_player_id)
                    THEN u.fav_player_id END
          INTO v_star FROM users u WHERE u.id = p_user;
        IF v_star IS NOT NULL THEN v_rule := 'fav';
        ELSE
          SELECT player_id INTO v_star FROM moment_participants WHERE moment_id = p_moment AND is_top;
          v_rule := CASE WHEN v_star IS NULL THEN 'auto' ELSE 'top' END;
        END IF;
      END IF;
      INSERT INTO cards (user_id, kind, moment_id, first_boost_id, team_id, tier, edition,
                         star_player_id, star_rule, issued_client)
      VALUES (p_user, 'moment', p_moment, v_boost, p_team, v_moment.tier,
              CASE WHEN v_partner THEN 'partner' ELSE 'rorr' END::card_edition,
              v_star, v_rule, p_client)
      RETURNING * INTO v_card;
      v_is_new := true;
    END IF;
  ELSIF p_milestone IS NOT NULL THEN
    SELECT * INTO v_card FROM cards WHERE user_id = p_user AND milestone_id = p_milestone;
    IF NOT FOUND THEN
      UPDATE milestones SET celebrations = celebrations + 1 WHERE id = p_milestone RETURNING celebrations INTO v_celebr;
      INSERT INTO cards (user_id, kind, milestone_id, first_boost_id, team_id, tier, edition,
                         star_player_id, star_rule, celebration_no, issued_client)
      VALUES (p_user, 'commemorative', p_milestone, v_boost, p_team, NULL, 'partner',
              v_ms.player_id, 'fav', v_celebr, p_client)
      RETURNING * INTO v_card;
      v_is_new := true;
    END IF;
  END IF;

  -- 8) 응원 포인트: 순간당 1회(base+tier), 경기당 첫 Boost에 streak 1회
  IF p_moment IS NOT NULL THEN
    SELECT value INTO v_ptcfg FROM app_config WHERE key = 'points';
    INSERT INTO point_events (user_id, team_id, match_id, moment_id, boost_id, kind, points, currency, dedup_key)
    VALUES (p_user, p_team, v_match, p_moment, v_boost, 'base', (v_ptcfg->>'base')::int, p_currency,
            p_user || ':' || p_moment || ':base')
    ON CONFLICT (dedup_key) DO NOTHING;
    GET DIAGNOSTICS v_added = ROW_COUNT;
    IF v_added = 1 THEN
      INSERT INTO point_events (user_id, team_id, match_id, moment_id, boost_id, kind, points, currency, dedup_key)
      VALUES (p_user, p_team, v_match, p_moment, v_boost, 'tier',
              (v_ptcfg->'tier'->>v_moment.tier::text)::int, p_currency, p_user || ':' || p_moment || ':tier');
      v_pts := jsonb_build_object('base', (v_ptcfg->>'base')::int,
                                  'tier', (v_ptcfg->'tier'->>v_moment.tier::text)::int);

      -- 연속 응원: 이 경기·이 팀의 첫 Boost일 때만. 쉬었는지(초기화)는 경기 종료 워커가 판정
      INSERT INTO cheer_streaks AS s (user_id, team_id, current, best, last_match_id)
      VALUES (p_user, p_team, 1, 1, v_match)
      ON CONFLICT (user_id, team_id) DO UPDATE
        SET current = s.current + 1, best = GREATEST(s.best, s.current + 1), last_match_id = v_match
        WHERE s.last_match_id IS DISTINCT FROM v_match
      RETURNING current INTO v_streak;
      IF v_streak IS NOT NULL THEN
        INSERT INTO point_events (user_id, team_id, match_id, moment_id, boost_id, kind, points, currency, dedup_key)
        VALUES (p_user, p_team, v_match, p_moment, v_boost, 'streak',
                LEAST(v_streak * (v_ptcfg->>'streak_step')::int, (v_ptcfg->>'streak_max')::int), p_currency,
                p_user || ':' || v_match || ':' || p_team || ':streak')
        ON CONFLICT (dedup_key) DO NOTHING;
        v_pts := v_pts || jsonb_build_object('streak', LEAST(v_streak * (v_ptcfg->>'streak_step')::int, (v_ptcfg->>'streak_max')::int));
      END IF;
    END IF;
  END IF;

  -- 9) 아웃박스(순위 집계·실시간 카운터·알림)
  INSERT INTO outbox_events (topic, aggregate_id, payload)
  VALUES ('boost.created', v_boost::text, jsonb_build_object(
    'boost_id', v_boost, 'user_id', p_user, 'team_id', p_team, 'moment_id', p_moment,
    'currency', p_currency, 'amount', p_amount, 'client', p_client, 'card_new', v_is_new));

  -- 10) 응답(OpenAPI BoostResult와 같은 모양. star_player_id는 API 계층이 star_player{id,nickname,role,photo_url}로 확장)
  RETURN jsonb_build_object(
    'boost_id', v_boost,
    'replayed', false,
    'balance', (SELECT to_jsonb(b) - 'user_id' FROM v_wallet_balance b WHERE b.user_id = p_user),
    'points_added', v_pts || jsonb_build_object('total',
        COALESCE((v_pts->>'base')::int,0) + COALESCE((v_pts->>'tier')::int,0) + COALESCE((v_pts->>'streak')::int,0)),
    'moment_totals', CASE WHEN p_moment IS NULL THEN NULL ELSE jsonb_build_object(
        'energy', v_tot.energy_total, 'spark', v_tot.spark_total,
        'energy_badge', v_tot.energy_badge, 'spark_badge', v_tot.spark_badge) END,
    'level_up', CASE WHEN v_new_badge > v_prev_badge AND NOT v_is_new
                     THEN jsonb_build_object('currency', p_currency, 'from', v_prev_badge, 'to', v_new_badge) END,
    'card', CASE WHEN v_card.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', v_card.id, 'is_new', v_is_new, 'kind', v_card.kind, 'tier', v_card.tier,
        'team_id', v_card.team_id, 'issued_at', v_card.issued_at,
        'edition', v_card.edition, 'star_player_id', v_card.star_player_id, 'star_rule', v_card.star_rule,
        'celebration_no', v_card.celebration_no, 'serial_no', v_card.serial_no) END
  );
END $$;

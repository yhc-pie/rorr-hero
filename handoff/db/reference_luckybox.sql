-- =====================================================================
-- 참조 구현: 스폰서 행운 박스 열기 (정책 §6-1 B, 논의 중)
-- 작성일: 2026-10-17
-- 규칙: 결과는 서버 난수, 고른 박스 위치와 무관 / 큰 순간 알림당 1회 / 총량 소진 시 미노출
--       홀드아웃 그룹은 박스를 받지 않음(측정용) / 당첨 Spark는 일반 Spark 묶음으로 적립
-- 오류 코드: box_unavailable(조건 불충족·총량 소진·홀드아웃 — 사용자에게 구분해 알리지 않음), minor_restricted
-- 통합(2026-10-17): 확장 sponsor_box_opens 이름·win/miss 결과·rng_seed_ref 채택. API = POST /v1/sponsor/boxes
-- =====================================================================
SET search_path = rorr, public;

CREATE OR REPLACE FUNCTION open_sponsor_box(
  p_user    uuid,
  p_moment  uuid,
  p_client  client_kind,
  p_pick    int,               -- 0~2, 연출 기록용
  p_roll    numeric DEFAULT NULL  -- 테스트용 고정 난수(운영에서는 NULL)
) RETURNS jsonb LANGUAGE plpgsql SET search_path = rorr, public AS $$
DECLARE
  v_now   timestamptz := now();
  v_m     moments%ROWTYPE;
  v_c     sponsor_contracts%ROWTYPE;
  v_prev  sponsor_box_opens%ROWTYPE;
  v_grp   holdout_group;
  v_age   age_band;
  v_roll  numeric := COALESCE(p_roll, random() * 100);
  v_res   box_result;
  v_spark int := 0;
  v_lot   uuid;
  v_id    uuid;
  v_season_end timestamptz;
BEGIN
  -- 이미 연 순간이면 같은 결과
  SELECT * INTO v_prev FROM sponsor_box_opens WHERE user_id = p_user AND moment_id = p_moment;
  IF FOUND THEN
    RETURN jsonb_build_object('open_id', v_prev.id, 'result', v_prev.result, 'prize', CASE WHEN v_prev.spark > 0 THEN jsonb_build_object('spark', v_prev.spark) END, 'replayed', true);
  END IF;

  SELECT age_band INTO v_age FROM users WHERE id = p_user;
  IF v_age <> 'adult' THEN RAISE EXCEPTION 'minor_restricted'; END IF;   -- 법률 확인 전 미성년 미노출(§9)

  SELECT * INTO v_m FROM moments WHERE id = p_moment;
  IF NOT FOUND OR v_m.status NOT IN ('upcoming','open') OR COALESCE(v_m.tier, v_m.tier_hint) = 'silver' THEN
    RAISE EXCEPTION 'box_unavailable';
  END IF;

  -- 적용 캠페인: 파트너 팀·기간·범위(종류·최소 등급)·총량
  SELECT c.* INTO v_c FROM sponsor_contracts c
  WHERE c.is_active AND c.valid @> v_now AND c.team_id = v_m.team_id
    AND EXISTS (SELECT 1 FROM partner_agreements a WHERE a.team_id = c.team_id AND a.valid @> v_now)
    AND (NOT c.scope ? 'kinds' OR c.scope->'kinds' ? v_m.kind::text)
    AND c.pool_spark_used + 10 <= c.pool_spark_total
  ORDER BY lower(c.valid) LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'box_unavailable'; END IF;

  -- 홀드아웃 배정(캠페인당 사용자 고정)
  INSERT INTO sponsor_holdout (contract_id, user_id, grp)
  VALUES (v_c.id, p_user, CASE WHEN (('x' || substr(md5(v_c.id::text || p_user::text),1,8))::bit(32)::bigint % 10000) < v_c.holdout_bp
                               THEN 'holdout' ELSE 'treatment' END::holdout_group)
  ON CONFLICT DO NOTHING;
  SELECT grp INTO v_grp FROM sponsor_holdout WHERE contract_id = v_c.id AND user_id = p_user;
  IF v_grp = 'holdout' THEN RAISE EXCEPTION 'box_unavailable'; END IF;   -- 대조군: 박스 없이 라벨만

  -- 결과: 누적 확률(odds 합 100)
  v_res := CASE
    WHEN v_roll < (v_c.odds->>'none')::numeric THEN 'miss' ELSE 'win' END;
  v_spark := CASE
    WHEN v_roll < (v_c.odds->>'none')::numeric THEN 0
    WHEN v_roll < (v_c.odds->>'none')::numeric + (v_c.odds->>'spark5')::numeric THEN 5
    ELSE 10 END;

  IF v_spark > 0 THEN
    v_season_end := date_trunc('year', v_now) + interval '1 year';   -- 시즌 말(운영값으로 교체)
    INSERT INTO wallet_lots (user_id, currency, kind, source, source_ref, qty, remaining, expires_at)
    VALUES (p_user, 'spark', 'free', 'sponsor_box', v_c.id::text, v_spark, v_spark, v_season_end)
    RETURNING id INTO v_lot;
    INSERT INTO wallet_ledger (user_id, currency, lot_id, delta, reason, ref_type, ref_id, balance_after)
    VALUES (p_user, 'spark', v_lot, v_spark, 'sponsor_box', 'contract', v_c.id::text,
            (SELECT spark FROM v_wallet_balance WHERE user_id = p_user));
    UPDATE sponsor_contracts SET pool_spark_used = pool_spark_used + v_spark WHERE id = v_c.id;
  END IF;

  INSERT INTO sponsor_box_opens (contract_id, user_id, moment_id, odds_version, result, spark, lot_id, client, picked_index, rng_seed_ref)
  VALUES (v_c.id, p_user, p_moment, v_c.odds_version, v_res, v_spark, v_lot, p_client, p_pick,
          'roll:' || round(v_roll, 6) || '@' || v_now)
  RETURNING id INTO v_id;

  INSERT INTO outbox_events (topic, aggregate_id, payload)
  VALUES ('sponsor_box.opened', v_id::text, jsonb_build_object('contract_id', v_c.id, 'user_id', p_user,
          'moment_id', p_moment, 'result', v_res, 'spark', v_spark));

  RETURN jsonb_build_object(
    'open_id', v_id, 'replayed', false, 'result', v_res,
    'prize', CASE WHEN v_spark > 0 THEN jsonb_build_object('spark', v_spark) END,
    'odds', v_c.odds, 'odds_version', v_c.odds_version, 'sponsor_id', v_c.sponsor_id,
    'next', CASE WHEN v_spark > 0
                 THEN jsonb_build_object('currency','spark','amount', v_spark)
                 ELSE jsonb_build_object('currency','energy','amount', 10) END,
    'balance', (SELECT to_jsonb(b) - 'user_id' FROM v_wallet_balance b WHERE b.user_id = p_user));
END $$;

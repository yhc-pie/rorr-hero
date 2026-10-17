-- =====================================================================
-- 참조 구현: 스폰서 행운 박스 열기 (정책 §6-1 B, 논의 중)
-- 작성일: 2026-10-17
-- 규칙: 결과는 서버 난수, 고른 박스 위치와 무관 / 큰 순간 알림당 1회 / 총량 소진 시 미노출
--       홀드아웃 그룹은 박스를 받지 않음(측정용) / 당첨 Spark는 일반 Spark 묶음으로 적립
-- 오류 코드: box_unavailable(조건 불충족·총량 소진), box_holdout, box_minor
-- =====================================================================
SET search_path = rorr, public;

CREATE OR REPLACE FUNCTION open_lucky_box(
  p_user    uuid,
  p_moment  uuid,
  p_client  client_kind,
  p_pick    int,               -- 0~2, 연출 기록용
  p_roll    numeric DEFAULT NULL  -- 테스트용 고정 난수(운영에서는 NULL)
) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_now   timestamptz := now();
  v_m     moments%ROWTYPE;
  v_c     sponsor_campaigns%ROWTYPE;
  v_prev  lucky_box_opens%ROWTYPE;
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
  SELECT * INTO v_prev FROM lucky_box_opens WHERE user_id = p_user AND moment_id = p_moment;
  IF FOUND THEN
    RETURN jsonb_build_object('open_id', v_prev.id, 'result', v_prev.result, 'spark', v_prev.spark, 'replayed', true);
  END IF;

  SELECT age_band INTO v_age FROM users WHERE id = p_user;
  IF v_age <> 'adult' THEN RAISE EXCEPTION 'box_minor'; END IF;   -- 법률 확인 전 미성년 미노출(§9)

  SELECT * INTO v_m FROM moments WHERE id = p_moment;
  IF NOT FOUND OR v_m.status NOT IN ('predicted','open') OR v_m.tier = 'silver' THEN
    RAISE EXCEPTION 'box_unavailable';
  END IF;

  -- 적용 캠페인: 파트너 팀·기간·범위(종류·최소 등급)·총량
  SELECT c.* INTO v_c FROM sponsor_campaigns c
  WHERE c.is_active AND c.valid @> v_now AND c.team_id = v_m.team_id
    AND EXISTS (SELECT 1 FROM partner_agreements a WHERE a.team_id = c.team_id AND a.valid @> v_now)
    AND (NOT c.scope ? 'kinds' OR c.scope->'kinds' ? v_m.kind::text)
    AND c.pool_spark_used + 10 <= c.pool_spark_total
  ORDER BY lower(c.valid) LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'box_unavailable'; END IF;

  -- 홀드아웃 배정(캠페인당 사용자 고정)
  INSERT INTO sponsor_holdout (campaign_id, user_id, grp)
  VALUES (v_c.id, p_user, CASE WHEN (('x' || substr(md5(v_c.id::text || p_user::text),1,8))::bit(32)::bigint % 10000) < v_c.holdout_bp
                               THEN 'holdout' ELSE 'treatment' END::holdout_group)
  ON CONFLICT DO NOTHING;
  SELECT grp INTO v_grp FROM sponsor_holdout WHERE campaign_id = v_c.id AND user_id = p_user;
  IF v_grp = 'holdout' THEN RAISE EXCEPTION 'box_holdout'; END IF;

  -- 결과: 누적 확률(odds 합 100)
  v_res := CASE
    WHEN v_roll < (v_c.odds->>'none')::numeric THEN 'none'
    WHEN v_roll < (v_c.odds->>'none')::numeric + (v_c.odds->>'spark5')::numeric THEN 'spark5'
    ELSE 'spark10' END;
  v_spark := CASE v_res WHEN 'spark5' THEN 5 WHEN 'spark10' THEN 10 ELSE 0 END;

  IF v_spark > 0 THEN
    v_season_end := date_trunc('year', v_now) + interval '1 year';   -- 시즌 말(운영값으로 교체)
    INSERT INTO wallet_lots (user_id, currency, kind, source, source_ref, qty, remaining, expires_at)
    VALUES (p_user, 'spark', 'free', 'lucky_box', v_c.id::text, v_spark, v_spark, v_season_end)
    RETURNING id INTO v_lot;
    INSERT INTO wallet_ledger (user_id, currency, lot_id, delta, reason, ref_type, ref_id, balance_after)
    VALUES (p_user, 'spark', v_lot, v_spark, 'lucky_box', 'campaign', v_c.id::text,
            (SELECT spark FROM v_wallet_balance WHERE user_id = p_user));
    UPDATE sponsor_campaigns SET pool_spark_used = pool_spark_used + v_spark WHERE id = v_c.id;
  END IF;

  INSERT INTO lucky_box_opens (campaign_id, user_id, moment_id, odds_version, result, spark, lot_id, client, picked_index)
  VALUES (v_c.id, p_user, p_moment, v_c.odds_version, v_res, v_spark, v_lot, p_client, p_pick)
  RETURNING id INTO v_id;

  INSERT INTO outbox_events (topic, aggregate_id, payload)
  VALUES ('luckybox.opened', v_id::text, jsonb_build_object('campaign_id', v_c.id, 'user_id', p_user,
          'moment_id', p_moment, 'result', v_res, 'spark', v_spark));

  RETURN jsonb_build_object(
    'open_id', v_id, 'replayed', false, 'result', v_res, 'spark', v_spark,
    'odds', v_c.odds, 'odds_version', v_c.odds_version, 'sponsor_id', v_c.sponsor_id,
    'next', CASE WHEN v_spark > 0
                 THEN jsonb_build_object('currency','spark','amount', v_spark)
                 ELSE jsonb_build_object('currency','energy','amount', 10) END,
    'balance', (SELECT to_jsonb(b) - 'user_id' FROM v_wallet_balance b WHERE b.user_id = p_user));
END $$;

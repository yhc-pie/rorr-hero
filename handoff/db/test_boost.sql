-- =====================================================================
-- Boost 참조 구현 테스트 (schema.sql → reference_boost.sql 적용 후 실행)
-- 실행: psql -v ON_ERROR_STOP=1 -f test_boost.sql   → 마지막 줄 'ALL BOOST TESTS PASSED'
-- =====================================================================
SET search_path = rorr, public;
BEGIN;

-- 기초 데이터 --------------------------------------------------------
INSERT INTO leagues VALUES ('lck','LCK',true);
INSERT INTO teams (id, league_id, name, short_name) VALUES ('T1','lck','T1','T1'),('GEN','lck','Gen.G','GEN');
INSERT INTO players (id, team_id, nickname, role) VALUES
  ('faker','T1','Faker','mid'),('oner','T1','Oner','jungle'),('gumayusi','T1','Gumayusi','bot');
INSERT INTO partner_agreements (team_id, team_share_bp, player_ip_ok, valid)
  VALUES ('T1', 5000, true, tstzrange(now() - interval '30 days', now() + interval '300 days'));  -- 테스트용 임의 비율
INSERT INTO users (id, display_name, age_band, fav_player_id) VALUES
  ('00000000-0000-0000-0000-000000000001','fan1','adult','faker'),
  ('00000000-0000-0000-0000-000000000002','fan2','adult',NULL);
INSERT INTO matches (id, league_id, team_a, team_b, starts_at, status)
  VALUES ('m1','lck','T1','GEN', now() - interval '1 hour','live');
INSERT INTO games (id, match_id, game_no) VALUES ('m1-g1','m1',1);
INSERT INTO moments (id, game_id, moment_key, kind, tier, team_id, label_ko, label_en, status, opens_at, closes_at)
VALUES ('10000000-0000-0000-0000-000000000001','m1-g1','baron-1-24','baron','gold','T1','바론 교전','Baron fight','open', now() - interval '1 min', now() + interval '5 min'),
       ('10000000-0000-0000-0000-000000000002','m1-g1','dragon-1-16','dragon','silver','T1','드래곤','Dragon','resolved', now() - interval '20 min', now() - interval '10 min'),
       ('10000000-0000-0000-0000-000000000003','m1-g1','teamfight-1-30','teamfight','holo','GEN','한타','Teamfight','open', now() - interval '1 min', now() + interval '5 min');
INSERT INTO moment_participants VALUES
  ('10000000-0000-0000-0000-000000000001','oner',9.1,true),
  ('10000000-0000-0000-0000-000000000001','faker',4.2,false);
INSERT INTO milestones (id, player_id, kind, value, unit_ko, unit_en, achieved_on, celebrate_window, source)
VALUES ('20000000-0000-0000-0000-000000000001','faker','career_kills',1500,'킬','kills', current_date, daterange(current_date-3, current_date+4), 'lck_official');
INSERT INTO legal_notice_versions VALUES ('boost_sheet_energy@2026-10-17','boost_sheet_energy','ko','사용 즉시 소진 · 환불 불가 · 수익 일부 T1과 배분', now());

-- 지갑: fan1 = 유료 Energy 120(단가 100) + 보너스 30 + Spark 35 / fan2 = 보너스 Energy 50만
INSERT INTO wallet_lots (user_id, currency, kind, source, qty, remaining, unit_price_krw, list_unit_price_krw, expires_at) VALUES
 ('00000000-0000-0000-0000-000000000001','energy','paid','purchase',120,120,100,100, now() + interval '5 years'),
 ('00000000-0000-0000-0000-000000000001','energy','bonus','promo_bonus',30,30,0,0, now() + interval '1 year'),
 ('00000000-0000-0000-0000-000000000001','spark','free','ad_reward',35,35,0,0, now() + interval '90 days'),
 ('00000000-0000-0000-0000-000000000002','energy','bonus','signup_bonus',50,50,0,0, now() + interval '1 year');

-- 검사 도우미
CREATE FUNCTION pg_temp.expect(cond boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF NOT cond THEN RAISE EXCEPTION 'FAIL: %', label; END IF; RAISE NOTICE 'ok  %', label; END $$;
CREATE FUNCTION pg_temp.expect_error(stmt text, code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE stmt; EXCEPTION WHEN others THEN
    IF SQLERRM = code THEN RAISE NOTICE 'ok  error %', code; RETURN; END IF;
    RAISE EXCEPTION 'FAIL: expected %, got %', code, SQLERRM;
  END;
  RAISE EXCEPTION 'FAIL: expected error %', code;
END $$;

-- T1 첫 Boost: 골드 순간 Energy 10 → 카드 신규, 주인공 = 내 선수 Faker(참여), 포인트 20+30+10
DO $$ DECLARE r jsonb; BEGIN
  r := send_boost('00000000-0000-0000-0000-000000000001','T1',NULL,'10000000-0000-0000-0000-000000000001',NULL,
                  'energy',10,'web','alert','boost_sheet_energy@2026-10-17','k1');
  PERFORM pg_temp.expect((r->'card'->>'is_new')::boolean, 'T1 card issued');
  PERFORM pg_temp.expect(r->'card'->>'star_player_id' = 'faker' AND r->'card'->>'star_rule' = 'fav', 'T1 star = fav participant');
  PERFORM pg_temp.expect((r->'points_added'->>'total')::int = 60, 'T1 points 20+30+10');
  PERFORM pg_temp.expect((r->'balance'->>'energy_paid')::int = 110 AND (r->'balance'->>'energy_bonus')::int = 30, 'T1 paid deducted, bonus untouched');
  PERFORM pg_temp.expect((r->'moment_totals'->>'energy_badge')::int = 1, 'T1 badge 1');
END $$;

-- T2 같은 순간 재Boost Energy 40 → 카드 추가 없음, 포인트 0, 누적 50 → 배지 2, level_up 1→2
DO $$ DECLARE r jsonb; BEGIN
  r := send_boost('00000000-0000-0000-0000-000000000001','T1',NULL,'10000000-0000-0000-0000-000000000001',NULL,
                  'energy',40,'ext','panel','boost_sheet_energy@2026-10-17','k2');
  PERFORM pg_temp.expect(NOT (r->'card'->>'is_new')::boolean, 'T2 no new card');
  PERFORM pg_temp.expect((r->'points_added'->>'total')::int = 0, 'T2 no points on re-boost');
  PERFORM pg_temp.expect((r->'level_up'->>'to')::int = 2, 'T2 level up to 2');
  PERFORM pg_temp.expect((SELECT count(*) FROM cards WHERE user_id='00000000-0000-0000-0000-000000000001') = 1, 'T2 one card per moment');
END $$;

-- T3 같은 순간 Spark 5 → Spark 배지 1(재화별 따로), Energy 배지 유지
DO $$ DECLARE r jsonb; BEGIN
  r := send_boost('00000000-0000-0000-0000-000000000001','T1',NULL,'10000000-0000-0000-0000-000000000001',NULL,
                  'spark',5,'web','lucky_box',NULL,'k3');
  PERFORM pg_temp.expect((r->'moment_totals'->>'spark_badge')::int = 1 AND (r->'moment_totals'->>'energy_badge')::int = 2, 'T3 badges per currency');
END $$;

-- T4 멱등: 같은 키 재전송 → replayed, 차감 없음
DO $$ DECLARE r jsonb; b int; BEGIN
  SELECT energy_paid INTO b FROM v_wallet_balance WHERE user_id='00000000-0000-0000-0000-000000000001';
  r := send_boost('00000000-0000-0000-0000-000000000001','T1',NULL,'10000000-0000-0000-0000-000000000001',NULL,
                  'energy',40,'ext','panel','boost_sheet_energy@2026-10-17','k2');
  PERFORM pg_temp.expect((r->>'replayed')::boolean, 'T4 replayed');
  PERFORM pg_temp.expect((SELECT energy_paid FROM v_wallet_balance WHERE user_id='00000000-0000-0000-0000-000000000001') = b, 'T4 no double charge');
END $$;

-- T5 비제휴 팀 Energy → energy_not_allowed
SELECT pg_temp.expect_error($q$SELECT rorr.send_boost('00000000-0000-0000-0000-000000000001','GEN',NULL,'10000000-0000-0000-0000-000000000003',NULL,'energy',10,'web','panel','boost_sheet_energy@2026-10-17','k5')$q$, 'energy_not_allowed');

-- T6 비제휴 팀 Spark → 허용, RORR 카드(주인공 없음), 홀로그램 포인트 20+60, streak는 팀별(GEN 첫 경기 → +10)
DO $$ DECLARE r jsonb; BEGIN
  r := send_boost('00000000-0000-0000-0000-000000000001','GEN',NULL,'10000000-0000-0000-0000-000000000003',NULL,
                  'spark',5,'web','panel',NULL,'k6');
  PERFORM pg_temp.expect(r->'card'->>'edition' = 'rorr' AND r->'card'->>'star_player_id' IS NULL, 'T6 rorr card without player');
  PERFORM pg_temp.expect((r->'points_added'->>'total')::int = 90, 'T6 points 20+60+10');
END $$;

-- T7 닫힌 순간 → moment_closed
SELECT pg_temp.expect_error($q$SELECT rorr.send_boost('00000000-0000-0000-0000-000000000001','T1',NULL,'10000000-0000-0000-0000-000000000002',NULL,'energy',10,'web','panel','boost_sheet_energy@2026-10-17','k7')$q$, 'moment_closed');

-- T8 보너스 Energy만 있는 사용자 → insufficient_balance(보너스는 Boost 불가, v1.3)
SELECT pg_temp.expect_error($q$SELECT rorr.send_boost('00000000-0000-0000-0000-000000000002','T1',NULL,'10000000-0000-0000-0000-000000000001',NULL,'energy',10,'web','panel','boost_sheet_energy@2026-10-17','k8')$q$, 'insufficient_balance');
SELECT pg_temp.expect((SELECT count(*) FROM boosts WHERE idempotency_key='k8') = 0, 'T8 rolled back');

-- T9 최소 단가 미만 → amount_below_min
SELECT pg_temp.expect_error($q$SELECT rorr.send_boost('00000000-0000-0000-0000-000000000001','T1',NULL,'10000000-0000-0000-0000-000000000001',NULL,'spark',3,'web','panel',NULL,'k9')$q$, 'amount_below_min');

-- T10 Energy인데 고지 버전 없음 → 체크 제약 위반
DO $$ BEGIN
  BEGIN
    PERFORM send_boost('00000000-0000-0000-0000-000000000001','T1',NULL,'10000000-0000-0000-0000-000000000001',NULL,'energy',10,'web','panel',NULL,'k10');
    RAISE EXCEPTION 'FAIL: notice required';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'ok  T10 energy requires notice version';
  END;
END $$;

-- T11 기념 Boost → 기념 에디션(등급 없음), 축하 순번 1. 같은 기념일 재Boost는 카드 추가 없음
INSERT INTO wallet_lots (user_id, currency, kind, source, qty, remaining, expires_at)
VALUES ('00000000-0000-0000-0000-000000000002','spark','free','ad_reward',20,20, now() + interval '90 days');
DO $$ DECLARE r jsonb; BEGIN
  r := send_boost('00000000-0000-0000-0000-000000000002','T1','faker',NULL,'20000000-0000-0000-0000-000000000001','spark',5,'web','milestone',NULL,'k11');
  PERFORM pg_temp.expect(r->'card'->>'kind' = 'commemorative' AND r->'card'->'tier' = 'null'::jsonb, 'T11 commemorative without tier');
  PERFORM pg_temp.expect((r->'card'->>'celebration_no')::int = 1, 'T11 celebration no 1');
  r := send_boost('00000000-0000-0000-0000-000000000002','T1','faker',NULL,'20000000-0000-0000-0000-000000000001','spark',5,'web','milestone',NULL,'k12');
  PERFORM pg_temp.expect(NOT (r->'card'->>'is_new')::boolean, 'T11 one card per milestone');
END $$;

-- T12 원장: append-only
DO $$ BEGIN
  BEGIN UPDATE wallet_ledger SET delta = 1; RAISE EXCEPTION 'FAIL: ledger mutable';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; RAISE NOTICE 'ok  T12 ledger append-only';
  END;
END $$;

-- T13 정산 근거: 유료 사용분만 기록(보너스 0건), 비제휴 Spark는 배분 대상 아님
SELECT pg_temp.expect((SELECT COALESCE(SUM(u.qty),0) FROM boost_lot_usage u JOIN wallet_lots l ON l.id=u.lot_id
                        WHERE l.kind='paid') = 50, 'T13 paid usage 50 (10+40)');
SELECT pg_temp.expect((SELECT count(*) FROM boost_lot_usage u JOIN wallet_lots l ON l.id=u.lot_id WHERE l.kind='bonus') = 0, 'T13 no bonus usage');

-- T14 아웃박스 이벤트 기록
SELECT pg_temp.expect((SELECT count(*) FROM outbox_events WHERE topic='boost.created') = 6, 'T14 outbox events for 6 boosts');

DO $$ BEGIN RAISE NOTICE 'ALL BOOST TESTS PASSED'; END $$;
ROLLBACK;

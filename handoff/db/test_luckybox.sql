-- 행운 박스 참조 구현 테스트 → 마지막 줄 'ALL LUCKY BOX TESTS PASSED'
SET search_path = rorr, public;
BEGIN;
INSERT INTO leagues VALUES ('lck','LCK',true);
INSERT INTO teams (id, league_id, name, short_name) VALUES ('T1','lck','T1','T1'),('GEN','lck','Gen.G','GEN');
INSERT INTO partner_agreements (team_id, team_share_bp, valid) VALUES ('T1', 5000, tstzrange(now()-interval '1 day', now()+interval '1 year'));
INSERT INTO users (id, display_name, age_band, show_in_highlights) VALUES
 ('00000000-0000-0000-0000-00000000000a','a','adult',true),('00000000-0000-0000-0000-00000000000b','b','adult',true),
 ('00000000-0000-0000-0000-00000000000c','c','under19',false);  -- 미성년은 하이라이트 OFF가 제약
INSERT INTO matches (id, league_id, team_a, team_b, starts_at, status) VALUES ('m1','lck','T1','GEN', now(),'live');
INSERT INTO games (id, match_id, game_no) VALUES ('m1-g1','m1',1);
INSERT INTO moments (id, game_id, moment_key, kind, tier, team_id, label_ko, label_en, status) VALUES
 ('30000000-0000-0000-0000-000000000001','m1-g1','baron-1','baron','gold','T1','바론','Baron','predicted'),
 ('30000000-0000-0000-0000-000000000002','m1-g1','dragon-1','dragon','silver','T1','드래곤','Dragon','predicted'),
 ('30000000-0000-0000-0000-000000000003','m1-g1','fight-1','teamfight','gold','GEN','한타','Fight','predicted'),
 ('30000000-0000-0000-0000-000000000004','m1-g1','baron-2','baron','holo','T1','바론2','Baron2','predicted');
INSERT INTO sponsors (id, name) VALUES ('nova','NOVA Gear');
INSERT INTO sponsor_campaigns (id, sponsor_id, team_id, scope, odds, odds_version, pool_spark_total, holdout_bp, valid)
VALUES ('40000000-0000-0000-0000-000000000001','nova','T1','{"kinds":["baron","teamfight"]}','{"none":75,"spark5":20,"spark10":5}','odds@2026-10-17', 15, 0,
        tstzrange(now()-interval '1 day', now()+interval '30 days'));

CREATE FUNCTION pg_temp.expect(cond boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF NOT cond THEN RAISE EXCEPTION 'FAIL: %', label; END IF; RAISE NOTICE 'ok  %', label; END $$;
CREATE FUNCTION pg_temp.err(stmt text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE stmt; EXCEPTION WHEN others THEN RETURN SQLERRM; END; RETURN 'no error'; END $$;

DO $$ DECLARE r jsonb; BEGIN
  -- roll 80 → spark5(75 이상 95 미만), 다음 행동 = Spark 5 Boost
  r := open_lucky_box('00000000-0000-0000-0000-00000000000a','30000000-0000-0000-0000-000000000001','web',1,80);
  PERFORM pg_temp.expect(r->>'result'='spark5' AND (r->'balance'->>'spark')::int=5 AND r->'next'->>'currency'='spark', 'win spark5 → wallet + spark CTA');
  -- 같은 순간 다시 열기 → 같은 결과(replayed)
  r := open_lucky_box('00000000-0000-0000-0000-00000000000a','30000000-0000-0000-0000-000000000001','ext',0,1);
  PERFORM pg_temp.expect((r->>'replayed')::boolean AND r->>'result'='spark5', 'one box per moment');
  -- roll 10 → 꽝, 다음 행동 = Energy 10 Boost
  r := open_lucky_box('00000000-0000-0000-0000-00000000000b','30000000-0000-0000-0000-000000000001','web',2,10);
  PERFORM pg_temp.expect(r->>'result'='none' AND r->'next'->>'currency'='energy', 'miss → energy CTA');
  -- roll 99 → spark10, 총량 15 중 15 사용
  r := open_lucky_box('00000000-0000-0000-0000-00000000000b','30000000-0000-0000-0000-000000000004','web',0,99);
  PERFORM pg_temp.expect(r->>'result'='spark10', 'win spark10');
  PERFORM pg_temp.expect((SELECT pool_spark_used FROM sponsor_campaigns)=15, 'pool counts spark');
END $$;
-- 총량 소진(남은 0 < 10) → box_unavailable
SELECT pg_temp.expect(pg_temp.err($q$SELECT rorr.open_lucky_box('00000000-0000-0000-0000-00000000000a','30000000-0000-0000-0000-000000000004','web',0,1)$q$)='box_unavailable', 'pool exhausted → unavailable');
-- 실버 순간·비제휴 팀 순간 → unavailable, 미성년 → box_minor
SELECT pg_temp.expect(pg_temp.err($q$SELECT rorr.open_lucky_box('00000000-0000-0000-0000-00000000000b','30000000-0000-0000-0000-000000000002','web',0,1)$q$)='box_unavailable', 'silver moment → unavailable');
SELECT pg_temp.expect(pg_temp.err($q$SELECT rorr.open_lucky_box('00000000-0000-0000-0000-00000000000b','30000000-0000-0000-0000-000000000003','web',0,1)$q$)='box_unavailable', 'non-partner moment → unavailable');
SELECT pg_temp.expect(pg_temp.err($q$SELECT rorr.open_lucky_box('00000000-0000-0000-0000-00000000000c','30000000-0000-0000-0000-000000000001','web',0,1)$q$)='box_minor', 'minor → box_minor');
-- 홀드아웃 100% 캠페인 → box_holdout
UPDATE sponsor_campaigns SET holdout_bp = 5000, pool_spark_total = 100;
DELETE FROM sponsor_holdout;
DO $$ DECLARE n int := 0; h int := 0; e text; i int; BEGIN
  FOR i IN 1..40 LOOP
    INSERT INTO users (id, display_name, age_band) VALUES (gen_random_uuid(), 'u'||i, 'adult');
  END LOOP;
  FOR e IN SELECT pg_temp.err(format('SELECT rorr.open_lucky_box(%L,%L,''web'',0,1)', u.id, '30000000-0000-0000-0000-000000000001'))
           FROM users u WHERE display_name LIKE 'u%' LOOP
    n := n + 1; IF e = 'box_holdout' THEN h := h + 1; END IF;
  END LOOP;
  PERFORM pg_temp.expect(h > 5 AND h < 35, format('holdout ~50%% assigned (%s/%s)', h, n));
END $$;
DO $$ BEGIN RAISE NOTICE 'ALL LUCKY BOX TESTS PASSED'; END $$;
ROLLBACK;

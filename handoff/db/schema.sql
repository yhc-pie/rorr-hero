-- =====================================================================
-- RORR 서비스 DB 스키마 (PostgreSQL 16)
-- 작성일: 2026-10-17 · 근거: 정책 v1.3, 서비스 플로우 v2(2026-10-15), docs/specs/refund.md
-- 범위: 서비스 DB(계정·재화·Boost·카드·순위·메시지·광고·스폰서·결제·정산·퀴즈)
--       경기 원천 데이터(Timescale 하이퍼테이블·Neo4j)는 RORR Datacenter에 있으며
--       여기에는 서비스가 쓰는 경기·순간 요약만 둔다(datacenter → 수집 워커가 적재)
-- 원칙
--   1) 재화는 원장(wallet_ledger, append-only)으로만 변경. 잔액 = 묶음(wallet_lots.remaining) 합
--   2) 중복 방지는 유니크 제약으로(카드·포인트·행운 박스·멱등 키)
--   3) 정책 판정값(에디션·배분율·확률표)은 "발급·결제 시점 값"을 행에 복사해 저장
--   4) 팀 배분율은 partner_agreements에만. 클라이언트 응답에 내보내지 않는다
--   5) 미정 값은 app_config에서 읽는다(코드 고정 금지)
-- 검증: PostgreSQL 16.13에서 전체 실행 확인(handoff/13-data-model.md §6)
-- 통합: 2026-10-17 웹(df84cfb)·확장(rorr-extension 6e9eca4) 설계를 이 파일 하나로 통합(handoff/18-canonical-merge.md)
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()

CREATE SCHEMA IF NOT EXISTS rorr;
SET search_path = rorr, public;

-- ---------------------------------------------------------------------
-- 0. 열거형
-- ---------------------------------------------------------------------
CREATE TYPE client_kind      AS ENUM ('web','ext','admin','system');
CREATE TYPE age_band         AS ENUM ('under14','under19','adult','unknown');
CREATE TYPE alert_level      AS ENUM ('all','holo','off');
CREATE TYPE auth_provider    AS ENUM ('google','apple','microsoft','email');
CREATE TYPE match_status     AS ENUM ('scheduled','live','finished','cancelled');
CREATE TYPE moment_kind      AS ENUM ('dragon','baron','elder','herald','teamfight','siege','nexus','steal','comeback','other');
CREATE TYPE moment_tier      AS ENUM ('silver','gold','holo');
CREATE TYPE moment_status    AS ENUM ('upcoming','open','resolved','closed','cancelled');
CREATE TYPE milestone_kind   AS ENUM ('career_games','career_kills','debut_anniversary','other');
CREATE TYPE currency_kind    AS ENUM ('energy','spark');
CREATE TYPE lot_kind         AS ENUM ('paid','bonus','free');           -- free = Spark
CREATE TYPE lot_source       AS ENUM ('purchase','signup_bonus','promo_bonus','ad_reward','quiz_prize','sponsor_box','admin_grant');
CREATE TYPE lot_status       AS ENUM ('active','depleted','refund_locked','refunded','expired','cancelled');
CREATE TYPE ledger_reason    AS ENUM ('purchase','bonus','ad_reward','quiz_prize','sponsor_box','boost','boost_hold','boost_release','deco_purchase','refund','expire','cancel','adjust');
CREATE TYPE boost_target     AS ENUM ('team','player');
CREATE TYPE boost_entry      AS ENUM ('panel','alert','player_chip','sponsor_box','milestone','recap','other');
CREATE TYPE boost_status     AS ENUM ('pending','settled','voided','rejected');   -- BOOST_SETTLE_MODE
CREATE TYPE star_reason      AS ENUM ('fav_in_play','fav_not_in_play','auto','non_partner','milestone');
CREATE TYPE card_kind        AS ENUM ('moment','commemorative');
CREATE TYPE card_edition     AS ENUM ('partner','rorr');
CREATE TYPE point_kind       AS ENUM ('base','tier','streak');
CREATE TYPE msg_status       AS ENUM ('pending','visible','hidden','rejected');
CREATE TYPE report_status    AS ENUM ('open','actioned','dismissed');
CREATE TYPE rank_period      AS ENUM ('season','month','week','match');
CREATE TYPE rank_criterion   AS ENUM ('points','cards','streak','big_moments','spark_points');
CREATE TYPE order_status     AS ENUM ('created','paid','failed','cancelled','partially_refunded','refunded');
CREATE TYPE refund_type      AS ENUM ('withdrawal','balance','minor_cancel','service_end','company_fault');
CREATE TYPE refund_method    AS ENUM ('pg_cancel','bank_transfer');
CREATE TYPE refund_status    AS ENUM ('requested','approved','processing','done','rejected');
CREATE TYPE settle_status    AS ENUM ('draft','calculated','team_confirmed','paid','adjusted');
CREATE TYPE box_result       AS ENUM ('win','miss');
CREATE TYPE holdout_group    AS ENUM ('treatment','holdout');
CREATE TYPE inbox_category   AS ENUM ('service','mine','team','promo');
CREATE TYPE sender_kind      AS ENUM ('rorr','team');
CREATE TYPE consent_category AS ENUM ('team_news','promo','promo_night','match_start');
CREATE TYPE channel_kind     AS ENUM ('inbox','email','web_push','ext_notification','ics');
CREATE TYPE quiz_status      AS ENUM ('open','closed','resolved','void');
CREATE TYPE deco_kind        AS ENUM ('team','rorr');

-- ---------------------------------------------------------------------
-- 1. 설정 (정책 §8 미정 값 — 코드 고정 금지)
-- ---------------------------------------------------------------------
CREATE TABLE app_config (
  key         text PRIMARY KEY,
  value       jsonb NOT NULL,
  note        text,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  text
);

-- ---------------------------------------------------------------------
-- 2. 계정
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email                citext UNIQUE,
  display_name         text NOT NULL,
  avatar_url           text,
  locale               text NOT NULL DEFAULT 'ko' CHECK (locale IN ('ko','en')),
  age_band             age_band NOT NULL DEFAULT 'unknown',
  guardian_consent_at  timestamptz,                         -- 만 14세 미만 법정대리인 동의
  is_anonymous         boolean NOT NULL DEFAULT false,      -- 순위·메시지 익명
  show_in_highlights   boolean NOT NULL DEFAULT true,       -- 미성년 기본 false(앱에서 설정)
  msg_public           boolean NOT NULL DEFAULT true,
  alert_level          alert_level NOT NULL DEFAULT 'all',
  created_at           timestamptz NOT NULL DEFAULT now(),
  deleted_at           timestamptz,                         -- 삭제 요청(유예 후 파기)
  CONSTRAINT minor_highlight CHECK (age_band = 'adult' OR show_in_highlights = false OR age_band = 'unknown')
);

CREATE TABLE auth_identities (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider    auth_provider NOT NULL,
  subject     text NOT NULL,
  linked_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (provider, subject)
);
CREATE INDEX ON auth_identities (user_id);

CREATE TABLE sessions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client              client_kind NOT NULL,
  device_label        text,
  refresh_token_hash  bytea NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  last_seen_at        timestamptz NOT NULL DEFAULT now(),
  revoked_at          timestamptz
);
CREATE INDEX ON sessions (user_id) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------
-- 3. 리그·팀·선수·협약
-- ---------------------------------------------------------------------
CREATE TABLE leagues (
  id          text PRIMARY KEY,                -- 'lck'
  name        text NOT NULL,
  is_enabled  boolean NOT NULL DEFAULT false   -- false = '준비 중'(알림 신청만)
);

CREATE TABLE teams (
  id          text PRIMARY KEY,                -- 'T1','GEN'
  league_id   text NOT NULL REFERENCES leagues(id),
  name        text NOT NULL,
  short_name  text NOT NULL,
  logo_asset  text,                            -- 파트너만 사용(협약 범위)
  color_hex   text
);

CREATE TABLE players (
  id           text PRIMARY KEY,               -- 'faker'
  team_id      text REFERENCES teams(id),
  nickname     text NOT NULL,
  role         text NOT NULL CHECK (role IN ('top','jungle','mid','bot','support')),
  photo_asset  text,                           -- 구단 제공 공식 파일만
  is_active    boolean NOT NULL DEFAULT true
);

-- 협약: 기간 중복 금지. 배분율은 서버 정산 전용(대외 비공개)
CREATE TABLE partner_agreements (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id                text NOT NULL REFERENCES teams(id),
  team_share_bp          int  NOT NULL CHECK (team_share_bp BETWEEN 0 AND 10000),
  rate_disclosure_ok     boolean NOT NULL DEFAULT false,   -- 팀이 비율 공개에 동의했나
  official_wording_ok    boolean NOT NULL DEFAULT false,   -- "공식" 표현 허용
  player_ip_ok           boolean NOT NULL DEFAULT false,   -- 닉네임·사진 사용
  survival_clause        boolean NOT NULL DEFAULT false,   -- 파트너 에디션 존속 조항(§4-1)
  valid                  tstzrange NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  EXCLUDE USING gist (team_id WITH =, valid WITH &&)
);

CREATE TABLE user_teams (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  team_id     text NOT NULL REFERENCES teams(id),
  is_primary  boolean NOT NULL DEFAULT false,               -- 대표 팀(§5-2)
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, team_id)
);
CREATE UNIQUE INDEX user_one_primary_team ON user_teams (user_id) WHERE is_primary;

-- 확장 '내 선수'(카드 주인공 우선): 팀별. 행 없음 = 아직 안 물음, player_id NULL = 자동
CREATE TABLE user_my_players (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  team_id     text NOT NULL REFERENCES teams(id),
  player_id   text REFERENCES players(id),
  asked_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, team_id)
);

-- 웹 ★ 즐겨찾기 선수 — '내 선수'와 별개
CREATE TABLE user_favorite_players (
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  player_id   text NOT NULL REFERENCES players(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, player_id)
);

-- ---------------------------------------------------------------------
-- 4. 경기·세트·순간·기념일 (datacenter → 수집 워커 적재)
-- ---------------------------------------------------------------------
CREATE TABLE matches (
  id            text PRIMARY KEY,               -- 'lck-2026-10-15-t1-gen'
  league_id     text NOT NULL REFERENCES leagues(id),
  team_a        text NOT NULL REFERENCES teams(id),
  team_b        text NOT NULL REFERENCES teams(id),
  best_of       int  NOT NULL DEFAULT 3,
  starts_at     timestamptz NOT NULL,
  status        match_status NOT NULL DEFAULT 'scheduled',
  score_a       int NOT NULL DEFAULT 0,
  score_b       int NOT NULL DEFAULT 0,
  source_ref    text,                          -- datacenter 경기 ID(조인키 계약 필요)
  CHECK (team_a <> team_b)
);
CREATE INDEX ON matches (starts_at);
CREATE INDEX ON matches (status) WHERE status = 'live';

CREATE TABLE games (
  id            text PRIMARY KEY,               -- match_id || '-g' || game_no
  match_id      text NOT NULL REFERENCES matches(id),
  game_no       int  NOT NULL,
  started_at    timestamptz,
  ended_at      timestamptz,
  winner_team   text REFERENCES teams(id),
  source_ref    text,
  UNIQUE (match_id, game_no)
);

CREATE TABLE match_lineups (
  match_id    text NOT NULL REFERENCES matches(id),
  game_no     int  NOT NULL,
  team_id     text NOT NULL REFERENCES teams(id),
  player_id   text NOT NULL REFERENCES players(id),
  role        text NOT NULL CHECK (role IN ('top','jungle','mid','bot','support')),
  PRIMARY KEY (match_id, game_no, player_id)
);

-- 확장 중계 매칭(/v1/ext/match/resolve)
CREATE TABLE broadcasts (
  id           bigserial PRIMARY KEY,
  match_id     text NOT NULL REFERENCES matches(id),
  host         text NOT NULL CHECK (host IN ('youtube','chzzk','soop','twitch')),
  channel_id   text,
  url_pattern  text,
  default_offset_ms int NOT NULL DEFAULT 0,
  UNIQUE (match_id, host, channel_id)
);

-- 익명 지연 보정 보고(사용자 ID 미저장, 90일 보관)
CREATE TABLE stream_offset_reports (
  id          bigserial PRIMARY KEY,
  host        text NOT NULL,
  match_id    text NOT NULL REFERENCES matches(id),
  delta_ms    int NOT NULL,
  reported_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE moments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id       text NOT NULL REFERENCES games(id),
  moment_key    text NOT NULL,                  -- 'baron-2-24' (게임 안 고유)
  kind          moment_kind NOT NULL,
  tier_hint     moment_tier NOT NULL,           -- 예고 시 예상 등급(알림 종류 결정)
  tier          moment_tier,                    -- 확정 등급(resolved). 카드·포인트는 Boost 시점 값으로 고정(BE-2)
  team_id       text REFERENCES teams(id),      -- 순간을 만든 팀(승률이 움직인 쪽)
  game_sec      int,                            -- 게임 시각(초)
  label_ko      text NOT NULL,
  label_en      text NOT NULL,
  wp_before     numeric(5,2),
  wp_after      numeric(5,2),
  winprob_delta_pp numeric(5,2),
  status        moment_status NOT NULL DEFAULT 'upcoming',
  alert_eta_at  timestamptz,                    -- 예고 시각(카운트다운 기준)
  opens_at      timestamptz,                    -- Boost 창 열림
  closes_at     timestamptz,                    -- Boost 창 닫힘(누적 종료)
  resolved_at   timestamptz,
  cancel_reason text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (game_id, moment_key),
  CHECK (closes_at IS NULL OR opens_at IS NULL OR closes_at > opens_at)
);
CREATE INDEX ON moments (game_id, status);

CREATE TABLE moment_participants (
  moment_id     uuid NOT NULL REFERENCES moments(id) ON DELETE CASCADE,
  player_id     text NOT NULL REFERENCES players(id),
  contribution  numeric(8,3),                   -- wGE+/LwRC+ 기여도(정렬용)
  is_top        boolean NOT NULL DEFAULT false, -- 카드 주인공 기본값
  PRIMARY KEY (moment_id, player_id)
);
CREATE UNIQUE INDEX one_top_per_moment ON moment_participants (moment_id) WHERE is_top;

CREATE TABLE milestones (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id     text NOT NULL REFERENCES players(id),
  kind          milestone_kind NOT NULL,
  value         int NOT NULL,                   -- 1500 (통산 킬)
  unit_ko       text NOT NULL,
  unit_en       text NOT NULL,
  achieved_on   date NOT NULL,
  celebrate_window daterange NOT NULL,           -- 달성일 ±MS_WINDOW_DAYS
  game_id       text REFERENCES games(id),      -- 경기 기록이면 달성 경기
  source        text NOT NULL,                  -- 'lck_official' | 'rorr_aggregate'
  celebrations  int NOT NULL DEFAULT 0,         -- 축하 순번 발급 카운터
  UNIQUE (player_id, kind, value)
);

-- ---------------------------------------------------------------------
-- 5. 재화: 상품·주문·묶음·원장
-- ---------------------------------------------------------------------
CREATE TABLE energy_packages (
  id               text PRIMARY KEY,            -- 'e100'
  qty              int  NOT NULL CHECK (qty > 0),
  list_price_krw   int  NOT NULL,               -- 정가(정산 기준)
  discount_bp      int  NOT NULL DEFAULT 0 CHECK (discount_bp BETWEEN 0 AND 1000), -- 상한 10%
  price_krw        int  GENERATED ALWAYS AS (list_price_krw - (list_price_krw * discount_bp / 10000)) STORED,
  is_active        boolean NOT NULL DEFAULT true
);

CREATE TABLE energy_orders (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id),
  package_id       text NOT NULL REFERENCES energy_packages(id),
  qty              int  NOT NULL,
  amount_krw       int  NOT NULL,               -- 실결제
  list_amount_krw  int  NOT NULL,               -- 정가 환산(정산 기준)
  status           order_status NOT NULL DEFAULT 'created',
  pg_provider      text NOT NULL DEFAULT 'toss',
  pg_payment_key   text UNIQUE,
  paid_at          timestamptz,
  withdrawal_until timestamptz,                 -- paid_at + REFUND_WINDOW_DAYS
  idempotency_key  text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key)
);

-- 묶음: 결제 1건·보너스 1건·Spark 지급 1건 = 1행. 차감은 묶음 단위
CREATE TABLE wallet_lots (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid NOT NULL REFERENCES users(id),
  currency             currency_kind NOT NULL,
  kind                 lot_kind NOT NULL,
  source               lot_source NOT NULL,
  source_ref           text,                    -- order_id / ad token / quiz week / box id
  qty                  int NOT NULL CHECK (qty > 0),
  remaining            int NOT NULL CHECK (remaining >= 0),
  unit_price_krw       numeric(12,4) NOT NULL DEFAULT 0,  -- 실결제 단가(환불 기준)
  list_unit_price_krw  numeric(12,4) NOT NULL DEFAULT 0,  -- 정가 단가(정산 기준, v1.3)
  status               lot_status NOT NULL DEFAULT 'active',
  refund_lock_id       uuid,                    -- 환불 처리 중 잠금
  acquired_at          timestamptz NOT NULL DEFAULT now(),
  expires_at           timestamptz NOT NULL,    -- 유료 5년·보너스 1년·Spark 시즌 말
  CHECK (remaining <= qty),
  CHECK ((currency = 'energy' AND kind IN ('paid','bonus')) OR (currency = 'spark' AND kind = 'free')),
  CHECK (kind = 'paid' OR unit_price_krw = 0)
);
CREATE INDEX wallet_lots_spend ON wallet_lots (user_id, currency, kind, expires_at) WHERE status = 'active' AND remaining > 0;

-- append-only 원장
CREATE TABLE wallet_ledger (
  id             bigserial PRIMARY KEY,
  user_id        uuid NOT NULL REFERENCES users(id),
  currency       currency_kind NOT NULL,
  lot_id         uuid REFERENCES wallet_lots(id),
  delta          int NOT NULL CHECK (delta <> 0),
  reason         ledger_reason NOT NULL,
  ref_type       text,                          -- 'boost' | 'order' | 'refund' ...
  ref_id         text,
  balance_after  int NOT NULL,                  -- 해당 재화(유료+보너스 또는 Spark) 합
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON wallet_ledger (user_id, created_at DESC);

CREATE FUNCTION forbid_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION '% is append-only', TG_TABLE_NAME; END $$;
CREATE TRIGGER wallet_ledger_append_only BEFORE UPDATE OR DELETE ON wallet_ledger
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();

-- 잔액 뷰: 유료·보너스·Spark 분리(§1 UI 규칙)
CREATE VIEW v_wallet_balance AS
SELECT u.id AS user_id,
  COALESCE(SUM(l.remaining) FILTER (WHERE l.currency='energy' AND l.kind='paid'  AND l.status='active' AND l.expires_at > now()),0)::int AS energy_paid,
  COALESCE(SUM(l.remaining) FILTER (WHERE l.currency='energy' AND l.kind='bonus' AND l.status='active' AND l.expires_at > now()),0)::int AS energy_bonus,
  COALESCE(SUM(l.remaining) FILTER (WHERE l.currency='spark'                     AND l.status='active' AND l.expires_at > now()),0)::int AS spark
FROM users u LEFT JOIN wallet_lots l ON l.user_id = u.id
GROUP BY u.id;

-- ---------------------------------------------------------------------
-- 6. Boost·누적·카드·포인트
-- ---------------------------------------------------------------------
CREATE TABLE disclosures (                       -- 고지 문구 버전(환불 불가·보너스 용도·행운 박스 확률)
  id            text PRIMARY KEY,               -- 'boost_no_refund@2026-10-17'
  disclosure_key text NOT NULL,
  locale        text NOT NULL,
  body          text NOT NULL,
  effective_at  timestamptz NOT NULL
);

CREATE TABLE boosts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id),
  match_id         text REFERENCES matches(id),
  moment_id        uuid REFERENCES moments(id),      -- NULL = 순간 미선택 Boost
  milestone_id     uuid REFERENCES milestones(id),   -- 기념 Boost
  target           boost_target NOT NULL,
  team_id          text NOT NULL REFERENCES teams(id),  -- 응원(적립) 팀
  player_id        text REFERENCES players(id),         -- 선수 대상일 때
  currency         currency_kind NOT NULL,
  amount           int NOT NULL CHECK (amount > 0),
  is_partner       boolean NOT NULL,                     -- 판정 시점 값 복사
  status           boost_status NOT NULL DEFAULT 'settled', -- immediate=settled / on_moment=pending→settled|voided
  game_clock_s     int,                                  -- 게임 시각(초)
  client           client_kind NOT NULL,
  client_version   text,
  entry            boost_entry NOT NULL DEFAULT 'panel',
  disclosure_version text REFERENCES disclosures(id),    -- 노출된 고지(§1-2)
  disclosure_shown_at timestamptz,
  idempotency_key  text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  settled_at       timestamptz,
  void_reason      text,
  UNIQUE (user_id, idempotency_key),
  CHECK (NOT (moment_id IS NOT NULL AND milestone_id IS NOT NULL)),
  CHECK (target = 'team' OR player_id IS NOT NULL),
  CHECK (currency = 'spark' OR is_partner),                    -- 비제휴 + Energy 금지(§2)
  CHECK (currency = 'spark' OR disclosure_version IS NOT NULL) -- Energy는 고지 기록 필수
);
CREATE INDEX ON boosts (moment_id);
CREATE INDEX ON boosts (user_id, created_at DESC);

-- 어느 묶음에서 얼마를 썼나 → 정산 근거(유료만 배분)
CREATE TABLE boost_lot_usage (
  boost_id             uuid NOT NULL REFERENCES boosts(id),
  lot_id               uuid NOT NULL REFERENCES wallet_lots(id),
  qty                  int NOT NULL CHECK (qty > 0),
  unit_price_krw       numeric(12,4) NOT NULL,
  list_unit_price_krw  numeric(12,4) NOT NULL,
  PRIMARY KEY (boost_id, lot_id)
);

-- 같은 순간 누적(재화별) → 배지 단계(§4)
CREATE TABLE moment_totals (
  user_id       uuid NOT NULL REFERENCES users(id),
  moment_id     uuid NOT NULL REFERENCES moments(id),
  team_id       text NOT NULL REFERENCES teams(id),
  energy_total  int NOT NULL DEFAULT 0,
  spark_total   int NOT NULL DEFAULT 0,
  energy_badge  smallint NOT NULL DEFAULT 0 CHECK (energy_badge BETWEEN 0 AND 3),
  spark_badge   smallint NOT NULL DEFAULT 0 CHECK (spark_badge BETWEEN 0 AND 3),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, moment_id)
);

CREATE TABLE cards (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id),
  kind             card_kind NOT NULL,
  moment_id        uuid REFERENCES moments(id),
  milestone_id     uuid REFERENCES milestones(id),
  first_boost_id   uuid NOT NULL REFERENCES boosts(id),
  team_id          text NOT NULL REFERENCES teams(id),
  tier             moment_tier,                         -- 기념 에디션은 NULL(등급 없음)
  edition          card_edition NOT NULL,               -- 발급 시점 협약으로 고정(§4-1)
  star_player_id   text REFERENCES players(id),         -- 카드 주인공(파트너만)
  star_reason      star_reason,
  celebration_no   int,                                 -- 기념 에디션 "N번째 축하"
  serial_no        bigint GENERATED ALWAYS AS IDENTITY,
  issued_client    client_kind NOT NULL,
  issued_at        timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind='moment' AND moment_id IS NOT NULL AND milestone_id IS NULL AND tier IS NOT NULL)
      OR (kind='commemorative' AND milestone_id IS NOT NULL AND moment_id IS NULL AND tier IS NULL AND celebration_no IS NOT NULL)),
  CHECK (edition = 'partner' OR star_player_id IS NULL)  -- 비제휴 카드에 선수 금지
);
CREATE UNIQUE INDEX one_card_per_moment    ON cards (user_id, moment_id)    WHERE moment_id IS NOT NULL;
CREATE UNIQUE INDEX one_card_per_milestone ON cards (user_id, milestone_id) WHERE milestone_id IS NOT NULL;

-- 카드 배지는 moment_totals 조인으로 표시(컬렉션은 순간 종료 후 최종 단계)
CREATE VIEW v_card_with_badges AS
SELECT c.*, COALESCE(t.energy_badge,0) AS energy_badge, COALESCE(t.spark_badge,0) AS spark_badge,
       COALESCE(t.energy_total,0) AS energy_total, COALESCE(t.spark_total,0) AS spark_total
FROM cards c LEFT JOIN moment_totals t ON t.user_id = c.user_id AND t.moment_id = c.moment_id;

CREATE TABLE point_events (
  id          bigserial PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id),
  team_id     text NOT NULL REFERENCES teams(id),
  match_id    text REFERENCES matches(id),
  moment_id   uuid REFERENCES moments(id),
  boost_id    uuid REFERENCES boosts(id),
  kind        point_kind NOT NULL,
  points      int NOT NULL CHECK (points > 0),
  currency    currency_kind NOT NULL,          -- 비제휴 Spark 팬 순위 집계용
  dedup_key   text NOT NULL UNIQUE,            -- base/tier: user:moment / streak: user:match:team
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON point_events (team_id, user_id);

CREATE TABLE cheer_streaks (
  user_id        uuid NOT NULL REFERENCES users(id),
  team_id        text NOT NULL REFERENCES teams(id),
  current        int NOT NULL DEFAULT 0,
  best           int NOT NULL DEFAULT 0,
  last_match_id  text REFERENCES matches(id),
  PRIMARY KEY (user_id, team_id)
);

-- ---------------------------------------------------------------------
-- 7. 응원 메시지·반응·신고
-- ---------------------------------------------------------------------
CREATE TABLE cheer_messages (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  boost_id     uuid UNIQUE REFERENCES boosts(id),
  user_id      uuid NOT NULL REFERENCES users(id),
  team_id      text NOT NULL REFERENCES teams(id),
  moment_id    uuid REFERENCES moments(id),
  milestone_id uuid REFERENCES milestones(id),     -- 응원 롤 수록 대상
  player_id    text REFERENCES players(id),
  match_id     text REFERENCES matches(id),
  body         text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 80),  -- 상한 결정 대기(D-9: 웹 80 / 확장 60)
  is_anonymous boolean NOT NULL DEFAULT false,
  status       msg_status NOT NULL DEFAULT 'pending',
  moderated_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON cheer_messages (team_id, created_at DESC) WHERE status = 'visible';

CREATE TABLE message_reactions (
  message_id  uuid NOT NULL REFERENCES cheer_messages(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)                 -- '나도 응원' 1회
);

CREATE TABLE message_replies (
  id          bigserial PRIMARY KEY,
  message_id  uuid NOT NULL REFERENCES cheer_messages(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id),
  chip_id     text NOT NULL CHECK (chip_id IN ('gg','next_match','best_moment','till_end')), -- 칩만 허용
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id, chip_id)
);

CREATE TABLE message_reports (
  id           bigserial PRIMARY KEY,
  message_id   uuid NOT NULL REFERENCES cheer_messages(id),
  reporter_id  uuid NOT NULL REFERENCES users(id),
  reason       text NOT NULL,
  status       report_status NOT NULL DEFAULT 'open',
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, reporter_id)
);

-- ---------------------------------------------------------------------
-- 8. 순위 스냅샷
-- ---------------------------------------------------------------------
CREATE TABLE ranking_snapshots (
  team_id      text NOT NULL REFERENCES teams(id),
  period       rank_period NOT NULL,
  period_key   text NOT NULL,                    -- '2026' | '2026-10' | '2026-W42' | match_id
  criterion    rank_criterion NOT NULL,
  computed_at  timestamptz NOT NULL,
  rank         int NOT NULL,
  user_id      uuid NOT NULL REFERENCES users(id),
  value        int NOT NULL,
  delta        int,
  PRIMARY KEY (team_id, period, period_key, criterion, computed_at, rank)
);
CREATE INDEX ranking_me ON ranking_snapshots (team_id, period, period_key, criterion, computed_at, user_id);

-- ---------------------------------------------------------------------
-- 9. 광고 월(웹 보상형)
-- ---------------------------------------------------------------------
CREATE TABLE ad_sessions (
  token        text PRIMARY KEY,                 -- 1회용
  user_id      uuid NOT NULL REFERENCES users(id),
  issued_at    timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  used_at      timestamptz,
  granted      boolean,
  spark        int,
  ip_hash      bytea
);
CREATE INDEX ON ad_sessions (user_id, issued_at DESC);

-- ---------------------------------------------------------------------
-- 10. 스폰서·행운 박스(§6-1 B, 논의 중)
-- ---------------------------------------------------------------------
CREATE TABLE sponsors (
  id          text PRIMARY KEY,
  name        text NOT NULL,
  mark_asset  text,
  blocked_categories text[] NOT NULL DEFAULT '{}'
);

CREATE TABLE sponsor_contracts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sponsor_id        text NOT NULL REFERENCES sponsors(id),
  team_id           text NOT NULL REFERENCES teams(id),          -- 파트너 팀만(앱 검증)
  scope             jsonb NOT NULL,                              -- {"match_ids":[],"kinds":["baron"],"min_tier":"gold"}
  odds              jsonb NOT NULL,                              -- {"none":75,"spark5":20,"spark10":5}
  odds_version      text NOT NULL,
  pool_spark_total  int NOT NULL CHECK (pool_spark_total >= 0),
  pool_spark_used   int NOT NULL DEFAULT 0,
  holdout_bp        int NOT NULL DEFAULT 1000 CHECK (holdout_bp BETWEEN 0 AND 5000),
  min_tier          moment_tier NOT NULL DEFAULT 'gold',
  kill_drop_bp      int,                                         -- SPONSOR_BOX_KILL_DROP
  valid             tstzrange NOT NULL,
  is_active         boolean NOT NULL DEFAULT true,
  CHECK (pool_spark_used <= pool_spark_total)
);

CREATE TABLE sponsor_moment_exposures (       -- 순간에 후원 라벨이 붙었는지(노출 판정 결과)
  moment_id    uuid PRIMARY KEY REFERENCES moments(id),
  contract_id  uuid NOT NULL REFERENCES sponsor_contracts(id),
  box_enabled  boolean NOT NULL,
  decided_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sponsor_holdout (
  contract_id  uuid NOT NULL REFERENCES sponsor_contracts(id),
  user_id      uuid NOT NULL REFERENCES users(id),
  grp          holdout_group NOT NULL,
  assigned_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (contract_id, user_id)
);

CREATE TABLE sponsor_box_opens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id   uuid NOT NULL REFERENCES sponsor_contracts(id),
  user_id       uuid NOT NULL REFERENCES users(id),
  moment_id     uuid NOT NULL REFERENCES moments(id),
  odds_version  text NOT NULL,
  result        box_result NOT NULL,
  spark         int NOT NULL DEFAULT 0,
  lot_id        uuid REFERENCES wallet_lots(id),
  client        client_kind NOT NULL,
  picked_index  smallint CHECK (picked_index BETWEEN 0 AND 2),   -- 연출용 기록(결과와 무관, 선택)
  rng_seed_ref  text NOT NULL,                                   -- 서버 난수 감사 기록
  opened_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, moment_id),                                   -- 큰 순간 알림당 1회
  CHECK ((result='miss' AND spark=0) OR (result='win' AND spark IN (5,10)))
);

-- ---------------------------------------------------------------------
-- 11. 알림 노출 기록(빈도 상한·측정)
-- ---------------------------------------------------------------------
CREATE TABLE headsup_impressions (
  id            bigserial PRIMARY KEY,
  user_id       uuid REFERENCES users(id),       -- 비로그인은 NULL + anon_id
  anon_id       text,
  moment_id     uuid NOT NULL REFERENCES moments(id),
  tier          moment_tier NOT NULL,
  client        client_kind NOT NULL,
  shown_at      timestamptz NOT NULL DEFAULT now(),
  clicked_at    timestamptz,
  dismissed_at  timestamptz,
  moment_cancelled boolean NOT NULL DEFAULT false,
  sponsor_contract_id uuid REFERENCES sponsor_contracts(id)
);
CREATE INDEX ON headsup_impressions (user_id, shown_at DESC);

-- ---------------------------------------------------------------------
-- 12. 메시지 발송(알림함)·수신 동의(§5-5·§5-7)
-- ---------------------------------------------------------------------
CREATE TABLE consent_records (
  id            bigserial PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES users(id),
  category      consent_category NOT NULL,
  channel       channel_kind NOT NULL,
  granted       boolean NOT NULL,                -- 동의/철회
  text_version  text NOT NULL,
  recorded_at   timestamptz NOT NULL DEFAULT now(),
  reconfirm_due date                             -- 2년 재확인
);
CREATE INDEX ON consent_records (user_id, category, channel, recorded_at DESC);

CREATE VIEW v_current_consent AS
SELECT DISTINCT ON (user_id, category, channel) user_id, category, channel, granted, recorded_at, reconfirm_due
FROM consent_records ORDER BY user_id, category, channel, recorded_at DESC;

CREATE TABLE match_alert_subscriptions (
  user_id     uuid NOT NULL REFERENCES users(id),
  team_id     text NOT NULL REFERENCES teams(id),
  channel     channel_kind NOT NULL CHECK (channel IN ('ext_notification','web_push','ics')),
  paused_until timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, team_id)                 -- 한 사용자 한 채널
);

CREATE TABLE inbox_messages (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category        inbox_category NOT NULL,
  sender          sender_kind NOT NULL,
  sender_team_id  text REFERENCES teams(id),
  is_ad           boolean NOT NULL,
  title_ko        text NOT NULL,
  title_en        text NOT NULL,
  body_ko         text NOT NULL,
  body_en         text NOT NULL,
  audience_rule   jsonb NOT NULL,                -- 응원 활동 기준만(결제 기준 금지 — 앱 검증)
  audience_size   int,
  requested_by    text NOT NULL,
  reviewed_by     text,
  version         int NOT NULL DEFAULT 1,
  scheduled_at    timestamptz,
  sent_at         timestamptz,
  CHECK (sender = 'rorr' OR sender_team_id IS NOT NULL),
  CHECK (NOT is_ad OR title_ko LIKE '(광고)%'),
  CHECK (category <> 'service' OR NOT is_ad)
);

CREATE TABLE inbox_deliveries (
  message_id  uuid NOT NULL REFERENCES inbox_messages(id),
  user_id     uuid NOT NULL REFERENCES users(id),
  delivered_at timestamptz NOT NULL DEFAULT now(),
  read_at     timestamptz,
  PRIMARY KEY (message_id, user_id)
);
CREATE INDEX ON inbox_deliveries (user_id, delivered_at DESC);

CREATE TABLE muse_lines (                        -- 서하 대사 세그먼트 캐시(/v1/ext/muse/lines)
  id          bigserial PRIMARY KEY,
  segment     text NOT NULL CHECK (segment IN ('pre','live','between','post')),
  trigger_key text NOT NULL,
  team_mode   text NOT NULL DEFAULT 'neutral',
  lang        text NOT NULL CHECK (lang IN ('ko','en')),
  body        text NOT NULL,
  version     int NOT NULL,
  UNIQUE (segment, trigger_key, team_mode, lang, version)
);

-- 측정 이벤트 수신(POST /v1/events) → DW 적재 전 버퍼(user_id는 가명 키)
CREATE TABLE analytics_events_buffer (
  id          bigserial PRIMARY KEY,
  pseudo_user text,
  client      client_kind NOT NULL,
  name        text NOT NULL,
  props       jsonb NOT NULL DEFAULT '{}',
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 13. 환불·정산
-- ---------------------------------------------------------------------
CREATE TABLE refunds (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id),
  type             refund_type NOT NULL,
  lot_ids          uuid[] NOT NULL,
  gross_krw        int NOT NULL CHECK (gross_krw >= 0),
  fee_krw          int NOT NULL CHECK (fee_krw >= 0),
  net_krw          int GENERATED ALWAYS AS (gross_krw - fee_krw) STORED,
  method           refund_method NOT NULL,
  status           refund_status NOT NULL DEFAULT 'requested',
  idempotency_key  text NOT NULL,
  reason           text,
  requested_at     timestamptz NOT NULL DEFAULT now(),
  done_at          timestamptz,
  UNIQUE (user_id, idempotency_key),
  CHECK (gross_krw > fee_krw)
);
ALTER TABLE wallet_lots ADD CONSTRAINT wallet_lots_refund_fk FOREIGN KEY (refund_lock_id) REFERENCES refunds(id);

CREATE TABLE settlements (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id          text NOT NULL REFERENCES teams(id),
  agreement_id     uuid NOT NULL REFERENCES partner_agreements(id),
  period_month     date NOT NULL CHECK (date_trunc('month', period_month) = period_month),
  gross_list_krw   bigint NOT NULL,              -- Σ 유료 사용분 × 정가 단가
  team_share_krw   bigint NOT NULL,
  adjust_krw       bigint NOT NULL DEFAULT 0,    -- 정산 후 취소분(음수)
  status           settle_status NOT NULL DEFAULT 'draft',
  team_confirmed_at timestamptz,                 -- 분기 공동 확인(§2-1)
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (team_id, period_month)
);

-- 시즌 누적 배분액 공개용(월 1회 갱신, §2-1) — 집계값만, 비율 비노출
CREATE VIEW v_team_share_disclosure AS
SELECT team_id, date_trunc('year', period_month)::date AS season,
       SUM(team_share_krw + adjust_krw) AS shared_krw, MAX(created_at) AS updated_at
FROM settlements WHERE status IN ('team_confirmed','paid','adjusted')
GROUP BY team_id, date_trunc('year', period_month);

-- ---------------------------------------------------------------------
-- 14. 확장 전용: 퀴즈 스트릭(§5-6)
-- ---------------------------------------------------------------------
CREATE TABLE quiz_questions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id     text NOT NULL REFERENCES games(id),
  prompt_ko   text NOT NULL,
  prompt_en   text NOT NULL,
  options     jsonb NOT NULL,                    -- [{"id":"a","ko":"T1","en":"T1"},{"id":"b",...}]
  opens_at    timestamptz NOT NULL,
  closes_at   timestamptz NOT NULL,              -- 서버 시각, 어느 중계에도 결과 노출 전
  answer      text,
  status      quiz_status NOT NULL DEFAULT 'open',
  CHECK (closes_at > opens_at),
  CHECK (jsonb_array_length(options) = 2)
);

CREATE TABLE quiz_answers (
  question_id  uuid NOT NULL REFERENCES quiz_questions(id),
  user_id      uuid NOT NULL REFERENCES users(id),
  choice       text NOT NULL,
  answered_at  timestamptz NOT NULL DEFAULT now(),
  is_correct   boolean,
  points       int,
  PRIMARY KEY (question_id, user_id)
);

CREATE TABLE quiz_streaks (
  user_id       uuid PRIMARY KEY REFERENCES users(id),
  current       int NOT NULL DEFAULT 0,
  season_best   int NOT NULL DEFAULT 0,
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE quiz_weekly_results (
  week_key     text NOT NULL,                    -- LCK 주 단위 '2026-W42'
  user_id      uuid NOT NULL REFERENCES users(id),
  points       int NOT NULL,
  best_streak  int NOT NULL,
  reached_at   timestamptz NOT NULL,             -- 동점 처리 ② 먼저 도달
  rank         int NOT NULL,
  prize_spark  int NOT NULL DEFAULT 0,
  lot_id       uuid REFERENCES wallet_lots(id),
  PRIMARY KEY (week_key, user_id)
);

-- ---------------------------------------------------------------------
-- 15. 유료 장식(§2-2, 출시 순서: RORR 장식 1종 → 팀 장식 1종)
-- ---------------------------------------------------------------------
CREATE TABLE deco_items (
  id            text PRIMARY KEY,
  kind          deco_kind NOT NULL,
  team_id       text REFERENCES teams(id),
  name_ko       text NOT NULL,
  name_en       text NOT NULL,
  price_energy  int NOT NULL CHECK (price_energy > 0),
  sale_label    text,                            -- '2026 시즌 판매'(희소성 표현 금지)
  is_active     boolean NOT NULL DEFAULT false,
  CHECK ((kind = 'team') = (team_id IS NOT NULL))
);

CREATE TABLE deco_purchases (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id),
  item_id          text NOT NULL REFERENCES deco_items(id),
  energy_paid      int NOT NULL DEFAULT 0,
  energy_bonus     int NOT NULL DEFAULT 0,       -- RORR 장식만 >0 가능(앱·트리거 검증)
  idempotency_key  text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, item_id),
  UNIQUE (user_id, idempotency_key)
);

-- ---------------------------------------------------------------------
-- 16. 미들티어 지원: 멱등 키·아웃박스·감사
-- ---------------------------------------------------------------------
CREATE TABLE idempotency_keys (
  user_id       uuid NOT NULL,
  key           text NOT NULL,
  route         text NOT NULL,
  request_hash  bytea NOT NULL,
  status_code   int,
  response      jsonb,
  locked_until  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key)
);

CREATE TABLE outbox_events (
  id            bigserial PRIMARY KEY,
  topic         text NOT NULL,                   -- 'boost.created','card.issued','moment.upcoming' ...
  aggregate_id  text NOT NULL,
  payload       jsonb NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  published_at  timestamptz
);
CREATE INDEX outbox_unpublished ON outbox_events (id) WHERE published_at IS NULL;

CREATE TABLE admin_audit (
  id          bigserial PRIMARY KEY,
  actor       text NOT NULL,
  action      text NOT NULL,
  target      text NOT NULL,
  before      jsonb,
  after       jsonb,
  at          timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 17. 정책 보조 트리거
-- ---------------------------------------------------------------------
-- 비제휴 팀 Energy Boost 차단(is_partner 값을 서버가 협약으로 다시 확인)
CREATE FUNCTION check_boost_partner() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE partner boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM partner_agreements a
                 WHERE a.team_id = NEW.team_id AND a.valid @> NEW.created_at) INTO partner;
  IF NEW.is_partner IS DISTINCT FROM partner THEN
    RAISE EXCEPTION 'is_partner mismatch for team % at %', NEW.team_id, NEW.created_at;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER boosts_partner_check BEFORE INSERT ON boosts
  FOR EACH ROW EXECUTE FUNCTION check_boost_partner();

-- Boost에는 유료 Energy·Spark만(v1.3 §1-1 안 C: 보너스 Energy는 RORR 장식 전용)
CREATE FUNCTION check_boost_lot_kind() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k lot_kind;
BEGIN
  SELECT kind INTO k FROM wallet_lots WHERE id = NEW.lot_id;
  IF k = 'bonus' THEN RAISE EXCEPTION 'bonus energy cannot be used for boosts'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER boost_lot_usage_kind BEFORE INSERT ON boost_lot_usage
  FOR EACH ROW EXECUTE FUNCTION check_boost_lot_kind();

-- 배지 단계 계산(설정값은 app_config 'badge_thresholds')
CREATE FUNCTION badge_level(total int, cur currency_kind) RETURNS smallint LANGUAGE sql STABLE SET search_path = rorr, public AS $$
  SELECT CASE
    WHEN total >= (SELECT value::text::int FROM app_config WHERE key = 'BADGE_' || upper(cur::text) || '_L3') THEN 3
    WHEN total >= (SELECT value::text::int FROM app_config WHERE key = 'BADGE_' || upper(cur::text) || '_L2') THEN 2
    WHEN total >= (SELECT value::text::int FROM app_config WHERE key = 'BADGE_' || upper(cur::text) || '_L1') THEN 1
    ELSE 0 END::smallint
$$;

-- ---------------------------------------------------------------------
-- 18. 초기 설정값(정책 §8 현재값 — 운영에서 변경)
-- ---------------------------------------------------------------------
INSERT INTO app_config (key, value, note) VALUES
 -- 응답 GET /v1/config 의 키 = 이 표의 key (정책 §8 이름, 평면)
 ('min_ext_version',          '"2.0.0"', '구버전 확장 차단'),
 ('flags',                    '{"sponsor_moment_enabled":false,"partner_official_label":false,"fav_player_star":true}', '기능 플래그'),
 ('BOOST_SETTLE_MODE',        '"immediate"', 'OI-13 결정 전 기본. on_moment = 202 pending → SSE boost.settled/voided'),
 ('STEP_ENERGY',              '[10,50,100,500]', '허용 금액(이 값만)'),
 ('STEP_SPARK',               '[5,10,20,50]', '허용 금액(이 값만)'),
 ('BADGE_ENERGY_L1',          '10',  '1단계 = 최소 단가'),
 ('BADGE_ENERGY_L2',          '50',  '§8 1차값'),
 ('BADGE_ENERGY_L3',          '100', '§8 1차값'),
 ('BADGE_SPARK_L1',           '5',   '1단계 = 최소 단가'),
 ('BADGE_SPARK_L2',           '20',  '§8 1차값'),
 ('BADGE_SPARK_L3',           '50',  '§8 1차값 = 하루 광고 한도'),
 ('POINTS_BASE',              '20',  '§5-3'),
 ('POINTS_TIER',              '{"silver":10,"gold":30,"holo":60}', '§5-3'),
 ('POINTS_STREAK_STEP',       '10',  '§5-3 — 첫 경기 0, 2경기째 +10 (BE-1 2026-10-17)'),
 ('POINTS_STREAK_MAX',        '100', '§5-3'),
 ('BOOST_CONFIRM_WINDOW_MS',  '5000', '두 번 누르기'),
 ('HEADSUP_COUNTDOWN_S',      '40',  '큰 순간 알림 카운트다운'),
 ('HEADSUP_GOLD_MIN_GAP',     '180', '웹 골드 배너 간격(초)'),
 ('HEADSUP_WEB_MAX_PER_VISIT','3',   '웹 방문당'),
 ('EXT_HEADSUP_MIN_GAP',      '90',  '확장(제안, 실측 후)'),
 ('BOOST_GRACE_MS',           '0',   'BE-4 마감 직후 여유(지연 실측 후)'),
 ('QUIZ_WINDOW_S',            '12',  '퀴즈 응답 시간'),
 ('QUIZ_GRACE_MS',            '0',   '지연 실측 후'),
 ('QUIZ_PRIZE',               '{"top_n":10,"pool":30,"table":[8,5,4,3,3,2,2,1,1,1]}', '§5-6'),
 ('MOMENT_TIER_GOLD_PP',      '12',  '승률 변화 %p'),
 ('MOMENT_TIER_HOLO_PP',      '30',  '승률 변화 %p'),
 ('SPARK_PER_AD',             '5',   '§6 임시'),
 ('AD_DAILY_LIMIT',           '10',  '§6'),
 ('SPONSOR_BOX_ODDS',         '[[0,75],[5,20],[10,5]]', '§6-1 B 임시 [spark, %]'),
 ('REFUND',                   '{"window_days":7,"fee_rate":0.05,"fee_min_krw":1000,"sla_business_days":3}', '§1-1 임시'),
 ('EXPIRY',                   '{"paid_years":5,"bonus_days":365,"spark":"season_end"}', '§1-1'),
 ('BONUS_ENERGY_SCOPE',       '"rorr_deco"', 'v1.3 안 C'),
 ('MS_WINDOW_DAYS',           '3',   '§4-2'),
 ('MESSAGE_MAX_CHARS',        '80',  'D-9 결정 대기(확장 60)'),
 ('MESSAGING',                '{"team_weekly_cap":1,"promo_weekly_cap":2,"daily_cap":3,"min_audience":50,"night":["21:00","08:00"]}', '§5-7 제안'),
 ('PARTNER_ENERGY_SHARE_FLOOR','0.20', 'v1.3 §6-1 제안');

# 실시간 이벤트 계약 (SSE) — 웹·확장 공용

- 작성일: 2026-10-17 · 통합: 웹(df84cfb)·확장(rorr-extension 6e9eca4) 이벤트 정의를 하나로 합침(이름은 확장 정의 채택, `handoff/18-canonical-merge.md`)
- 엔드포인트: `GET /v1/stream?match_ids=m1,m2` — 비로그인은 **경기 채널**만, 로그인하면 **사용자 채널**이 자동 합류
- 형식: `id`(단조 증가) · `event` · `data`(JSON 한 줄). 모든 `data`에 `server_ts`
- 하트비트: 15초 `event: ping`. 30초 무수신 시 클라이언트 재연결
- 재연결: `Last-Event-ID` → 최근 5분 재전송. 그 이상이면 `event: resync` → 클라이언트가 REST로 현재 상태 재조회(`/v1/matches/{id}`, `/v1/matches/{id}/moments?status=open`, `/v1/me/wallet`)
- 표시 시각: 결과형 이벤트는 `server_ts + offset_ms`(확장 지연 보정), 예고형(`moment.upcoming`, `quiz.opened`)은 즉시
- 확장: 패널이 열려 있는 동안만 연결. 닫히면 서비스 워커가 1분 간격 `GET /v1/matches/{id}/moments?status=open`으로 아이콘 배지만 표시(정책 §5-4 푸시 금지)

---

## 1. 이벤트 목록

| event | 채널 | 주요 필드 | 웹 | 확장 |
|---|---|---|---|---|
| `ping` | 공통 | `server_ts` | 연결 유지 | 같음 |
| `resync` | 공통 | `reason` | 상태 재조회 | 같음 |
| `config.changed` | 공통 | `keys[]` | `/v1/config` 재조회 | 같음 |
| `match.state` | 경기 | `match_id, game_no, clock_s, score[2], gold_diff` (5초·변화 시) | 티커·경기 페이지 | 매치 스트립 |
| `match.started` / `match.ended` | 경기 | `match_id, result?` | 경기 페이지 상태 | S3·S4·S1 전환 |
| `game.started` / `game.ended` | 경기 | `game_no, winner?` | 세트 표시 | 세트 사이 화면 |
| `moment.upcoming` | 경기 | `moment_id, kind, label{ko,en}, team_id, tier_hint, eta_at, closes_at, participants[], top_performer, sponsor?` | 골드 배너 / 홀로그램 팝업 | 예고 줄(카운트다운 `HEADSUP_COUNTDOWN_S`) |
| `moment.open` | 경기 | `moment_id, opens_at, closes_at` | "지금 이 순간" 칩·선수 칩 | Boost CTA 활성 |
| `moment.stats` | 경기 | `moment_id, boosters_count` (2초 묶음) | "함께 Boost 중 n" | 같음 |
| `moment.resolved` | 경기 | `moment_id, final_tier, outcome, top_performer, winprob_delta_pp, label` | 확정 라벨 | 순간 플래시 + 서하 hype |
| `moment.closed` | 경기 | `moment_id, closed_at` | 순간 칩 해제·두 번 누르기 해제 | 같음 |
| `moment.cancelled` | 경기 | `moment_id, reason` | 예고 조용히 철회 | 같음(`on_moment` 모드면 `boost.voided`가 뒤따름) |
| `sponsor.pool` | 경기 | `contract_id, box_enabled` | 박스 버튼 숨김/표시(라벨 유지) | 같음 |
| `message.new` | 경기 | `message{…}` (검수 통과분) | 팬덤 라이브·응원 피드 | 리캡 |
| `quiz.opened` | 경기 | `quiz_id, prompt{ko,en}, options[2], closes_at` | — | 퀴즈 카드 `QUIZ_WINDOW_S` |
| `quiz.resolved` | 경기 + 사용자 | `quiz_id, correct_option, my?{correct, streak, score}` | — | 정답·스트릭 |
| `quiz.void` | 경기 | `quiz_id` | — | "This one happened too fast. It won't count." |
| `boost.settled` | 사용자 | `boost_id, card{…}, points_added` (`on_moment` 모드) | 카드 공개 | 같음 |
| `boost.voided` | 사용자 | `boost_id, reason` | "순간이 성립하지 않아 돌려드렸어요" | 같음 |
| `wallet.changed` | 사용자 | `balance{energy_paid, energy_bonus, spark}, reason` | 헤더 잔액 | 패널 잔액(웹 충전 즉시 반영) |
| `card.updated` | 사용자 | `card_id, tier?, badges?` | 컬렉션 갱신 | 같음 |

## 2. 예시

```text
event: moment.upcoming
id: 1729150000123-42
data: {"server_ts":"2026-10-15T08:24:00Z","match_id":"lck-2026-10-15-t1-gen","game_no":2,
       "moment_id":"5b1e…","kind":"baron","tier_hint":"gold","team_id":"T1",
       "label":{"ko":"바론 교전 임박","en":"Baron fight incoming"},
       "eta_at":"2026-10-15T08:24:38Z","closes_at":"2026-10-15T08:26:10Z",
       "participants":["oner","faker","keria"],"top_performer":"faker",
       "sponsor":{"sponsor_id":"nova","label":{"ko":"후원 · presented by NOVA Gear","en":"Sponsored · presented by NOVA Gear"},
                  "box_enabled":true,"odds":[[0,75],[5,20],[10,5]],"odds_version":"odds@2026-10-17"}}

event: moment.resolved
data: {"server_ts":"…","moment_id":"5b1e…","final_tier":"gold","outcome":"secured","team_id":"T1","top_performer":"oner",
       "label":{"ko":"T1 바론 스틸","en":"BARON STOLEN — T1"},"winprob_delta_pp":26.8,"game_time":"24:10"}

event: wallet.changed
data: {"server_ts":"…","balance":{"energy_paid":120,"energy_bonus":0,"spark":35},"reason":"purchase"}
```

| 필드 | 규칙 |
|---|---|
| `tier_hint` | `gold` → 배너·예고 줄, `holo` → 중앙 팝업. `silver`는 알림 없음. 확정 등급은 `moment.resolved.final_tier` |
| `participants` | 파트너 팀 선수만. 비제휴 팀이면 빈 배열, 라벨에 선수명 없음 |
| `sponsor` | 파트너 경기·계약 범위일 때만. 대조군 사용자에게는 `box_enabled:false`로 보냄(사용자 채널 덮어쓰기) |
| `eta_at` | 카운트다운 기준. 클라이언트 시계 오차는 `server_ts`로 보정 |

## 3. 클라이언트 처리 규칙

| 규칙 | 내용 |
|---|---|
| 빈도 상한 | 웹 `HEADSUP_GOLD_MIN_GAP`(180초)·방문당 3회·홀로그램 경기당 1회 / 확장 `EXT_HEADSUP_MIN_GAP`. 노출은 `POST /v1/headsup/impressions`로 기록 |
| 모달 겹침 | 결제·Boost 완료·로그인·행운 박스 무대가 열려 있으면 보류 → 닫힌 뒤 `eta_at`이 남아 있으면 표시 |
| 설정 | `alert_level=holo`면 골드 무시, `off`면 전부 무시 |
| 탭 신호(웹) | 탭이 숨겨져 있으면 제목 앞 "(⚡ 곧 바론)" + 파비콘 점 |
| 아이콘 배지(확장) | 패널 닫힘 시 `chrome.action.setBadgeText` |
| 순서 | 같은 `moment_id`는 `upcoming → open → resolved|cancelled → closed`. 역순 도착 시 `id` 기준 정렬, 같은 `id` 재수신 무시 |

## 4. 서버 측 발행

- 원천: 순간 감지 워커 → `moments` 갱신 + `outbox_events`(`moment.*`) / Boost·지갑 트랜잭션 → `outbox_events`(`boost.*`, `wallet.changed`)
- 팬아웃: 아웃박스 퍼블리셔 → Redis Pub/Sub `live:{match_id}`(경기) · `user:{user_id}`(사용자) → 실시간 게이트웨이 → 클라이언트
- `moment.stats`: `boost.created`를 2초 창으로 집계(개인 식별 정보 없음)
- 재전송 버퍼: 채널별 Redis Stream(최근 5분)

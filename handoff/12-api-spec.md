# 12. API 정의 — 웹·확장 공용 단일 기준

- 작성일: 2026-10-17 · 통합: 2026-10-17(웹 df84cfb + 확장 rorr-extension 6e9eca4 → 이 문서 하나. 결정 근거 [18-canonical-merge](18-canonical-merge.md))
- 계약 원본: [`api/openapi.yaml`](api/openapi.yaml)(OpenAPI 3.1, 54개 오퍼레이션, `openapi-spec-validator` 통과, 참조 구현 응답이 `BoostResult`·`SponsorBoxResult` 스키마와 일치) · 실시간: [`api/realtime-events.md`](api/realtime-events.md)
- 확장 저장소의 `handoff/api/openapi.yaml`·`09-api-spec.md`는 **참고용으로 대체됨** — 구현은 이 문서 기준
- 이전 초안: 서비스 플로우 v2(2026-10-15) → 대체

---

## 1. 웹·확장이 쓰는 API 구분

- 계정·지갑·Boost·카드·순위·메시지·실시간은 **같은 API**. 각 오퍼레이션의 `x-clients`가 구분 기준(both 32 · web 13 · ext 9)

| 구분 | API | 이유 |
|---|---|---|
| **확장 전용**(9) | `POST /ext/match/resolve` 중계 탭 → 경기 매칭 | 웹은 중계를 보여 주지 않음 |
| | `POST /ext/offset-reports` 익명 지연 보정값 보고 | 중계 화면과 패널 동기화 |
| | `GET /ext/muse/lines` 서하 대사 묶음 | 서하는 확장의 메인 캐릭터 |
| | `POST /ext/muse/chat` 서하 1:1 대화(경기 맥락 첨부, 스트리밍) | 웹은 일반 Ask. 과금 방식 결정 대기(EXT-2) |
| | `GET /quiz/current` · `POST /quiz/{id}/answers` 퀴즈 스트릭 | 참여는 확장 전용(웹은 순위 열람만) |
| | `PUT /me/my-player` 팀별 '내 선수'(카드 주인공) | 웹 미적용 규칙 |
| | `POST /auth/ext/token` · `POST /auth/ext/refresh` | 웹은 쿠키 세션 |
| **웹 전용**(13) | 충전(`/energy/packages`, `/energy/orders`, `/payments/toss/*`), 환불(`/me/refund-quote`, `/refunds`), 광고 월(`/ads/rewarded/*`), 알림함 목록·읽음, 수신 동의, 카드 이미지 저장 | 확장은 rorr.club 링크로 보냄(정책 §1-2). 확장은 미읽음 수만 `GET /me`에서 |
| **공용**(32) | `/config`, `/me`, `/me/preferences`, `/me/teams`, `/me/wallet`(+ledger), `/matches`, `/moments/{id}`, `/boost-context`, `/boosts`, `/me/boosts`, `/sponsor/boxes`, `/headsup/impressions`, `/me/cards`, `/cards/{id}`, `/me/points`, `/teams/{id}/rankings`, `/teams/{id}/fandom`, `/messages`(+반응·답장·신고), `/me/match-alerts`, `/players/{id}/milestones`, `/quiz/ranking`, `/stream`, `/events`, `/auth/logout` | |

- 공용이지만 쓰는 방식이 다른 것: `/stream`(확장은 패널 열림 동안만 연결), `/me/match-alerts`(확장은 `ext_notification` 채널), `/messages`(확장은 리캡에서만 표시)

## 2. 공통 규약

| 항목 | 규칙 |
|---|---|
| 기본 경로 | `https://api.rorr.club/v1` — 하위 호환이 깨지면 `/v2` |
| 형식 | JSON(UTF-8), 시각 ISO 8601 UTC, 날짜 `YYYY-MM-DD`, 원화는 `_krw` 정수, Energy·Spark는 개수 |
| 인증 | 웹: HttpOnly 쿠키 `rorr_sid` + 상태 변경 시 `X-CSRF-Token` / 확장: `Authorization: Bearer`(액세스 15분, 리프레시 30일). 같은 계정 |
| 클라이언트 | `X-RORR-Client: web/1.4.2` · `ext/2.0.0` 필수 — 채널 기록·최소 버전 판정(미달 403 `client_outdated`) |
| 정책 변수 | `GET /v1/config`(평면 키, 5분 캐시, 변경 시 SSE `config.changed`). 화면은 이 값을 읽고 하드코딩하지 않음 |
| 멱등 | 금액이 오가는 POST(`/boosts`, `/sponsor/boxes`, `/energy/orders`, `/refunds`)는 `Idempotency-Key`(UUIDv4) 필수, 그 외 변경 요청은 권장. 24시간 보관, 같은 키·같은 본문 → 첫 응답 재반환, 같은 키·다른 본문 → 422 `idempotency_mismatch` |
| 오류 | `{"error":{"code","message_key","params","message?","request_id"}}` — 화면 문구는 `message_key`+`params`로 i18n(서버는 문장을 조합하지 않음) |
| 페이지 | 커서 `?cursor=&limit=`(기본 20, 최대 100) → `{items, next_cursor}` |
| 추적 | 응답 헤더 `X-Request-Id` |

## 3. 화면 → API 매핑

| 화면 | 호출 순서 |
|---|---|
| 앱 시작 | `GET /config` → `GET /me`(로그인 시) → `GET /matches?status=live` → `GET /stream?match_ids=…` |
| 팀·선수 패널 응원 탭(웹) / Boost 시트(확장) | `GET /boost-context?team_id&player_id&moment_id` 하나로 그림 — 또는 `/config` + `GET /moments/{id}`(my 블록) + `/me/wallet` 조합(확장 기존 방식). 결과는 같음 |
| Boost 두 번째 누름 | `POST /boosts` → 201(즉시 확정) 또는 202(`BOOST_SETTLE_MODE=on_moment`, SSE `boost.settled`/`boost.voided`) |
| 큰 순간 알림 | SSE `moment.upcoming` → 표시 → `POST /headsup/impressions{shown}` → 클릭 `{clicked}` |
| 행운 박스 | 후원 줄 → `POST /sponsor/boxes{moment_id}` → 결과 `next`로 Boost 상자 사전 선택 |
| 기념할 순간 | `GET /players/{id}/milestones` → `GET /boost-context?milestone_id` → `POST /boosts{milestone_id}` |
| 컬렉션 | `GET /me/cards` → `GET /cards/{id}` → (웹) `GET /cards/{id}/image` |
| Energy 충전(웹) | `GET /energy/packages` → `POST /energy/orders{return_to}` → 토스 → `POST /payments/toss/confirm` → 복귀. 확장은 SSE `wallet.changed`로 즉시 반영 |
| 환불(웹) | `GET /me/wallet` → `GET /me/refund-quote` → `POST /refunds` |
| 광고 월(웹) | `POST /ads/rewarded/session` → GAM → `POST /ads/rewarded/grant` |
| 알림함·동의(웹) | `GET /me/inbox` · `GET/PUT /me/consents` · `PUT /me/match-alerts` |
| 확장: 중계 탭 감지 | `POST /ext/match/resolve` → `/stream` 구독 → 보정 1탭 → `POST /ext/offset-reports` |
| 확장: 퀴즈 | SSE `quiz.opened` → `POST /quiz/{id}/answers{option_id}` → SSE `quiz.resolved` |
| 확장: 내 선수 | 경기 시작 카드 → `PUT /me/my-player{team_id, player_id|null}` |
| 측정 | `POST /events`(묶음 최대 50건) |

## 4. 핵심 오퍼레이션

### 4-1. `GET /v1/boost-context`

- Boost 상자 렌더용 **서버 집계**: `is_partner`, `allowed_currencies`, `steps`, `balance`(유료·보너스·Spark 분리), `moment`, `my_moment`(누적·배지·`to_next`·카드 보유), `star_preview`, `disclosures`(버전 포함 고지), `share_line`(비율 없음), `sponsor`
- 캐시: 순간 열림 5초 / 그 외 30초, SSE `moment.closed`·`wallet.changed`로 무효화

### 4-2. `POST /v1/boosts`

```json
// 요청
{ "team_id":"T1", "target_player_id":"faker", "moment_id":"5b1e…", "currency":"energy", "amount":10,
  "message":"오늘도 응원해", "client":"web", "entry":"player_chip",
  "disclosure_version":"boost_no_refund@2026-10-17" }
// 201 응답 (첫 경기 → 연속 보너스 0)
{ "boost_id":"b_8f2c", "status":"settled", "replayed":false,
  "balance":{"energy_paid":110,"energy_bonus":30,"spark":35},
  "points_added":{"base":20,"tier":30,"streak":0,"total":50},
  "moment_totals":{"energy":10,"spark":0,"energy_badge":1,"spark_badge":0,"to_next":{"energy":40,"spark":5}},
  "level_up":null,
  "card":{"id":"c_19ad","is_new":true,"kind":"moment","tier":"gold","edition":"partner","team_id":"T1",
          "star_player":{"id":"faker","nickname":"Faker","role":"mid"},"star_reason":"fav_in_play","serial_no":4127},
  "message":{"id":"msg_1","status":"pending"}, "boosters_count":1285 }
```

- `amount`는 `STEP_ENERGY`·`STEP_SPARK` 값만(아니면 422 `amount_not_allowed`)
- 처리 순서 = `db/reference_boost.sql`(실행 가능한 참조 구현), 테스트 30건(`db/test_boost.sql`)
- 같은 순간 재Boost: `card.is_new=false`, `points_added.total=0`, 단계 상승 시 `level_up`
- 연속 응원 보너스 = (연속 경기 수 − 1) × 10, 최대 100 → 첫 경기 0, 2경기째 +10(BE-1, 2026-10-17)
- `star_reason`: `fav_in_play`(내 선수가 교전 참여) / `fav_not_in_play`(미참여 → 기여 1위) / `auto`(내 선수 없음 → 기여 1위) / `non_partner` / `milestone`

### 4-3. `POST /v1/sponsor/boxes`

- 요청 `{moment_id, client, picked_index?}`. 결과는 서버 난수(`rng_seed_ref` 기록), 고른 위치와 무관. 같은 순간 재요청 → `replayed=true` + 첫 결과
- 응답 `result: win|miss`, `prize: {spark: 5|10} | null`, `next`: 당첨 `{spark, N}` / 꽝 `{energy, 10}` → Boost 상자 사전 선택(재화 라디오·강조·버튼 문구 동시 갱신)
- 409 `box_unavailable`(조건 불충족·총량 소진·**대조군** — 사용자에게 구분해 알리지 않음), 403 `minor_restricted` → 박스 숨기고 후원 라벨만
- 참조 구현 `db/reference_luckybox.sql`(함수 `open_sponsor_box`), 테스트 11건

## 5. 오류 코드

| HTTP | code | 화면 처리(`message_key`) |
|---|---|---|
| 400 | `bad_request` | 일반 오류 |
| 401 | `unauthorized` | 확장: 토큰 갱신 1회 → 실패 시 로그인 / 웹: 로그인 모달 → 같은 상태로 복귀 |
| 403 | `minor_restricted` | 해당 기능 숨김(행운 박스·결제 한도 초과 등) |
| 403 | `client_outdated` | 확장 업데이트 안내 |
| 404 | `not_found` · `moment_not_found` | 빈 상태 / 알림 닫기 |
| 409 | `insufficient_paid_energy` | `params.need, have, bonus_available` — 웹: 토스트 + 충전 화면 + 복귀 배너 / 확장: 토스트 + 웹 충전 링크. `bonus_available=true`면 "Boost에는 유료 Energy만 쓸 수 있어요" |
| 409 | `insufficient_spark` | 부족 안내 + 웹 광고 월 링크(경기 중 광고 유도 문구 금지) |
| 409 | `moment_closed` | "이 순간의 Boost가 마감됐어요" + 순간 칩 해제 |
| 409 | `milestone_closed` | "기념 기간이 끝났어요" |
| 409 | `box_unavailable` | 박스 버튼 숨김 |
| 409 | `already_used` | 광고 토큰 재사용 |
| 409 | `quiz_closed` · `quiz_already_answered` | 퀴즈 카드 마감 표시 |
| 422 | `amount_not_allowed` | 스테퍼 값으로 되돌림(개발 오류 로그) |
| 422 | `energy_not_allowed` | 비제휴 팀 Energy — Spark로 전환 |
| 422 | `not_partner_player` | 비제휴 선수 대상 — 팀 Boost로 |
| 422 | `disclosure_version_stale` | 고지 문구 변경 → `boost-context` 재조회 후 다시 확인 |
| 422 | `message_rejected` | "보낼 수 없는 표현이 있어요" — 메시지만 비우고 다시 |
| 422 | `idempotency_mismatch` | 개발 오류 — 신고 |
| 429 | `rate_limited` | `Retry-After`만큼 버튼 비활성 |
| 5xx | `server_error` | "보내지 못했어요. 차감되지 않았어요." — 같은 키로 재시도 |

## 6. 요청 한도 (사용자 기준)

| 대상 | 한도 | 초과 |
|---|---|---|
| `POST /boosts` | 10회/10초, 120회/시간 | 429 |
| `POST /sponsor/boxes` | 순간당 1회(판정) + 5회/분 | 409 / 429 |
| `POST /quiz/*/answers` | 문항당 1회 | 409 |
| `POST /ext/muse/chat` | 10회/분 | 429 |
| `POST /ads/rewarded/*` | `AD_DAILY_LIMIT` + 세션 간격 | 429 |
| 읽기 | 로그인 600회/분 · 비로그인 IP당 300회/분 | 429 |
| `/stream` | IP당 5연결 | 429 |

## 7. 관리자 API (별도 호스트 `admin.api.rorr.club`, 사내 SSO, 모든 변경 `admin_audit` 기록)

| 영역 | 오퍼레이션 |
|---|---|
| 설정 | `GET/PUT /admin/config/{key}` — `app_config`(= `/v1/config` 원본). 기능 플래그 즉시 차단(`flags.*`) |
| 협약 | `POST /admin/agreements` — 기간·배분율·공개 동의·IP 범위 |
| 순간 | `PATCH /admin/moments/{id}`(등급 정정·취소) |
| 기념일 | `POST /admin/milestones` — 출처 필수 |
| 메시지 | `GET /admin/messages?status=pending`, `POST /admin/messages/{id}/moderate`, 신고 큐 |
| 알림함 | `POST /admin/inbox`(요청자·검수자·대상 규칙·문안 버전), 대상 수 미리보기 |
| 스폰서 | `POST /admin/sponsor-contracts`(범위·최소 등급·확률표 버전·총량·대조군·철회 임계치), 지표 조회 |
| 환불 | `POST /admin/refunds/{id}/approve|reject` |
| 정산 | `POST /admin/settlements/{month}/calculate`, 팀 확인 기록 |
| Muse | `POST /admin/muse-lines`(세그먼트·버전) |

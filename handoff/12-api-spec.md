# 12. API 정의

- 작성일: 2026-10-17
- 계약 원본: [`api/openapi.yaml`](api/openapi.yaml)(OpenAPI 3.1, 43개 오퍼레이션·30개 스키마, `openapi-spec-validator` 통과, 참조 구현 응답이 `BoostResult` 스키마와 일치) · 실시간: [`api/realtime-events.md`](api/realtime-events.md)
- 이전 초안: 서비스 플로우 v2(2026-10-15, 아티팩트 "rorr.club 서비스 플로우" §5) → 정책 v1.3·행운 박스·기념 에디션·퀴즈·알림함을 반영해 대체

---

## 1. 공통 규약

| 항목 | 규칙 |
|---|---|
| 기본 경로 | `https://api.rorr.club/v1` — 하위 호환이 깨지면 `/v2` |
| 형식 | JSON(UTF-8), 시각은 ISO 8601 UTC(`2026-10-17T08:00:00Z`), 날짜 `YYYY-MM-DD`, 금액 원(정수) |
| 인증 | 웹: HttpOnly 세션 쿠키 `rorr_sid` + 상태 변경 시 `X-CSRF-Token` / 확장: `Authorization: Bearer`(액세스 15분, 리프레시 30일). 같은 계정 |
| 비로그인 허용 | 경기·순간·메시지·순위 조회, SSE, 퀴즈 응답(순위·상금 제외), 알림 노출 기록 |
| 멱등 | 금액이 오가는 POST(`/boosts`, `/energy/orders`, `/refunds`, `/moments/{id}/lucky-box`)는 `Idempotency-Key`(UUIDv4) 필수. 24시간 보관, 같은 키·같은 본문 → 처음 응답 재반환(200), 같은 키·다른 본문 → 409 `idempotency_mismatch` |
| 페이지 | 커서 방식 `?cursor=` → 응답 `next_cursor`(없으면 null). 기본 20, 최대 100 |
| 언어 | `Accept-Language: ko|en` — 고지·라벨 텍스트 선택. 오류 `message`는 개발용, 화면 문구는 `code`로 매핑 |
| 추적 | 모든 응답 `X-Request-Id`. 클라이언트는 오류 신고 시 함께 기록 |
| 클라이언트 표시 | 요청 헤더 `X-Client: web/1.4.2` 또는 `ext/2.0.0` — 강제 업데이트 판단·통계 |

## 2. 화면 → API 매핑

| 화면 | 호출 순서 |
|---|---|
| 앱 시작 | `GET /me`(로그인 시) → `GET /matches?status=live` → `GET /live/stream?match_ids=…` |
| 팀·선수 패널 응원 탭 | `GET /boost-context?team_id&player_id&moment_id` → (메시지·순위 탭) `GET /messages`, `GET /teams/{id}/rankings` |
| 재화·금액 변경 | 로컬 상태만. 재화 변경 시 `GET /boost-context?currency=`(고지 버전 갱신) |
| Boost 두 번째 누름 | `POST /boosts`(Idempotency-Key) → 결과로 연출·카드 표시 |
| 큰 순간 알림 | SSE `moment.alert` → 표시 → `POST /alerts/impressions{shown}` → 클릭 시 `{clicked}` + 패널 열기 |
| 행운 박스 | 후원 줄 → `POST /moments/{id}/lucky-box` → 결과 `next`로 Boost 상자 사전 선택 |
| 기념할 순간 | `GET /players/{id}/milestones` → `GET /boost-context?milestone_id` → `POST /boosts{milestone_id}` |
| 컬렉션 | `GET /me/cards` → 카드 상세 `GET /cards/{id}` → 저장 `GET /cards/{id}/image` |
| Energy 충전 | `GET /energy/packages` → `POST /energy/orders{return_to}` → 토스 결제창 → `POST /payments/toss/confirm` → `return_to`로 복귀 |
| 환불 | `GET /me/wallet` → `GET /me/refund-quote` → `POST /refunds` |
| 광고 월 | `POST /ads/rewarded/session` → GAM 재생 → `RewardedSlotGranted` → `POST /ads/rewarded/grant` |
| 알림함·동의 | `GET /me/inbox` · `GET/PUT /me/consents` · `PUT /me/match-alerts` |
| 확장: 중계 탭 감지 | `POST /ext/match-resolve` → SSE 구독 → 지연 보정 1탭(로컬 저장) |
| 확장: 퀴즈 | SSE `quiz.open` → `POST /quiz/{id}/answers` → SSE `quiz.result` |
| 확장: 내 선수 | 경기 시작 카드 → `PUT /me/fav-player` |

## 3. 핵심 오퍼레이션

### 3-1. `GET /v1/boost-context`

- 목적: Boost 상자에 필요한 **서버 판정값을 한 번에** 받는다. 클라이언트에서 파트너 여부·허용 재화·최소 단가·고지 문구를 하드코딩하지 않기 위함
- 주요 응답: `is_partner`, `allowed_currencies`, `steps`, `min`, `balance`(유료·보너스·Spark 분리), `moment`, `my_moment`(누적·배지·`to_next`·카드 보유), `notices`(버전 포함 고지), `share_line`(비율 없음), `sponsor`
- 캐시: 순간이 열려 있으면 5초, 아니면 30초. SSE `moment.closed` 수신 시 무효화

### 3-2. `POST /v1/boosts`

```json
// 요청
{ "team_id":"T1", "player_id":"faker", "moment_id":"5b1e…", "currency":"energy", "amount":10,
  "message":"오늘도 응원해", "client":"web", "entry":"player_chip",
  "notice_version":"boost_sheet_energy@2026-10-17" }
// 201 응답
{ "boost_id":"b_8f2c", "replayed":false,
  "balance":{"energy_paid":110,"energy_bonus":30,"spark":35},
  "points_added":{"base":20,"tier":30,"streak":10,"total":60},
  "moment_totals":{"energy":10,"spark":0,"energy_badge":1,"spark_badge":0,"to_next":{"energy":40,"spark":5}},
  "level_up":null,
  "card":{"id":"c_19ad","is_new":true,"kind":"moment","tier":"gold","edition":"partner","team_id":"T1",
          "star_player":{"id":"faker","nickname":"Faker","role":"mid"},"star_rule":"fav","serial_no":4127},
  "message":{"id":"msg_1","status":"pending"},
  "rank_hint":{"team_id":"T1","rank":127,"delta":1} }
```

- 처리 순서는 `db/reference_boost.sql`(실행 가능한 참조 구현)과 같아야 한다 — 테스트 27건(`db/test_boost.sql`)
- 같은 순간 재Boost: `card.is_new=false`, `points_added.total=0`, 단계 상승 시 `level_up`
- 메시지는 비동기 검수 → `pending`. 통과 시 SSE `message.new`

### 3-3. `POST /v1/moments/{id}/lucky-box`

- 결과는 서버 난수. `picked_index`는 연출 기록용. 같은 순간 재요청 → `replayed=true` + 같은 결과
- 응답 `next`: 당첨 `{spark, 5|10}` / 꽝 `{energy, 10}` → 클라이언트는 Boost 상자를 이 값으로 사전 선택(재화 라디오·강조·버튼 문구 동시 갱신)
- 403 `box_holdout`·`box_minor`: 박스를 숨기고 후원 라벨만. 409 `box_unavailable`: 총량 소진·조건 불충족
- 참조 구현: `db/reference_luckybox.sql`, 테스트 10건

## 4. 오류 코드

| HTTP | code | 화면 처리 |
|---|---|---|
| 401 | `login_required` | 로그인 모달 → 같은 상태로 복귀 |
| 402 | `insufficient_balance` | `details.need/have/bonus_only` — 웹: 토스트 + 충전 화면 + 복귀 배너 / 확장: 토스트 + 웹 충전 링크. `bonus_only=true`면 "Boost에는 유료 Energy만 쓸 수 있어요" |
| 403 | `minor_limit` | 미성년 월 결제 한도 안내 |
| 403 | `box_holdout` · `box_minor` | 박스 숨김(사용자 안내 없음) |
| 404 | `not_found` | 빈 상태 |
| 409 | `moment_closed` | "이 순간의 Boost가 마감됐어요" + 순간 칩 해제(순간 미선택 Boost로 다시 보낼 수 있음) |
| 409 | `milestone_closed` | "기념 기간이 끝났어요" |
| 409 | `box_unavailable` | 박스 버튼 숨김 |
| 409 | `idempotency_mismatch` | 개발 오류 — 새 키로 재시도하지 말고 신고 |
| 409 | `already_used` | 광고 토큰 재사용 |
| 409 | `quiz_closed` | "이미 마감됐어요" |
| 422 | `amount_below_min` | 스테퍼 최소값으로 되돌림 |
| 422 | `energy_not_allowed` | 비제휴 팀 Energy — 재화를 Spark로 전환 |
| 422 | `not_partner_player` | 비제휴 선수 대상 — 팀 Boost로 |
| 422 | `notice_version_stale` | 고지 문구가 바뀜 → `boost-context` 재조회 후 다시 확인 |
| 422 | `message_rejected` | 금칙어 — 메시지만 비우고 Boost는 다시 |
| 429 | `rate_limited` | `Retry-After`만큼 버튼 비활성 |
| 5xx | `internal` | "보내지 못했어요. 차감되지 않았어요." — 같은 Idempotency-Key로 재시도 |

## 5. 요청 한도 (미들티어, 사용자 기준)

| 범주 | 한도 | 비고 |
|---|---|---|
| `POST /boosts` | 10회/10초, 120회/시간 | 두 번 누르기 구조상 정상 사용은 훨씬 낮음 |
| `POST /lucky-box` | 순간당 1회(서버 제약) + 20회/분 | |
| `POST /ads/rewarded/*` | 일일 한도(`ad_reward.daily_limit`) + 세션 간격 | 서버 판정 |
| 조회 | 600회/분 | |
| 비로그인 | IP 기준 300회/분, SSE 연결 IP당 5개 | |

## 6. 관리자 API (별도 호스트 `admin.api.rorr.club`, 사내 SSO, 모든 변경 `admin_audit` 기록)

| 영역 | 오퍼레이션 |
|---|---|
| 설정 | `GET/PUT /admin/config/{key}` — 정책 §8 변수(`app_config`) |
| 협약 | `POST /admin/agreements` — 기간·배분율·공개 동의·IP 범위 |
| 순간 | `PATCH /admin/moments/{id}`(등급 정정·무효) |
| 기념일 | `POST /admin/milestones` — 출처 필수 |
| 메시지 | `GET /admin/messages?status=pending`, `POST /admin/messages/{id}/moderate`, 신고 큐 |
| 알림함 | `POST /admin/inbox`(요청자·검수자·대상 규칙·문안 버전), 발송 전 대상 수 미리보기 |
| 스폰서 | `POST /admin/campaigns`(범위·확률표 버전·총량·홀드아웃), 지표 조회 |
| 환불 | `POST /admin/refunds/{id}/approve|reject` |
| 정산 | `POST /admin/settlements/{month}/calculate`, 팀 확인 기록 |

# 18. 웹·확장 개발 설계 통합 기록

- 작성일: 2026-10-17
- 배경: 같은 날 두 세션이 공용 API·DB 설계를 따로 작성 — 웹 `rorr-hero/handoff`(df84cfb, 테이블 52·API 43) · 확장 `rorr-extension/handoff`(6e9eca4, 테이블 43·API 30). 둘 다 "웹·확장 공용"이라 개발 기준이 둘이 되는 문제
- 결정: **`rorr-hero/handoff/api/`·`db/`를 단일 기준**으로 하고, 확장 설계의 더 나은 장치·이름을 흡수. 확장 저장소의 `handoff/api/`·`handoff/schema/`·09·10·13은 참고용(머리말에 대체 표시)
- 결과: 테이블 59 · API 54(공용 32·웹 13·확장 9) · 참조 구현 테스트 41건(Boost 30·행운 박스 11) 통과

---

## 1. 항목별 채택

| # | 항목 | 웹(df84cfb) | 확장(6e9eca4) | 통합 기준 |
|---|---|---|---|---|
| 1 | 정책 변수 전달 | `app_config` 묶음 키, 전용 API 없음 | `GET /v1/config` 평면 대문자 이름 | **확장 채택**: `/v1/config` + 평면 이름(`app_config` 행 = 키) |
| 2 | Boost 확정 방식 | 즉시만 | `BOOST_SETTLE_MODE` immediate/on_moment, 201/202, `boost_status` | **확장 채택**. 참조 구현은 immediate, on_moment는 `boost_hold`/`boost_release` + SSE |
| 3 | 금액 검사 | 최소 단가 이상 | 스테퍼 단계 값만(`amount_not_allowed`) | **확장 채택** |
| 4 | 연속 응원 첫 경기 | +10 | 0 | **0**(BE-1 사용자 결정, 정책 예시 50 P) |
| 5 | 카드 주인공 기록 | `star_rule` fav/top/auto | `star_reason` 4종 | **확장 채택** + `milestone` |
| 6 | 내 선수 저장 | `users.fav_player_id` 1개 | 팀별(행 없음=안 물음, NULL=자동) | **확장 채택**, 테이블 `user_my_players`(웹 ★ `user_favorite_players`와 구분) |
| 7 | 같은 순간 누적 | `moment_totals` | `card_currency_totals` | 웹 유지(카드 유무와 무관) |
| 8 | 응원 포인트 | `point_events`(종류별 행) | `cheer_points`(순간당 1행) | 웹 유지 |
| 9 | 재화 묶음 | `wallet_lots` 통합 | `energy_lots` + `spark_lots` | 웹 유지(외래키 1개). `refund.md`도 이 이름으로 갱신 |
| 10 | 고지 버전 | `legal_notice_versions`·`notice_version` | `disclosures`·`disclosure_version` | **확장 채택** |
| 11 | 순간 상태 | predicted/open/resolved/void, 단일 등급 | upcoming/open/resolved/closed/cancelled, `tier_hint`/`final_tier` | **확장 채택**. 카드·포인트 등급은 Boost 시점 값 고정(BE-2) |
| 12 | 실시간 | `/v1/live/stream` 공개만, `moment.alert`·`void` | `/v1/ext/stream` 경기+사용자 채널, `moment.upcoming`·`cancelled`, `wallet.changed` 등 | **공용 `/v1/stream`** + 확장 이벤트 이름·사용자 채널 채택, 웹의 `sponsor.pool`·`message.new` 추가 |
| 13 | 오류 형식 | `message`·`details` | `message_key`·`params` | **확장 채택**(`message`는 개발용 선택) |
| 14 | 잔액 부족 | 402 `insufficient_balance` | 409 `insufficient_paid_energy`·`insufficient_spark` | **확장 채택** |
| 15 | 멱등 키 불일치 | 409 | 422 | **422** |
| 16 | 설정 API | `PATCH /me/settings` | `/me/preferences`(+`fav_players`) | **`/me/preferences`** + `my_players`, 별도 `PUT /me/my-player` |
| 17 | 알림 수준 값 | all/holo/off | all/decisive/off | **all/holo/off**(등급 이름과 일치). 확장 화면 문구 "결정적 순간만"은 유지, 값만 변경 |
| 18 | 행운 박스 | `POST /moments/{id}/lucky-box`, none/spark5/spark10, `lucky_box_opens` | `POST /sponsor/boxes`, win/miss+prize, `sponsor_box_opens`, `rng_seed_ref` | **확장 채택**(경로·이름·결과·난수 기록) + 웹 `picked_index`(선택)·`next` |
| 19 | 대조군 응답 | 403 `box_holdout` | 409 `box_unavailable` | **확장 채택**(대조군 여부를 노출하지 않음) |
| 20 | 미성년 | `box_minor`, `minor_limit` | `minor_restricted` | **`minor_restricted`** |
| 21 | 응원 메시지 | Boost 동반, 80자, `messages` | 별도 `POST /messages`, 60자, `cheer_messages` | 이름 `cheer_messages` 채택. **글자 수·별도 작성 허용은 결정 대기(D-9)** — 현재 80자·Boost 동반 |
| 22 | 알림 노출 기록 | `alert_impressions` | `headsup_impressions`(+무산 여부) | **확장 채택** |
| 23 | 중계 매칭·지연 | `/ext/match-resolve` | `/ext/match/resolve` + `broadcasts`·`stream_offset_reports`·`/ext/offset-reports` | **확장 채택** |
| 24 | 서하 | 없음 | `/ext/muse/lines`·`/ext/muse/chat`·`muse_lines` | **확장 채택** |
| 25 | 측정 | 15-frontend §3 이벤트 이름만 | `POST /v1/events` + 확장 handoff 14 정의 | **확장 채택** + 웹 이벤트 이름 병기 |
| 26 | Boost 상자 데이터 | `GET /boost-context` | `/config` + `GET /moments/{id}`(my) + `/me/wallet` | **둘 다 유지** — boost-context는 같은 값의 서버 집계(어느 쪽을 써도 결과 같음) |
| 27 | 팬덤·배분 공개 | `/teams/{id}/share-disclosure` | `/teams/{id}/fandom` | **`/teams/{id}/fandom`**(목표 + 공개 배분액) |
| 28 | 퀴즈 | `choice`, `/quiz/leaderboard` | `option_id`, `/quiz/ranking?scope` | **확장 채택** |
| 29 | 연령 | `age_band` | `is_minor` | `age_band` 저장, API는 `is_minor`도 제공 |
| 30 | 웹 전용 영역 | 결제·환불·광고 월·알림함·동의·기념 에디션·장식·관리 | 없음(기념 에디션 미포함) | 웹 유지(확장 스키마에 없던 부분 그대로) |

## 2. 확장 쪽이 바꿔야 할 것 (확장 세션·담당자)

| # | 내용 |
|---|---|
| E-1 | 구현 기준을 `rorr-hero/handoff/api/openapi.yaml`·`db/schema.sql`로 변경(확장 09·10·13 머리말에 표시함) |
| E-2 | `alert_level` 값 `decisive` → `holo`(화면 문구는 그대로) |
| E-3 | 스트림 경로 `/v1/ext/stream` → `/v1/stream` |
| E-4 | 행운 박스 응답에 `next` 사용 가능(당첨 → Spark N, 꽝 → Energy 10) |
| E-5 | 테이블 이름: `energy_lots`·`spark_lots` → `wallet_lots`, `card_currency_totals` → `moment_totals`, `cheer_points` → `point_events`, `user_fav_players` → `user_my_players` |
| E-6 | 확장 `boost_tx.sql` 테스트는 통합 참조 구현(`test_boost.sql`)으로 대체 — 시나리오는 모두 포함(첫 경기 0·재Boost·보너스 불가·멱등·비제휴·마감) |

## 3. 웹 쪽이 바꾼 것 (이번 커밋)

- 연속 응원 보너스 첫 경기 0 — 사이트 포인트 계산·블로그·FAQ 예시(60 → 50점 등)
- `docs/specs/refund.md`: Boost는 유료만, 정산은 정가 단가, `wallet_lots`, 테스트 4·9 교체
- handoff 01: 확장 기준 v45, 하단 구성(독 + 메뉴)
- handoff 06: 확장 설정 이름 추가

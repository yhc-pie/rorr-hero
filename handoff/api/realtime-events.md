# 실시간 이벤트 계약 (SSE)

- 작성일: 2026-10-17
- 엔드포인트: `GET /v1/live/stream?match_ids=m1,m2` (웹·확장 공용, 비로그인 허용)
- 형식: Server-Sent Events. 각 이벤트는 `id`(단조 증가 문자열), `event`(아래 이름), `data`(JSON 한 줄)
- 재연결: 클라이언트는 `Last-Event-ID`를 보내고 서버는 최근 2분 이벤트를 재전송. 그 이상 끊겼으면 `snapshot`을 먼저 보낸다
- 하트비트: 15초마다 `: ping` 주석 줄(프록시 타임아웃 방지). 30초 무수신이면 클라이언트가 재연결
- 개인 이벤트(내 잔액·카드)는 이 스트림에 싣지 않는다 — POST 응답과 `GET /v1/me`로만. 스트림은 경기 단위 공개 정보만
- 지연 보정: 결과형 이벤트(`moment.resolved`, `score`)는 클라이언트가 플랫폼 지연 오프셋만큼 늦춰 표시(확장). 예고형(`moment.alert`)은 즉시

---

## 1. 이벤트 목록

| event | 언제 | 소비자 | 클라이언트 동작 |
|---|---|---|---|
| `snapshot` | 연결·장기 단절 후 | 웹·확장 | 상태 전체 교체 |
| `score` | 킬·오브젝트·세트 변화 | 웹 티커·경기 페이지·확장 스트립 | 숫자 갱신(지연 보정) |
| `moment.alert` | 큰 순간 예고(골드·홀로그램) | 웹 배너/팝업·확장 예고 줄 | 빈도 상한·모달 겹침 확인 후 표시 |
| `moment.open` | Boost 창 열림 | Boost 상자 | "지금 이 순간" 칩 활성, 선수 칩 갱신 |
| `moment.resolved` | 순간 확정(승률 변화 포함) | 알림·카드 | 예고 철회 또는 확정 라벨("BARON STOLEN — T1") |
| `moment.closed` | Boost 창 닫힘(누적 종료) | Boost 상자 | 순간 칩 해제, 열린 상자에 "마감" 안내 |
| `moment.void` | 예고 무산 | 알림 | 조용히 철회(문구 없음) |
| `boosting.count` | 5초 간격 집계 | Boost 상자 | "함께 Boost 중 n" |
| `sponsor.pool` | 캠페인 총량 소진·재개 | 후원 줄 | 박스 버튼 숨김/표시(라벨은 유지) |
| `quiz.open` / `quiz.closed` / `quiz.result` / `quiz.void` | 퀴즈 문항 상태 | **확장만** | 퀴즈 카드 |
| `message.new` | 검수 통과 메시지 | 팬덤 라이브·응원 피드 | 아래에 추가(채팅 순서) |
| `match.status` | 경기 시작·세트 종료·종료 | 전부 | S3/S4 전환, 리캡 |

## 2. 페이로드

```text
event: moment.alert
id: 1729150000123-42
data: {"match_id":"lck-2026-10-15-t1-gen","game_no":2,"moment_id":"5b1e…","moment_key":"baron-2-24",
       "kind":"baron","tier":"gold","team_id":"T1",
       "label":{"ko":"바론 교전 임박","en":"Baron fight incoming"},
       "eta_at":"2026-10-15T08:24:38Z","closes_at":"2026-10-15T08:26:10Z",
       "participants":[{"player_id":"oner","is_top":true},{"player_id":"faker","is_top":false}],
       "sponsor":{"sponsor_id":"nova","label":{"ko":"후원 · presented by NOVA Gear","en":"Sponsored · presented by NOVA Gear"},
                  "box":true,"odds":{"none":75,"spark5":20,"spark10":5},"odds_version":"odds@2026-10-17"}}
```

| 필드 | 규칙 |
|---|---|
| `tier` | `gold` → 배너(웹)·예고 줄(확장), `holo` → 중앙 팝업. `silver`는 알림 없음 |
| `team_id` | 순간을 만든 팀. 비제휴 팀이면 `participants`는 빈 배열, 라벨에 선수명 없음 |
| `participants` | 파트너 팀 선수만. 웹 "이 교전의 선수" 칩·확장 카드 주인공 미리보기 |
| `sponsor` | 파트너 경기·캠페인 범위일 때만. 비제휴·범위 밖은 키 없음. `box:false`면 라벨만 |
| `eta_at` | 카운트다운 기준(서버 시각). 클라이언트 시계 오차는 `snapshot.server_time`으로 보정 |

```text
event: moment.resolved
data: {"moment_id":"5b1e…","outcome":"secured","team_id":"T1",
       "label":{"ko":"T1 바론 스틸","en":"BARON STOLEN — T1"},"wp_before":41.2,"wp_after":68.0,"game_time":"24:10"}

event: moment.closed
data: {"moment_id":"5b1e…","closed_at":"2026-10-15T08:26:10Z"}

event: boosting.count
data: {"moment_id":"5b1e…","count":1240}

event: sponsor.pool
data: {"campaign_id":"…","box":false}

event: quiz.open
data: {"question_id":"…","game_id":"…-g2","prompt":{"ko":"다음 드래곤, 어느 팀?","en":"Next dragon?"},
       "options":[{"id":"a","ko":"T1","en":"T1"},{"id":"b","ko":"GEN","en":"GEN"}],"closes_at":"…"}

event: snapshot
data: {"server_time":"…","matches":[{"id":"…","status":"live","score":[1,0],"game_no":2,
       "open_moments":[…],"alert":null}]}
```

## 3. 클라이언트 처리 규칙

| 규칙 | 내용 |
|---|---|
| 빈도 상한 | 웹 골드 180초·방문당 3회·홀로그램 경기당 1회 / 확장 `EXT_HEADSUP_MIN_GAP`. 서버도 같은 값으로 `alert_impressions`를 보고 판단할 수 있으나, 1차 판정은 클라이언트(오프라인 허용) |
| 모달 겹침 | 결제·Boost 완료·로그인·행운 박스 무대가 열려 있으면 알림을 보류했다가 닫힌 뒤 `eta_at`이 남아 있으면 표시 |
| 설정 | `alert_level=holo`면 골드 무시, `off`면 전부 무시 |
| 탭 신호(웹) | `document.hidden`이면 탭 제목 앞 "(⚡ 곧 바론)" + 파비콘 점, 돌아오면 원복 |
| 아이콘 배지(확장) | 패널 닫힘 시 `chrome.action.setBadgeText`로 신호(서비스 워커) |
| 순서 보장 | 같은 `moment_id`의 이벤트는 `alert → open → resolved/void → closed` 순. 역순 도착 시 `id` 기준 정렬 |
| 중복 | 같은 `id` 재수신은 무시 |

## 4. 서버 측 발행

- 원천: 순간 감지 워커(datacenter 승률·wGE+ ΔG) → `moments` 갱신 + `outbox_events`(`moment.*`)
- 팬아웃: 아웃박스 퍼블리셔 → Redis Pub/Sub 채널 `live:{match_id}` → 실시간 게이트웨이(SSE 노드) → 연결된 클라이언트
- `boosting.count`: `boost.created` 이벤트를 5초 창으로 집계해 발행(개인 식별 정보 없음)
- 재전송 버퍼: 매치별 Redis Stream(최근 2분, `MAXLEN ~ 2000`)

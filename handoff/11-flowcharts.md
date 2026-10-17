# 11. 플로차트

- 작성일: 2026-10-17 · 형식: Mermaid(GitHub에서 바로 렌더, 전체 렌더 검증 완료)
- 상태 기계(화면 단위)는 [14-interaction-spec](14-interaction-spec.md)

| # | 흐름 | 종류 |
|---|---|---|
| F-1 | 사용자 여정 전체 | 흐름도 |
| F-2 | Boost 서버 판정 | 흐름도 |
| F-3 | Boost 요청 전 구간 | 시퀀스 |
| F-4 | 큰 순간 알림 표시 판정 | 흐름도 |
| F-5 | 스폰서 행운 박스 | 시퀀스 |
| F-6 | Energy 부족 → 충전 → 복귀 | 시퀀스 |
| F-7 | 충전 결제(토스페이먼츠) | 시퀀스 |
| F-8 | 환불 | 흐름도 |
| F-9 | 광고 월 Spark | 시퀀스 |
| F-10 | 로그인(웹·확장) | 시퀀스 |
| F-11 | 확장 경기 매칭·지연 보정 | 흐름도 |
| F-12 | 확장 퀴즈 스트릭 | 시퀀스 |
| F-13 | 기념 에디션 | 흐름도 |
| F-14 | 응원 메시지 검수 | 흐름도 |
| F-15 | 알림함 발송 판정(§5-7) | 흐름도 |
| F-16 | 월 정산·배분액 공개 | 흐름도 |

---

## F-1. 사용자 여정 전체

```mermaid
flowchart TD
  A["방문: rorr.club 또는 확장 설치"] --> B["응원 팀 선택(비로그인 가능)"]
  B --> C{"경기 진행 중?"}
  C -- "아니오" --> D["다음 경기 안내 + 경기 시작 알림 옵트인"]
  D --> C
  C -- "예" --> E["라이브: 티커·경기 페이지 / 확장 Watch"]
  E --> F["큰 순간 예고(골드·홀로그램)"]
  F --> G{"사용자 선택"}
  G -- "이 순간 Boost 준비" --> H["Boost 상자"]
  G -- "행운 박스 열기(파트너·스폰서)" --> I["행운 박스 무대"]
  I -- "당첨: Spark N" --> H
  I -- "꽝: Energy 10" --> H
  G -- "닫기" --> E
  H --> J{"로그인?"}
  J -- "아니오" --> K["로그인"] --> H
  J -- "예" --> L{"잔액?"}
  L -- "부족" --> M["충전(웹) → 복귀"] --> H
  L -- "충분" --> N["두 번 누르기 → 전송"]
  N --> O["Boost 완료 연출 → 모먼트 카드(신규 또는 배지 상승)"]
  O --> P["포인트·순위 반영 · 응원 메시지"]
  P --> E
  E -->|"경기 종료"| Q["리캡: 오늘 카드·포인트 → 컬렉션(최종 단계 저장)"]
```

## F-2. Boost 서버 판정

```mermaid
flowchart TD
  S["POST /v1/boosts"] --> I{"Idempotency-Key 기존?"}
  I -- "완료" --> R0["처음 응답 재반환"]
  I -- "신규" --> M{"amount ∈ STEP_ENERGY·STEP_SPARK?"}
  M -- "아니오" --> E1["422 amount_not_allowed"]
  M -- "예" --> P{"팀 협약 유효?<br/>(현재 시각)"}
  P -- "아니오" --> PE{"currency = energy?"}
  PE -- "예" --> E2["422 energy_not_allowed"]
  PE -- "아니오(Spark)" --> W
  P -- "예" --> NV{"Energy면 고지 버전 최신?"}
  NV -- "아니오" --> E3["422 disclosure_version_stale"]
  NV -- "예" --> W{"순간·기념 창 열림?"}
  W -- "아니오" --> E4["409 moment_closed / milestone_closed"]
  W -- "예 또는 순간 미선택" --> D["묶음 잠금·차감<br/>Energy=유료만 / Spark"]
  D --> B{"잔액 충분?"}
  B -- "아니오" --> E5["409 insufficient_paid_energy·insufficient_spark<br/>(전체 롤백)"]
  B -- "예" --> T["moment_totals 누적 → 배지 재계산"]
  T --> C{"이 순간·기념일 카드 있음?"}
  C -- "없음" --> C1["카드 발급<br/>에디션=발급 시점 협약<br/>주인공=내 선수(참여 시)→기여 1위"]
  C -- "있음" --> C2["카드 유지 · level_up 판정"]
  C1 --> PT["포인트: base+tier(순간당 1회)<br/>streak=(연속 경기−1)×10(경기·팀당 1회, 첫 경기 0)"]
  C2 --> OB
  PT --> OB["아웃박스 boost.created · 메시지 검수 큐"]
  OB --> R["201 BoostResult"]
```

## F-3. Boost 요청 전 구간

```mermaid
sequenceDiagram
  autonumber
  participant U as 사용자
  participant FE as 웹·확장 UI
  participant BFF as 웹 BFF
  participant GW as API 게이트웨이
  participant API as Service API
  participant DB as 서비스 DB
  participant OB as 아웃박스 퍼블리셔
  participant RT as 실시간 게이트웨이
  U->>FE: 주 버튼 1회
  FE->>FE: armed(5초) · 문구 "한 번 더 눌러 보내기" · 차감 없음
  U->>FE: 주 버튼 2회
  FE->>BFF: POST /api/boosts (쿠키, CSRF, Idempotency-Key)
  Note over FE,GW: 확장은 BFF 없이 GW로 Bearer
  BFF->>GW: 내부 토큰 + 본문
  GW->>GW: 스키마 검증 · 요청 한도 · 멱등 선점
  GW->>API: 사용자 컨텍스트 + 요청
  API->>DB: BEGIN · 판정 · 차감 · 누적 · 카드 · 포인트 · outbox · COMMIT
  DB-->>API: 결과
  API-->>GW: 201 BoostResult
  GW->>GW: 멱등 응답 저장 · 응답 필터(배분율 차단)
  GW-->>FE: 201
  FE->>U: 연출 → 카드(신규·배지 상승·N 남음)
  OB->>DB: 미발행 outbox 읽기
  OB->>RT: boost.created (Redis)
  RT-->>FE: moment.stats (5초 집계)
```

## F-4. 큰 순간 알림 표시 판정 (클라이언트)

```mermaid
flowchart TD
  A["SSE moment.upcoming 수신"] --> B{"tier = silver?"}
  B -- "예" --> X["표시 안 함"]
  B -- "아니오" --> C{"alert_level 설정"}
  C -- "off" --> X
  C -- "holo만 & tier=gold" --> X
  C -- "통과" --> D{"빈도 상한<br/>웹: 골드 180초·방문 3회, 홀로 경기당 1회<br/>확장: EXT_HEADSUP_MIN_GAP"}
  D -- "초과" --> X
  D -- "통과" --> E{"모달 열림?<br/>결제·Boost 완료·로그인·행운 박스"}
  E -- "예" --> Q["보류 큐 → 닫힌 뒤 eta 남았으면 표시"]
  E -- "아니오" --> F{"웹 탭 숨김?"}
  F -- "예" --> T["탭 제목 '(⚡ 곧 바론)' + 파비콘 점"]
  F -- "아니오" --> G{"tier"}
  G -- "gold" --> H["골드 배너(웹 상단 / 확장 예고 줄)"]
  G -- "holo" --> I["홀로그램 팝업(웹 중앙 / 확장 패널 중앙)"]
  H --> S{"sponsor.box?"}
  I --> S
  S -- "예" --> SP["후원 줄: 라벨 + 행운 박스 열기 + 확률"]
  S -- "라벨만" --> SL["후원 라벨"]
  H --> L["POST /headsup/impressions shown"]
  I --> L
```

## F-5. 스폰서 행운 박스

```mermaid
sequenceDiagram
  autonumber
  participant U as 사용자
  participant FE as UI
  participant API as Service API
  participant DB as 서비스 DB
  U->>FE: 행운 박스 열기
  alt 비로그인
    FE->>U: 로그인 → 복귀
  end
  FE->>FE: 무대 열기(250ms) · 후원 라벨·확률 상시
  FE->>FE: 섞기 1.5초 (서버 호출과 병행)
  FE->>API: POST /sponsor/boxes {picked_index}
  API->>DB: 캠페인 잠금 · 홀드아웃 · 미성년 · 1회 확인 · 서버 난수 · 총량 차감 · Spark 묶음
  DB-->>API: result
  API-->>FE: {result, spark, next}
  U->>FE: 박스 선택(첫 박스에 초점)
  FE->>FE: 흔들기 1.1초 → 결과(당첨 입자 / 꽝 차분)
  alt 당첨
    FE->>U: "Spark N으로 이 순간 Boost" → Boost 상자(Spark·N 선택)
  else 꽝
    FE->>U: "이 순간, Energy로 직접 Boost해 볼까요?" + 배분 1줄 → Boost 상자(Energy·10)
  end
  FE->>FE: 알림 줄 버튼 → 결과 칩
  Note over FE,API: 403 holdout·minor → 박스 숨김, 409 unavailable → 라벨만
```

## F-6. Energy 부족 → 충전 → 복귀

```mermaid
sequenceDiagram
  autonumber
  participant U as 사용자
  participant W as 웹 패널
  participant X as 확장 패널
  participant API as API
  U->>W: Boost(Energy 50)
  W->>API: POST /boosts
  API-->>W: 409 insufficient_paid_energy {need:50, have:20, bonus_available:false}
  W->>U: 토스트 "Energy 50 필요 · 보유 20"
  W->>W: /account/energy?return_to=/team/T1?tab=cheer&moment=…&cur=energy&amt=50
  W->>U: 상단 배너(부족 30 · 돌아가기) + 충분한 최소 팩 강조
  U->>W: 결제 완료
  W->>U: "Boost로 돌아가기" → 패널 응원 탭, 같은 순간·재화·금액
  rect rgba(127,127,127,0.08)
  U->>X: Boost(Energy 50)
  X->>API: POST /boosts
  API-->>X: 409 insufficient_paid_energy
  X->>U: 토스트 + "rorr.club에서 충전" (새 탭)
  U->>X: 패널로 돌아옴(visibilitychange)
  X->>API: GET /me
  X->>U: "잔액을 새로 불러왔어요 · 이어서 Boost할 수 있어요" + 시트 Energy 선택으로 재오픈
  end
```

## F-7. 충전 결제

```mermaid
sequenceDiagram
  autonumber
  participant U as 사용자
  participant W as 웹
  participant B as BFF
  participant API as API
  participant T as 토스페이먼츠
  participant DB as DB
  U->>W: 패키지 선택(청약철회 고지 표시)
  W->>B: POST /api/energy/orders {package_id, return_to} + Idempotency-Key
  B->>API: 주문 생성(미성년 월 한도 검사)
  API->>DB: energy_orders(created)
  API-->>W: order_id, amount, PG 파라미터
  W->>T: 결제창
  T-->>B: success 리다이렉트(paymentKey, orderId, amount)
  B->>API: POST /payments/toss/confirm
  API->>T: 승인 API(금액 대조)
  T-->>API: 승인
  API->>DB: orders(paid) + wallet_lots(paid, 단가·정가 단가, +5년) + ledger(purchase)
  API-->>B: balance, return_to
  B-->>W: return_to로 이동
  T--)API: 웹훅(서명 검증, 멱등)
```

## F-8. 환불

```mermaid
flowchart TD
  A["내 Boost › Energy › 환불 신청"] --> B["GET /me/refund-quote"]
  B --> C{"묶음별 판정"}
  C -- "보너스" --> N1["환불 불가(비활성)"]
  C -- "구매 7일 이내" --> D["수수료 0"]
  C -- "7일 경과" --> E["수수료 max(5%, 1,000원)"]
  C -- "면제 사유<br/>서비스 종료·미성년·회사 귀책" --> D
  D --> F{"실수령 > 0?"}
  E --> F
  F -- "아니오" --> N2["신청 불가 · below_fee 안내"]
  F -- "예" --> G["POST /refunds (Idempotency-Key)"]
  G --> H["묶음 refund_locked<br/>(동시 Boost 차단)"]
  H --> I["관리 승인"]
  I --> J{"PG 취소 성공?"}
  J -- "예" --> K["묶음 refunded · 원장 refund · done"]
  J -- "아니오" --> L["계좌 환급 전환 · processing 유지"] --> K
  K --> M["3영업일 이내 완료 안내"]
```

## F-9. 광고 월 Spark (웹)

```mermaid
sequenceDiagram
  autonumber
  participant U as 사용자
  participant W as 광고 월
  participant API as API
  participant G as GAM
  W->>API: POST /ads/rewarded/session
  API-->>W: token, remaining_today (한도 초과 시 429 + 다음 가능 시각)
  W->>G: 보상형 슬롯 요청
  alt no-fill
    G-->>W: 광고 없음
    W->>U: "지금은 볼 수 있는 광고가 없어요" (대체 보상 없음)
  else RewardedSlotReady
    W->>U: "광고 보고 Spark 받기"
    U->>G: 전체 화면 시청
    alt 끝까지
      G-->>W: RewardedSlotGranted
      W->>API: POST /ads/rewarded/grant {token}
      API-->>W: spark_added 5, balance
    else 닫기
      G-->>W: RewardedSlotClosed → 미지급
    end
  end
```

## F-10. 로그인

```mermaid
sequenceDiagram
  autonumber
  participant W as 웹
  participant B as BFF
  participant P as OAuth 제공자
  participant API as API
  participant X as 확장 SW
  W->>B: /api/auth/google
  B->>P: 인가 요청(state, PKCE)
  P-->>B: callback code
  B->>API: 계정 조회·생성·연결(로컬 응원 팀 병합)
  API-->>B: user
  B-->>W: Set-Cookie rorr_sid · 원래 화면
  X->>P: chrome.identity.launchWebAuthFlow(rorr.club 인증 화면 경유)
  P-->>X: 리다이렉트(code)
  X->>API: POST /auth/ext/token {code, PKCE}
  API-->>X: access(15분) · refresh(30일)
  X->>X: chrome.storage에 보관 · 패널에 auth.changed
```

## F-11. 확장 경기 매칭·지연 보정

```mermaid
flowchart TD
  A["탭 활성·URL 변경"] --> B{"지원 호스트?<br/>YouTube·치지직·SOOP·Twitch"}
  B -- "아니오" --> S1["S1 평시: Muse 채팅 + 다음 경기"]
  B -- "예" --> C["POST /ext/match/resolve {host,url,title}"]
  C --> D{"match_id 확정?"}
  D -- "예" --> E["SSE 구독 + 기본 오프셋 적용"]
  D -- "후보 여러 개" --> F["경기 선택 목록"] --> E
  D -- "없음" --> S1
  E --> G{"이 경기 개인 오프셋 저장됨?"}
  G -- "아니오" --> H["보정 1탭: '이 장면이 보이면 눌러 주세요'"] --> I["offset 저장"]
  G -- "예" --> J["S3 경기 중"]
  I --> J
  J --> K["결과형 이벤트는 오프셋만큼 지연 표시 · 예고형은 즉시"]
```

## F-12. 확장 퀴즈 스트릭

```mermaid
sequenceDiagram
  autonumber
  participant Q as 퀴즈 워커
  participant RT as SSE
  participant X as 확장
  participant API as API
  Q->>RT: quiz.open (closes_at = 결과가 어느 중계에도 보이기 전)
  RT-->>X: 퀴즈 카드(2지선다, 카운트다운) · 큰 순간 예고와 겹치면 퀴즈 먼저 마감
  X->>API: POST /quiz/{id}/answers {choice} (무료, 재화 없음)
  API-->>X: 202
  Q->>RT: quiz.closed
  alt 마감 전 이벤트 발생
    Q->>RT: quiz.void → "This one happened too fast. It won't count."
  else 정상
    Q->>RT: quiz.result → 정답 +1·점수 10+스트릭×5 / 오답 0 / 미응답 유지
  end
  Note over Q: 주 마감 → 상위 10명 총 30 Spark(공식 규칙 게시 전 지급 금지, 수령 연령 제한)
```

## F-13. 기념 에디션

```mermaid
flowchart TD
  A["선수 패널 응원 탭 상단 '기념할 순간'"] --> B{"파트너 팀 선수?"}
  B -- "아니오" --> X["기념일 미노출"]
  B -- "예" --> C{"오늘이 기념 기간<br/>(달성일 ±3일)?"}
  C -- "이전" --> D["미리 보기만 · 'N일에 열려요'"]
  C -- "이후" --> E["미리 보기만 · '기념 기간이 끝났어요'"]
  C -- "기간 중" --> F["기념 Boost → Boost 상자 기념 모드"]
  F --> G["POST /boosts {milestone_id}"]
  G --> H{"이 기념일 카드 있음?"}
  H -- "없음" --> I["기념 에디션 발급(등급 없음) · 축하 순번 N"]
  H -- "있음" --> J["누적만(배지)"]
  I --> K["축하 연출 → '축하 완료 ✓' · 알림함 '내 소식'"]
  F -.-> L["메시지 → 응원 롤(공개분만, 선수 전달은 T1 협의 중)"]
```

## F-14. 응원 메시지 검수

```mermaid
flowchart TD
  A["Boost와 함께 메시지(1~80자)"] --> B["messages status=pending"]
  B --> C{"금칙어·선수 비난 필터"}
  C -- "명백 위반" --> R["rejected · 작성자에게만 안내"]
  C -- "의심" --> Q["관리 검수 큐"]
  C -- "통과" --> V["visible → SSE message.new"]
  Q -- "승인" --> V
  Q -- "거절" --> R
  V --> P["신고(⋯ 메뉴)"] --> RQ["신고 큐 → hidden 또는 유지"]
  V --> RE["'나도 응원'(1회, 포인트 미반영) · 칩 답장 4종"]
```

## F-15. 알림함 발송 판정 (정책 §5-7)

```mermaid
flowchart TD
  A["발송 요청(RORR 또는 파트너 팀 → RORR 대리)"] --> B{"분류"}
  B -- "서비스 공지" --> SA{"광고성 내용?"} -- "있음" --> NO["반려"]
  SA -- "없음" --> SEND
  B -- "내 소식" --> M1{"사용자 '내 소식' 켜짐?"} -- "예" --> SEND
  B -- "팀·선수 소식" --> T1{"비제휴 팀?"} -- "예" --> NO
  T1 -- "아니오" --> T2{"팀 소식 옵트인?"} -- "아니오" --> SKIP["제외"]
  T2 -- "예" --> CAP
  B -- "광고" --> P1{"미성년?"} -- "예" --> SKIP
  P1 -- "아니오" --> P2{"광고 옵트인?"} -- "아니오" --> SKIP
  P2 -- "예" --> P3{"야간(21~08시)?"} -- "예" --> P4{"야간 동의?"} -- "아니오" --> HOLD["08시 이후로 보류"]
  P3 -- "아니오" --> CAP
  P4 -- "예" --> CAP
  CAP{"대상 규칙 = 응원 활동 기준만?<br/>결제·잔액 기준 금지<br/>최소 인원 이상?"} -- "아니오" --> NO
  CAP -- "예" --> F{"빈도 상한<br/>팀 주1·광고 주2·하루 3"} -- "초과" --> SKIP
  F -- "통과" --> SEND["발송: 제목 '(광고)' 표기(광고), 발신자 배지"]
  SEND --> G{"라이브 경기 중?"} -- "예" --> IN["알림함에만 적재 · 푸시는 경기 후"]
  G -- "아니오" --> PU["알림함 + 동의 채널 푸시"]
```

## F-16. 월 정산·배분액 공개

```mermaid
flowchart TD
  A["매월 1일 배치"] --> B["파트너 경기 Boost의 유료 사용분<br/>Σ qty × 정가 단가"]
  B --> C["× 협약 배분율(Boost 시점 유효 협약)"]
  C --> D["- 전월 정산 후 취소분(adjust)"]
  D --> E["settlements calculated"]
  E --> F{"분기 말?"}
  F -- "예" --> G["팀 공동 확인 → team_confirmed<br/>'2026 Q4 정산 · T1 확인'"]
  F -- "아니오" --> H["월 지급"]
  G --> I["v_team_share_disclosure 갱신(월 1회)"]
  H --> I
  I --> J["ⓘ 펼침·배분 안내 글: 시즌 누적 배분액(원) · 비율 미표기"]
```

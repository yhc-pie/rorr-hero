# 15. 프론트엔드 설계 (웹 · 확장 · 공용)

- 작성일: 2026-10-17 · 화면 명세는 04, 동작은 05·14, 계약은 12·openapi.yaml

---

## 1. 웹 (Next.js App Router)

### 1-1. 라우트 트리

```
app/
  (site)/
    layout.tsx                 헤더·티커·푸터·전역 오버레이 호스트(알림·토스트·행운 박스 무대)
    page.tsx                   홈
    match/[id]/page.tsx
    stats/page.tsx             (/wrc, /wge → redirect)
    rank/page.tsx
    spark/page.tsx             광고 월(GAM, 클라이언트 전용)
    blog/[slug]/page.tsx       SSG
    faq/[[...id]]/page.tsx     SSG
    legal/[doc]/page.tsx       SSG(docs/legal/*.md)
    about/page.tsx · contact/page.tsx
    chat/page.tsx
    account/[tab]/page.tsx     energy · boost · collection · inbox · billing · settings
    @panel/(.)player/[id]/page.tsx   인터셉트 라우트 → 사이드 패널
    @panel/(.)team/[id]/page.tsx
    player/[id]/page.tsx · team/[id]/page.tsx   직접 진입 시 전체 페이지
  api/                         BFF 라우트(16 문서) — 세션 쿠키 → 내부 토큰 변환 프록시
```

- 원본 해시 라우트(`#player/Faker`)는 `middleware.ts`에서 받을 수 없으므로 클라이언트 진입 스크립트가 `location.hash`를 새 경로로 `replace`
- 패널 탭·순간 이어받기는 URL 쿼리로: `/team/T1?tab=cheer&moment=…&cur=spark&amt=5` — 새로고침·공유에도 유지(원본 `BXCARRY` 대체)

### 1-2. 상태 계층

| 계층 | 도구 | 내용 |
|---|---|---|
| 서버 상태 | TanStack Query | `me`, `boost-context`, 카드, 순위, 메시지. 키 규칙 `['boost-context', team, player, moment, currency]` |
| 실시간 | `LiveProvider`(SSE 1개 연결 공유) | 이벤트 → Query 캐시 갱신(`score`, `moment.*`) + 알림 매니저로 전달 |
| UI 상태 | Zustand | 열린 오버레이, 알림 큐, 두 번 누르기 상태, 행운 박스 무대 단계 |
| URL 상태 | searchParams | 패널 탭·이어받기 값·언어 |
| 로컬 | localStorage(try/catch) | 테마, 비로그인 응원 팀, 알림 노출 횟수(방문 단위), 익명 ID |

### 1-3. 전역 오버레이 매니저

- 한 번에 하나의 **모달 계열**(로그인·결제·Boost 완료·행운 박스·공유)만. 큰 순간 알림은 모달이 열려 있으면 보류 큐에 넣고, 닫힌 뒤 `eta_at`이 남아 있으면 표시
- 쌓임 순서는 `tokens.css` §7 z-index 토큰만 사용
- 열 때 초점 이동·닫을 때 복귀, 배경 `inert`

### 1-4. 주요 컴포넌트 (공용 패키지 `@rorr/ui`)

```ts
type Currency = 'energy' | 'spark';

interface BoostBoxProps {
  ctx: BoostContext;                       // GET /boost-context 응답 그대로
  target: { teamId: string; playerId?: string };
  preset?: { currency: Currency; amount: number; entry: BoostEntry };   // 행운 박스·선수 칩 이어받기
  layout: 'panel' | 'sheet';               // 웹 패널 / 확장 시트
  onSent(result: BoostResult): void;       // 연출·카드 표시로 연결
}

interface CurrencyPickerProps {            // role="radiogroup"
  value: Currency;
  allowed: Currency[];                     // 비제휴: ['spark'] → energy는 disabled + 사유
  balance: { energy_paid: number; spark: number };
  onChange(c: Currency): void;             // 변경 시 금액은 해당 재화 기본값으로
}

interface StepperProps { steps: number[]; value: number; onChange(n: number): void; }

interface SendButtonProps {                // 두 번 누르기 상태 기계(14 §2)
  currency: Currency; amount: number;
  confirmWindowMs: number;                 // GET /v1/config BOOST_CONFIRM_WINDOW_MS
  disabled?: boolean;
  onConfirm(): Promise<void>;
}

interface MomentCardProps {
  card: Card;                              // API Card
  size: 'sm' | 'md' | 'lg';
  face?: 'front' | 'back';
  showRemaining?: { currency: Currency; toNext: number | null };   // 재Boost 결과
}

interface LuckyBoxStageProps {
  momentId: string;
  sponsor: SponsorLabel;
  container: 'fullscreen' | 'panel';       // 웹 / 확장(폭 304px)
  onResult(r: SponsorBoxResult): void;       // r.next로 BoostBox preset
}

interface IdentityHeaderProps {            // 패널 축소형 헤더(04 §2)
  kind: 'player' | 'team';
  name: string; sub: string;
  avatar?: { src: string; shape: 'round' | 'logo' } | { initial: string };
  watch: RefObject<HTMLElement>;           // 큰 이름 요소
}
```

### 1-5. 오류·로딩 표시

| 상황 | 표시 |
|---|---|
| 첫 로딩 | 실제 배치와 같은 골격(skeleton). 스피너 단독 금지 |
| Boost 전송 중 | 주 버튼 진행 표시·비활성, 3초 넘으면 "조금 걸리고 있어요" |
| 오류 | `error.code` → i18n 키(12 §4). 차감 여부를 반드시 함께 안내 |
| 오프라인 | 상단 오프라인 바, Boost 비활성, 라이브 해설 "일시 정지 · 마지막 갱신 {시각}" |
| SSE 끊김 | 5초 내 자동 재연결(지수 백오프 최대 30초), 재연결 후 `snapshot` 반영 |

### 1-6. 성능 예산

- 첫 화면 JS 170KB(gzip) 이하, LCP 2.5초 이하(4G), CLS 0.1 이하
- 패널·행운 박스 무대·카드 캔버스 저장은 지연 로딩
- 이미지: WebP/AVIF, 선수 사진 `assets/t1/web/*.webp` 규격 유지
- 원본 단일 HTML(약 1.2MB)·CSS 349KB는 이식 대상이 아님

## 2. 크롬 확장 (MV3)

### 2-1. 구성

| 부분 | 역할 | 비고 |
|---|---|---|
| 사이드 패널(`side_panel`) | 모든 UI(React) | 독(질문·오늘의 모먼트·Boost) + 메뉴(v45) |
| 서비스 워커 | 인증 토큰 보관·갱신, SSE 연결(패널 열림 동안), 탭 감지(`tabs.onUpdated`), 아이콘 배지, 경기 시작 알림(`alarms`·`notifications`) | 비활성 종료 전제 — 패널 열림 동안만 SSE 유지 |
| 콘텐츠 스크립트 | 없음(권장) — `tabs` API로 URL·제목만 | DOM 삽입·변경 금지 |
| 저장 | `chrome.storage.local`(설정·토큰·지연 오프셋·코치마크), IndexedDB(관계 기억) | |
| 렌더러 | VRM 3D 동봉(원격 코드 금지) | 저사양 폴백: 정지 이미지 |

### 2-2. 메시지 흐름

```
서비스 워커 ──(chrome.runtime port: 'live')──▶ 사이드 패널
  · live.event {SSE 이벤트 그대로}
  · auth.changed {loggedIn}
  · tab.match {match_id, host, default_offset_ms}
사이드 패널 ──▶ 서비스 워커
  · live.subscribe {match_ids}
  · offset.set {match_id, offset_ms}
  · badge.clear
```

- 패널이 닫혀 있으면 SW는 `moment.upcoming`(골드 이상)만 받아 아이콘 배지 표시, 푸시 알림은 띄우지 않음(정책 §5-4)
- 충전 복귀: 패널 `visibilitychange`(visible) → `GET /me` 재조회 → 직전 상태가 Boost 시트·큰 순간 알림이면 시트를 Energy 선택으로 다시 엶

### 2-3. 권한

`sidePanel` `storage` `identity` `notifications` `alarms` `tabs` + 호스트 4곳(YouTube·치지직·SOOP·Twitch) + `api.rorr.club`. `<all_urls>` 금지. CSP는 원격 스크립트 금지.

## 3. 공용 규칙

- **i18n**: 문장 단위 키, 조사 함수는 `@rorr/i18n`의 `josa(name, '이/가')`(라틴 끝 n·m·l·ng 받침, 숫자는 읽는 소리 기준). 고유명 번역 금지
- **토큰**: 컴포넌트에 원시 hex 금지. `@rorr/tokens`만 참조
- **분석 이벤트**: `alert_shown` `alert_clicked` `boost_armed` `boost_sent` `boost_failed{code}` `card_revealed{is_new,level_up}` `box_shown` `box_open` `box_result{prize}` `box_cta{currency}` `topup_start` `topup_return` `quiz_answer` — 공통 속성 `client`, `match_id`, `moment_id`, `is_partner`. 개인 결제 금액은 보내지 않음
- **테스트**: 컴포넌트 단위(Testing Library) + 시각 회귀(Playwright 스크린샷 1440·390, KO·EN, 다크·라이트) + E2E(로그인 → Boost → 카드, 행운 박스 → Boost, Energy 부족 → 충전 → 복귀)

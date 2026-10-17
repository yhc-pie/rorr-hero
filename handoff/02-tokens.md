# 02. 디자인 토큰

- 작성일: 2026-10-17
- 파일: [`tokens/tokens.css`](tokens/tokens.css)(단일 원본) · [`tokens/tokens.json`](tokens/tokens.json)(같은 값, 도구 연동용)
- 측정: Playwright `getComputedStyle(document.documentElement)` — 웹 다크·라이트 각 1회, 확장 목업 1회

---

## 1. 이름 규칙

- 원본 변수명은 역사적 이름이 섞여 있어 그대로 옮기지 않는다
  - 예: `--gold`·`--cyan`은 이름과 달리 **보라(행동 보조색)**, `--cta`·`--v-solid`·`--brand-v`는 모두 같은 `#6F4CFF`
- 새 이름 = `--{분류}-{역할}-{변형}`. 각 줄 주석에 원본 변수명을 남김(이식 중 대조용)
- Tailwind 포팅 시 `theme.extend.colors`에 `--color-*`를 CSS 변수로 연결(`'bg-page': 'var(--color-bg-page)'`)하고 다크·라이트는 `data-theme` 속성으로 전환

## 2. 색 역할 규칙 (Design v2, 2026-10-16)

| 규칙 | 내용 |
|---|---|
| 보라 = 행동 | 채운 보라 버튼(`--color-action`)은 **화면당 1개**. 나머지는 테두리 버튼·텍스트 링크 |
| 빨강 = LIVE | `--color-live`는 LIVE 배지·점에만. 순위 하락 화살표는 중립 회색 |
| 재화색 = 아이콘·숫자 | Energy `--color-energy`, Spark `--color-spark`는 아이콘·숫자에만. 예외: 사이드 패널 Boost 주 버튼 |
| 선택 상태 | 보라 테두리 + 옅은 보라 면 하나로 통일(재화·금액·칩) |
| 컨테이너 | 컨테이너 안 컨테이너 금지. 내부 구분은 면 톤(`raised`) 또는 1px 선 하나 |
| 스폰서 | 스폰서 청록(`--color-sponsor-*`)은 후원 줄·행운 박스 버튼·무대에만. 보라(행동)·주황(Spark)과 섞지 않음 |
| 팀색 | 파트너 팀만 팀색 사용. 비제휴 팀은 팀색·로고 없음, RORR 보라 |

## 3. 값 요약

### 3-1. 웹 색 (다크 / 라이트)

| 토큰 | 다크 | 라이트 | 용도 |
|---|---|---|---|
| `--color-bg-page` | #14181F | #F0F2F5 | 페이지 |
| `--color-bg-surface` | #191F28 | #FFFFFF | 헤더·티커·카드 |
| `--color-bg-raised` | #1D2333 | #E9EEF4 | 올린 면(Boost 상자) |
| `--color-line` | #2A3040 | #CED6E6 | 1px 구분 |
| `--color-ink` | #F0F2F5 | #000000 | 본문 |
| `--color-ink-mute` | #9AA1B5 | #757B90 | 보조 |
| `--color-action` | #6F4CFF | #6F4CFF | 주 버튼 |
| `--color-action-ui` | #9CA3F1 | #6F4CFF | 선택 테두리·링크 |
| `--color-live` | #E5484D | #C10F0F | LIVE |
| `--color-energy` | #00B395 | #00B395 | Energy |
| `--color-spark` | #FF6F00 | #B84E00 | Spark |
| `--color-t1` | #E4002B | #C8102E | 파트너 팀(T1) |

### 3-2. 타이포

| 토큰 | 값 | 사용처(실측) |
|---|---|---|
| `--font-ui` | Pretendard Variable → Apple SD Gothic Neo → Malgun Gothic | 전체 |
| `--text-body` | 17px / 1.55 | 웹 본문 |
| `--text-panel-body` | 14px / 1.5 | 확장 본문 |
| `--text-display` | 51.84px · 800 · 자간 -1.81px · 줄간격 59px | 홈 히어로 h1 |
| `--text-page-title` | 40px · 700 · 자간 -0.8px · 줄간격 48px | 서브 페이지 제목 `.rhero h1` |
| `--text-entity-name` | 44px · 800 · 자간 -0.44px · 줄간격 44px | 패널 선수·팀 이름 |
| `--text-sm` / `--text-xs` | 13px / 12px | 보조 문구·칩(원본 사용 빈도 1·3위) |
| `--text-2xs` | 11px | 최소 크기 |

- 굵기: 700(268회) · 800(133) · 600(108) · 500(91). 400은 본문만
- 금지: 대문자 + 넓은 자간 라벨

### 3-3. 모서리·간격·크기

- 모서리 4단: 입력 8 · 내부 12 · 컨테이너 16 · 원형(버튼·칩·배지). 원본에 `4px`·`3px`·`14px`가 일부 남음 → 4단으로 정리
- 간격: 8px 기본(원본 `gap` 최다 8·6·10·12). 토큰은 4·6·8·10·12·16·20·24 + 섹션 72(모바일 56)
- 조작 요소 높이: 48(패널 Boost 주 버튼) · 44(기본) · 40(재화 선택·행운 박스 열기) · 36(확장 박스 버튼) · 28(확장 칩)
- 초점: 모든 조작 요소 `:focus-visible` 2px 링(`--focus-ring`)

### 3-4. 동작

| 토큰 | 값 | 비고 |
|---|---|---|
| `--ease-standard` | cubic-bezier(.2,.8,.2,1) | 원본 최다(24회) |
| `--ease-pop` | cubic-bezier(.2,1.6,.4,1) | 당첨 수량 튀어나옴 |
| `--dur-base` | 200ms | 원본 최다(20회). 그 외 150·300·350ms |
| `--dur-toast` | 2400ms | |
| `--dur-confirm-window` | 5000ms | Boost 두 번 누르기 유효 시간 |
| reduced motion | 0ms | 원본 `prefers-reduced-motion` 블록 18곳 — 반복·장식 애니메이션 정지 |

## 4. 웹·확장 불일치 — 결정 필요

| # | 항목 | 웹 | 확장 | 권고 |
|---|---|---|---|---|
| T-1 | 페이지 배경 | #14181F | #141016(붉은 기) | **웹 값으로 통일**. 확장은 중계 옆이라 더 어둡게 하려면 `--color-bg-page`를 공유하고 확장만 별도 토큰 1개 |
| T-2 | 1px 선 | #2A3040 | #313644 | 웹 값 통일 |
| T-3 | Spark 색 | #FF6F00(라이트 #B84E00) | #FFB547 | 공식 DS `--ds-accent` = #FF6F00 → **웹 값 통일**. 단 웹도 행운 박스 당첨 수량·입자에 #FFB547 하드코딩 → `--color-prize`로 분리 유지할지 결정 |
| T-4 | 선택 상태 | 보라 테두리 + 옅은 보라 면 | `--selected` #209FEE(공식 DS `--ds-selected`) | Design v2(보라 통일)가 나중 결정 → **보라 통일**. 확장 목업 수정 필요 |
| T-5 | 팀 오른쪽 색(다크) | #FF3A66 | #FE2054 | 라이트는 둘 다 #FE2054. 다크 대비용 밝힘 여부 결정 |
| T-6 | 행운 박스 열기 버튼 | 40px · 면 rgba(47,123,255,.12) | 36px · 면 .22 | 높이는 패널 폭 차이로 유지, 면 투명도는 하나로 |
| T-7 | 본문 크기 | 17px | 14px | **의도된 차이**(패널 폭 360px) — 유지 |

## 5. 원본 CSS의 알려진 문제 (이식 시 정리)

- CSS 약 349KB, `!important` 569개, `@keyframes` 86개. 기능 추가 때마다 파일 하단에 덮어쓴 구조 → **실측값 기준으로 이식**
- 같은 변수의 재정의: `:root` 토큰이 12·487·1299행 등 여러 블록에서 재정의됨. 최종값은 1299행 이후 "RORR Design System (2026-06) token layer"와 2422행 "Design v2" 블록
- 라이트 `--err-line`이 다크 값(#5A2229) 그대로 — 라이트에서 오류 테두리 대비 부족. 라이트 값 지정 필요
- 하드코딩 색: 스폰서 청록(`#7CF5FF` `#2F7BFF` `rgba(124,245,255,.6)`), 당첨 앰버(`#FFB547`), 등급 글자(`#F2C766` `#C9B8FF`), 순위 칩 빨강(`#E2012D`) — 토큰 파일에 이름을 붙였으니 컴포넌트에서 변수로 참조
- 브레이크포인트 21종 혼재 → `03-layout-responsive.md` §2의 5단으로 정리

# RORR 개발 핸드오프 패키지 — 웹 + 웹·확장 정합

- 작성일: 2026-10-17 · 작성: Pitch Interactive(사업·디자인) · 대상: 웹(Next.js 포팅)·확장(MV3) 개발 담당
- 기준 시점
  - 웹: `yhc-pie/rorr-hero` `main` **193dbc6** (`index.html` = `portal.html`)
  - 확장: `rorr-extension` 목업 v44(`2c3d579`) 기준으로 대조. **확장 상세 명세는 확장 저장소 `handoff/`(v45, cb425fb)가 원본** — 화면 명세·컴포넌트 CSS·i18n·캡처 18장 포함
  - 규칙: `docs/policy/boost-economy-policy.md` **v1.3**(2026-10-17)
- 상태: 데모(서버 연결 없음). 화면·동작·규칙 확정본이며, 미정 값은 설정 변수로 둠

---

## 1. 읽는 순서

| 순서 | 문서 | 내용 | 주 독자 |
|---|---|---|---|
| 1 | 이 문서 | 범위·기준 자료 우선순위·작업 원칙 | 전원 |
| 2 | [01-architecture-map.md](01-architecture-map.md) | 화면 지도·라우트·상태·서버 경계·웹/확장 공용 API | 웹·확장 리드 |
| 3 | [02-tokens.md](02-tokens.md) + [tokens/](tokens/) | 색·타입·모서리·간격·z-index·동작 토큰, 웹/확장 불일치 | 프론트엔드 |
| 4 | [03-layout-responsive.md](03-layout-responsive.md) | 그리드·폭 체계·브레이크포인트·패널 크기 | 프론트엔드 |
| 5 | [04-components.md](04-components.md) | 핵심 컴포넌트 명세(변형·속성·상태) | 프론트엔드 |
| 6 | [05-flows-interactions.md](05-flows-interactions.md) | Boost·큰 순간·행운 박스·재화 부족 흐름, 상태 전이, 동작 타이밍 | 프론트엔드·백엔드 |
| 7 | [06-rules-config.md](06-rules-config.md) | 정책 → 구현 규칙·서버 판정·설정 변수 | 백엔드 |
| 8 | [07-web-vs-extension.md](07-web-vs-extension.md) | 두 제품의 의도된 차이·공용 컴포넌트·정합 과제 | 웹·확장 리드 |
| 9 | [08-a11y-i18n-edge.md](08-a11y-i18n-edge.md) | 접근성·다국어·엣지 케이스·QA 체크리스트 | 전원 |
| 10 | [09-open-items.md](09-open-items.md) | 결정 대기·출시 블로커·알려진 부채 | 전원 |

### 1-1. 개발 설계 (2026-10-17 추가)

| 문서 | 내용 | 주 독자 |
|---|---|---|
| [10-system-architecture.md](10-system-architecture.md) | 전체 구성도, 계층 책임, 권장 기술(CTO 확정 필요), 모노레포 구조, 비기능 목표, 구축 순서 | 전원 |
| [11-flowcharts.md](11-flowcharts.md) | 플로차트 16종(Mermaid): 여정·Boost 판정·시퀀스·알림·행운 박스·충전·환불·광고·로그인·확장 매칭·퀴즈·기념·검수·발송·정산 | 전원 |
| [12-api-spec.md](12-api-spec.md) + [api/openapi.yaml](api/openapi.yaml) + [api/realtime-events.md](api/realtime-events.md) | REST 43개 오퍼레이션, 공통 규약·오류 코드·요청 한도·화면→API 매핑, SSE 이벤트 계약 | FE·BE |
| [13-data-model.md](13-data-model.md) + [db/](db/) | PostgreSQL 스키마(테이블 52·뷰 4), ERD, 불변식, **실행 가능한 참조 구현**(Boost·행운 박스)과 테스트 37건 | BE |
| [14-interaction-spec.md](14-interaction-spec.md) | 상태 기계 7종(Boost 상자·주 버튼·알림·행운 박스·헤더·실시간·확장 S0~S5), 카드 공개 분기, 이벤트→화면 표 | FE |
| [15-frontend.md](15-frontend.md) | 웹 라우트 트리·상태 계층·오버레이 매니저·공용 컴포넌트 인터페이스, 확장 구성·메시지 흐름·권한 | FE |
| [16-middle-tier.md](16-middle-tier.md) | BFF·게이트웨이(인증 통합·CSRF·멱등·한도·응답 필터)·실시간 게이트웨이·캐시 | FE·BE·인프라 |
| [17-backend.md](17-backend.md) | 도메인 모듈 16개, 핵심 트랜잭션(Boost·충전·환불·정산), 순간 감지 워커, 배치, 외부 연동, 관측 | BE |

## 2. 기준 자료 우선순위 (충돌 시)

1. **규칙** — 정책 v1.3. 화면·문구·데이터 모델이 정책과 다르면 정책을 따른다
2. **화면·동작** — 웹 `index.html`(193dbc6) 실측값(`getComputedStyle`). CSS 원문은 같은 셀렉터를 여러 번 덮어쓰므로 원문 위쪽 정의를 옮기지 않는다
3. **확장 화면** — 확장 목업 v44 + 확장 `docs/02`(기능 명세)·`docs/03`(화면·흐름)
4. **토큰** — 이 패키지 `tokens/tokens.css`. 웹·확장 불일치 항목은 `02-tokens.md` §4 결정 후 적용
5. **변경 이력** — 웹 `docs/HANDOFF.md` §5(커밋별), 확장 `docs/13-design-review.md`(버전별)

## 3. 이 패키지와 기존 문서의 관계

| 기존 문서 | 위치 | 이 패키지에서 |
|---|---|---|
| 포팅 핸드오프 노트 | rorr-hero `docs/HANDOFF.md` | 라우트 매핑·옮기지 않을 것·변경 이력 원본. 01·02에서 요약·인용 |
| 미구현·데모 현황 | rorr-hero `docs/IMPLEMENTATION-GAPS.md` | 서버 연동 필요 목록 원본. 01 §4에서 요약 |
| 환불 개발 명세 | rorr-hero `docs/specs/refund.md` | 그대로 사용(형식: 규칙 → 설정값 → 데이터 → API → 화면 → 완료 기준) |
| 법적 고지 초안 | rorr-hero `docs/legal/*.md` | 그대로 사용. `[대괄호]` 값 확정 전 게시 금지 |
| 확장 기획 문서 00~15 | rorr-extension `docs/` | 확장 기능·흐름 원본. 07에서 웹과 대조 |
| **확장 핸드오프 패키지** | rorr-extension `handoff/`(규칙·화면 명세·토큰·컴포넌트·상태 로직·QA·`css/`·`i18n-ko.json`·`screens/`) | 확장 구현은 그 패키지 기준. 이 패키지는 웹 전체 + 두 제품 정합(02 §4·07·09)을 담당 |
| 정책 | rorr-hero `docs/policy/boost-economy-policy.md` (원본은 사업 담당 관리) | 06에서 구현 규칙으로 변환. 문구·조항은 정책 원문이 우선 |

## 4. 작업 원칙

- **판정은 서버**: 재화 차감·카드 발급·배지 단계·포인트·행운 박스 결과·순위는 전부 서버. 클라이언트(웹·확장)는 표시만
- **웹·확장 같은 원장·같은 API**: 확장 전용 API는 매칭·순간 스트림·Muse 대사 3종으로 한정
- **미정 값은 코드에 고정하지 않음**: `06-rules-config.md` §6 변수표대로 설정에서 읽기
- **문구는 i18n 키로**: 원본의 `KO` 사전(영문 문장 → 국문, 약 1,050개)은 문구 원본으로만 참조. DOM 순회 번역 방식은 옮기지 않음
- **데모 장치는 옮기지 않음**: 샘플 데이터 엔진, `localStorage` 상태, 스폰서 미리보기 토글(`?sponsor=`·`rorr-sp`), 행운 박스 결과 강제(`?box=`), 좌하단 데모 칩
- **확인 방법**: 각 화면을 원본과 같은 상태로 띄워 1440·390px, KO·EN, 다크·라이트에서 실측 비교

## 5. 문의

- 규칙·문구·우선순위: 사업 담당(Charles, CBO)
- 화면·토큰 해석: 디자인 담당
- 정책 원문 변경은 사업 담당만 수행. 개발 중 정책과 충돌하는 요구가 생기면 구현 전에 문의

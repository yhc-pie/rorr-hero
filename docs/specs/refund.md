# 개발 명세 · Energy 환불 (정책 §1-1)

- 작성일: 2026-10-15 · 상태: 정책 결정 완료(수수료 5%·최소 1,000원, 임시), 약관 문구는 법률 검토 후 확정
- 기준: `docs/policy/boost-economy-policy.md` §1-1(환불), §8(배분)
- 규칙과 숫자가 이 문서와 정책 문서 사이에서 다르면 **정책 문서가 우선**

---

## 1. 규칙 요약

- 7일 이내 청약철회: 미사용 유료분 전액, 수수료 0
- 7일 이후: 미사용 유료분 환불, 수수료 5%(최소 1,000원) 공제
- Boost에 사용한 Energy·보너스 Energy·Spark: 환불 없음
- 사용 순서: 보너스 → 유료, 같은 종류는 만료일 빠른 묶음부터
- 파트너 배분: Boost에 사용된 **유료** Energy만 대상

## 2. 설정값 (코드 하드코딩 금지)

| 키 | 값 | 비고 |
|---|---|---|
| `REFUND_WINDOW_DAYS` | 7 | 구매 시각 기준 |
| `REFUND_FEE_RATE` | 0.05 | 7일 경과 후 적용 (임시) |
| `REFUND_FEE_MIN_KRW` | 1000 | 요율 금액과 비교해 큰 값 적용 |
| `PAID_EXPIRY_YEARS` | 5 | 유료 Energy |
| `BONUS_EXPIRY_DAYS` | 365 | 보너스 Energy |
| `REFUND_SLA_BUSINESS_DAYS` | 3 | 접수 후 환급 기한 |
| `PARTNER_SHARE_BP` | 7000 (T1) | `partner_agreements`에서 조회 |

## 3. 데이터

**energy_lots** (구매·지급 1건 = 1행)

| 컬럼 | 설명 |
|---|---|
| `id, user_id` | |
| `kind` | `paid` / `bonus` |
| `order_id` | 유료면 결제 주문, 보너스면 지급 사유 ID |
| `qty, remaining` | 지급 수량, 남은 수량 |
| `unit_price_krw` | 유료 1 Energy당 결제 환산가 (결제 금액 ÷ 유료 수량). 보너스는 0 |
| `purchased_at, expires_at` | |
| `status` | `active` / `refunded` / `expired` / `cancelled` |

**wallet_ledger** (append-only): 모든 증감을 `lot_id`와 함께 기록. 사유 `purchase / bonus / boost / refund / expire / cancel / adjust`

**boost_lot_usage**: Boost 1건이 어느 묶음에서 몇 개를 썼는지 기록 → 정산 계산 근거
`boost_id, lot_id, qty, unit_price_krw`

**refunds**

| 컬럼 | 설명 |
|---|---|
| `id, user_id, lot_ids[]` | |
| `type` | `withdrawal`(7일 이내) / `balance`(7일 경과) / `minor_cancel` / `service_end` |
| `gross_krw, fee_krw, net_krw` | |
| `method` | `pg_cancel` / `bank_transfer` |
| `status` | `requested → approved → processing → done` / `rejected` |
| `requested_at, done_at, reason` | |

**settlements**: 월별·팀별 `sum(boost_lot_usage.qty × unit_price_krw)` 중 `kind=paid`만. 정산 후 취소된 금액은 `adjust_krw`(음수)로 다음 달에 반영

## 4. 계산 규칙

- **차감 순서**: Boost 시 `bonus` 묶음을 `expires_at` 오름차순으로 먼저 쓰고, 부족분을 `paid` 묶음에서 `expires_at` 오름차순으로 사용
- **환불 견적** (묶음별):
  - `refundable = remaining × unit_price_krw` (paid만)
  - 구매 후 7일 이내 → `fee = 0`
  - 7일 경과 → `fee = max(round(refundable × REFUND_FEE_RATE), REFUND_FEE_MIN_KRW)`
  - 수수료 면제(`fee = 0`): 7일 이내, 서비스 종료, 미성년 취소, 회사 귀책(관리자 처리 시 사유 코드 `company_fault`)
  - `net = refundable − fee`가 0 이하이면 신청 불가(견적 API가 `refundable: false, reason: 'below_fee'` 반환)
- **미성년 취소**: 해당 주문 전체 취소(사용분 포함). 사용된 유료분의 기정산 금액은 `settlements.adjust_krw`로 차감
- **서비스 종료**: 미사용 유료분 전액, `fee = 0`

## 5. API

| 엔드포인트 | 요청 | 응답 |
|---|---|---|
| `GET /me/wallet` | — | 유료·보너스 잔액, 묶음별 남은 수량·만료일 |
| `GET /me/refund-quote` | `lot_ids?` | 묶음별 환불 가능액, 수수료, 실수령액, 적용 유형(7일 이내/이후), 환급 방법 |
| `POST /refunds` | `lot_ids, method, bank_account?` + `Idempotency-Key` | `refund_id, status, net_krw, expected_by` |
| `GET /me/refunds` | — | 환불 내역·상태 |
| `POST /admin/refunds/{id}/approve` · `/reject` | `reason?` | 상태 |
| `POST /payments/toss/webhook` | PG 취소 결과 | 원장 반영 |

- 환불 요청이 들어오면 해당 묶음의 `remaining`을 즉시 잠가 동시 Boost 사용을 막음
- 결제 취소(PG) 실패 시 계좌 환급으로 전환

## 6. 화면

- **충전 화면**: "구매 후 7일 이내 미사용분은 전액 환불, 이후에는 수수료 공제 후 환불" + 환불 정책 링크 (문구 확정본 별도 전달)
- **Boost 확인 화면**: "보낸 Boost는 취소할 수 없어요" (현재 사이트에 일부 반영)
- **내 Boost › Energy**: 유료·보너스 잔액 분리, 만료 예정 표시, "환불 신청" → 견적 확인 → 신청
- **환불 정책 페이지**: 푸터 "환불 정책" 링크 대상 (현재 `#`)
- 문구는 개발에서 작성하지 않음. 법률 검토본을 i18n 키로 전달

## 7. 완료 기준 (테스트 케이스)

| # | 상황 | 기대 결과 |
|---|---|---|
| 1 | 10,000원(유료 100) 구매, 3일째, 미사용 | 10,000원 환불, 수수료 0 |
| 2 | 10,000원(유료 100) 구매, 3일째, 40 사용 | 6,000원 환불, 수수료 0 |
| 3 | 10,000원(유료 100) 구매, 10일째, 미사용 | 수수료 1,000원 → 9,000원 환불 |
| 3-1 | 50,000원(유료 500) 구매, 10일째, 미사용 | 수수료 2,500원 → 47,500원 환불 |
| 3-2 | 10일째, 유료 잔액 8개(단가 100원 = 800원) | 수수료 공제 후 0원 이하 → 신청 불가, 사유 안내 |
| 3-3 | 10일째, 서비스 장애로 회사 귀책 처리 | 수수료 0 |
| 4 | 유료 100 + 보너스 20 패키지, 30 사용 | 보너스 20 먼저 소진 → 유료 90 남음 → 유료 90 기준 환불 |
| 5 | 보너스만 15 남음 | 환불 0원, 신청 버튼 비활성 |
| 6 | 보너스 지급 후 366일 | 보너스 만료 처리, 원장 `expire` 기록 |
| 7 | 미성년 결제 취소, 60 사용·그중 40 Boost(T1) 정산 완료 | 주문 전액 취소, 다음 달 T1 정산에서 40 × 단가 × 70% 차감 |
| 8 | 환불 요청 처리 중 Boost 시도 | 잠긴 묶음은 사용 불가, 다른 묶음 또는 잔액 부족 안내 |
| 9 | Boost 50 사용(보너스 20 + 유료 30) | T1 정산 대상은 유료 30 × 단가만 |
| 10 | 같은 환불 요청 2회 전송 | 멱등 키로 1회만 처리 |
| 11 | PG 취소 실패 | 계좌 환급으로 전환, 상태 `processing` 유지 |
| 12 | 서비스 종료 공지 후 환불 | 미사용 유료분 전액, 수수료 0 |

- 결제수단: 출시 시 휴대폰 결제는 제공하지 않음(정책 §1-1)

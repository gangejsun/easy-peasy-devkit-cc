<!-- epcc-pack-ledger: backend/supabase v3.12.0 -->

# supabase 팩 — 심볼 원장

## provides — 없다

**이 팩은 심볼 표면이 없다.** 두 리소스가 담은 것은 인라인 스니펫 형태의 쿼리·정책 패턴
이고 최상위 `export`가 하나도 없다 (추출 시점 실측: `export default` 1건만, 그것도 예제
파일 안). 이는 결함이 아니라 팩의 **형태**다.

| 팩 형태 | 예 | 특징 |
| --- | --- | --- |
| 심볼 표면형 | `backend/aws-container` (25개 export) · `frontend/*` | 프로젝트 모듈을 정의한다. 이음매가 그것을 import한다 |
| **패턴 지식형** | `backend/supabase` | 벤더 SDK를 **어떻게 쓰는가**를 가르친다. 정의하는 프로젝트 모듈이 없다 |

BaaS 축이 패턴 지식형이 되는 것은 자연스럽다 — 데이터 액세스 모듈 자체를 벤더가
제공하므로 프로젝트가 정의할 것은 그것을 **감싸는 층**이고, 그 층의 형태는 호스트
런타임(프론트엔드 축)이 정한다. 그래서 이음매 소유다.

이 구분은 게이트에 실질적 함의가 있다: **`provides`가 빈 팩에서 원장 역방향 검사
(원장에 없는 export 찾기)를 돌리면 전부 위반으로 잡힌다.** `pack.json`의
`symbolSurface: false`를 보고 그 검사를 건너뛰어야 한다.

## requires — 이음매가 제공해야 한다

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `createClient` | 프로젝트 | `Promise<SupabaseClient<Database>>` — 요청 단위, 쿠키 결합 | 쿠키에 접근하는 방법이 호스트 런타임의 함수. 이 조합에서는 `next/headers` |
| `fromSupabaseError` | 프로젝트 | PostgREST/SQLSTATE 오류 → HTTP 응답 | 상태 코드·봉투가 와이어 계약의 함수 |
| `Database` | 생성물 | `supabase gen types`가 만든 타입 | **이 팩이 생성 절차를 소유**하지만(`database-patterns.md`) 산출 파일 자체는 프로젝트의 것이다 |

## 추출 시 이 팩에서 제거한 것

| 옮긴 것 | 원래 위치 | 간 곳 | 이유 |
| --- | --- | --- | --- |
| §Server client (요청 단위·쿠키 결합) | `database-patterns.md` L18-58 | 이음매 `server-client.md` | 쿠키 접근이 호스트 런타임의 함수 |
| Layer 2·3 (Route Handler·Server Action 테스트) | `testing.md` L51-160 | 이음매 `handler-testing.md` | 핸들러를 직접 호출하는 테스트는 핸들러 형태에 종속 |
| `validation-and-errors.md` 전체 | — | 이음매 | Zod 배선·에러 봉투·env 검증이 **문단 단위로** Next.js와 얽혀 있어 절 경계로 갈리지 않았다. 통째로 이음매가 흡수 |
| `edge-and-operations.md` 전체 | — | 이음매 | 미들웨어·Edge 런타임·CORS·보안 헤더는 Supabase가 아니라 호스트의 관심사다 |

## 이 팩이 얻은 것

| 받은 것 | 원래 위치 | 이유 |
| --- | --- | --- |
| §생성 타입 (`supabase gen types`) | `nextjs-frontend-guide/typescript-standards.md` §7 | DB 스키마에서 타입을 만드는 것은 프론트엔드가 아니라 이 축의 지식이다 |

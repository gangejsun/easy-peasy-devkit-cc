<!-- epcc-pack-ledger: backend/aws-container v3.12.0 -->

# aws-container 팩 — 심볼 원장

게이트가 기계 대조하는 표다. `provides`는 이 팩이 정의하므로 **이음매가 새로 정의하면
중복**이고, `requires`는 이 팩이 소비하지만 정의하지 않으므로 **이음매가 반드시 제공해야**
한다. 라이브러리 API는 대상이 아니다 — 프로젝트 로컬 심볼만 싣는다.

## provides — 이 팩이 정의한다

| 심볼 | 정의 파일 | 성격 |
| --- | --- | --- |
| `pool` · `db` | data-access.md | pg Pool + Drizzle 인스턴스 (싱글턴) |
| `tasks` · `tags` | data-access.md | Drizzle 테이블 정의 (마이그레이션의 원본) |
| `Task` · `NewTask` | data-access.md | 테이블에서 추론한 도메인 타입 |
| `findOwnedTask` | data-access.md | 소유권 필터 조회 |
| `listOwnedTasks` | data-access.md | 커서 목록 조회 |
| `updateOwnedTask` · `deleteOwnedTask` | data-access.md | 영향 행 확인 변이 |
| `replaceTaskTags` | data-access.md | 트랜잭션 변이 |
| `env` · `publicEnvKeys` | input-validation.md | 검증된 환경변수 단일 진입점 |
| `CreateTaskInput` · `UpdateTaskInput` | input-validation.md | 요청 DTO |
| `ListTasksQuery` · `TaskIdParam` | input-validation.md | 쿼리·경로 DTO |
| `jsonBody` · `queryParams` · `pathParam` | input-validation.md | 파싱 헬퍼 |
| `ObjectStorage` | portability-boundaries.md | 저장소 포트 (앱이 보는 유일한 타입) |
| `log` · `logBootConfig` · `requestContext` | portability-boundaries.md | 구조화 로깅 |
| `testEnv` | testing.md | 테스트 환경변수 픽스처 |

## requires — 이음매가 제공해야 한다

**종류를 구분한다.** `프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 이음매가
고른 패키지에서 오므로 import 문에 이름이 등장하는지로 판정한다. 이 팩의 requires는
전부 프로젝트 심볼이다.

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `app` | 프로젝트 | Hono 앱 인스턴스 (서브 앱 마운트 지점) | 라우트 조립 순서가 조합의 함수 |
| `AppEnv` | 프로젝트 | `c.get`/`c.set` 타입 바인딩 | 컨텍스트에 싣는 것이 인증 방식에 달렸다 |
| `AppError` | 프로젝트 | `status`·`code`·`message`를 갖는 에러 | 에러 코드표가 와이어 계약의 함수 |
| `onError` | 프로젝트 | 전역 에러 → 봉투 매핑 | 응답 봉투가 와이어 계약의 함수 |
| `requireAuth` | 프로젝트 | 인증 미들웨어 | 토큰 검증 방식이 백엔드 인증 차원의 함수 |
| `AuthUser` | 프로젝트 | 검증된 주체(`sub` 등) | 위와 같다 |
| `safeReturnPath` | 프로젝트 | 복귀 경로 검증 | 로그인 흐름이 프론트엔드 축과의 계약 |
| `isUniqueViolation` | 프로젝트 | SQLSTATE → 도메인 에러 판별 | 409 매핑이 와이어 계약의 함수 |
| `insertTask` | 프로젝트 | 생성 쿼리 | **비대칭**: 조회·수정·삭제 쿼리는 팩이 소유하는데 생성만 이음매(완전 예제)에 있다. 원본 `react-aws-backend-guide`에서 승계한 구조이며 이번 재배치가 만든 것이 아니다 |

## 알려진 공백 (추출 시점에 승계, 수리하지 않음)

| 항목 | 상태 |
| --- | --- |
| `insertTask`의 소재 | `data-access.md`가 CRUD 중 C만 빠뜨렸다. 팩으로 옮기는 것이 옳으나 본문 개선은 이번 범위 밖이다 — 지금은 `requires`로 선언해 조립 후 미정의가 되지 않게 한다 |
| 이음매 완전 예제의 재정의 | `complete-example.md`가 `tasks`·`Task`·`findOwnedTask` 등을 **같은 파일 경로·같은 시그니처로** 다시 보여준다. 자기완결 관통 예제라는 의도이며 시그니처가 같으므로 중복 정의 FAIL은 아니다. 게이트는 원장의 소비처로 인정한다 |

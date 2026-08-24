<!-- epcc-pack-ledger: backend/fastapi v3.14.0 -->

# fastapi 팩 — 심볼 원장 (L0 선언본)

저작 전에 메인 세션이 선언한 계약이다. 클러스터를 갈라 병렬로 써도 중복 정의와 **시그니처
추측**이 생기지 않게 하는 유일한 장치다.

## provides — 이 팩이 정의한다

**「형태」 열은 의무다.** 소유 파일만 배정하고 형태를 비우면 형제 클러스터가 시그니처를
추측한다 — 실측(node-api)에서 `getTask(ownerId, id)`를 다른 클러스터가 `getTask(id, ownerId)`로
불렀고 두 인자가 모두 `string`이라 타입 검사도 게이트도 잡지 못해 모든 단건 조회가 404가
됐다. 인자 **순서** · 반환 · 실패 시 던지는 것 · **호출자가 배선해야 하는 것**을 함께 적는다.

**「정의 파일」은 문서의 소유이지 코드의 경로가 아니다.** 소스 경로가 자명하지 않은
심볼에는 형태 열에 **경로를 못박는다** — fastapi 실측에서 한 클러스터가 `Task`를
`app/db/models.py`에서 import했는데 정의는 `app/db/tasks.py`에 있었고, **게이트도 못 잡았다**
(원장 검사는 리소스 파일만 본다). 잡은 것은 타입체커 실행이었다.

**이 팩에서 특히 위험한 자리**: `owner_id`와 `task_id`가 **둘 다 `UUID`**다. 순서를 바꿔도
파이썬은 물론 pyright도 잡지 못한다. 전 함수에서 **`session` → `owner_id` → `task_id`** 순서를
고정한다. 그리고 **필드 소비 의무**를 형태에 적는다 — 시그니처가 맞아도 인자의 *내용*을
안 쓰면 같은 부류의 치명 결함이 된다(aws-serverless 실측: `create_task`가 `status`를 버렸다).

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `Base` | data-access.md | **`app/db/base.py`** — `class Base(DeclarativeBase)` — `MetaData`에 명명 규칙을 건다(제약 이름이 Alembic 자동생성에 필요하다) | 선언 기반 |
| `Task` | data-access.md | **`app/db/tasks.py`** — `class Task(Base)` — `id: Mapped[UUID]`(PK, 서버 기본값 아님 — 앱이 만든다) · `title: Mapped[str]` · `status: Mapped[TaskStatus]` · `owner_id: Mapped[UUID]`(**복합 인덱스의 선두 컬럼이다 — 단독 `index=True`를 주지 않는다**) · `created_at: Mapped[datetime]`(tz-aware). **`(owner_id, created_at, id)` 복합 인덱스**가 키셋 페이지네이션의 전제다 | ORM 모델 |
| `engine` | data-access.md | **`app/db/session.py`** **여기가 유일한 정의다.** 풀 값을 다른 파일이 다시 쓰면 두 벌이 갈린다 — `AsyncEngine` — 모듈 최상위에서 만든다. `pool_size`·`max_overflow`·`pool_pre_ping`을 명시한다 | 엔진 |
| `session_factory` | data-access.md | **`app/db/session.py`** — `async_sessionmaker[AsyncSession]` — `expire_on_commit=False`. **켜 두면 커밋 후 속성 접근이 다시 쿼리를 날려 응답 직렬화 중 I/O가 난다** | 세션 팩토리 |
| `get_session` | data-access.md | **`app/db/session.py`** — `async def get_session() -> AsyncIterator[AsyncSession]` — FastAPI 의존성. **요청당 세션 하나**를 열고 성공이면 커밋, 예외면 롤백한 뒤 닫는다. 라우터는 `Depends(get_session)`로만 받는다 | 세션 의존성 |
| `list_tasks` | data-access.md | `async def list_tasks(session: AsyncSession, owner_id: UUID, q: TaskQuery) -> tuple[list[Task], str \| None]` — **소유자가 두 번째다.** 반환은 `(항목, 다음 커서)`. `WHERE owner_id = :owner_id`가 **유일한 경계**다 | 목록 |
| `get_task` | data-access.md | `async def get_task(session: AsyncSession, owner_id: UUID, task_id: UUID) -> Task \| None` — **두 UUID의 순서가 생명이다.** 없으면 `None`(예외 아님) | 단건 |
| `create_task` | data-access.md | `async def create_task(session: AsyncSession, owner_id: UUID, data: TaskCreate) -> Task` — **`data`의 `title`과 `status`를 모두 옮긴다.** `status`를 하드코딩하면 클라이언트가 보낸 값이 조용히 사라진다(aws-serverless 실측 치명). `owner_id`만 세션에서 온다. 중복은 `AppError('CONFLICT')` | 생성 |
| `update_task` | data-access.md | `async def update_task(session: AsyncSession, owner_id: UUID, task_id: UUID, patch: dict[str, Any]) -> Task` — `patch`는 **이미 `exclude_unset=True`로 뽑은 것**이다(라우터의 의무). 비었으면 `AppError('VALIDATION_FAILED')`. 영향 행 0이면 `AppError('NOT_FOUND')` | 수정 |
| `delete_task` | data-access.md | `async def delete_task(session: AsyncSession, owner_id: UUID, task_id: UUID) -> None` — **`rowcount`를 확인한다.** 0이면 `AppError('NOT_FOUND')`. 확인하지 않으면 남의 것을 지우라는 요청도 204가 된다 | 삭제 |
| `encode_cursor` | data-access.md | `def encode_cursor(created_at: datetime, task_id: UUID) -> str` — 불투명 문자열. 내부 정렬 키를 와이어 계약으로 만들지 않는다 | 커서 인코딩 |
| `decode_cursor` | data-access.md | `def decode_cursor(cursor: str) -> tuple[datetime, UUID]` — 실패는 `AppError('VALIDATION_FAILED')`. **커서는 신뢰 입력이 아니다** | 커서 디코딩 |
| `Settings` | input-validation.md | `class Settings(BaseSettings)` — `DATABASE_URL` · `LOG_LEVEL` · `ENV`. `model_config = SettingsConfigDict(env_file=…, extra='forbid')` | 환경 스키마 |
| `settings` | input-validation.md | `Settings` 인스턴스 — **모듈 최상위에서 만든다.** 검증 실패가 부팅 실패여야 한다(요청 시점에 터지면 절반이 살아 있는 서버가 된다) | 검증된 환경 값 |
| `TaskStatus` | input-validation.md | **`app/schemas/task.py`** — `class TaskStatus(StrEnum)` — 멤버는 `OPEN`·`DONE`이고 **값은 소문자 `"open"`·`"done"`이다.** 와이어·DB·테스트 단언에 쓰는 것은 **값**이지 멤버 이름이 아니다 — 이 칸을 비워 두었더니 형제 클러스터가 `== "DONE"`으로 단언해 대표 차단 증명 테스트가 항상 빨갰다(감사 C 실측). 스키마·모델·쿼리가 같은 열거를 재사용한다 | 상태 열거 |
| `TaskCreate` | input-validation.md | `class TaskCreate(BaseModel)` — `title: str`(1~200) · `status: TaskStatus = TaskStatus.OPEN`. `extra='forbid'` | 생성 본문 |
| `TaskUpdate` | input-validation.md | `class TaskUpdate(BaseModel)` — `title: str \| None = None` · `status: TaskStatus \| None = None`. **선택 필드의 기본값은 `None`만이다** — `None`이 아닌 기본값을 두면 `model_dump()`가 그것을 실어 부분 수정이 나머지 필드를 덮어쓴다(pack-smoke가 FAIL로 막는다) | 수정 본문 |
| `TaskQuery` | input-validation.md | **`app/schemas/task.py`** — `class TaskQuery(BaseModel)` — `limit: int = 20`(1~100) · `cursor: str \| None` · `status: TaskStatus \| None` · **`extra='forbid'`**. 라우터는 **`Annotated[TaskQuery, Query()]`로 받는다** — `Depends()`는 `extra='forbid'`를 무시해 미지 쿼리 파라미터가 조용히 통과한다(C1 실행 확인) | 목록 쿼리 |
| `TaskOut` | input-validation.md | `class TaskOut(BaseModel)` — `model_config = ConfigDict(from_attributes=True)`. **ORM 모델을 그대로 반환하지 않는다** — 응답 스키마가 없으면 나중에 추가한 컬럼이 조용히 새어 나간다 | 응답 스키마 |
| `ERROR_STATUS` | error-handling.md | **`app/http/errors.py`** — `dict[str, int]` — 도메인 코드 → HTTP 상태. **유일한 매핑표** | 상태 매핑 |
| `to_app_error` | error-handling.md | **`app/http/errors.py`** — `def to_app_error(exc: BaseException) -> AppError` — 예외 핸들러가 **반드시 먼저 호출한다**. 모르는 것은 전부 `INTERNAL`로 접는다(원본 메시지에 DSN·테이블명이 들어 있다) | 정규화 |
| `is_unique_violation` | error-handling.md | **`app/db/errors.py`**(HTTP를 모른다 — `db/`가 부르므로 `http/` 아래에 두면 계층이 깨진다) — `def is_unique_violation(exc: BaseException) -> bool` — `IntegrityError`의 **SQLSTATE `23505`**로 판정한다. 메시지 문자열 매칭은 로케일·드라이버에 따라 깨진다 | 중복 판별 |
| `is_foreign_key_violation` | error-handling.md | **`app/db/errors.py`** — `def is_foreign_key_violation(exc: BaseException) -> bool` — SQLSTATE **`23503`** | 참조 무결성 판별 |
| `field_errors` | error-handling.md | **`app/http/errors.py`** — `def field_errors(exc: ValidationError \| RequestValidationError) -> dict[str, list[str]]` — `loc`을 점으로 이어 키로 쓴다. **배열 인덱스를 지우지 않는다** — 몇 번째 항목이 틀렸는지가 사라지면 폼이 오류를 못 붙인다 | 필드 오류 |
| `create_app` | project-structure.md | **`app/factory.py`** — `def create_app() -> FastAPI` — **요청을 받지 않는다.** 라우터 마운트 + 예외 핸들러 등록 + lifespan 부착만 한다. `install_error_handlers(app)`(이음매)를 **반드시 부른다** | 앱 조립 |
| `lifespan` | project-structure.md | **`app/factory.py`** **여기가 유일한 정의다** — `@asynccontextmanager async def lifespan(app: FastAPI) -> AsyncIterator[None]` — 기동 시 풀 예열, 종료 시 `await engine.dispose()`. **`create_app`이 `FastAPI(lifespan=lifespan)`로 넘겨야 한다** — 부착하지 않으면 조용히 안 돈다 | 수명 주기 |
| `configure_logging` | operations.md | **`app/obs/logging.py`** — `def configure_logging(level: str) -> None` — **`create_app`보다 먼저**, 모듈 임포트 시점에 부른다. 나중에 부르면 uvicorn이 이미 만든 핸들러가 남아 로그가 두 번 찍힌다 | 로깅 설정 |
| `health_router` | operations.md | `APIRouter` — **`app/obs/health.py`에 둔다**(`logging.py`가 아니다: `readyz`가 `engine`을 쓰므로 합치면 부팅 시점 로깅 설정이 DB 모듈을 끌어온다). `GET /healthz`(프로세스 생존, DB 안 본다) · `GET /readyz`(`SELECT 1`). **둘을 합치면 DB 순단에 재시작 루프가 돈다** | 헬스체크 |
| `app_client` | testing.md | **`tests/conftest.py`** — `async def app_client(app: FastAPI) -> AsyncIterator[AsyncClient]` — `ASGITransport`로 앱을 **네트워크 없이** 직접 태운다. `base_url='http://test'` 필수(httpx가 상대 URL을 못 만든다) | 테스트 클라이언트 |
| `override_user` | testing.md | **`tests/conftest.py`** — `def override_user(app: FastAPI, user: AuthUser) -> None` — `app.dependency_overrides[current_user]`를 채운다. **테스트마다 되돌린다** — 안 되돌리면 다음 테스트가 앞 사용자로 돈다 | 의존성 오버라이드 |

## requires — 이음매가 제공해야 한다

`프로젝트`는 이음매가 정의해야 하고, `라이브러리`는 import 문에 이름이 등장하는지로
판정한다. **팩이 호출하는 심볼에는 호출 시그니처를 적는다** — 적지 않으면 이음매가
인자 순서를 추측한다(게이트가 FAIL로 막는다).

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `AppError` | 프로젝트 | `AppError(code: str, message: str, details: dict[str, list[str]] \| None = None)` — **앞 두 인자가 모두 `str`이니 순서가 생명이다(코드가 먼저).** 코드표에 반드시 포함: `VALIDATION_FAILED` · **`UNAUTHENTICATED`**(`current_user`가 던진다 — 빠지면 401이 500으로 나간다) · `FORBIDDEN` · `NOT_FOUND` · `CONFLICT` · `INTERNAL`. **`app/errors.py`에 둔다** — `app/http/` 아래가 **아니다**. `app/http/errors.py`가 `fastapi`를 import하므로 거기 두면 `import app.db.tasks`가 fastapi를 전이로 끌어와 계층 규율이 깨진다(감사 A 실행 확인) | 에러 코드표와 필드 오류 형태가 와이어 계약의 함수 |
| `install_error_handlers` | 프로젝트 | `def install_error_handlers(app: FastAPI) -> None` — `AppError` · `RequestValidationError` · `Exception` 셋에 핸들러를 건다. **`to_app_error`로 먼저 정규화하고 `ERROR_STATUS`로 상태를 정한다.** `create_app`이 부른다 | 응답 봉투가 와이어 계약의 함수 |
| `current_user` | 프로젝트 | `async def current_user(...) -> AuthUser` — FastAPI 의존성. 실패는 `AppError('UNAUTHENTICATED')`. `app/http/auth.py`에 둔다. **라우터는 `Depends(current_user)`로만 받는다** — 토큰을 직접 파싱하는 라우터가 하나라도 있으면 경계가 둘이 된다 | 토큰 검증 방식이 조합의 함수 |
| `AuthUser` | 프로젝트 | 최소 `{ id: UUID, roles: list[str] }` — `id`가 `owner_id`가 된다 | 위와 같다 |
| `auth_for` | 프로젝트 | `def auth_for(owner_id: UUID, roles: list[str] \| None = None) -> AuthUser` — 테스트가 `override_user`에 넘길 주체를 만든다. **동기** | 클레임 형태가 인증 방식의 함수 |
| `api_router` | 프로젝트 | `APIRouter` — 도메인 라우터를 모아 `create_app`이 `include_router(api_router, prefix='/api')`로 붙인다 | 라우트 구성이 조합의 함수 |

## 알려진 공백

없다. 축-지역 필수 슬롯 6개가 모두 채워지고, 비어 보이는 것(API 엔드포인트 · 인증 경계 ·
완전 예제)은 `pack.json`의 `seamSlots`가 선언한 이음매의 몫이다.

## 예제에 등장하는 앱 심볼 (프로젝트가 만든다)

`provides`도 `requires`도 아니다. 예제에서 이름만 등장하므로 조립 후에도 정의가 없는 것이 정상이다.

**함수·클래스만이 아니라 컬럼·필드도 등재한다.** 예제가 도입한 컬럼이 어디에도 선언되지
않으면 독자가 그것을 모델에 있는 컬럼으로 읽고, 그 상태로 `alembic check`를 돌리면
드리프트가 난다(감사 C 실측).

| 이름 | 등장 | 성격 |
| --- | --- | --- |
| `TaskService` | project-structure.md (계층 예시) | 서비스 계층 예시 |
| `priority` | migrations.md (확장-축소 예시) | **예제 전용 컬럼.** 모델(`Task`)에 없다 — §4가 확장 단계로 더하는 컬럼을 §5의 백필이 채우는 흐름을 보이기 위한 것이다 |

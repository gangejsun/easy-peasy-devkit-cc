<!-- epcc-pack: backend/fastapi v3.14.0 -->
# 프로젝트 구조 — 계층 경계와 앱 조립

`create_app`과 `lifespan`, 그리고 **무엇이 무엇을 부르는가**를 소유한다. 데이터 계층은
`data-access.md`, 스키마는 `input-validation.md`, 에러 표는 `error-handling.md`,
마이그레이션은 `migrations.md` 가 소유한다.

에러 모듈은 **계층에 따라 셋으로 갈라져 있다.** `AppError` 가 `app/http/` 에 있으면
`import app.db.tasks` 한 줄이 fastapi 를 전이로 끌어와 계층이 무너진다(§1).

| 심볼 | 파일 | 프레임워크를 import 하는가 |
| --- | --- | --- |
| `AppError` | `app/errors.py` (**이음매 소유**) | 아니다 — 모든 계층이 던진다 |
| `is_unique_violation` · `is_foreign_key_violation` | `app/db/errors.py` | 아니다 — SQLAlchemy 만 |
| `ERROR_STATUS` · `to_app_error` · `field_errors` | `app/http/errors.py` | 그렇다 — `RequestValidationError` |

`app/errors.py` · `app/http/handlers.py` · `app/http/auth.py` · `app/http/routers.py` 는
**이음매 소유**다. 팩은 부르기만 하고, 조립 전에 정의가 없는 것이 정상이다.

## 1. 결정 트리 — 이 코드는 어느 계층인가

| 이 코드가 하는 일 | 두는 곳 | 못 하는 것 |
| --- | --- | --- |
| 상태 코드·헤더·쿠키·`Request`를 다룬다 | `app/http/` (라우터) | SQL 을 짜지 않는다 |
| "누가 무엇을 할 수 있는가"를 정한다 | `app/services/` | `Request`를 받지 않는다 |
| `select`/`update`/`delete` 를 만든다 | `app/db/` | `HTTPException` 을 던지지 않는다 |
| 프로세스 환경을 읽는다 | `app/settings.py` **한 곳** | 요청 시점에 읽지 않는다 |
| 프로세스 수명에 한 번 일어난다 | `lifespan` (`app/factory.py`) | 요청 핸들러에서 하지 않는다 |
| 라우트·핸들러·미들웨어를 붙인다 | `create_app` | 요청 인자를 받지 않는다 |

**계층은 한 방향이다**: `routers → services → db`. 리포지토리가 `HTTPException` 을 던지거나
`Request` 를 받으면 그 함수는 HTTP 를 세워야만 테스트할 수 있게 되고, 배치나 마이그레이션
스크립트에서 재사용할 수 없게 된다.

경계는 눈으로 지키지 않는다. import 방향은 기계가 볼 수 있다 — 단, **grep 은 이 일에 맞지 않는다.**

```bash
# ✅ 디렉토리가 없으면 검사도 없다 — 존재를 먼저 단언한다
test -d app/db && test -d app/services || exit 1
# ✅ 전이까지 본다: app/db 가 무엇을 거쳐서든 웹 프레임워크를 끌어오면 여기서 죽는다
uv run python -c "import app.db.tasks, sys; assert 'fastapi' not in sys.modules"
```

`! grep -rE "^(from|import) (fastapi|starlette)" app/db/ app/services/` 형태를 쓰지 않는다.
**두 가지를 놓치는데 둘 다 통과로 보인다.**

| 상황 | `!` + grep | 위 가드 |
| --- | --- | --- |
| `app/services/` 가 아직 없다 | grep 이 exit 2 → `!` 가 뒤집어 **exit 0(통과)** | exit 1 |
| `app/db/errors.py` 가 fastapi 를 직접 import | exit 1 (잡는다) | exit 1 |
| `app/db` → `app/schemas` → fastapi (두 다리 건너) | **exit 0(놓친다)** | exit 1 |
| 위반 없는 정상 트리 | exit 0 | exit 0 — **전부 막는 것이 아니다** <!-- verified: 네 상황을 실제 트리에 만들어 두 가드의 종료 코드를 대조 --> |

## 2. 앱 조립 (`app/factory.py`)

<!-- file: app/factory.py -->
```python
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text

from app.db.session import engine
from app.http.handlers import install_error_handlers
from app.http.routers import api_router
from app.obs.health import health_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    async with engine.connect() as conn:   # 첫 요청이 커넥션 지연을 떠안지 않게 예열한다
        await conn.execute(text("SELECT 1"))
    yield
    await engine.dispose()                 # 종료 시 풀을 반납한다


def create_app() -> FastAPI:
    app = FastAPI(title="tasks-api", lifespan=lifespan)
    install_error_handlers(app)            # 라우터보다 먼저 — 등록을 빠뜨리면 전부 500 이다
    app.include_router(health_router)      # 프리픽스 없이 루트에 (프로브는 /api 뒤가 아니다)
    app.include_router(api_router, prefix="/api")
    return app
```

`create_app`은 **인자를 받지 않는다.** 설정을 인자로 받기 시작하면 테스트마다 다른 앱이
조립되고, 그때부터 "테스트에서는 되는데 배포하면 안 되는" 차이가 인자 안에 숨는다.
환경 차이는 `settings` 하나가 흡수한다.

**`app` 인스턴스를 모듈 최상위에서 만들지 않는다.** `factory.py`가 임포트만으로 앱을
세우면 Alembic 이나 스크립트가 `app.db` 를 임포트할 때도 라우터 전체가 함께 올라온다.
앱을 만드는 곳은 `main.py` 하나다.

## 3. `lifespan` — 부착하지 않으면 조용히 안 돈다

`lifespan`을 정의만 하고 `FastAPI(lifespan=lifespan)`로 넘기지 않으면 **아무 경고 없이**
기동·종료 코드가 통째로 건너뛰어진다. ASGI 서버는 `lifespan.startup.complete`를 정상으로
받으므로 로그에도 흔적이 남지 않고, 풀은 종료 시 반납되지 않는다.

| 형태 | 기동/종료 로그 | ASGI 가 받은 응답 |
| --- | --- | --- |
| `FastAPI(lifespan=lifespan)` | startup · shutdown 둘 다 실행 | `lifespan.startup.complete` |
| `FastAPI()` (부착 누락) | **아무것도 실행되지 않음** | `lifespan.startup.complete` — 똑같다 <!-- verified: 두 앱에 ASGI lifespan 이벤트를 직접 넣어 훅 실행 여부와 send 메시지를 대조 --> |

`lifespan` 안에서 실패하면 서버는 기동하지 않는다. **DB 가 있어야만 뜰 수 있는 서버로 만들지
마라** — 예열은 `connect()` 한 번이면 된다. **마이그레이션은 여기서 돌리지 않는다** — 이유와 배포 순서는 `resources/migrations.md` §7 이 소유한다.

`httpx`의 `ASGITransport`는 lifespan 을 **돌리지 않는다.** 테스트에서 기동 코드가 필요하면
`async with lifespan(app):`로 감싸야 하고, 테스트 하네스 전체는 `testing.md` 가 소유한다.
<!-- verified: ASGITransport 로만 요청했을 때 훅 로그 0건 -->

## 4. 부팅 (`app/main.py`)

<!-- file: app/main.py -->
```python
import app.obs.sql  # noqa: F401  — 데코레이터 등록형. import 안 하면 느린 쿼리 관측이 영영 안 돈다
from app.factory import create_app
from app.obs.logging import configure_logging
from app.settings import settings

configure_logging(settings.LOG_LEVEL)   # create_app 보다 먼저
app = create_app()
```

`app/obs/sql.py` 는 `@event.listens_for(engine.sync_engine, …)` 로 자신을 등록하는 모듈이다.
아무도 import 하지 않으면 파일이 존재해도 **훅이 하나도 걸리지 않고 경고가 0건**이다 —
배선하면 같은 쿼리에 2건이 찍힌다. `# noqa: F401` 이 없으면 ruff 가 미사용 import 로 지운다.
<!-- verified: 같은 두 쿼리를 SLOW_MS=0 으로 돌려 import 없음 0건 / 있음 2건 대조 -->

`main.py`는 **요청을 받지 않는다.** 라우트가 하나라도 여기 있으면 `uvicorn app.main:app`을
띄우지 않고는 그 라우트를 테스트할 수 없다.

`configure_logging`은 `create_app`보다, 그리고 uvicorn 이 자기 핸들러를 붙이기 전에 부른다.
나중에 부르면 핸들러가 둘이 되어 모든 줄이 두 번 찍힌다.

```bash
uv run uvicorn app.main:app --reload    # 개발
uv run uvicorn app.main:app --workers 4 # 배포 (워커마다 별도 풀이다 — 풀 사이징은 operations.md)
```

## 5. 의존성 주입 배선 — 별칭을 만들어 반복을 없앤다

```python
# app/http/routers.py
SessionDep = Annotated[AsyncSession, Depends(get_session)]
UserDep = Annotated[AuthUser, Depends(current_user)]
```

이 절의 `app/http/routers.py` 발췌는 **이음매 소유**다(봉투 형태는 조합이 정한다). 팩은
거기서 지켜야 할 형태만 정한다. `Annotated` 별칭은 한 번 만들어 쓴다 —
`session: AsyncSession = Depends(get_session)` 를 라우터마다 반복하면 어느 하나에서
`Depends` 를 빠뜨려도 시그니처가 그럴듯해 보인다.

**세션은 `Depends(get_session)`으로만 받는다.** 라우터가 `session_factory()`를 직접 부르면
그 요청은 트랜잭션이 둘이 되고, 예외가 나도 `get_session`의 롤백이 그 세션을 모른다.

**사용자는 `Depends(current_user)`로만 받는다.** 토큰을 직접 파싱하는 라우터가 하나라도
있으면 경계가 둘이 되고, 그 둘은 반드시 갈라진다. `current_user`가 돌려준 `AuthUser.id`가
곧 `owner_id`이며, 그 값이 데이터 계층까지 그대로 내려간다.

```python
# app/http/routers.py
from app.db import tasks as repo              # 모듈 별칭으로 받는다 — 이름 충돌을 막는다
from app.services import tasks as service


@tasks_router.get("", response_model=list[TaskOut])
async def list_tasks(session: SessionDep, user: UserDep,
                     q: Annotated[TaskQuery, Query()]) -> list[Task]:   # Depends() 가 아니다
    items, _cursor = await repo.list_tasks(session, user.id, q)
    return items


@tasks_router.post("", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
async def create_task(session: SessionDep, user: UserDep, body: TaskCreate) -> Task:
    return await service.create_task(session, user.id, body)


@tasks_router.patch("/{task_id}", response_model=TaskOut)
async def patch_task(session: SessionDep, user: UserDep, task_id: UUID,
                     body: TaskUpdate) -> Task:
    patch = body.model_dump(exclude_unset=True)   # 보내지 않은 필드를 실어 보내지 않는다
    return await service.apply_patch(session, user.id, task_id, patch)
```

**축 계약 셋이 이 발췌에 있다.** ⓐ 생성 성공은 **201**이다(`200` 이면 클라이언트가 생성과
갱신을 구분하지 못한다). ⓑ 목록 쿼리 모델은 `Annotated[TaskQuery, Query()]` 로 받는다 —
`Depends()` 로 받으면 `extra="forbid"` 가 무효가 되어 알 수 없는 파라미터가 조용히 무시된다. <!-- verified: 같은 TaskQuery 를 두 형태로 받아 ?limit=5 는 양쪽 200, ?limit=5&bogus=1 은 Annotated 422 / Depends 200 -->
ⓒ `exclude_unset=True` 를 빼면 `TaskUpdate` 의 `None` 기본값이 실려 보내지 않은 필드가 `NULL`
로 덮인다. 이 변환은 **라우터의 의무**이고 `update_task` 는 이미 걸러진 `patch` 를 받는다.

## 6. 예외 핸들러 등록 — `create_app`이 반드시 부른다

`install_error_handlers(app)`는 이음매가 정의하고 **`create_app`이 부른다.** 호출을
빠뜨리면 `AppError`가 처리되지 않은 예외로 빠져나가 404 여야 할 응답이 500 + 트레이스백이
된다 — 문법 오류가 아니라서 아무것도 이 누락을 알려주지 않는다.

| `install_error_handlers(app)` | `AppError("NOT_FOUND", …)` 를 던지는 라우트의 응답 |
| --- | --- |
| 부른다 | `404` + `{"error": {"code": "NOT_FOUND", …}}` |
| 빠뜨린다 | 처리되지 않은 예외 — 서버가 500 과 트레이스백을 낸다 <!-- verified: 같은 라우트를 두 앱에 붙여 응답 대조 --> |

핸들러는 셋에 건다: `AppError` · `RequestValidationError` · `Exception`. **마지막 하나가 없어도
본문이 새지는 않는다** — Starlette 의 `ServerErrorMiddleware` 가 `debug=False` 에서 본문을
`Internal Server Error` 평문으로 고정한다. 문제는 누출이 아니라 **계약 파기**다: 이 팩의
`{"error":{"code":…}}` 봉투가 사라져 클라이언트가 무엇이 틀렸는지 구분할 수단을 잃는다.

| 앱 | `Exception` 핸들러 | 응답 본문 | DSN·테이블명 포함 |
| --- | --- | --- | --- |
| `debug=False` | 있음 | `{"error":{"code":"INTERNAL",…}}` (70B) | 없음 |
| `debug=False` | 없음 | `Internal Server Error` 평문 (21B) | 없음 |
| `debug=True` | 없음 | 트레이스백 (4487B) | **있음** — 양성 대조군 <!-- verified: DSN 문자열을 넣은 예외를 세 앱에 던지고 본문을 부분문자열로 검사 --> |

`FastAPI(debug=True)` 로 띄운 서버는 트레이스백을 그대로 내보낸다. **운영에서 `debug` 를 켜지
않는다.** 정규화는 `to_app_error` 가, 상태 코드는 `ERROR_STATUS.get(code, 500)` 이 정하며 둘 다
`app/http/errors.py`(`error-handling.md` 소유)에 있다.

## 7. 라우터 마운트 — 계층별로 다른 프리픽스

`api_router`는 도메인 라우터를 모으고 `create_app`이 `prefix="/api"`로 한 번 붙인다.
라우터마다 `/api`를 직접 적으면 프리픽스를 바꿀 때 누락이 생기고, 그 누락은 404 가 아니라
**인증이 걸리지 않은 경로**로 나타날 수 있다.

```python
# app/http/routers.py
tasks_router = APIRouter(prefix="/tasks", tags=["tasks"])
# … 라우트 정의 …
api_router = APIRouter()
api_router.include_router(tasks_router)     # 최종 경로: /api/tasks
```

`health_router`(`/healthz` · `/readyz`)는 `/api` **밖**에 둔다 — 프로브는 인증 헤더를 붙이지 않고,
프리픽스가 바뀌면 프로브가 먼저 죽는다. 헬스체크 내용은 `operations.md` 가 소유한다.

## 8. 서비스 계층 — 도메인 규칙이 사는 곳

**서비스는 모듈 함수다** — 클래스로 감싸지 않는다. 상태가 없는 함수를 클래스에 넣으면
생성자 배선이 하나 더 생기고, 그 배선은 라우터·테스트·배치에서 서로 다르게 된다.

```python
# app/services/tasks.py
from app.db import tasks as repo
from app.db.tasks import Task
from app.errors import AppError


async def read_task(session: AsyncSession, owner_id: UUID, task_id: UUID) -> Task:
    task = await repo.get_task(session, owner_id, task_id)
    if task is None:
        raise AppError("NOT_FOUND", "작업을 찾을 수 없다")   # 상태 코드가 아니라 도메인 코드다
    return task


async def apply_patch(session: AsyncSession, owner_id: UUID, task_id: UUID,
                      patch: dict[str, Any]) -> Task:
    return await repo.update_task(session, owner_id, task_id, patch)   # 허용 열은 리포지토리가 건다
```

리포지토리는 `None` 을 돌려주고 서비스가 `AppError` 로 올린다. 이 한 칸의 분리가 "없음"(데이터
사실)과 "404"(HTTP 결정)를 갈라놓는다 — 배치 작업에서 부를 때 404 는 의미가 없다.

서비스가 얇아 리포지토리를 그대로 통과시키는 것은 정상이다. **비어 있다고 없애지 마라** —
권한 규칙과 여러 리포지토리를 엮는 트랜잭션이 들어올 자리다. 서비스도 `session` 을 **인자로
받는다.**

## 오용 목록 ① — Flask · 구버전 FastAPI → 0.141 관용구 대조표

| 구 습관 | 현재 형태 (FastAPI 0.141) |
| --- | --- |
| `@app.on_event("startup")` / `"shutdown"` | `lifespan` 컨텍스트 매니저 + `FastAPI(lifespan=…)` |
| `app = FastAPI()` 를 모듈 최상위에 | `create_app()` 팩토리 · 인스턴스는 `main.py` 에서만 |
| `g` · `current_app` 같은 전역 요청 상태 | `Depends` 로 명시 주입 |
| `q: TaskQuery = Depends()` | `q: Annotated[TaskQuery, Query()]` |
| `session = Depends(get_session)` 를 라우터마다 반복 | `SessionDep = Annotated[…]` 별칭 하나 |
| 라우터마다 `try/except` 로 상태 코드 결정 | `AppError` 를 던지고 `install_error_handlers` 가 접는다 |
| 라우터 안에서 토큰 파싱 | `Depends(current_user)` 하나 |
| 라우터 경로에 `/api` 를 직접 적기 | `include_router(api_router, prefix="/api")` |
| 서비스가 `HTTPException` 을 던짐 | `AppError(code, message)` — 앞이 도메인 코드다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `main.py` vs `factory.py` | 앞은 부팅(로깅 설정 + 인스턴스 하나), 뒤는 조립. 라우트는 어느 쪽에도 없다 |
| `lifespan` vs 미들웨어 | 프로세스당 한 번은 앞, 요청마다는 뒤 |
| `include_router(prefix=…)` vs `APIRouter(prefix=…)` | 축 안의 묶음은 뒤, 앱 전체의 마운트 지점은 앞 |
| `Depends(get_session)` vs `session_factory()` | 요청 안이면 언제나 앞. 뒤는 스크립트·배치 전용 |
| `AppError` vs `HTTPException` | 팩·서비스는 언제나 앞. 뒤는 이음매의 핸들러 안에서만 보인다 |
| `/healthz` vs `/readyz` | 프로세스 생존은 앞(DB 를 안 본다), 의존성 준비는 뒤 |
| `create_app()` vs 모듈 전역 `app` | 테스트·스크립트가 부르는 것은 앞. 뒤는 uvicorn 이 가리키는 이름 하나 |

<!-- epcc-pack: backend/fastapi v3.14.0 -->
# 데이터 접근 — 세션 수명 · 소유권 · 커서

`app/db/` 전부를 소유한다: `Base` · `Task` · `engine` · `session_factory` · `get_session` · 작업 리포지토리 · 커서.
이 계층은 **HTTP를 모른다.** 앱 조립·라우터는 `project-structure.md`, 스키마는 `input-validation.md` 다.

> **이 축에는 행 수준 정책 엔진이 없다.** `WHERE owner_id = :owner_id` 가 **유일한 경계**이고,
> 빠뜨린 쿼리는 느린 쿼리가 아니라 데이터 유출이다.

## 1. 결정 트리 — 이 접근을 어디에 어떤 형태로 두는가

| 상황 | 형태 |
| --- | --- |
| 단건을 읽고 없으면 404 | `get_task` 가 `None` 을 반환하고 **서비스가** `AppError('NOT_FOUND')` 로 올린다 |
| 부분 수정 · 삭제 | `UPDATE … RETURNING` · `DELETE` + `rowcount`. 읽고-쓰기 왕복은 그 사이에 갈린다 |
| 중복 제약 위반 | `SAVEPOINT` 안에서 `flush()`하고 `is_unique_violation`으로 가른다 (§4) |

**리포지토리는 `session` 을 인자로 받고** 인자 순서는 전 함수에서 **`session` → `owner_id` → `task_id`** 다 — 뒤 둘이 모두 `UUID` 라 바꿔 넣어도 pyright 가 못 잡는다.

## 2. 세션과 선언 기반 소유 (`app/db/session.py` · `app/db/base.py`)

<!-- file: app/db/session.py -->
```python
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.settings import settings

engine = create_async_engine(
    settings.DATABASE_URL,
    pool_size=10,        # 상시 커넥션
    max_overflow=5,      # 순간 초과분 — 합이 PostgreSQL max_connections 를 넘지 않게 잡는다
    pool_pre_ping=True,  # 유휴 중 끊긴 커넥션을 요청 전에 걸러낸다
    pool_timeout=5,      # 풀이 비면 5초만 기다린다 — 무한 대기는 장애를 대기열로 감춘다
    pool_recycle=1800,   # 30분 넘은 커넥션은 버린다 (PgBouncer·NAT 가 조용히 끊는다)
)

session_factory = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """요청당 세션 하나. 성공이면 커밋, 예외면 롤백한 뒤 닫는다."""
    session = session_factory()
    try:
        yield session
        await session.commit()
    except Exception:
        await session.rollback()
        raise          # 다시 던지지 않으면 FastAPI 가 응답을 만들지 못한다
    finally:
        await session.close()
```

**`expire_on_commit=False` 는 선택이 아니다.** 기본값(`True`)이면 커밋 후 속성 접근이 지연 로드를 시도하고, async 에서 그것은 **예외**다 — 직렬화 도중 `MissingGreenlet` 이 나 500 이 된다.
<!-- verified: 2.0.52 · 커밋 후 t.title 접근. True → MissingGreenlet, False → 값 반환(추가 SELECT 0회) -->

`raise` 를 지우면 `FastAPIError: Response not awaited …` 가 나고, **`yield` 뒤에서 새로 터진 예외는
핸들러가 잡지 못한다**(`RuntimeError: … response already started.`) — 그래서 제약 위반은 `flush()`
에서 잡는다(§4). 실측 순서는 성공이 `열기 → 핸들러 → commit → close`, 예외가
`열기 → 핸들러 → rollback → close → 예외 핸들러` 로 **롤백이 핸들러보다 먼저** 돈다.
<!-- verified: fastapi 0.141.1 / starlette 1.6.0 에서 네 형태를 각각 실행하고 훅 순서를 계측 -->

<!-- file: app/db/base.py -->
```python
from sqlalchemy import MetaData
from sqlalchemy.orm import DeclarativeBase

NAMING_CONVENTION = {   # 이름이 없으면 Alembic 이 삭제문을 못 만든다
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_N_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)
```

같은 `UniqueConstraint("owner_id", "title")` 이 규칙 없이는 `name=None`, 있으면 `'uq_tasks_owner_id_title'` 이다. <!-- verified: MetaData 두 개로 같은 제약을 만들어 .name 대조 -->

## 3. 모델과 읽기 (`app/db/tasks.py`) — 소유권은 `WHERE`에 있다

<!-- file: app/db/tasks.py -->
```python
import base64
from datetime import datetime, timezone
from typing import Any, cast
from uuid import UUID, uuid4

from sqlalchemy import (CursorResult, DateTime, Enum as SAEnum, Index, String,
                        UniqueConstraint, delete, literal, select, tuple_, update)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.db.errors import is_unique_violation   # SQLSTATE 판별 — 프레임워크를 모른다
from app.errors import AppError                 # app/http/ 를 import 하지 않는다
from app.schemas.task import TaskCreate, TaskQuery, TaskStatus


class Task(Base):
    __tablename__ = "tasks"
    id: Mapped[UUID] = mapped_column(primary_key=True)          # 앱이 만든다(uuid4)
    title: Mapped[str] = mapped_column(String(200))
    status: Mapped[TaskStatus] = mapped_column(          # 스키마와 같은 열거
        SAEnum(TaskStatus, native_enum=False, length=16, name="task_status"))
    owner_id: Mapped[UUID] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        UniqueConstraint("owner_id", "title"),
        Index("ix_tasks_owner_created_id", "owner_id", "created_at", "id"),  # 키셋의 전제
    )


async def get_task(session: AsyncSession, owner_id: UUID, task_id: UUID) -> Task | None:
    return await session.scalar(
        select(Task).where(Task.owner_id == owner_id, Task.id == task_id)
    )
```

**§4·§5의 발췌는 모두 이 파일의 뒷부분이고 import 는 여기 한 번만 적는다.** `where(...)` 에 조건을
**두 개 다 넣는다** — `Task.id == task_id` 만 걸고 파이썬에서 소유자를 비교하는 형태는 이미 남의 행을
읽어 올린 뒤다. `owner_id` 에 `index=True` 를 따로 주지 않는 것은 복합 인덱스가 선두 컬럼을 덮기
때문이고, `status` 를 `String(16)` 으로 매핑하면 DB 왕복 후 값이 순수 `str` 이라 `isinstance` 가
`False` · `.value` 가 실패한다. `SAEnum(native_enum=False)` 는 DDL 이 **동일**하면서 타입을 살린다.
<!-- verified: 두 매핑으로 세션 왕복 — String(16)은 str, SAEnum 은 TaskStatus. CreateTable 컴파일 결과 동일 -->

## 4. 변이 — 허용 열 고정과 `rowcount`

```python
# app/db/tasks.py
async def delete_task(session: AsyncSession, owner_id: UUID, task_id: UUID) -> None:
    result = cast(CursorResult[Any], await session.execute(
        delete(Task).where(Task.owner_id == owner_id, Task.id == task_id)
    ))
    if result.rowcount == 0:   # 남의 행이거나 없는 행이다 — 확인하지 않으면 204 가 나간다
        raise AppError("NOT_FOUND", "작업을 찾을 수 없다")

async def update_task(session: AsyncSession, owner_id: UUID, task_id: UUID,
                      patch: dict[str, Any]) -> Task:
    bad = set(patch) - {"title", "status"}     # 허용 열 고정 — owner_id·id 는 못 바꾼다
    if bad:
        raise AppError("VALIDATION_FAILED", "수정할 수 없는 필드다",
                       {k: ["수정할 수 없다"] for k in sorted(bad)})
    if not patch:                              # 라우터를 거치지 않는 호출도 있다
        raise AppError("VALIDATION_FAILED", "수정할 필드가 없다", {"body": ["필드가 없다"]})
    stmt = (update(Task).where(Task.owner_id == owner_id, Task.id == task_id)
            .values(**patch).returning(Task))
    row = (await session.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise AppError("NOT_FOUND", "작업을 찾을 수 없다")
    return row

async def create_task(session: AsyncSession, owner_id: UUID, data: TaskCreate) -> Task:
    task = Task(id=uuid4(), title=data.title, status=data.status,   # status 를 옮긴다
                owner_id=owner_id, created_at=datetime.now(timezone.utc))
    try:
        async with session.begin_nested():        # SAVEPOINT — 이 INSERT 만 되돌린다
            session.add(task)
            await session.flush()
    except IntegrityError as exc:
        if is_unique_violation(exc):              # SQLSTATE 23505 (app/db/errors.py)
            raise AppError("CONFLICT", "같은 제목의 작업이 이미 있다") from exc
        raise
    return task
```

**허용 열이 없으면 `WHERE` 경계가 `SET` 으로 우회된다.** `patch` 에 `owner_id` 가 들어가면
`UPDATE tasks SET owner_id=? WHERE owner_id=? AND id=?` 가 되어 **자기 행을 남에게 넘긴다.**
라우터는 `TaskUpdate`(`extra='forbid'`)가 막지만 이 함수는 라우터 없이도 불린다.

| `update_task(s, ALICE, tid, …)` | 허용 열 없음 | 허용 열 고정 |
| --- | --- | --- |
| `{"owner_id": BOB}` | 통과 → **ALICE 조회 불가 · BOB 조회 가능** | `VALIDATION_FAILED` · 소유자 그대로 |
| `{"title", "status"}` (양성 대조군) | 정상 수정 | **정상 수정** — 전부 막는 것이 아니다 <!-- verified: 네 경우를 한 스크립트로 실행하고 DB 를 다시 읽어 owner_id 와 양쪽 조회 가능 여부를 대조 --> |

`AsyncSession.execute()` 의 반환형 `Result[Any]` 에는 `rowcount` 가 없다(DML 의 실물은 `CursorResult`)
— `cast` 없이 쓰면 pyright 가 `reportAttributeAccessIssue` 를 낸다. <!-- verified: pyright 1.1.411 · sqlalchemy 2.0.52 — cast 전 1건 → 후 0건 -->
생성은 **`data` 의 필드를 전부 옮긴다**(`status` 하드코딩은 클라이언트 값을 지운다). `exc.orig` 를 직접
`isinstance` 로 가르지 않는다 — asyncpg 에서 그것은 SQLAlchemy 방언이 감싼 객체이지 asyncpg 의
예외가 아니다(C1 실행 확인). 판별은 `app/db/errors.py` 의 두 함수만 쓴다.

## 5. 키셋 페이지네이션 — 커서는 `(created_at, id)` 둘이다

```python
# app/db/tasks.py
async def list_tasks(session: AsyncSession, owner_id: UUID,
                     q: TaskQuery) -> tuple[list[Task], str | None]:
    stmt = select(Task).where(Task.owner_id == owner_id)
    if q.status is not None:
        stmt = stmt.where(Task.status == q.status)
    if q.cursor is not None:
        created_at, task_id = decode_cursor(q.cursor)
        stmt = stmt.where(tuple_(Task.created_at, Task.id)
                          < tuple_(literal(created_at), literal(task_id)))
    stmt = stmt.order_by(Task.created_at.desc(), Task.id.desc()).limit(q.limit + 1)
    rows = list((await session.scalars(stmt)).all())
    if len(rows) <= q.limit:
        return rows, None
    last = rows[q.limit - 1]                      # limit+1 번째는 "더 있다"는 신호일 뿐이다
    return rows[: q.limit], encode_cursor(last.created_at, last.id)
```

asyncpg 방언에서 이것은 `(tasks.created_at, tasks.id) < ($1::TIMESTAMP WITH TIME ZONE, $2::UUID)`
로 컴파일돼 `ix_tasks_owner_created_id` 를 `Index Cond` 로 탄다. `literal()` 로 감싸는 것 자체가
pyright `reportArgumentType` 2건을 없앤다 — 두 번째 인자로 타입을 넘겨도 SQL 은 그대로다.
<!-- verified: asyncpg 방언 compile 결과 두 형태 동일 · pyright 1.1.411(literal 없음 2건 → 있음 0건) · Index Cond 는 감사 B1 의 실 PostgreSQL 16.2 EXPLAIN -->

**정렬 키가 하나면 동률에서 행이 사라진다.** 시드는 `owner` 행 37개 · 서로 다른 `created_at` 8개
(5행 묶음 7개 + 2행 묶음 1개)이고 **누락률은 limit 의 함수라 한 값으로 요약할 수 없다.**

| limit | 1 | 3 | 5 | 7 | 20 |
| --- | --- | --- | --- | --- | --- |
| `(created_at, id)` | \- | \- | 중복 0 · 누락 0 · 남의 행 0 | \- | \- |
| `created_at` 단일 | 누락 29(78%) | 16(43%) | 2(5%) | 9(24%) | 2(5%) <!-- verified: 같은 시드·같은 세션으로 두 형태를 limit 별 전수 순회. PostgreSQL 16 + asyncpg 0.31 에서 감사 B1 이 재확인 --> |

커서는 **불투명 문자열**이고 디코딩 실패는 `AppError('VALIDATION_FAILED')` 로 접는다.

```python
# app/db/tasks.py
def encode_cursor(created_at: datetime, task_id: UUID) -> str:
    raw = f"{created_at.isoformat()}|{task_id}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")

def decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)).decode()
        stamp, _, task_id = raw.partition("|")
        return datetime.fromisoformat(stamp), UUID(task_id)
    except Exception as exc:                      # 신뢰 입력이 아니다 — 500 이 되면 안 된다
        raise AppError("VALIDATION_FAILED", "커서를 해석할 수 없다",
                       {"cursor": ["형식이 올바르지 않다"]}) from exc
```

## 6. N+1 — async 에서는 조용하지 않다

동기 SQLAlchemy 의 N+1 은 느려질 뿐이지만 async 에서 지연 로드는 **예외**다 — 관계 속성을 그냥 읽으면
`MissingGreenlet` 이 나고 500 이 된다. 나타나는 형태는 **루프 안의 `await`** 다. <!-- verified: 2.0.52 에서 관계 속성 직접 접근 → MissingGreenlet -->

```python
# ❌ 20건이면 SELECT 20회 — 라운드트립이 건수에 비례한다
rows = [await get_task(session, owner_id, task_id) for task_id in ids]
# ✅ SELECT 1회. 소유권 필터는 그대로 살아 있다
rows = list((await session.scalars(
    select(Task).where(Task.owner_id == owner_id, Task.id.in_(ids)))).all())
```
<!-- verified: before_cursor_execute 로 커서 실행 횟수를 계수 — 20회 대 1회 -->

관계를 **선언한 경우에만** `selectinload` 를 쓴다. 이 팩의 `Task` 에는 관계가 없어 기본형에 없고,
추가했다면 `.options(selectinload(Task.<관계>))` 로 1+N 을 2회로 줄인다. <!-- verified: 관계 하나를 붙인 실험 모델에서 작업 5건 조회가 SELECT 6회 → 2회 -->

## 7. Alembic — 자동생성은 초안이지 결과물이 아니다

```python
# alembic/env.py
import app.db.tasks  # noqa: F401  — 모델 모듈을 import 해야 Base.metadata 가 채워진다
from app.db.base import Base
from app.settings import settings
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)
target_metadata = Base.metadata
```

`import app.db.tasks` 가 없으면 `Base.metadata.tables` 가 **빈 리스트**라 자동생성이 "변경 없음"을 낸다. <!-- verified: import 전 [] → import 후 ['tasks'] -->
초안은 읽고 고친 뒤 커밋한다: `uv run alembic revision --autogenerate -m "init tasks"` → `uv run alembic upgrade head`.

| 자동생성이 하는 것 | 자동생성이 **못 하는** 것 |
| --- | --- |
| 테이블·컬럼·인덱스 추가, 제약 추가/삭제(이름이 있을 때), 컬럼 타입 변경, 인덱스 이름 변경(drop+create) | 컬럼 이름 변경 — `add_column`+`drop_column` 으로 나와 **데이터가 사라진다**. 기존 행 백필 같은 데이터 이전 |
| `server_default` 변경은 **기본 설정에서 감지하지 않는다.** `compare_server_default=True` 를 주면 `alter_column` 을 만들지만 방언별 신뢰도가 낮아 이 팩은 켜지 않는다 | <!-- verified: alembic 1.19.1 · 드리프트 4종을 심고 생성물 대조. 플래그 없이 0건(본문 pass) → 켜면 alter_column. PG 16+asyncpg 0.31 은 감사 B1 재확인 --> |

## 오용 목록 ① — SQLAlchemy 1.4 동기 → 2.0 async 관용구 대조표

| 구 습관 (1.4 동기) | 현재 형태 (2.0 async) |
| --- | --- |
| `SessionLocal = sessionmaker(engine)` | `async_sessionmaker(engine, expire_on_commit=False)` |
| 함수마다 `session.commit()` | 커밋은 `get_session` 이 요청당 한 번 |
| `.values(**patch)` 를 그대로 | 허용 열을 뺀 나머지를 먼저 거부한다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `session.rollback()` vs `session.begin_nested()` | 요청 전체를 버릴 때만 앞. 제약 위반 한 건을 삼킬 때는 SAVEPOINT |
| `String(16)` vs `SAEnum(native_enum=False)` | 열거 컬럼은 뒤. 앞은 왕복 후 `str` 이 되어 어노테이션이 거짓말을 한다 |
| `pool_size` + `max_overflow` vs `pool_recycle` | 앞 둘의 **합**이 DB 의 `max_connections` 안. 뒤는 커넥션 나이 상한 |

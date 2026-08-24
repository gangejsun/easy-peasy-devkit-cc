<!-- epcc-pack: backend/fastapi v3.14.0 verified 2026-08-24 fastapi@0.141 pydantic@2 pydantic-settings@2 sqlalchemy@2 alembic@1 asyncpg@0.31 uvicorn@0.52 pytest@9 pytest-asyncio@1 httpx@0.28 ruff@0.16 pyright@1 -->

# fastapi 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 **그대로 삽입할 축-지역 조각**이다. 사전 제작 이음매가 있는
조합은 이 파일을 쓰지 않는다 — 그 경우 이음매의 `HUB.md`가 허브 전문을 갖는다.

각 조각은 `<!-- pack-slot: 이름 -->` ~ `<!-- /pack-slot -->` 사이에 있고, 축 안에서 닫혀
있어 프론트엔드 축이 무엇이든 그대로 성립한다. 조합의 함수인 것은 여기 없다 —
파일 끝의 표가 이음매의 몫을 명시한다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
app/
├── main.py                  # 부팅만 — configure_logging() → create_app() (요청을 받지 않는다)
├── factory.py               # create_app(): 라우터 마운트 + 예외 핸들러 + lifespan 부착
├── settings.py              # 프로세스 환경을 읽는 **유일한** 파일 (모듈 최상위에서 검증·실패)
├── db/
│   ├── base.py              # Base(DeclarativeBase) + 제약 명명 규칙 (Alembic 자동생성의 전제)
│   ├── session.py           # engine · session_factory · get_session 의존성
│   └── tasks.py             # 작업 리포지토리 — HTTP를 모른다. session을 인자로 받는다
├── schemas/
│   └── task.py              # Pydantic 스키마 + TaskStatus 열거 (모델과 같은 열거를 쓴다)
├── errors.py                # AppError — **이음매가 소유한다.** 프레임워크를 import하지 않는다
├── db/errors.py             # SQLSTATE 판별(23505·23503) — asyncpg만 안다. HTTP를 모른다
├── http/
│   ├── errors.py            # ERROR_STATUS · to_app_error · field_errors (fastapi를 import한다)
│   ├── handlers.py          # install_error_handlers — **이음매가 소유한다**
│   ├── auth.py              # current_user · AuthUser — **이음매가 소유한다**
│   └── routers.py           # api_router — **이음매가 소유한다**
├── obs/
│   ├── logging.py           # configure_logging — **DB를 import하지 않는다**
│   ├── health.py            # health_router — readyz가 engine을 쓰므로 갈라 둔다
│   └── sql.py               # 느린 쿼리 이벤트. **등록형이라 main.py가 import해야 돈다**
└── services/
    └── tasks.py             # 도메인 규칙. 리포지토리를 부르고 AppError를 던진다

alembic/
├── env.py                   # Base.metadata를 target_metadata로 준다 (자동생성의 전제)
└── versions/                # 마이그레이션 — 손으로 읽고 고친 뒤 커밋한다

tests/
├── conftest.py              # app_client · override_user · 테스트 DB 격리
├── test_schemas.py          # 스키마 단위 — 부분 수정·미지 키·빈 객체
├── test_errors.py           # 에러 정규화 — SQLSTATE 판별과 봉투
└── test_tasks.py            # 소유권 회귀 — 긍정·부정을 같은 테스트에 건다
```

**계층은 한 방향이다**: `routers → services → db`. 리포지토리가 `HTTPException`을 던지거나
`Request`를 받으면 그 계층은 이미 무너진 것이다 — 테스트가 HTTP를 세워야만 돌게 된다.

**`app/http/`의 네 파일은 이음매 소유다.** 팩은 그것들을 부르기만 한다. 조립 전에는
정의가 없는 것이 정상이고, 게이트가 `--assembly`와 함께 그 충족을 검사한다.
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
## Core Principles

1. **소유권은 `WHERE`에 있다.** 행 수준 정책 엔진이 없고 앱이 신뢰된 연결로 DB에 붙으므로,
   소유자 조건을 빠뜨린 쿼리는 요청한 것을 그대로 준다. 애플리케이션 검사는 이중 방어가
   아니라 **유일한 방어**다.
2. **계층은 한 방향이다** (`routers → services → db`). 리포지토리는 `session`을 인자로 받고
   HTTP를 모른다. 도메인 실패는 `AppError`(이음매)로 올라간다.
3. **트랜잭션 경계는 `get_session` 하나다.** 요청당 세션 하나를 열고 성공 시 한 번 커밋한다.
   리포지토리마다 커밋하면 라우터 하나가 절반만 반영된 상태를 남긴다.
4. **환경은 `settings` 한 곳에서만 읽는다.** `Settings`가 모듈 최상위에서 검증되므로 잘못된
   환경은 부팅 실패다 — 요청 시점에 터지면 절반이 살아 있는 서버가 된다.
5. **경계마다 스키마가 있다.** 입력은 `TaskCreate`·`TaskUpdate`·`TaskQuery`, 출력은 `TaskOut` —
   ORM 모델을 그대로 반환하면 나중에 추가한 컬럼이 조용히 새어 나간다.
6. **전부 async, 전부 타입 힌트.** 동기 세션 하나가 이벤트 루프를 막는다.
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
## Common Imports

```python
# app/db/ — 엔진·세션 계열은 sqlalchemy.ext.asyncio에서 온다
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, selectinload
# app/schemas/ · app/settings.py · 라우터
from typing import Annotated
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from fastapi import APIRouter, Depends, FastAPI, Query, status
from fastapi.exceptions import RequestValidationError
```

**v1 관용구와 헷갈리는 자리** — 이름이 한두 글자 차이라 옛 예제를 복사하면 조용히 섞인다.

| 구 습관 (Pydantic v1 · SQLAlchemy 1.x) | 현재 형태 (Pydantic 2 · SQLAlchemy 2.0) |
| --- | --- |
| `sessionmaker()` | `async_sessionmaker(...)` — 동기 쪽은 async 라우터에서 루프를 막는다 |
| `session.query(Task).filter(...)` | `await session.execute(select(Task).where(...))` |
| `declarative_base()` · `Column(...)` | `class Base(DeclarativeBase)` · `Mapped[...]` + `mapped_column(...)` |
| `class Config: orm_mode = True` | `model_config = ConfigDict(from_attributes=True)` |
| `.dict()` · `parse_obj()` · `@validator` | `.model_dump()` · `model_validate()` · `@field_validator` |
<!-- /pack-slot -->

<!-- pack-slot: architecture-overview -->
## Architecture Overview

```
부팅   configure_logging() → create_app(): 라우터 마운트 · install_error_handlers(app)
                                          · FastAPI(lifespan=lifespan) → 종료 시 engine.dispose()
요청 → api_router (이음매, prefix="/api") → 도메인 라우터
         ├ Depends(current_user) → AuthUser      ← 유일한 인증 경계 (실패 401)
         ├ TaskCreate / Annotated[TaskQuery, Query()] 검증 (실패 422)
         └ Depends(get_session) ─── 트랜잭션 경계 시작 (요청 하나 = 세션 하나)
                ▼
           TaskService (services/tasks.py) — 도메인 규칙, AppError를 던진다
                ▼
           db/tasks.py  get_task(session, owner_id, task_id)  ← 소유자 조건은 여기, WHERE 안에
                ▼        PostgreSQL 16 (asyncpg)
   성공 → get_session commit → TaskOut 직렬화 → JSON      ┐ 경계 끝
   예외 → get_session rollback → to_app_error(exc) → ERROR_STATUS.get(code, 500) → 이음매 봉투
```

- **커밋하는 곳은 `get_session` 하나뿐이다.** 서비스도 리포지토리도 커밋하지 않는다.
  `session_factory`가 `expire_on_commit=False`인 이유도 여기 있다 — 커밋 뒤 `TaskOut`이 속성을
  읽을 때 다시 쿼리가 나가면 응답 직렬화 도중 I/O가 난다.
- **화살표를 거스르는 의존은 없다 — 그리고 그것을 배치로 강제한다.** `db/`가 쓰는 두
  가지(`AppError` · SQLSTATE 판별)를 `http/` 밖에 둔 이유가 이것이다. `app/http/errors.py`는
  `RequestValidationError` 때문에 `fastapi`를 import하므로, `AppError`를 거기 두면
  `import app.db.tasks` 한 줄이 **fastapi를 전이로 끌어온다** — 실측에서 그랬다.
  `python -c "import app.db.tasks, sys; assert 'fastapi' not in sys.modules"`가 이 규율의
  검사식이다(문자열 grep은 전이를 못 본다). `health_router`의 `/healthz`는 DB를 보지 않는다.
<!-- /pack-slot -->

<!-- pack-slot: http-status-and-antipatterns -->
## HTTP 상태 매핑과 반복되는 안티패턴

`ERROR_STATUS`가 **유일한 매핑표**다. 어디서든 `ERROR_STATUS.get(code, 500)` 형태로 읽는다 —
첨자 접근은 모르는 코드에서 `KeyError`를 내고, 그 `KeyError`가 다시 500이 되며 원래 코드를 지운다.

| 도메인 코드 | 상태 | 언제 |
| --- | --- | --- |
| `VALIDATION_FAILED` | 422 | 스키마 위반 · 빈 patch · `decode_cursor` 실패 |
| `UNAUTHENTICATED` | 401 | `current_user`가 주체를 세우지 못했다 |
| `FORBIDDEN` | 403 | 주체는 확인됐지만 그 동작이 허용되지 않는다 |
| `NOT_FOUND` | 404 | `get_task`가 `None` · `rowcount == 0` — **남의 행도 여기다** |
| `CONFLICT` | 409 | `is_unique_violation` (SQLSTATE 23505) |
| `INTERNAL` | 500 | `to_app_error`가 접은 나머지 전부 |

- ❌ **404와 403을 소유권으로 가른다** — "있지만 네 것이 아니다"는 403이 곧 존재 누설이다.
  소유자 조건에 걸리지 않은 행은 **없는 행**으로 취급한다.
- ❌ **드라이버 메시지 문자열로 중복을 판정한다** — 로케일·버전에 따라 바뀐다.
  `is_unique_violation`·`is_foreign_key_violation`이 SQLSTATE(23505·23503)로 가른다.
- ❌ **라우터가 `HTTPException`을 직접 던진다** — 이음매의 핸들러를 우회해 봉투가 둘이 된다.
- ❌ **예외를 그대로 노출한다** — 원본 메시지에 DSN·테이블명이 들어 있다. 핸들러는 `to_app_error`로
  먼저 정규화한다. 필드 오류도 라우터마다 만들지 않는다 — `field_errors`가 유일한 자리다.
<!-- /pack-slot -->

<!-- pack-slot: quick-start-axis -->
## Quick Start — 엔드포인트 하나 추가하기

순서를 지킨다. 라우터가 리포지토리보다 먼저 나오면 시그니처를 추측하게 된다.

| # | 단계 | 여는 파일 |
| --- | --- | --- |
| 1 | 모델 컬럼·인덱스 (`(owner_id, created_at, id)` 복합 인덱스가 키셋 페이지네이션의 전제) | `app/db/base.py` · `app/db/tasks.py` |
| 2 | 마이그레이션 생성 후 **손으로 읽고 고친다** — 인덱스 이름·타입 변경·데이터 이전은 자동생성이 못 한다 | `alembic/versions/` |
| 3 | 스키마와 열거 — `TaskStatus`를 모델과 **공유**한다 | `app/schemas/task.py` |
| 4 | 리포지토리 함수 — 인자 순서는 항상 `session → owner_id → task_id` | `app/db/tasks.py` |
| 5 | 도메인 규칙 — 리포지토리를 부르고 `AppError`를 던진다 | `app/services/tasks.py` |
| 6 | 라우터 — `Depends(current_user)` · `Depends(get_session)` · `response_model=TaskOut` | 이음매의 `app/http/routers.py`가 모은다 |
| 7 | 테스트 — `app_client`로 앱을 직접 태우고 `override_user(app, auth_for(...))`로 주체를 바꾼다 | `tests/conftest.py` · `tests/test_tasks.py` |

```bash
uv run alembic revision --autogenerate -m "add tasks"
uv run alembic upgrade head
uv run ruff check . && uv run pyright && uv run pytest
```

**6번이 부분 수정이면** 본문을 `model_dump(exclude_unset=True)`로 뽑아 `update_task`에 넘긴다(라우터의
의무다). **7번은 긍정과 부정을 같은 테스트에 건다** — 404만 걸면 조회를 통째로 망가뜨려도 초록이다.
<!-- /pack-slot -->

<!-- pack-slot: anti-patterns-axis -->
## Anti-Patterns — 이 축에서 가장 비싼 것부터

**맨 위 셋은 전부 "데이터 계층에 정책 엔진이 없다"는 전제에서 나온다.** DB 연결이 신뢰된 연결이라
쿼리가 요청한 것을 그대로 준다 — 다른 축의 "행 수준 정책이 백업이니 애플리케이션 검사는 이중
방어"라는 서술은 여기서 **정확히 반대 지침**이다.

| 안티패턴 | 왜 비싼가 | 대신 |
| --- | --- | --- |
| 단건 조회에 소유자 조건이 없다 | 이 쿼리를 막는 것이 아무것도 없다. **한 줄 누락이 곧 전 사용자 데이터 유출**이다 | `get_task(session, owner_id, task_id)`만 부른다 |
| 조회한 뒤 파이썬에서 소유자를 비교한다 | 남의 행을 **이미 읽은 뒤**다. 로그·트레이스·타이밍에 남는다 | 필터를 쿼리로 내린다 |
| `UPDATE`/`DELETE` 뒤 `rowcount`를 안 본다 | 0행을 변이해도 성공이다 — 남의 것을 지우라는 요청이 204를 받는다 | 0이면 `AppError("NOT_FOUND")` |
| 인자를 `(session, task_id, owner_id)`로 부른다 | 둘 다 `UUID`라 타입 검사도 게이트도 못 잡는다. 전 단건 조회가 조용히 404가 된다 | `session → owner_id → task_id` 고정 |
| `create_task`가 `data.status`를 버리고 기본값을 하드코딩한다 | 클라이언트가 보낸 값이 조용히 사라진다. 문법이 완벽해 리뷰도 통과한다 | `data`의 필드를 **전부** 옮긴다 |
| 부분 수정에 `model_dump()`를 쓴다 | 보내지 않은 필드가 기본값으로 저장을 덮는다 | `model_dump(exclude_unset=True)` |
| ORM 모델을 응답으로 반환한다 | 나중에 추가한 컬럼이 조용히 새어 나간다 | `TaskOut` (`from_attributes=True`) |
| 라우터가 토큰을 직접 파싱한다 | 인증 경계가 둘이 되고, 그 둘은 반드시 갈라진다 | `Depends(current_user)`만 |
| 서비스·리포지토리에서 커밋한다 | 요청 하나가 절반만 반영된 상태를 남긴다 | 커밋은 `get_session`이 한 번 |
| 목록에 `selectinload`를 습관적으로 붙인다 | 직렬화하지도 않을 관계를 매 페이지마다 더 읽는다 | 응답에 실제로 실을 때만 |
| `OFFSET` 페이지네이션 · 커서를 신뢰 입력으로 다루기 | 깊은 페이지가 선형으로 느려지고, 클라이언트가 만든 문자열이 정렬 키로 들어간다 | `encode_cursor`/`decode_cursor` 키셋. 디코딩 실패는 `VALIDATION_FAILED` |
| `lifespan`을 만들고 `FastAPI(...)`에 안 넘긴다 · `configure_logging`을 `create_app` 뒤에 부른다 | 전자는 조용히 안 돌아 종료 때 커넥션이 남고, 후자는 uvicorn 핸들러가 남아 로그가 두 번 찍힌다 | `FastAPI(lifespan=lifespan)` · 로깅은 `create_app`보다 먼저 |
<!-- /pack-slot -->

## 이음매가 채울 것

| 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| `api-endpoints` | APIRouter 형태 + 요청/응답 봉투. 봉투는 와이어 계약이 정한다 |
| `auth-boundaries` | 토큰 검증 방식이 프론트 축에 서버 런타임이 있는지에 달렸다 |
| `complete-example` | 마이그레이션 → 모델 → 스키마 → 리포지토리 → 서비스 → 라우터 → 테스트 관통 |

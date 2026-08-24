<!-- epcc-pack: backend/fastapi v3.14.0 -->
# 테스트 — 앱을 네트워크 없이 태우고, 경계가 실제로 막는지 증명한다

이 파일은 **pytest 구성 · 테스트 클라이언트 · 의존성 오버라이드 · 테스트 DB 격리 · 차단
증명**을 소유한다. 라우터·리포지토리 구현은 `resources/project-structure.md`·
`resources/data-access.md`가, `AppError`·`current_user`·`auth_for`는 이음매가 소유한다.

## 1. 결정 트리 — 어느 층에서 시험할 것인가

| 무엇을 확인하나 | 층 | 무엇을 세우나 |
| --- | --- | --- |
| 소유권 필터 · 필드 보존 · `rowcount` 판정 | 리포지토리 | `db_session`만. HTTP를 세우지 않는다 |
| 상태 코드 · 직렬화 · 의존성 배선 | HTTP | `app_client` (`ASGITransport`) |
| 풀 예열 · `dispose` · 헬스체크 | 프로세스 | `lifespan_context` (§4) |
| 인덱스가 실제로 쓰이는지 | DB | 실 PostgreSQL 16. 스텁으로 대체되지 않는다 |

**HTTP를 세우지 않아도 되는 것은 세우지 않는다.** 이 축은 행 수준 정책 엔진이 없어
소유권이 `WHERE`에만 있고, 그 판정은 리포지토리 층에서 가장 싸게 잡힌다.

```python
# tests/test_tasks.py — 리포지토리 층: 세션만 받는다
async def test_repo_layer_needs_no_http(db_session):
    made = await create_task(db_session, ALICE, TaskCreate(title="t", status=TaskStatus.DONE))
    assert made.status == TaskStatus.DONE                      # ✅ 긍정: 보낸 필드가 산다
    assert await get_task(db_session, ALICE, made.id) is not None
    assert await get_task(db_session, BOB, made.id) is None     # ✅ 부정: 남에게는 없다
    rows = (await db_session.execute(select(Task).where(Task.owner_id == ALICE))).scalars().all()
    assert len(rows) == 1
```

인자 순서는 **`session` → `owner_id` → `task_id`** 고정이다. 둘 다 `UUID`라 바꿔 써도
파이썬도 pyright도 잡지 못한다 — 잡는 것은 이 테스트뿐이다(§7의 M10).

## 2. pytest 구성 (`pyproject.toml`)

<!-- file: pyproject.toml -->
```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "session"
asyncio_default_test_loop_scope = "session"
```

- `asyncio_mode`의 기본값은 **`strict`**이고, strict에서 `@pytest.mark.asyncio`가 없는
  async 테스트는 건너뛰지 않고 **실패한다** <!-- verified: pytest 9.1.1 + pytest-asyncio 1.4.0 실행, 미표식 테스트가 FAILED -->.
  `auto`를 쓰면 표식이 필요 없다 — 어느 쪽을 골라도 침묵은 없다
- **엔진을 세션 스코프 픽스처가 소유하면 루프 스코프도 세션이어야 한다** — 기본값
  `function`에서는 엔진이 만들어진 루프와 테스트가 도는 루프가 갈린다
- 1.4.0은 `asyncio_default_fixture_loop_scope`를 비워 두면 `PytestDeprecationWarning`을
  **낸다.** 다만 `pytest_configure`에서 나오므로 평범한 `pytest`에서도 `pytest -W always`
  에서도 **보이지 않고**, `PYTHONWARNINGS=always` 또는 `python -W always -m pytest`
  에서만 보인다 <!-- verified: pytest-asyncio 1.4.0 — 무플래그·pytest -W always 0건 / python -W always -m pytest·PYTHONWARNINGS=always 1건. 소스 plugin.py:295-299가 무조건 warn -->
- **경고가 안 보이는 것이지 없는 게 아니다.** 「X가 안 나온다」를 결론으로 쓰려면 그
  관측 장치로 X가 나오는 경우를 **먼저** 보여야 한다. 이 줄의 앞 판본이 그 실패였다

## 3. 앱을 네트워크 없이 부른다 — `ASGITransport`

```python
# tests/conftest.py — 발췌
async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
    response = await client.get("/api/tasks")
```

`base_url`은 **선택이 아니다.** 빼면 `ValueError: unknown url type: '/api/tasks'`가 난다
<!-- verified: httpx 0.28.1 실행, base_url 없이 상대 경로 요청 시 ValueError -->. 값은 아무
호스트나 되고 실제로 해석되지 않는다.

## 4. `lifespan`은 `ASGITransport`에서 돌지 않는다

**이 절이 이 파일에서 가장 비싼 사실이다.** `ASGITransport`는 HTTP 스코프만 보내므로
`create_app`에 붙인 `lifespan`이 **조용히 건너뛰어진다** — 요청은 200인데 startup은 한 번도
돌지 않았다 <!-- verified: fastapi 0.141.1 + httpx 0.28.1 실행, startup/shutdown 훅 미호출 -->.
풀 예열에 기대는 코드는 여기서 **다르게 동작한다**. 명시적으로 돌린다.

```python
# tests/conftest.py — 발췌  <!-- verified: starlette 1.6.0 실행, 요청 전 startup / 종료 시 shutdown -->
async with app.router.lifespan_context(app):   # ✅ startup이 여기서 돈다
    yield app                                   #    블록을 빠져나갈 때 shutdown이 돈다
```

## 5. 의존성 오버라이드 — 되돌리지 않으면 다음 테스트가 오염된다

`app.dependency_overrides`는 **앱 객체에 달린 전역 딕셔너리**다. 모듈 최상위 `app`을
공유한 채 지우지 않으면, 오버라이드를 심은 적 없는 다음 테스트가 앞 사용자로 200을
받는다 — 그리고 **둘 다 초록이다** <!-- verified: fastapi 0.141.1 실행, 미해제 시 2번째 테스트가 1번째 사용자로 200, 2 passed -->.
막는 방법은 두 가지고 **둘 다 쓴다**.

```python
# tests/conftest.py — 발췌
application = create_app()                     # ✅ ① 테스트마다 앱을 새로 만든다
application.dependency_overrides.clear()       # ✅ ② 그래도 명시적으로 비운다
```

①만으로도 오염은 사라지지만, 누군가 앱을 모듈 최상위로 올리는 순간 ②만 남는다.

## 6. 테스트 DB 격리 (`tests/conftest.py`)

각 테스트를 **바깥 트랜잭션 안에서 돌리고 끝나면 되돌린다.** 테이블을 지우는 것보다
빠르고, 병렬 워커끼리 커넥션이 갈리므로 서로를 보지 않는다. `os.environ`을 쓰는 자리는
이 파일뿐이고(정책 `env-single-entry`의 예외), `settings`가 모듈 최상위에서 검증하므로
**`app.settings` 임포트 전에** 주입해야 한다 — 그 뒤엔 늦다.

<!-- file: tests/conftest.py -->
```python
import os
from typing import AsyncIterator
from uuid import UUID

import pytest
import pytest_asyncio

# 이 파일이 os.environ을 쓰는 유일한 자리다 — settings 임포트보다 먼저여야 한다.
os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL", "postgresql+asyncpg://app:app@localhost:5432/app_test"
)

from fastapi import FastAPI                                    # noqa: E402
from httpx import ASGITransport, AsyncClient                   # noqa: E402
from sqlalchemy import func, select                            # noqa: E402
from sqlalchemy.ext.asyncio import AsyncSession                # noqa: E402

from app.db.base import Base                                   # noqa: E402
from app.db.tasks import Task                                  # noqa: E402  (매퍼 등록)
from app.db.session import engine, get_session                 # noqa: E402
from app.factory import create_app                             # noqa: E402
from app.http.auth import AuthUser, auth_for, current_user     # noqa: E402


@pytest_asyncio.fixture(scope="session")
async def db_schema() -> AsyncIterator[None]:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(db_schema: None) -> AsyncIterator[AsyncSession]:
    conn = await engine.connect()
    trans = await conn.begin()
    session = AsyncSession(
        bind=conn, expire_on_commit=False, join_transaction_mode="create_savepoint"
    )
    try:
        # 격리 가드 — 모든 테스트 시작 시점에 돈다. 테스트 순서에 기대지 않는다.
        empty = select(func.count()).select_from(Task)
        assert (await session.execute(empty)).scalar_one() == 0, "앞 테스트의 행이 남아 있다"
        yield session
    finally:
        await session.close()
        await trans.rollback()
        await conn.close()


@pytest_asyncio.fixture
async def app(db_session: AsyncSession) -> AsyncIterator[FastAPI]:
    application = create_app()

    async def _session_override() -> AsyncIterator[AsyncSession]:
        yield db_session

    application.dependency_overrides[get_session] = _session_override
    async with application.router.lifespan_context(application):
        yield application
    application.dependency_overrides.clear()


@pytest_asyncio.fixture
async def app_client(app: FastAPI) -> AsyncIterator[AsyncClient]:
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        yield client


def override_user(app: FastAPI, user: AuthUser) -> None:
    app.dependency_overrides[current_user] = lambda: user


@pytest.fixture
def as_user(app: FastAPI):
    def _login(owner_id: UUID) -> AuthUser:
        user = auth_for(owner_id)
        override_user(app, user)
        return user
    return _login
```

**오버라이드한 세션은 커밋하지 않는다** — 커밋 경계는 §1 표의 「프로세스」 층에서 따로 본다.

**격리는 믿지 말고 시험한다.** 이 패턴은 드라이버가 진짜 트랜잭션을 열 때만 성립한다.
그래서 가드를 **테스트가 아니라 `db_session` 픽스처 안에** 뒀다 — 테스트로 두면 그 테스트가
몇 번째로 도느냐에 따라 잡히기도 하고 안 잡히기도 한다(실제로 순서를 바꾸자 M7을 놓쳤다).
픽스처 안에서는 모든 테스트의 시작마다 돌아 **순서에 기대지 않는다**
<!-- verified: 롤백을 커밋으로 바꾼 M7에서 `앞 테스트의 행이 남아 있다 / assert 1 == 0`으로 실패 -->.

## 7. 차단 증명 — 무엇을 지우면 무엇이 빨개지는가

**부정 단언만 있는 테스트는 차단 장치가 아니다.** 남의 것에 404만 걸면 조회 함수를
`return None`으로 바꿔도 초록이다. 긍정을 **같은 함수 안에** 짝으로 건다.

```python
# tests/test_tasks.py — M1·M2·M6
async def test_read_is_scoped_to_owner(app_client, as_user):
    as_user(ALICE)
    task_id = (await app_client.post("/api/tasks", json={"title": "alice task"})).json()["id"]
    mine = await app_client.get(f"/api/tasks/{task_id}")
    assert mine.status_code == 200                    # ✅ 긍정 — 없으면 "전부 고장"과 못 가른다
    assert mine.json()["title"] == "alice task"       # ✅ 필드 보존까지 본다
    as_user(BOB)
    assert (await app_client.get(f"/api/tasks/{task_id}")).status_code == 404   # ✅ 부정
```

표의 M3·M5가 가리키는 두 테스트다. **`status`는 값이 소문자다** — 파이썬에서는 멤버
(`TaskStatus.DONE`)를, 와이어 JSON에서는 값(`"done"`)을 쓴다. 섞으면 요청은 422로 막히고
응답 단언은 영영 빨갛다.

```python
# tests/test_tasks.py — M3: 삭제는 영향 행 수로 갈린다
async def test_delete_is_scoped_to_owner(app_client, as_user):
    as_user(ALICE)
    task_id = (await app_client.post("/api/tasks", json={"title": "alice task"})).json()["id"]

    as_user(BOB)
    assert (await app_client.delete(f"/api/tasks/{task_id}")).status_code == 404   # ✅ 부정
    as_user(ALICE)
    assert (await app_client.get(f"/api/tasks/{task_id}")).status_code == 200      # ✅ 아직 산다
    assert (await app_client.delete(f"/api/tasks/{task_id}")).status_code == 204   # ✅ 긍정
```

```python
# tests/test_tasks.py — M5: 보낸 필드가 저장까지 살아 있는가
async def test_create_carries_every_supplied_field(app_client, as_user):
    as_user(ALICE)
    sent = await app_client.post("/api/tasks", json={"title": "done one", "status": "done"})
    assert sent.json()["status"] == "done"                                  # ✅ 긍정
    got = await app_client.get(f"/api/tasks/{sent.json()['id']}")
    assert got.json()["status"] == "done"                                   # ✅ 저장까지 산다
    omitted = await app_client.post("/api/tasks", json={"title": "open one"})
    assert omitted.json()["status"] == "open"                               # ✅ 대조: 기본값
```

부분 수정은 **보내지 않은 필드**가 시험 대상이다. 아래 두 줄이 지워졌을 때 잡히는지를
M8·M3이 확인한다.

```python
# app/http/routers.py · app/db/tasks.py — 시험이 지키는 두 줄
patch = body.model_dump(exclude_unset=True)   # 지우면 보내지 않은 필드가 저장을 덮는다
if result.rowcount == 0:                      # 지우면 남의 삭제 요청도 204가 된다
    raise AppError("NOT_FOUND", "작업을 찾을 수 없다")
```

구현을 실제로 망가뜨려 얻은 표다. **초록으로 남는 변이가 있으면 그 자리에 시험이 없는 것이다.**

| 변이 | 결과 | 빨개진 단언 |
| --- | --- | --- |
| M1 `get_task`의 `owner_id` 필터 제거 | FAIL | 부정 `assert 200 == 404` |
| M2 `get_task`가 항상 `None` | FAIL | **긍정** `assert 404 == 200` — 실린 4개 전부 |
| M3 `delete_task`의 `rowcount` 검사 제거 | FAIL | `assert 204 == 404` |
| M4 `delete_task`의 `owner_id` 필터 제거 | FAIL | `assert 204 == 404` |
| M5 `create_task`가 `status`를 하드코딩 | **처음엔 PASS → 시험 추가 후 FAIL** | `assert 'open' == 'done'` |
| M6 `create_task`가 `title`을 하드코딩 | FAIL | `assert 'x' == 'alice task'` |
| M7 격리 픽스처가 롤백 대신 커밋 | ERROR | `db_session` 가드 — 픽스처에서 나므로 FAIL이 아니라 ERROR다 |
| M8 라우터가 `exclude_unset=True` 제거 | FAIL | `IntegrityError` — `SET status=None` |
| M9 `update_task`의 `owner_id` 필터 제거 | FAIL | `assert 200 == 404` |
| M10 `get_task`의 두 `UUID` 인자 교환 | FAIL | 실린 4개 전부 |

**M5가 이 표의 이유다** — 처음 쓴 테스트 4개는 `status` 유실을 전혀 잡지 못했다.
표는 라우터·`current_user`를 이음매로 채운 조립본에서 얻었고 M8·M9는 위에 싣지 않은
`PATCH` 라우트를 쓴다 <!-- verified: 조립본 실행. 라우트·인증은 이음매 소유라 조합마다 재확인이 필요하다 -->.

## 오용 목록 ① — `TestClient`/구 관용구 → 현재 형태 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `TestClient(app)`로 async 테스트 | `AsyncClient(transport=ASGITransport(app=app), base_url=...)` |
| `ASGITransport`가 startup을 돌려줄 것으로 기대 | `app.router.lifespan_context(app)`로 명시적으로 돌린다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `get_session` 오버라이드 vs 실 `get_session` | 격리를 원하면 오버라이드, 커밋 경계를 원하면 실물 |
| 세션 스코프 엔진 vs 함수 스코프 루프 | 섞으면 루프가 갈린다. 루프 스코프도 세션으로 맞춘다 |
| 부정 단언만 vs 긍정·부정 짝 | 짝이 없으면 "전부 고장"이 "차단"으로 보인다 |
| `TaskStatus.DONE` vs `"done"` | 파이썬은 멤버, 와이어 JSON은 **값(소문자)**. 섞으면 422다 |

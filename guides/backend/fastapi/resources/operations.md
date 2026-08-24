<!-- epcc-pack: backend/fastapi v3.14.0 -->
# 운영 — 프로세스가 어떻게 뜨고, 어떻게 죽고, 무엇을 남기는가

이 파일은 **로깅 설정 · 헬스체크 · 풀 사이징 · 종료와 풀 반납 · 느린 쿼리 관측 ·
마이그레이션 배포 순서**를 소유한다. `engine`·`session_factory`·`get_session`의 정의는
`resources/data-access.md`가, `create_app`과 `lifespan`은 `resources/project-structure.md`가
소유한다 — 여기서는 그것들을 **부르고 관측할** 뿐이다.

## 1. 판단 — 무엇을 어디에 연결하는가

오케스트레이터는 프로브 결과로 **서로 다른 일**을 한다. 둘을 합치면 DB가 잠깐 흔들릴 때
멀쩡한 프로세스가 전부 재시작되고, 재시작 폭풍이 DB를 더 밀어붙인다.

| 프로브 | 무엇을 보나 | 실패하면 오케스트레이터가 | DB를 보나 |
| --- | --- | --- | --- |
| `GET /healthz` | 이벤트 루프가 응답하는가 | **프로세스를 죽인다** | 안 본다 |
| `GET /readyz` | 의존이 살아 있는가 | **트래픽만 뗀다** (프로세스는 산다) | `SELECT 1` |
| 기동 프로브 | 마이그레이션·예열이 끝났는가 | 기동 유예를 더 준다 | 안 본다 |

**`/healthz`가 DB를 보는 순간 그것은 헬스체크가 아니라 재시작 방아쇠다.** DB 순단 30초에
모든 파드가 죽으면, 돌아온 DB가 맞는 것은 커넥션 폭풍이다.

## 2. 로깅 설정 (`app/obs/logging.py`)

`configure_logging`은 **`create_app`보다 먼저**, 부팅 모듈의 임포트 시점에 부른다.
uvicorn은 자기 로거에 자기 핸들러를 달고 `propagate`를 끄기 때문에, 그 핸들러를 비우고
전파를 켜지 않으면 **uvicorn이 찍는 줄은 끝까지 JSON이 되지 않는다** — 애플리케이션 로그만
구조화되고 접근 로그는 평문으로 남는다 <!-- verified: uvicorn 0.52.4 실행, 로거 미조정 시 uvicorn 줄이 평문 형식으로만 출력 -->.

<!-- file: app/obs/logging.py -->
```python
import json
import logging
import sys
from typing import Any


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        for key, value in getattr(record, "extra_fields", {}).items():
            payload[key] = value
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        target = logging.getLogger(name)
        target.handlers = []          # uvicorn이 단 핸들러를 걷어낸다
        target.propagate = True       # 루트의 JSON 핸들러로 흘려보낸다
```

부팅 모듈(`app/main.py`, 정본은 `resources/project-structure.md`)이 `create_app()` **전에**
`configure_logging(settings.LOG_LEVEL)`을 부른다. 환경 값은 `settings`에서 온다 — 이 파일도,
아래 어떤 파일도 프로세스 환경을 직접 읽지 않는다(정책 `env-single-entry`).

임포트를 위에 모으든 호출 뒤로 미루든 **결과는 같다**: uvicorn은 앱 모듈을 임포트한 뒤에
자기 로깅을 세우므로, 두 형태의 출력이 한 줄도 다르지 않았다
<!-- verified: uvicorn 0.52.4로 두 형태를 각각 기동, 로그 9줄 전부 동일 -->. `noqa: E402`가
필요한 형태를 쓸 이유가 없다.

실측 출력 — uvicorn 자신의 줄까지 한 줄 JSON으로 나온다.

```
{"ts": "2026-08-24T00:51:20+0700", "level": "INFO", "logger": "uvicorn.error", "msg": "Application startup complete."}
{"ts": "2026-08-24T00:51:23+0700", "level": "INFO", "logger": "uvicorn.access", "msg": "127.0.0.1:63203 - \"GET /healthz HTTP/1.1\" 200"}
```

## 3. 헬스체크 (`app/obs/health.py`)

<!-- file: app/obs/health.py -->
```python
from fastapi import APIRouter, Response
from sqlalchemy import text

from app.db.session import engine

health_router = APIRouter()


@health_router.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@health_router.get("/readyz")
async def readyz(response: Response) -> dict[str, str]:
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception:
        response.status_code = 503
        return {"status": "unavailable"}
    return {"status": "ready"}
```

`/readyz`는 **예외 종류를 응답에 싣지 않는다.** 드라이버 예외 메시지에는 호스트·포트·
사용자명이 들어 있고, 이 경로는 대개 인증 밖이다. 로그에는 남기고 응답에는 넣지 않는다.

DB를 끊고 두 경로를 실제로 불러 갈리는 것을 확인했다 — `/healthz`는 계속 200이고
`/readyz`만 503이 된다 <!-- verified: 도달 불가 DB로 엔진 교체 후 실행, healthz=200 / readyz=503 -->.

| 상태 | `/healthz` | `/readyz` |
| --- | --- | --- |
| 정상 | 200 `{"status":"ok"}` | 200 `{"status":"ready"}` |
| DB 도달 불가 | **200** | **503** `{"status":"unavailable"}` |

## 4. 종료와 풀 반납 — `lifespan`

`lifespan`을 `create_app`이 `FastAPI(lifespan=lifespan)`로 넘기지 않으면 **조용히 안 돈다**.
붙였더라도 테스트의 `ASGITransport`에서는 돌지 않는다 — `resources/testing.md` §4를 본다.

```python
# app/factory.py — 발췌
@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))   # 첫 요청이 접속 비용을 내지 않게 예열한다
    yield
    await engine.dispose()                     # 풀의 커넥션을 실제로 닫는다
```

`await engine.dispose()`를 부르지 않고 프로세스를 끝내면 두 가지가 서로 다른 층에서 난다.
**한쪽은 그냥 나오고, 다른 쪽은 켜야만 보인다** — 그래서 "아무 경고도 없었다"는 근거가 되지 않는다.

| 무엇을 빠뜨렸나 | 무엇이 나오나 | 어디서 나오나 |
| --- | --- | --- |
| 커넥션을 풀에 반납하지 않았다 | `SAWarning: The garbage collector is trying to clean up non-checked-in connection …, which will be terminated.` | SQLAlchemy — 드라이버와 무관 <!-- verified: sqlalchemy 2.0.52, 아무 플래그 없이 기본 필터에서 출력됨(양성 대조) --> |
| 반납은 했지만 `dispose()`를 안 했다 | 드라이버가 내는 `ResourceWarning`. **기본 필터에서는 무시되어 아무것도 안 나온다** — `PYTHONWARNINGS=always`나 `python -W always`를 켜야 보인다 | DBAPI 드라이버 <!-- verified: 무플래그 실행은 0건, -W always/PYTHONWARNINGS=always에서 1건. aiosqlite로 관측했고 asyncpg 문구는 미검증 --> |

앞의 것은 **커넥션이 강제 종료된다**는 뜻이라 진짜 결함이고, 뒤의 것은 정리 누락이다.
서버 쪽에서 보면 `dispose()` 없이 죽은 프로세스는 DB에 유휴 세션을 남기고, 그 세션은
`tcp_keepalives`나 `idle_session_timeout`이 걷어갈 때까지 `max_connections`를 먹는다.

## 5. 풀 사이징

풀은 **프로세스마다** 만들어진다. 워커를 4개 띄우면 풀도 4개다.

```
프로세스당 최대 = pool_size + max_overflow
클러스터 최대   = 프로세스당 최대 × 워커 수 × 파드 수   ≤   max_connections - 예비분
```

**값은 여기서 정하지 않는다.** `engine`의 유일한 정의는 `resources/data-access.md`의
`app/db/session.py`이고, 아래는 그 인자들이 운영에서 무엇을 뜻하는지의 해설이다.

| 인자 | 운영에서의 뜻 |
| --- | --- |
| `pool_size` | 상시 유지분. 워커 수를 곱한 값이 DB 예산 안에 들어와야 한다 |
| `max_overflow` | 순간 폭주분. 반납되면 닫힌다 |
| `pool_timeout` | 못 얻었을 때 기다리는 한계. 길게 잡으면 고갈이 지표에서 사라진다 |
| `pool_recycle` | 중간 프록시가 끊는 유휴 커넥션을 먼저 버린다 |
| `pool_pre_ping` | 죽은 커넥션을 요청에 넘기지 않는다 (요청당 왕복 1회 비용) |

asyncpg 방언으로 실제 구성해 확인했다 — 풀 구현은 `AsyncAdaptedQueuePool`이고
`pool_size`·`max_overflow`·`pool_pre_ping`이 그대로 반영된다
<!-- verified: sqlalchemy 2.0.52 + asyncpg 0.31.0으로 엔진 구성, pool 클래스·size·_max_overflow·_pre_ping 판독 -->.

**`pool_timeout`을 크게 잡지 않는다.** 풀 고갈은 대개 느린 쿼리나 반납 누락의 결과인데,
오래 기다리면 그 원인이 지표에서 사라지고 응답 시간만 늘어난다.

## 6. 느린 쿼리 관측

SQLAlchemy의 커서 이벤트로 소요를 잰다. **비동기 엔진에는 직접 걸 수 없다** —
`AsyncEngine`에 걸면 `NotImplementedError: asynchronous events are not implemented at this
time.  Apply synchronous listeners to the AsyncEngine.sync_engine or
AsyncConnection.sync_connection attributes.` 가 난다
<!-- verified: sqlalchemy 2.0.52 실행, AsyncEngine 부착 시 NotImplementedError / sync_engine 부착은 성공 -->.
`engine.sync_engine`에 건다.

**이 모듈은 누군가 import해야 돈다.** 데코레이터 등록형이라 임포트되지 않으면 리스너가
아예 달리지 않는다 — 부팅 모듈에 `import app.obs.sql  # noqa: F401` 한 줄이 없으면 느린
쿼리 로깅은 영영 조용하다. 배선 없이 기동하면 `obs.sql` 줄이 **0건**, 한 줄을 넣으면 나온다
<!-- verified: uvicorn 0.52.4로 두 형태 기동, 미배선 0건 / 배선 후 2건(양성 대조) -->.

<!-- file: app/obs/sql.py -->
```python
# app/obs/sql.py — 느린 쿼리만 남긴다
import logging
import time

from sqlalchemy import event

from app.db.session import engine

log = logging.getLogger("obs.sql")
SLOW_MS = 200.0

@event.listens_for(engine.sync_engine, "before_cursor_execute")
def _before(conn, cursor, statement, parameters, context, executemany) -> None:
    conn.info.setdefault("t0", []).append(time.perf_counter())

@event.listens_for(engine.sync_engine, "after_cursor_execute")
def _after(conn, cursor, statement, parameters, context, executemany) -> None:
    elapsed_ms = (time.perf_counter() - conn.info["t0"].pop(-1)) * 1000
    if elapsed_ms >= SLOW_MS:
        log.warning("slow query", extra={"extra_fields": {
            "ms": round(elapsed_ms, 1), "sql": statement[:200]}})
```

- **시각은 `conn.info`에 스택으로 쌓는다.** 모듈 전역 변수에 넣으면 동시 요청끼리 서로의
  시작 시각을 덮어쓴다. 중첩 실행이 있어도 리스트면 짝이 맞는다
- **`parameters`를 로그에 넣지 않는다.** 바인딩 값에 사용자 데이터가 그대로 들어 있다
- 문장은 잘라서 남긴다. 자르지 않으면 느린 쿼리 한 건이 로그 예산을 먹는다

실제로 async 엔진에서 이벤트가 발화하고 소요가 측정되는 것을 확인했다(`SELECT 1`에
0.178 ms) <!-- verified: sqlalchemy 2.0.52 async 엔진에서 before/after_cursor_execute 발화 및 계측값 획득 -->.

느려지는 것은 대개 목록 쿼리다. 이 축의 목록은 **소유자 + 정렬 키**로 도는데, 그 복합
인덱스가 없으면 전체 스캔이 된다.

```python
# 인덱스를 타는 형태(개념) — 실제 list_tasks 정본은 data-access.md가 소유한다
stmt = (
    select(Task)
    .where(Task.owner_id == owner_id)
    .order_by(Task.created_at.desc(), Task.id.desc())
    .limit(limit)
)
```

## 7. 마이그레이션 배포 순서

**스키마와 코드는 동시에 바뀌지 않는다.** 롤링 배포 중에는 옛 코드와 새 코드가 같은 DB를
동시에 본다. 그래서 한 번에 하나씩, **되돌릴 수 있는 방향으로만** 움직인다.

| 단계 | 무엇을 한다 | 이때 도는 코드 |
| --- | --- | --- |
| 1 확장 | 컬럼·인덱스를 **추가**한다. `NOT NULL`은 아직 걸지 않는다 | 옛 코드 (새 컬럼을 모른다) |
| 2 배포 | 새 컬럼을 읽고 **쓰는** 코드를 내보낸다 | 옛/새 혼재 |
| 3 채움 | 남은 행을 배치로 채운다 | 새 코드 |
| 4 조임 | `NOT NULL`·유니크 제약을 건다 | 새 코드 |
| 5 축소 | 옛 컬럼을 **다음 배포에서** 지운다 | 새 코드만 |

- **`alembic upgrade head`는 앱 기동 훅이 아니라 배포 단계로 돌린다.** 기동 시 돌리면
  파드 N개가 동시에 같은 마이그레이션을 잡는다 <!-- unverified -->
- **자동생성본은 읽고 고친 뒤 커밋한다.** 인덱스 이름·타입 변경·데이터 이전을 자동생성이
  알아서 하지 못한다. `owner_id` 복합 인덱스가 빠지면 §6의 목록이 전체 스캔이 된다
- 큰 테이블의 인덱스는 **`CREATE INDEX CONCURRENTLY`**로 만든다. 일반 `CREATE INDEX`는
  쓰기를 막고, Alembic 자동생성은 그것을 골라 주지 않는다. 다만 **트랜잭션 블록 안에서는
  돌지 않는다** — Alembic은 마이그레이션을 트랜잭션으로 감싸므로
  `with op.get_context().autocommit_block():` 안에서
  `op.create_index(..., postgresql_concurrently=True)`를 부른다 <!-- unverified: PostgreSQL 서버 없음 -->

채우는 마이그레이션은 **몇 행을 건드렸는지 확인한다.** 0행은 성공이 아니라 대개 조건이 틀린 것이다.

```python
# alembic/versions/xxxx_backfill_status.py — 발췌
result = op.get_bind().execute(
    sa.text("UPDATE tasks SET status = 'open' WHERE status IS NULL")
)
if result.rowcount == 0:
    print("backfill matched 0 rows — 조건을 확인한다")
```

## 오용 목록 ① — 단일 프로세스 관용구 → 다중 워커 형태 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `/health` 하나로 생존·준비를 겸한다 | `/healthz`(DB 안 봄) · `/readyz`(`SELECT 1`)로 가른다 |
| `print()`로 관측한다 | 루트 핸들러 + `JsonFormatter`, uvicorn 로거는 전파시킨다 |
| `create_app()` 뒤에 로깅을 설정한다 | 부팅 모듈 임포트 시점, `create_app`보다 먼저 |
| 기동 훅에서 `alembic upgrade head` | 배포 파이프라인의 별도 단계로 뺀다 |
| 풀 크기를 파드 기준으로 잡는다 | 프로세스마다 풀이 하나다. 워커 수를 곱한다 |
| `AsyncEngine`에 커서 이벤트를 건다 | `engine.sync_engine`에 건다 |
| 종료 시 그냥 프로세스를 죽인다 | `lifespan` 종료에서 `await engine.dispose()` |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `/healthz` vs `/readyz` | 재시작시킬 것만 `/healthz`. 의존 확인은 `/readyz` |
| `pool_size` vs `max_overflow` | 상시 부하는 앞, 순간 폭주는 뒤. 합이 예산이다 |
| `pool_pre_ping` vs `pool_recycle` | 죽은 커넥션 탐지는 앞, 유휴 만료 예방은 뒤. 함께 쓴다 |
| `engine.dispose()` vs 커넥션 `close()` | 풀 전체 정리는 앞, 요청 단위 반납은 뒤 |
| `before_cursor_execute` vs 미들웨어 계측 | 쿼리 소요는 앞, 요청 소요는 뒤. 둘은 다른 값이다 |
| 확장 후 즉시 축소 vs 다음 배포에서 축소 | 롤링 중 옛 코드가 살아 있으면 축소는 다음 배포다 |

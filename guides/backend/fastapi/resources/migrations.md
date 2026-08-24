<!-- epcc-pack: backend/fastapi v3.14.0 -->
# 마이그레이션 — 배포 시점에 도는 코드

`alembic/` 전부를 소유한다: `env.py` 배선 · 자동생성의 한계 · 확장-축소 · 백필 · 배포 순서.
스키마를 **정의하는** 것(`Base`·`Task`·인덱스)은 `resources/data-access.md`가, 프로세스 기동
(`create_app`·`lifespan`)은 `resources/project-structure.md`가, 헬스체크·풀·관측은
`resources/operations.md`가 소유한다.

> **소유권 규율의 유일한 예외 문맥이다.** 이 축의 1원칙은 「소유권은 `WHERE`에 있다」이지만,
> 마이그레이션은 요청이 아니라 배포로 도므로 **주체가 없고 전 소유자의 행을 대상으로 한다** —
> 이 파일의 `WHERE`에 `owner_id`가 없는 것은 정상이고, **여기서만** 정상이다.

> **마이그레이션은 요청 시점이 아니라 배포 시점에 돈다.** 쿼리는 초당 수백 번 돌고 되돌릴 수
> 있지만, 마이그레이션은 한 번 돌고 **데이터를 지운 뒤에는 되돌릴 수 없다.** 수명이 다르므로
> 규율도 다르다 — 자동생성본을 읽지 않고 커밋하는 것이 이 파일이 막는 유일한 습관이다.

## 1. 결정 트리 — 이 변경을 자동생성에 맡기는가

| 무엇이 바뀌는가 | 어떻게 가르는가 |
| --- | --- |
| 표·컬럼·인덱스 **추가** | 자동생성 초안을 쓴다. 인덱스 이름만 읽고 확인한다 |
| 컬럼 **이름 변경** | **손으로 쓴다.** 자동생성은 `add_column`+`drop_column`을 내고 값을 옮기지 않는다 (§3) |
| 타입 변경 · `NOT NULL` 조임 | 기존 행이 새 제약을 만족해야 한다 — 백필이 **먼저**다 (§4·§5) |
| 컬럼 **삭제** | **두 배포로 가른다.** 옛 코드가 아직 그 컬럼을 읽는다 (§4) |
| `server_default` 추가·변경 | **손으로 쓴다.** 기본 설정의 자동생성이 보지 못한다 (§3) |
| 데이터만 바꾼다 (백필) | DDL 과 **다른 리비전**으로 가른다 (§5) |
| 큰 표에 인덱스 추가 | `CONCURRENTLY` + `autocommit_block` (§6) |

**자동생성은 초안이지 결과물이 아니다.** 위 표에서 「손으로 쓴다」로 갈린 것들은 자동생성이
**틀린 것을 내는** 것이 아니라 **그럴듯한 것을 내는** 자리다 — 문법이 완벽하고 실행도 되는데
데이터가 사라진다. 그래서 생성 직후 `alembic/versions/`의 파일을 여는 것이 단계에 들어 있다
(`PACK.md` Quick Start 2번).

## 2. 배선 (`alembic/env.py`) — async 엔진 위에서 동기 Alembic 을 돌린다

Alembic 의 마이그레이션 실행은 **동기**다. 이 축의 엔진은 async 이므로 `connection.run_sync()`로
동기 함수를 async 커넥션 위에 태운다. 접속 문자열은 `settings`에서만 온다 — `alembic.ini`의
`sqlalchemy.url`은 비워 두고 `env.py`가 덮어쓴다 (정책 `env-single-entry`).

<!-- file: alembic/env.py -->
```python
import asyncio

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

import app.db.tasks  # noqa: F401  — 없으면 metadata 가 비어 자동생성이 "변경 없음"을 낸다
from app.db.base import Base
from app.settings import settings

config = context.config
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL.replace("%", "%%"))
target_metadata = Base.metadata


def _run(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def _main() -> None:
    engine = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.", poolclass=pool.NullPool,   # 마이그레이션에 풀은 필요 없다
    )
    async with engine.connect() as connection:
        await connection.run_sync(_run)     # async 커넥션 위에서 동기 Alembic 을 돌린다
    await engine.dispose()


asyncio.run(_main())
```

**`import app.db.tasks` 한 줄이 자동생성의 전제다.** `Base.metadata`는 모델 모듈이 임포트될 때
채워지므로, 이 줄이 없으면 `Base.metadata.tables`가 `[]`이고 자동생성은 **아무 것도 없는 것이
아니라 「변경 없음」**을 낸다 — 즉 실패가 아니라 조용한 통과다. import 전 `[]` · 후 `['tasks']`,
그리고 그 상태로 돌린 자동생성 본문이 `pass` 하나였다.
<!-- verified: alembic 1.19.1 · env.py 에서 import 를 지우고 revision --autogenerate 실행, upgrade 본문이 pass. 되돌리면 create_table 생성(양성 대조) -->

**`.replace("%", "%%")`는 장식이 아니다.** `set_main_option`은 값을 ConfigParser 에 넣고,
ConfigParser 는 `%`를 보간 문법으로 읽는다 — 비밀번호에 `%`가 든 DSN 은 **부팅이 아니라
마이그레이션 실행 시점에** `ValueError: invalid interpolation syntax` 로 죽는다. 이 팩은
`settings` 한 곳에서만 접속 문자열을 읽으므로(정책 `env-single-entry`) 이 경로가 유일한 통로다.
<!-- verified: alembic 1.19.1 · DSN `…u:p%ss@db…` 로 재현 — 이스케이프 없이 ValueError(position 24), `%%` 로는 원본과 동일한 문자열로 읽힘. `%` 없는 DSN 에 걸어도 값이 변하지 않는 것까지 확인(회귀) -->

위 파일은 **온라인 모드만** 담는다. `--sql`(오프라인) 출력이 필요하면 `context.is_offline_mode()`
분기를 더한다 — 이 팩의 배포 경로는 온라인 실행이라 기본형에 넣지 않았다.

## 3. 자동생성이 보지 못하는 것

| 자동생성이 하는 것 | 자동생성이 **못 하는** 것 |
| --- | --- |
| 표·컬럼·인덱스 추가, 이름 있는 제약의 추가·삭제, 타입 변경 | **컬럼 이름 변경** — `add_column`+`drop_column`으로 나온다. 새 컬럼은 `NULL`로 생기고 옛 값은 옮겨지지 않는다 |
| 인덱스 추가·삭제 (`Index(...)` 선언 기준) | **데이터 이전·백필** — 스키마 차이만 보므로 행은 보지 않는다 |
| — | **`server_default`** — 기본 설정에서 비교하지 않는다. `compare_server_default=True`를 주면 `alter_column`을 만들지만 방언별 신뢰도가 낮아 이 팩은 켜지 않는다 <!-- verified: alembic 1.19.1 · 모델에 server_default 를 심고 두 설정으로 각각 생성 — 기본은 본문 pass, 플래그를 켜면 alter_column. SQLite 로 대리, PG 방언 신뢰도는 미검증 --> |

이름 변경이 가장 비싸다. `title` → `label`로 모델만 고치고 자동생성을 돌리면 이 둘이 나온다.

```python
# ❌ 자동생성이 내놓은 그대로 — 실행되고, 데이터는 사라진다
op.add_column("tasks", sa.Column("label", sa.String(200), nullable=True))
op.drop_column("tasks", "title")
# ✅ 손으로 고친다 — 이름만 바꾸면 값이 그대로 따라온다
op.alter_column("tasks", "title", new_column_name="label")
```

행 하나(`title='원래 값'`)를 넣고 위 두 문장을 그대로 돌리면 `label`이 `NULL`이 되고 `title`은
사라진다 — **실패가 아니라 성공으로 끝난다.**
<!-- verified: 값이 든 표에 두 형태를 각각 실행하고 다시 읽음 — add_column+drop_column 은 '원래 값' → None, alter_column(new_column_name) 은 '원래 값' 유지에 downgrade 왕복까지 성공(양성 대조). SQLite 로 대리 -->

`nullable=False`로 나온 경우는 사정이 다르다. 행이 있는 표에 기본값 없는 `NOT NULL` 컬럼을
더하는 것은 **DB 가 거부한다** — 그래서 이름 변경이 「조용히」 데이터를 지우는 것은 새 컬럼이
`NULL` 허용일 때다. 두 경우가 다르므로 생성물의 `nullable`을 반드시 읽는다.
<!-- verified: SQLite 로 대리 — "Cannot add a NOT NULL column with default value NULL" 로 중단. PG 의 문구·거동은 미검증 -->

## 4. 확장-축소 — 롤링 배포 중에는 두 벌의 코드가 같은 DB를 본다

**스키마와 코드는 동시에 바뀌지 않는다.** 배포가 도는 동안 옛 파드와 새 파드가 함께 살아 있으므로,
한 번에 하나씩 **되돌릴 수 있는 방향으로만** 움직인다.

| 단계 | 무엇을 한다 | 이때 도는 코드 |
| --- | --- | --- |
| 1 확장 | 컬럼·인덱스를 **추가**한다. `NOT NULL`은 아직 걸지 않는다 | 옛 코드 (새 컬럼을 모른다) |
| 2 배포 | 새 컬럼을 읽고 **쓰는** 코드를 내보낸다 | 옛/새 혼재 |
| 3 채움 | 남은 행을 배치로 채운다 (§5) | 새 코드 |
| 4 조임 | `NOT NULL`·유니크 제약을 건다 | 새 코드 |
| 5 축소 | 옛 컬럼을 **다음 배포에서** 지운다 | 새 코드만 |

**1 과 4 를 한 리비전에 합치면 2 단계가 사라진다.** 옛 코드는 새 컬럼에 값을 넣지 않으므로
`NOT NULL`이 즉시 걸리면 옛 파드의 `INSERT`가 전부 실패한다 — 배포가 절반쯤 진행된 시점에서
가장 아프게 터진다. 5 를 앞당기면 반대로 옛 파드의 `SELECT`가 없는 컬럼을 읽는다.

축소는 **다음 배포**다. 롤백 여지를 남기는 것이 목적이므로, 4 까지 끝난 뒤에도 한 배포를
기다렸다가 지운다.

## 5. 백필 — `rowcount`를 확인한다

**0행은 성공이 아니라 대개 조건이 틀린 것이다.** 백필은 조용히 아무 것도 안 해도 초록으로
끝나므로, 갱신 행 수를 세어 0이면 멈춘다. 아래 `priority` 는 **§4 의 1 단계로 더한 예제 전용
컬럼**이다 — `Task` 모델에는 없다(원장의 「예제에 등장하는 앱 심볼」).

```python
# alembic/versions/xxxx_backfill_priority.py — 발췌
BATCH = 1000

def upgrade() -> None:
    bind = op.get_bind()
    total = 0
    while True:                       # 한 문장으로 전 행을 잠그지 않는다
        result = bind.execute(sa.text(
            "UPDATE tasks SET priority = 0 WHERE id IN ("
            " SELECT id FROM tasks WHERE priority IS NULL LIMIT :n)"), {"n": BATCH})
        if result.rowcount == 0:      # 더 채울 행이 없다 — 정상 종료
            break
        total += result.rowcount
    if total == 0:                    # 한 행도 못 찾았다 — 조건을 의심한다
        raise RuntimeError("backfill matched 0 rows — 조건을 확인한다")

def downgrade() -> None:
    # 되돌릴 것이 없다: 옛 값을 어디에도 남기지 않았으므로 되살릴 수 없다.
    # 이 리비전은 DDL 을 만들지 않았다 — 스키마는 앞 리비전이 되돌린다.
    pass
```

배치로 도는 이유는 잠금이다. 한 `UPDATE`가 전 행을 건드리면 그 트랜잭션이 끝날 때까지 쓰기가
밀린다. `LIMIT`로 끊으면 각 배치가 짧게 잠그고 끝난다.

시드 3행에서 `총 3` 뒤 다음 배치가 `rowcount == 0`으로 정상 종료했고, 같은 마이그레이션의
조건을 틀린 값으로 바꾸면 `총 0`으로 `RuntimeError`가 나 배포가 멈췄다 — **양성·음성 두 경우를
같은 스크립트로 확인했다.**
<!-- verified: alembic 1.19.1 · 3행 시드에서 갱신 3 → 다음 배치 0 으로 종료. WHERE 를 매칭 불가 조건으로 바꾸면 갱신 0 → RuntimeError. SQLite 로 대리 -->

**DDL 과 백필을 한 리비전에 섞지 않는다.** 백필이 중간에 실패했을 때 앞의 DDL 이 함께
되돌아가는지는 DB 의 트랜잭션 DDL 지원에 달려 있고, 되돌아가지 않으면 **버전 스탬프는 옛
리비전인데 스키마는 이미 바뀐** 상태가 남아 재실행이 막힌다. 실측에서 정확히 그렇게 됐다:
스탬프는 직전 리비전으로 돌아갔지만 추가된 컬럼은 남았고, 다시 돌리자 `duplicate column name`
으로 죽었다.
<!-- verified: SQLite(aiosqlite) 로 대리 — 실패 후 alembic current 는 직전 리비전, PRAGMA table_info 에는 컬럼이 남음. PostgreSQL 의 트랜잭션 DDL 거동은 미검증 -->

## 6. `CREATE INDEX CONCURRENTLY` — 트랜잭션 밖에서 불러야 한다

큰 표에 일반 `CREATE INDEX`를 걸면 인덱스가 만들어지는 동안 **쓰기가 막힌다.** PostgreSQL 의
`CONCURRENTLY`가 그것을 피하지만 **트랜잭션 블록 안에서는 돌지 않고**, Alembic 은 마이그레이션을
트랜잭션으로 감싼다. 그래서 `autocommit_block()`으로 그 구간만 빠져나온다.

**이것은 이미 운영 중인 표에 인덱스를 뒤늦게 더할 때의 형태다.** 기본형의
`ix_tasks_owner_created_id`(키셋 페이지네이션의 전제)는 `data-access.md`가 `__table_args__`로
선언하고 **초기 리비전의 자동생성이 만든다** — 빈 표라 잠글 쓰기가 없다. 아래는 나중에
`status` 조회가 느려져 새 인덱스를 더하는 경우다.

```python
# alembic/versions/xxxx_add_status_index.py — 발췌
def upgrade() -> None:
    with op.get_context().autocommit_block():   # 이 안은 트랜잭션 밖이다
        op.create_index("ix_tasks_owner_status", "tasks", ["owner_id", "status"],
                        postgresql_concurrently=True, if_not_exists=True)

def downgrade() -> None:
    with op.get_context().autocommit_block():   # 삭제도 같은 규율을 탄다
        op.drop_index("ix_tasks_owner_status", "tasks",
                      postgresql_concurrently=True, if_exists=True)
```

`postgresql_concurrently=True`가 PG 방언에서 실제로 `CREATE INDEX CONCURRENTLY`로 컴파일되는
것과, 플래그 없는 같은 인덱스가 `CREATE INDEX`로 나오는 것을 대조했다. `autocommit_block`은
`MigrationContext`에 있다.
<!-- verified: sqlalchemy 2.0.52 postgresql 방언으로 CreateIndex 컴파일만 대조(양성·음성) · alembic 1.19.1 MigrationContext.autocommit_block 존재 확인. **서버 실행은 미검증** -->

**`autocommit_block` 안은 되돌아가지 않는다.** 그 구간에서 실패하면 인덱스가 `INVALID` 상태로
남을 수 있고, 그때는 지우고 다시 만든다 — 그래서 이 리비전에는 다른 것을 담지 않는다.
<!-- unverified: PostgreSQL 서버 없음 — INVALID 인덱스의 실제 상태 전이를 관측하지 못했다 -->

## 7. 언제 돌리는가 — `upgrade head`는 배포 단계다

**앱 기동 훅에서 돌리지 않는다.** 파드 N개가 동시에 뜨면 N개가 같은 마이그레이션을 잡고,
먼저 잡은 하나 외에는 실패하거나 대기한다. 실패하면 그 파드는 기동에 실패한 것으로 취급돼
재시작 루프에 들어간다 — 마이그레이션 한 건이 배포 전체를 흔든다. <!-- unverified: 다중 파드 경합을 실물로 재현하지 못했다 -->

배포 파이프라인의 **별도 단계**로 뺀다: 마이그레이션 잡 하나가 `upgrade head`를 돌려 끝내고,
그 다음에 새 코드가 롤아웃된다. §4 의 1 단계가 이 잡이다.

**다운그레이드는 배포 도구가 아니다.** `downgrade()`를 쓰는 자리는 **로컬과 CI 의 왕복 시험**
(§8)이고, 운영에서 되돌리는 수단으로 기대하지 않는다 — `drop_column`의 역방향은 컬럼을 되살릴
뿐 **값을 되살리지 못한다.** 그래서:

- `downgrade()`를 **비워 두지 않는다** — §8 의 왕복이 돌지 않는다
- 데이터를 지우는 리비전은 `downgrade()`에 되살릴 수 없다는 것을 주석으로 명시한다
- 운영의 되돌림은 다운그레이드가 아니라 **§4 의 확장-축소**다. 축소를 미루는 이유가 이것이다

## 8. 마이그레이션을 테스트한다 — 왕복과 빈 diff

```bash
uv run alembic upgrade head      # 적용
uv run alembic downgrade -1      # 방금 쓴 리비전 한 칸만 되돌린다
uv run alembic upgrade head      # 다시 — 셋이 모두 성공해야 한다
uv run alembic check             # 모델과 스키마가 어긋나면 여기서 드러난다
```

**두 값의 역할이 다르다.** 리비전을 하나 쓸 때마다 도는 것은 `downgrade -1`(방금 쓴 것만
되돌아가는가)이고, CI 가 도는 **전체 왕복**은 `downgrade base` → `upgrade head`(첫 리비전부터
전부 되감기는가)다. 아래 실측은 뒤쪽이다.

`alembic check`는 **생성물을 남기지 않고** 드리프트만 판정한다. 깨끗하면
`No new upgrade operations detected.`와 종료 코드 0, 어긋나면 `FAILED: New upgrade operations
detected: [...]`와 **0이 아닌 종료 코드**를 낸다 — 그래서 CI 단계로 그대로 쓸 수 있다.
모델에 컬럼 하나를 심어 실패를, 되돌려 통과를 각각 확인했다.
<!-- verified: alembic 1.19.1 · 드리프트 심음 → FAILED + 종료 코드 255(양성 대조), 되돌림 → 통과 + 0. SQLite 로 대리 -->

왕복이 잡는 것은 **`downgrade()`가 실제로 도는가**이고, `check`가 잡는 것은 **모델과 마이그레이션이
같은 스키마를 말하는가**다. 둘은 다른 결함을 잡으므로 하나로 대신하지 않는다 — 손으로 고친
자동생성본은 `upgrade()`만 고치고 `downgrade()`를 그대로 두기 쉽고, 그 결함은 왕복에서만 나온다.

`upgrade head` → `downgrade base` → `upgrade head` 왕복 뒤 `check`가 통과하고, 그 상태에서
`revision --autogenerate`가 본문 `pass` 하나(빈 diff)를 내는 것을 확인했다.
<!-- verified: alembic 1.19.1 + sqlalchemy 2.0.52 + aiosqlite 0.22.1 · 위 네 명령을 순서대로 실행. PG 왕복은 미검증 -->

**테스트 스위트는 이 검증을 대신하지 않는다.** `resources/testing.md`의 테스트 DB 는
`Base.metadata.create_all`로 만들어 마이그레이션을 한 번도 돌리지 않는다 — 그래서 위 네 명령은
**pytest 와 별개의 CI 단계**여야 하고, 빠지면 마이그레이션 결함은 어떤 초록도 빨갛게 만들지 못한다.

## 오용 목록 ① — 동기 Alembic 템플릿 → async 형태 대조표

| 구 습관 (동기 템플릿) | 현재 형태 (async 엔진) |
| --- | --- |
| `engine_from_config` + `with connectable.connect()` | `async_engine_from_config` + `await connection.run_sync(...)` |
| `target_metadata = None` 인 채로 자동생성 | 모델 모듈 import + `target_metadata = Base.metadata` |
| `alembic.ini`의 `sqlalchemy.url`에 접속 문자열을 적는다 | `env.py`가 `settings.DATABASE_URL`로 덮어쓴다 |
| 기동 훅에서 `alembic upgrade head` | 배포 파이프라인의 별도 단계로 뺀다 |
| 자동생성본을 읽지 않고 커밋 | 열어서 `nullable`·인덱스 이름·이름 변경 여부를 읽고 고친다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `alembic check` vs `revision --autogenerate` | 드리프트 **판정**은 앞(파일을 남기지 않는다), 실제 **작성**은 뒤 |
| `downgrade -1` vs `downgrade base` | **직전 리비전 한 칸**을 시험하는 것은 앞, **전체 왕복**을 검증하는 것은 뒤(§8) |
| 확장 후 즉시 축소 vs 다음 배포에서 축소 | 롤링 중 옛 코드가 살아 있으면 축소는 다음 배포다 |
| `alter_column(new_column_name=…)` vs `add_column`+`drop_column` | 이름만 바꾸는 것은 앞. 뒤는 값을 옮기지 않는다 |
| DDL 과 백필을 한 리비전에 vs 나눠서 | 나눈다. 섞으면 실패 시 스탬프와 스키마가 갈린다 |

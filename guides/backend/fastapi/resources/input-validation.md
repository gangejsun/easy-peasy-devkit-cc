<!-- epcc-pack: backend/fastapi v3.14.0 -->
# 입력 검증 — 요청 본문·쿼리·환경을 같은 장치로 잠근다

이 파일이 소유하는 것은 `app/schemas/task.py`(요청·응답 스키마와 `TaskStatus` 열거)와
`app/settings.py`(환경 스키마)다. 검증 **실패를 응답으로 바꾸는 일**은 소유하지 않는다 —
`app/http/errors.py`(→ `error-handling.md`)와 이음매의 `install_error_handlers`가 한다.
검증된 값을 SQL로 옮기는 일도 소유하지 않는다(`app/db/tasks.py` → `data-access.md`).

## 1. 결정 트리 — 입력마다 실패 시점이 다르다

| 들어오는 것 | 받는 자리 | 실패 시점 | 실패 형태 |
| --- | --- | --- | --- |
| 요청 본문 | `TaskCreate` · `TaskUpdate` 파라미터 | 요청 | `RequestValidationError` → 422 |
| 쿼리스트링 | `Annotated[TaskQuery, Query()]` | 요청 | `RequestValidationError` → 422 |
| 경로 파라미터 | `task_id: UUID` 어노테이션 | 요청 | `RequestValidationError` → 422 |
| 커서 문자열 | `decode_cursor` (`data-access.md`) | 요청 | `AppError("VALIDATION_FAILED")` |
| 인증 주체 | `current_user` (이음매) | 요청 | `AppError("UNAUTHENTICATED")` |
| 프로세스 환경 | `Settings` | **부팅** | `ValidationError` → 프로세스가 뜨지 않는다 |

**요청 입력은 422로 끝나고 환경 입력은 부팅 실패로 끝난다.** 이 축에는 행 수준 정책 엔진이
없어서 애플리케이션이 통과시킨 값은 그대로 DB에 들어간다. 스키마가 유일한 문지기다.

`owner_id`는 이 표에 없다. **클라이언트가 보낸 소유자를 스키마로 받지 않는다** — 소유자는
`current_user`에서만 오고, 본문에 `owner_id`가 실려 오면 `extra="forbid"`가 422로 거절한다.

## 2. 스키마 모듈 (`app/schemas/task.py`)

한 파일이 요청·응답·열거를 모두 갖는다. 모델(`data-access.md`)과 스키마가 **같은
`TaskStatus`를 import해서 쓴다** — 열거를 두 벌 두면 한쪽만 값이 늘어난다.

<!-- file: app/schemas/task.py -->
```python
# app/schemas/task.py
from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class TaskStatus(StrEnum):
    OPEN = "open"
    DONE = "done"


class TaskCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1, max_length=200)
    status: TaskStatus = TaskStatus.OPEN


class TaskUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    # ✅ 선택 필드의 기본값은 None만이다 — 보낸 것과 안 보낸 것을 가르는 유일한 표식이다
    title: str | None = Field(default=None, min_length=1, max_length=200)
    status: TaskStatus | None = None

    @field_validator("title", "status")
    @classmethod
    def _reject_explicit_null(cls, value: object) -> object:
        # 생략된 필드는 여기 오지 않는다 (기본값은 검증하지 않는 것이 pydantic 기본 동작)
        if value is None:
            raise ValueError("null로 필드를 지울 수 없다")
        return value

    @model_validator(mode="after")
    def _reject_empty_patch(self) -> TaskUpdate:
        if not self.model_fields_set:
            raise ValueError("수정할 필드를 최소 하나 보낸다")
        return self


class TaskQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None
    status: TaskStatus | None = None


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    status: TaskStatus
    created_at: datetime
```

다섯 스키마 전부 `extra="forbid"`이거나 응답 전용이다. `TaskQuery`의 `forbid`는 **받는
방식에 따라 켜지고 꺼진다** — 6절이 그 조건을 다룬다.

## 3. 부분 수정 — `exclude_unset=True`가 유일한 안전장치다

`PATCH`는 "보낸 필드만 바꾼다"는 뜻이다. `model_dump()`는 **보내지 않은 필드도 기본값으로
채워서** 돌려주므로 그대로 `UPDATE`에 넘기면 나머지 컬럼이 덮어써진다.

```text
>>> TaskUpdate.model_validate({"status": "done"})   # pydantic 2.13.4 실행 출력
model_dump()                  = {'title': None, 'status': <TaskStatus.DONE: 'done'>}
model_dump(exclude_unset=True) = {'status': <TaskStatus.DONE: 'done'>}
model_fields_set               = {'status'}
```

`title: None`이 실려 나가는 것이 보인다. 라우터가 이것을 그대로 넘기면 제목이 지워진다.
그래서 **`patch`를 만드는 쪽이 라우터의 의무**다 — `update_task`는 이미 걸러진 dict를 받는다.

```python
# app/http/routers.py (발췌 — 라우터 본체는 이음매가 소유한다)
patch = body.model_dump(exclude_unset=True)
task = await update_task(session, user.id, task_id, patch)
```

기본값을 `None`이 아닌 것으로 두면 `exclude_unset`조차 구하지 못한다. `title: str = ""`로
바꾼 모델을 같은 입력으로 돌리면 `model_dump()`가 `{'title': '', ...}`를 준다 — 문법은 완벽하고
타입 검사도 통과하며, 제목만 조용히 빈 문자열이 된다.

```python
# tests/test_schemas.py (발췌)
def test_partial_update_carries_only_sent_fields() -> None:
    patch = TaskUpdate.model_validate({"status": "done"}).model_dump(exclude_unset=True)
    assert patch == {"status": TaskStatus.DONE}  # ✅ 보낸 것은 실린다
    assert "title" not in patch                  # ✅ 안 보낸 것은 실리지 않는다
```

두 단언을 **같은 함수 안에** 건다. `not in`만 걸면 `model_dump`를 통째로 `{}`로 바꿔도 초록이다.

## 4. 명시적 `null`과 빈 본문 — `exclude_unset`이 막지 못하는 두 구멍

`{"title": null}`은 **보낸 필드**다. `model_fields_set`에 `title`이 들어가므로
`exclude_unset=True`를 통과하고 `patch == {'title': None}`이 되어 NOT NULL 컬럼에 닿는다.
`{}`(빈 본문)은 반대로 아무것도 안 담긴 `patch`를 만들어 0행 `UPDATE`를 날린다.

2절의 두 검증기가 각각을 422로 돌린다. 실행 출력:

```text
TaskUpdate.model_validate({"title": None}) -> loc=('title',)  type=value_error  msg=Value error, null로 필드를 지울 수 없다
TaskUpdate.model_validate({})              -> loc=()          type=value_error  msg=Value error, 수정할 필드를 최소 하나 보낸다
```

`field_validator`가 생략된 필드를 건드리지 않는 것이 핵심이다 — `{"status": "done"}`을 넣으면
`title`은 검증기를 **거치지 않고** `patch`에서도 빠진다(실행 확인). `mode="after"` 모델
검증기의 `loc`은 빈 튜플이라 필드에 붙지 않는다 — `error-handling.md` 5절이 그 처리다.

## 5. 미지 키 — `extra`의 세 값은 서로 다른 사고를 낸다

`{"title": "t", "owner_id": "attacker", "is_admin": true}`를 세 설정에 각각 넣은 실행 결과다.

| `extra` | 결과 | 이 축에서의 의미 |
| --- | --- | --- |
| `"ignore"` (기본값) | `{'title': 't'}` — 조용히 버린다 | 오타 필드가 무시돼 "저장했다"는 200이 나간다 |
| `"forbid"` | 422, `loc=('owner_id',)`·`loc=('is_admin',)` 두 건 | 권한 상승 시도가 **요청 단계에서** 죽는다 |
| `"allow"` | `{'title': 't', 'owner_id': 'attacker', 'is_admin': True}` | `model_dump()`가 미지 키를 실어 나른다 |

`"allow"`는 이 축에서 특히 위험하다. `model_dump()` 결과를 `UPDATE`의 `patch`로 쓰는 순간
클라이언트가 이름 붙인 컬럼이 그대로 SQL에 닿는다. **요청 본문 스키마는 전부 `"forbid"`다.**

## 6. 목록 쿼리 — `Annotated[TaskQuery, Query()]`로 받는다

`Depends()`로 받으면 FastAPI가 모델을 통째로 검증하지 않고 **필드마다 개별 쿼리 파라미터를
만들어** 전부 넘긴다. 그 경로에서는 `extra="forbid"`가 **아무 일도 하지 않는다.** 같은
스키마·같은 요청으로 두 방식을 계측한 결과다.

```text
>>> GET /api/tasks?limit=5&utm_source=ad   (TaskQuery는 extra="forbid"다)
q: TaskQuery = Depends()           -> 200  {"limit":5,"cursor":null,"status":null}
q: Annotated[TaskQuery, Query()]   -> 422  loc=['query','utm_source'] type=extra_forbidden
>>> GET /api/tasks?limit=5                 (미지 파라미터 없음 — 양성 대조군)
q: Annotated[TaskQuery, Query()]   -> 200  {"limit":5}
```

마지막 줄이 대조군이다. **거절만 계측하면 그 경로가 그냥 전부 422인지 알 수 없다** — 정상
요청이 200을 받는 것까지 봐야 422가 "차단"이라는 뜻이 된다.

```python
# app/http/routers.py (발췌 — 라우터 본체는 이음매가 소유한다)
@router.get("")
async def list_route(q: Annotated[TaskQuery, Query()], ...): ...
```

`Depends()` 경로는 `exclude_unset=True`를 걸어도 **모든 필드를 준다**(FastAPI가 전부 명시로
넘긴 탓이다). `Annotated` 경로는 보낸 것만 준다 — 위 출력의 `{"limit":5}`가 그것이다.
어느 쪽이든 첫 페이지 판정은 `cursor`가 `None`인지로 하고, `model_fields_set`으로는 하지 않는다.

## 7. 응답 스키마 — ORM을 그대로 반환하지 않는다

`from_attributes=True`가 붙은 `TaskOut`만 응답에 쓴다. `Task` 모델을 `response_model`로 쓰면
나중에 추가한 컬럼이 조용히 새어 나간다. 실제 SQLAlchemy 인스턴스로 실행한 결과다.

```text
>>> TaskOut.model_validate(task).model_dump(mode="json")   # Task(..., secret_field="LEAK")
{"id": "ec4a4b00-...", "title": "t", "status": "done", "created_at": "2026-08-23T17:26:30.587457Z"}
"LEAK" in output: False
```

`mode="json"`이 `StrEnum`을 `'done'` 문자열로, `datetime`을 ISO-8601로 바꾼다. 기본
`model_dump()`는 `<TaskStatus.DONE: 'done'>` 열거 객체를 그대로 준다 — 로그에 찍을 때와
와이어로 내보낼 때가 다르다는 뜻이다. FastAPI는 `response_model=TaskOut`이면 `mode="json"`
경로를 스스로 탄다.

```python
# app/http/routers.py (발췌)
@router.get("/{task_id}", response_model=TaskOut)
async def read_task(...) -> Task: ...
```

## 8. 환경 스키마 (`app/settings.py`) — 부팅 시점에 실패한다

**환경을 읽는 파일은 이 하나뿐이다.** 다른 파일이 직접 읽으면 타입도 검증도 부팅 시점
실패도 전부 우회된다.

<!-- file: app/settings.py -->
```python
# app/settings.py
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="forbid"
    )

    DATABASE_URL: str
    LOG_LEVEL: str = "INFO"
    ENV: str = "dev"


# ✅ 모듈 최상위 — 검증 실패가 곧 부팅 실패다.
# pyright는 DATABASE_URL을 안 넘겼다고 본다(값이 환경에서 온다는 것을 모른다). 이 한 줄만 억제한다
settings = Settings()  # pyright: ignore[reportCallIssue]
```

억제가 필요한 이유가 이 파일의 성격 그 자체다 — **필수 필드를 인자가 아니라 환경에서
채운다.** 억제는 그 한 줄에만 건다. 파일 단위로 끄면 진짜 타입 오류까지 함께 사라진다.

`DATABASE_URL` 없이 이 모듈을 import하면 **import 자체가 터진다.** 실행 출력:

```text
RESULT: raised pydantic_core._pydantic_core.ValidationError
errors(): [{"type":"missing","loc":["DATABASE_URL"],"msg":"Field required","input":{}}]
traceback 마지막 프레임: ('settings_mod.py', 11, '<module>')
```

트레이스백이 `<module>` 프레임을 가리킨다 — 요청 처리 중이 아니라 프로세스가 뜨는 도중이다.
`settings = Settings()`를 함수 안으로 옮기면 이 보호가 사라지고, 첫 요청이 올 때까지
**절반만 살아 있는 서버**가 헬스체크에 200을 준다.

`extra="forbid"`가 어디에 걸리는지는 직관과 다르다. 실행으로 확인한 두 경우:

| 미지 키가 있는 곳 | 결과 |
| --- | --- |
| 프로세스 환경변수 (`UNRELATED_KEY=x`) | **통과한다.** 환경변수 전체를 스키마로 보지 않는다 |
| `.env` 파일 안 (`UNRELATED_KEY=x`) | **422 상당의 `ValidationError`**, `loc=['unrelated_key']` |

`loc`이 소문자다 — pydantic-settings가 키를 정규화하기 때문이다(같은 이유로 소문자
`database_url` 환경변수도 `DATABASE_URL` 필드를 채운다). **`.env`에는 이 스키마가 아는 키만
둔다.** 배포에 `.env`가 없으면 이 검사는 아예 돌지 않고 누락(`missing`) 검사만 남는다.

## 오용 목록 ① — Pydantic v1 → v2 관용구 대조표

| 구 습관 (v1) | 현재 형태 (v2) |
| --- | --- |
| `class Config: orm_mode = True` | `model_config = ConfigDict(from_attributes=True)` |
| `class Config: extra = "forbid"` | `model_config = ConfigDict(extra="forbid")` |
| `.dict()` · `.json()` | `.model_dump()` · `.model_dump_json()` |
| `.dict(exclude_unset=True)` | `.model_dump(exclude_unset=True)` |
| `.parse_obj(x)` · `.from_orm(x)` | `.model_validate(x)` |
| `@validator("f")` | `@field_validator("f")` + `@classmethod` |
| `@root_validator` | `@model_validator(mode="before" \| "after")` |
| `__fields_set__` | `model_fields_set` |
| `Field(..., min_items=1)` | `Field(min_length=1)` (시퀀스에도 `min_length`) |
| `BaseSettings`가 `pydantic`에 있다 | 별도 패키지 `pydantic-settings`의 `BaseSettings` <!-- verified: pydantic 2.13.4에서 pydantic.BaseSettings는 존재하지 않고, pydantic-settings 2.15.0에서 import했다 --> |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `model_dump()` vs `model_dump(exclude_unset=True)` | 전체 교체(`PUT`)는 앞, 부분 수정(`PATCH`)은 **반드시** 뒤 |
| `exclude_unset` vs `exclude_none` | 앞은 "안 보낸 것"을 뺀다. 뒤는 명시적 `null`까지 삼켜 **거절해야 할 입력을 조용히 무시한다** |
| `model_dump()` vs `model_dump(mode="json")` | 내부 전달·로그는 앞, 와이어로 나가는 값은 뒤(`StrEnum`·`UUID`·`datetime`이 달라진다) |
| `TaskQuery = Depends()` vs `Annotated[TaskQuery, Query()]` | **이 팩은 항상 뒤다.** `Depends()`에서는 `extra="forbid"`가 무효라 미지 쿼리 파라미터가 조용히 통과한다 |
| `field_validator` vs `model_validator(mode="after")` | 필드에 `loc`을 붙여야 하면 앞, 필드 간 관계(빈 패치 등)는 뒤(`loc`이 `()`다) |
| `DATABASE_URL: str` vs `PostgresDsn` | `PostgresDsn`은 스킴을 검사하지만 `str`이 아닌 URL 객체라 엔진에 넘길 때 `str()`이 필요하다. 이 팩은 `str`을 쓴다 <!-- verified: TypeAdapter(PostgresDsn)로 postgresql+asyncpg 통과·mysql 거절을 실행 확인 --> |
| `TaskStatus`를 스키마·모델에 따로 정의 | 한 곳(`app/schemas/task.py`)에 두고 모델이 import한다 |
| `Field(min_length=1)` vs `str \| None` 기본값 | 길이 제약은 값이 있을 때만 걸린다. 생략 자체를 막으려면 필수 필드로 둔다 |

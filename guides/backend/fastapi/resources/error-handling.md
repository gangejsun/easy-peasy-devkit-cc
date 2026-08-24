<!-- epcc-pack: backend/fastapi v3.14.0 -->
# 에러 처리 — 예외 하나가 응답 하나가 되는 길을 단일화한다

이 파일이 소유하는 것은 **두 모듈**이다 — `app/db/errors.py`(SQLSTATE 판별)와
`app/http/errors.py`(상태 매핑 `ERROR_STATUS` · 정규화 `to_app_error` · 필드 오류
`field_errors`). **응답 봉투의 모양과 `AppError` 자체는 소유하지 않는다** — 와이어 계약의
함수라서 이음매가 `app/errors.py`와 `app/http/handlers.py`에 둔다. 무엇을 던질지는 각
계층이 정한다(`data-access.md` · `input-validation.md`).

## 1. 결정 트리 — 어디서 잡고 어디서 던지는가

| 계층 | 던지는 것 | 잡는가 |
| --- | --- | --- |
| `app/db/tasks.py` (리포지토리) | `AppError` · 드라이버 예외를 **그대로** | 아니다 |
| `app/services/tasks.py` (도메인) | `AppError` | 도메인 규칙으로 바꿀 때만 |
| `app/http/routers.py` (라우터) | 던지지 않는다 | 아니다 |
| `install_error_handlers` (이음매) | — | **여기서만 잡는다** |

**`try/except`를 라우터에 쓰지 않는다.** 잡는 자리가 늘어나면 같은 실패가 요청 경로마다
다른 상태 코드로 나가고, 그 차이는 테스트가 아니라 사용자가 발견한다. 예외 핸들러가
`to_app_error`로 한 번 접고 `ERROR_STATUS`로 한 번 매핑하는 것이 전부다.

리포지토리가 `HTTPException`을 던지면 그 계층은 이미 무너진 것이다 — 그 함수는 HTTP를
세워야만 테스트할 수 있게 된다.

## 2. 세 모듈로 가른다 — 배치가 곧 계층 규율이다

에러 심볼을 한 파일에 몰면 `app/db/tasks.py`가 `AppError` 하나 때문에 `fastapi`를 **전이로**
끌어온다. `app/http/errors.py`가 `RequestValidationError` 때문에 `fastapi`를 import하기
때문이다. 그래서 셋으로 가른다.

| 파일 | 담는 것 | import해도 되는 것 |
| --- | --- | --- |
| `app/errors.py` | `AppError` (**이음매 소유**) | 표준 라이브러리뿐 |
| `app/db/errors.py` | SQLSTATE 판별 두 개 | 드라이버 지식만 — HTTP를 모른다 |
| `app/http/errors.py` | `ERROR_STATUS` · `to_app_error` · `field_errors` | `fastapi` · `pydantic` |

검사식은 grep이 아니라 **실제 import**다. 전이 의존은 문자열로 보이지 않는다.

```text
>>> python -c "import app.db.tasks, sys; assert 'fastapi' not in sys.modules"
(출력 없음 — 통과)
>>> 양성 대조군: AppError와 판별 함수를 app/http/errors.py 한 파일로 되돌린 뒤 같은 명령
AssertionError          # sys.modules에 fastapi·starlette·pydantic이 적재된다
```

대조군이 있어야 이 검사가 위반을 **볼 수 있는 상태였다는 것**이 증명된다. 대조군 없이 얻은
"fastapi가 없다"는 「없다」가 아니라 「측정하지 못했다」다.

<!-- file: app/db/errors.py -->
```python
# app/db/errors.py
from __future__ import annotations

UNIQUE_VIOLATION = "23505"
FOREIGN_KEY_VIOLATION = "23503"


def _sqlstate(exc: BaseException) -> str | None:
    """SQLAlchemy 래퍼 → 어댑터 예외 → 원본 드라이버 예외 순으로 SQLSTATE를 찾는다."""
    orig = getattr(exc, "orig", None)
    for current in (exc, orig, getattr(orig, "__cause__", None)):
        if current is None:
            continue
        code = getattr(current, "sqlstate", None) or getattr(current, "pgcode", None)
        if code:
            return str(code)
    return None


def is_unique_violation(exc: BaseException) -> bool:
    return _sqlstate(exc) == UNIQUE_VIOLATION


def is_foreign_key_violation(exc: BaseException) -> bool:
    return _sqlstate(exc) == FOREIGN_KEY_VIOLATION
```

이 파일은 `sqlalchemy`도 `asyncpg`도 import하지 않는다 — `getattr`로만 훑기 때문이다.
리포지토리가 부담 없이 부를 수 있는 이유이자, 드라이버를 바꿔도 이 파일이 안 깨지는 이유다.

<!-- file: app/http/errors.py -->
```python
# app/http/errors.py
from __future__ import annotations

from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError

from app.db.errors import is_foreign_key_violation, is_unique_violation
from app.errors import AppError  # 이음매가 소유한다

# 도메인 코드 → HTTP 상태. **유일한 매핑표**다
ERROR_STATUS: dict[str, int] = {
    "VALIDATION_FAILED": 422,
    "UNAUTHENTICATED": 401,
    "FORBIDDEN": 403,
    "NOT_FOUND": 404,
    "CONFLICT": 409,
    "INTERNAL": 500,
}


def field_errors(exc: ValidationError | RequestValidationError) -> dict[str, list[str]]:
    """loc을 점으로 이어 키로 쓴다. 배열 인덱스를 지우지 않는다."""
    result: dict[str, list[str]] = {}
    for err in exc.errors():
        loc = err.get("loc") or ()
        key = ".".join(str(part) for part in loc) or "__root__"
        result.setdefault(key, []).append(str(err.get("msg", "")))
    return result


def to_app_error(exc: BaseException) -> AppError:
    """예외 핸들러가 반드시 먼저 부른다. 모르는 것은 전부 INTERNAL로 접는다."""
    if isinstance(exc, AppError):
        return exc
    if isinstance(exc, (ValidationError, RequestValidationError)):
        return AppError("VALIDATION_FAILED", "요청을 검증하지 못했다", field_errors(exc))
    if is_unique_violation(exc):
        return AppError("CONFLICT", "이미 같은 작업이 있다")
    if is_foreign_key_violation(exc):
        return AppError("VALIDATION_FAILED", "참조하는 대상이 없다")
    return AppError("INTERNAL", "요청을 처리하지 못했다")
```

`http/` → `db/`는 정상 방향이다. 반대 방향의 import는 없다.

`ERROR_STATUS`를 조회할 때는 반드시 기본값을 둔다 — `ERROR_STATUS.get(err.code, 500)`.
코드표에 없는 코드가 `KeyError`를 내면 **에러 핸들러 안에서 에러가 나서** 500조차 못 만든다.

## 3. `to_app_error` — 모르는 것을 접는 것이 보안 조치다

드라이버 예외의 문자열에는 접속 정보·테이블명·제약 이름·실행된 SQL이 들어 있다. SQLAlchemy가
만든 `IntegrityError`를 `str()`로 찍으면 이렇게 생겼다(실행 출력, 값은 잘랐다).

```text
(sqlalchemy.dialects.postgresql.asyncpg.IntegrityError) <class 'asyncpg.exceptions.UniqueViolationError'>: <드라이버 메시지>
[SQL: INSERT INTO tasks ...]
```

이것을 응답 본문에 실으면 스키마가 통째로 새어 나간다. `to_app_error`의 마지막 줄
`return AppError("INTERNAL", ...)`가 **원본 메시지를 버리는 것**이 요점이다. 원본은 로그로
보낸다 — `logger.exception(...)`은 핸들러 안에서 부르고, 응답에는 상관관계 ID만 싣는다.

```python
# tests/test_errors.py (발췌)
def test_to_app_error_keeps_known_and_folds_unknown() -> None:
    known = AppError("NOT_FOUND", "작업을 찾을 수 없다")
    assert to_app_error(known) is known              # ✅ 아는 것은 그대로 통과한다
    folded = to_app_error(RuntimeError("host=db user=admin password=s3cr3t"))
    assert folded.code == "INTERNAL"                 # ✅ 모르는 것은 접힌다
    assert "s3cr3t" not in folded.message            # ✅ 원문이 새지 않는다
```

세 단언이 같은 함수 안에 있다. 마지막 줄만 걸면 `to_app_error`가 무엇을 반환하든 초록이고,
첫 줄만 걸면 접기가 아예 없어도 초록이다.

## 4. SQLSTATE 판별 — `exc.orig`는 asyncpg 예외가 아니다

`postgresql+asyncpg`에서 예외는 **세 겹**이다. SQLAlchemy 2.0.52 dialect 소스
(`dialects/postgresql/asyncpg.py:781-797`)가 asyncpg 예외를 자기 DBAPI 예외로 번역하면서
`sqlstate`·`pgcode`를 채우고 `raise translated_error from error`로 원본을 `__cause__`에
남긴다. 층마다 갖는 속성이 다르다.

| 층 | 클래스 | `sqlstate` | `pgcode` |
| --- | --- | --- | --- |
| `exc` | `sqlalchemy.exc.IntegrityError` | 없다 | 없다 |
| `exc.orig` | `sqlalchemy.dialects.postgresql.asyncpg.IntegrityError` | `"23505"` | `"23505"` |
| `exc.orig.__cause__` | `asyncpg.exceptions.UniqueViolationError` | `"23505"` | **없다** |

**`pgcode`가 채워지는 것은 `exc.orig` 층뿐이다** <!-- verified: 감사 B1이 실 PostgreSQL 16.2에서 확인. 저작 측은 asyncpg 0.31이 만든 예외 객체에 그 속성이 없음을 확인했다 -->. `_sqlstate`가
층마다 `sqlstate` → `pgcode` 순으로 보고 `getattr` 기본값을 쓰는 이유다 — 없는 속성을
직접 읽으면 판별 함수가 `AttributeError`로 죽는다.

**`isinstance(exc.orig, asyncpg.exceptions.UniqueViolationError)`는 `False`다**(실행 확인).
드라이버 클래스로 판정하려 들면 조용히 아무것도 안 잡혀 모든 중복 저장이 500이 된다.
메시지 문자열 판정도 안 된다 — 아래는 로케일·드라이버·PostgreSQL 버전이 바뀌면 죽는다.

```python
# ❌ 드라이버 메시지는 계약이 아니다 — 문구가 바뀌면 조용히 500이 된다
if "unique constraint" in str(exc):
    raise AppError("CONFLICT", "이미 있다")
```

```python
# ✅ SQLSTATE는 PostgreSQL이 정의한 다섯 글자 코드다
if is_unique_violation(exc):
    raise AppError("CONFLICT", "이미 같은 작업이 있다")
```

`23505`·`23503`은 asyncpg의 클래스 속성과 일치한다 —
`UniqueViolationError.sqlstate == "23505"`, `ForeignKeyViolationError.sqlstate == "23503"`.
드라이버가 SQLSTATE를 안 주면(다른 DB, 커넥션 단계 오류) `_sqlstate`가 `None`을 주고 두
판별 함수가 `False`가 된다 — **예외를 내지 않는다.** 판별 함수가 터지면 핸들러가 함께 터진다.

## 5. `field_errors` — `loc`을 그대로 키로 쓴다

FastAPI의 `RequestValidationError.errors()`는 `loc`을 **튜플**로 준다. 첫 원소가 입력의
출처(`"body"` · `"query"` · `"path"`)이고, 배열 본문이면 **정수 인덱스**가 뒤따른다.
실제 요청으로 계측한 형태다.

| 요청 | `loc` | `type` |
| --- | --- | --- |
| `POST` 본문에 `title` 누락 | `('body', 'title')` | `missing` |
| 본문이 `null`이거나 아예 없음 | `('body',)` | `missing` |
| 배열 본문 2번째 항목의 `title`이 빈 문자열 | `('body', 1, 'title')` | `string_too_short` |
| 깨진 JSON | `('body', 1)` — **1은 필드가 아니라 문자 위치다** | `json_invalid` |
| `?limit=999` | `('query', 'limit')` | `less_than_equal` |
| 경로의 UUID가 깨짐 | `('path', 'task_id')` | `uuid_parsing` |

`('body', 1, 'title')` → `"body.1.title"`. **인덱스를 지우지 않는다.** 지우면 배열의 몇 번째
항목이 틀렸는지가 사라져 폼이 오류를 어디에도 붙이지 못한다. 첫 원소도 남긴다 — 지우면
같은 이름의 쿼리 파라미터와 본문 필드가 한 키로 뭉치고, 깨진 JSON의 `('body', 1)`이
`"1"`이라는 뜻 없는 키가 된다.

`loc`이 빈 튜플인 경우가 있다 — `model_validator(mode="after")`가 던진 오류다. 그때만
`"__root__"`로 접는다. **같은 오류라도 경로에 따라 키가 다르다**(둘 다 실행 확인):

| 부른 곳 | `loc` | `field_errors` 키 |
| --- | --- | --- |
| `TaskUpdate.model_validate({})` 직접 | `()` | `__root__` |
| `PATCH` 요청으로 같은 본문 | `('body',)` | `body` |

FastAPI가 본문 위치를 앞에 붙이기 때문이다. 클라이언트는 두 키를 모두 "필드가 아닌
본문 전체의 오류"로 다뤄야 한다.

`errors()`의 각 항목은 `type`·`loc`·`msg`·`input`(+ 때때로 `ctx`) 키를 갖는다.
**`input`을 응답에 그대로 싣지 않는다** — 사용자가 보낸 원문이고, 인증 헤더나 비밀번호가
들어 있던 요청이면 그대로 되돌아 나간다.

## 6. 존재 누설 금지 — 404와 403은 다른 질문에 답한다

이 축에는 행 수준 정책 엔진이 없다. 소유권은 `WHERE owner_id = :owner_id`에만 있고,
그래서 `get_task`는 **"없다"와 "남의 것이다"를 구분하지 못한다.** 그 구분 불가가 기능이다.

| 상황 | 상태 | 이유 |
| --- | --- | --- |
| 내 것이 아니거나 없는 `task_id` | **404** | 둘을 가르면 ID 대입만으로 남의 자원 존재를 알아낸다 |
| 토큰이 없거나 만료 | 401 | 자원과 무관하다 |
| 토큰은 유효하나 역할·스코프가 부족 | 403 | **자원 식별자가 비밀이 아닐 때만** 쓴다 |
| 같은 제목이 이미 있다 | 409 | `is_unique_violation`이 판정한다 |

403을 "남의 자원"에 쓰면 그 응답 자체가 "그 자원은 존재한다"는 답이 된다. 역할 부족에만
403을 쓰고, 소유권 불일치는 404로 접는다. 오류 메시지도 마찬가지다 — `"작업 42는 사용자
7의 것이다"` 같은 문구는 상태 코드를 404로 두고도 같은 정보를 준다.

## 7. 핸들러 배선 — 이음매가 하고, 팩은 형태만 고정한다

`install_error_handlers(app)`는 이음매(`app/http/handlers.py`)의 것이다. 봉투 모양은 조합이
정하지만 **순서는 팩이 고정한다** — 접고, 매핑하고, `details`에 `field_errors`를 싣는다.

```python
# app/http/handlers.py (발췌 — 이음매가 소유한다)
err = to_app_error(exc)
status = ERROR_STATUS.get(err.code, 500)
```

핸들러는 **셋 다** 등록한다: `AppError` · `RequestValidationError` · `Exception`.
`Exception`이 빠지면 예상 못 한 예외가 FastAPI 기본 경로로 빠져 스택 트레이스가 나가고,
`RequestValidationError`가 빠지면 422 봉투만 모양이 달라져 클라이언트가 파서를 두 벌 갖는다.

## 오용 목록 ① — `HTTPException` 관용구 → `AppError` 관용구 대조표

| 구 습관 (`HTTPException` 직접 사용) | 현재 형태 |
| --- | --- |
| 라우터에서 `raise HTTPException(404, "없음")` | 리포지토리·서비스가 `AppError("NOT_FOUND", ...)` |
| 계층마다 `try/except`로 상태 코드 결정 | `to_app_error` 한 곳 + `ERROR_STATUS` 한 곳 |
| `HTTPException(400)`으로 검증 실패 | `RequestValidationError`를 핸들러가 422로 |
| `detail=str(exc)`로 원인 전달 | `AppError("INTERNAL", 고정 문구)` + 원인은 로그로 |
| `except IntegrityError: raise HTTPException(409)` | `is_unique_violation(exc)`로 SQLSTATE 판정 |
| `exc.errors()`를 그대로 `detail`에 | `field_errors(exc)`로 `{키: [문구]}` 정규화 |
| `@app.exception_handler`를 모듈마다 선언 | `install_error_handlers(app)` 한 번 (`create_app`이 부른다) |
| `RequestValidationError.errors()`에 `url` 키가 있다고 가정 | FastAPI 쪽에는 없다. pydantic `ValidationError.errors()`에만 있고 `include_url=False`로 끈다 <!-- verified: fastapi 0.141.1 실제 요청에서 키가 input/loc/msg/type뿐, pydantic 2.13.4는 url 포함 --> |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `exc.orig` vs `exc.orig.__cause__` | SQLSTATE는 둘 다 갖지만, **드라이버 클래스는 `__cause__`에만** 있다 |
| `isinstance(orig, UniqueViolationError)` vs `sqlstate == "23505"` | 앞은 asyncpg dialect에서 항상 `False`다. 뒤만 쓴다 |
| `sqlstate` vs `pgcode` | **`exc.orig` 층에서만** 둘 다 같은 값이다. 원본 asyncpg 예외에는 `pgcode`가 없어 `sqlstate`를 먼저 본다 |
| `23505` vs `23503` | 중복 저장은 앞(409). 없는 대상 참조는 뒤(422 — 클라이언트가 잘못된 ID를 보냈다) |
| 403 vs 404 | 역할 부족은 403, **소유권 불일치는 404**. 뒤를 403으로 하면 존재가 새어 나간다 |
| 409 vs 422 | 스키마는 맞는데 상태가 충돌하면 409, 스키마가 틀리면 422 |
| `pydantic.ValidationError` vs `RequestValidationError` | 앞은 직접 `model_validate` 호출 시, 뒤는 FastAPI가 요청을 파싱할 때. `field_errors`는 둘 다 받는다 |
| `ERROR_STATUS[code]` vs `.get(code, 500)` | 핸들러 안에서는 반드시 뒤. `KeyError`가 나면 500 응답조차 못 만든다 |
| `logger.error(str(exc))` vs `logger.exception(...)` | 스택이 필요하면 뒤. 앞은 원인 위치를 지워 버린다 |

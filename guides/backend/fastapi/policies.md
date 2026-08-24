<!-- epcc-pack-policies: backend/fastapi v3.14.0 -->

# fastapi 팩 — 파일 간 불변식 (L0 초안)

이 팩이 **선언한 정책을 팩 자신과 이음매가 지키는지** 게이트가 대조한다. 정책을 선언한 곳과
강제하는 곳이 다르고 둘을 맞춰볼 의무가 없으면 정책은 문서로만 남는다 — 이 파일이 그 의무다.

## 기계 검사 (게이트 `check_policies` · `check_pack_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간 아님.
산문과 안티패턴 예시를 세면 전부 위양성이 된다.

**`증명 예` 열은 의무다** (없으면 게이트 FAIL). 게이트가 ① 예가 자기 정규식에 매치되는가
② `forbid`면 그 예가 대상 파일에 실재하지 않는가를 단언한다.

**`대상` 값에 마크다운 강조를 쓰지 않는다.** `**seam**`은 scope로 인식되지 않아 정책이
조용히 전 파일을 겨눈다 — vue 팩에서 실제로 그랬다.

**정규식에 선택 그룹을 쓰지 않는다.** `respond(\.fail)?\(` 부류는 성공 경로만으로 충족돼
정작 검증하려던 실패 경로를 전혀 측정하지 못한다(감사 A 실측). 정규식이 **통과시키면 안 되는
문자열**로도 확인한다 — 그것이 통과하면 그 정책은 죽은 것이다.

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `env-single-entry` | forbid | guide | `os\.environ` | `testing.md` | `url = os.environ["DATABASE_URL"]` | 환경 값은 `settings` 한 곳에서만 읽는다. 다른 파일이 직접 읽으면 타입도 검증도 부팅 시점 실패도 우회된다. 예외는 **하나뿐**이다: 테스트가 격리 DB를 주입하는 자리. 스키마를 적용하는 자리는 pydantic-settings가 읽으므로 `os.environ`이 필요 없다 |
| `no-sync-session` | forbid | guide | `\bsessionmaker\(` | — | `SessionLocal = sessionmaker(engine)` | 동기 `sessionmaker`는 async 라우터 안에서 이벤트 루프를 막는다. 이 축은 `async_sessionmaker`만 쓴다 — 두 이름이 한 글자 차이라 복사하면 조용히 섞인다 |
| `no-orm-in-response` | forbid | guide | `response_model\s*=\s*Task\b` | — | `@router.get("/{id}", response_model=Task)` | ORM 모델을 응답 스키마로 쓰면 나중에 추가한 컬럼이 조용히 새어 나간다. `TaskOut`만 응답에 쓴다 |
| `ownership-in-where` | require | guide | `Task\.owner_id\s*==` | — | `select(Task).where(Task.owner_id == owner_id)` | 이 축에는 행 수준 정책 엔진이 없다. **소유권은 `WHERE`에 있어야 하고**, 파이썬에서 거르는 형태는 남의 행을 이미 읽은 뒤다 |
| `rowcount-checked` | require | guide | `\.rowcount\b` | — | `if result.rowcount == 0: raise AppError("NOT_FOUND", ...)` | `UPDATE`·`DELETE`는 0행을 변이해도 성공이다. 확인하지 않으면 남의 것을 지우라는 요청도 204가 된다 |
| `partial-update-exclude-unset` | require | guide | `exclude_unset\s*=\s*True` | — | `patch = body.model_dump(exclude_unset=True)` | 없으면 보내지 않은 필드가 기본값으로 저장을 덮어쓴다. **실측 최악의 결함이 이 부류였고 문법은 완벽했다** — `pack-smoke.sh`의 스키마 실행이 같은 부류를 FAIL로 막는다 |
| `no-string-sqlstate` | forbid | guide | `(duplicate key\|unique constraint\|violates)` | — | `if "unique constraint" in str(exc):` | 드라이버 메시지는 로케일·버전에 따라 바뀐다. SQLSTATE(`23505`)로 판정한다. **정규식을 `"duplicate key"` 하나로 두면 팩 자신이 ❌ 예로 시연한 `"unique constraint"`조차 못 잡는다**(감사 C 실측) |
| `seam-no-http-exception` | forbid | seam | `raise HTTPException\(` | — | `raise HTTPException(status_code=404)` | 이음매가 `HTTPException`을 직접 던지면 `ERROR_STATUS` 매핑표를 우회한다 — 코드표에 없는 상태가 새어 나오고 봉투가 두 형태가 된다. `AppError`를 던지고 `install_error_handlers`가 옮긴다 |
| `seam-status-lookup` | forbid | seam | `ERROR_STATUS\[` | — | `status = ERROR_STATUS[app.code]` | 첨자 접근은 코드표에 없는 코드에서 `KeyError`를 내고, 그 `KeyError`가 다시 500으로 접힌다 — 원인이 사라진다. `ERROR_STATUS.get(code, 500)`을 쓴다 |
| `seam-depends-current-user` | require | seam | `Depends\(current_user\)` | — | `user: AuthUser = Depends(current_user)` | 라우터가 토큰을 직접 파싱하면 경계가 둘이 되고, 그 둘은 반드시 갈라진다. 주체는 이 의존성 하나로만 얻는다 |
| `vocab-task` | forbid | guide | `\bnotes?\b\|노트` | — | `notes = []` | 어휘는 Task/작업 (L0 발행). 클러스터를 갈라 쓰면 어휘가 갈린다 — 실측에서 `task` 217회 ↔ `note` 166회로 벌어졌고 완전 예제가 서로 실행 불가였다 |

## 사람이 지킬 것 (기계가 판정할 수 없다)

- **`get_session`이 트랜잭션 경계다.** 리포지토리 함수마다 커밋하면 라우터 하나가 절반만
  반영된 상태를 남길 수 있다. 커밋은 요청 성공 시 한 번이다
- **`selectinload`를 쓸 자리와 쓰지 말 자리를 사람이 가른다.** 목록에서 관계를 안 쓰면
  붙이지 않는다 — 붙이면 쓰지도 않을 행을 매 페이지마다 더 읽는다
- **Alembic 자동생성본은 읽고 고친 뒤 커밋한다.** 인덱스 이름·타입 변경·데이터 이전을
  자동생성이 알아서 하지 못한다. 특히 `owner_id` 인덱스가 빠지면 목록이 전체 스캔이 된다
- **`current_user`를 우회하는 라우터를 만들지 않는다.** 하나라도 토큰을 직접 파싱하면
  경계가 둘이 되고, 그 둘은 반드시 갈라진다

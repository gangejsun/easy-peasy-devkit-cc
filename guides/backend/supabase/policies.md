<!-- epcc-pack-policies: backend/supabase v3.12.0 -->

# supabase 팩 — 파일 간 불변식

이 팩이 **선언한 정책을 이음매가 지키는지** 게이트가 대조한다. 실측에서 감사 지적의
최대 부류(57건 중 26건)가 "정책을 선언한 곳과 강제하는 곳이 다르고 둘을 맞춰볼 의무가
없다"였다 — 이 파일이 그 의무다.

> **이 축의 전제**: 데이터 계층에 행 수준 정책 엔진(RLS)이 **있다.** 아래 정책은 이중
> 방어의 한쪽을 지키는 것이다. 정책 엔진이 없는 축의 팩에 이 절을 복사하면 "데이터
> 계층이 백업해 준다"는 잘못된 안심을 심는다.

## 기계 검사 (게이트 `check_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간
아님. 아래는 전부 **추출 시점에 사전 제작 이음매로 시험해 위반 0을 확인**했다
(원시 grep으로는 위반처럼 보이는 8건이 전부 산문·주석이었다).

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 반례 | 설명 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `getUser-not-getSession` | forbid | guide | `getSession\(` | — | `const { data } = await supabase.auth.getSession()` | `const s = await client.auth.getSession()` | 서버에서 사용자 확인은 항상 `getUser()`. `getSession()`은 쿠키를 그대로 신뢰하므로 인증 경계로 쓸 수 없다 |
| `no-select-star` | forbid | guide | `select\('\*'\)` | — | `await supabase.from('tasks').select('*')` | `.select('*')` | 핸들러에서 컬럼을 명시한다. `select('*')`는 스키마 변경 시 조용히 payload가 커지고 비밀 컬럼을 끌고 온다 |
| `no-module-singleton-client` | forbid | guide | `^(const\|let\|var) [A-Za-z_$][A-Za-z0-9_$]* = createClient\(` | — | `const supabase = createClient(url, anonKey)` | `const db = createClient(url, anonKey)` | 클라이언트는 요청 단위로 만든다. 모듈 수준 싱글턴은 요청 간에 인증 컨텍스트를 섞는다 |
| `error-is-checked` | require | guide | `if \(error\)` | — | `if (error) throw toAppError(error)` | `if (error !== null)` | Supabase 쿼리는 throw하지 않고 `error`를 반환한다. 확인하지 않으면 실패가 빈 결과로 둔갑한다 |

`대상`: `guide`=조립된 가이드 전체 · `seam`=이음매만 · `pack`=이 팩만 · `file:<이름>`.

**`증명 예` 열은 의무다** (없으면 게이트 FAIL). 그 정규식이 실제로 잡는 문자열 하나를
적는다. 게이트가 두 가지를 단언한다: ① 예가 자기 정규식에 매치되는가 — 매치되지 않으면
아무것도 못 잡는 죽은 정규식이다 ② `forbid`면 그 예가 대상 파일에 실재하지 않는가 —
실재하면 팩이 자기 정책을 어긴 것이다. 실측(2026-08-23) vue 팩 저작에서 정책마다 결함
픽스처를 만들어 돌리는 일이 벽시계를 지배했고, 이 열이 그 왕복을 밀리초로 대체한다.

**`대상` 값에 마크다운 강조를 쓰지 않는다.** `**seam**`은 게이트가 scope로 인식하지
못해 정책이 조용히 전 파일을 겨눈다 — vue 팩에서 실제로 그랬고, "이음매를 겨눈다"는
감사 수리가 무효인 채로 출하됐다. 게이트가 이제 강조를 벗기지만 표에는 맨 값을 쓴다.

## 사람이 지킬 것 (기계로 판정 불가)

- **모든 테이블에 RLS를 켠다.** 애플리케이션 검사는 UX이고 강제는 정책이다. 테이블을
  추가하고 정책을 빠뜨리면 anon 키로 전량이 열린다
- **service role 키는 서버의 격리된 경로에서만 쓴다** (웹훅·크론·관리 작업). 이 키는
  RLS를 우회하므로 일반 요청 경로에 들어오면 정책 엔진이 사실상 꺼진다
- **부재와 미인가를 같은 응답으로 낸다.** RLS가 가린 행은 `PGRST116`으로 오는데, 이를
  403으로 구분해 응답하면 존재가 누설된다

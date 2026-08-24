<!-- epcc-pack: backend/supabase v3.12.0 verified 2026-08-21 @supabase/ssr@0.12 @supabase/supabase-js@2 zod@4 vitest@4 -->

# supabase 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 **그대로 삽입할 축-지역 조각**이다. 사전 제작 이음매가
있는 조합은 이 파일을 쓰지 않는다 — 그 경우 이음매의 `HUB.md`가 허브 전문을 갖는다.

> **이 축의 전제**: 데이터 계층에 **행 수준 정책 엔진(RLS)이 있다.** 애플리케이션 층
> 검사는 UX이고 강제는 RLS다 — 이중 방어를 전제로 쓴다. 정책 엔진이 **없는** 축
> (`aws-container`·`aws-serverless` 등)에 이 서술을 옮기면 정확히 반대 지침이 된다.
> 그 축에서는 애플리케이션 층 소유권 검사 누락이 곧 데이터 유출이다.

> **이 팩은 얇다 — 그리고 그것이 정상이다.** BaaS 축의 "백엔드 가이드"는 대부분 호스트
> 런타임(핸들러·미들웨어·에러 봉투·검증 배선)에 관한 것이고, 그것은 프론트엔드 축이
> 정한다. 이 축이 실제로 소유하는 것은 클라이언트 사용 규율·쿼리 패턴·RLS·스토리지·
> 리얼타임·생성 타입뿐이다. 자체 서버 축(`aws-container`·`fastapi`)의 팩이 두꺼운 것과
> 대비된다.

<!-- pack-slot: core-principles-axis -->
### 2. Authorize with getUser(), never getSession(), on the server

`getSession()` reads the cookie without verifying it — it can be spoofed.
`getUser()` revalidates the JWT against Supabase Auth on every call.

```ts
// Bad — trusts an unverified cookie
const { data: { session } } = await supabase.auth.getSession()
if (!session) return fail(401, 'unauthenticated', 'Sign in required')
```

```ts
// Good — verified identity
const { data: { user } } = await supabase.auth.getUser()
if (!user) return fail(401, 'unauthenticated', 'Sign in required')
```

### 3. Create the Supabase client per request — never a module-level singleton

```ts
// Bad — one client at import time; cookies from one request leak into another
export const supabase = createServerClient(url, key, { cookies: staticCookies })
```

```ts
// Good — a fresh cookie-bound client inside every handler/action
export async function POST(request: NextRequest) {
  const supabase = await createClient()
  // ...
}
```

### 4. Enable RLS on every table — app checks are UX, RLS is enforcement

```sql
-- Bad: no RLS — anyone holding the anon key can read/write every row
create table tasks ( ... );
```

```sql
-- Good: RLS on + owner policy; handlers still filter, Postgres enforces
alter table tasks enable row level security;
create policy "tasks_owner_all" on tasks for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
```

### 5. Never ignore the error returned by a Supabase query

supabase-js does not throw — every call returns `{ data, error }` and `data` may be `null`.

```ts
// Bad — error silently discarded; returns null data as success
const { data } = await supabase.from('tasks').select('id, title')
return ok(data)
```

```ts
// Good — every query checks error and maps it to a status
const { data, error } = await supabase.from('tasks').select('id, title')
if (error) return fromSupabaseError(error)
return ok(data)
```

<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
```ts
// 데이터 액세스 · 인증 (클라이언트를 **어떻게** 만드는지는 이음매가 정한다)
import { createServerClient, createBrowserClient } from '@supabase/ssr'
import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/types/database'
```
<!-- /pack-slot -->

## 이음매가 채울 것 — 이 팩에 없는 것

| 허브 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| Quick Start 전체 | 엔드포인트를 만드는 절차가 핸들러 형태(= 프론트엔드 축)에 달렸다 |
| Architecture Overview | 서버 코드가 어디 사는지가 프론트엔드 축에 달렸다 |
| Directory Structure | 호스트 프레임워크의 배치 규약이다 |
| Core Principle "입력을 검증한다" | 원칙은 보편이나 **파싱 헬퍼의 형태**(요청 객체 타입)가 호스트 런타임에 달렸다. 이 규칙은 반드시 넣는다 |
| HTTP Status Codes 표 · 에러 봉투 | 곧 와이어 계약이다 |
| Server Action / 액션 경계 계약 | 프론트엔드 축이 그런 경계를 제공할 때만 존재한다 |
| Navigation Guide | 팩 리소스 행은 `pack.json`이 제공한다 |

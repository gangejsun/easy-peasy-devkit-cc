# Architecture Overview

## Next.js App Router Backend Architecture

Next.js App Router는 파일 시스템 기반 라우팅과 React Server Components를 결합한 풀스택 프레임워크.
백엔드 로직은 크게 세 가지 방식으로 구현한다.

### 세 가지 서버 사이드 패턴

| 패턴 | 위치 | 용도 | 예시 |
|------|------|------|------|
| **Server Component** | `app/**/page.tsx` | 데이터 읽기 (READ) | 목록 페이지, 상세 페이지 |
| **Route Handler** | `app/api/**/route.ts` | REST API, 외부 연동 | 웹훅, 3rd party API, 모바일 API |
| **Server Action** | `"use server"` 함수 | 데이터 변경 (CUD) | 폼 제출, 상태 변경, 삭제 |

### Request Lifecycle

```
Client Request
    |
    v
next.config.ts (headers, redirects, rewrites)
    |
    v
middleware.ts (auth check, locale, redirect)
    |
    v
    +-- Page Request --> Layout --> Page (Server Component)
    |                                  |
    |                              async data fetch (Supabase)
    |
    +-- API Request --> Route Handler (app/api/)
    |                       |
    |                   Service Logic --> Supabase
    |
    +-- Server Action --> "use server" function
                              |
                          Service Logic --> Supabase
                              |
                          revalidatePath/revalidateTag
```

### Server/Client Boundary

```
Server (Node.js runtime)
├── Server Components (default) -- async 가능, DB 접근 가능
├── Route Handlers              -- NextRequest/NextResponse
├── Server Actions              -- "use server"
├── Middleware                  -- Edge runtime
└── lib/ 서비스 로직            -- 순수 함수

Client (Browser)
├── Client Components           -- "use client", 상태, 이벤트
├── Zustand stores              -- 클라이언트 상태
└── Browser APIs                -- localStorage, etc.
```

**핵심 원칙**: 서버에서 할 수 있는 것은 서버에서 한다. 클라이언트는 인터랙션이 필요한 경우에만 사용.

---

## Module Organization

### 서비스 로직 분리 패턴

Route Handler나 Server Action에 비즈니스 로직을 직접 넣지 않는다. `lib/` 디렉토리에 서비스 함수로 분리.

```typescript
// bad: Route Handler에 로직 직접 작성
export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const body = await request.json();
  // 50줄의 비즈니스 로직...
  const { data } = await supabase.from("users").insert(body);
  return NextResponse.json(data);
}

// good: 서비스 함수 분리
// lib/services/user.ts
export async function createUser(input: CreateUserInput) {
  const supabase = await createClient();
  const validated = createUserSchema.parse(input);
  const { data, error } = await supabase
    .from("users")
    .insert(validated)
    .select()
    .single();

  if (error) throw new AppError("USER_CREATE_FAILED", error.message);
  return data;
}

// app/api/users/route.ts
export async function POST(request: NextRequest) {
  const body = await request.json();
  const user = await createUser(body);
  return NextResponse.json(user, { status: 201 });
}
```

### 디렉토리 별 책임

| 디렉토리 | 책임 | 포함하는 것 |
|----------|------|-----------|
| `app/api/` | HTTP 인터페이스 | 요청 파싱, 응답 포맷팅, 상태 코드 |
| `lib/actions/` | Server Actions | `"use server"`, 폼 처리, revalidation |
| `lib/supabase/` | DB 클라이언트 | 클라이언트 생성, 연결 관리 |
| `lib/services/` | 비즈니스 로직 | 검증, 변환, 비즈니스 규칙 (선택) |
| `types/` | 타입 정의 | 요청/응답 타입, DB 타입 |
| `constants/` | 상수 | 설정값, 열거형 |

---

## When to Use What

| 상황 | 패턴 | 이유 |
|------|------|------|
| 페이지에서 데이터 표시 | Server Component | 서버에서 직접 fetch, 번들 크기 0 |
| 폼 제출 | Server Action | Progressive enhancement, 자동 revalidation |
| 외부 API/웹훅 | Route Handler | REST 엔드포인트 필요 |
| 모바일 앱 API | Route Handler | JSON API 제공 |
| 인증 체크/리다이렉트 | Middleware | 모든 요청 전 실행 |
| CRON 작업 | Route Handler | Vercel Cron 연동 |
| 파일 업로드 | Route Handler / Server Action | 상황에 따라 선택 |

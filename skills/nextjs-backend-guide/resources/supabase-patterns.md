# Supabase Patterns

## Client Creation

### 서버 클라이언트 (Server Components, Route Handlers, Server Actions)

```typescript
// lib/supabase/server.ts
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Server Component에서 cookie 설정 시 무시
          }
        },
      },
    }
  );
}
```

### 브라우저 클라이언트 (Client Components)

```typescript
// lib/supabase/client.ts
import { createBrowserClient } from "@supabase/ssr";

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
```

### Admin 클라이언트 (Service Role - 관리자 작업)

```typescript
// lib/supabase/admin.ts
import { createClient } from "@supabase/supabase-js";

export function createAdminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );
}
```

**주의**: Admin 클라이언트는 RLS를 우회하므로 서버 사이드에서만, 반드시 필요한 경우에만 사용.

---

## Authentication

### 서버에서 현재 사용자 가져오기

```typescript
import { createClient } from "@/lib/supabase/server";

export default async function ProfilePage() {
  const supabase = await createClient();

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return <div>Hello, {user.email}</div>;
}
```

### Auth 이벤트 리스닝 (Client)

```typescript
"use client";

import { createClient } from "@/lib/supabase/client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";

export function useAuthListener() {
  const router = useRouter();
  const supabase = createClient();

  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") {
        router.push("/login");
      }
      router.refresh();
    });

    return () => subscription.unsubscribe();
  }, [router, supabase]);
}
```

### Sign In / Sign Up

```typescript
"use server";

import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

export async function signIn(formData: FormData) {
  const supabase = await createClient();

  const { error } = await supabase.auth.signInWithPassword({
    email: formData.get("email") as string,
    password: formData.get("password") as string,
  });

  if (error) {
    return { error: error.message };
  }

  redirect("/");
}

export async function signUp(formData: FormData) {
  const supabase = await createClient();

  const { error } = await supabase.auth.signUp({
    email: formData.get("email") as string,
    password: formData.get("password") as string,
    options: {
      data: {
        name: formData.get("name") as string,
      },
    },
  });

  if (error) {
    return { error: error.message };
  }

  redirect("/verify-email");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
```

---

## Row Level Security (RLS)

### 핵심 원칙

- 모든 테이블에 RLS 활성화
- Supabase 서버 클라이언트는 인증된 사용자의 JWT를 자동으로 전달
- RLS 정책이 행 단위 접근을 제어

### 일반적 RLS 정책 패턴

```sql
-- 사용자가 자신의 데이터만 읽기
CREATE POLICY "Users can read own data"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

-- 사용자가 자신의 데이터만 수정
CREATE POLICY "Users can update own data"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);

-- 인증된 사용자만 삽입
CREATE POLICY "Authenticated users can insert"
  ON posts FOR INSERT
  WITH CHECK (auth.uid() = author_id);

-- 모든 사용자 읽기 가능 (공개 데이터)
CREATE POLICY "Public read access"
  ON posts FOR SELECT
  USING (published = true);
```

### 코드에서 RLS 활용

```typescript
// RLS가 자동 적용되므로 별도 필터 불필요
const supabase = await createClient();

// 로그인한 사용자의 프로필만 반환됨 (RLS)
const { data: profile } = await supabase
  .from("profiles")
  .select("*")
  .single();

// 공개된 게시글만 반환됨 (RLS)
const { data: posts } = await supabase
  .from("posts")
  .select("*")
  .order("created_at", { ascending: false });
```

---

## Realtime

```typescript
"use client";

import { createClient } from "@/lib/supabase/client";
import { useEffect, useState } from "react";
import type { RealtimePostgresChangesPayload } from "@supabase/supabase-js";

export function useRealtimeMessages(channelId: string) {
  const [messages, setMessages] = useState<Message[]>([]);
  const supabase = createClient();

  useEffect(() => {
    const channel = supabase
      .channel(`messages:${channelId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "messages",
          filter: `channel_id=eq.${channelId}`,
        },
        (payload: RealtimePostgresChangesPayload<Message>) => {
          if (payload.eventType === "INSERT") {
            setMessages((prev) => [...prev, payload.new as Message]);
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [channelId, supabase]);

  return messages;
}
```

---

## Storage

```typescript
import { createClient } from "@/lib/supabase/server";

// 파일 업로드
async function uploadFile(file: File, bucket: string, path: string) {
  const supabase = await createClient();

  const { data, error } = await supabase.storage
    .from(bucket)
    .upload(path, file, {
      cacheControl: "3600",
      upsert: false,
    });

  if (error) throw error;
  return data;
}

// Public URL 가져오기
function getPublicUrl(bucket: string, path: string) {
  const supabase = createClient();
  const { data } = supabase.storage.from(bucket).getPublicUrl(path);
  return data.publicUrl;
}

// Signed URL 생성 (비공개 파일)
async function getSignedUrl(bucket: string, path: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(path, 3600); // 1시간

  if (error) throw error;
  return data.signedUrl;
}
```

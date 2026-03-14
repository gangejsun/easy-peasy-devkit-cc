# Server Actions

## Overview

Server Action은 서버에서 실행되는 비동기 함수로, `"use server"` 지시어로 정의한다.
폼 제출과 데이터 변경(Create, Update, Delete)에 사용한다.

---

## 기본 패턴

### 파일 단위 Server Action

```typescript
// lib/actions/user.ts
"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { z } from "zod";

const updateProfileSchema = z.object({
  name: z.string().min(1).max(100),
  bio: z.string().max(500).optional(),
});

export async function updateProfile(formData: FormData) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Unauthorized" };
  }

  const raw = {
    name: formData.get("name"),
    bio: formData.get("bio"),
  };

  const result = updateProfileSchema.safeParse(raw);
  if (!result.success) {
    return { error: "Validation failed", details: result.error.flatten() };
  }

  const { error } = await supabase
    .from("profiles")
    .update(result.data)
    .eq("id", user.id);

  if (error) {
    return { error: error.message };
  }

  revalidatePath("/profile");
  return { success: true };
}
```

### 컴포넌트에서 사용

```typescript
// app/profile/page.tsx
import { updateProfile } from "@/lib/actions/user";

export default async function ProfilePage() {
  return (
    <form action={updateProfile}>
      <input name="name" required />
      <textarea name="bio" />
      <button type="submit">Save</button>
    </form>
  );
}
```

---

## 반환값 패턴

Server Action은 throw 대신 결과 객체를 반환한다 (클라이언트에서 에러 처리가 용이).

```typescript
// 타입 정의
type ActionResult<T = void> =
  | { success: true; data?: T }
  | { success: false; error: string; details?: unknown };

// 사용
export async function createPost(formData: FormData): Promise<ActionResult<{ id: string }>> {
  try {
    const supabase = await createClient();
    // ...검증, 삽입 로직

    const { data, error } = await supabase
      .from("posts")
      .insert(validated)
      .select("id")
      .single();

    if (error) {
      return { success: false, error: error.message };
    }

    revalidatePath("/posts");
    return { success: true, data: { id: data.id } };
  } catch {
    return { success: false, error: "Unexpected error occurred" };
  }
}
```

---

## Client Component에서 Server Action 사용

`useActionState` (React 19) 또는 `useTransition`을 활용:

```typescript
"use client";

import { useActionState } from "react";
import { updateProfile } from "@/lib/actions/user";

function ProfileForm() {
  const [state, formAction, isPending] = useActionState(updateProfile, null);

  return (
    <form action={formAction}>
      <input name="name" required />
      {state?.error && <p className="text-red-500">{state.error}</p>}
      <button type="submit" disabled={isPending}>
        {isPending ? "Saving..." : "Save"}
      </button>
    </form>
  );
}
```

### useTransition 패턴 (비폼 작업)

```typescript
"use client";

import { useTransition } from "react";
import { deletePost } from "@/lib/actions/post";

function DeleteButton({ postId }: { postId: string }) {
  const [isPending, startTransition] = useTransition();

  function handleDelete() {
    startTransition(async () => {
      const result = await deletePost(postId);
      if (!result.success) {
        // 에러 처리
      }
    });
  }

  return (
    <button onClick={handleDelete} disabled={isPending}>
      {isPending ? "Deleting..." : "Delete"}
    </button>
  );
}
```

---

## Revalidation

```typescript
"use server";

import { revalidatePath, revalidateTag } from "next/cache";

export async function createPost(formData: FormData) {
  // ...생성 로직

  // 특정 경로 revalidation
  revalidatePath("/posts");

  // 특정 태그 revalidation (fetch에서 tag 지정 시)
  revalidateTag("posts");

  // 레이아웃까지 revalidation
  revalidatePath("/posts", "layout");
}
```

---

## Redirect after Action

```typescript
"use server";

import { redirect } from "next/navigation";

export async function createPost(formData: FormData) {
  // ...생성 로직

  const { data } = await supabase
    .from("posts")
    .insert(validated)
    .select("id")
    .single();

  revalidatePath("/posts");
  redirect(`/posts/${data.id}`); // throw하므로 try 밖에서 호출
}
```

**주의**: `redirect()`는 내부적으로 throw하므로 try-catch 블록 안에 넣지 않는다.

---

## File Upload with Server Action

```typescript
"use server";

import { createClient } from "@/lib/supabase/server";

export async function uploadAvatar(formData: FormData) {
  const supabase = await createClient();
  const file = formData.get("avatar") as File;

  if (!file || file.size === 0) {
    return { error: "No file provided" };
  }

  if (file.size > 5 * 1024 * 1024) {
    return { error: "File too large (max 5MB)" };
  }

  const ext = file.name.split(".").pop();
  const fileName = `${crypto.randomUUID()}.${ext}`;

  const { error } = await supabase.storage
    .from("avatars")
    .upload(fileName, file);

  if (error) {
    return { error: error.message };
  }

  const { data: urlData } = supabase.storage
    .from("avatars")
    .getPublicUrl(fileName);

  return { success: true, url: urlData.publicUrl };
}
```

---

## Anti-Patterns

```typescript
// bad: Server Action에서 throw (클라이언트가 에러 처리 어려움)
"use server";
export async function createPost(formData: FormData) {
  throw new Error("Something went wrong"); // 클라이언트에서 처리 불가
}

// bad: redirect를 try-catch 안에 넣기
export async function createPost(formData: FormData) {
  try {
    // ...
    redirect("/posts"); // catch에 잡힘!
  } catch {
    return { error: "Failed" };
  }
}

// bad: 검증 없이 FormData 사용
export async function updateUser(formData: FormData) {
  const name = formData.get("name") as string; // 검증 없이 직접 사용
  await supabase.from("users").update({ name });
}
```

# Validation Patterns

## Why Zod

- TypeScript-first: 스키마에서 타입 자동 추론
- 런타임 검증 + 컴파일 타임 타입 안전성
- Next.js, React Hook Form과 자연스럽게 통합
- 작은 번들 크기, 제로 의존성

---

## Basic Patterns

### Primitives

```typescript
import { z } from "zod";

const emailSchema = z.string().email();
const ageSchema = z.number().int().min(0).max(150);
const nameSchema = z.string().min(1).max(100).trim();
const urlSchema = z.string().url();
const uuidSchema = z.string().uuid();
```

### Objects

```typescript
const createUserSchema = z.object({
  email: z.string().email("유효한 이메일을 입력하세요"),
  name: z.string().min(1, "이름은 필수입니다").max(100),
  age: z.number().int().min(0).optional(),
  role: z.enum(["user", "admin"]).default("user"),
});

type CreateUserInput = z.infer<typeof createUserSchema>;
```

### Arrays

```typescript
const tagsSchema = z.array(z.string()).min(1).max(10);

const itemsSchema = z.array(
  z.object({
    name: z.string(),
    quantity: z.number().int().positive(),
  })
);
```

---

## Route Handler에서 검증

```typescript
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";

const createPostSchema = z.object({
  title: z.string().min(1).max(200),
  content: z.string().min(1),
  tags: z.array(z.string()).optional().default([]),
  published: z.boolean().optional().default(false),
});

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const validated = createPostSchema.parse(body);

    // validated는 타입이 보장된 데이터
    const result = await createPost(validated);
    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        {
          error: "Validation Error",
          details: error.errors.map((e) => ({
            field: e.path.join("."),
            message: e.message,
          })),
        },
        { status: 400 }
      );
    }
    return NextResponse.json(
      { error: "Internal Server Error" },
      { status: 500 }
    );
  }
}
```

---

## Server Action에서 검증

```typescript
"use server";

import { z } from "zod";

const updateProfileSchema = z.object({
  name: z.string().min(1).max(100),
  bio: z.string().max(500).optional(),
  website: z.string().url().optional().or(z.literal("")),
});

export async function updateProfile(formData: FormData) {
  const raw = {
    name: formData.get("name"),
    bio: formData.get("bio"),
    website: formData.get("website"),
  };

  const result = updateProfileSchema.safeParse(raw);

  if (!result.success) {
    return {
      error: "Validation failed",
      fieldErrors: result.error.flatten().fieldErrors,
    };
  }

  // result.data는 타입 안전
  const { name, bio, website } = result.data;
  // ...
}
```

---

## Search Params 검증

```typescript
const searchParamsSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().min(1).max(100).default(10),
  sort: z.enum(["newest", "oldest", "popular"]).default("newest"),
  q: z.string().optional(),
});

export async function GET(request: NextRequest) {
  const params = Object.fromEntries(request.nextUrl.searchParams);
  const { page, limit, sort, q } = searchParamsSchema.parse(params);
  // ...
}
```

---

## Type Inference

```typescript
// 스키마에서 타입 추론
const userSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  name: z.string(),
  createdAt: z.string().datetime(),
});

type User = z.infer<typeof userSchema>;

// Input과 Output 분리
const createUserSchema = userSchema.omit({ id: true, createdAt: true });
type CreateUserInput = z.infer<typeof createUserSchema>;

const updateUserSchema = createUserSchema.partial();
type UpdateUserInput = z.infer<typeof updateUserSchema>;
```

---

## Advanced Patterns

### Conditional Validation

```typescript
const paymentSchema = z.discriminatedUnion("method", [
  z.object({
    method: z.literal("card"),
    cardNumber: z.string().length(16),
    expiry: z.string().regex(/^\d{2}\/\d{2}$/),
  }),
  z.object({
    method: z.literal("bank"),
    accountNumber: z.string().min(10),
    bankCode: z.string(),
  }),
]);
```

### Transform

```typescript
const slugSchema = z
  .string()
  .transform((val) => val.toLowerCase().replace(/\s+/g, "-"));

const priceSchema = z
  .string()
  .transform((val) => Number(val.replace(/,/g, "")))
  .pipe(z.number().positive());
```

### Preprocess

```typescript
// FormData의 빈 문자열을 undefined로 변환
const optionalString = z.preprocess(
  (val) => (val === "" ? undefined : val),
  z.string().optional()
);
```

### Schema Composition

```typescript
const baseSchema = z.object({
  id: z.string().uuid(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

const userSchema = baseSchema.extend({
  email: z.string().email(),
  name: z.string(),
});

const postSchema = baseSchema.extend({
  title: z.string(),
  content: z.string(),
  authorId: z.string().uuid(),
});
```

### Refine (Custom Validation)

```typescript
const dateRangeSchema = z
  .object({
    startDate: z.string().datetime(),
    endDate: z.string().datetime(),
  })
  .refine((data) => new Date(data.startDate) < new Date(data.endDate), {
    message: "End date must be after start date",
    path: ["endDate"],
  });

const passwordSchema = z
  .object({
    password: z.string().min(8),
    confirmPassword: z.string(),
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: "Passwords don't match",
    path: ["confirmPassword"],
  });
```

---

## Environment Variable Validation

```typescript
// lib/env.ts
import { z } from "zod";

const envSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
});

export const env = envSchema.parse(process.env);
```

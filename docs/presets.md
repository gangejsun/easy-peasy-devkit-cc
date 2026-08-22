# Presets Guide

프리셋은 **프론트엔드 축과 백엔드 축 두 개**로 나뉜다. `/epcc-init`에서 각각 하나씩 고르면
스택 조합이 확정되고, 그 조합에 맞는 가이드 스킬이 결정된다.

> **왜 2축인가**: 가이드 내용은 한 축의 함수가 아니라 **조합의 함수**이기 때문이다.
> 같은 Supabase라도 Next.js와 짝지으면 Route Handlers·Server Actions 중심이고,
> React+Vite SPA와 짝지으면 Edge Functions·브라우저 직접 호출 중심으로 완전히 다른
> 가이드가 된다. 두 축을 먼저 확정해야 서로를 고려한 가이드를 만들 수 있다.

## 프론트엔드 축 (`presets/frontend/`)

| 이름 | 스택 | 서버 코드 위치 |
| --- | --- | --- |
| `nextjs` | Next.js 15 App Router + React 19 + Tailwind v4 + shadcn/ui + Zustand | 프레임워크 내장 (Route Handlers·Server Actions) |
| `react-vite` | React + Vite SPA (SSR 없음) + Tailwind + React Router + Zustand | 없음 — 백엔드 축이 전적으로 소유 |
| `vanilla` | 프레임워크 없음 — 표준 DOM + ES 모듈 (Vite 번들) | 없음 |
| `none` | 프론트엔드 없음 (API 전용 프로젝트) | — |

**언어는 프리셋이 아니라 차원이다.** 모든 프론트엔드 프리셋은 TypeScript를 기본값으로
두되(`vanilla`만 JavaScript 기본), `/epcc-init` Step 4에서 바꿀 수 있다. JavaScript를 고르면
가이드의 타입 표준 슬롯이 JSDoc 규약과 런타임 스키마 검증으로 대체되고 생성 타입 절은 빠진다.

## 백엔드 축 (`presets/backend/`)

백엔드는 **형태가 세 가지**다 — 이름만 다른 동급 항목이 아니다.

| 이름 | 형태 | 스택 | 보안 경계 |
| --- | --- | --- | --- |
| `supabase` | BaaS | PostgreSQL + RLS + Auth + Storage + Realtime | RLS가 최종 방어선. 정책이 없으면 **전면 차단** |
| `firebase` | BaaS | Firestore + Auth + Storage + Cloud Functions | Security Rules가 최종 방어선. 규칙이 없으면 **전면 개방**(RLS와 정반대) |
| `aws-serverless` | 서버리스 조립 | Lambda + API Gateway + DynamoDB + Cognito | **행 수준 정책 엔진 없음** — 애플리케이션 층 검사가 실질적 유일 경계 |
| `aws-container` | 자체 서버 | ECS/Fargate + ALB + RDS PostgreSQL + Drizzle + Cognito(OIDC) | **행 수준 정책 엔진 없음** — 소유권 검사 누락이 곧 데이터 유출. AWS 종속을 인프라 층에만 두어 온프레미스 이식이 가능하다 |
| `gcp-serverless` | 서버리스 조립 | Cloud Run/Functions + Firestore + Identity Platform | IAM/토큰 검증 + (직접 접근 경로가 있으면) Security Rules |
| `fastapi` | 자체 서버 | FastAPI + SQLAlchemy 2.0 + Pydantic v2 + Alembic + pytest | 애플리케이션 층이 유일한 경계 |
| `node-api` | 자체 서버 | Express/NestJS + PostgreSQL + Prisma/Drizzle + Zod | 애플리케이션 층이 유일한 경계 |
| `none` | — | 백엔드 없음 / 외부 REST API 소비 | 외부 API 토큰 보관 위치가 위험 지점 |

**데이터 계층에 정책 엔진이 있는지가 가이드 내용을 가장 크게 가른다.** 있으면 애플리케이션
검사를 이중 방어로 쓰지만, 없으면 소유권 검사 누락이 곧 데이터 유출이다. 두 서술을 뒤바꾸면
안전하다는 착각을 만들기 때문에 생성 시 이 값을 반드시 전달한다.

`frontend: none` + `backend: none`은 이전의 `blank` 프리셋에 해당한다.

## 조합 → 가이드 매핑

| 조합 | 가이드 |
| --- | --- |
| `nextjs` × `supabase` | **사전 제작본 사용** — 플러그인의 `/nextjs-frontend-guide`·`/nextjs-backend-guide` |
| `react-vite` × `aws-container` | **사전 제작본 사용** — 플러그인의 `/react-aws-frontend-guide`·`/react-aws-backend-guide` |
| `none` × `none` | 없음 (Core 스킬만) |
| 그 외 모든 조합 | 프로젝트의 `.claude/skills/frontend-guide`·`backend-guide`로 **생성** |

생성 경로는 `stack-guide-generator`가 담당하며, 규격서 기반 신선 생성 → 기계 검증 게이트 →
독립 적대적 감사 → 수리 → 재검증 루프를 거친다. 가이드당 서브에이전트 2개를 쓰므로
몇 분 걸린다. 프리셋 밖 차원(MongoDB·Prisma·Cognito 등)으로 바꿔도 이 경로로 처리된다 —
**프리셋은 출발점이지 상한이 아니다.**

**사전 제작본을 쓸지 생성할지는 시스템이 정한다 — 묻지 않는다.** 구현 세부가 사용자에게
새어 나가면 답할 수 없는 질문이 되기 때문이다. 생성 경로도 승인을 묻지 않고 바로 실행한다.

### 사전 제작본 추가 기준

조합은 27개이고 전부 사전 제작하면 가이드 **45개(약 9만 줄)** 가 된다. 실측 근거가 있다:
가이드 2개에 권한 상승 취약점·폐기 API·이전 메이저 버전 잔재가 쌓여 **몇 달간 발견되지
않았고**, 그것을 찾는 데 감사 에이전트 3개와 수리 에이전트 2개가 들었다. 감사받지 않는
사전 제작본은 부패해서 **없는 가이드보다 나쁘다** — 틀린 지침을 신뢰하게 만들기 때문이다.

그래서 추가 기준은 개수가 아니라 조건이다: **정기 감사 대상으로 등록할 수 있을 때만
사전 제작한다.** 그렇지 않은 조합은 신선 생성이 엄격히 우월하다.

현재 사전 제작본은 2쌍이다. `react-vite` × `aws-container`가 두 번째로 추가된 이유는
조직의 표준 스택이어서 **실제로 쓰이고 유지되기 때문**이다 — 위 조건을 충족한 사례다.

### 구식화 점검 — 묻지 않고 대조한다

사전 제작 가이드는 SKILL.md 첫머리에 검증 기준선을 선언한다:

```
<!-- epcc-guide-baseline: verified 2026-08-21 next@15 react@19 zod@4 tailwindcss@4 ... -->
```

`/epcc-init`이 프로젝트의 `package.json`과 **메이저 버전을 대조**해, 어긋날 때만 어떤
패키지가 어떻게 다른지 보고한다. 일치하면 아무 말도 하지 않는다. "재생성할까요?"를 묻지
않는 이유는 사용자가 가이드의 낡음을 판단할 근거가 없어 그 질문이 곧 소음이 되기 때문이다.

## 병합 규칙

`/epcc-init`은 세 파일을 이 순서로 병합한다 (뒤가 앞을 덮어씀):

1. `presets/base.json` — 공통 `domains`·보안 패턴 (AWS Key, GitHub PAT, Generic API Key)
2. `presets/frontend/<선택>.json`
3. `presets/backend/<선택>.json`

- `security.secretPatterns`와 `additionalStack`은 덮어쓰지 않고 **누적**한다
- `domains.sourceDir`은 프론트엔드 축 우선, 프론트엔드가 `none`이면 백엔드 축
- 각 프리셋의 `notes`는 config에 기록하지 않고 **가이드 생성 에이전트에 조합 맥락으로 전달**한다

## 툴체인이 둘인 조합

`react-vite` × `fastapi`처럼 언어·패키지 매니저가 다른 조합은 축마다 명령이 다르다.
config는 이를 축별로 기록하되, **프로젝트 대표 명령**(`techStack.commands`)을 반드시 채운다 —
`build-gate`와 `health-check`가 읽는 값이다.

## 커스텀 스택

프리셋에 없는 조합은 `/epcc-init`에서 가장 가까운 축을 고른 뒤 Step 4.5에서 차원을 바꾸거나,
`/stack-guide-generator`를 직접 호출해 차원을 지정한다. 어느 쪽이든 같은 검증 루프를 거쳐
프로젝트 소유 가이드가 생성된다.

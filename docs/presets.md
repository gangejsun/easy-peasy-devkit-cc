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
| `nextjs` | Next.js 15 App Router + React 19 + TS strict + Tailwind v4 + shadcn/ui + Zustand | 프레임워크 내장 (Route Handlers·Server Actions) |
| `react-vite` | React + Vite SPA (SSR 없음) + TS + Tailwind + React Router + Zustand | 없음 — 백엔드 축이 전적으로 소유 |
| `none` | 프론트엔드 없음 (API 전용 프로젝트) | — |

## 백엔드 축 (`presets/backend/`)

| 이름 | 스택 | 보안 경계 |
| --- | --- | --- |
| `supabase` | BaaS: PostgreSQL + RLS + Auth + Storage + Realtime | RLS가 최종 방어선. 서버 런타임이 있으면 애플리케이션 층 검사와 이중 방어 |
| `fastapi` | 자체 서버: FastAPI + SQLAlchemy 2.0 + Pydantic v2 + Alembic + pytest | 애플리케이션 층이 유일한 경계 |
| `none` | 백엔드 없음 / 외부 REST API 소비 | 외부 API 토큰 보관 위치가 위험 지점 |

`frontend: none` + `backend: none`은 이전의 `blank` 프리셋에 해당한다.

## 조합 → 가이드 매핑

| 조합 | 가이드 |
| --- | --- |
| `nextjs` × `supabase` | **사전 제작본 사용** — 플러그인의 `/nextjs-frontend-guide`·`/nextjs-backend-guide` |
| `none` × `none` | 없음 (Core 스킬만) |
| 그 외 모든 조합 | 프로젝트의 `.claude/skills/frontend-guide`·`backend-guide`로 **생성** |

생성 경로는 `stack-guide-generator`가 담당하며, 규격서 기반 신선 생성 → 기계 검증 게이트 →
독립 적대적 감사 → 수리 → 재검증 루프를 거친다. 가이드당 서브에이전트 2개를 쓰므로
몇 분 걸린다. 프리셋 밖 차원(MongoDB·Prisma·Cognito 등)으로 바꿔도 이 경로로 처리된다 —
**프리셋은 출발점이지 상한이 아니다.**

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

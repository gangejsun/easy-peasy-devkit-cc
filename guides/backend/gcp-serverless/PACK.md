<!-- epcc-pack: backend/gcp-serverless v3.14.0 verified 2026-08-24 hono@4 @hono/node-server@2 @google-cloud/firestore@9 jose@6 zod@4 typescript@7 vitest@4 @types/node@26 -->

# gcp-serverless 축 팩 — 허브 조각

조립 시 `SKILL.md`로 옮겨지는 조각들이다. 각 조각은 `<!-- pack-slot: 이름 -->` ~
`<!-- /pack-slot -->` 사이에 있고, 축 안에서 닫혀 조합이 바뀌어도 그대로 쓰인다.
파일 끝의 「이음매가 채울 것」 표에 있는 슬롯만 이음매가 새로 쓴다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
src/
├── main.ts                  # 부팅만 — startServer() + SIGTERM 핸들러 안에서 shutdown(server)
├── app.ts                   # createApp(): 라우터 마운트 + installErrorHandlers + /healthz
├── settings.ts              # 프로세스 환경을 읽는 **유일한 파일** (모듈 최상위에서 검증·실패)
├── errors.ts                # AppError — **이음매가 소유한다.** 프레임워크를 import하지 않는다
├── schemas/
│   ├── task.ts              # zod 스키마 + TaskStatus (값은 소문자 'open'·'done')
│   └── errors.ts            # fieldErrors — zod 오류를 필드 맵으로
├── firestore/
│   ├── client.ts            # Firestore 인스턴스 — 모듈 최상위, 프로세스당 하나
│   ├── converter.ts         # taskConverter — 읽을 때 스키마를 다시 파싱한다
│   ├── tasks.ts             # 작업 리포지토리 — HTTP를 모른다. ownerId → taskId 순서
│   ├── cursor.ts            # encodeCursor · decodeCursor — 커서는 신뢰 입력이 아니다
│   └── errors.ts            # gRPC 코드 판별(5·6·9·10) — HTTP를 모른다
├── identity/
│   └── verify.ts            # verifyIdToken · jwks — Identity Platform ID 토큰
├── http/
│   ├── errors.ts            # ERROR_STATUS · toAppError (hono를 import한다)
│   ├── handlers.ts          # installErrorHandlers — **이음매가 소유한다**
│   ├── auth.ts              # currentUser · AuthUser — **이음매가 소유한다**
│   └── routes.ts            # apiRouter — **이음매가 소유한다**
├── obs/
│   └── log.ts               # log() — stdout에 JSON 한 줄. severity 키를 쓴다
└── services/
    └── tasks.ts             # 도메인 규칙. 리포지토리를 부르고 AppError를 던진다

firestore.indexes.json       # 복합 인덱스 선언 — 없으면 목록 쿼리가 런타임에 죽는다
firestore.rules              # 전면 거부 — 이 축은 클라이언트가 Firestore에 직접 붙지 않는다
Dockerfile                   # Cloud Run 컨테이너. PORT를 환경에서 읽고 0.0.0.0에 바인딩한다

test/
├── helpers.ts               # appFetch · withEmulator
├── schemas.test.ts          # 스키마 단위 — 부분 수정·미지 키·빈 객체
├── errors.test.ts           # gRPC 코드 판별과 상태 매핑
└── tasks.test.ts            # 소유권 회귀 — 긍정·부정을 같은 테스트에 건다
```

**계층은 한 방향이다**: `routes → services → firestore`. 리포지토리가 `Context`를 받거나
HTTP 상태를 알면 그 계층은 이미 무너진 것이다 — 테스트가 HTTP를 세워야만 돌게 된다.

**`src/http/`의 세 파일(`handlers.ts`·`auth.ts`·`routes.ts`)과 `src/errors.ts`는 이음매
소유다.** 팩은 그것들을 부르기만 한다. 조립 전에는 정의가 없는 것이 정상이고, 게이트가
`--assembly`와 함께 그 충족을 검사한다.
<!-- /pack-slot -->

> **아래 슬롯은 L2가 쓴다** (L0는 디렉토리 트리만 동결한다):
> `core-principles-axis` · `common-imports-axis` · `architecture-overview` ·
> `http-status-and-antipatterns` · `quick-start-axis` · `anti-patterns-axis`.

## 이음매가 채울 것

| 슬롯 | 무엇을 |
| --- | --- |
| `api-endpoints` | Hono 라우터 형태 · 요청/응답 봉투 · 에러 봉투 방출 |
| `auth-boundaries` | 토큰이 어떻게 도착하는가(베어러 vs 세션 쿠키) · `currentUser` 배선 · 로그인/로그아웃 흐름 |
| `complete-example` | 인덱스 → 스키마 → converter → 리포지토리 → 서비스 → 라우터 → 테스트 관통 |

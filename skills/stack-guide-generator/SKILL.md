---
name: stack-guide-generator
description: 프로젝트의 기술 스택 조합(프론트엔드·백엔드 유형·클라우드·DB·데이터 액세스·인증)에 맞는 frontend-guide/backend-guide 스킬을 프로젝트의 .claude/skills/에 생성합니다. epcc-init이 스택 선택 후 호출하거나, 사용자가 "가이드 생성", "스택 가이드", "기술 스택 변경"을 요청할 때, 프리셋에 없는 스택(AWS·MongoDB·SvelteKit 등)으로 시작할 때 사용합니다.
---

# Stack Guide Generator

확정된 스택 조합으로 프로젝트 소유의 가이드 스킬을 생성한다.
구조는 `assets/guide-skeleton.md` 계약을 따르고, 내용은 조합 지식으로 채운다.

> **원칙: 본문을 먼저 만들고 검증한 뒤에만 설치한다.** description이 본문이 못 지키는
> 약속을 하는 스킬(placeholder)을 만드는 것이 이 스킬이 대체하는 실패 모드다.

## Step 1: 차원 확정

우선순위: `epcc.config.json`의 `techStack` → 부족한 차원만 인터뷰.

| 차원 | 선택지 예 | 의존 규칙 |
| --- | --- | --- |
| 프론트엔드 | Next.js · React+Vite · SvelteKit · 없음(API 전용) | — |
| 백엔드 유형 | BaaS(Supabase·Firebase) · 클라우드 자체 구축 · 프레임워크 내장 | **기본값이 있어도 반드시 확인 질문** — 프리셋의 Supabase는 기본값이지 고정이 아니다 |
| 클라우드/호스팅 | AWS · GCP · Azure · Vercel · 자체 | 자체 구축 선택 시 필수 |
| DB | PostgreSQL · MySQL · MongoDB · DynamoDB | BaaS면 자동 추론 후 확인만, 자체 구축이면 필수 질문 |
| 데이터 액세스 | Prisma · Drizzle · SQLAlchemy · SDK 직접 | DB 확정 후 |
| 인증 | Supabase Auth · NextAuth · Cognito · 자체 | 백엔드 유형 연동 |

확정된 조합을 `epcc.config.json`의 `techStack.backend`에 기록한다 (스키마의 backendType·cloudProvider·database·dataAccess·auth 필드).

## Step 2: 생성 범위와 분기

| 조합 | 동작 |
| --- | --- |
| **정확히** Next.js + Supabase(+PostgreSQL) | **생성하지 않음** — 플러그인의 nextjs-frontend/backend-guide가 곧 이 조합의 가이드다. 중복 생성은 낭비이자 드리프트 원천 |
| Next.js + 다른 백엔드 | frontend-guide + backend-guide 생성 |
| 프론트엔드 없음 (API 전용) | backend-guide만 |
| 백엔드 없음 (정적/SPA+외부 API) | frontend-guide만 (API 클라이언트 패턴 포함) |
| 기존 생성본 존재 | Step 5의 스탬프 대조 — 수동 편집 감지 시 덮어쓰지 않고 diff 제시 |

## Step 3: 생성

1. `assets/guide-skeleton.md`를 읽고 필수 섹션 8개 골격을 만든다
2. 내용 슬롯을 확정 조합의 지식으로 채운다:
   - 검증 가능한 사실(공식 문서 수준의 표준 패턴)만 단정형으로 쓴다
   - 프로젝트에 실재하는 구조(디렉토리·설정)가 있으면 관례보다 우선한다
   - 확신이 없는 패턴은 쓰지 않는다 — 빈 슬롯이 틀린 내용보다 낫다
   - **형식 참조 (선택, 방화벽 있음)**: 예시 코드 밀도·좋/나쁨 쌍의 형식·설명 어조가
     막히면 플러그인의 `nextjs-frontend-guide`·`nextjs-backend-guide`를 **형식
     참조로만** 열어본다. 내용·라이브러리·패턴 복사는 금지 — Step 4의 교차 누출
     검사가 이를 잡는다. 계약(skeleton)과 충돌하면 항상 계약이 이긴다
3. resources/를 4~10개로 분할하고 Navigation Guide에 전부 매핑한다
4. 산출 위치: 프로젝트의 `.claude/skills/frontend-guide/` · `.claude/skills/backend-guide/`
5. **관계형 DB면 데이터 모델링 카드와 연결한다 — 복사하지 않는다.** 정본은
   T1 규칙 카드(`.claude/rules/` 아래 `data-modeling.md`)로 epcc-init이 모든 프리셋에
   설치하며, `paths:`(supabase·migrations·db·prisma·drizzle) 매칭 시 자동 로드된다.
   생성하는 backend-guide에는 다음만 넣는다:
   - Navigation Guide에 1행: 테이블·마이그레이션 설계 → 데이터 모델링 카드 (자동 로드) 안내
   - **PostgreSQL이 아닌 RDB(MySQL 등)**: "카드의 PG 특화 절(§5·10·14·16·18)은 원칙만
     취하고 문법은 이 스택으로 치환" 1줄을 명시
   - **NoSQL(MongoDB·DynamoDB)**: 카드는 paths 미매칭으로 휴면 — 해당 DB의 모델링
     패턴(문서 설계·파티션 키 등)을 조합 지식으로 리소스에 직접 작성

   > 정본을 스킬 리소스로 복사·적응하지 않는 이유: 사본은 플러그인 갱신에서 끊긴
   > 드리프트 원천이다. 단일 카드 + 버전 스탬프 갱신이 v3의 배포 방식이다.

## Step 4: 자기 검증 — 실패 시 설치하지 않는다

skeleton의 체크리스트 6항을 기계적으로 확인한다:

```bash
# 섹션 존재·순서
grep -n "^## " .claude/skills/backend-guide/SKILL.md
# dangling 참조
grep -oE 'resources/[a-z-]+\.md' .claude/skills/backend-guide/SKILL.md | sort -u | while read r; do [ -f ".claude/skills/backend-guide/$r" ] || echo "MISSING $r"; done
# 교차 누출 (예: 비-Supabase 조합)
grep -ci supabase .claude/skills/backend-guide/SKILL.md .claude/skills/backend-guide/resources/*.md
# 예산
wc -l .claude/skills/backend-guide/SKILL.md .claude/skills/backend-guide/resources/*.md
```

전항 통과 → 설치 확정. 실패 → 산출물을 지우고 실패 항목 보고.

## Step 5: 스탬프와 보고

- 각 SKILL.md에 생성 스탬프 기록 (skeleton의 형식)
- 사용자 보고: 생성된 스킬 2개(또는 1개)·리소스 수·검증 결과·"다음 세션부터 자동 트리거됨"
- 재생성 요청 시: 스탬프의 stack= 값과 새 조합을 비교해 변경 차원을 보고하고,
  수동 편집이 감지되면 편집 부분 diff를 보여준 뒤 사용자 확인을 받는다

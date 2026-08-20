# 가이드 구조 계약 (Guide Skeleton Contract)

생성되는 frontend-guide / backend-guide가 반드시 따라야 하는 구조.
nextjs-frontend-guide(290줄·리소스 10)·nextjs-backend-guide(220줄·리소스 10)의
실증된 골격에서 도출했다.

## 구조와 내용의 구분

- **구조(스택 무관)**: 섹션 골격·순서·형식. 아래 표의 전 항목. 생성 시 변경 불가
- **내용(스택 고유)**: 각 슬롯을 채우는 실제 지식. 확정된 스택 조합에서만 도출한다.
  다른 스택의 내용(예: Supabase 패턴을 AWS 가이드에)을 누출하면 자기 검증 실패다

## 필수 섹션 (순서 고정)

| # | 섹션 (구조) | 내용 슬롯 | 예산 |
| --- | --- | --- | --- |
| 1 | frontmatter | `name: frontend-guide`/`backend-guide` · description은 "무엇을 다루는가 + Use when creating or modifying <작업 목록>" 형식. `[Preset:]` 접두사 금지 (프로젝트 소유이므로 게이팅 불필요) | ≤450자 |
| 2 | `## Quick Start` — 작업 단위 체크리스트 2개 | 체크리스트 이름(New Component/New Route Handler 등)과 항목은 스택에서 도출 | 항목 6~9개/개 |
| 3 | `## Architecture Overview` | 스택 구성 요소와 책임 경계 | ≤30줄 |
| 4 | `## Directory Structure` | 해당 스택의 관례적 배치 (프로젝트 실제 구조가 있으면 그것을 우선) | ≤30줄 |
| 5 | `## Core Principles (N Key Rules)` — 번호형 규칙 + 코드 예시 | 규칙 5~8개. 각 규칙에 좋은/나쁜 예 코드 1쌍. **backend는 입력 검증·인증/권한 규칙을, frontend는 반복 UI 추출(공통 레이아웃) 규칙을 반드시 포함** — 스택이 바뀌어도 이 두 범주는 보편이다 | 규칙당 ≤20줄 |
| 6 | `## Common Imports` | 스택 표준 import 블록 | ≤30줄 |
| 7 | 보조 섹션 1개 (frontend: 컴포넌트 템플릿 / backend: HTTP Status + Anti-Patterns) | 스택별 선택 | ≤40줄 |
| 8 | `## Navigation Guide` — **태스크→리소스 매핑 테이블** | "하려는 일 → 읽을 파일" 행. resources/ 전 파일이 정확히 1회 이상 등장해야 함 | 전 리소스 커버 |

## resources/ 분할 규칙

- 4~10개 파일. 스택 복잡도에 비례 (BaaS 단순 조합 4~6, 자체 구축 조합 6~10)
- 각 파일 ≤300줄. 초과 시 파일 상단에 TOC
- 파일명은 태스크 중심 (`api-routes.md`, `database-patterns.md`) — 기술명 나열 금지
- 데이터 액세스·인증 리소스는 **확정 조합 전용** 내용만 담는다

## 자기 검증 체크리스트 (Step 4에서 기계적으로 확인)

1. 필수 섹션 8개가 순서대로 존재하는가
2. Navigation Guide의 모든 참조 파일이 실재하는가 (dangling 0)
3. SKILL.md ≤300줄, 리소스 파일당 ≤300줄
4. **교차 누출 0**: 확정 조합에 없는 스택 키워드가 본문에 없는가
   (예: 비-Supabase 조합에서 `grep -ci supabase` = 0, 비관계형 DB에서 RLS·마이그레이션 부재)
5. description이 본문에 실재하는 내용만 약속하는가 (placeholder 사고의 재발 방지)
6. 생성 스탬프가 존재하는가

**하나라도 실패하면 설치하지 않는다.** 실패 항목을 보고하고 사용자 판단을 받는다.

## 생성 스탬프 형식

SKILL.md frontmatter 직후 1줄:

```
<!-- epcc-guide: generated YYYY-MM-DD stack=<frontend>+<backendType>+<database>+<dataAccess> -->
```

재생성 시 이 스탬프와 파일 수정 시각을 대조해 수동 편집을 감지한다.

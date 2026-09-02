<!-- epcc-doctor: allow-stale-refs -->
<!--
  프로젝트 전용 code-conventions 카드의 생성 뼈대.
  epcc-init Step 7.5가 프리셋에 맞는 스택 블록 하나만 남기고 나머지 스택 블록을 제거한 뒤
  프로젝트의 `.claude/rules/` 아래 `code-conventions.md`로 저장한다.

  원칙:
  - 프로젝트 소유 파일 — epcc-rule-version 스탬프를 넣지 않는다
  - "공통" 표시 블록(네이밍 일반·코드 스타일·커밋 메시지)은 모든 프리셋에서 유지한다
  - 프로젝트 고유 규약이 이미 있으면(기존 CLAUDE.md·린트 설정) 사용자 확인 후 반영한다
  - 이 주석 블록과 {{안내}}는 생성 시 전부 제거한다
  - 실전 검증 출처: easy-peasy-claudecode-devkit에서 앱 서비스 개발로 검증된 컨벤션
-->
---
paths:
  - "{{SOURCE_DIR}}/**"
  # 토폴로지가 요구하는 경로를 **반드시** 여기 넣는다 (epcc-init Step 7.5 항목 5가 검증한다):
  #   monorepo → 공유 패키지 경로 (예: "packages/**")
  #   msa      → 서비스 루트들   (예: "services/**", "apps/**")
  # 빠뜨리면 그 경로를 편집할 때 이 카드가 로드되지 않는다.
---

# 코딩 컨벤션

## 핵심 원칙

<!-- 스택 블록 [nextjs-supabase / react 계열] — TypeScript+React 검증본 -->
- **any 금지** — unknown 또는 구체적 타입 사용
- **서버 컴포넌트 우선** — `"use client"`는 필요 시만 (Next.js만 해당)
- **Import**: `{{IMPORT_ALIAS}}` alias 필수 (상대경로 금지)
- **함수 컴포넌트**: `function` 키워드 선언 (arrow function보다 선호)
- TypeScript strict 모드 준수

<!-- 스택 블록 [python-fastapi] -->
- 타입 힌트 필수 — mypy(또는 pyright) strict 통과
- Pydantic v2 모델로 모든 입출력 검증
- 라우터는 라우팅만 — 비즈니스 로직은 서비스 계층으로 분리
- 포맷/린트: ruff (PEP 8 준수)

<!-- 스택 블록 [blank] — 스택 확정 후 채운다. 비워두지 말고 확정 시점에 갱신 -->

## 네이밍 규칙 (공통 — 스택에 맞게 예시만 조정)

| 대상                   | 규칙                                     | 예시                             |
| ---------------------- | ---------------------------------------- | -------------------------------- |
| 컴포넌트/클래스 파일   | PascalCase                               | `ProductCard`, `OrderService`    |
| 함수/변수/유틸/훅 파일 | camelCase                                | `formatPrice`, `useCart.ts`      |
| 상수                   | UPPER_SNAKE_CASE                         | `MAX_RETRIES`, `API_BASE_URL`    |
| DB 네이밍              | snake_case · 복수형 테이블 · `_at` 접미사 | 상세: `.claude/rules/data-modeling.md` (T1 카드 — DB 경로 편집 시 자동 로드) |
| 타입/인터페이스        | PascalCase + 접미사                      | `OrderResponse`, `UserProfile`   |
| 상태 스토어            | use~Store                                | `useAuthStore`                   |

## 코드 스타일 (공통)

- Props/스키마 타입은 사용하는 컴포넌트·모듈과 같은 파일에 정의
- 매직 넘버 금지 → 이름 있는 상수로 정의
- 에러 핸들링: 경계(핸들러/Error Boundary)에서 잡고, 사용자에게는 친화적 메시지만 노출

## 커밋 메시지 (공통)

- **{{커밋 언어 — 기본: 한국어}}**로 작성, 형식: `태그: 설명`
- Conventional Commits 8종:
  `feat:` 새 기능 | `fix:` 버그 수정 | `refactor:` 리팩토링 | `style:` 스타일/UI |
  `chore:` 설정/빌드 | `docs:` 문서 | `test:` 테스트 | `perf:` 성능 개선
- 예: `feat: 주문 생성 페이지 추가`

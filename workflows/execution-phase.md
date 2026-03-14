---
description: "[Phase 4] 구현 단계 워크플로우 (코드 작성)"
---

# Execution Phase Workflow (P4)

이 워크플로우는 `dev/active/[기능명]/` 에 정의된 계획에 따라 실제 코드를 구현하는 과정입니다.

1. **문서 숙지**
   - 구현 전 반드시 `dev/active/[기능명]/` 에 있는 `plan.md`, `context.md`, `tasks.md` 파일을 모두 읽고 목표와 제약사항을 파악해야 합니다.

2. **컨텍스트 로드**
   - 개발에 들어가기 전 `.claude/rules/project-structure.md`, `.claude/rules/code-conventions.md`, `.claude/rules/domain-boundaries.md` 파일을 확인하여 프로젝트 공통 규칙을 숙지합니다.

3. **코드 구현**
   - `tasks.md`에 정의된 **Scope(수정 범위) 안에서만** 코딩을 진행합니다.
   - 작업 중 예상치 못한 문제가 발생해 기존 구조를 크게 변경해야 한다면(아키텍처 변경 등), 즉시 코딩을 멈추고 `notify_user` 로 사용자에게 상황을 공유합니다.

4. **상태 동기화**
   - `dev/active/[기능명]/tasks.md` 의 체크리스트 현황을 업데이트해 나가며 진행 상황을 추적합니다.

5. **자체 검증**
   - 코드를 수정한 뒤에는 문법 오류나 에러 처리가 누락되지 않았는지 꼼꼼히 확인하고, 빌드/테스트 명령을 실행하여 안정성을 검증합니다.

6. **리뷰 단계 전환**
   - 구현 코드 퀄리티가 만족스러우면 Review Phase 워크플로우로 전환합니다.

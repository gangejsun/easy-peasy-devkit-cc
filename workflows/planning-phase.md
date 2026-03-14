---
description: "[Phase 1~3] 기획 단계 워크플로우 (PRD 및 개발 문서 생성)"
---

# Planning Phase Workflow (P1~P3)

이 워크플로우는 사용자가 신규 기능 개발이나 대규모 수정을 요청했을 때, 기획 문서(PRD)와 개발 문서(plan, context, tasks)를 생성하는 과정입니다.

1. **요구사항 분석 (P1)**
   - 사용자의 요청을 분석하고 구체화합니다. 구체적인 정보가 부족하면 즉시 사용자에게 물어봅니다 (`notify_user`).

2. **PRD 생성/수정 (P2)**
   - 신규 기능: `/dev/docs/prd/prd-[기능명].md`를 작성합니다.
   - 기존 기능 개선: `/dev/docs/prd/` 에서 관련 문서를 검색하여 내용을 업데이트합니다.

3. **개발 문서 생성 (P3)**
   - `/dev/active/[기능명]/` 디렉토리 하위에 다음 파일들을 작성합니다.
     - `[기능명]-plan.md`
     - `[기능명]-context.md`
     - `[기능명]-tasks.md`

4. **검토 (Human-in-the-Loop)**
   - 기획 문서 생성을 완료하면, 구현(Phase 4)으로 곧바로 넘어가지 말고 `notify_user`를 통해 사용자에게 문서 내용 및 Scope(수정 범위) 확인을 요청합니다.

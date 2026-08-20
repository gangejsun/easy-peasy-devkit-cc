---
paths:
  - ".claude/**"
  - "scripts/**"
  - "hooks/**"
  - "rules/**"
  - "agents/**"
  - "skills/**"
---
<!-- epcc-rule-version: 3.4.2 -->

# 하네스 변경 카드

훅·규칙·스킬·에이전트·스크립트를 건드릴 때 로드된다.

> **핵심: Script가 할 수 있는 것은 Script에, LLM만 할 수 있는 것은 LLM에.**

## 추가 전 3-질문

| # | 질문 | YES면 |
| --- | --- | --- |
| Q1 | 기존 훅/규칙/스킬/**Claude Code 빌트인**과 역할이 겹치는가 | **중단** — 기존 것을 확장하거나 빌트인을 쓴다 |
| Q2 | 향상된 모델 성능 덕에 이제 불필요한 것 아닌가 | **중단** |
| Q3 | 이미 잘 동작하는 것을 굳이 바꾸는 건 아닌가 | **중단** |

Q1의 "빌트인"은 실제로 확인한다. `/code-review`, `/simplify`, `/security-review`,
`skill-creator`, `/init`, `/run`, `/loop`은 Claude Code가 제공한다. **이들과 경쟁하는
자산을 만들지 않는다.**

## 해결 수단 우선순위

```
1. 기존 문서 수정 (1~3줄 추가)        ← 가장 선호
2. 기존 훅 로직 확장
3. 기존 스크립트에 기능 추가
4. 신규 스크립트 작성                  ← 가장 후순위
```

## 침묵 실패 방지 (필수)

새 훅·스크립트를 만들거나 고쳤으면 **아래를 실제로 실행**한다. 생략 불가.

1. `scripts/lib/common.sh`를 source하고 `epcc_begin`으로 시작한다
   (플러그인 밖 자체 훅이라면 이 lib에 의존하지 말고 같은 규율 — 루트 확정 실패 시 exit 2,
   숫자 검증, 이벤트별 출력 규격 — 을 자체 구현한다)
   — 루트는 `epcc_root()`로만 구한다. `BASH_SOURCE`, `dirname ../..` **금지**
   — 숫자는 `epcc_num()`을 통과시킨다. `|| echo 0` **금지**
2. 출력은 `epcc_emit_context` / `epcc_emit_block`으로만 한다
   — 이벤트마다 지원 필드가 다르다. 미지원 필드는 **조용히 무시**된다
   — Stop은 `decision`/`reason`을 지원하지 않는다 (`continue`+`systemMessage` 사용)
   — PreCompact/SessionEnd는 평문 stdout이 컨텍스트에 들어가지 않는다 (JSON 필요)
3. `bash "${CLAUDE_PLUGIN_ROOT:-.}/scripts/doctor.sh" --fast` + `--self-test` → 통과 확인
4. hooks.json에 등록했으면 `workflow.graph.json`에도 노드/엣지를 추가한다

## 도달 경로 검증

규칙·점검 장치를 추가할 때 **그 파일이 의도한 시점에 실제로 로드되는지** 즉시 확인한다.

- `paths:` 조건부 로딩이면 대상 파일의 paths가 실제 편집 경로를 포함하는가
- 플러그인에 넣는 자산이면 **Claude Code가 지원하는 컴포넌트 타입인가**
  (`skills`/`commands`/`agents`/`hooks`/`mcpServers`/`outputStyles`/`lspServers` — **`rules`는 없다**)
- 프로젝트에 있어야 하는 파일이면 `epcc-init`에 설치 단계가 있는가
- **프리셋/스택 분기가 있으면 모든 조합에서 도달하는가** — 보편 규범을 한 프리셋
  전용 스킬 안에 두지 않는다 (T1 카드가 보편 배포 수단이다). 사본 배포는 드리프트
  원천이므로 최후 수단 — 단일 정본 + 참조를 우선한다

> v2에서 규칙 697줄이 4개월간 아무 프로젝트에도 도달하지 못했다. 원인은 이 검증의 부재다.

## 자산 부재 판정 — 3-위치 검색

Agent·Skill·Hook·플러그인이 "없다"고 단정하려면 세 곳을 **모두** 확인한다:

1. 프로젝트 로컬 `.claude/`
2. 플러그인 캐시 `~/.claude/plugins/cache/`
3. 마켓플레이스 `~/.claude/plugins/marketplaces/`

한 곳만 보고 "없음"이라 결론내지 않는다. 특히 부재를 근거로 새 자산을 만들기 전에.

## 폐기 프로토콜 — Shadow 미러

**소비자 프로젝트의** `.claude/` 자산(규칙·스킬·훅 커스텀)을 폐기할 때 즉시 삭제하지 않는다.
`.claude/deprecated/`로 이동하고 만료일을 파일명에 새긴다 (기본 14일):

```
.claude/skills/foo/SKILL.md → .claude/deprecated/skills_foo_SKILL.md.shadow-expires-2026-09-03
```

만료까지 문제가 없으면 삭제 확정, 문제가 생기면 원위치 복구(롤백).
만료분은 `doctor --lessons`가 보고한다. 폐기 결정은 항상 사용자 승인을 거친다.

단, **플러그인 저장소 자체의 자산**은 git이 롤백을 보장하므로 shadow 없이 삭제한다 —
shadow는 되돌림 리마인더가 없는 소비자 프로젝트 커스텀용이다.

## 에이전트 예외

에이전트는 `.claude/rules/`를 상속받지 않는다. 에이전트에 필요한 규범은
**해당 에이전트 프롬프트에 직접** 기재한다. 규칙 파일로 대신하려 하지 않는다.
단 같은 규범을 두 곳이 주장하게 두지 않는다 — 한 곳이 원본이고 다른 곳은 인용이다.

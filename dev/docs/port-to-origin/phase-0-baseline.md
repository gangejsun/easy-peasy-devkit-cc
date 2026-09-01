# Phase 0 — 기준선 실측 + 플랫폼 계약 신설

> 이 프롬프트를 `~/Documents/easy-peasy-claudecode-devkit`에서 붙여넣는다.

---

이 저장소의 `.claude/` 하네스를 v3 설계로 전면 개편한다. 총 9단계이고 지금은 **0단계**다.
아직 하네스를 고치지 않는다 — **재기 위한 자를 먼저 만들고, 현재 값을 기록한다.**

## 왜 이것부터인가

개편 후 "좋아졌다"를 주장하려면 개편 전 숫자가 있어야 한다. 그리고 이 저장소의 하네스는
2026-05-20 이후 손대지 않았으므로, 무엇이 **살아는 있으나 작동하지 않는지** 아무도 모른다.
출처 저장소(easy-peasy-devkit-cc)에서 같은 구조의 훅 8개가 4개월간 죽은 채 아무 신호도
내지 않은 것이 확인됐다. 원인은 셋이었다:

1. 루트 경로를 `BASH_SOURCE` 상대로 계산 → 배포 시 저장소 밖을 가리킴
2. `|| echo 0` 폴백이 1줄 자리에 2줄을 넣어 정수 비교를 붕괴시킴
3. 이벤트가 지원하지 않는 JSON 필드로 출력 → **조용히 무시됨**

3번이 특히 중요하다. `Stop` 이벤트는 `decision`/`reason`을 지원하지 않는다.
이 저장소의 `.claude/hooks/stop-guard.sh`가 그 형식을 쓰고 있다면 **한 번도 차단한 적이 없다.**

## 할 일

### 1. 하네스 전수 인벤토리

`dev/docs/harness-evaluation/v0-baseline.md`에 아래를 기록한다. 추정하지 말고 실행해서 센다.

```bash
wc -l .claude/rules/*.md | sort -n
wc -l .claude/hooks/*.sh | sort -n
ls .claude/skills/ | wc -l
ls .claude/agents/
cat .claude/settings.json | python3 -c "import json,sys; h=json.load(sys.stdin)['hooks']; print({k: [c['command'] for e in v for c in e['hooks']] for k,v in h.items()})"
```

기록 형식:

| 자산 | 개수 | 총 줄수 | 비고 |
| --- | --- | --- | --- |
| `.claude/rules/` | | | `paths:` 없는 파일 목록을 함께 (= 매 세션 상시 로드) |
| `.claude/hooks/` | | | 이벤트별 배선 |
| `.claude/skills/` | | | |
| `.claude/agents/` | | | frontmatter의 `tools` 선언 유무 |

### 2. 상주 컨텍스트 비용 실측

매 세션 무조건 로드되는 것의 **문자 수**를 잰다. 이것이 개편 전후 비교의 핵심 지표다.

```bash
# CLAUDE.md
wc -c CLAUDE.md
# paths 없는 규칙 (= 상시 로드)
for f in .claude/rules/*.md; do head -1 "$f" | grep -q '^---' || wc -c "$f"; done
# 스킬 description 총합 (스킬은 호출하지 않아도 description이 전량 상주한다)
for f in .claude/skills/*/SKILL.md; do
  awk '/^description:/{f=1} f{print} /^---$/{if(f)exit}' "$f"
done | wc -c
```

세 값과 합계를 기록한다. 출처 저장소의 같은 시점 값은 **20,034자**였고 그중 71%가
스킬 description이었다 — 예산이 있는 곳(T0 40줄)과 비용이 몰린 곳이 어긋나 있었다.

### 3. 죽은 훅 색출 (이 단계의 핵심)

훅 11개에 **실제 stdin을 주입해서** 무슨 일이 일어나는지 본다. 코드를 읽는 것으로
대신하지 않는다 — 읽어서 멀쩡해 보이는 것이 실행하면 죽는다.

```bash
mkdir -p /tmp/epcc-baseline
echo '{"hook_event_name":"SessionStart","cwd":"'$PWD'"}'      > /tmp/epcc-baseline/SessionStart.json
echo '{"hook_event_name":"Stop","cwd":"'$PWD'","stop_hook_active":false}' > /tmp/epcc-baseline/Stop.json
echo '{"hook_event_name":"PreCompact","cwd":"'$PWD'"}'        > /tmp/epcc-baseline/PreCompact.json
echo '{"hook_event_name":"UserPromptSubmit","cwd":"'$PWD'","prompt":"test"}' > /tmp/epcc-baseline/UserPromptSubmit.json
echo '{"hook_event_name":"PreToolUse","cwd":"'$PWD'","tool_name":"Write","tool_input":{"file_path":"/tmp/x.ts","content":"const a=1"}}' > /tmp/epcc-baseline/PreToolUse.json
echo '{"hook_event_name":"PostToolUse","cwd":"'$PWD'","tool_name":"Edit","tool_input":{"file_path":"/tmp/x.ts"}}' > /tmp/epcc-baseline/PostToolUse.json

for h in .claude/hooks/*.sh; do
  # settings.json에서 이 훅이 걸린 이벤트를 찾아 해당 픽스처를 넣는다
  echo "── $h"
  bash "$h" < /tmp/epcc-baseline/<해당이벤트>.json; echo "  exit=$?"
done
```

각 훅에 대해 기록한다: **exit 코드 · stdout · stderr · 이벤트가 그 출력 형식을 지원하는가.**

판정 기준 (`docs/platform-contract.md`를 아래 4번에서 만든 뒤 대조):

- `SessionStart` / `UserPromptSubmit` / `UserPromptExpansion` — stdout 평문이 그대로 컨텍스트가 된다
- `PreCompact` / `SessionEnd` / `Stop` / `PostToolUse` — **평문은 컨텍스트에 들어가지 않는다.** `additionalContext` JSON이 필요하다
- `Stop` — `decision`/`reason` **미지원**. 차단은 `{"continue":false,"systemMessage":"…"}`
- `PreToolUse` — `hookSpecificOutput` 지원

**형식이 틀린 훅은 "작동 중"이 아니라 "조용히 무시되는 중"이다.** 그 목록이 이 단계의 산출이다.

### 4. `.claude/docs/platform-contract.md` 신설

플랫폼 동작을 기억으로 단정해서 생긴 결함이 출처 저장소에서 세 부류였다. 그것을 한 곳에
모으고 **출처 URL과 확인 날짜를 붙인다.** 이후 모든 단계가 이 파일을 근거로 삼는다.

각 절은 반드시 `확인: YYYY-MM-DD · 출처: <URL>` 로 시작한다. **전언·기억·"아마 그럴 것"은 넣지 않는다.**
아래 6절을 공식 문서로 **직접 확인해서** 채운다 (아래 값은 2026-08-24 기준 확인분이므로
날짜가 지났으면 재확인한다):

| 절 | 내용 | 출처 |
| --- | --- | --- |
| 1. 치환 변수 | `${CLAUDE_SKILL_DIR}`(모든 스킬) · `${CLAUDE_PLUGIN_ROOT}`(**플러그인 스킬만**) · `${CLAUDE_PROJECT_DIR}` · `${CLAUDE_PLUGIN_DATA}`. 치환되는 곳은 스킬 마크다운 본문과 `allowed-tools` frontmatter **두 곳뿐**. 자작 표기(`<skill-dir>` 등)는 아무것도 치환하지 않는다 | code.claude.com/docs/en/skills |
| 2. 플러그인 컴포넌트 자동 발견 | `skills`/`commands`/`agents`/`hooks`/`mcpServers`/`outputStyles`/`lspServers`. **`rules`는 컴포넌트 타입이 아니다** | code.claude.com/docs/en/plugins-reference |
| 3. `.claude/rules/` 로딩 | **네이티브 기능이다.** `paths:` 없음 → 매 세션 시작 시 무조건 로드(= `.claude/CLAUDE.md`와 동일 우선순위). `paths:` 있음 → 매칭 파일을 **읽을 때**. glob이며 중괄호 확장 지원. 사용자 수준 `~/.claude/rules/`가 프로젝트보다 먼저 로드된다 | code.claude.com/docs/en/memory |
| 4. `CLAUDE.md` 로딩 | 상위 디렉토리 전부 시작 시 로드 · 하위는 그 디렉토리 파일을 읽을 때 · **블록 HTML 주석은 주입 전에 제거된다**(유지자 메모용으로 안전) · 권고 200줄 미만 · **시스템 프롬프트가 아니라 사용자 메시지로 전달된다 = 강제가 아니라 맥락이다. 반드시 막아야 하는 것은 훅으로 만든다** | code.claude.com/docs/en/memory |
| 5. 훅 이벤트별 출력 규격 | 위 3번의 표를 근거와 함께 | code.claude.com/docs/en/hooks |
| 6. 서브에이전트 | **에이전트는 `.claude/rules/`를 상속받지 않는다** → 필요한 규범은 프롬프트에 직접 적는다. frontmatter의 `tools`·`disallowedTools`·`model`·`effort` | code.claude.com/docs/en/sub-agents |

파일 머리에 사용법을 적는다:

> 1. 플랫폼 동작을 주장하기 전에 여기를 본다.
> 2. 없으면 공식 문서를 확인하고 **출처 URL과 확인 날짜를 적어 추가한다.**
> 3. 틀린 것으로 드러나면 고치고 날짜를 갱신한다. 확인 날짜 180일 초과는 경고 대상이다 —
>    플랫폼은 움직인다.

### 5. `docs/lessons.md` 형식 점검

이후 단계의 되먹임 루프가 이 파일을 소비한다. 지금 형식이 아래와 다르면 **기록을 잃지 않는
선에서** 맞춘다 (기존 항목은 보존한다).

```markdown
## [category: <카테고리>] <교훈 제목>

- 날짜: YYYY-MM-DD
- 상황: 무엇을 하고 있었는가
- 실수: 무엇을 잘못했는가
- 교훈: 다음에 어떻게 다르게 할 것인가
```

카테고리는 구체적으로. `misc`·`general` 같은 넓은 카테고리는 집계를 무의미하게 만든다.

## 하지 말 것

- **아직 아무 훅·규칙도 고치지 않는다.** 3번에서 죽은 훅을 찾아도 지금 고치지 않는다 —
  고칠 자(doctor)가 1단계에서 생기고, 고치는 것은 2단계다. 지금 고치면 "고쳤다"를
  증명할 방법이 없다.
- 인벤토리를 추정으로 채우지 않는다. 명령을 실제로 돌린 출력만 적는다.
- `platform-contract.md`에 확인하지 않은 항목을 적지 않는다. 모르면 "미확인"으로 남긴다.

## 검증

```bash
test -f dev/docs/harness-evaluation/v0-baseline.md && echo OK
test -f .claude/docs/platform-contract.md && echo OK
grep -c '확인: 20' .claude/docs/platform-contract.md   # 6 이상
```

## 완료 기준 (DoD)

1. `v0-baseline.md`에 규칙·훅·스킬·에이전트 개수와 총 줄수가 **명령 출력 기반으로** 적혀 있다
2. 상주 컨텍스트 비용이 CLAUDE.md / 상시 규칙 / 스킬 description 3분할로 실측돼 있다
3. 훅 11개 각각의 exit 코드·출력·**형식 적합 여부**가 표로 있고, "조용히 무시되는 중"인
   훅 목록이 명시돼 있다
4. `.claude/docs/platform-contract.md`의 6개 절이 전부 출처 URL과 확인 날짜를 갖는다
5. 이 단계에서 `.claude/hooks/`·`.claude/rules/`의 **내용 변경은 0건**이다

---

**다음**: `phase-1-verification-base.md`

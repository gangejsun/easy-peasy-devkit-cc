---
name: completion-review
description: 코드 구현이 끝나고 문서를 최신화해야 할 때 사용합니다. context.md 업데이트, tasks.md 체크 완료, 관련 아키텍처/API 문서 갱신, 완료 작업 아카이브를 처리합니다. Reversible 변경의 마무리 담당이며 Costly 이상은 epcc-reviewer가 맡습니다.
---

# Completion Review

개발 완료 후 문서 최신화 및 아카이브를 수행하는 스킬입니다.

## 워크플로우

### Step 1: 작업 유형 확인 및 업데이트 범위 결정

| 작업 유형                | Step 2 (개발 문서)             | Step 3 (프로젝트 문서)              | Step 4 (아카이브) |
| ------------------------ | ------------------------------ | ----------------------------------- | ----------------- |
| 신규 기능 개발           | context + tasks 전체 업데이트  | PRD, CLAUDE.md, dev/docs/ 전체 확인 | 수행              |
| 기존 기능 확장/수정/삭제 | context + tasks 업데이트       | 변경된 부분의 관련 dev/docs/        | 수행              |
| 버그 수정                | tasks만 (dev docs가 있는 경우) | 최소 업데이트 (필요한 경우만)       | 생략 가능         |
| 리팩토링                 | context + tasks 업데이트       | 아키텍처 문서 중점 업데이트         | 수행              |

### Step 2: 개발 문서 업데이트

`dev/active/<feature-name>/` 의 문서를 업데이트합니다.

### Step 3: 프로젝트 문서 업데이트

구현 중 발생한 변경사항을 분석하고, 해당하는 문서를 업데이트합니다.

### Step 4: 아카이브

```bash
git mv dev/active/<feature-name> dev/archive/<feature-name>
```

### Step 4.5: 산출물 자체 검증

아카이브는 되돌리기 번거롭다(`git mv` 이후 경로가 바뀐다). 옮기기 **전에** 대조한다 —
하나라도 실패하면 아카이브하지 않고 그 항목을 보고한다:

- [ ] `tasks.md`의 미체크 항목이 0개이거나, 남은 항목마다 제외 사유가 적혀 있는가
- [ ] `context.md`의 SESSION PROGRESS가 **append**됐는가 (이전 세션 기록이 살아 있는가)
- [ ] Step 1 표가 지목한 프로젝트 문서가 실제로 갱신됐는가 (갱신 불필요면 그 판단이 적혀 있는가)
- [ ] 구현이 PRD와 달라진 지점이 있으면 사용자에게 보고됐는가 (자동 수정 금지)

```bash
grep -n '^- \[ \]' dev/active/<feature-name>/tasks.md   # 미체크 잔량
git diff --stat HEAD -- dev/docs/                        # 프로젝트 문서 갱신 실재
```

### Step 5: 사용자에게 완료 보고

네 줄로 낸다 — 이 스킬은 Reversible 변경의 마무리이므로 보고가 길면 그 자체가 비용이다.

```
갱신: <파일 N개> (개발 문서 N · 프로젝트 문서 N)
아카이브: dev/active/<name> → dev/archive/<name>   (또는: 생략 — 사유)
남은 것: <미체크 항목과 제외 사유, 없으면 "없음">
확인 필요: <PRD와 달라진 지점, 없으면 "없음">
```

「확인 필요」가 비어 있지 않으면 **거기서 멈추고 사용자의 선택을 받는다** —
구현과 PRD 중 무엇이 맞는지는 이 스킬이 정하지 않는다.

## Pitfalls

- PRD와 다른 구현 발견 시 자동 수정하지 말 것 — 반드시 사용자에게 보고 후 선택
- 아카이브 전 tasks.md 미체크 항목이 의도적 제외인지 누락인지 확인
- context.md SESSION PROGRESS 업데이트 시 이전 세션 기록을 덮어쓰지 말 것 — append 방식

---
name: web-asset-generator
description: 로고·텍스트·이모지로 웹 에셋을 생성합니다 — favicon 세트(16~512px, ICO), Apple Touch Icon, Android Chrome 아이콘, OG/소셜 카드 이미지, Next.js Metadata API 코드. "파비콘", "favicon", "OG 이미지", "소셜 카드", "og:image", "apple-touch-icon", "메타 이미지"에 사용합니다. 수동 호출 전용.
disable-model-invocation: true
---

# Web Asset Generator

로고/텍스트/이모지 → favicon + OG 이미지 → Next.js 통합 코드 제공.
생성 엔진은 **Pillow** 하나다 — 로컬에서 도형·텍스트를 그려 래스터화한다. 키도 네트워크도 쓰지 않는다.

## 워크플로우

### Step 1: 작업 유형 판별

| 키워드 | 유형 | 실행 |
|--------|------|------|
| "파비콘만" | favicon-only | generate_favicons.py |
| "OG 이미지만" | og-only | generate_og_images.py |
| "전체 에셋" | full | 둘 다 실행 |
| 명시 없음 | full | 기본값: 전체 생성 |

### Step 2: 사용자 인터뷰

소스 이미지, 브랜드 색상, 소스 유형(로고/이모지), OG 생성 방식(Pillow/AI) 수집.

### Step 3: 의존성 확인

`${CLAUDE_SKILL_DIR}`는 Claude Code가 치환한다 — 개인·프로젝트·플러그인 어디에 설치되어도 해석된다:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/check_dependencies.py
```

Pillow 부재(exit 2) 시 안내된 설치 명령을 사용자 확인 후 실행한다.

### Step 4: 파비콘 생성

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/generate_favicons.py <logo_path> public/ all --validate
```

### Step 5: OG/소셜 이미지 생성

**Pillow 모드** (오프라인 기본):

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/generate_og_images.py --title "<제목>" --out public/ \
  [--subtitle "<부제>"] [--logo <path>] [--bg "#0F172A"] [--fg "#FFFFFF"]
```

**AI로 배경·일러스트를 만들고 싶을 때**는 이 스킬이 하지 않는다 — `/image-generator`가
그 일을 한다(개발 하네스 쪽 스킬이다). 거기서 받은 이미지를 `--logo`·배경으로 넘겨 합성한다.
그 스킬이 보이지 않으면 위 Pillow 모드가 그대로 답이다(단색 배경 + 텍스트).

> 이전 판은 여기에 「Nano Banana 2 AI 모드」가 있다고 적어 두었지만 **구현이 없었다** —
> 스크립트도 인자도 키 확인 절차도 존재하지 않았다. 없는 기능을 있다고 적으면 모델이
> 그것을 부르려다 실패한다. 그래서 실물이 있는 곳을 가리키도록 고쳤다.

### Step 6: 검증 결과 확인

`--validate` 플래그로 파일 크기, 이미지 크기, 포맷 호환성, WCAG 대비비 검증.

### Step 7: Next.js Metadata API 통합 코드 제공

`references/specifications.md`의 "Next.js 15 Metadata API Integration" 섹션 참조.

### Step 8: 완료 요약

생성된 파일 목록, 검증 결과, 다음 단계 보고.

## 참조 문서

- 에셋 사양: [references/specifications.md](references/specifications.md)

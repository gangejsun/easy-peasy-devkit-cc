---
name: scroll-stop-builder
description: >
  비디오 파일을 받아 Apple 스타일의 스크롤 드리븐 애니메이션 웹사이트를 생성합니다.
  FFmpeg로 프레임을 추출하고, Canvas 기반 렌더링으로 스크롤에 따라 영상이 재생/역재생되는
  프리미엄 제품 소개 사이트를 구축합니다. 13개 섹션(starscape, loader, navbar, hero,
  scroll-animation, annotation cards, specs, features, CTA, testimonials, card-scanner, footer)을
  사용자 선택에 따라 조합합니다.
  사용자가 "스크롤 스톱 사이트", "스크롤 애니메이션 웹사이트", "비디오 스크롤 사이트",
  "Apple 스타일 스크롤", "scroll-stop build"를 요청할 때 사용합니다.
  marketing-workflow Stage 2로도 호출됩니다.
  AI 프롬프트 생성은 /scroll-stop-prompter. SEO 분석은 /seo-strategy. 전체 파이프라인은 /marketing-workflow.
  수동 호출 전용 (/scroll-stop-builder). 자동 트리거되지 않습니다. (project)
---

# Scroll-Stop Builder

비디오 파일 → 프레임 추출 → Canvas 스크롤 애니메이션 웹사이트 생성.

Apple 제품 페이지와 동일한 기법: 프레임 시퀀스를 Canvas에 그리며 스크롤 위치에 매핑.

## 전제 조건

- FFmpeg 설치 필수 (`brew install ffmpeg`)
- 비디오 3-10초, 첫 프레임 흰 배경 필수
- 로컬 서버 필요 (`file://`에서 프레임 로드 불가)

## 워크플로우

### Step 1: 작업 유형 판별

| 조건 | 모드 | 실행 Step |
|------|------|----------|
| marketing-workflow에서 호출 (prompts.md 존재) | pipeline | 2(부분) → 3 → 4 → 5 → 6 → 7 |
| 단독 호출 + URL 제공 | standalone-url | 2 → 3 → 4 → 5 → 6 |
| 단독 호출 + 콘텐츠 직접 제공 | standalone-manual | 2 → 3 → 4 → 5 → 6 |

### Step 2: 사용자 인터뷰

브랜드/제품명, 로고, 액센트 컬러, 배경 컬러, 분위기/바이브 수집. 섹션 토글 확인.

### Step 3: 비디오 분석 및 프레임 추출

```bash
bash .claude/skills/scroll-stop-builder/scripts/extract-frames.sh "<VIDEO_PATH>" "<OUTPUT_DIR>" [TARGET_FPS]
```

### Step 4: HTML 사이트 생성

단일 HTML 파일로 생성. 각 섹션 구현은 `references/sections-guide.md` 참조.

### Step 5: 디자인 시스템 적용

인터뷰 결과에서 폰트, 컬러, 카드 스타일, 버튼, 효과 구성.

### Step 6: 콘텐츠 적용 및 서빙

```bash
cd "<OUTPUT_DIR>" && python3 -m http.server 8080
```

### Step 7: 파이프라인 핸드오프 (pipeline 모드 전용)

`site.md`를 캠페인 디렉토리에 저장.

## 참조 문서

- 섹션 구현 가이드: [references/sections-guide.md](references/sections-guide.md) (~982줄, 13개 섹션별 HTML/CSS/JS)
- HTML 스캐폴드: [assets/html-template.html](assets/html-template.html)
- 프레임 추출 스크립트: [scripts/extract-frames.sh](scripts/extract-frames.sh)
- 파이프라인 연동: `.claude/skills/marketing-workflow/SKILL.md`

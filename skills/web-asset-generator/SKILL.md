---
name: web-asset-generator
description: 로고, 텍스트, 이모지로부터 웹 에셋(favicon, OG 이미지, 소셜 카드)을 생성합니다. favicon 세트(16~512px, ICO), Apple Touch Icon, Android Chrome 아이콘, Facebook/Twitter/LinkedIn용 OG 이미지를 자동 생성하고 Next.js Metadata API 코드를 제공합니다. OG 이미지는 Pillow(오프라인) 또는 Nano Banana 2(AI 고퀄리티) 중 선택 가능합니다. 사용자가 "파비콘", "favicon", "OG 이미지", "소셜 카드", "og:image", "apple-touch-icon", "사이트 아이콘", "소셜 미디어 이미지", "메타 이미지"를 요청할 때 사용합니다. 수동 호출 전용.
---

# Web Asset Generator

로고/텍스트/이모지 → favicon + OG 이미지 → Next.js 통합 코드 제공.
하이브리드 생성 엔진: **Pillow**(파비콘 전용) + **Nano Banana 2**(OG 이미지 선택적).

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

이 스킬 로드 시 표시되는 Base directory를 `<skill-dir>`로 치환해 실행한다:

```bash
python3 <skill-dir>/scripts/check_dependencies.py
```

Pillow 부재(exit 2) 시 안내된 설치 명령을 사용자 확인 후 실행한다.

### Step 4: 파비콘 생성

```bash
python3 <skill-dir>/scripts/generate_favicons.py <logo_path> public/ all --validate
```

### Step 5: OG/소셜 이미지 생성

**Pillow 모드** (오프라인 기본):

```bash
python3 <skill-dir>/scripts/generate_og_images.py --title "<제목>" --out public/ \
  [--subtitle "<부제>"] [--logo <path>] [--bg "#0F172A"] [--fg "#FFFFFF"]
```

**AI 모드** (Nano Banana 2): 사용자가 고품질을 원할 때만. API 키 확인 후 프롬프트 기반 생성.

### Step 6: 검증 결과 확인

`--validate` 플래그로 파일 크기, 이미지 크기, 포맷 호환성, WCAG 대비비 검증.

### Step 7: Next.js Metadata API 통합 코드 제공

`references/specifications.md`의 "Next.js 15 Metadata API Integration" 섹션 참조.

### Step 8: 완료 요약

생성된 파일 목록, 검증 결과, 다음 단계 보고.

## 참조 문서

- 에셋 사양: [references/specifications.md](references/specifications.md)

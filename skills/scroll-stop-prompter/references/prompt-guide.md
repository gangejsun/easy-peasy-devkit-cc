# Prompt A/B/C 상세 가이드

## Prompt A — Assembled Shot (조립뷰)

완성된 제품의 프리미엄 스튜디오 샷. 포함 요소:

- 카메라 앵글 (3/4 뷰, 정면 등)
- 조명 (스튜디오 3점 조명, 림 라이트 등)
- 배경 (그라데이션, 반사면 등)
- 소재 질감 묘사
- 해상도/종횡비 지시 (`--ar 16:9`, `--v 6` 등)

## Prompt B — Deconstructed Shot (분해뷰)

제품을 구성 요소별로 분해한 폭발도(exploded view). 포함 요소:

- 각 부품의 공간 배치
- 부품 간 간격과 정렬
- 개별 부품의 소재 질감
- 동일 조명 환경 유지

## Prompt C — Video Transition (비디오 전환)

분해 → 조립 또는 조립 → 분해 전환 애니메이션. 포함 요소:

- 전환 방향과 속도
- 카메라 무브먼트 (orbiting, push-in 등)
- 모션 블러/잔상 효과
- 루프 가능 여부
- 프레임 레이트 지시 (24fps)
- 길이 (3-5초)

## AI 모델 최적화 매핑

| 프롬프트 유형 | 추천 모델        | 모델별 접미사                          |
| ------------- | ---------------- | -------------------------------------- |
| A (이미지)    | Midjourney v6    | `--ar 16:9 --v 6 --style raw`          |
| A (이미지)    | DALL-E 3         | 프롬프트 시작에 "Photorealistic" 추가  |
| A (이미지)    | Stable Diffusion | negative prompt 포함                   |
| B (이미지)    | Midjourney v6    | `--ar 16:9 --v 6 --style raw`          |
| C (비디오)    | Runway Gen-3     | "Camera: [move], Duration: [sec]" 구조 |
| C (비디오)    | Kling            | 첫 문장에 모션 지시 집중               |
| C (비디오)    | Pika             | "Motion: [type]" 접두사                |

# Technical SEO Checklist

사이트 감사(Mode 2) 시 점검할 기술 SEO 항목.

## Crawlability & Indexability

- [ ] `robots.txt` 존재 및 유효성 확인
- [ ] `sitemap.xml` 존재 및 유효성
- [ ] Canonical URL 일관성
- [ ] 크롤 예산 최적화

## URL Structure

- [ ] 깔끔한 URL 구조 (파라미터 최소화)
- [ ] 키워드 포함 slug
- [ ] 깊이 3단계 이하
- [ ] 하이픈 사용, 소문자 일관성

## Redirects

- [ ] 301 리다이렉트 체인 없음 (최대 1홉)
- [ ] 리다이렉트 루프 없음

## HTTP/Security

- [ ] 전체 HTTPS 적용
- [ ] Mixed content 없음
- [ ] HSTS 헤더 설정

## Performance (Core Web Vitals)

- [ ] **LCP** < 2.5초
- [ ] **FID/INP** < 200ms
- [ ] **CLS** < 0.1

## Image Optimization

- [ ] 차세대 포맷 (WebP, AVIF) 사용
- [ ] lazy loading
- [ ] 모든 이미지에 descriptive alt 텍스트
- [ ] srcset/sizes 반응형 이미지

## Structured Data

- [ ] JSON-LD 형식 사용
- [ ] 해당 스키마 타입 적용 (Organization, Product, Article, FAQ 등)
- [ ] Google Rich Results Test 통과

## Server Configuration

- [ ] 서버 응답 시간 < 200ms
- [ ] Gzip/Brotli 압축 활성화
- [ ] 적절한 Cache-Control 헤더
- [ ] CDN 사용 (정적 에셋)

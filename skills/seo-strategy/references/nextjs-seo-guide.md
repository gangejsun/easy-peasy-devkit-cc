# Next.js App Router SEO Guide

Next.js 15 App Router 프로젝트에서의 SEO 최적화 패턴.

## Metadata API

### Static Metadata

```typescript
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Product Name - Tagline',
  description: '150-160자 이내 설명. CTA 포함 권장.',
  openGraph: { /* ... */ },
  twitter: { card: 'summary_large_image' },
  robots: { index: true, follow: true },
  alternates: { canonical: 'https://example.com' },
}
```

### Dynamic Metadata

```typescript
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params
  const product = await getProduct(slug)
  return {
    title: `${product.name} - Site Name`,
    description: product.description.slice(0, 160),
  }
}
```

## Sitemap (`app/sitemap.ts`)

## Robots (`app/robots.ts`)

## JSON-LD Structured Data

## OG Image Generation (`app/opengraph-image.tsx`)

## SEO Checklist for Next.js

- [ ] `generateMetadata()` 모든 동적 페이지에 구현
- [ ] `sitemap.ts` 자동 생성 설정
- [ ] `robots.ts` 크롤 규칙 정의
- [ ] JSON-LD 주요 페이지에 적용
- [ ] OG 이미지 동적 생성 또는 정적 파일 제공
- [ ] `next/image` 사용 (자동 최적화)
- [ ] `next/font` 사용 (FOIT/FOUT 방지)
- [ ] ISR/SSG 활용

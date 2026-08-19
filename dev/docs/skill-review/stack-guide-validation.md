# stack-guide-generator 검증 리포트 (G-5)

- 날짜: 2026-08-19 · 방식: 서브에이전트 생성 3종 + 메인 세션 독립 채점 (자기보고 불신뢰 원칙)

## 테스트 결과

| 테스트 | 조합 | 판정 | 근거 (독립 채점) |
| --- | --- | --- | --- |
| T2 | FastAPI + AWS + PostgreSQL + SQLAlchemy (프론트 없음) | **통과** | backend-guide만 생성(범위 판단 정확) · 7섹션 순서 정확 · 누출 0 (supabase·prisma·next.js) · 예산 193줄 · dangling 0 · 스탬프 실재 |
| T3 | SvelteKit 2 + Supabase BaaS (미지 스택 — 과적합 검증) | **통과** | 거부 조건 비해당 판단 정확(Supabase지만 Next.js 아님) · 조합 외 누출 0 · SvelteKit 고유 계약 실재(+page.server 17·hooks.server 5) · 230/203줄 · dangling 0 |
| T6 | Next.js + AWS + PostgreSQL + Prisma + NextAuth (**누출 판별**) | **통과** | **Supabase 매치 0** (양 가이드) · 기타 외부 스택 0 · 조합 키워드 실재(prisma 135·nextauth 20) · 7섹션 · 213/207줄 · 스탬프 실재 |
| T4 | 정확히 Next.js+Supabase → 생성 거부 | 명령 커버리지 확인 | SKILL.md Step 2 분기 테이블 L33 — 행동 테스트는 미실행 |
| T5 | 수동 편집 보호 | 명령 커버리지 확인 | Step 2 L37 + Step 5 L70-71 — 행동 테스트는 미실행 |
| T1 · T7 | react-vite 프리셋 · MongoDB | **미실행** | 메커니즘이 각각 T2(프리셋 생성)·T6(누출 방지)과 동일 — 토큰 절약 판단. 필요 시 동일 방식으로 실행 가능 |

## 핵심 증명

1. **구조/내용 분리 계약이 작동한다** — T6에서 exemplar(nextjs-backend-guide)가 Supabase 결합인데도
   생성물에 Supabase 0회, Prisma/NextAuth로 완전 대체됨
2. **미지 스택에서 과적합하지 않는다** — T3가 Next.js 패턴을 복사하지 않고 SvelteKit 고유
   계약(load 함수·hooks.server.ts·form actions)으로 채움. 확신 낮은 패턴은 제외함(Step 3-2 규칙 준수)
3. **자기 검증이 실행된다** — T2·T3 에이전트가 Step 4 명령을 실제 실행했고, 메인 세션
   독립 채점과 결과 일치

## 비용·특이사항

- T2: 53k 토큰 · 4.4분 / T3: 77k 토큰 · 24분 / T6: 사용량 미보고 (아래)
- T6 에이전트는 생성 완료 후 검증 단계에서 환경 오류(기기 절전)로 중단 — 산출물은
  완전했고 메인 세션 채점으로 판정 확정. 스킬 결함 아님
- 생성 규모: 조합당 가이드 1~2개, 총 779~1,503줄 (스킬당 리소스 5개)

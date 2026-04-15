---
name: brainstorming
description: Use when the user wants to explore an idea, compare approaches, or design a feature before implementation. Helps turn vague ideas into concrete designs through collaborative dialogue. Not needed for bug fixes, simple config changes, or tasks with already-clear requirements.
---

# Brainstorming Ideas Into Designs

## Overview

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions one at a time to refine the idea. Once you understand what you're building, present the design and get user approval.

<HARD-GATE>
Do NOT write any code or take any implementation action until you have presented a design and the user has approved it.
</HARD-GATE>

## Checklist

Complete these items in order:

1. **Explore project context** — check files, docs, recent commits
2. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
3. **Propose 2-3 approaches** — with trade-offs and your recommendation
4. **Present design** — in sections scaled to their complexity, get user approval after each section
5. **Hand off to next Phase** — brainstorming 결과를 CLAUDE.md 워크플로우의 다음 Phase로 전달

## The Process

**Understanding the idea:**

- Check out the current project state first (files, docs, recent commits)
- **원본 요구사항 기록**: 사용자의 최초 요청을 그대로 기록해둔다 (Before/After 비교용)
- Ask questions one at a time to refine the idea
- Only one question per message - if a topic needs more exploration, break it into multiple questions
- Focus on understanding: purpose, constraints, success criteria

**Diagnosing ambiguity (모호함 진단):**

질문 전에 사용자 요청의 모호함을 아래 6개 카테고리로 분류하고, 해당하는 항목부터 우선 질문한다:

| 카테고리               | 모호함 예시                | 가설 옵션 예시                        |
| ---------------------- | -------------------------- | ------------------------------------- |
| Scope (범위)           | "사용자"가 누구인지 불명확 | 전체 사용자 / 관리자만 / 특정 역할    |
| Behavior (동작)        | 실패 시 동작 미정의        | 조용히 실패 / 에러 표시 / 자동 재시도 |
| Interface (인터페이스) | 통신 방식 미정의           | REST API / GraphQL / WebSocket        |
| Data (데이터)          | 데이터 형식 미정의         | JSON / CSV / 둘 다                    |
| Constraints (제약)     | 성능 요구 미정의           | <100ms / <1s / 특별한 요구 없음       |
| Priority (우선순위)    | 중요도 불명확              | 필수(MVP) / 선호(v1.1) / 미래(v2)     |

**Hypotheses as Options (가설을 옵션으로 제시):**

열린 질문 대신 구체적 가설 옵션을 제시하여 사용자의 인지 부하를 줄인다:

- **BAD**: "어떤 인증 방식을 원하세요?" (사용자가 선택지를 떠올려야 함)
- **GOOD**: "인증 방식을 선택해주세요: (A) OAuth 소셜 로그인 — 구현 빠름 / (B) Email+Password — 완전 통제 / (C) Magic Link — 비밀번호 없음"
- 각 옵션에 1줄 트레이드오프 설명을 포함한다

**Exploring approaches:**

- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

**Presenting the design:**

- Once you believe you understand what you're building, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense

## Before/After Summary (명확화 비교)

설계 완료 후, handoff 전에 **명확화 전/후 비교표**를 생성하여 사용자에게 보여준다.

## After the Design

설계 승인 후, 다음 Phase로 진행:

| 호출 상황                                   | 전환 대상                                                 |
| ------------------------------------------- | --------------------------------------------------------- |
| P0 파이프라인 진행 중 (planning-agent 경유) | planning-agent에게 설계 요약을 반환 → P0-B(Research) 진행 |
| 단독 호출 — 신규 기능 (Large)               | P1(프롬프트 강화) → P2(PRD) → P3(개발 문서) 흐름 진행     |
| 단독 호출 — 신규 기능 (Medium)              | P1(프롬프트 강화) → P4(구현) 흐름 진행                    |
| 단독 호출 — 기존 기능 확장                  | 개발 문서 생성(P3)으로 전환                               |

### 단독 호출 시 산출물 저장

단독 호출(`/brainstorming`)인 경우, 설계 승인 후 저장 여부를 사용자에게 확인.

### P0 파이프라인 연결 시 산출물

planning-agent 경유 시, 설계 결과를 **구조화된 요약**으로 반환.

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Hypotheses as Options** - 열린 질문 대신 구체적 가설 옵션을 제시. 각 옵션에 트레이드오프 1줄 포함
- **Diagnose before asking** - 질문 전에 모호함 카테고리(Scope/Behavior/Interface/Data/Constraints/Priority)로 분류
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design, get approval before moving on
- **Before/After tracking** - 원본 요구사항 기록 → 완료 시 명확화 비교표 생성
- **Be flexible** - Go back and clarify when something doesn't make sense

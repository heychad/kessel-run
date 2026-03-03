# Ralph Wiggum: The AI Development Loop Technique

> Source: https://ghuntley.com/ralph/
> Author: Geoffrey Huntley
> Fetched: 2026-03-01

---

## Core Concept

"Ralph is a technique. In its purest form, Ralph is a Bash loop."

```bash
while :; do cat PROMPT.md | claude-code ; done
```

Ralph is an autonomous development pattern where an AI agent iteratively builds software through continuous loops, receiving feedback and self-correcting based on test results and code review.

## Key Principles

**One Item Per Loop**
The fundamental rule is implementing a single task per iteration. This conserves context window (~170k tokens) and prevents rabbit-holing. Broadening scope only after establishing stability.

**Deterministic Stack Allocation**
Every loop maintains consistent inputs:
- A `@fix_plan.md` (prioritized todo list)
- Specification files (`@specs/`)
- Project standards and libraries

**Monolithic, Not Microservices**
Ralph operates as a single autonomous process in one repository, avoiding inter-agent communication complexity. This is vertical scaling, not distributed systems.

## The Three Phases

### Phase One: Generation
Code generation is now inexpensive. Control quality through:
- Technical standard libraries defining acceptable patterns
- Detailed specifications guiding implementation
- Updating stdlib when Ralph generates incorrect patterns

### Phase Two: Backpressure
Ensure Ralph generates *correct* code through:
- Automated testing (especially unit tests)
- Static analysis for dynamically typed languages
- Type checking in compiled languages
- Security scanning or custom validators

The wheel speed matters more than perfection — fast iteration beats slow correctness.

### Phase Three: Feedback Loops
Ralph self-improves by:
- Searching the codebase before implementing (avoiding duplicates)
- Running tests immediately after changes
- Capturing test importance in documentation
- Updating `@AGENT.md` with discovered command sequences

## Critical Prompting Techniques

**"Don't Assume It's Not Implemented"**
Common failure: ripgrep returns false negatives. Instruct Ralph to search thoroughly before coding:

> "Before making changes search codebase (don't assume not implemented) using parallel subagents. Think hard."

**Capture Test Reasoning**
Future loops lose context. Document *why* tests matter:

> "Important: When authoring documentation capture the why tests and backing implementation is important."

**No Placeholder Implementations**
Combat models' tendency toward minimal code:

> "DO NOT IMPLEMENT PLACEHOLDER IMPLEMENTATIONS. WE WANT FULL IMPLEMENTATIONS."

## Subagent Strategy

- Use up to 500 parallel subagents for searching, reading, and writing
- Restrict to **1 subagent only** for builds and tests (prevents backpressure saturation)
- This prevents overwhelming feedback channels

## The TODO List as Living Document

`@fix_plan.md` is the nervous system:
- Dynamically created/destroyed based on project state
- Periodically regenerated when Ralph stalls
- Tracks completed items and discovered bugs
- Sorted by implementation priority
- Updated after each successful loop

Huntley reports deleting and regenerating this file multiple times during CURSED (the new programming language being built via Ralph).

## Real-World Results

A Y Combinator engineer reportedly completed a $50,000 contract deliverable for $297 using Ralph — demonstrating 168x cost reduction on greenfield projects.

One field report: "We Put a Coding Agent in a While Loop and It Shipped 6 Repos Overnight"

## Failure Modes & Recovery

**When Ralph Breaks the Build**
Three options:
1. `git reset --hard` and restart the loop
2. Craft recovery prompts to rescue progress
3. Use alternative models (Huntley used Gemini for compilation error analysis when context filled)

**When Ralph Goes Off Track**
Tune the signs (prompts):
- Add guardrails like "SLIDE DOWN, DON'T JUMP, LOOK AROUND"
- Ralph learns from repeated correction
- Each loop is opportunity to adjust guidance

## Context Window Economics

Advertised vs. real context: Claude's 200k window exhibits quality degradation around 147-152k. Strategy:

- Allocate sparingly to primary context
- Offload expensive operations (summarization, analysis) to subagents
- Reuse specifications efficiently across loops

## Project-Specific Features

**For Compilers (CURSED Example)**
- Standard library must be authored in the target language itself, not the implementation language
- Migrate rust stdlib implementations to self-hosted versions
- Tests must live alongside stdlib source code
- Documentation explains both implementation *and why* it matters

**For General Projects**
- Enforce single sources of truth (no migrations/adapters)
- Fix unrelated failing tests as part of incremental changes
- Tag releases automatically when tests pass

## Maintainability Philosophy

Huntley reframes the question: "By whom?" Rather than assuming human maintenance, he suggests leveraging more Ralph loops to adapt code when needed. This shifts from static code quality to dynamic problem-solving capability.

However, he emphasizes: "Engineers are still needed. Anyone claiming tools do 100% without senior expertise is peddling nonsense."

## Current CURSED Build Prompt

The production prompt includes 31+ numbered instructions, prioritizing:
- Studying specs before implementation
- Following fix_plan.md sequentially
- Running tests immediately after changes
- Maintaining AGENT.md documentation
- Preventing placeholder code
- Cleaning completed tasks from tracking

## Broader Implications

Ralph demonstrates that agentic loops can:
- Build entire programming languages with no training data
- Replace most outsourced greenfield development
- Achieve 90% project completion before human refinement
- Operate without explicit central planning

The pattern is deterministically bad in unpredictable ways, but corrections compound across loops — eventually producing production-grade results.

**Key insight:** "Any problem created by AI can be resolved through a different series of prompts and running more loops with Ralph."

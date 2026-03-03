# Effective Harnesses for Long-Running Agents — Anthropic Engineering

> Source: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
> Fetched: 2026-03-01

---

## Core Problem

Long-running agents face a fundamental constraint: they operate in discrete sessions without memory between contexts. "Each new session begins with no memory of what came before." This creates continuity challenges when complex projects span multiple context windows.

## Key Failure Modes

Two primary failure patterns identified:

1. **Over-ambition**: Agents attempt to complete too much simultaneously, running out of context mid-implementation and leaving features undocumented.

2. **Premature completion**: After partial progress, agents declare projects finished without completing all requirements.

## Two-Part Solution

### Initializer Agent
The first session establishes foundational infrastructure:
- `init.sh` script for environment setup
- `claude-progress.txt` logging file tracking agent actions
- Initial git repository with baseline commits

### Coding Agent
Subsequent sessions follow a structured approach:
- Read progress logs and git history to understand prior work
- Select one feature to implement incrementally
- Commit changes with descriptive messages
- Update progress documentation

## Environment Management Strategy

**Feature List Implementation**: The initializer creates a JSON file containing 200+ feature specifications marked as failing initially. This provides explicit guidance preventing premature project closure.

**Incremental Progress**: Rather than implementing broadly, agents tackle individual features sequentially, committing after each change.

**Testing Requirements**: Agents use browser automation tools (Puppeteer MCP) for end-to-end verification rather than relying solely on unit tests.

## Session Startup Sequence

Each coding agent begins with deliberate groundwork:
1. Execute `pwd` to confirm working directory
2. Review git logs and progress files
3. Select highest-priority incomplete feature
4. Verify existing functionality via basic smoke tests
5. Only then commence new feature development

## Failure Mode Solutions

| Problem | Initializer Response | Coding Agent Response |
|---------|---------------------|----------------------|
| Declares victory prematurely | Comprehensive JSON feature list | Reads feature list; works one feature |
| Leaves buggy state | Git repo + progress file | Basic testing first; commits + updates |
| Marks incomplete work done | Feature tracking file | Tests thoroughly before marking complete |
| Unclear startup steps | `init.sh` script provided | Executes standardized startup routine |

## Key Patterns for Ralph

Several patterns from this research directly inform the Ralph loop:

1. **JSON feature list with passes/fails** — PRD.json follows this exact pattern. JSON is harder for models to accidentally modify than markdown.

2. **One feature per session** — Ralph's "one objective per context window" rule.

3. **Progress log** — PROGRESS.md serves the same role as `claude-progress.txt`, carrying learnings across iterations.

4. **Git commit per feature** — Every successful Ralph iteration commits, creating rollback points.

5. **Startup sequence** — Ralph's deterministic stack allocation (read spec, read progress, read git log, then work).

6. **Preventing premature completion** — The `<promise>COMPLETE</promise>` signal only fires when ALL PRD items pass.

## Future Directions

Open questions:
- Whether specialized agents (testing, QA, cleanup) would outperform single general-purpose agents
- How these principles extend beyond web development to scientific research or financial modeling

## Key Insight

The solution draws inspiration from human software engineering practices. By implementing structured handoffs comparable to shift-based team workflows, agents can maintain coherent progress across fragmented sessions.

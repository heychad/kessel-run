# Claude Code Agent Teams — Official Documentation

> Source: https://code.claude.com/docs/en/agent-teams
> Fetched: 2026-03-01

---

> **Warning**: Agent teams are experimental and disabled by default. Enable by adding `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` to settings.json or environment.

Agent teams let you coordinate multiple Claude Code instances working together. One session acts as the team lead, coordinating work, assigning tasks, and synthesizing results. Teammates work independently, each in its own context window, and communicate directly with each other.

Unlike subagents, which run within a single session and can only report back to the main agent, you can also interact with individual teammates directly without going through the lead.

## When to Use Agent Teams

Best use cases:
- **Research and review**: multiple teammates investigate different aspects simultaneously, share and challenge findings
- **New modules or features**: teammates each own a separate piece without stepping on each other
- **Debugging with competing hypotheses**: teammates test different theories in parallel
- **Cross-layer coordination**: changes spanning frontend, backend, and tests

Agent teams add coordination overhead and use significantly more tokens. For sequential tasks, same-file edits, or work with many dependencies, a single session or subagents are more effective.

## Subagents vs Agent Teams

|                   | Subagents                                        | Agent teams                                         |
| :---------------- | :----------------------------------------------- | :-------------------------------------------------- |
| **Context**       | Own context window; results return to the caller | Own context window; fully independent               |
| **Communication** | Report results back to the main agent only       | Teammates message each other directly               |
| **Coordination**  | Main agent manages all work                      | Shared task list with self-coordination             |
| **Best for**      | Focused tasks where only the result matters      | Complex work requiring discussion and collaboration |
| **Token cost**    | Lower: results summarized back to main context   | Higher: each teammate is a separate Claude instance |

Use subagents when you need quick, focused workers that report back. Use agent teams when teammates need to share findings, challenge each other, and coordinate on their own.

## Enable Agent Teams

```json
// settings.json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

## Starting a Team

Tell Claude to create an agent team and describe the task and team structure in natural language:

```
I'm designing a CLI tool that helps developers track TODO comments across
their codebase. Create an agent team to explore this from different angles: one
teammate on UX, one on technical architecture, one playing devil's advocate.
```

Claude creates a team with a shared task list, spawns teammates, has them explore, synthesizes findings, and cleans up when finished.

## Display Modes

- **In-process**: all teammates run inside your main terminal. Use Shift+Down to cycle through teammates. Works in any terminal.
- **Split panes**: each teammate gets its own pane. Requires tmux or iTerm2.

```json
// settings.json
{
  "teammateMode": "in-process"  // or "tmux" or "auto"
}
```

## Controlling Teams

### Specify teammates and models
```
Create a team with 4 teammates to refactor these modules in parallel.
Use Sonnet for each teammate.
```

### Require plan approval
```
Spawn an architect teammate to refactor the authentication module.
Require plan approval before they make any changes.
```

### Talk to teammates directly
- **In-process mode**: Shift+Down to cycle, type to message. Press Enter to view, Escape to interrupt. Ctrl+T toggles task list.
- **Split-pane mode**: click into pane.

### Task assignment
Lead creates tasks, teammates work through them. Three states: pending, in progress, completed. Tasks can depend on other tasks.
- **Lead assigns**: tell lead which task goes to which teammate
- **Self-claim**: after finishing, teammate picks next unassigned, unblocked task

### Shutdown
```
Ask the researcher teammate to shut down
```
Lead sends shutdown request. Teammate can approve (exit) or reject.

### Cleanup
```
Clean up the team
```
Removes shared team resources. Shut down teammates first.

## Architecture

| Component     | Role                                                                                       |
| :------------ | :----------------------------------------------------------------------------------------- |
| **Team lead** | Main session that creates team, spawns teammates, coordinates work |
| **Teammates** | Separate Claude Code instances working on assigned tasks                            |
| **Task list** | Shared list of work items (`~/.claude/tasks/{team-name}/`)                                |
| **Mailbox**   | Messaging system for inter-agent communication                                          |

Team config: `~/.claude/teams/{team-name}/config.json`
Task list: `~/.claude/tasks/{team-name}/`

### Permissions
Teammates start with lead's permission settings. If lead uses `--dangerously-skip-permissions`, all teammates do too.

### Context and communication
Each teammate has its own context window. Loads same project context (CLAUDE.md, MCP servers, skills) plus spawn prompt. Lead's conversation history does NOT carry over.

**Communication:**
- **Automatic message delivery**: messages delivered automatically to recipients
- **Idle notifications**: teammates notify lead when they finish
- **Shared task list**: all agents see task status and claim work
- **message**: send to one specific teammate
- **broadcast**: send to all (use sparingly — costs scale with team size)

## Best Practices

### Give teammates enough context
Include task-specific details in spawn prompt (they don't inherit lead's conversation history).

### Team size
Start with 3-5 teammates. 5-6 tasks per teammate keeps everyone productive. Three focused teammates often outperform five scattered ones.

### Size tasks appropriately
- **Too small**: coordination overhead exceeds benefit
- **Too large**: teammates work too long without check-ins
- **Just right**: self-contained units that produce a clear deliverable

### Wait for teammates to finish
If lead starts implementing instead of waiting: "Wait for your teammates to complete their tasks before proceeding"

### Avoid file conflicts
Break work so each teammate owns different files.

### Monitor and steer
Check in on progress, redirect approaches, synthesize findings. Don't let team run unattended too long.

## Quality Gates with Hooks

- `TeammateIdle`: runs when teammate is about to go idle. Exit code 2 sends feedback and keeps teammate working.
- `TaskCompleted`: runs when task is being marked complete. Exit code 2 prevents completion and sends feedback.

## Limitations

- No session resumption with in-process teammates (`/resume` and `/rewind` don't restore)
- Task status can lag (teammates sometimes fail to mark tasks completed)
- Shutdown can be slow (teammates finish current request first)
- One team per session
- No nested teams (teammates can't spawn their own teams)
- Lead is fixed (can't promote teammate to lead)
- Permissions set at spawn (all teammates start with lead's mode)
- Split panes require tmux or iTerm2

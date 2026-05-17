# grind

Iterative AI coding loop: one agent works, another reviews, repeat until clean.

Both worker and reviewer maintain persistent sessions across iterations, accumulating context so each round builds on the previous.

## How it works

1. **Worker** works on the task
2. **Reviewer** reviews the changes
3. If issues found, feed review back to worker, repeat
4. If `ALL_GOOD`, stop

Loop runs until the reviewer has no more issues.

## Supported agents

Only Claude Code and OpenAI Codex are supported. Both support persistent session resumption which is core to how grind works.

## Install

```bash
echo 'source ~/grind.zsh' >> ~/.zshrc
source ~/grind.zsh
```

## Usage

```bash
grind "Add input validation to the signup form"
grind "Fix the race condition" "Focus only on performance and thread safety."
grind "" "Ensure there are no security vulnerabilities."
```

- First argument: task description (empty string for review-only mode)
- Second argument: custom review prompt (optional, termination instruction is always appended)

## Mode flags

Pick the agent combination with a single flag (c=Claude, x=Codex, first=worker, second=reviewer):

```bash
grind --cx "Add rate limiting"    # Claude works, Codex reviews (default)
grind --xc "Add rate limiting"    # Codex works, Claude reviews
grind --cc "Add rate limiting"    # Claude works, Claude reviews
grind --xx "Add rate limiting"    # Codex works, Codex reviews
```

## Configuration

Override agents via environment variables (used when no mode flag is passed):

```bash
GRIND_WORKER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p"
GRIND_REVIEWER="codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -o /tmp/grind_review_$$.out"
GRIND_REVIEW_PROMPT="Review the code changes in this repository. Ensure there are no bugs and the solution is elegant and simple."
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [OpenAI Codex CLI](https://github.com/openai/codex)

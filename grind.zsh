#!/usr/bin/env zsh

# grind: iterative AI coding loop (doer works, reviewer checks, repeat until clean)
#
# Both doer and reviewer maintain persistent sessions across iterations,
# accumulating context so each round builds on the previous.
#
# Usage:
#   grind "task description" ["review prompt"]
#   grind "" "review prompt"    (review-only mode, no initial task)
#
# Examples:
#   grind "Add input validation to the signup form"
#   grind "Refactor the database layer" "Focus on thread safety and error handling."
#
# Supported agents (use as GRIND_DOER or GRIND_REVIEWER):
#   Claude:    claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p
#   Codex:     codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox
#   OpenCode:  opencode -p
#   Gemini:    gemini -m gemini-2.5-pro --approval-mode=yolo -p
#   Crush:     crush --yolo run -q -m anthropic/claude-sonnet-4 --
#   Oh My Pi:  omp --slow -p
#   Pi:        pi --model anthropic/claude-sonnet-4 --thinking high -p
#   Trae:      trae-cli run
#   Cursor:    cursor-agent --yolo --model claude-sonnet-4-6 --print
#   Cline:     cline --yolo
#   Qoder:     qodercli -p
#   Droid:     droid exec --auto high --model gpt-5.5
#   Kilocode:  kilo run --auto --model anthropic/claude-sonnet-4-6
#   Goose:     goose run --text
#
# Override for a single run:
#   GRIND_DOER="gemini -m gemini-2.5-pro --approval-mode=yolo -p" \
#   GRIND_REVIEWER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort high -p" \
#   grind "Fix the race condition in the worker pool"
#
# Or export to change defaults for the session:
#   export GRIND_DOER="codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox"
#   export GRIND_REVIEWER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort high -p"
#   grind "Implement retry logic for the HTTP client"

# Configuration: override these before calling grind()
GRIND_DOER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p"
GRIND_REVIEWER="codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -o /tmp/grind_review.out"
GRIND_REVIEW_PROMPT="Review the code changes in this repository. Ensure there are no bugs and the solution is elegant and simple."

_grind_run() {
  local agent_cmd="$1"
  local prompt="$2"
  local session_id="$3"
  local output_file="$4"

  if [[ "$agent_cmd" == claude* ]]; then
    if [[ -n "$session_id" ]]; then
      eval "$agent_cmd" '--resume "$session_id" --output-format json' '"$prompt"' < /dev/null 2>/dev/null
    else
      eval "$agent_cmd" '--output-format json' '"$prompt"' < /dev/null 2>/dev/null
    fi
  elif [[ "$agent_cmd" == codex* ]]; then
    local codex_flags=$(echo "$agent_cmd" | sed 's/^codex exec//')
    if [[ -n "$session_id" ]]; then
      eval "codex exec resume \"$session_id\" \"$prompt\" $codex_flags" < /dev/null 2>/tmp/grind_codex_stderr.txt
    else
      eval "$agent_cmd" '"$prompt"' < /dev/null 2>/tmp/grind_codex_stderr.txt
    fi
    cat /tmp/grind_codex_stderr.txt
  else
    eval "$agent_cmd" '"$prompt"' < /dev/null 2>/dev/null
  fi
}

_grind_parse_output() {
  local raw="$1"
  local agent_cmd="$2"

  if [[ "$agent_cmd" == claude* ]]; then
    echo "$raw" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "$raw"
  elif [[ "$agent_cmd" == codex* ]]; then
    if [[ -f /tmp/grind_review.out ]]; then
      cat /tmp/grind_review.out
    else
      echo "$raw" | sed -n '/^codex$/,/^tokens used$/{ /^codex$/d; /^tokens used$/d; p; }'
    fi
  else
    echo "$raw"
  fi
}

_grind_parse_session() {
  local raw="$1"
  local agent_cmd="$2"

  if [[ "$agent_cmd" == claude* ]]; then
    echo "$raw" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null
  elif [[ "$agent_cmd" == codex* ]]; then
    echo "$raw" | grep -o 'session id: [^ ]*' | head -1 | awk '{print $3}'
  fi
}

grind() {
  local task="$1"
  local review_prompt="${2:-$GRIND_REVIEW_PROMPT}"
  local iteration=0
  local review_output=""
  local doer_session=""
  local reviewer_session=""

  if [[ -z "$task" && -z "$review_prompt" ]]; then
    echo "Usage: grind \"task description\" [\"review prompt\"]"
    echo "       grind \"\" \"review prompt\"    (review-only mode, no initial task)"
    echo ""
    echo "Configure agents via:"
    echo "  GRIND_DOER=\"claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p\""
    echo "  GRIND_REVIEWER=\"codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox\""
    return 1
  fi

  echo "═══ grind: starting ═══"
  echo "Task: $task"
  echo "Doer: $GRIND_DOER"
  echo "Reviewer: $GRIND_REVIEWER"
  echo ""

  while true; do
    (( iteration++ ))
    echo "─── iteration $iteration ───"

    # WORK (skip on first iteration if no task)
    if [[ -n "$task" || -n "$review_output" ]]; then
      echo "[work] doer..."
      local work_prompt=""
      if [[ -z "$review_output" ]]; then
        work_prompt="$task"
      elif [[ -n "$doer_session" ]]; then
        work_prompt="The reviewer found these issues:

$review_output

Fix all the issues above."
      elif [[ -n "$task" ]]; then
        work_prompt="Original task: $task

The reviewer found these issues with your previous work:

$review_output

Fix all the issues above."
      else
        work_prompt="The reviewer found these issues with your previous work:

$review_output

Fix all the issues above."
      fi

      local doer_raw=""
      doer_raw=$(_grind_run "$GRIND_DOER" "$work_prompt" "$doer_session")
      if [[ -z "$doer_session" ]]; then
        doer_session=$(_grind_parse_session "$doer_raw" "$GRIND_DOER")
        [[ -n "$doer_session" ]] && echo "[work] session: $doer_session"
      fi
      local doer_result=""
      doer_result=$(_grind_parse_output "$doer_raw" "$GRIND_DOER")
      echo "$doer_result"
      echo "[work] done"
    fi

    # REVIEW
    echo "[review] reviewer..."
    local full_review_prompt=""
    if [[ -n "$task" && -z "$reviewer_session" ]]; then
      full_review_prompt="The task was: $task

"
    fi
    if [[ -n "$reviewer_session" ]]; then
      full_review_prompt+="Review the latest changes.

"
    fi
    full_review_prompt+="$review_prompt

If there are no issues and the code is correct and complete, respond with exactly: ALL_GOOD
Otherwise, list the issues that need to be fixed."

    rm -f /tmp/grind_review.out
    local reviewer_raw=""
    reviewer_raw=$(_grind_run "$GRIND_REVIEWER" "$full_review_prompt" "$reviewer_session")
    if [[ -z "$reviewer_session" ]]; then
      reviewer_session=$(_grind_parse_session "$reviewer_raw" "$GRIND_REVIEWER")
      [[ -n "$reviewer_session" ]] && echo "[review] session: $reviewer_session"
    fi
    review_output=$(_grind_parse_output "$reviewer_raw" "$GRIND_REVIEWER")
    echo "[review] done"

    # GATE
    if [[ -z "$review_output" ]]; then
      echo "[gate] reviewer returned empty output, treating as ALL_GOOD"
      echo ""
      echo "═══ grind: DONE after $iteration iteration(s) ═══"
      return 0
    fi

    if echo "$review_output" | grep -q "ALL_GOOD"; then
      echo ""
      echo "═══ grind: DONE after $iteration iteration(s) ═══"
      return 0
    fi

    echo ""
    echo "[review output]"
    echo "$review_output"
    echo ""
    echo "[gate] issues found, iterating..."
    echo ""
  done
}

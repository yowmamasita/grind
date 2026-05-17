#!/usr/bin/env zsh

# grind: iterative AI coding loop (worker works, reviewer checks, repeat until clean)
#
# Both worker and reviewer maintain persistent sessions across iterations,
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
# Supported agents (set as GRIND_WORKER or GRIND_REVIEWER):
#   Claude:  claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p
#   Codex:   codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox
#
# Mode flags (c=Claude, x=Codex, first=worker, second=reviewer):
#   grind --cc "task"   Claude works, Claude reviews
#   grind --cx "task"   Claude works, Codex reviews (default)
#   grind --xc "task"   Codex works, Claude reviews
#   grind --xx "task"   Codex works, Codex reviews

# Configuration: override these before calling grind()
GRIND_WORKER="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p"
GRIND_REVIEWER="codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -o /tmp/grind_review_$$.out"
GRIND_REVIEW_PROMPT="Review the code changes in this repository. Ensure there are no bugs and the solution is elegant and simple."

_grind_run() {
  local agent_cmd="$1"
  local prompt="$2"
  local session_id="$3"

  if [[ "$agent_cmd" == claude* ]]; then
    if [[ -n "$session_id" ]]; then
      eval "$agent_cmd" '--resume "$session_id" --output-format json' '"$prompt"' < /dev/null 2>/dev/null
    else
      eval "$agent_cmd" '--output-format json' '"$prompt"' < /dev/null 2>/dev/null
    fi
  elif [[ "$agent_cmd" == codex* ]]; then
    local codex_flags=$(echo "$agent_cmd" | sed 's/^codex exec//')
    if [[ -n "$session_id" ]]; then
      eval "codex exec resume \"$session_id\" \"$prompt\" $codex_flags" < /dev/null 2>/tmp/grind_codex_stderr_$$.txt
    else
      eval "$agent_cmd" '"$prompt"' < /dev/null 2>/tmp/grind_codex_stderr_$$.txt
    fi
    cat /tmp/grind_codex_stderr_$$.txt
  fi
}

_grind_parse_output() {
  local raw="$1"
  local agent_cmd="$2"
  local role="$3"

  if [[ "$agent_cmd" == claude* ]]; then
    echo "$raw" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "$raw"
  elif [[ "$agent_cmd" == codex* ]]; then
    if [[ "$role" == "reviewer" && -f /tmp/grind_review_$$.out ]]; then
      cat /tmp/grind_review_$$.out
    else
      echo "$raw" | sed -n '/^codex$/,/^tokens used$/{ /^codex$/d; /^tokens used$/d; p; }'
    fi
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
  local mode=""
  if [[ "$1" == --* ]]; then
    mode="$1"
    shift
  fi

  local task="$1"
  local review_prompt="${2:-$GRIND_REVIEW_PROMPT}"
  local iteration=0
  local review_output=""
  local worker_session=""
  local reviewer_session=""

  local claude_cmd="claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p"
  local codex_cmd="codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox -o /tmp/grind_review_$$.out"

  local active_worker="$GRIND_WORKER"
  local active_reviewer="$GRIND_REVIEWER"
  case "$mode" in
    --cc) active_worker="$claude_cmd"; active_reviewer="$claude_cmd" ;;
    --cx) active_worker="$claude_cmd"; active_reviewer="$codex_cmd" ;;
    --xc) active_worker="$codex_cmd"; active_reviewer="$claude_cmd" ;;
    --xx) active_worker="$codex_cmd"; active_reviewer="$codex_cmd" ;;
  esac

  if [[ -z "$task" && -z "$review_prompt" ]]; then
    echo "Usage: grind [--cc|--cx|--xc|--xx] \"task description\" [\"review prompt\"]"
    echo "       grind \"\" \"review prompt\"    (review-only mode, no initial task)"
    echo ""
    echo "Modes (c=Claude, x=Codex, first=worker, second=reviewer):"
    echo "  --cc  Claude works, Claude reviews"
    echo "  --cx  Claude works, Codex reviews (default)"
    echo "  --xc  Codex works, Claude reviews"
    echo "  --xx  Codex works, Codex reviews"
    echo ""
    echo "Configure agents via:"
    echo "  GRIND_WORKER=\"claude --dangerously-skip-permissions --model claude-opus-4-6 --effort medium -p\""
    echo "  GRIND_REVIEWER=\"codex exec -m gpt-5.5 -c model_reasoning_effort=high --dangerously-bypass-approvals-and-sandbox\""
    return 1
  fi

  echo "═══ grind: starting ═══"
  echo "Task: $task"
  echo "Worker: $active_worker"
  echo "Reviewer: $active_reviewer"
  echo ""

  while true; do
    (( iteration++ ))
    echo "─── iteration $iteration ───"

    # WORK (skip on first iteration if no task)
    if [[ -n "$task" || -n "$review_output" ]]; then
      echo "[work] worker..."
      local work_prompt=""
      if [[ -z "$review_output" ]]; then
        work_prompt="$task"
      elif [[ -n "$worker_session" ]]; then
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

      local worker_raw=""
      worker_raw=$(_grind_run "$active_worker" "$work_prompt" "$worker_session")
      if [[ -z "$worker_session" ]]; then
        worker_session=$(_grind_parse_session "$worker_raw" "$active_worker")
        [[ -n "$worker_session" ]] && echo "[work] session: $worker_session"
      fi
      local worker_result=""
      worker_result=$(_grind_parse_output "$worker_raw" "$active_worker" "worker")
      echo "$worker_result"
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

    rm -f /tmp/grind_review_$$.out
    local reviewer_raw=""
    reviewer_raw=$(_grind_run "$active_reviewer" "$full_review_prompt" "$reviewer_session")
    if [[ -z "$reviewer_session" ]]; then
      reviewer_session=$(_grind_parse_session "$reviewer_raw" "$active_reviewer")
      [[ -n "$reviewer_session" ]] && echo "[review] session: $reviewer_session"
    fi
    review_output=$(_grind_parse_output "$reviewer_raw" "$active_reviewer" "reviewer")
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

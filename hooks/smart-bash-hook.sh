#!/bin/bash

# Smart Pre-Bash Hook for Claude Code
# - Intercepts verbose commands
# - Runs them and saves full output to log
# - Returns concise summary to Claude
# - User can view full log at ~/.command-filter/latest.log

LOGS_DIR="$HOME/.command-filter"
mkdir -p "$LOGS_DIR"

# Read JSON input from stdin
input=$(cat)

# Extract the command from tool_input.command in the JSON
command=$(echo "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"command"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')

# Unescape the command
command=$(echo "$command" | sed 's/\\"/"/g' | sed 's/\\\\/\\/g')

# If we couldn't extract the command, allow it through normally
if [ -z "$command" ]; then
  exit 0
fi

# Check if this is a verbose command
is_verbose=false
command_type=""

if [[ "$command" =~ ^docker\ compose\ (build|up|pull|push|logs) ]] || [[ "$command" =~ ^docker\ build ]]; then
  is_verbose=true
  command_type="docker"
elif [[ "$command" =~ ^(npm|yarn|pnpm)\ (install|ci)($|\ ) ]]; then
  is_verbose=true
  command_type="npm"
elif [[ "$command" =~ ^(npm|yarn|pnpm)\ run\ (build|dev|start) ]] || [[ "$command" =~ ^(npm|yarn|pnpm)\ build ]]; then
  is_verbose=true
  command_type="npm_script"
elif [[ "$command" =~ ^cargo\ (build|run|test|clippy) ]]; then
  is_verbose=true
  command_type="cargo"
elif [[ "$command" =~ ^pip\ install ]] || [[ "$command" =~ ^(poetry|pipenv)\ install ]]; then
  is_verbose=true
  command_type="pip"
elif [[ "$command" =~ ^pytest ]] || [[ "$command" =~ ^python.*-m\ pytest ]]; then
  is_verbose=true
  command_type="pytest"
elif [[ "$command" =~ ^(jest|vitest|mocha|ava)($|\ ) ]] || [[ "$command" =~ npm\ (run\ )?test ]]; then
  is_verbose=true
  command_type="jest"
elif [[ "$command" =~ ^(make|cmake|ninja)($|\ ) ]]; then
  is_verbose=true
  command_type="make"
elif [[ "$command" =~ ^go\ (build|test|mod) ]]; then
  is_verbose=true
  command_type="go"
elif [[ "$command" =~ ^kubectl\ (logs|describe) ]]; then
  is_verbose=true
  command_type="kubectl"
elif [[ "$command" =~ ^git\ (clone|pull|fetch) ]]; then
  is_verbose=true
  command_type="git"
elif [[ "$command" =~ ^(bundle|gem)\ install ]]; then
  is_verbose=true
  command_type="bundle"
elif [[ "$command" =~ ^terraform\ (plan|apply|init) ]]; then
  is_verbose=true
  command_type="terraform"
elif [[ "$command" =~ ^gradle\ (build|assemble) ]] || [[ "$command" =~ ^mvn\ (compile|package|install) ]]; then
  is_verbose=true
  command_type="gradle"
fi

# If not verbose, let it through normally
if [ "$is_verbose" = false ]; then
  exit 0
fi

# === VERBOSE COMMAND DETECTED ===

# Extract cwd from input JSON
cwd=$(echo "$input" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"cwd"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//')

# Change to cwd
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  cd "$cwd"
fi

# Log file paths
timestamp=$(date +%Y%m%d_%H%M%S)
output_file="$LOGS_DIR/output_${timestamp}.log"
ln -sf "$output_file" "$LOGS_DIR/latest.log"

# Write header to log
{
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Command Filter Log - $(date)"
  echo "Directory: $cwd"
  echo "Command: $command"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
} > "$output_file"

# Run the command and capture output
/bin/bash -c "$command" >> "$output_file" 2>&1
exit_code=$?

# Append footer to log
{
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Exit code: $exit_code"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
} >> "$output_file"

# Read output for summary extraction
output=$(cat "$output_file")

# Extract summary based on command type
summary=""

case "$command_type" in
  docker)
    if [ $exit_code -eq 0 ]; then
      if echo "$output" | grep -q "Successfully built\|Successfully tagged"; then
        image_info=$(echo "$output" | grep -E "Successfully (built|tagged)" | tail -1)
        summary="Docker build succeeded. $image_info"
      elif echo "$output" | grep -q "Container.*Started\|Container.*Running"; then
        summary="Docker compose up succeeded. Containers started."
      else
        summary="Docker command completed successfully."
      fi
    else
      error_line=$(echo "$output" | grep -iE "error|failed|cannot|unable" | head -1)
      summary="Docker command failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  npm)
    if [ $exit_code -eq 0 ]; then
      packages=$(echo "$output" | grep -oE "added [0-9]+ packages?" | tail -1 || echo "")
      vulns=$(echo "$output" | grep -oE "[0-9]+ vulnerabilit(y|ies)" | tail -1 || echo "0 vulnerabilities")
      time_info=$(echo "$output" | grep -oE "in [0-9]+(\.[0-9]+)?m?s" | tail -1 || echo "")
      summary="npm install succeeded. ${packages:-Packages installed}. ${vulns}. ${time_info}"
    else
      error_line=$(echo "$output" | grep -iE "ERR!|error|failed" | head -1)
      summary="npm install failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  npm_script)
    if [ $exit_code -eq 0 ]; then
      summary="npm script completed successfully."
    else
      error_line=$(echo "$output" | grep -iE "error|failed|exception" | head -1)
      summary="npm script failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  cargo)
    if [ $exit_code -eq 0 ]; then
      warnings=$(echo "$output" | grep -c "warning:" || echo "0")
      if echo "$output" | grep -q "Finished"; then
        finish_line=$(echo "$output" | grep "Finished" | tail -1)
        summary="Cargo succeeded. $warnings warning(s). $finish_line"
      else
        summary="Cargo succeeded. $warnings warning(s)."
      fi
    else
      error_line=$(echo "$output" | grep -E "^error\[" | head -1)
      summary="Cargo failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  pip)
    if [ $exit_code -eq 0 ]; then
      summary="pip install succeeded."
    else
      error_line=$(echo "$output" | grep -iE "error|failed|could not" | head -1)
      summary="pip install failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  pytest)
    if [ $exit_code -eq 0 ]; then
      results=$(echo "$output" | grep -oE "[0-9]+ passed" | tail -1 || echo "")
      skipped=$(echo "$output" | grep -oE "[0-9]+ skipped" | tail -1 || echo "")
      time_info=$(echo "$output" | grep -oE "in [0-9]+\.[0-9]+s" | tail -1 || echo "")
      summary="pytest passed. ${results}${skipped:+, $skipped}. ${time_info}"
    else
      passed=$(echo "$output" | grep -oE "[0-9]+ passed" | tail -1 || echo "0 passed")
      failed=$(echo "$output" | grep -oE "[0-9]+ failed" | tail -1 || echo "? failed")
      failed_tests=$(echo "$output" | grep -E "^FAILED " | sed 's/FAILED //' | head -5 | tr '\n' ', ' | sed 's/, $//')
      summary="pytest failed. ${passed}, ${failed}. Failed: ${failed_tests:-see log}"
    fi
    ;;

  jest)
    if [ $exit_code -eq 0 ]; then
      tests=$(echo "$output" | grep -oE "Tests:.*[0-9]+ passed" | tail -1 || echo "Tests passed")
      summary="Jest passed. $tests"
    else
      tests=$(echo "$output" | grep -oE "Tests:.*" | tail -1 || echo "")
      summary="Jest failed. ${tests:-Some tests failed}. See log."
    fi
    ;;

  make)
    if [ $exit_code -eq 0 ]; then
      summary="Build succeeded."
    else
      error_line=$(echo "$output" | grep -E "error:|Error:|make:.*Error" | head -1)
      summary="Build failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  go)
    if [ $exit_code -eq 0 ]; then
      if echo "$command" | grep -q "test"; then
        summary="Go tests passed."
      else
        summary="Go build succeeded."
      fi
    else
      error_line=$(echo "$output" | grep -E "^.*\.go:[0-9]+:" | head -1)
      summary="Go command failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  git)
    if [ $exit_code -eq 0 ]; then
      if echo "$command" | grep -q "clone"; then
        summary="Git clone succeeded."
      else
        summary="Git command succeeded."
      fi
    else
      error_line=$(echo "$output" | grep -iE "error|fatal" | head -1)
      summary="Git command failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  kubectl)
    last_lines=$(echo "$output" | tail -3 | tr '\n' ' ')
    if [ $exit_code -eq 0 ]; then
      summary="kubectl succeeded. $last_lines"
    else
      summary="kubectl failed (exit $exit_code). $last_lines"
    fi
    ;;

  terraform)
    if [ $exit_code -eq 0 ]; then
      if echo "$output" | grep -q "Plan:"; then
        plan=$(echo "$output" | grep "Plan:" | tail -1)
        summary="Terraform plan succeeded. $plan"
      elif echo "$output" | grep -q "Apply complete"; then
        apply=$(echo "$output" | grep "Apply complete" | tail -1)
        summary="Terraform apply succeeded. $apply"
      else
        summary="Terraform command succeeded."
      fi
    else
      error_line=$(echo "$output" | grep -iE "Error:" | head -1)
      summary="Terraform failed (exit $exit_code). ${error_line:-See log.}"
    fi
    ;;

  *)
    last_lines=$(echo "$output" | tail -3 | tr '\n' ' ')
    if [ $exit_code -eq 0 ]; then
      summary="Command succeeded. $last_lines"
    else
      summary="Command failed (exit $exit_code). ${last_lines:-See log.}"
    fi
    ;;
esac

# Add view log hint
summary="$summary (View full: cat ~/.command-filter/latest.log)"

# Clean up summary (remove control chars, limit length)
summary=$(echo "$summary" | tr -d '\r' | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-500)

# Output JSON to modify the tool input
escaped_summary=$(echo "$summary" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Verbose command output saved to log - returning summary",
    "updatedInput": {
      "command": "echo \"${escaped_summary}\""
    }
  }
}
EOF

exit 0

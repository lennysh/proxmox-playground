#!/usr/bin/env bash
#
# Summarize a Proxmox vzdump task log: successes, failures, skipped guests, job status.
# Usage: summarize-vzdump-log.sh <path-to-task.log>
#        summarize-vzdump-log.sh --errors-only <path-to-task.log>
#        summarize-vzdump-log.sh --warnings <path-to-task.log>
#
set -euo pipefail

ERRORS_ONLY=false
SHOW_WARNINGS=false
LOG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
Summarize a Proxmox vzdump task log.

Usage: summarize-vzdump-log.sh [options] <vzdump-task.log>

Options:
  --errors-only, -e   Failures, incomplete VMs, job result only
  --warnings, -w      Also print other ERROR: lines with line numbers
  -h, --help          This help
EOF
      exit 0
      ;;
    --errors-only|-e)
      ERRORS_ONLY=true
      shift
      ;;
    --warnings|-w)
      SHOW_WARNINGS=true
      shift
      ;;
    *)
      LOG="$1"
      shift
      ;;
  esac
done

if [[ -z "$LOG" ]]; then
  echo "Usage: $0 [--errors-only] [--warnings] <vzdump-task.log>" >&2
  echo "  --errors-only, -e   Compact: failures + incomplete VMs + job result only" >&2
  echo "  --warnings, -w      Also list other ERROR: lines (line numbers; often non-fatal)" >&2
  exit 1
fi

if [[ ! -f "$LOG" ]]; then
  echo "Error: not a readable file: $LOG" >&2
  exit 1
fi

# --- counts ---
n_start=$(grep -c '^INFO: Starting Backup of VM ' "$LOG" || true)
n_ok=$(grep -c '^INFO: Finished Backup of VM ' "$LOG" || true)

job_line=$(grep '^INFO: starting new backup job:' "$LOG" | head -1 | sed 's/^INFO: starting new backup job: //' || true)
skip_line=$(grep '^INFO: skip external VMs:' "$LOG" | head -1 || true)
job_end=$(grep -E '^INFO: Backup job finished' "$LOG" | tail -1 || true)
task_err=$(grep '^TASK ERROR:' "$LOG" | tail -1 || true)

if [[ "$ERRORS_ONLY" != true ]]; then
  echo "=== vzdump log summary ==="
  echo "File: $LOG"
  echo ""
  if [[ -n "$job_line" ]]; then
    echo "Job: ${job_line:0:120}$([[ ${#job_line} -gt 120 ]] && echo '...')"
  fi
  if [[ -n "$skip_line" ]]; then
    echo "$skip_line"
  fi
  echo ""
  echo "Backups started:  $n_start"
  echo "Backups finished: $n_ok"
  echo ""
fi

# --- explicit failures: ERROR: Backup of VM N failed - ... ---
n_fail=$(grep -cE '^ERROR: Backup of VM [0-9]+ failed -' "$LOG" || true)
failures=$(grep -E '^ERROR: Backup of VM [0-9]+ failed -' "$LOG" || true)

if [[ -n "$failures" ]]; then
  echo "━━ FAILED BACKUPS ($n_fail) ━━"
  awk '
    /^INFO: Starting Backup of VM / {
      sub(/^.*Starting Backup of VM /, ""); sub(/ .*/, ""); vmid = $0; gname = ""
    }
    /^INFO: CT Name: /   { sub(/^INFO: CT Name: /, ""); gname = $0 }
    /^INFO: VM Name: /   { sub(/^INFO: VM Name: /, ""); gname = $0 }
    /^ERROR: Backup of VM [0-9]+ failed/ {
      line = $0
      sub(/^ERROR: Backup of VM /, "", line)
      n = index(line, " failed - ")
      fvm = substr(line, 1, n - 1)
      reason = substr(line, n + length(" failed - "))
      printf "  VM %-6s", fvm
      if (gname != "" && fvm == vmid) printf " (%s)", gname
      printf "\n         %s\n", reason
    }
  ' "$LOG"
  echo ""
else
  if [[ "$ERRORS_ONLY" == true ]]; then
    echo "No explicit backup failures (no 'ERROR: Backup of VM N failed' lines)."
  elif [[ "$n_start" -gt 0 ]]; then
    echo "Failed backups:   0 (no ERROR: Backup of VM ... failed lines)"
    echo ""
  fi
fi

# --- VMs that started but neither finished nor have explicit failure ---
mapfile -t started < <(grep '^INFO: Starting Backup of VM ' "$LOG" | sed -n 's/^INFO: Starting Backup of VM \([0-9][0-9]*\).*/\1/p' | sort -u)
mapfile -t finished < <(grep '^INFO: Finished Backup of VM ' "$LOG" | sed -n 's/^INFO: Finished Backup of VM \([0-9][0-9]*\).*/\1/p' | sort -u)
mapfile -t failed_ids < <(grep '^ERROR: Backup of VM ' "$LOG" | sed -n 's/^ERROR: Backup of VM \([0-9][0-9]*\) failed.*/\1/p' | sort -u)

incomplete=()
for vm in "${started[@]}"; do
  okf=false
  for f in "${finished[@]}"; do [[ "$f" == "$vm" ]] && okf=true && break; done
  okfail=false
  for f in "${failed_ids[@]}"; do [[ "$f" == "$vm" ]] && okfail=true && break; done
  if [[ "$okf" == false && "$okfail" == false ]]; then
    incomplete+=("$vm")
  fi
done

if [[ ${#incomplete[@]} -gt 0 ]]; then
  echo "━━ INCOMPLETE (started, no Finished / no explicit fail) ━━"
  echo "  VM IDs: ${incomplete[*]}"
  echo "  (log may be truncated or job interrupted)"
  echo ""
fi

# --- other ERROR lines (often non-fatal, e.g. guest fs-freeze) ---
if [[ "$SHOW_WARNINGS" == true ]]; then
  other=$(grep -n '^ERROR:' "$LOG" | grep -v 'ERROR: Backup of VM [0-9][0-9]* failed' || true)
  if [[ -n "$other" ]]; then
    echo "━━ OTHER ERROR: lines (may be non-fatal) ━━"
    echo "$other" | head -50
    n_other=$(echo "$other" | wc -l)
    if [[ "$n_other" -gt 50 ]]; then
      echo "  ... ($n_other total, showing first 50; use rg/grep on the log for full list)"
    fi
    echo ""
  fi
fi

[[ "$ERRORS_ONLY" == true ]] && echo ""
echo "━━ Job result ━━"
[[ -n "$job_end" ]] && echo "  $job_end" || echo "  (no 'Backup job finished' line found)"
[[ -n "$task_err" ]] && echo "  $task_err"
if [[ "$ERRORS_ONLY" != true && "$n_fail" -eq 0 && ${#incomplete[@]} -eq 0 && "$n_start" -eq "$n_ok" && "$n_start" -gt 0 ]]; then
  echo "  All $n_start backup(s) completed successfully."
fi
echo ""

# Exit non-zero if there were failures (useful in scripts)
if [[ "$n_fail" -gt 0 || ${#incomplete[@]} -gt 0 ]]; then
  exit 2
fi
if [[ "$task_err" == *ERROR* ]]; then
  exit 2
fi
exit 0

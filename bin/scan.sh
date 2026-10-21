#!/usr/bin/env bash
# =============================================================================
# scan.sh <project-path> — ONE command to scan ONE local project.
#
# Runs semgrep (SAST), gitleaks (secrets) and/or trivy (dependency CVEs)
# against a local folder and writes a dev-friendly HTML report. No GitHub,
# no API token, nothing gets cloned — your code never leaves this machine.
# A single tool can be selected with --tool.
#
# Usage:
#   bash bin/scan.sh /path/to/my-project                    # all 3 tools + HTML
#   bash bin/scan.sh /path/to/my-project --tool gitleaks    # secrets only
#   bash bin/scan.sh /path/to/my-project --tools "semgrep trivy"   # two tools
#   bash bin/scan.sh /path/to/my-project --name myapp       # custom report name
#   bash bin/scan.sh /path/to/my-project --dry-run          # preview only
#
# Output: data/reports/<name>/{json,html}/  + logs in data/reports/_run_logs/
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"

ALL_TOOLS="semgrep gitleaks trivy"

usage() {
  cat <<'EOF'
sec-dev scan.sh — scan ONE local project folder (no GitHub, no token).

Usage:
  bash bin/scan.sh <project-path> [options]

Options:
  --tool <name>      scan with a single tool: semgrep | gitleaks | trivy
                     (repeat or space-separate to pick several)
  --name <name>      report folder name (default: project folder name)
  --dry-run          print what would be done, change nothing
  -h, --help         show this help

Examples:
  bash bin/scan.sh C:/code/my-app                # all 3 scanners
  bash bin/scan.sh C:/code/my-app --tool gitleaks   # secrets check only
  bash bin/scan.sh C:/code/my-app --dry-run      # preview
EOF
}

warn_missing_tools() {
  local bin missing=0
  for bin in "$SEMGREP_BIN" "$GITLEAKS_BIN" "$TRIVY_BIN"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "WARN: not found on PATH: $bin" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    echo "     Run the one-time installer first:  bash bin/install_tools.sh" >&2
  fi
}

json_for() {
  case "$1" in
    semgrep)  echo "sast.json" ;;
    gitleaks) echo "secrets.json" ;;
    trivy)    echo "sca.json" ;;
  esac
}

run_scanner() {
  local label="$1" outfile="$2" logbase="$3"; shift 3
  echo "  --> running ${label}..."
  "$@" >"${logbase}.stdout" 2>"${logbase}.stderr"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "  !! ${label} exited rc=${rc} (normal when it found issues; see ${logbase}.stderr)"
  fi
  # Scanner JSON may be missing or invalid (e.g. tool crashed). Write an error
  # marker so the report still renders and the problem is visible.
  if [[ ! -s "$outfile" ]] || ! python3 -c 'import json,sys;json.load(open(sys.argv[1],encoding="utf-8",errors="replace"))' "$outfile" 2>/dev/null; then
    echo "  !! ${label} produced no valid JSON; writing error marker to ${outfile}"
    printf '{"status":"error","scanner":"%s","rc":%s}\n' \
      "$label" "$rc" >"$outfile"
  fi
}

main() {
  local project="" name="" tools="$TOOLS" user_tools=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      # --tool/--tools accumulate: "--tool semgrep --tool gitleaks" runs both,
      # and a space-separated list "--tools 'semgrep gitleaks'" works too.
      --tool|--tools) user_tools="${user_tools:+$user_tools }${2:-}"; shift 2 ;;
      --name)  name="$2"; shift 2 ;;
      --dry-run) export DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
      *)  project="$1"; shift ;;
    esac
  done
  [[ -n "$user_tools" ]] && tools="$user_tools"

  # --- Validate inputs -------------------------------------------------------
  if [[ -z "$project" ]]; then
    echo "ERROR: missing project path." >&2
    echo "       Usage: bash bin/scan.sh <path-to-project> [--tool semgrep|gitleaks|trivy]" >&2
    exit 1
  fi
  if [[ ! -d "$project" ]]; then
    echo "ERROR: project folder not found: $project" >&2
    echo "       Pass the FULL path to your project folder (e.g. bash bin/scan.sh C:/code/my-app)." >&2
    exit 1
  fi
  project="$(cd "$project" && pwd)"   # normalize (also handles Windows paths under Git Bash)

  # --- Validate / normalize tool selection -----------------------------------
  local want=() t
  for t in $tools; do
    case " $ALL_TOOLS " in
      *" $t "*) want+=("$t") ;;
      *) echo "ERROR: unknown tool '$t' (choose from: $ALL_TOOLS)" >&2; exit 1 ;;
    esac
  done
  [[ ${#want[@]} -gt 0 ]] || { echo "ERROR: no valid tool selected (choose from: $ALL_TOOLS)" >&2; exit 1; }

  # No duplicate runs if the same tool was listed twice.
  tools="$(printf '%s\n' "${want[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')"

  # --- Report naming -----------------------------------------------------------
  name="${name:-$(basename "$project")}"
  name="${name// /_}"                            # no spaces in file names
  [[ -n "$name" ]] || name="project"

  local json_dir="$REPORTS_DIR/$name/json"
  local html_dir="$REPORTS_DIR/$name/html"
  local log_dir="$LOGS_DIR/$name"
  if [[ "$DRY_RUN" -ne 1 ]]; then
    mkdir -p "$json_dir" "$html_dir" "$log_dir"
  fi

  echo "==> scan.sh  [DRY_RUN=${DRY_RUN}]"
  echo "    project:  ${project}"
  echo "    tools:    ${tools}"
  echo "    report:   ${html_dir}"
  warn_missing_tools

  if [[ "$DRY_RUN" -eq 1 ]]; then
    for t in $tools; do
      echo "    DRY-RUN: would run ${t} on '${project}' -> ${json_dir}/$(json_for "$t")"
    done
    echo "    DRY-RUN: would render HTML into ${html_dir}"
    return 0
  fi

  # --- Run the selected scanners ----------------------------------------------
  for t in $tools; do
    case "$t" in
      semgrep)
        # --config p/default: explicit ruleset (semgrep's "auto" config
        # requires metrics to be enabled; p/default works with --metrics=off).
        run_scanner "semgrep" "$json_dir/sast.json" "$log_dir/sast.json" \
          "$SEMGREP_BIN" scan --json --metrics=off --config p/default \
          --no-rewrite-rule-ids -o "$json_dir/sast.json" "$project"
        ;;
      gitleaks)
        run_scanner "gitleaks" "$json_dir/secrets.json" "$log_dir/secrets.json" \
          "$GITLEAKS_BIN" detect --source "$project" --no-banner \
          --report-format json --report-path "$json_dir/secrets.json"
        ;;
      trivy)
        run_scanner "trivy" "$json_dir/sca.json" "$log_dir/sca.json" \
          "$TRIVY_BIN" fs --format json --output "$json_dir/sca.json" --no-progress "$project"
        ;;
    esac
  done

  # --- Render the HTML report (only pages for the tools that ran) -------------
  echo "  --> rendering HTML report..."
  "${PYTHON:-python3}" "$SCRIPT_DIR/render_reports.py" "$name" \
    --input "$json_dir" --output "$html_dir" --tools "$tools"

  # --- Friendly summary ---------------------------------------------------------
  echo
  echo "==> Done. Your report:  $html_dir/digest.html"
  local open_cmd="xdg-open"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) open_cmd="explorer.exe" ;;
    Darwin*) open_cmd="open" ;;
  esac
  echo "    To open it now:  ${open_cmd} ${html_dir}/digest.html"
  echo "    (raw scanner JSON is in ${json_dir}; logs in ${log_dir})"
}

main "$@"

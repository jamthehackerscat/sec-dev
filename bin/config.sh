#!/usr/bin/env bash
# =============================================================================
# config.sh — central configuration for sec-dev (the LOCAL single-project
# scanner). Source this from other scripts (never run directly).
#
#   sec-dev/bin/config.sh       this file (loader + defaults)
#   sec-dev/config/settings.sh  optional non-secret overrides
#   sec-dev/.venv/              git-ignored venv holding semgrep (created by
#                               bin/install_tools.sh)
#   sec-dev/data/               git-IGNORED scan results (JSON + HTML + logs)
# =============================================================================

# --- Base paths ---------------------------------------------------------------
# bin/ lives one level under the tool root.
DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # .../sec-dev
export DEV_DIR

export SETTINGS_FILE="${SETTINGS_FILE:-$DEV_DIR/config/settings.sh}"
export DATA_DIR="${DATA_DIR:-$DEV_DIR/data}"                  # scan results
export REPORTS_DIR="${REPORTS_DIR:-$DEV_DIR/data/reports}"    # per-project outputs
export LOGS_DIR="${LOGS_DIR:-$REPORTS_DIR/_run_logs}"         # scanner logs

# --- Optional settings ----------------------------------------------------------
# Load overrides from config/settings.sh if present (all have defaults here).
if [[ -f "$SETTINGS_FILE" ]]; then
  # shellcheck disable=SC1091
  source "$SETTINGS_FILE"
fi

# --- PATH -----------------------------------------------------------------------
# Where the tools land (both are NOT on the default PATH on most systems, so we
# prepend them here — no user shell config files are ever touched):
#   $DEV_DIR/.venv/bin (or Scripts on Windows)   semgrep
#   ~/.local/bin                                 gitleaks + trivy
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) export VENV_BIN="$DEV_DIR/.venv/Scripts" ;;
  *)                    export VENV_BIN="$DEV_DIR/.venv/bin" ;;
esac
export PATH="$VENV_BIN:$HOME/.local/bin:$PATH"

# --- Tools ---------------------------------------------------------------------
# Command names for the scanners (PATH commands; override via settings.sh).
export SEMGREP_BIN="${SEMGREP_BIN:-semgrep}"
export GITLEAKS_BIN="${GITLEAKS_BIN:-gitleaks}"
export TRIVY_BIN="${TRIVY_BIN:-trivy}"

# Default scanners used when none are selected on the command line.
export TOOLS="${TOOLS:-semgrep gitleaks trivy}"

# --- Run controls ----------------------------------------------------------------
# When set to 1, scripts print what they WOULD do instead of doing it.
export DRY_RUN="${DRY_RUN:-0}"

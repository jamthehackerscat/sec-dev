#!/usr/bin/env bash
# =============================================================================
# install_tools.sh — install EVERYTHING sec-dev needs, on Linux / macOS /
# Windows (Git Bash or WSL). Run WITHOUT sudo:
#
#     bash bin/install_tools.sh
#
# Installs, in order:
#   1. system prerequisites   python3 (+venv), curl, git, tar
#                             (via sudo apt-get on Debian/Ubuntu, brew on
#                              macOS, winget on Windows — only if missing)
#   2. semgrep   (SAST)       into an isolated local venv at sec-dev/.venv
#                             (no pipx, no sudo, no PEP 668 headaches)
#   3. gitleaks  (secrets)    latest release binary into ~/.local/bin
#   4. trivy     (SCA)        latest release binary into ~/.local/bin
#
# Nothing here touches your shell config files — bin/config.sh adds the
# install locations to PATH at runtime.
#
# Usage:   bash bin/install_tools.sh [--dry-run]
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config.sh"

if [[ "${1:-}" == "--dry-run" ]]; then export DRY_RUN=1; fi

# --- OS / arch detection -------------------------------------------------------
OS_FAMILY="$(uname -s)"
case "$OS_FAMILY" in
  Linux*)                    OS_FAMILY=linux ;;
  Darwin*)                   OS_FAMILY=darwin ;;
  MINGW*|MSYS*|CYGWIN*)      OS_FAMILY=windows ;;
  *) echo "ERROR: unsupported OS: $OS_FAMILY" >&2; exit 1 ;;
esac
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64)      MACHINE=x64 ;;
  aarch64|arm64)     MACHINE=arm64 ;;
esac
export PATH="$HOME/.local/bin:$PATH"   # so we can find tools right after install

apt_try() {   # apt install with a friendly fallback message
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would run: sudo apt-get install -y $*"
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y "$@"
  else
    echo "ERROR: missing package(s): $* — install them with your distro's" >&2
    echo "       package manager (this script supports Debian/Ubuntu apt)." >&2
    exit 1
  fi
}

# --- 1. System prerequisites ----------------------------------------------------
ensure_prereqs() {
  echo "==> checking system prerequisites (python3, curl, git, tar)"
  case "$OS_FAMILY" in
    linux)
      local missing=()
      for t in curl python3 git tar; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
      done
      if [[ ${#missing[@]} -gt 0 ]]; then
        echo "  installing missing: ${missing[*]}"
        apt_try "${missing[@]}"
      fi
      # `python3 -m venv` needs the separate python3-venv package on Debian/Ubuntu.
      if ! python3 -c 'import venv' >/dev/null 2>&1; then
        echo "  installing python3-venv"
        apt_try python3-venv
      fi
      ;;
    darwin)
      if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: Homebrew not found. Install it first:  https://brew.sh" >&2
        exit 1
      fi
      local missing=()
      for t in python3 git; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
      done
      if [[ ${#missing[@]} -gt 0 ]]; then
        echo "  installing missing: ${missing[*]} (brew)"
        [[ "$DRY_RUN" -eq 1 ]] && { echo "  [dry-run] would run: brew install ${missing[*]}"; return 0; }
        brew install "${missing[@]}"
      fi
      ;;
    windows)
      if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
        echo "  installing Python (winget)"
        if [[ "$DRY_RUN" -eq 1 ]]; then echo "  [dry-run] would run: winget install -e --id Python.Python.3.12"; return 0; fi
        winget install -e --id Python.Python.3.12 \
          --accept-package-agreements --accept-source-agreements \
          || { echo "ERROR: could not install Python via winget — install it from" >&2
               echo "       https://www.python.org/downloads/ and re-run this script." >&2; exit 1; }
      fi
      ;;
  esac
  echo "  prerequisites OK"
}

# --- 2. Semgrep (SAST) -------------------------------------------------------------
install_semgrep() {
  echo "==> installing semgrep (SAST)"
  if [[ "$OS_FAMILY" == "windows" ]]; then
    if command -v semgrep >/dev/null 2>&1; then echo "  semgrep already on PATH"; return 0; fi
    echo "  installing semgrep via winget"
    if [[ "$DRY_RUN" -eq 1 ]]; then echo "  [dry-run] would run: winget install -e --id returntocorp.Semgrep"; return 0; fi
    winget install -e --id returntocorp.Semgrep \
      --accept-package-agreements --accept-source-agreements \
      || echo "  !! winget install failed — install semgrep manually: https://semgrep.dev/docs/getting-started/"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would create a venv at $DEV_DIR/.venv and pip-install semgrep"
    return 0
  fi
  if [[ ! -x "$VENV_BIN/python" ]]; then
    echo "  creating venv at $DEV_DIR/.venv"
    python3 -m venv "$DEV_DIR/.venv"
  fi
  echo "  pip-installing semgrep into $DEV_DIR/.venv (a few minutes on first run)"
  "$VENV_BIN/python" -m pip install --upgrade pip
  "$VENV_BIN/python" -m pip install --upgrade semgrep
}

# --- 3. Gitleaks (secrets) ----------------------------------------------------------
install_gitleaks() {
  echo "==> installing gitleaks (secrets)"
  if command -v gitleaks >/dev/null 2>&1; then echo "  gitleaks already on PATH"; return 0; fi
  if [[ "$OS_FAMILY" == "windows" ]]; then
    echo "  installing gitleaks via winget"
    if [[ "$DRY_RUN" -eq 1 ]]; then echo "  [dry-run] would run: winget install -e --id gitleaks.gitleaks"; return 0; fi
    winget install -e --id gitleaks.gitleaks \
      --accept-package-agreements --accept-source-agreements \
      || echo "  !! winget install failed — install gitleaks manually: https://github.com/gitleaks/gitleaks/releases"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] would download the latest gitleaks release into ~/.local/bin"
    return 0
  fi
  local tag url tmp
  tag="$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')"
  url="https://github.com/gitleaks/gitleaks/releases/download/${tag}/gitleaks_${tag#v}_${OS_FAMILY}_${MACHINE}.tar.gz"
  echo "  downloading ${url}"
  tmp="$(mktemp -d)"
  curl -fsSL "$url" | tar -xz -C "$tmp"
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$tmp/gitleaks" "$HOME/.local/bin/gitleaks"
  rm -rf "$tmp"
}

# --- 4. Trivy (SCA) -------------------------------------------------------------------
install_trivy() {
  echo "==> installing trivy (SCA)"
  if command -v trivy >/dev/null 2>&1; then echo "  trivy already on PATH"; return 0; fi
  if [[ "$OS_FAMILY" == "windows" ]]; then
    echo "  installing trivy via winget"
    if [[ "$DRY_RUN" -eq 1 ]]; then echo "  [dry-run] would run: winget install -e --id aquasecurity.Trivy"; return 0; fi
    winget install -e --id aquasecurity.Trivy \
      --accept-package-agreements --accept-source-agreements \
      || echo "  !! winget install failed — install trivy manually: https://trivy.dev/docs/getting-started/installation/"
    return 0
  fi
  echo "  downloading trivy into ~/.local/bin (official install script)"
  if [[ "$DRY_RUN" -eq 1 ]]; then return 0; fi
  mkdir -p "$HOME/.local/bin"
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b "$HOME/.local/bin"
}

# --- 5. Verify -------------------------------------------------------------------------
verify() {
  echo
  echo "==> verifying tools"
  local ok=1
  for bin in "$SEMGREP_BIN" "$GITLEAKS_BIN" "$TRIVY_BIN"; do
    if command -v "$bin" >/dev/null 2>&1; then
      echo "    ok: $bin -> $(command -v "$bin")"
      if [[ "$DRY_RUN" -ne 1 ]]; then "$bin" --version 2>/dev/null | head -1 | sed 's/^/        /'; fi
    else
      echo "    missing: $bin" >&2
      ok=0
    fi
  done
  if [[ "$ok" -ne 1 ]]; then
    echo "!! one or more tools are still missing — scroll up for the error." >&2
    exit 1
  fi
}

main() {
  echo "==> sec-dev installer  [OS=${OS_FAMILY} arch=${MACHINE} DRY_RUN=${DRY_RUN}]"
  echo "    install dir: ~/.local/bin  (gitleaks, trivy)   +   $DEV_DIR/.venv  (semgrep)"

  ensure_prereqs
  install_semgrep
  install_gitleaks
  install_trivy
  verify

  echo
  echo "==> All tools ready. Next step:"
  echo "        bash bin/scan.sh /path/to/your/project"
}

main

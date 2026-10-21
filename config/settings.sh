#!/usr/bin/env bash
# =============================================================================
# settings.sh — optional non-secret overrides for sec-dev.
# Sourced by bin/config.sh. Everything here already has a working default;
# only uncomment (and edit) the lines you actually need.
# =============================================================================

# Tool binary names — only needed if a tool is installed under a different
# name or lives somewhere else on PATH:
# SEMGREP_BIN="${SEMGREP_BIN:-semgrep}"
# GITLEAKS_BIN="${GITLEAKS_BIN:-gitleaks}"
# TRIVY_BIN="${TRIVY_BIN:-trivy}"

# Scanners used when none are passed to bin/scan.sh:
# TOOLS="${TOOLS:-semgrep gitleaks trivy}"

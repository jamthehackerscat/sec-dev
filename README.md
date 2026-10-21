# sec-dev — scan **one** project folder for security problems

Runs three free, trusted security scanners on **one local project folder** and
gives you a readable HTML report with `file:line` locations and "how to fix"
hints. **No GitHub account. No API token. Nothing gets cloned or uploaded —
your code never leaves your machine.**

| What it finds                                     | Tool     | Report page    |
|---------------------------------------------------|----------|----------------|
| Code bugs & insecure code patterns                | Semgrep  | `sast.html`    |
| Hardcoded passwords, API keys, secrets            | Gitleaks | `secrets.html` |
| Known vulnerabilities (CVEs) in your dependencies | Trivy    | `sca.html`     |

---

## Quick start (3 steps)

### Step 1 — Install the tools (once, 2–5 minutes)

Open a terminal and run:

```bash
cd sec-dev
bash bin/install_tools.sh
```

That's it — the installer puts everything where it's needed (`semgrep` in a
local `sec-dev/.venv`, `gitleaks` + `trivy` in `~/.local/bin`; on Windows Git
Bash it uses `winget` instead). Nothing is added to your shell config.
On Ubuntu/Debian the installer may ask for your `sudo` password — only if a
system package (python3, curl, git) is missing.

> **Windows users:** open **Git Bash** or **WSL (Ubuntu)** first, then use the
> commands above. The only difference is how you write your project path:
>
> | Terminal  | Project path looks like  |
> |-----------|--------------------------|
> | Git Bash  | `C:/code/my-app`         |
> | WSL       | `/mnt/c/code/my-app`     |

### Step 2 — Scan your project

```bash
bash bin/scan.sh /full/path/to/your/project
```

> First run is slower: semgrep downloads its rules and trivy downloads its CVE
> database once. Later runs are fast.

### Step 3 — Open the report

The report is at `data/reports/<project-name>/html/digest.html` where
`<project-name>` is just your project's **folder name**. To open it:

| OS      | How to open it                                                                 |
|---------|--------------------------------------------------------------------------------|
| Windows | double-click `sec-dev\data\reports\my-app\html\digest.html` in File Explorer    |
| macOS   | `open data/reports/my-app/html/digest.html`                                     |
| Linux   | `xdg-open data/reports/my-app/html/digest.html`                                 |

so `bash bin/scan.sh C:/code/my-app` (Git Bash) or
`bash bin/scan.sh /mnt/c/code/my-app` (WSL) → `data/reports/my-app/html/digest.html`.

That's the whole tool. Everything below is optional.

---

## Scan one security tool only

Worried about just one thing? Pick the tool with `--tool`:

```bash
bash bin/scan.sh /path/to/project --tool gitleaks    # secrets only
bash bin/scan.sh /path/to/project --tool semgrep     # code bugs only
bash bin/scan.sh /path/to/project --tool trivy       # dependencies only
bash bin/scan.sh /path/to/project --tools "semgrep trivy"   # any combo
```

You get only the relevant report page(s) + a digest — no empty pages for
scanners you didn't run.

## All options

```bash
bash bin/scan.sh <project-path>                # scan with all 3 tools
        --tool semgrep|gitleaks|trivy          # one tool only (repeatable)
        --name <name>                          # custom report folder name
        --dry-run                              # preview, change nothing
```

| Option      | What it does                                              |
|-------------|-----------------------------------------------------------|
| `--tool`    | Scan with one tool only (default: all three)              |
| `--name`    | Name of the report folder (default: your project's name)  |
| `--dry-run` | Prints what *would* run, does nothing                     |

## Where results live

```
sec-dev/data/reports/<project-name>/
  json/          raw scanner output (sast.json, secrets.json, sca.json)
  html/          digest.html + one page per tool you ran
sec-dev/data/reports/_run_logs/<project-name>/   scanner logs (if you need them)
```

`sec-dev/data/` is git-ignored — results are never accidentally committed.

## Reading the report

Each page is a table of findings:

- **Severity** — Critical / High / Medium / Low
- **Location** — exact `file:line`, click-friendly
- **Finding** — what the tool detected, in plain words
- **How to fix** — a concrete hint (e.g. *"Upgrade to 4.21.1 (currently
  4.18.0)"*)

`digest.html` gives a one-screen summary of everything.

## FAQ / Troubleshooting

| Problem                              | Fix                                                            |
|--------------------------------------|----------------------------------------------------------------|
| `bash: command not found`            | You're in cmd/PowerShell. Open **Git Bash** (or WSL) instead.  |
| `semgrep: command not found` etc.    | Run `bash bin/install_tools.sh` once (it installs everything). |
| `Permission denied` on a script      | Run it as `bash bin/scan.sh ...` — never with `sudo`.          |
| First trivy run seems stuck          | Normal: it downloads the CVE database once.                    |
| "0 findings" everywhere?             | Good news — nothing was found.                                       |
| Scanner errors like "exit rc=1"      | Normal for semgrep/gitleaks: rc=1 means **findings found**.          |
| Scan looks slow on huge projects     | Normal. semgrep already skips `node_modules`/build dirs; for trivy you can add a `.trivyignore`. |
| Installer fails on Ubuntu/Debian     | It needs `sudo` for the apt step only — allow the prompt.      |
| Still stuck                          | Open an issue and paste the output of the failing command.     |

## Notes

- Scanners are independent: if one fails, the others still run and the page
  shows an error marker instead of crashing.
- The tools run only against your local checkout — nothing is sent anywhere
  (semgrep runs with `--metrics=off`; it and trivy only *download* rules /
  CVE data). Semgrep uses the public `p/default` ruleset.
- Custom tool paths / defaults can be tweaked in `config/settings.sh`
  (everything there has a working default, you shouldn't need to).

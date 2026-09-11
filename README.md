# Pentest toolkit (OSCP / CTF)

[![CI](https://github.com/aardwolfsecurityltd/CTF-Toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/aardwolfsecurityltd/CTF-Toolkit/actions/workflows/ci.yml)

An offline, browser-and-shell toolkit for authorised penetration testing and OSCP/CTF practice.
Everything runs locally. No data leaves the machine.

> **Authorised testing only.** Use this against systems you own or have explicit written
> permission to test. See [SECURITY.md](SECURITY.md).

## Open this first

**index.html** — launcher linking every tool.

Keep all files in the same folder so the cross-links work (the launcher, and the playbook's
"more commands in arsenal" deep links).

## What's inside

- **oscp-playbook.html** — the command centre. Switchable tracks (recon, web, Linux, Windows,
  Active Directory, pivoting, buffer overflow, passwords) plus tools that open full-screen:
  a scan planner (paste nmap → per-service commands + box-type routing), a reverse-shell
  generator, a hash identifier, an exploit suggester (with optional live NVD lookup), a proof
  checklist, a per-box credentials/notes tracker, a timer, per-step evidence capture, and an
  auto write-up generator (markdown + print/PDF). Set your IP/LHOST once and every command
  fills itself in. State is saved per box in your browser (localStorage).
- **oscp-arsenal.html** — 1,028 commands from the Orange Cyberdefense arsenal, searchable and
  colour-coded by engagement phase. Accepts `?q=` to pre-filter (used by the playbook links).
- **oscp-cheatsheet.md** — printable quick reference, grouped by port and by phase.
- **oscp-enum.sh** — first-pass enumeration runner. Scans, then fires the right per-service
  tools, printing and logging every command. Usage: `./oscp-enum.sh <ip>`
- **build-arsenal.sh** — re-clones the upstream repo and rebuilds oscp-arsenal.html so it never
  goes stale. Usage: `./build-arsenal.sh [output.html]`

## Setup

```
chmod +x oscp-enum.sh build-arsenal.sh
```

Open index.html in a browser. If the exploit suggester's live NVD lookup is blocked by the
browser on a local file (CORS), serve the folder instead:

```
python3 -m http.server 8000    # then open http://localhost:8000
```

## Running it online

**https://aardwolfsecurityltd.github.io/CTF-Toolkit/**

The `Deploy to GitHub Pages` workflow publishes the repo root as a static site, so the
launcher, playbook and arsenal are browsable without cloning.

Pages has to be turned on once by a repo admin — `GITHUB_TOKEN` isn't allowed to create the
site itself, so `configure-pages`' `enablement` option fails with "Resource not accessible by
integration". Either **Settings → Pages → Source: GitHub Actions**, or:

```
gh api -X POST repos/OWNER/REPO/pages -f build_type=workflow
```

The shell scripts obviously only run locally.

## Notes

- Authorised testing only. Where a tool or technique is off-limits on the OSCP exam
  (sqlmap, automated exploitation, Metasploit beyond the permitted box) the playbook flags it.
- The web commands use the machine name once you set the Domain field (i.e. what you added to
  /etc/hosts); otherwise they use the IP.
- The exploit suggester is triage, not a live vulnerability oracle: it routes you to the
  authoritative sources and flags well-known candidates. Confirm patch levels before acting.
- `oscp-enum.sh` prints every command before running it, which means it assembles commands as
  strings and runs them via `bash -c`. Targets and hostnames are validated against a strict
  character allowlist first, so a target containing shell metacharacters is refused rather
  than executed.
- `oscp-arsenal.html` is generated. Edit `build-arsenal.sh` and regenerate rather than
  hand-editing the page.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Both shell scripts are shellcheck-clean and CI
enforces it.

## Licence

MIT — see [LICENSE](LICENSE). The command set in `oscp-arsenal.html` is generated from the
[Orange Cyberdefense arsenal](https://github.com/Orange-Cyberdefense/arsenal), which carries
its own licence.

# Pentest toolkit

[![CI](https://github.com/aardwolfsecurityltd/CTF-Toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/aardwolfsecurityltd/CTF-Toolkit/actions/workflows/ci.yml)

An offline, browser-and-shell toolkit for CTF boxes, lab machines and authorised
penetration testing. Everything runs locally. No data leaves the machine.

Where a technique is out of bounds on a certification exam — the OSCP rules are the
strictest you are likely to meet — the tools say so, but nothing here assumes you are
sitting one.

> **Authorised testing only.** Use this against systems you own, a lab or CTF you are
> registered with, or an engagement covered by a signed scope. See [SECURITY.md](SECURITY.md).

## Open this first

**index.html** — launcher linking every tool.

Keep the files in one folder so the cross-links work. Every page also carries a nav bar
across the top, so you can move between them without going back to the launcher.

## What's inside

- **playbook.html** — the command centre. Switchable tracks (recon, web, Linux, Windows,
  Active Directory, AD certificate services & delegation, pivoting, container escape, buffer overflow,
  passwords, AV evasion) plus
  tools that open full-screen: a scan planner (paste or drop nmap output → per-service
  commands + box-type routing), a reverse-shell generator, a hash identifier, an exploit
  suggester (with optional live NVD lookup), a SUID cross-reference (paste the output of
  `find / -perm -4000` and it maps every binary onto GTFOBins, ranks them root-shell first,
  rewrites each command to the path on the box, and tells you which ones are just the
  standard bits), a proof checklist, a per-box credentials, notes
  and attempt tracker, a block-based findings editor (drag-to-reorder, severity and status,
  feeds the report), a timer, per-step evidence capture including screenshots, and a write-up
  generator (markdown, self-contained HTML, and print/PDF) in either lab or exam shape. Set your IP/LHOST once and
  every command fills itself in. Press `/` or `Ctrl-K` to search every track, tool and step.
- **arsenal.html** — 1,028 commands from the Orange Cyberdefense arsenal, searchable and
  colour-coded by engagement phase. Fills in the same target variables as the playbook,
  accepts `?q=`, `?cat=` and `?section=` (the playbook deep-links into it pre-filtered),
  writes the current filter back to the URL so a view can be shared, and will copy every
  visible command out as a shell script.
- **cheatsheet.html** — the quick reference, grouped by port and by phase, with a section
  index and print styles. Generated from **cheatsheet.md**, which is still there if you
  would rather read the markdown in your notes app.
- **enum.sh** — first-pass enumeration runner. Scans, then fires the right per-service
  tools, printing and logging every command. Usage: `./enum.sh <ip>`
- **build-arsenal.sh** — rebuilds arsenal.html from a pinned upstream commit.
- **build-cheatsheet.sh** — renders cheatsheet.md to cheatsheet.html.
- **release.sh** — merges the open pull request, tags the release and pushes the tag.
  Reads the version out of the merged code rather than taking one on the command line,
  and refuses to release if CI is not green, the five version stamps disagree, or the
  tag already exists. `./release.sh --dry-run` runs every check and changes nothing.

## Setup

```
chmod +x enum.sh build-arsenal.sh build-cheatsheet.sh release.sh
```

Open index.html in a browser. If the exploit suggester's live NVD lookup is blocked by the
browser on a local file (CORS), serve the folder instead:

```
python3 -m http.server 8000    # then open http://localhost:8000
```

## enum.sh

```
./enum.sh <ip> [hostname] [-u] [-n] [-j N] [--dry-run] [--force]
```

| flag | what it does |
|---|---|
| `-u` | also run a UDP top-ports scan (needs sudo). With `-j N` it runs in the background and is collected at the end |
| `-n` | also run nikto on web ports (slow) |
| `-j N` | run up to N service blocks at once. Output is buffered per block and printed in a fixed order, so it stays readable; `-j 4` typically halves the wall clock. Default 1 |
| `--dry-run` | print and log every command without running any of them — useful for reading the commands, or checking what a target would get hit with. Works without the tools installed |
| `--force` | redo steps whose output file already exists. By default they are skipped, so a re-run after a crash does not repeat the long scans |

It writes everything to `enum_<ip>/`, including `commands.log` — every command it ran, in
order. When it finishes it points you at `enum_<ip>/nmap/detailed.nmap`; drop that file
onto the playbook's scan planner and it routes the box to a track and lists the
per-service commands.

## Where your work is saved

**The playbook keeps everything in this browser's `localStorage`, keyed by the box name.**
Nothing is uploaded anywhere, and nothing is written to disk unless you export it. That
means:

- Clearing site data, using a private window, or opening the toolkit from a different
  browser or machine loses the lot.
- **Use `export box` in the top bar** to write the whole box — ticks, notes, credentials,
  attempts, scan, timer and screenshots — to a JSON file, and `import` to bring it back.
- If the browser refuses to save (private mode, full quota) a red banner appears at the
  top of the page rather than failing quietly.
- The box picker lists every box you have worked on, and can create, duplicate and delete
  them.

Screenshots pasted into an evidence box are downscaled before being stored, but they are
still the bulk of what is saved. `localStorage` gives you roughly 5MB in total, so export
a finished box and delete it rather than keeping dozens around.

## Keyboard shortcuts (playbook)

| key | action |
|---|---|
| `Ctrl-K` or `/` | command palette — search every track, tool, phase and step |
| `?` | the shortcut list |
| `1` – `9` | switch track |
| `0` | overview |
| `e` / `c` | expand / collapse every phase |
| `t` | start or pause the timer |
| `n` | notes, credentials and attempts |
| `Esc` | close a tool or the palette |

Shortcuts are ignored while you are typing in a field. The arsenal uses `/` and `Ctrl-K`
to focus its search, and `Esc` to clear it.

The current view lives in the URL — `playbook.html#track=ad`, `#tool=writeup` — so it can
be linked and bookmarked, and a reload puts you back where you were.

## Running it online

**https://aardwolfsecurityltd.github.io/CTF-Toolkit/**

The `Deploy to GitHub Pages` workflow publishes the repo root as a static site, so the
launcher, playbook, arsenal and cheat sheet are browsable without cloning.

Pages has to be turned on once by a repo admin — `GITHUB_TOKEN` isn't allowed to create the
site itself, so `configure-pages`' `enablement` option fails with "Resource not accessible by
integration". Either **Settings → Pages → Source: GitHub Actions**, or:

```
gh api -X POST repos/OWNER/REPO/pages -f build_type=workflow
```

The shell scripts obviously only run locally.

## Notes

- Authorised testing only. Where a tool or technique is off-limits on a certification exam
  (sqlmap, automated exploitation, Metasploit beyond the permitted box) the playbook flags it.
- The web commands use the machine name once you set the Domain field (i.e. what you added to
  /etc/hosts); otherwise they use the IP.
- The exploit suggester is triage, not a live vulnerability oracle: it routes you to the
  authoritative sources and flags well-known candidates. Confirm patch levels before acting.
- `enum.sh` prints every command before running it, which means it assembles commands as
  strings and runs them via `bash -c`. Targets and hostnames are validated against a strict
  character allowlist first, so a target containing shell metacharacters is refused rather
  than executed. The same allowlist is applied to any hostname the playbook parses out of a
  scan you paste in, for the same reason.
- `arsenal.html` and `cheatsheet.html` are generated. `./build-arsenal.sh` and
  `./build-cheatsheet.sh` reproduce the committed pages byte-for-byte, and CI checks it.
  Edit the generator, never the generated page.
- The arsenal builds from an upstream commit pinned in `build-arsenal.sh`. That keeps the
  build reproducible; a weekly `Arsenal drift` workflow checks for new upstream commands and
  opens a pull request. To refresh by hand: `./build-arsenal.sh --latest`.

## Versions

`v1.8.0`. The version shows in the nav bar of every page, so you can tell whether an
offline copy is current. Tagging `v*` builds an offline zip and attaches it to the release;
the repo does not carry a bundle that can go stale.

Pages were renamed in v1.1.0 to drop the exam-specific prefix (`oscp-playbook.html` →
`playbook.html`, and so on). The old paths are redirect stubs, so links published before
the rename still work.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The shell scripts are shellcheck-clean and CI
enforces it, and `node --test tests/*.test.mjs` runs the page tests.

## Licence

MIT — see [LICENSE](LICENSE). The command set in `arsenal.html` is generated from the
[Orange Cyberdefense arsenal](https://github.com/Orange-Cyberdefense/arsenal), which carries
its own licence.

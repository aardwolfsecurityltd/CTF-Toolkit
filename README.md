# Pentest toolkit (OSCP / CTF)

An offline, browser-and-shell toolkit for authorised penetration testing and OSCP/CTF practice.
Everything runs locally. No data leaves the machine.

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
  goes stale. Usage: `./build-arsenal.sh`

## Setup

```
chmod +x oscp-enum.sh build-arsenal.sh
```

Open index.html in a browser. If the exploit suggester's live NVD lookup is blocked by the
browser on a local file (CORS), serve the folder instead:

```
python3 -m http.server 8000    # then open http://localhost:8000
```

## Notes

- Authorised testing only. Where a tool or technique is off-limits on the OSCP exam
  (sqlmap, automated exploitation, Metasploit beyond the permitted box) the playbook flags it.
- The web commands use the machine name once you set the Domain field (i.e. what you added to
  /etc/hosts); otherwise they use the IP.
- The exploit suggester is triage, not a live vulnerability oracle: it routes you to the
  authoritative sources and flags well-known candidates. Confirm patch levels before acting.

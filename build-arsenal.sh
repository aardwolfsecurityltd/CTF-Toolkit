#!/usr/bin/env bash
###############################################################################
# build-arsenal.sh
# Regenerate arsenal.html from the Orange Cyberdefense arsenal repo.
#
#   ./build-arsenal.sh [output.html]     build from the pinned commit
#   ./build-arsenal.sh --latest [out]    build from upstream master and move the pin
#
# The upstream commit is PINNED below. That is what makes the committed page
# reproducible: without a pin, CI would go red whenever upstream pushed
# anything at all, on a pull request that had nothing to do with it. Refreshing
# the command set is a deliberate act -- run with --latest, review the diff, and
# commit both the new pin and the regenerated page.
#
# Needs: git, python3. Clones into a temp dir and cleans up after itself.
###############################################################################
set -euo pipefail

# Pinned upstream commit. Updated by --latest; do not edit by hand.
ARSENAL_COMMIT="7fc3af8e0575c1247bf1cea8e5405b18e2154359"
ARSENAL_REPO="https://github.com/Orange-Cyberdefense/arsenal.git"

for tool in git python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "[!] $tool is required but not installed."; exit 1; }
done

USE_LATEST=0
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --latest)  USE_LATEST=1; shift ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
        -*)        echo "Unknown option: $1"; exit 1 ;;
        *)         ARGS+=("$1"); shift ;;
    esac
done

OUT="${ARGS[0]:-arsenal.html}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[*] Cloning Orange Cyberdefense arsenal..."
if [[ $USE_LATEST -eq 1 ]]; then
    if ! git clone --depth 1 --quiet "$ARSENAL_REPO" "$TMP/arsenal"; then
        echo "[!] Clone failed. Check network access to github.com and try again."
        exit 1
    fi
    NEW_COMMIT="$(git -C "$TMP/arsenal" rev-parse HEAD)"
    if [[ "$NEW_COMMIT" != "$ARSENAL_COMMIT" ]]; then
        echo "[*] Moving the pin: $ARSENAL_COMMIT -> $NEW_COMMIT"
        # Rewrite our own pin line, then carry on with this build.
        tmpf="$(mktemp)"
        sed "s|^ARSENAL_COMMIT=\".*\"|ARSENAL_COMMIT=\"$NEW_COMMIT\"|" "$0" > "$tmpf"
        cat "$tmpf" > "$0"
        rm -f "$tmpf"
        ARSENAL_COMMIT="$NEW_COMMIT"
    else
        echo "[*] Already at the newest upstream commit."
    fi
else
    # A pinned build needs history, so fetch just the one commit we want.
    mkdir -p "$TMP/arsenal"
    git -C "$TMP/arsenal" init --quiet
    git -C "$TMP/arsenal" remote add origin "$ARSENAL_REPO"
    if ! git -C "$TMP/arsenal" fetch --depth 1 --quiet origin "$ARSENAL_COMMIT"; then
        echo "[!] Could not fetch pinned commit $ARSENAL_COMMIT."
        echo "    Upstream may have rewritten history. Re-run with --latest to move the pin."
        exit 1
    fi
    git -C "$TMP/arsenal" checkout --quiet FETCH_HEAD
fi
echo "[*] Upstream commit: $ARSENAL_COMMIT"

CHEATS="$TMP/arsenal/arsenal/data/cheats"
[ -d "$CHEATS" ] || CHEATS="$(find "$TMP/arsenal" -type d -name cheats -print -quit)"
[ -d "$CHEATS" ] || { echo "[!] Could not find the cheats directory in the repo."; exit 1; }

echo "[*] Parsing and building $OUT ..."
CHEATS="$CHEATS" OUT="$OUT" python3 - <<'PYEOF'
import os, re, json, html

ROOT = os.environ["CHEATS"]
OUT  = os.environ["OUT"]

SECTION_NAMES = {
    "Active_directory":"Active Directory","Password cracking":"Password Cracking",
    "Password extraction":"Password Extraction","SQL Injection":"SQL Injection",
    "Race Condition":"Race Condition","ReverseShell":"Reverse Shell",
}
SECTION_ORDER = ["Scan","Protocol","Web","SQL Injection","Deserialization","BruteForce",
    "Password Cracking","Reverse Shell","Metasploit","Active Directory","Windows","Linux",
    "Password Extraction","Network","Services","Tools","Language","Databases","Archive",
    "Crypto","Files","Install","Pwn","Wifi","Cloud","Flashrom","Race Condition"]
def sec_key(s): return (SECTION_ORDER.index(s) if s in SECTION_ORDER else len(SECTION_ORDER), s)

CAT_META = {
 "RECON":("Recon","#38bdf8","find hosts, ports, users, shares before you touch anything"),
 "ATTACK":("Attack","#fb7185","brute force, spray, coerce, or actively exploit a service"),
 "EXPLOIT":("Exploit","#f43f5e","run a specific exploit to gain code execution"),
 "POSTEXPLOIT":("Post-exploit","#fbbf24","after a shell: dump creds, harvest, enumerate from inside"),
 "PRIVESC":("Priv-esc","#c084fc","escalate from user to root/SYSTEM/domain admin"),
 "PIVOT":("Pivot","#60a5fa","tunnel and move laterally deeper into the network"),
 "PERSIST":("Persist","#f472b6","keep your access across reboots and logouts"),
 "CONNECT":("Connect","#34d399","open a session to a service you already have creds for"),
 "UTILS":("Utility","#94a3b8","supporting plumbing: servers, transfers, encoding"),
 "CODE":("Code","#a3a3a3","compile or build something you will run on target"),
 "MISC":("Misc","#6b7280","everything else, mostly handy one-liners"),
}
CAT_ORDER = ["RECON","ATTACK","EXPLOIT","POSTEXPLOIT","PRIVESC","PIVOT","PERSIST","CONNECT","UTILS","CODE","MISC"]

entries=[]
for dirpath,_,files in os.walk(ROOT):
    for f in files:
        if not f.endswith(".md") or f in ("README.md","arsenal.md"): continue
        rel=os.path.relpath(os.path.join(dirpath,f),ROOT).split(os.sep)
        section=SECTION_NAMES.get(rel[0],rel[0].replace("_"," "))
        tool=os.path.splitext(f)[0]
        with open(os.path.join(dirpath,f),encoding="utf-8",errors="replace") as fh:
            lines=fh.read().splitlines()
        i=0
        while i<len(lines):
            if lines[i].startswith("## "):
                cur={"section":section,"tool":tool,"desc":lines[i][3:].strip(),"tags":[],"cmd":""}
                j=i+1; cmd=[]
                while j<len(lines):
                    l=lines[j]
                    if l.startswith("## "): break
                    if l.startswith("#") and not l.startswith("## ") and "/" in l:
                        cur["tags"]+=re.findall(r"#([a-zA-Z0-9_]+/[^\s#]+)",l)
                    elif l.strip().startswith("```"):
                        j+=1
                        while j<len(lines) and not lines[j].strip().startswith("```"): cmd.append(lines[j]); j+=1
                    j+=1
                cur["cmd"]="\n".join(cmd).strip()
                if cur["cmd"]: entries.append(cur)
                i=j; continue
            i+=1

def field(tags,pre): return [t.split("/",1)[1] for t in tags if t.startswith(pre+"/")]
for e in entries:
    cats=field(e["tags"],"cat")
    e["cats"]=cats
    e["cat"]=cats[0].split("/")[0] if cats else "MISC"
    e["ports"]=field(e["tags"],"port"); e["protocols"]=field(e["tags"],"protocol")
    e["platforms"]=field(e["tags"],"plateform")+field(e["tags"],"platform")

entries.sort(key=lambda e:(sec_key(e["section"]),e["tool"].lower(),e["desc"].lower()))
esc=lambda s: html.escape(s or "",quote=True)
from collections import Counter
cc=Counter(e["cat"] for e in entries)
sc=Counter(e["section"] for e in entries)

rows=[]; cur=None
for e in entries:
    if e["section"]!=cur:
        cur=e["section"]; n=sc[cur]
        rows.append(f'<h2 class="group" data-section="{esc(cur)}"><span class="group-name">{esc(cur)}</span><span class="group-count">{n}</span></h2>')
    label,colour,_=CAT_META.get(e["cat"],CAT_META["MISC"])
    blob=" ".join([e["desc"],e["cmd"],e["tool"],e["section"],e["cat"]," ".join(e["cats"][:1]),
                   " ".join(e["protocols"]),
                   " ".join("port:"+p+" "+p for p in e["ports"]),
                   " ".join(e["platforms"])]).lower()
    badges=[f'<span class="badge cat" style="--c:{colour}">{esc(label)}</span>',f'<span class="badge tool">{esc(e["tool"])}</span>']
    for p in e["ports"]: badges.append(f'<span class="badge port">:{esc(p)}</span>')
    for pr in e["protocols"]: badges.append(f'<span class="badge proto">{esc(pr)}</span>')
    for pl in e["platforms"]: badges.append(f'<span class="badge plat">{esc(pl)}</span>')
    rows.append(f'<div class="cmd" data-cat="{esc(e["cat"])}" data-section="{esc(e["section"])}" data-search="{esc(blob)}" style="--c:{colour}">'
        f'<div class="desc">{esc(e["desc"])}</div><div class="line"><code>{esc(e["cmd"])}</code>'
        f'<button class="copy" aria-label="Copy command" title="Copy">copy</button></div><div class="meta">{"".join(badges)}</div></div>')

chips=['<button class="chip active" data-cat="ALL">all <span class="n">%d</span></button>'%len(entries)]
for c in CAT_ORDER:
    if cc.get(c):
        label,colour,_=CAT_META[c]
        chips.append(f'<button class="chip" data-cat="{c}" style="--c:{colour}">{esc(label)} <span class="n">{cc[c]}</span></button>')
seen=[]
for e in entries:
    if e["section"] not in seen: seen.append(e["section"])
seen.sort(key=sec_key)
opts=['<option value="ALL">All sections</option>']+[f'<option value="{esc(s)}">{esc(s)} ({sc[s]})</option>' for s in seen]
legend="\n".join(f'<div class="leg"><span class="dot" style="background:{CAT_META[c][1]}"></span><span class="leg-label">{esc(CAT_META[c][0])}</span><span class="leg-mean">{esc(CAT_META[c][2])}</span></div>' for c in CAT_ORDER if cc.get(c))

# The page template. Kept byte-identical to the shipped arsenal.html so
# that rebuilding does not quietly restyle the page -- see CONTRIBUTING.md.
TPL=r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Arsenal reference</title>
<meta name="description" content="Over a thousand penetration-testing commands from the Orange Cyberdefense arsenal, searchable and colour-coded by engagement phase. Fills in your target variables and runs entirely offline.">
<meta name="theme-color" content="#0f1319">
<meta property="og:type" content="website">
<meta property="og:title" content="Arsenal reference — pentest toolkit">
<meta property="og:description" content="Over a thousand commands, searchable and colour-coded by engagement phase, with your target variables filled in.">
<link rel="icon" href="data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%2032%2032%22%3E%3Crect%20width%3D%2232%22%20height%3D%2232%22%20rx%3D%227%22%20fill%3D%22%230f1319%22%2F%3E%3Cpath%20d%3D%22M9%2011l5%205-5%205%22%20fill%3D%22none%22%20stroke%3D%22%2338bdf8%22%20stroke-width%3D%223%22%20stroke-linecap%3D%22round%22%20stroke-linejoin%3D%22round%22%2F%3E%3Cpath%20d%3D%22M18%2021h6%22%20fill%3D%22none%22%20stroke%3D%22%2338bdf8%22%20stroke-width%3D%223%22%20stroke-linecap%3D%22round%22%2F%3E%3C%2Fsvg%3E">
<style>
:root{
  --bg:#0f1319; --surface:#141a22; --elev:#1a212c; --line:#2a3342;
  --ink:#e7ebf2; --muted:#8b95a7; --faint:#7c8798;
  --accent:#5aa2ff;
  --mono:ui-monospace,"JetBrains Mono","Cascadia Code","IBM Plex Mono",Menlo,Consolas,monospace;
  --sans:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  --bar:104px;
}
*{box-sizing:border-box}
html{scroll-padding-top:calc(var(--bar) + 8px)}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:4px}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
  font-size:14px;line-height:1.5;-webkit-font-smoothing:antialiased}
a{color:var(--accent)}

/* ---- shared top nav ---- */
.topnav{display:flex;align-items:center;gap:2px;flex-wrap:wrap;padding:7px 20px;
  background:var(--surface);border-bottom:1px solid var(--line);font-family:var(--mono);font-size:12px}
.topnav a{color:var(--muted);text-decoration:none;padding:4px 10px;border-radius:6px}
.topnav a:hover{color:var(--ink);background:var(--elev)}
.topnav a[aria-current="page"]{color:var(--ink);background:var(--elev)}
.topnav .sep{flex:1}
.topnav .ver{color:var(--faint);font-size:11px;padding-right:8px}

/* ---- target variables, shared with the playbook ---- */
.vars{display:flex;flex-wrap:wrap;gap:6px;margin-top:9px;align-items:center}
.vars .vlabel{font-family:var(--mono);font-size:10.5px;color:var(--faint);letter-spacing:.4px;flex:none}
.vfield{display:flex;align-items:center;gap:5px;background:var(--surface);
  border:1px solid var(--line);border-radius:6px;padding:3px 7px;flex:1 1 120px;min-width:0}
.vfield label{font-family:var(--mono);font-size:10.5px;color:var(--faint);flex:none}
.vfield input{background:transparent;border:0;outline:0;color:var(--ink);
  font-family:var(--mono);font-size:12.5px;width:100%;min-width:0}
.vfield:focus-within{border-color:var(--accent)}
.ph{border-radius:3px;padding:0 2px}
.ph.filled{color:var(--accent);background:rgba(90,162,255,.13)}
.actions{display:flex;gap:6px;align-items:center;flex:none}
.act{font-family:var(--mono);font-size:11px;color:var(--muted);background:var(--elev);
  border:1px solid var(--line);border-radius:5px;padding:4px 9px;cursor:pointer}
.act:hover{color:var(--ink);border-color:var(--faint)}
.act.ok{color:#0b0f14;background:#34d399;border-color:#34d399}

/* ---- sticky command bar (the hero is the prompt) ---- */
.bar{position:sticky;top:0;z-index:30;background:linear-gradient(180deg,var(--bg) 70%,rgba(15,19,25,.92));
  border-bottom:1px solid var(--line);padding:14px 20px 12px}
.bar-inner{max-width:1180px;margin:0 auto}
.prompt{display:flex;align-items:center;gap:10px;background:var(--surface);
  border:1px solid var(--line);border-radius:8px;padding:11px 14px;
  transition:border-color .12s,box-shadow .12s}
.prompt:focus-within{border-color:var(--accent);box-shadow:0 0 0 3px rgba(90,162,255,.16)}
.prompt .glyph{color:var(--accent);font-family:var(--mono);font-weight:700;font-size:17px;line-height:1}
#q{flex:1;background:transparent;border:0;outline:0;color:var(--ink);
  font-family:var(--mono);font-size:15px;letter-spacing:.1px}
#q::placeholder{color:var(--faint)}
.count{font-family:var(--mono);font-size:12.5px;color:var(--muted);white-space:nowrap}
.count b{color:var(--ink)}
.kbd{font-family:var(--mono);font-size:11px;color:var(--faint);border:1px solid var(--line);
  border-radius:4px;padding:1px 5px}

.controls{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-top:10px}
.chips{display:flex;flex-wrap:wrap;gap:6px;flex:1;min-width:0}
.chip{font-family:var(--mono);font-size:12px;color:var(--muted);background:transparent;
  border:1px solid var(--line);border-radius:999px;padding:4px 11px;cursor:pointer;
  display:inline-flex;align-items:center;gap:6px;transition:.12s}
.chip .n{color:var(--faint);font-size:11px}
.chip:hover{color:var(--ink);border-color:var(--faint)}
.chip.active{color:var(--bg);background:var(--ink);border-color:var(--ink);font-weight:600}
.chip[data-cat]:not([data-cat="ALL"]).active{background:var(--c);border-color:var(--c);color:#0b0f14}
.chip[data-cat]:not([data-cat="ALL"]).active .n{color:rgba(11,15,20,.6)}
select{font-family:var(--mono);font-size:12px;color:var(--ink);background:var(--surface);
  border:1px solid var(--line);border-radius:6px;padding:5px 8px;cursor:pointer}

/* ---- legend ---- */
details.legend{max-width:1180px;margin:12px auto 0;padding:0 20px}
details.legend>summary{cursor:pointer;color:var(--muted);font-size:12.5px;
  font-family:var(--mono);list-style:none;user-select:none;display:inline-flex;gap:6px;align-items:center}
details.legend>summary::-webkit-details-marker{display:none}
details.legend>summary::before{content:"+";color:var(--accent);font-weight:700}
details.legend[open]>summary::before{content:"\2212"}
.legend-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));
  gap:6px 22px;margin-top:12px}
.leg{display:flex;align-items:baseline;gap:9px;font-size:12.5px}
.leg .dot{width:9px;height:9px;border-radius:50%;flex:none;position:relative;top:1px}
.leg-label{font-family:var(--mono);color:var(--ink);min-width:96px}
.leg-mean{color:var(--muted)}

/* ---- list ---- */
main{max-width:1180px;margin:0 auto;padding:8px 20px 120px}
.group{position:sticky;top:var(--bar);z-index:10;margin:26px 0 2px;
  padding:7px 0 7px;background:var(--bg);
  border-bottom:1px solid var(--line);
  font-family:var(--mono);font-size:12.5px;font-weight:600;letter-spacing:.4px;
  color:var(--muted);display:flex;align-items:center;gap:10px}
.group-name{color:var(--ink)}
.group-count{color:var(--faint);font-weight:400}

.cmd{border-left:2px solid var(--c);padding:11px 0 11px 14px;
  border-bottom:1px solid rgba(42,51,66,.5)}
.cmd .desc{color:var(--ink);font-size:13.5px;margin-bottom:6px;max-width:74ch}
.line{display:flex;align-items:flex-start;gap:10px;background:var(--surface);
  border:1px solid var(--line);border-radius:6px;padding:9px 11px}
.line code{font-family:var(--mono);font-size:13px;color:#d7e3f4;white-space:pre-wrap;
  word-break:break-word;flex:1;line-height:1.55}
.copy{flex:none;font-family:var(--mono);font-size:11px;color:var(--muted);
  background:var(--elev);border:1px solid var(--line);border-radius:5px;
  padding:3px 9px;cursor:pointer;transition:.12s}
.copy:hover{color:var(--ink);border-color:var(--faint)}
.copy.ok{color:#0b0f14;background:#34d399;border-color:#34d399}
.meta{display:flex;flex-wrap:wrap;gap:6px;margin-top:7px}
.badge{font-family:var(--mono);font-size:10.5px;padding:1.5px 7px;border-radius:4px;
  border:1px solid var(--line);color:var(--muted);letter-spacing:.2px}
.badge.cat{color:var(--c);border-color:color-mix(in srgb,var(--c) 45%,var(--line))}
.badge.port{color:#cbd5e1}
.badge.proto,.badge.plat{color:var(--muted)}

.empty{display:none;text-align:center;color:var(--muted);padding:80px 20px;
  font-family:var(--mono);font-size:13px}
.empty.show{display:block}
.hidden{display:none!important}

@media (max-width:620px){
  :root{--bar:150px}
  .line{flex-direction:column;gap:8px}
  .copy{align-self:flex-start}
  .cmd .desc{max-width:none}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>
</head>
<body>

<nav class="topnav" aria-label="Toolkit">
  <a href="index.html">launcher</a>
  <a href="playbook.html">playbook</a>
  <a href="arsenal.html" aria-current="page">arsenal</a>
  <a href="cheatsheet.html">cheat sheet</a>
  <span class="sep"></span>
  <span class="ver">v1.4.2</span>
</nav>

<div class="bar">
  <div class="bar-inner">
    <label class="prompt">
      <span class="glyph">&#10095;</span>
      <input id="q" type="text" autocomplete="off" spellcheck="false"
        placeholder="search __N__ commands:  kerberoast &middot; port 445 &middot; privesc &middot; reverse shell">
      <span class="count"><b id="shown">__N__</b> / __N__</span>
      <span class="kbd">/</span>
    </label>
    <div class="controls">
      <div class="chips" id="chips">
        __CHIPS__
      </div>
      <select id="section" aria-label="Filter by section">
        __OPTS__
      </select>
    </div>
    <div class="vars">
      <span class="vlabel">fill</span>
      <div class="vfield"><label for="v_IP">IP</label><input id="v_IP" placeholder="10.10.10.10" autocomplete="off"></div>
      <div class="vfield"><label for="v_DOMAIN">DOMAIN</label><input id="v_DOMAIN" placeholder="box.local" autocomplete="off"></div>
      <div class="vfield"><label for="v_USER">USER</label><input id="v_USER" placeholder="user" autocomplete="off"></div>
      <div class="vfield"><label for="v_PASS">PASS</label><input id="v_PASS" placeholder="pass" autocomplete="off"></div>
      <div class="vfield"><label for="v_LHOST">LHOST</label><input id="v_LHOST" placeholder="tun0 IP" autocomplete="off"></div>
      <div class="vfield"><label for="v_LPORT">LPORT</label><input id="v_LPORT" placeholder="443" autocomplete="off"></div>
      <div class="actions">
        <button class="act" id="copyVisible" type="button" title="Copy every command currently shown, as a shell script">copy visible</button>
        <button class="act" id="clearAll" type="button" title="Clear the search, phase and section filters">clear</button>
      </div>
    </div>
  </div>
</div>

<details class="legend">
  <summary>what the phase colours mean</summary>
  <div class="legend-grid">
    __LEGEND__
  </div>
</details>

<main id="list">
  __ROWS__
  <div class="empty" id="empty">no commands match. clear the search or pick a different phase.</div>
</main>

<script>
(function(){
  const q = document.getElementById('q');
  const shown = document.getElementById('shown');
  const empty = document.getElementById('empty');
  const cmds = Array.from(document.querySelectorAll('.cmd'));
  const groups = Array.from(document.querySelectorAll('.group'));
  const chips = Array.from(document.querySelectorAll('.chip'));
  const sectionSel = document.getElementById('section');

  let cat = 'ALL', section = 'ALL', term = '';

  /* ---- target variables, shared with the playbook ----
     The playbook writes toolkit:vars; reading it here means a command copied
     out of the arsenal is filled in the same way, instead of still carrying
     <ip> and <user> for you to edit by hand. */
  const VAR_KEYS = ['IP','DOMAIN','USER','PASS','LHOST','LPORT'];
  const PLACEHOLDERS = {
    ip:'IP', target:'IP', rhost:'IP', dc_ip:'IP', 'dc-ip':'IP',
    domain:'DOMAIN', domain_name:'DOMAIN', dc_fqdn:'DOMAIN', fqdn:'DOMAIN', host:'DOMAIN',
    user:'USER', username:'USER',
    password:'PASS', pass:'PASS',
    lhost:'LHOST', lport:'LPORT'
  };
  let VARS = {};
  function loadVars(){
    try{ VARS = JSON.parse(localStorage.getItem('toolkit:vars') || '{}') || {}; }catch(_){ VARS = {}; }
    VAR_KEYS.forEach(k=>{ const el = document.getElementById('v_'+k); if(el) el.value = VARS[k] || ''; });
  }
  function saveVars(){
    try{
      const cur = JSON.parse(localStorage.getItem('toolkit:vars') || '{}') || {};
      localStorage.setItem('toolkit:vars', JSON.stringify(Object.assign(cur, VARS)));
    }catch(_){ /* private window: substitution still works for this session */ }
  }

  /* Keep the original text so the page can be re-filled when a value changes. */
  const codes = cmds.map(el => el.querySelector('code'));
  const raws  = codes.map(el => el.textContent);
  const PH_RE = /<([a-z_][a-z0-9_-]{0,24})>/gi;

  function fillOne(el, raw){
    let any = false;
    const frag = document.createDocumentFragment();
    let last = 0, m;
    PH_RE.lastIndex = 0;
    while((m = PH_RE.exec(raw)) !== null){
      const key = PLACEHOLDERS[m[1].toLowerCase()];
      const val = key ? (VARS[key] || '') : '';
      if(!val) continue;
      if(m.index > last) frag.appendChild(document.createTextNode(raw.slice(last, m.index)));
      const sp = document.createElement('span');
      sp.className = 'ph filled';
      sp.textContent = val;
      frag.appendChild(sp);
      last = m.index + m[0].length;
      any = true;
    }
    if(!any) return false;
    if(last < raw.length) frag.appendChild(document.createTextNode(raw.slice(last)));
    el.textContent = '';
    el.appendChild(frag);
    return true;
  }
  function fillAll(){
    codes.forEach((el, i) => { if(!fillOne(el, raws[i])) el.textContent = raws[i]; });
  }

  VAR_KEYS.forEach(k=>{
    const el = document.getElementById('v_'+k);
    if(!el) return;
    el.addEventListener('input', ()=>{ VARS[k] = el.value.trim(); saveVars(); fillAll(); });
  });

  /* ---- filter state also lives in the URL, so a filtered view can be shared ---- */
  function syncUrl(){
    const p = new URLSearchParams();
    if(term) p.set('q', term);
    if(cat !== 'ALL') p.set('cat', cat);
    if(section !== 'ALL') p.set('section', section);
    const qs = p.toString();
    const url = location.pathname + (qs ? '?' + qs : '');
    try{ history.replaceState(null, '', url); }catch(_){}
  }

  function apply(){
    const words = term.split(/\s+/).filter(Boolean);
    let vis = 0;
    for(const el of cmds){
      let ok = true;
      if(cat !== 'ALL' && el.dataset.cat !== cat) ok = false;
      if(ok && section !== 'ALL' && el.dataset.section !== section) ok = false;
      if(ok && words.length){
        const hay = el.dataset.search;
        for(const w of words){ if(!hay.includes(w)){ ok = false; break; } }
      }
      el.classList.toggle('hidden', !ok);
      if(ok) vis++;
    }
    // hide group headers whose section has no visible rows
    for(const g of groups){
      let n = g.nextElementSibling, any = false;
      while(n && !n.classList.contains('group')){
        if(n.classList.contains('cmd') && !n.classList.contains('hidden')){ any = true; break; }
        n = n.nextElementSibling;
      }
      g.classList.toggle('hidden', !any);
    }
    shown.textContent = vis;
    empty.classList.toggle('show', vis === 0);
    syncUrl();
  }

  q.addEventListener('input', ()=>{ term = q.value.trim().toLowerCase(); apply(); });

  chips.forEach(c=>c.addEventListener('click', ()=>{
    chips.forEach(x=>x.classList.remove('active'));
    c.classList.add('active');
    cat = c.dataset.cat;
    apply();
  }));

  sectionSel.addEventListener('change', ()=>{ section = sectionSel.value; apply(); });

  document.getElementById('clearAll').addEventListener('click', ()=>{
    q.value = ''; term = '';
    section = 'ALL'; sectionSel.value = 'ALL';
    cat = 'ALL';
    chips.forEach(x=>x.classList.toggle('active', x.dataset.cat === 'ALL'));
    apply(); q.focus();
  });

  function flash(btn, text){
    const old = btn.textContent;
    btn.textContent = text; btn.classList.add('ok');
    setTimeout(()=>{ btn.textContent = old; btn.classList.remove('ok'); }, 1100);
  }
  async function toClipboard(text, btn, label){
    try{ await navigator.clipboard.writeText(text); }
    catch(_){ const t=document.createElement('textarea'); t.value=text;
      document.body.appendChild(t); t.select(); document.execCommand('copy'); t.remove(); }
    flash(btn, label);
  }

  /* copy every command currently on screen, as a runnable script */
  document.getElementById('copyVisible').addEventListener('click', function(){
    const lines = cmds.filter(el => !el.classList.contains('hidden'))
      .map(el => {
        const desc = el.querySelector('.desc').textContent;
        const code = el.querySelector('code').textContent;
        return '# ' + desc + '\n' + code;
      });
    if(!lines.length){ flash(this, 'nothing shown'); return; }
    if(lines.length > 200 && !confirm(lines.length + ' commands are shown. Copy all of them?')) return;
    const head = '#!/usr/bin/env bash\n# from the arsenal reference'
      + (term ? ' - search: ' + term : '')
      + (cat !== 'ALL' ? ' - phase: ' + cat : '')
      + (section !== 'ALL' ? ' - section: ' + section : '')
      + '\n# REVIEW BEFORE RUNNING. Placeholders still in <angle brackets> need a value.\n\n';
    toClipboard(head + lines.join('\n\n') + '\n', this, lines.length + ' copied');
  });

  // copy buttons
  document.getElementById('list').addEventListener('click', async (e)=>{
    const btn = e.target.closest('.copy');
    if(!btn) return;
    const code = btn.parentElement.querySelector('code').textContent;
    try{ await navigator.clipboard.writeText(code); }
    catch(_){ const t=document.createElement('textarea'); t.value=code;
      document.body.appendChild(t); t.select(); document.execCommand('copy'); t.remove(); }
    const old = btn.textContent; btn.textContent='copied'; btn.classList.add('ok');
    setTimeout(()=>{ btn.textContent=old; btn.classList.remove('ok'); }, 1100);
  });

  // keyboard: "/" focus, Esc clear
  document.addEventListener('keydown', (e)=>{
    if((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k'){ e.preventDefault(); q.focus(); q.select(); return; }
    if(e.key === '/' && !/^(INPUT|TEXTAREA|SELECT)$/.test((document.activeElement||{}).tagName || '')){
      e.preventDefault(); q.focus();
    }
    else if(e.key === 'Escape' && document.activeElement === q){
      q.value=''; term=''; apply(); q.blur();
    }
  });

  /* deep link: arsenal.html?q=smb&cat=RECON pre-fills search and filters
     (the playbook cross-links use ?q=) */
  try{
    const p = new URLSearchParams(location.search);
    const qp = p.get('q');
    if(qp){ q.value = qp; term = qp.trim().toLowerCase(); }
    const cp = p.get('cat');
    if(cp && chips.some(c=>c.dataset.cat === cp)){
      cat = cp;
      chips.forEach(x=>x.classList.toggle('active', x.dataset.cat === cp));
    }
    const sp = p.get('section');
    if(sp && [...sectionSel.options].some(o=>o.value === sp)){ section = sp; sectionSel.value = sp; }
  }catch(_){}

  loadVars();
  fillAll();
  apply();
})();
</script>
</body>
</html>
"""

out=(TPL.replace("__CHIPS__","\n".join(chips)).replace("__OPTS__","\n".join(opts))
        .replace("__LEGEND__",legend).replace("__ROWS__","\n".join(rows)).replace("__N__",str(len(entries))))
with open(OUT,"w",encoding="utf-8") as fh:
    fh.write(out)
print("[+] %d commands written to %s" % (len(entries),OUT))
PYEOF

echo "[+] Done."

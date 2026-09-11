#!/usr/bin/env bash
###############################################################################
# build-arsenal.sh
# Regenerate oscp-arsenal.html from the current Orange Cyberdefense arsenal repo.
# Run this whenever you want to refresh the command set (they add commands often).
#
#   ./build-arsenal.sh [output.html]
#
# Needs: git, python3. Clones into a temp dir and cleans up after itself.
###############################################################################
set -euo pipefail

for tool in git python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "[!] $tool is required but not installed."; exit 1; }
done

OUT="${1:-oscp-arsenal.html}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[*] Cloning Orange Cyberdefense arsenal..."
if ! git clone --depth 1 --quiet \
        https://github.com/Orange-Cyberdefense/arsenal.git "$TMP/arsenal"; then
    echo "[!] Clone failed. Check network access to github.com and try again."
    exit 1
fi

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
        rows.append(f'<h2 class="group"><span class="group-name">{esc(cur)}</span><span class="group-count">{n}</span></h2>')
    label,colour,_=CAT_META.get(e["cat"],CAT_META["MISC"])
    blob=" ".join([e["desc"],e["cmd"],e["tool"],e["section"],e["cat"]," ".join(e["protocols"]),
                   " ".join("port:"+p+" "+p for p in e["ports"])]).lower()
    badges=[f'<span class="badge cat" style="--c:{colour}">{esc(label)}</span>',f'<span class="badge tool">{esc(e["tool"])}</span>']
    for p in e["ports"]: badges.append(f'<span class="badge port">:{esc(p)}</span>')
    for pr in e["protocols"]: badges.append(f'<span class="badge proto">{esc(pr)}</span>')
    rows.append(f'<div class="cmd" data-cat="{esc(e["cat"])}" data-section="{esc(e["section"])}" data-search="{esc(blob)}" style="--c:{colour}">'
        f'<div class="desc">{esc(e["desc"])}</div><div class="line"><code>{esc(e["cmd"])}</code>'
        f'<button class="copy" aria-label="Copy command">copy</button></div><div class="meta">{"".join(badges)}</div></div>')

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

# CSS/JS identical in spirit to the shipped page
TPL=r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Arsenal reference</title>
<style>
:root{--bg:#0f1319;--surface:#141a22;--elev:#1a212c;--line:#2a3342;--ink:#e7ebf2;--muted:#8b95a7;--faint:#5c6678;--accent:#5aa2ff;
--mono:ui-monospace,"JetBrains Mono","Cascadia Code","IBM Plex Mono",Menlo,Consolas,monospace;--sans:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;--bar:104px}
*{box-sizing:border-box}html{scroll-padding-top:calc(var(--bar) + 8px)}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);font-size:14px;line-height:1.5}
.bar{position:sticky;top:0;z-index:30;background:var(--bg);border-bottom:1px solid var(--line);padding:14px 20px}
.bar-inner{max-width:1180px;margin:0 auto}
.prompt{display:flex;align-items:center;gap:10px;background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:11px 14px}
.prompt:focus-within{border-color:var(--accent);box-shadow:0 0 0 3px rgba(90,162,255,.16)}
.prompt .glyph{color:var(--accent);font-family:var(--mono);font-weight:700;font-size:17px}
#q{flex:1;background:transparent;border:0;outline:0;color:var(--ink);font-family:var(--mono);font-size:15px}
.count{font-family:var(--mono);font-size:12.5px;color:var(--muted);white-space:nowrap}.count b{color:var(--ink)}
.kbd{font-family:var(--mono);font-size:11px;color:var(--faint);border:1px solid var(--line);border-radius:4px;padding:1px 5px}
.controls{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-top:10px}
.chips{display:flex;flex-wrap:wrap;gap:6px;flex:1;min-width:0}
.chip{font-family:var(--mono);font-size:12px;color:var(--muted);background:transparent;border:1px solid var(--line);border-radius:999px;padding:4px 11px;cursor:pointer;display:inline-flex;align-items:center;gap:6px}
.chip .n{color:var(--faint);font-size:11px}.chip:hover{color:var(--ink);border-color:var(--faint)}
.chip.active{color:var(--bg);background:var(--ink);border-color:var(--ink);font-weight:600}
.chip[data-cat]:not([data-cat="ALL"]).active{background:var(--c);border-color:var(--c);color:#0b0f14}
select{font-family:var(--mono);font-size:12px;color:var(--ink);background:var(--surface);border:1px solid var(--line);border-radius:6px;padding:5px 8px}
details.legend{max-width:1180px;margin:12px auto 0;padding:0 20px}
details.legend>summary{cursor:pointer;color:var(--muted);font-size:12.5px;font-family:var(--mono);list-style:none;display:inline-flex;gap:6px;align-items:center}
details.legend>summary::-webkit-details-marker{display:none}
details.legend>summary::before{content:"+";color:var(--accent);font-weight:700}details.legend[open]>summary::before{content:"\2212"}
.legend-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:6px 22px;margin-top:12px}
.leg{display:flex;align-items:baseline;gap:9px;font-size:12.5px}.leg .dot{width:9px;height:9px;border-radius:50%;flex:none;position:relative;top:1px}
.leg-label{font-family:var(--mono);color:var(--ink);min-width:96px}.leg-mean{color:var(--muted)}
main{max-width:1180px;margin:0 auto;padding:8px 20px 120px}
.group{position:sticky;top:var(--bar);z-index:10;margin:26px 0 2px;padding:7px 0;background:var(--bg);border-bottom:1px solid var(--line);font-family:var(--mono);font-size:12.5px;font-weight:600;color:var(--muted);display:flex;gap:10px}
.group-name{color:var(--ink)}.group-count{color:var(--faint);font-weight:400}
.cmd{border-left:2px solid var(--c);padding:11px 0 11px 14px;border-bottom:1px solid rgba(42,51,66,.5)}
.cmd .desc{color:var(--ink);font-size:13.5px;margin-bottom:6px;max-width:74ch}
.line{display:flex;align-items:flex-start;gap:10px;background:var(--surface);border:1px solid var(--line);border-radius:6px;padding:9px 11px}
.line code{font-family:var(--mono);font-size:13px;color:#d7e3f4;white-space:pre-wrap;word-break:break-word;flex:1;line-height:1.55}
.copy{flex:none;font-family:var(--mono);font-size:11px;color:var(--muted);background:var(--elev);border:1px solid var(--line);border-radius:5px;padding:3px 9px;cursor:pointer}
.copy:hover{color:var(--ink);border-color:var(--faint)}.copy.ok{color:#0b0f14;background:#34d399;border-color:#34d399}
.meta{display:flex;flex-wrap:wrap;gap:6px;margin-top:7px}
.badge{font-family:var(--mono);font-size:10.5px;padding:1.5px 7px;border-radius:4px;border:1px solid var(--line);color:var(--muted)}
.badge.cat{color:var(--c);border-color:color-mix(in srgb,var(--c) 45%,var(--line))}.badge.port{color:#cbd5e1}
.empty{display:none;text-align:center;color:var(--muted);padding:80px 20px;font-family:var(--mono)}.empty.show{display:block}
.hidden{display:none!important}
@media (max-width:620px){:root{--bar:150px}.line{flex-direction:column;gap:8px}}
</style></head><body>
<div class="bar"><div class="bar-inner">
<label class="prompt"><span class="glyph">&#10095;</span>
<input id="q" type="text" autocomplete="off" spellcheck="false" placeholder="search __N__ commands">
<span class="count"><b id="shown">__N__</b> / __N__</span><span class="kbd">/</span></label>
<div class="controls"><div class="chips" id="chips">__CHIPS__</div><select id="section">__OPTS__</select></div>
</div></div>
<details class="legend"><summary>what the phase colours mean</summary><div class="legend-grid">__LEGEND__</div></details>
<main id="list">__ROWS__<div class="empty" id="empty">no commands match.</div></main>
<script>
(function(){const q=document.getElementById('q'),shown=document.getElementById('shown'),empty=document.getElementById('empty');
const cmds=[...document.querySelectorAll('.cmd')],groups=[...document.querySelectorAll('.group')],chips=[...document.querySelectorAll('.chip')],sectionSel=document.getElementById('section');
let cat='ALL',section='ALL',term='';
function apply(){const words=term.split(/\s+/).filter(Boolean);let vis=0;
for(const el of cmds){let ok=true;if(cat!=='ALL'&&el.dataset.cat!==cat)ok=false;
if(ok&&section!=='ALL'&&el.dataset.section!==section)ok=false;
if(ok&&words.length){const hay=el.dataset.search;for(const w of words){if(!hay.includes(w)){ok=false;break;}}}
el.classList.toggle('hidden',!ok);if(ok)vis++;}
for(const g of groups){let n=g.nextElementSibling,any=false;while(n&&!n.classList.contains('group')){if(n.classList.contains('cmd')&&!n.classList.contains('hidden')){any=true;break;}n=n.nextElementSibling;}g.classList.toggle('hidden',!any);}
shown.textContent=vis;empty.classList.toggle('show',vis===0);}
q.addEventListener('input',()=>{term=q.value.trim().toLowerCase();apply();});
chips.forEach(c=>c.addEventListener('click',()=>{chips.forEach(x=>x.classList.remove('active'));c.classList.add('active');cat=c.dataset.cat;apply();}));
sectionSel.addEventListener('change',()=>{section=sectionSel.value;apply();});
document.getElementById('list').addEventListener('click',async e=>{const b=e.target.closest('.copy');if(!b)return;
const code=b.parentElement.querySelector('code').textContent;
try{await navigator.clipboard.writeText(code);}catch(_){const t=document.createElement('textarea');t.value=code;document.body.appendChild(t);t.select();document.execCommand('copy');t.remove();}
const o=b.textContent;b.textContent='copied';b.classList.add('ok');setTimeout(()=>{b.textContent=o;b.classList.remove('ok');},1100);});
document.addEventListener('keydown',e=>{if(e.key==='/'&&document.activeElement!==q){e.preventDefault();q.focus();}else if(e.key==='Escape'&&document.activeElement===q){q.value='';term='';apply();q.blur();}});
try{const qp=new URLSearchParams(location.search).get('q');if(qp){q.value=qp;term=qp.trim().toLowerCase();apply();}}catch(_){}})();
</script></body></html>"""

out=(TPL.replace("__CHIPS__","\n".join(chips)).replace("__OPTS__","\n".join(opts))
        .replace("__LEGEND__",legend).replace("__ROWS__","\n".join(rows)).replace("__N__",str(len(entries))))
with open(OUT,"w",encoding="utf-8") as fh:
    fh.write(out)
print("[+] %d commands written to %s" % (len(entries),OUT))
PYEOF

echo "[+] Done."

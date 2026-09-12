#!/usr/bin/env bash
###############################################################################
# build-cheatsheet.sh
# Render cheatsheet.md to cheatsheet.html.
#
#   ./build-cheatsheet.sh [output.html]
#
# Why this exists: GitHub Pages serves a .md file as text/markdown, which
# browsers download rather than display. Linking the raw markdown from the
# launcher therefore looked fine locally and handed visitors a file on the
# hosted site. The generated page is committed, and CI checks it still matches
# the source, exactly as it does for the arsenal.
#
# Deliberately a tiny markdown subset (headings, fenced code, rules, lists,
# inline code and bold) rather than a dependency: that is all the cheat sheet
# uses, and the toolkit stays install-free.
#
# Needs: python3.
###############################################################################
set -euo pipefail

command -v python3 >/dev/null 2>&1 || { echo "[!] python3 is required but not installed."; exit 1; }

SRC="cheatsheet.md"
OUT="${1:-cheatsheet.html}"
[ -f "$SRC" ] || { echo "[!] $SRC not found."; exit 1; }

echo "[*] Rendering $SRC -> $OUT ..."
SRC="$SRC" OUT="$OUT" python3 - <<'PYEOF'
import os, re, html

src = open(os.environ["SRC"], encoding="utf-8").read()
OUT = os.environ["OUT"]

def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    return t

def slug(t):
    s = re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")
    return s or "section"

lines = src.splitlines()
out, toc = [], []
i, n = 0, len(lines)
para, olist, ulist = [], [], []
seen = {}

def flush_para():
    if para:
        out.append("<p>" + inline(" ".join(para)) + "</p>")
        del para[:]

def flush_lists():
    if olist:
        out.append("<ol>" + "".join("<li>" + inline(x) + "</li>" for x in olist) + "</ol>")
        del olist[:]
    if ulist:
        out.append("<ul>" + "".join("<li>" + inline(x) + "</li>" for x in ulist) + "</ul>")
        del ulist[:]

def flush_all():
    flush_para()
    flush_lists()

while i < n:
    line = lines[i]

    if line.strip().startswith("```"):
        flush_all()
        lang = line.strip()[3:].strip()
        i += 1
        body = []
        while i < n and not lines[i].strip().startswith("```"):
            body.append(lines[i]); i += 1
        i += 1
        code = html.escape("\n".join(body), quote=True)
        cls = ' class="lang-' + html.escape(lang, quote=True) + '"' if lang else ""
        out.append('<div class="block"><button class="copy" type="button" aria-label="Copy this block">copy</button>'
                   '<pre' + cls + '><code>' + code + "</code></pre></div>")
        continue

    m = re.match(r"^(#{1,4})\s+(.*)$", line)
    if m:
        flush_all()
        lvl = len(m.group(1)); text = m.group(2).strip()
        sid = slug(text)
        if sid in seen:
            seen[sid] += 1
            sid = sid + "-" + str(seen[sid])
        else:
            seen[sid] = 1
        out.append("<h%d id=\"%s\">%s</h%d>" % (lvl, sid, inline(text), lvl))
        if lvl == 2:
            toc.append((sid, text))
        i += 1
        continue

    if re.match(r"^---+\s*$", line):
        flush_all(); out.append("<hr>"); i += 1; continue

    m = re.match(r"^\s*(\d+)\.\s+(.*)$", line)
    if m:
        flush_para(); olist.append(m.group(2)); i += 1; continue

    m = re.match(r"^\s*[-*]\s+(.*)$", line)
    if m:
        flush_para(); ulist.append(m.group(1)); i += 1; continue

    if not line.strip():
        flush_all(); i += 1; continue

    flush_lists(); para.append(line.strip()); i += 1

flush_all()

TOC = "".join('<a href="#%s">%s</a>' % (sid, html.escape(t)) for sid, t in toc)
BODY = "\n".join(out)

# The page template. Committed output must match a fresh render, so keep
# changes here rather than editing cheatsheet.html by hand.
TPL = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cheat sheet</title>
<meta name="description" content="A printable syntax cheat sheet for penetration testing and CTF work, grouped by port and by phase: scanning, per-service enumeration, reverse shells, TTY upgrades, file transfer, privilege escalation and password cracking.">
<meta name="theme-color" content="#0f1319">
<meta property="og:type" content="website">
<meta property="og:title" content="Cheat sheet - pentest toolkit">
<meta property="og:description" content="Syntax quick reference grouped by port and by phase. Prints on a couple of pages.">
<link rel="icon" href="data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%2032%2032%22%3E%3Crect%20width%3D%2232%22%20height%3D%2232%22%20rx%3D%227%22%20fill%3D%22%230f1319%22%2F%3E%3Cpath%20d%3D%22M9%2011l5%205-5%205%22%20fill%3D%22none%22%20stroke%3D%22%232dd4bf%22%20stroke-width%3D%223%22%20stroke-linecap%3D%22round%22%20stroke-linejoin%3D%22round%22%2F%3E%3Cpath%20d%3D%22M18%2021h6%22%20fill%3D%22none%22%20stroke%3D%22%232dd4bf%22%20stroke-width%3D%223%22%20stroke-linecap%3D%22round%22%2F%3E%3C%2Fsvg%3E">
<style>
:root{
  --bg:#0f1319; --surface:#141a22; --elev:#1a212c; --line:#2a3342;
  --ink:#e7ebf2; --muted:#8b95a7; --faint:#7c8798; --accent:#2dd4bf;
  --mono:ui-monospace,"JetBrains Mono","Cascadia Code","IBM Plex Mono",Menlo,Consolas,monospace;
  --sans:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
}
*{box-sizing:border-box}
html{scroll-padding-top:60px}
body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
  font-size:14px;line-height:1.6;-webkit-font-smoothing:antialiased}
a{color:var(--accent)}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:4px}

.topnav{display:flex;align-items:center;gap:2px;flex-wrap:wrap;padding:7px 20px;
  background:var(--surface);border-bottom:1px solid var(--line);font-family:var(--mono);font-size:12px;
  position:sticky;top:0;z-index:20}
.topnav a{color:var(--muted);text-decoration:none;padding:4px 10px;border-radius:6px}
.topnav a:hover{color:var(--ink);background:var(--elev)}
.topnav a[aria-current="page"]{color:var(--ink);background:var(--elev)}
.topnav .sep{flex:1}
.topnav .ver{color:var(--faint);font-size:11px;padding-right:8px}
.topnav button{font-family:var(--mono);font-size:11px;color:var(--muted);background:var(--elev);
  border:1px solid var(--line);border-radius:5px;padding:3px 9px;cursor:pointer}
.topnav button:hover{color:var(--ink);border-color:var(--faint)}

.layout{max-width:1180px;margin:0 auto;padding:22px 20px 110px;display:grid;
  grid-template-columns:210px minmax(0,1fr);gap:34px;align-items:start}
.toc{position:sticky;top:64px;font-family:var(--mono);font-size:12px;display:flex;
  flex-direction:column;gap:1px;max-height:calc(100vh - 90px);overflow-y:auto}
.toc a{color:var(--muted);text-decoration:none;padding:3px 8px;border-radius:5px;border-left:2px solid transparent}
.toc a:hover{color:var(--ink);background:var(--surface)}
.toc a.active{color:var(--ink);border-left-color:var(--accent);background:var(--surface)}

article{min-width:0}
h1{font-family:var(--mono);font-size:21px;margin:0 0 6px;letter-spacing:.3px}
h2{font-family:var(--mono);font-size:15px;margin:34px 0 10px;color:var(--accent);
  border-bottom:1px solid var(--line);padding-bottom:6px;scroll-margin-top:60px}
h3{font-family:var(--mono);font-size:13px;margin:20px 0 6px;color:var(--ink)}
p{color:var(--muted);max-width:78ch;margin:8px 0}
p strong,li strong{color:var(--ink)}
ol,ul{color:var(--muted);max-width:78ch;padding-left:22px}
li{margin:4px 0}
hr{border:0;border-top:1px solid var(--line);margin:26px 0}
code{font-family:var(--mono);font-size:12.5px;color:#d7e3f4;background:var(--elev);
  border-radius:4px;padding:1px 5px}

.block{position:relative;margin:10px 0}
.block pre{background:var(--surface);border:1px solid var(--line);border-radius:8px;
  padding:12px 14px;overflow-x:auto;margin:0}
.block pre code{background:none;padding:0;font-size:12.5px;line-height:1.65;color:#d7e3f4;white-space:pre}
.block .copy{position:absolute;top:7px;right:7px;font-family:var(--mono);font-size:11px;
  color:var(--muted);background:var(--elev);border:1px solid var(--line);border-radius:5px;
  padding:3px 9px;cursor:pointer;opacity:0;transition:opacity .12s}
.block:hover .copy,.block .copy:focus-visible{opacity:1}
.block .copy.ok{opacity:1;color:#0b0f14;background:#34d399;border-color:#34d399}

@media (max-width:820px){
  .layout{grid-template-columns:1fr;gap:16px}
  .toc{position:static;max-height:none;flex-direction:row;flex-wrap:wrap;
    border-bottom:1px solid var(--line);padding-bottom:10px}
  .block .copy{opacity:1}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}

@media print{
  .topnav,.toc,.block .copy{display:none!important}
  body{background:#fff;color:#111;font-size:10.5pt}
  .layout{display:block;max-width:none;padding:0}
  a{color:#111;text-decoration:none}
  h1{font-size:16pt}
  h2{font-size:12pt;color:#111;border-bottom:1px solid #999;margin-top:16pt;break-after:avoid}
  h3{font-size:10.5pt;break-after:avoid}
  p,ol,ul,li{color:#222}
  code{background:#f0f0f0;color:#111}
  .block{break-inside:avoid;margin:6pt 0}
  .block pre{background:#f6f6f6;border:1px solid #ccc;padding:6pt 8pt}
  .block pre code{color:#111;white-space:pre-wrap}
  hr{margin:10pt 0}
}
</style>
</head>
<body>

<nav class="topnav" aria-label="Toolkit">
  <a href="index.html">launcher</a>
  <a href="playbook.html">playbook</a>
  <a href="arsenal.html">arsenal</a>
  <a href="cheatsheet.html" aria-current="page">cheat sheet</a>
  <span class="sep"></span>
  <span class="ver">v1.4.2</span>
  <button type="button" id="printBtn">print</button>
</nav>

<div class="layout">
  <nav class="toc" id="toc" aria-label="Sections">__TOC__</nav>
  <article id="doc">
__BODY__
  </article>
</div>

<script>
(function(){
  document.getElementById("printBtn").addEventListener("click",function(){window.print();});

  document.getElementById("doc").addEventListener("click",async function(e){
    var btn=e.target.closest(".copy");
    if(!btn)return;
    var code=btn.parentElement.querySelector("code").textContent;
    try{await navigator.clipboard.writeText(code);}
    catch(_){var t=document.createElement("textarea");t.value=code;
      document.body.appendChild(t);t.select();document.execCommand("copy");t.remove();}
    var old=btn.textContent;btn.textContent="copied";btn.classList.add("ok");
    setTimeout(function(){btn.textContent=old;btn.classList.remove("ok");},1100);
  });

  // highlight the section you are reading
  var links=Array.prototype.slice.call(document.querySelectorAll(".toc a"));
  var heads=links.map(function(a){return document.getElementById(a.getAttribute("href").slice(1));})
                 .filter(Boolean);
  if("IntersectionObserver" in window && heads.length){
    var io=new IntersectionObserver(function(entries){
      entries.forEach(function(en){
        if(!en.isIntersecting)return;
        links.forEach(function(a){a.classList.toggle("active",a.getAttribute("href")==="#"+en.target.id);});
      });
    },{rootMargin:"-60px 0px -75% 0px"});
    heads.forEach(function(h){io.observe(h);});
  }
})();
</script>
</body>
</html>
"""
open(OUT, "w", encoding="utf-8").write(TPL.replace("__TOC__", TOC).replace("__BODY__", BODY))
print("[+] %d sections written to %s" % (len(toc), OUT))
PYEOF

echo "[+] Done."

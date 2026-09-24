// Boot each page in a real DOM and check it renders. Needs jsdom; if it is not
// installed the tests skip rather than fail, so a clone with no npm still runs
// the rest of the suite (CI installs it).
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = f => fs.readFileSync(path.join(ROOT, f), "utf8");

let JSDOM, VirtualConsole;
try {
  ({JSDOM, VirtualConsole} = await import("jsdom"));
} catch {
  test("render tests", {skip: "jsdom not installed (npm i --no-save jsdom)"}, () => {});
}

function boot(file, url) {
  const errors = [];
  const vc = new VirtualConsole()
    .on("jsdomError", e => errors.push(e.message))
    .on("error", (...a) => errors.push(a.join(" ")));
  const dom = new JSDOM(read(file), {
    runScripts: "dangerously",
    url: url || "https://example.org/" + file,
    virtualConsole: vc,
  });
  return {dom, window: dom.window, d: dom.window.document, errors};
}

if (JSDOM) {
  test("playbook renders every track and tool without errors", () => {
    const {window, d, errors} = boot("playbook.html");
    assert.deepEqual(errors, [], "script errors on load");
    assert.equal(d.querySelectorAll("#tracks .track-pill").length, 12, "11 tracks + overview");
    assert.equal(d.querySelectorAll("#tools .track-pill").length, 8, "8 tools");
    assert.ok([...d.querySelectorAll("#tracks .track-pill")].some(p => p.dataset.id === "container"),
      "container escape track missing");
    assert.ok([...d.querySelectorAll("#tracks .track-pill")].some(p => p.dataset.id === "adcs"),
      "ADCS track missing");
    assert.ok(d.querySelector("#boxPick"), "box picker missing");
    assert.ok(d.querySelector(".empty-cta"), "first-run call to action missing");
    assert.ok(d.querySelector("#stuckLive .cue"), "stuck panel has no live cue");
    window.close();
  });

  test("playbook steps label their checkboxes", () => {
    const {window, d} = boot("playbook.html");
    const pill = [...d.querySelectorAll("#tracks .track-pill")].find(p => p.dataset.id === "linux");
    pill.dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    const steps = [...d.querySelectorAll("#phases .step")];
    assert.ok(steps.length > 5);
    for (const s of steps) {
      const cb = s.querySelector("input[type=checkbox]");
      const label = s.querySelector("label.step-desc");
      assert.ok(cb && label && label.htmlFor === cb.id, "step checkbox has no label: " + s.dataset.id);
    }
    assert.equal(window.location.hash, "#track=linux", "track did not become a deep link");
    window.close();
  });

  test("playbook command palette finds a step by its command text", () => {
    const {window, d} = boot("playbook.html");
    d.dispatchEvent(new window.KeyboardEvent("keydown", {key: "/", bubbles: true}));
    assert.equal(d.getElementById("pal").hidden, false, "palette did not open");
    const input = d.getElementById("palInput");
    input.value = "kerberoast";
    input.dispatchEvent(new window.Event("input", {bubbles: true}));
    const rows = [...d.querySelectorAll("#palList .pal-item .t")].map(e => e.textContent);
    assert.ok(rows.length > 0, "no palette results for 'kerberoast'");
    assert.ok(rows.some(r => /kerberoast/i.test(r)), "results do not mention kerberoast: " + rows.join(" | "));
    window.close();
  });

  test("box state is kept per box and survives switching", () => {
    const {window, d} = boot("playbook.html");
    const setVar = (k, v) => {
      const el = d.getElementById("v_" + k);
      el.value = v;
      el.dispatchEvent(new window.Event("input", {bubbles: true}));
    };
    const tickFirstStep = () => {
      const pill = [...d.querySelectorAll("#tracks .track-pill")].find(p => p.dataset.id === "linux");
      pill.dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
      const cb = d.querySelector("#phases .step input[type=checkbox]");
      cb.checked = true;
      cb.dispatchEvent(new window.Event("change", {bubbles: true}));
      return cb;
    };

    setVar("BOX", "alpha");
    setVar("IP", "10.10.10.1");
    tickFirstStep();
    assert.ok(window.localStorage.getItem("playbook2:alpha"), "alpha progress was not saved");

    // a second box must not inherit the first one's ticks
    setVar("BOX", "beta");
    assert.equal(d.querySelector("#phases .step input[type=checkbox]").checked, false,
      "beta started with alpha's ticks");

    // ...and going back restores them
    setVar("BOX", "alpha");
    assert.equal(d.querySelector("#phases .step input[type=checkbox]").checked, true,
      "alpha's ticks did not come back");

    const picker = d.getElementById("boxPick");
    const listed = [...picker.options].map(o => o.value);
    assert.ok(listed.includes("alpha"), "box picker does not list alpha: " + listed.join(","));
    window.close();
  });

  test("the timer records one stamp per box and pauses", () => {
    const {window, d} = boot("playbook.html");
    const box = d.getElementById("v_BOX");
    box.value = "timed";
    box.dispatchEvent(new window.Event("input", {bubbles: true}));

    const btn = d.getElementById("timerStart");
    btn.click();                                   // start
    assert.equal(btn.textContent, "pause");
    btn.click();                                   // pause
    assert.equal(btn.textContent, "resume");

    const keys = Object.keys(window.localStorage);
    const timerKeys = keys.filter(k => k.startsWith("timer2:"));
    assert.deepEqual(timerKeys, ["timer2:timed"],
      "the timer should own exactly one key per box, found: " + timerKeys.join(","));
    const v = JSON.parse(window.localStorage.getItem("timer2:timed"));
    assert.ok(v.start > 0 && v.paused > 0, "paused timer did not persist both stamps");

    // a stray "timer2:timed:paused" key would show up here as a phantom box
    const boxes = [...d.getElementById("boxPick").options].map(o => o.value);
    assert.ok(!boxes.some(b => b.includes(":")), "phantom box in the picker: " + boxes.join(","));
    window.close();
  });

  test("evidence accepts text and reports coverage in the write-up", () => {
    const {window, d} = boot("playbook.html");
    const box = d.getElementById("v_BOX");
    box.value = "ev";
    box.dispatchEvent(new window.Event("input", {bubbles: true}));

    const pill = [...d.querySelectorAll("#tracks .track-pill")].find(p => p.dataset.id === "linux");
    pill.dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    const step = d.querySelector("#phases .step");
    const cb = step.querySelector("input[type=checkbox]");
    cb.checked = true;
    cb.dispatchEvent(new window.Event("change", {bubbles: true}));

    step.querySelector(".ev-btn").click();
    const ta = step.querySelector(".ev-ta");
    assert.ok(ta, "evidence textarea did not open");
    ta.value = "root@kali:~# id\nuid=0(root)";
    ta.dispatchEvent(new window.Event("input", {bubbles: true}));

    const stored = JSON.parse(window.localStorage.getItem("evidence2:ev"));
    const entry = stored[step.dataset.id];
    assert.equal(entry.text, "root@kali:~# id\nuid=0(root)");
    assert.deepEqual(entry.shots, [], "shots should start empty");

    // the write-up view should now count one step with evidence
    [...d.querySelectorAll("#tools .track-pill")].find(p => p.dataset.id === "__writeup")
      .dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    const gap = d.querySelector(".wu-gap").textContent;
    assert.match(gap, /1 steps ticked, 1 with evidence/);
    assert.match(d.querySelector(".wu-preview").textContent, /uid=0\(root\)/);
    window.close();
  });

  test("arsenal applies a deep-linked filter and fills target variables", () => {
    const {window, d, errors} = boot("arsenal.html", "https://example.org/arsenal.html?q=kerberoast");
    assert.deepEqual(errors, [], "script errors on load");
    const total = d.querySelectorAll(".cmd").length;
    assert.ok(total > 500, "expected the full command set, got " + total);
    const shown = Number(d.getElementById("shown").textContent);
    assert.ok(shown > 0 && shown < total, "deep-linked filter did not narrow the list");

    const ip = d.getElementById("v_IP");
    ip.value = "10.10.11.5";
    ip.dispatchEvent(new window.Event("input", {bubbles: true}));
    const filled = d.querySelectorAll(".cmd:not(.hidden) code .ph.filled");
    assert.ok(filled.length > 0, "setting IP filled no placeholders");
    window.close();
  });

  test("findings are editable, persist, and flow into the write-up", () => {
    const {window, d} = boot("playbook.html");
    const box = d.getElementById("v_BOX");
    box.value = "fnd";
    box.dispatchEvent(new window.Event("input", {bubbles: true}));

    [...d.querySelectorAll("#tools .track-pill")].find(p => p.dataset.id === "__findings")
      .dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    assert.ok(d.querySelector(".fnd-empty"), "findings should start with an empty state");

    d.querySelector(".fnd-add").dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    const card = d.querySelector(".fnd");
    assert.ok(card, "adding a finding rendered no card");

    const title = card.querySelector(".title");
    title.value = "SQL injection in /login";
    title.dispatchEvent(new window.Event("input", {bubbles: true}));
    const sev = card.querySelector("select.sev");
    sev.value = "high";
    sev.dispatchEvent(new window.Event("change", {bubbles: true}));
    const desc = card.querySelector(".desc");
    desc.value = "The user parameter is injectable; UNION select dumps the users table.";
    desc.dispatchEvent(new window.Event("input", {bubbles: true}));

    const stored = JSON.parse(window.localStorage.getItem("findings:fnd"));
    assert.equal(stored.length, 1);
    assert.equal(stored[0].title, "SQL injection in /login");
    assert.equal(stored[0].severity, "high");

    // it should now appear in the write-up's Findings section
    [...d.querySelectorAll("#tools .track-pill")].find(p => p.dataset.id === "__writeup")
      .dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    const report = d.querySelector(".wu-preview").textContent;
    assert.match(report, /Findings/);
    assert.match(report, /SQL injection in \/login/);
    assert.match(report, /HIGH/);
    window.close();
  });

  test("cheat sheet renders markdown, not raw source", () => {
    const {window, d, errors} = boot("cheatsheet.html");
    assert.deepEqual(errors, [], "script errors on load");
    assert.ok(d.querySelectorAll("h2").length > 10, "sections missing");
    assert.equal(d.querySelectorAll(".toc a").length, d.querySelectorAll("h2").length, "TOC is out of step");
    assert.ok(d.querySelectorAll(".block pre code").length > 10, "code blocks missing");
    assert.ok(!/```/.test(d.body.textContent), "raw markdown fences leaked into the page");
    window.close();
  });

  // A step command is a template: {IP}, {LHOST} and friends are swapped for the
  // target variables at render time, and any other {BRACES} become "<lowercase>".
  // For a standalone placeholder ({WPTOKEN}) that is the intent. For shell
  // parameter expansion it is a silent corruption -- ${IFS} would render as
  // $<ifs> and the command would no longer work when pasted.
  test("no step command hides shell expansion from the token substituter", () => {
    const {window, d} = boot("playbook.html");
    try {
      // Deliberate fill-me-in placeholders, which render as <lowercase> on purpose.
      const placeholders = new Set(["WPTOKEN"]);
      const resolved = new Set(["BOX", "IP", "LHOST", "LPORT", "DOMAIN", "USER", "PASS", "HOST"]);
      const eaten = [], unknown = [];
      let scanned = 0;
      for (const pill of d.querySelectorAll("#tracks .track-pill")) {
        pill.dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
        for (const el of d.querySelectorAll("#phases .cmdtext[data-tpl]")) {
          const tpl = el.dataset.tpl;
          scanned++;
          // ${FOO} -- the substituter eats the {FOO} and leaves a broken $
          for (const m of tpl.matchAll(/\$\{([A-Z]+)\}/g)) {
            eaten.push(m[0] + " in: " + tpl.slice(0, 70));
          }
          for (const m of tpl.matchAll(/\{([A-Z]+)\}/g)) {
            if (!resolved.has(m[1]) && !placeholders.has(m[1])) {
              unknown.push(m[1] + " in: " + tpl.slice(0, 70));
            }
          }
        }
      }
      assert.ok(scanned > 50, "no command templates found -- did the tracks render?");
      assert.deepEqual(eaten, [], "shell ${EXPANSION} will be mangled by substitute()");
      assert.deepEqual(unknown, [], "unresolvable {TOKEN} in a step command");
    } finally {
      window.close();
    }
  });

  test("SUID cross-reference maps a pasted list onto GTFOBins", () => {
    const {d, window} = boot("playbook.html");
    try {
      const pill = [...d.querySelectorAll(".track-pill")].find(p => p.dataset.id === "__suid");
      assert.ok(pill, "SUID xref tool pill missing");
      pill.dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
      const ta = d.getElementById("suidInput");
      // Kenobi's real find output in miniature, plus the shapes that broke on real data.
      ta.value = [
        "/usr/bin/find",              // execs a shell directly -> keeps -p
        "/usr/bin/php7.4",            // matches only after the version suffix is walked off
        "/usr/bin/wget",              // multi-line script; the binary is on the LAST line
        "/usr/bin/dosbox",            // file-write only, not a shell
        "/usr/bin/gimp-2.10",         // in GTFOBins, but with no SUID context
        "/usr/bin/menu",              // Kenobi's answer: no entry at all
        "/usr/lib/x86_64-linux-gnu/lxc/lxc-user-nic", // distro helper, not a custom binary
        "/usr/bin/su",
        "/snap/core20/2599/usr/bin/su",  // snap copy of the same thing
        "-rwsr-xr-x 1 root root 1 Jan 1 2024 /usr/bin/env", // ls -la form
      ].join("\n");
      ta.dispatchEvent(new window.Event("input", {bubbles: true}));
      d.getElementById("suidBtn").dispatchEvent(new window.MouseEvent("click", {bubbles: true}));

      const out = d.getElementById("suidOut");
      const txt = out.textContent;
      const cmds = [...out.querySelectorAll(".cmdtext")].map(c => c.textContent);
      const titles = [...out.querySelectorAll(".ptitle")].map(e => e.textContent);
      const cmd = re => cmds.find(c => re.test(c));

      // the command must name the binary where it actually lives
      assert.match(cmd(/find/) || "", /^\/usr\/bin\/find \. -exec \/bin\/sh -p /, "find not rewritten to its real path with -p");
      assert.ok(cmd(/php7\.4/), "php7.4 did not match GTFOBins' php entry");
      assert.ok(cmd(/env \/bin\/sh -p/), "env not parsed out of ls -la output");

      // 19% of GTFOBins SUID entries are multi-line scripts where the binary is
      // not the first token. Truncating or blindly prepending produces garbage.
      const wget = cmd(/use-askpass/) || "";
      assert.equal(wget.split("\n").length, 3, "wget's multi-line script was flattened");
      assert.match(wget, /\n\/usr\/bin\/wget --use-askpass=/, "path not substituted on the line that invokes wget");
      assert.match(wget, /^echo -e /, "the script's first line was overwritten with the path");

      // one note per group, not repeated per row
      assert.equal((txt.match(/load-bearing/g) || []).length, 1, "the -p note is repeated per row");

      // each not-a-shell bucket is its own group and says something different
      assert.ok(titles.some(t => /^Root shell$/.test(t)), "direct-exec shell group missing");
      assert.ok(titles.some(t => /Useful, but not a shell/.test(t)), "dosbox should land in the useful group");
      assert.ok(titles.some(t => /Not in GTFOBins at all/.test(t)), "menu should report as unknown");
      assert.ok(titles.some(t => /In GTFOBins, but no SUID technique/.test(t)), "gimp should report as known-but-no-route");
      assert.ok(titles.some(t => /Standard on any box/.test(t)), "su should be ranked as a standard SUID bit");

      // distro helpers are not "custom binaries", and snap copies are one finding
      assert.ok(!/lxc-user-nic/.test(txt.split("Standard on any box")[0]), "lxc-user-nic flagged as a custom binary");
      assert.match(txt, /\+1 more copy/, "the /snap copy of su was not folded into one row");
      assert.match(d.getElementById("suidHint").textContent, /10 pasted, 9 distinct/, "summary should count distinct binaries");

      assert.ok(!/\{[A-Z]+\}/.test(cmds.join("\n")), "unsubstituted {TOKEN} in a SUID command");
    } finally {
      window.close();
    }
  });

  test("write-up offers report templates with their own stylesheet", () => {
    const {window, d, errors} = boot("playbook.html");
    assert.deepEqual(errors, [], "script errors on load");
    // capture the print-view document
    let printed = "";
    window.open = () => ({ document: { write: h => { printed += h; }, close(){} }, focus(){}, print(){} });
    const set = (k, v) => { const el = d.getElementById("v_" + k); el.value = v; el.dispatchEvent(new window.Event("input", {bubbles: true})); };
    set("BOX", "b"); set("IP", "10.0.0.9");
    const openWU = () => [...d.querySelectorAll("#tools .track-pill")].find(x => x.dataset.id === "__writeup").dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    openWU();

    const tpls = [...d.querySelectorAll(".wu-mode .genbtn")].map(b => b.textContent);
    assert.ok(tpls.some(t => /Lab/.test(t)) && tpls.some(t => /OSCP/.test(t)), "expected Lab and OSCP templates: " + tpls.join(","));
    assert.match(d.querySelector(".wu-preview h1").textContent, /Penetration Test Report/, "lab title wrong");
    assert.match(d.querySelector(".phase-field label").textContent, /Tester name/, "lab author label wrong");

    // select OSCP
    [...d.querySelectorAll(".wu-mode .genbtn")].find(b => /OSCP/.test(b.textContent)).dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    assert.match(d.querySelector(".wu-preview h1").textContent, /OSCP Exam Report/, "OSCP title wrong");
    assert.match(d.querySelector(".phase-field label").textContent, /Candidate name/, "OSCP author label wrong");
    assert.ok([...d.querySelectorAll(".wu-preview h2")].some(h => /Proof values/.test(h.textContent)), "OSCP proof-values section missing");

    // the print view must carry the OSCP stylesheet, not the lab one
    [...d.querySelectorAll(".wu-actions .genbtn")].find(b => /print/.test(b.textContent)).dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    assert.match(printed, /OSCP Exam Report/, "print view missing OSCP title");
    assert.match(printed, /#0b5394/, "print view did not use the OSCP stylesheet");
    assert.ok(!/Georgia/.test(printed), "print view still using the lab serif stylesheet");
    window.close();
  });

  test("cheat sheet fills target variables and shares them", () => {
    const {window, d, errors} = boot("cheatsheet.html");
    assert.deepEqual(errors, [], "script errors on load");
    assert.equal(d.querySelectorAll(".vars .vfield input").length, 6, "variable inputs missing");

    const set = (k, v) => { const el = d.getElementById("v_" + k); el.value = v; el.dispatchEvent(new window.Event("input", {bubbles: true})); };
    set("IP", "10.10.11.42");
    set("LHOST", "10.8.0.5");   // leave USER/PASS/DOMAIN/LPORT empty on purpose

    const filled = [...d.querySelectorAll("#doc code .ph.filled")].map(s => s.textContent);
    assert.ok(filled.includes("10.10.11.42"), "IP did not fill into any command");
    assert.ok(filled.includes("10.8.0.5"), "LHOST did not fill");

    const body = d.getElementById("doc").textContent;
    assert.ok(/\$\(ip -4/.test(body), "$(...) command substitution was clobbered");
    assert.ok(body.includes("$ports"), "$ports was clobbered");
    assert.ok(body.includes("<user>"), "unset placeholder <user> should stay literal");
    assert.ok(!/\$LHOST/.test(body), "set $LHOST should have been replaced");

    // shared with the playbook & arsenal
    const shared = JSON.parse(window.localStorage.getItem("toolkit:vars"));
    assert.equal(shared.IP, "10.10.11.42");
    window.close();
  });

  test("cheat sheet copy strips comment lines from the command", () => {
    const {window, d, errors} = boot("cheatsheet.html");
    assert.deepEqual(errors, [], "script errors on load");
    let copied = null;
    Object.defineProperty(window.navigator, "clipboard",
      {value: {writeText: t => { copied = t; return Promise.resolve(); }}, configurable: true});

    // any block that mixes a real command line with a # comment line
    const block = [...d.querySelectorAll("#doc .block")].find(b => {
      const lines = b.querySelector("code").textContent.split("\n");
      const hasCmd = lines.some(l => l.trim() && !l.trim().startsWith("#"));
      const hasComment = lines.some(l => l.trim().startsWith("#"));
      return hasCmd && hasComment;
    });
    assert.ok(block, "expected a mixed command+comment block somewhere in the cheat sheet");
    const original = block.querySelector("code").textContent;
    block.querySelector(".copy").dispatchEvent(new window.MouseEvent("click", {bubbles: true}));

    assert.ok(copied, "nothing copied");
    assert.ok(!copied.split("\n").some(l => l.trim().startsWith("#")),
      "copied text still contains a full comment line:\n" + copied);
    assert.ok(copied.trim().length > 0, "copy stripped everything");
    assert.ok(original.split("\n").some(l => l.trim().startsWith("#")),
      "test precondition: the source block should have had a comment line");
    window.close();
  });

  test("cheat sheet collapses to the open ports you focus on", () => {
    const {window, d, errors} = boot("cheatsheet.html");
    assert.deepEqual(errors, [], "script errors on load");
    assert.ok(d.querySelector(".focus #ports"), "open-ports focus control missing");

    const visible = () => [...d.querySelectorAll("#doc h2")]
      .filter(h => !h.classList.contains("filtered"))
      .map(h => h.textContent);
    const before = visible().length;
    assert.ok(before > 15, "expected the full section set before filtering");

    const p = d.getElementById("ports");
    p.value = "22,445";
    p.dispatchEvent(new window.Event("input", {bubbles: true}));
    const after = visible();

    assert.ok(after.some(x => /SSH/.test(x)), "SSH (22) should stay");
    assert.ok(after.some(x => /SMB/.test(x)), "SMB (445) should stay");
    assert.ok(!after.some(x => /FTP/.test(x)), "FTP (21) should be filtered out");
    assert.ok(!after.some(x => /^Web/.test(x)), "Web should be filtered out");
    // universal (non-port) sections must always remain
    assert.ok(after.some(x => /Reverse shells/.test(x)), "universal section dropped");
    assert.ok(after.some(x => /Privilege escalation/.test(x)), "universal section dropped");
    // TOC follows the filter
    assert.ok(d.querySelectorAll(".toc a.filtered").length > 0, "TOC did not follow the filter");

    // "use my scan" reads the shared scan
    window.localStorage.setItem("toolkit:vars", JSON.stringify({BOX: "b"}));
    window.localStorage.setItem("scan2:b", JSON.stringify([{port: "80"}, {port: "161"}]));
    d.getElementById("useScan").dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    const s2 = visible();
    assert.ok(s2.some(x => /^Web/.test(x)) && s2.some(x => /SNMP/.test(x)), "use-my-scan did not focus on 80/161");

    d.getElementById("clearFocus").dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    assert.equal(visible().length, before, "show-all did not restore every section");
    window.close();
  });

  test("launcher renders and every card points somewhere real", () => {
    const {d, window} = boot("index.html");
    const cards = [...d.querySelectorAll("a.card")];
    assert.ok(cards.length >= 5, "expected all tool cards");
    for (const c of cards) {
      assert.ok(fs.existsSync(path.join(ROOT, c.getAttribute("href"))), "card links to missing " + c.getAttribute("href"));
    }
    window.close();
  });

  // ---- flow: the scan drives the page ----
  // These cover the join between the scan, the credential table and the tick
  // state (`ctx`) that the front door, the step gates, the track ranking and
  // the tool row all read. Each of those used to derive its own answer, or no
  // answer at all.
  //
  // Every case closes its window in a finally: a jsdom window left open keeps
  // the page's setInterval alive, and the test runner then never exits, so one
  // failed assertion would hang CI rather than report.

  const AD_SCAN = `Nmap scan report for dc01.corp.local (10.10.11.50)
53/tcp   open  domain        Simple DNS Plus
88/tcp   open  kerberos-sec  Microsoft Windows Kerberos
135/tcp  open  msrpc         Microsoft Windows RPC
389/tcp  open  ldap          Microsoft Windows Active Directory LDAP
445/tcp  open  microsoft-ds?
5985/tcp open  http          Microsoft HTTPAPI httpd 2.0`;

  const LINUX_SCAN = `Nmap scan report for 10.10.10.3
22/tcp open  ssh     OpenSSH 7.2p2 Ubuntu 4ubuntu2.8
80/tcp open  http    Apache httpd 2.4.18`;

  // jsdom gives each instance its own localStorage, so a reload cannot be
  // simulated by booting twice. Seeding before the page script runs tests the
  // real boot path instead.
  function bootSeeded(seed) {
    const inject = "<body><script>" + Object.entries(seed)
      .map(([k, v]) => "localStorage.setItem(" + JSON.stringify(k) + "," + JSON.stringify(v) + ");")
      .join("") + "<\/script>";
    const errors = [];
    const vc = new VirtualConsole()
      .on("jsdomError", e => errors.push(e.message))
      .on("error", (...a) => errors.push(a.join(" ")));
    const dom = new JSDOM(read("playbook.html").replace("<body>", inject), {
      runScripts: "dangerously",
      url: "https://example.org/playbook.html",
      virtualConsole: vc,
    });
    return {dom, window: dom.window, d: dom.window.document, errors};
  }

  function harness(h) {
    h = h || boot("playbook.html");
    const {window, d} = h;
    h.set = (k, v) => { const el = d.getElementById("v_" + k); el.value = v;
      el.dispatchEvent(new window.Event("input", {bubbles: true})); };
    h.hit = el => el.dispatchEvent(new window.MouseEvent("click", {bubbles: true}));
    h.go = id => h.hit([...d.querySelectorAll(".track-pill")].find(p => p.dataset.id === id));
    h.shown = row => [...d.querySelectorAll("#" + row + " .track-pill")]
      .filter(p => !p.classList.contains("demoted")).map(p => p.dataset.id);
    h.phases = () => [...d.querySelectorAll("#phases .phase")]
      .map(p => ({title: p.querySelector(".ptitle").textContent, locked: p.classList.contains("locked")}));
    h.lockedTitles = () => h.phases().filter(p => p.locked).map(p => p.title);
    h.moves = () => [...d.querySelectorAll(".move .mt")].map(e => e.textContent);
    h.addCred = (u, s) => {
      h.hit(d.getElementById("addCred"));
      const rows = [...d.querySelectorAll("#credRows input")];
      const n = rows.length;
      rows[n - 3].value = u; rows[n - 3].dispatchEvent(new window.Event("input", {bubbles: true}));
      rows[n - 2].value = s; rows[n - 2].dispatchEvent(new window.Event("input", {bubbles: true}));
    };
    h.scan = text => {
      // the intake lives on the overview's empty state and in the planner tool;
      // open the tool when the current view is neither
      if (!d.getElementById("scanInput")) h.go("__planner");
      const ta = d.getElementById("scanInput");
      ta.value = text; ta.dispatchEvent(new window.Event("input", {bubbles: true}));
      h.hit(d.getElementById("genBtn"));
    };
    return h;
  }

  // run a case against a harness and always close the window
  const flow = fn => () => { const h = harness(); try { fn(h); } finally { h.window.close(); } };

  test("the page opens on recon, and says the scan is what drives it", flow(h => {
    const d = h.d;
    assert.deepEqual(h.errors, [], "script errors on load");

    // recon is the landing view and the highlighted pill
    assert.equal(d.getElementById("thName").textContent, "Recon", "did not land on the recon track");
    const active = d.querySelector(".track-pill.active");
    assert.equal(active && active.dataset.id, "recon", "recon is not the highlighted pill");
    assert.ok(d.querySelector("#phases .step"), "the recon steps did not render");

    // a checklist does not announce the scan, so the track has to
    const cta = d.querySelector(".empty-cta");
    assert.ok(cta, "no call to action pointing at the scan");
    assert.match(cta.textContent, /scan/i);
    h.hit(cta.querySelector(".genbtn"));
    assert.ok(d.getElementById("scanInput"), "the call to action did not open the planner");

    // With nothing to go on, only recon has a reason to be on screen...
    assert.deepEqual(h.shown("tracks"), ["__overview", "recon"]);
    // ...but nothing is ever actually removed.
    assert.equal(d.querySelectorAll("#tracks .track-pill").length, 12, "demoted tracks left the DOM");
    assert.match(d.querySelector("#tracks .morepill").textContent, /\+10 more/);
  }));

  test("using the planner does not stop ticks from rendering", flow(h => {
    h.set("BOX", "applyprog");
    h.go("linux");
    const first = h.d.querySelector("#phases .step:not(.locked) input[type=checkbox]");
    first.checked = true;
    first.dispatchEvent(new h.window.Event("change", {bubbles: true}));

    // the planner renders .step rows that carry a command but no tick, and the
    // overlay keeps its output after closing; applyProg used to throw on the
    // first of those, freezing the bar and leaving saved ticks unapplied
    h.scan(LINUX_SCAN);
    h.go("linux");
    assert.deepEqual(h.errors, [], "a script error escaped while switching tracks");
    const back = h.d.querySelector("#phases .step:not(.locked) input[type=checkbox]");
    assert.equal(back.checked, true, "a saved tick did not render after using the planner");
    assert.match(h.d.getElementById("plabel").textContent, /^Linux\s+1 ticked \//,
      "the progress bar is stale: " + h.d.getElementById("plabel").textContent);
  }));

  test("the overview still holds the intake, and drops the prompt once scanned", flow(h => {
    h.set("BOX", "intake");
    h.go("__overview");
    assert.ok(h.d.querySelector(".intake #scanInput"), "the scan intake is not on the overview");
    assert.ok(!h.d.querySelector(".boxtype"), "the board rendered before there was any scan");

    h.scan(LINUX_SCAN);
    h.go("recon");
    assert.ok(!h.d.querySelector(".empty-cta"), "the paste-a-scan prompt outstayed the scan");
    h.go("__overview");
    assert.ok(h.d.querySelector(".boxtype"), "the board did not replace the intake");
  }));

  test("a domain controller scan routes the whole page to Active Directory", flow(h => {
    h.set("BOX", "dc");
    h.scan(AD_SCAN);
    h.go("__overview");

    assert.match(h.d.querySelector(".boxtype .bt").textContent, /Active Directory/, "box type wrong");
    assert.equal(h.d.getElementById("v_IP").value, "10.10.11.50", "IP not adopted from the scan");
    assert.equal(h.shown("tracks")[1], "ad", "AD is not the first suggested track");
    assert.match(h.d.querySelector('.track-pill[data-id="ad"] .why').textContent, /88/,
      "the pill does not say why it was suggested");
    assert.match(h.d.querySelector(".boxtype .genbtn").textContent, /Active Directory/,
      "the call to action disagrees with the ranking");
    assert.ok(h.moves().some(m => /first credential/i.test(m)),
      "no-creds-on-a-DC should suggest getting one: " + h.moves().join(" | "));
  }));

  test("AD attack phases stay locked until a credential exists", flow(h => {
    h.set("BOX", "dc2");
    h.scan(AD_SCAN);
    h.go("ad");

    const before = h.phases();
    assert.equal(before[0].locked, false, "the no-creds phase should be workable");
    assert.ok(before.slice(1).every(p => p.locked),
      "post-credential phases should be locked: " + JSON.stringify(before));
    assert.match(h.d.querySelector("#phases .lockbadge").textContent, /domain credential/,
      "a locked phase must say what it is waiting for");

    // locked steps stay visible -- seeing what comes next is the point -- but
    // they are not tickable
    const locked = h.d.querySelector("#phases .step.locked input[type=checkbox]");
    assert.ok(locked, "locked steps were hidden rather than disabled");
    assert.equal(locked.disabled, true, "a locked step was tickable");

    h.addCred("svc_sql", "Summer2024!");
    h.go("ad");
    assert.deepEqual(h.lockedTitles(), [], "phases stayed locked after a credential was recorded");
    h.go("__overview");
    assert.ok(h.moves().some(m => /BloodHound/i.test(m)),
      "with a credential the board should suggest mapping the domain: " + h.moves().join(" | "));
  }));

  test("a foothold unlocks the privesc phases and the tools that need a shell", flow(h => {
    h.set("BOX", "lin");
    h.scan(LINUX_SCAN);
    h.go("linux");

    assert.deepEqual(h.lockedTitles(), ["Local enumeration", "Escalate to root", "Loot"]);
    const suid = () => h.d.querySelector('#tools .track-pill[data-id="__suid"]');
    assert.ok(suid().classList.contains("demoted"), "SUID xref offered before there is a shell");

    // ticking a step in a phase that gives:"shell" is the only thing that moves it
    const cb = h.d.querySelector("#phases .step:not(.locked) input[type=checkbox]");
    cb.checked = true;
    cb.dispatchEvent(new h.window.Event("change", {bubbles: true}));

    assert.deepEqual(h.lockedTitles(), [], "a shell did not unlock the later phases");
    assert.ok(!suid().classList.contains("demoted"), "SUID xref still folded away with a shell");
    h.go("__overview");
    assert.ok(h.moves().some(m => /privilege escalation/i.test(m)),
      "board did not move on to privesc: " + h.moves().join(" | "));
  }));

  test("locked steps do not dilute the progress count", flow(h => {
    h.set("BOX", "prog");
    h.scan(AD_SCAN);
    h.go("ad");

    const open = h.d.querySelectorAll("#phases .step:not(.locked)").length;
    assert.ok(h.d.querySelectorAll("#phases .step.locked").length > 0, "expected locked steps here");
    assert.ok(open > 0 && open < h.d.querySelectorAll("#phases .step").length);
    assert.match(h.d.getElementById("plabel").textContent, new RegExp("0 ticked / " + open + "$"),
      "the bar counted steps you cannot yet tick: " + h.d.getElementById("plabel").textContent);
  }));

  test("the credential table is the source for USER and PASS", flow(h => {
    h.set("BOX", "creds");
    assert.ok(!h.d.getElementById("vars").classList.contains("open"),
      "the extra variable fields should start folded");

    h.addCred("admin", "Pass123!");
    assert.equal(h.d.getElementById("v_USER").value, "admin", "USER not adopted from the table");
    assert.equal(h.d.getElementById("v_PASS").value, "Pass123!", "PASS not adopted from the table");
    assert.ok(h.d.getElementById("vars").classList.contains("open"),
      "the fields should reveal themselves once they hold something");

    // a second row does not steal the pair, but "set" promotes it on demand
    h.addCred("svc", "Other456!");
    assert.equal(h.d.getElementById("v_USER").value, "admin", "a later row overwrote the live credential");
    const setBtns = [...h.d.querySelectorAll("#credRows button")].filter(b => b.textContent === "set");
    assert.equal(setBtns.length, 2, "every credential row should offer 'set'");
    h.hit(setBtns[1]);
    assert.equal(h.d.getElementById("v_USER").value, "svc", "'set' did not promote the second row");
    assert.equal(h.d.getElementById("v_PASS").value, "Other456!");
  }));

  test("header actions collapse into menus without going missing", flow(h => {
    const d = h.d;
    assert.equal(d.querySelectorAll(".boxbar > button.txtbtn").length, 0,
      "box actions should live in the menu, not loose in the bar");
    for (const id of ["boxNew", "boxDup", "boxDel", "boxExport", "boxImport"]) {
      assert.ok(d.querySelector("#boxMenu .menu-body #" + id), id + " missing from the box menu");
    }
    for (const id of ["expandAll", "collapseAll", "resetProg"]) {
      assert.ok(d.querySelector("#viewMenu .menu-body #" + id), id + " missing from the view menu");
    }
    // BOX and IP are the only two you need on minute one
    assert.equal(d.querySelectorAll("#vars > .field").length, 2, "too many always-on variable fields");
    assert.equal(d.querySelectorAll("#varsMoreRow .field").length, 5, "the folded fields went missing");
    for (const k of ["BOX", "IP", "LHOST", "LPORT", "DOMAIN", "USER", "PASS"]) {
      assert.ok(d.getElementById("v_" + k), "v_" + k + " no longer exists");
    }
  }));

  test("target variables are per-box, and fill the commands", flow(h => {
    h.set("BOX", "vbox");
    h.set("IP", "10.10.10.9");
    h.set("LHOST", "10.8.0.5");
    assert.ok(h.window.localStorage.getItem("vars2:vbox"), "variables were not saved for the box");

    // a different box starts clean rather than inheriting them...
    h.set("BOX", "other");
    assert.equal(h.d.getElementById("v_IP").value, "", "the second box inherited the first box's IP");
    // ...and coming back restores them
    h.set("BOX", "vbox");
    assert.equal(h.d.getElementById("v_IP").value, "10.10.10.9", "IP did not come back");
    assert.equal(h.d.getElementById("v_LHOST").value, "10.8.0.5", "LHOST did not come back");

    h.go("recon");
    const filled = [...h.d.querySelectorAll("#phases .tok.filled")].map(e => e.textContent);
    assert.ok(filled.includes("10.10.10.9"), "the restored IP did not fill into any command");
  }));

  test("a reload reopens the last box with its variables", () => {
    // what localStorage looks like after working a box, then reloading
    const h = bootSeeded({
      "toolkit:vars": JSON.stringify({IP: "10.10.10.9", BOX: "vbox"}),
      "toolkit:boxes": JSON.stringify(["vbox"]),
      "vars2:vbox": JSON.stringify({IP: "10.10.10.9", LHOST: "10.8.0.5", LPORT: "", DOMAIN: "", USER: "", PASS: ""}),
      "scan2:vbox": JSON.stringify([{port: "22", proto: "tcp", service: "ssh", version: "OpenSSH 7.2"}]),
    });
    try {
      assert.deepEqual(h.errors, [], "script errors on load");
      assert.equal(h.d.getElementById("v_BOX").value, "vbox", "the last box was not reopened");
      assert.equal(h.d.getElementById("v_IP").value, "10.10.10.9", "IP was lost across a reload");
      assert.equal(h.d.getElementById("v_LHOST").value, "10.8.0.5", "LHOST was lost across a reload");
      // and the restored scan drives the board, not the empty state
      assert.ok(h.d.querySelector(".boxtype"), "the board did not render from the restored scan");
      assert.ok(!h.d.querySelector(".intake"), "the intake rendered despite a saved scan");
    } finally { h.window.close(); }
  });

  test("upgrading from pre-1.10 state keeps the variables it only had shared", () => {
    // what a v1.9.x user's storage looks like: toolkit:vars holds the live
    // variables, and no vars2:<box> exists yet
    const h = bootSeeded({
      "toolkit:vars": JSON.stringify({IP: "10.10.10.4", LHOST: "10.8.0.2", BOX: "old"}),
      "toolkit:boxes": JSON.stringify(["old"]),
      "playbook2:old": JSON.stringify({"linux:p1s0": true}),
    });
    try {
      assert.deepEqual(h.errors, [], "script errors on load");
      assert.equal(h.d.getElementById("v_IP").value, "10.10.10.4", "upgrade blanked the IP");
      assert.equal(h.d.getElementById("v_LHOST").value, "10.8.0.2", "upgrade blanked LHOST");
      // and it is adopted into per-box storage, so a later box switch keeps it
      const saved = JSON.parse(h.window.localStorage.getItem("vars2:old"));
      assert.equal(saved.IP, "10.10.10.4", "the migrated variables were not persisted per box");
    } finally { h.window.close(); }
  });

  test("a second scan replaces the hostname the first one set", flow(h => {
    h.set("BOX", "one");
    h.scan(AD_SCAN);
    assert.equal(h.d.getElementById("v_DOMAIN").value, "dc01.corp.local");

    // a different box must not inherit the first one's domain -- the board puts
    // it in a headline, so a stale one is now visibly wrong
    h.set("BOX", "two");
    h.go("__planner");
    h.scan(`Nmap scan report for dc02.other.local (10.10.11.51)
88/tcp  open  kerberos-sec
389/tcp open  ldap`);
    assert.equal(h.d.getElementById("v_DOMAIN").value, "dc02.other.local");

    // but something typed by hand is left alone
    h.set("DOMAIN", "typed.by.hand");
    h.go("__planner");
    h.scan(AD_SCAN);
    assert.equal(h.d.getElementById("v_DOMAIN").value, "typed.by.hand",
      "a hand-typed domain was overwritten by a scan");
  }));

  test("demoting a track or tool never makes it unreachable", flow(h => {
    h.set("BOX", "reach");
    h.scan(LINUX_SCAN);
    assert.equal(h.d.querySelectorAll("#tracks .track-pill").length, 12);
    assert.equal(h.d.querySelectorAll("#tools .track-pill").length, 8);

    const more = h.d.querySelector("#tracks .morepill");
    assert.ok(more, "no disclosure for the demoted tracks");
    h.hit(more);
    assert.ok(h.d.getElementById("tracks").classList.contains("show-all"), "'more' did not reveal them");
    assert.match(more.textContent, /less/);

    // a demoted track still renders when clicked
    h.go("bof");
    assert.equal(h.d.getElementById("thName").textContent, "Buffer overflow");
  }));
}

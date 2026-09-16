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

  test("launcher renders and every card points somewhere real", () => {
    const {d, window} = boot("index.html");
    const cards = [...d.querySelectorAll("a.card")];
    assert.ok(cards.length >= 5, "expected all tool cards");
    for (const c of cards) {
      assert.ok(fs.existsSync(path.join(ROOT, c.getAttribute("href"))), "card links to missing " + c.getAttribute("href"));
    }
    window.close();
  });
}

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
    assert.equal(d.querySelectorAll("#tracks .track-pill").length, 11, "10 tracks + overview");
    assert.equal(d.querySelectorAll("#tools .track-pill").length, 7, "7 tools");
    assert.ok([...d.querySelectorAll("#tracks .track-pill")].some(p => p.dataset.id === "container"),
      "container escape track missing");
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

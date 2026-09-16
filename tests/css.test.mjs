// Regression test for the always-on storeWarn banner (v1.7.2 and earlier):
// an author `.banner{display:flex}` overrides the UA `[hidden]{display:none}`,
// so an element toggled with the `hidden` attribute stays visible unless it
// also carries a `.class[hidden]{display:none}` guard. jsdom does not model
// this cascade, so the render tests could not catch it — hence a source check.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const src = fs.readFileSync(path.join(ROOT, "playbook.html"), "utf8");

test("elements toggled via [hidden] with a display rule carry a [hidden] guard", () => {
  const hiddenClasses = new Set();
  for (const m of src.matchAll(/class="([a-z0-9 _-]+)"[^>]*\shidden(?=[>\s])/g)) {
    m[1].split(/\s+/).forEach(c => c && hiddenClasses.add(c));
  }
  assert.ok(hiddenClasses.size > 0, "found no hidden-toggled classes — did the markup or regex change?");

  const problems = [];
  for (const cls of hiddenClasses) {
    const rule = new RegExp("\\." + cls + "\\{([^}]*)\\}").exec(src);
    if (!rule) continue;
    const disp = /display\s*:\s*([^;}]+)/.exec(rule[1]);
    if (disp && disp[1].trim() !== "none") {
      const guarded = new RegExp("\\." + cls + "\\[hidden\\]").test(src);
      if (!guarded) problems.push("." + cls + " sets display:" + disp[1].trim() + " but has no .[hidden] guard");
    }
  }
  assert.deepEqual(problems, [], "unguarded hidden+display element(s):\n" + problems.join("\n"));
});

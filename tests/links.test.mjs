// Every relative link in the shipped pages must resolve to a file in the repo.
// Cheap, dependency-free, and the thing most likely to break silently after a
// rename (it is exactly what broke when the pages lost their oscp- prefix).
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PAGES = fs.readdirSync(ROOT).filter(f => f.endsWith(".html"));

const EXTERNAL = /^(https?:|mailto:|data:|#|javascript:)/i;
// Attribute values assembled in JS ( src="'+escapeHtml(b.src)+'" ) are not
// links to check.
const TEMPLATED = /[+(){}$\s]|['"`]/;

function linksIn(file) {
  const src = fs.readFileSync(path.join(ROOT, file), "utf8");
  const out = [];
  for (const m of src.matchAll(/\b(?:href|src)\s*=\s*"([^"]+)"/g)) out.push(m[1]);
  // links built in JS, e.g. "arsenal.html?q=" + term. Match the whole quoted
  // literal, so fragments of string concatenation are not mistaken for paths.
  for (const m of src.matchAll(/(['"`])([a-z0-9][a-z0-9._-]*\.(?:html|md|sh|js|css)(?:\?[^'"`]*)?)\1/gi)) out.push(m[2]);
  return out;
}

test("pages exist to test", () => {
  assert.ok(PAGES.length >= 4, "expected the toolkit pages, found " + PAGES.join(", "));
});

for (const page of PAGES) {
  test(`${page} has no broken relative links`, () => {
    const broken = [];
    for (const raw of new Set(linksIn(page))) {
      if (EXTERNAL.test(raw) || TEMPLATED.test(raw)) continue;
      const target = raw.split(/[?#]/)[0];
      if (!target) continue;
      if (!fs.existsSync(path.join(ROOT, target))) broken.push(raw);
    }
    assert.deepEqual(broken, [], `${page} links to missing files`);
  });
}

test("the launcher links to every tool", () => {
  const src = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  for (const f of ["playbook.html", "arsenal.html", "cheatsheet.html", "enum.sh", "build-arsenal.sh"]) {
    assert.ok(src.includes(f), "index.html does not link to " + f);
  }
});

test("renamed pages keep a redirect stub", () => {
  for (const [stub, target] of [["oscp-playbook.html", "playbook.html"],
                                ["oscp-arsenal.html", "arsenal.html"],
                                ["oscp-cheatsheet.html", "cheatsheet.html"]]) {
    const p = path.join(ROOT, stub);
    assert.ok(fs.existsSync(p), stub + " is missing; old published links would 404");
    const src = fs.readFileSync(p, "utf8");
    assert.match(src, new RegExp('http-equiv="refresh"[^>]*' + target), stub + " does not redirect to " + target);
  }
});

test("no page references the old file names outside the stubs", () => {
  for (const page of PAGES) {
    if (page.startsWith("oscp-") || page === "404.html") continue;
    const src = fs.readFileSync(path.join(ROOT, page), "utf8");
    assert.ok(!/oscp-(playbook|arsenal|cheatsheet)\.html/.test(src),
      page + " still points at a pre-rename file name");
  }
});

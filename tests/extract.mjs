// Pull named functions and consts straight out of the page source so the tests
// exercise the shipped code, not a copy of it. The playbook is one file with no
// build step and no module system, which is deliberate -- this is the price.
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

export function pageScript(file) {
  const src = fs.readFileSync(path.join(ROOT, file), "utf8");
  const m = src.match(/<script>\n([\s\S]*?)\n<\/script>/);
  if (!m) throw new Error("no <script> block found in " + file);
  return m[1];
}

// Take `function name(...) { ... }` including nested braces, by counting.
// This has to understand regex literals, not just strings: `.replace(/"/g, ...)`
// contains a lone double quote that a naive scanner reads as the start of a
// string, and it then swallows the rest of the file.
function takeFunction(src, name) {
  const start = src.indexOf("function " + name + "(");
  if (start < 0) throw new Error("function " + name + " not found");
  const open = src.indexOf("{", start);
  let depth = 0, inStr = null, esc = false, inRe = false, inClass = false;
  let prev = "";
  for (let j = open; j < src.length; j++) {
    const c = src[j];

    if (esc) { esc = false; continue; }

    if (inStr) {
      if (c === "\\") esc = true;
      else if (c === inStr) inStr = null;
      continue;
    }
    if (inRe) {
      if (c === "\\") esc = true;
      else if (c === "[") inClass = true;
      else if (c === "]") inClass = false;
      else if (c === "/" && !inClass) inRe = false;
      continue;
    }

    if (c === '"' || c === "'" || c === "`") { inStr = c; prev = c; continue; }

    // A "/" starts a regex when what precedes it cannot end an expression.
    if (c === "/") {
      if (src[j + 1] === "/") {                 // line comment
        j = src.indexOf("\n", j);
        if (j < 0) break;
        prev = "";
        continue;
      }
      if (src[j + 1] === "*") {                 // block comment
        j = src.indexOf("*/", j) + 1;
        prev = "";
        continue;
      }
      if (prev === "" || "(,=:[!&|?{};+-*%<>~^".includes(prev)) { inRe = true; continue; }
      prev = c;
      continue;
    }

    if (c === "{") depth++;
    else if (c === "}") { depth--; if (depth === 0) return src.slice(start, j + 1); }

    if (!/\s/.test(c)) prev = c;
  }
  throw new Error("unbalanced braces reading " + name);
}

function takeConst(src, name) {
  const re = new RegExp("^const\\s+" + name + "\\s*=", "m");
  const m = re.exec(src);
  if (!m) throw new Error("const " + name + " not found");
  // consts here are single-line declarations ending in ";"
  const line = src.slice(m.index);
  const end = line.indexOf(";\n");
  if (end < 0) throw new Error("could not find end of const " + name);
  return line.slice(0, end + 1);
}

// Build a sandbox module exposing the requested symbols.
export function load(file, {functions = [], consts = []} = {}) {
  const src = pageScript(file);
  const parts = [
    ...consts.map(c => takeConst(src, c)),
    ...functions.map(f => takeFunction(src, f)),
  ];
  const body = parts.join("\n\n") + "\nreturn {" + [...consts, ...functions].join(",") + "};";
  return new Function(body)();
}

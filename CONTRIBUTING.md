# Contributing

Thanks for helping improve the toolkit.

## Ground rules

- **Authorised testing only.** Don't add anything whose only use is unauthorised
  access. See [SECURITY.md](SECURITY.md).
- **Flag exam restrictions, don't assume them.** The toolkit is for CTFs, labs and
  authorised engagements generally. Where a technique is out of bounds on a
  certification exam (sqlmap, automated exploitation, Metasploit beyond the permitted
  box) say so in a note, the way the existing entries do — rather than writing as
  though every reader is sitting the OSCP.
- **Enumeration, not autopwn.** `enum.sh` deliberately runs no exploits.

## Running the checks

```
bash -n enum.sh build-arsenal.sh build-cheatsheet.sh
shellcheck enum.sh build-arsenal.sh build-cheatsheet.sh
node --test tests/*.test.mjs
```

The render tests want jsdom. It is never committed — install it on demand:

```
npm install --no-save jsdom
```

Without it those tests skip and the rest still run.

## Shell scripts

All three scripts are shellcheck-clean at default severity, and CI enforces it.

`enum.sh` prints and logs every command before running it — that is the point of the
tool, not an accident. Because commands are assembled as strings and passed to
`bash -c`, **any new value interpolated into a command string must come from a
validated source.** Target and hostname are checked against an allowlist at startup;
keep it that way.

Its command log is file descriptor 3, not a variable. A parallel block re-points fd 3
at its own buffer, which is what keeps `-j N` from interleaving and what keeps
shellcheck quiet about subshell state. If you add a step, use `run` and let it handle
both the printing and the logging.

Every `run` that writes an output file should pass that path as the second argument —
that is what makes `--force` and the skip-on-rerun behaviour work.

## Generated pages

Two pages are generated and committed. **Don't hand-edit either one.**

| page | generator | source |
|---|---|---|
| `arsenal.html` | `./build-arsenal.sh` | upstream arsenal repo, at a pinned commit |
| `cheatsheet.html` | `./build-cheatsheet.sh` | `cheatsheet.md` |

**The committed pages must be byte-identical to a fresh build**, and CI checks both.
The markup lives in the `TPL` string inside each generator; restyle there and
regenerate, never the other way round.

The arsenal is pinned to an upstream commit in `build-arsenal.sh`. That pin is what
makes the build reproducible — without it, CI would go red on an unrelated pull request
every time upstream pushed anything. To move it deliberately:

```
./build-arsenal.sh --latest      # updates the pin and rebuilds
```

A weekly `Arsenal drift` workflow does the same thing and opens a pull request, so new
upstream commands arrive as a review rather than a surprise failure.

Everything written into the arsenal page comes from a third-party repository, so it all
goes through `esc()`. If you add a new field to the template, escape it.

`build-cheatsheet.sh` implements a deliberately small markdown subset — headings, fenced
code, rules, ordered and unordered lists, inline code and bold. That is all the cheat
sheet uses. If you need more, extend the renderer rather than adding a dependency.

## The playbook's flow model

The playbook is not a static checklist. A single derived object, `ctx`, joins the
parsed scan, the credential table and the tick state into one answer to "where am I
on this box", and the front door, the step gates, the track ranking, the tool row and
the next-move list all read it. Nothing derives its own version of that answer — if
you need a new signal, add it to `recomputeCtx()` and call `refreshChrome()` wherever
the underlying state changes.

Four optional keys drive it, and all four are data, not code:

| key | goes on | means |
|---|---|---|
| `when:c=>…` | a phase or a step | show it as workable only when this holds of `ctx` |
| `needs:"…"` | a phase or a step | the blocker, in words, shown on the lock |
| `gives:"shell"` / `"root"` | a phase | ticking anything inside it moves `ctx.shell` |
| `when:c=>…` | a `TOOLS` entry | offer the tool up front rather than under "more" |

`needs` is a noun phrase that completes "unlocks once you have …", so write
`"a domain credential"`, not `"credentials required"`.

Two rules matter more than the rest:

- **Gate, never hide.** A gated step still renders, with its command, greyed and not
  tickable — seeing what comes next is half of what a playbook is for. A demoted
  track or tool stays in the DOM and stays one click away under "more". Nothing the
  toolkit can do should ever become unreachable because a guess about context was
  wrong.
- **Say why.** A lock states its blocker, a suggested track carries the reason it was
  suggested, and a next move names the phase it jumps to. An unexplained ordering is
  a guess the reader cannot check.

Track ranking lives in `trackScore()` — one `case` per track, returning a score and
the reason shown on the pill. Anything scoring zero is demoted, not removed. The
`nextMoves()` list is ordered by hand, filtered by `ctx`, and capped at five; each
entry jumps to the exact phase that does the work, so a suggestion and its commands
can never drift apart.

`boxTypeOf()` names the host and then takes its recommended track from the ranking,
so the banner and the pills beside it cannot disagree.

## The HTML tools

`index.html`, `playbook.html` and `404.html` are hand-written, dependency-free, and work
offline from `file://`. Please keep that true — no CDN links, no build step, no
framework. jsdom in `tests/` is a test harness, not a runtime dependency.

State lives in `localStorage`. If you add any:

- Namespace it, and key it per box: `yourthing:<box>`.
- Add the prefix to `STORE_PREFIXES` in `playbook.html` so the box manager can list,
  duplicate, export and delete it with everything else.
- Go through the `store` wrapper rather than touching `localStorage` directly. It
  raises the "not saving your work" banner on the first failed write and flashes the
  save indicator on success; a bare `try/catch` loses both.
- Extend `boxState`/`writeBoxState` so it survives an export/import round trip.

Nav, favicon, meta tags and the version string are repeated in each page rather than
shared, because there is no build step. If you change one, change all four.

## Tests

`tests/pure.test.mjs` pulls functions straight out of `playbook.html` and exercises
them — no DOM, no dependencies. `tests/extract.mjs` does the pulling; it understands
strings, comments and regex literals, which is what it takes to find the end of a
function in a file with no module boundaries.

`tests/links.test.mjs` checks every relative link in every page resolves, and that the
pre-rename redirect stubs still point somewhere.

`tests/render.test.mjs` boots each page in jsdom and asserts it renders: tracks, tools,
labelled checkboxes, the command palette, the arsenal's filters and variable filling.
It also covers the flow model end to end — that a DC scan routes the page to Active
Directory, that the attack phases stay locked until a credential is recorded, that a
foothold unlocks the privesc phases and their tools, that locked steps do not count
toward progress, and that nothing demoted becomes unreachable. If you add a `when`
gate, add the case that proves it both locks and unlocks.

If you fix a parsing bug, add a fixture to `tests/fixtures/` and a case to
`pure.test.mjs`. The nmap parser in particular is fed untrusted text.

## Pull requests

Keep them focused, say what you tested, and note any new tool dependency (and how to
install it) in the README.

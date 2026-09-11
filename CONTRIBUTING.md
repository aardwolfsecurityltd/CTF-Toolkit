# Contributing

Thanks for helping improve the toolkit.

## Ground rules

- **Authorised testing only.** Don't add anything whose only use is unauthorised
  access. See [SECURITY.md](SECURITY.md).
- **Respect the OSCP restrictions.** The playbook flags techniques that are
  off-limits on the exam (sqlmap, automated exploitation, Metasploit beyond the
  permitted box). If you add something restricted, flag it the same way.
- **Enumeration, not autopwn.** `oscp-enum.sh` deliberately runs no exploits.

## Shell scripts

Both scripts are shellcheck-clean at default severity, and CI enforces it:

```
shellcheck oscp-enum.sh build-arsenal.sh
bash -n oscp-enum.sh build-arsenal.sh
```

`oscp-enum.sh` prints and logs every command before running it — that is the
point of the tool, not an accident. Because commands are assembled as strings
and passed to `bash -c`, **any new value interpolated into a command string must
come from a validated source.** Target and hostname are checked against an
allowlist at startup; keep it that way.

## The arsenal page

Don't hand-edit `oscp-arsenal.html` — it is generated. Change
`build-arsenal.sh` and regenerate:

```
./build-arsenal.sh
```

Everything written into the page comes from a third-party repository, so it all
goes through `esc()`. If you add a new field to the template, escape it.

## The HTML tools

`index.html` and `oscp-playbook.html` are hand-written, dependency-free, and
work offline from `file://`. Please keep all three true — no CDN links, no build
step, no framework.

State lives in `localStorage`, keyed per box. If you add state, namespace it.

## Pull requests

Keep them focused, say what you tested, and note any new tool dependency
(and how to install it) in the README.

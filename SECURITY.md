# Security policy

## Authorised use only

This repository contains penetration testing and CTF tooling. It is published
for use against systems you own, or that you have **explicit written permission**
to test — your own lab, a CTF platform you are registered with, or an engagement
covered by a signed scope.

Running these tools against systems you are not authorised to test is illegal in
most jurisdictions. You are responsible for staying inside your scope.

Nothing here is an exploit or a weaponised payload: the toolkit is enumeration,
reference material, and command generation. It does not autopwn anything.

## Reporting a vulnerability in this toolkit

If you find a security problem in the toolkit itself — for example a way that
untrusted input (a target name, a scan result, upstream arsenal data) could
execute code on the operator's machine — please report it privately:

1. Open a [security advisory](https://github.com/aardwolfsecurityltd/CTF-Toolkit/security/advisories/new), or
2. Email the maintainers rather than opening a public issue.

Please don't open a public issue for these. We'll acknowledge within a few days.

### Known hardening in place

- `enum.sh` builds commands as strings and runs them through `bash -c` so
  that each command can be printed and learned. Targets and hostnames are
  therefore validated against a strict character allowlist before use.
- The playbook applies that same allowlist to any hostname it parses out of scan
  output you paste or drop in, because that value is interpolated into a
  copy-paste-ready `echo ... >> /etc/hosts` command. A hostname that does not
  match is dropped rather than quoted.
- Everything the playbook renders from scan text — service names, versions,
  script output — is HTML-escaped. Scan output is untrusted input: it is
  attacker-influenced whenever the target controls a banner.
- `build-arsenal.sh` HTML-escapes every value taken from the upstream arsenal
  repository before writing it into the generated page, and builds from a
  commit pinned in the script rather than whatever upstream happens to be
  serving at the time.
- Nothing is transmitted anywhere. The one outbound request in the toolkit is
  the exploit suggester's NVD lookup, which is off by default and sends only the
  product/version string you ask it to look up.

### Your data

The playbook stores everything — notes, credentials, screenshots — in the
browser's `localStorage`, unencrypted, on your own machine. That is the right
trade-off for an offline tool, but it does mean credentials from an engagement
sit in your browser profile until you clear them. Delete the box when the
engagement ends, and treat an exported `*-box.json` as sensitive: it contains
every credential you recorded.

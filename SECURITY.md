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

- `oscp-enum.sh` builds commands as strings and runs them through `bash -c` so
  that each command can be printed and learned. Targets and hostnames are
  therefore validated against a strict character allowlist before use.
- `build-arsenal.sh` HTML-escapes every value taken from the upstream arsenal
  repository before writing it into the generated page.

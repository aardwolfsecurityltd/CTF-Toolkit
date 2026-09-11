#!/usr/bin/env bash
###############################################################################
# enum.sh
# Structured, self-documenting enumeration runner for CTF boxes, lab machines
# and authorised engagements.
#
# Design goals:
#   1. Cover the standard services you meet on lab, CTF and exam boxes.
#   2. PRINT every command before it runs, and log it to commands.log, so you
#      learn the syntax instead of hiding it behind a black box.
#   3. Only enumerate ports that are actually open (saves time).
#   4. Nothing here breaks certification tool restrictions: no autopwn, no
#      sqlmap, no vulnerability scanners. Enumeration only.
#
# Usage:
#   ./enum.sh <ip> [hostname] [-u] [-n] [-j N] [--dry-run] [--force]
#     <ip>        target IP (required)
#     [hostname]  optional vhost/FQDN, used for zone transfer and vhost hints
#     -u          also run a UDP top-ports scan (needs sudo)
#     -n          also run nikto on web ports (slow)
#     -j N        run up to N service blocks at once (default 1, sequential).
#                 Output is buffered per block and printed in a fixed order, so
#                 it stays readable; -j 4 typically halves the wall clock.
#     --dry-run   print and log every command without running any of them
#     --force     redo steps whose output file already exists (default: skip,
#                 so a re-run after a crash does not repeat the long scans)
#
# Feed the result into the playbook: the scan planner reads
#   enum_<ip>/nmap/detailed.nmap
# directly -- drop the file onto the planner, or paste its contents.
#
# Handy tools it will use if present (install what you are missing):
#   nmap, netexec (nxc), enum4linux-ng, smbclient, smbmap, whatweb,
#   feroxbuster|ffuf|gobuster, onesixtyone, snmpwalk, ldapsearch, dig,
#   rpcinfo, showmount, redis-cli, nikto, odat, mongosh, rsync, finger
###############################################################################

set -o pipefail

# ---------------------------------------------------------------- args --------
IP=""
TARGET_HOST=""
DO_UDP=0
DO_NIKTO=0
DRY_RUN=0
FORCE=0
JOBS=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--udp)     DO_UDP=1; shift ;;
        -n|--nikto)   DO_NIKTO=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        --force)      FORCE=1; shift ;;
        -j|--jobs)    JOBS="${2:-1}"; shift 2 ;;
        -j*)          JOBS="${1#-j}"; shift ;;
        -h|--help)    sed -n '2,36p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
        -*)           echo "Unknown option: $1"; exit 1 ;;
        *)
            if   [[ -z "$IP" ]];          then IP="$1"
            elif [[ -z "$TARGET_HOST" ]]; then TARGET_HOST="$1"
            else echo "Unexpected argument: $1"; exit 1
            fi
            shift ;;
    esac
done

if [[ -z "$IP" ]]; then
    echo "Usage: $0 <ip> [hostname] [-u] [-n] [-j N] [--dry-run] [--force]"
    exit 1
fi

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
    echo "Refusing -j '$JOBS': job count must be a positive integer."
    exit 1
fi

# Commands below are built as strings and run through `bash -c` (so that the
# exact command can be printed and learned). That makes the target shell input,
# so accept only literal IPv4/IPv6/hostname forms -- no metacharacters.
if ! [[ "$IP" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "Refusing target '$IP': only letters, digits, dot, colon, hyphen and underscore are allowed."
    exit 1
fi
if [[ -n "$TARGET_HOST" ]] && ! [[ "$TARGET_HOST" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Refusing hostname '$TARGET_HOST': only letters, digits, dot, hyphen and underscore are allowed."
    exit 1
fi

# --------------------------------------------------------------- colours ------
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
CYN='\033[0;36m'; BLU='\033[1;34m'; NC='\033[0m'

# --------------------------------------------------------------- output -------
OUTDIR="enum_${IP}"
mkdir -p "$OUTDIR"/{nmap,web,smb,other}
CMDLOG="$OUTDIR/commands.log"
PARTS="$OUTDIR/.parts"
rm -rf "$PARTS"; mkdir -p "$PARTS"
: > "$CMDLOG"
# fd 3 is the command log. A parallel block re-points it at its own buffer
# (see spawn), which keeps every command in order without any shared state.
exec 3>>"$CMDLOG"

# --------------------------------------------------------------- wordlists ----
DIRLIST="/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt"
[[ -f "$DIRLIST" ]] || DIRLIST="/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt"
[[ -f "$DIRLIST" ]] || DIRLIST="/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt"
[[ -f "$DIRLIST" ]] || DIRLIST="/usr/share/wordlists/dirb/common.txt"
[[ -f "$DIRLIST" ]] || DIRLIST=""
SNMP_COMMS="/usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt"

# --------------------------------------------------------------- helpers ------
section() { echo -e "\n${BLU}==== $* ====${NC}"; }
have()    { command -v "$1" >/dev/null 2>&1; }

# run "<command string>" ["<output file>"]
# echoes the command, logs it, then runs it (optionally tee to a file).
# With --dry-run it stops after printing. With an output file that already
# exists it skips, unless --force.
run() {
    local cmd="$1"; local out="${2:-}"
    if [[ -n "$out" && -s "$out" && $FORCE -eq 0 && $DRY_RUN -eq 0 ]]; then
        echo -e "${YEL}[skip]${NC} $out already has output (--force to redo)"
        return 0
    fi
    echo -e "${CYN}[cmd]${NC} $cmd"
    echo "$cmd" >&3
    [[ $DRY_RUN -eq 1 ]] && return 0
    if [[ -n "$out" ]]; then
        bash -c "$cmd" 2>&1 | tee "$out"
    else
        bash -c "$cmd"
    fi
}

need() {  # warn (do not abort) if a tool is missing
    if ! have "$1"; then
        echo -e "${YEL}[!] $1 not found. Install: ${2:-apt install $1}${NC}"
        return 1
    fi
    return 0
}

# is a given TCP port in the open set?
has() { [[ ",$PORTS," == *",$1,"* ]]; }

# --- parallel service blocks -------------------------------------------------
# Each block is a function. With -j 1 it runs inline, exactly as before. With
# -j N the block runs in a subshell writing to its own buffer, and the buffers
# are printed in submission order once everything finishes -- so the output
# still reads top to bottom even though the work overlapped.
SPAWN_NAMES=()
SPAWN_PIDS=()

# how many of our own service jobs are still running (the background UDP scan
# is deliberately not counted -- it must not eat a service slot)
running_jobs() {
    local n=0 pid
    for pid in "${SPAWN_PIDS[@]}"; do
        kill -0 "$pid" 2>/dev/null && n=$((n + 1))
    done
    echo "$n"
}

# spawn <buffer-name> <command> [args...]
spawn() {
    local name="$1"; shift
    if [[ $JOBS -le 1 ]]; then
        "$@"
        return 0
    fi
    while [[ "$(running_jobs)" -ge "$JOBS" ]]; do sleep 0.2; done
    (
        exec 3>"$PARTS/$name.cmds"
        "$@"
    ) > "$PARTS/$name.out" 2>&1 &
    SPAWN_NAMES+=("$name")
    SPAWN_PIDS+=("$!")
    return 0
}

# wait for the spawned blocks, then replay their buffers in submission order
drain() {
    [[ $JOBS -le 1 ]] && return 0
    local i
    for i in "${!SPAWN_PIDS[@]}"; do
        wait "${SPAWN_PIDS[$i]}" 2>/dev/null || true
    done
    for i in "${!SPAWN_NAMES[@]}"; do
        local name="${SPAWN_NAMES[$i]}"
        [[ -f "$PARTS/$name.out" ]]  && cat "$PARTS/$name.out"
        [[ -f "$PARTS/$name.cmds" ]] && cat "$PARTS/$name.cmds" >> "$CMDLOG"
    done
    SPAWN_NAMES=()
    SPAWN_PIDS=()
    return 0
}

# A dry run only prints commands, so it has no business insisting the tools are
# installed -- reading the commands on a machine without them is a fair use.
if ! have nmap; then
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${YEL}[!] nmap not found, but this is a dry run: commands are printed, not run.${NC}"
    else
        echo -e "${RED}[!] nmap not found; it drives every stage of this script. Install: apt install nmap${NC}"
        exit 1
    fi
fi

echo -e "${GRN}[*] Target: $IP  ${TARGET_HOST:+(host: $TARGET_HOST)}${NC}"
[[ $DRY_RUN -eq 1 ]] && echo -e "${YEL}[*] Dry run: commands are printed and logged, nothing is executed.${NC}"
[[ $JOBS -gt 1 ]]    && echo -e "${GRN}[*] Running up to $JOBS service blocks at once; their output is buffered and printed in order.${NC}"
if [[ -n "$DIRLIST" ]]; then
    echo -e "${GRN}[*] Wordlist: $DIRLIST${NC}"
else
    echo -e "${YEL}[!] No wordlist found; web directory brute-forcing will be skipped."
    echo -e "    Install one: apt install seclists${NC}"
fi

# ============================================================== PORT SCAN =====
section "Port scan: $IP"

run "nmap -p- --min-rate 10000 -T4 -Pn $IP -oN $OUTDIR/nmap/allports.nmap" "$OUTDIR/nmap/allports.nmap"

# A UDP scan is slow and independent of everything else, so start it now and
# collect it at the end rather than blocking the whole run on it.
UDP_PID=""
if [[ $DO_UDP -eq 1 && $DRY_RUN -eq 0 && $JOBS -gt 1 ]]; then
    echo -e "${GRN}[*] UDP scan started in the background; results appear at the end.${NC}"
    echo "sudo nmap -sU --top-ports 100 -T4 -Pn $IP -oN $OUTDIR/nmap/udp.nmap" >&3
    udp_scan() { sudo nmap -sU --top-ports 100 -T4 -Pn "$IP" -oN "$OUTDIR/nmap/udp.nmap"; }
    udp_scan > "$PARTS/udp.out" 2>&1 &
    UDP_PID=$!
fi

# sort -un also de-duplicates: nmap can list a port twice when it reports more
# than one service on it, and a repeated -p entry is just noise in the scan line
PORTS=$(grep -oP '^\d+(?=/tcp\s+open)' "$OUTDIR/nmap/allports.nmap" 2>/dev/null | sort -un | paste -sd, -)

if [[ -z "$PORTS" ]]; then
    echo -e "${YEL}[!] No open TCP ports on full sweep. Consider UDP (-u), or the host may be filtering.${NC}"
else
    echo -e "${GRN}[+] Open TCP ports: $PORTS${NC}"
    run "nmap -sCV -p$PORTS -Pn $IP -oN $OUTDIR/nmap/detailed.nmap" "$OUTDIR/nmap/detailed.nmap"
fi

if [[ $DO_UDP -eq 1 && -z "$UDP_PID" ]]; then
    section "UDP top-ports scan"
    run "sudo nmap -sU --top-ports 100 -T4 -Pn $IP -oN $OUTDIR/nmap/udp.nmap" "$OUTDIR/nmap/udp.nmap"
fi

# ============================================================== SERVICES ======

svc_ftp() {
    section "FTP (21)"
    run "nmap -p21 --script ftp-anon,ftp-syst -Pn $IP -oN $OUTDIR/other/ftp.nmap" "$OUTDIR/other/ftp.nmap"
    echo -e "${YEL}[i] Anonymous: ftp $IP   (user: anonymous, pass: anything). Try mget *.${NC}"
}

svc_ssh() {
    section "SSH (22)"
    run "nmap -p22 --script ssh2-enum-algos,ssh-auth-methods -Pn $IP -oN $OUTDIR/other/ssh.nmap" "$OUTDIR/other/ssh.nmap"
    echo -e "${YEL}[i] Note the version for known CVEs. Look out for reused creds / stray private keys.${NC}"
}

svc_telnet() {
    section "Telnet (23)"
    run "nmap -p23 --script telnet-encryption,telnet-ntlm-info -Pn $IP -oN $OUTDIR/other/telnet.nmap" "$OUTDIR/other/telnet.nmap"
    echo -e "${YEL}[i] Connect: telnet $IP   Banners here often name the device and firmware.${NC}"
}

svc_smtp() {
    section "SMTP (25)"
    run "nmap -p25 --script smtp-commands,smtp-enum-users -Pn $IP -oN $OUTDIR/other/smtp.nmap" "$OUTDIR/other/smtp.nmap"
    echo -e "${YEL}[i] User enum: smtp-user-enum -M VRFY -U users.txt -t $IP${NC}"
}

svc_finger() {
    section "finger (79)"
    run "nmap -p79 --script finger -Pn $IP -oN $OUTDIR/other/finger.nmap" "$OUTDIR/other/finger.nmap"
    have finger && run "finger @$IP" "$OUTDIR/other/finger.txt"
    echo -e "${YEL}[i] Usernames from finger feed straight into an SSH or SMTP brute.${NC}"
}

svc_dns() {
    section "DNS (53)"
    run "dig @$IP version.bind chaos txt"
    if [[ -n "$TARGET_HOST" ]]; then
        run "dig axfr @$IP $TARGET_HOST" "$OUTDIR/other/dns_axfr.txt"
    else
        echo -e "${YEL}[i] Zone transfer needs a domain: dig axfr @$IP <domain>${NC}"
    fi
}

svc_kerberos() {
    section "Kerberos (88) - very likely a Domain Controller"
    echo -e "${YEL}[i] AD box. Pull the domain from SMB/LDAP output and add it to /etc/hosts.${NC}"
    echo -e "${YEL}[i] User enum : kerbrute userenum -d <domain> --dc $IP users.txt${NC}"
    echo -e "${YEL}[i] AS-REP    : impacket-GetNPUsers <domain>/ -no-pass -usersfile users.txt -dc-ip $IP${NC}"
    echo -e "${YEL}[i] Kerberoast: impacket-GetUserSPNs <domain>/<user>:<pass> -dc-ip $IP -request${NC}"
}

svc_mail() {
    section "POP3/IMAP (110/143/993/995)"
    run "nmap -p110,143,993,995 --script pop3-capabilities,imap-capabilities -Pn $IP -oN $OUTDIR/other/mail.nmap" "$OUTDIR/other/mail.nmap"
}

svc_rpc() {
    section "RPCbind / NFS (111)"
    have rpcinfo  && run "rpcinfo -p $IP" "$OUTDIR/other/rpcinfo.txt"
    run "nmap -p111 --script nfs-ls,nfs-showmount,nfs-statfs -Pn $IP -oN $OUTDIR/other/nfs.nmap" "$OUTDIR/other/nfs.nmap"
    have showmount && run "showmount -e $IP" "$OUTDIR/other/showmount.txt"
    echo -e "${YEL}[i] Mount a share: sudo mount -t nfs $IP:/<share> /mnt/nfs -o nolock${NC}"
    echo -e "${YEL}[i] no_root_squash on an export is a direct route to root.${NC}"
}

svc_rservices() {
    section "r-services (512/513/514)"
    run "nmap -p512,513,514 --script rexec-brute,rlogin-brute -Pn $IP -oN $OUTDIR/other/rservices.nmap" "$OUTDIR/other/rservices.nmap"
    echo -e "${YEL}[i] A permissive .rhosts means: rlogin -l root $IP   with no password at all.${NC}"
}

svc_smb() {
    section "SMB (139/445)"
    run "nmap -p139,445 --script 'smb-os-discovery,smb-enum-shares,smb-enum-users,smb-security-mode,smb2-security-mode,smb-protocols' -Pn $IP -oN $OUTDIR/smb/nmap_smb.nmap" "$OUTDIR/smb/nmap_smb.nmap"
    if have nxc; then
        run "nxc smb $IP"                             "$OUTDIR/smb/nxc_info.txt"
        run "nxc smb $IP -u '' -p '' --shares"        "$OUTDIR/smb/nxc_null_shares.txt"
        run "nxc smb $IP -u 'guest' -p '' --shares"   "$OUTDIR/smb/nxc_guest_shares.txt"
    elif have crackmapexec; then
        run "crackmapexec smb $IP --shares"           "$OUTDIR/smb/cme_shares.txt"
    fi
    have enum4linux-ng && run "enum4linux-ng -A $IP"  "$OUTDIR/smb/enum4linux.txt"
    have smbmap        && run "smbmap -H $IP"         "$OUTDIR/smb/smbmap.txt"
    have smbmap        && run "smbmap -H $IP -u guest -p ''" "$OUTDIR/smb/smbmap_guest.txt"
    have smbclient     && run "smbclient -L //$IP/ -N" "$OUTDIR/smb/smbclient_list.txt"
    echo -e "${YEL}[i] Connect: smbclient //$IP/<share> -N     (or -U '<user>%<pass>')${NC}"
    echo -e "${YEL}[i] Recurse: smbclient //$IP/<share> -N -c 'recurse ON; ls'${NC}"
}

svc_ldap() {
    section "LDAP (389/636)"
    run "nmap -p389 --script ldap-rootdse -Pn $IP -oN $OUTDIR/other/ldap.nmap" "$OUTDIR/other/ldap.nmap"
    have ldapsearch && run "ldapsearch -x -H ldap://$IP -s base -b '' namingContexts" "$OUTDIR/other/ldap_base.txt"
    echo -e "${YEL}[i] Dump: ldapsearch -x -H ldap://$IP -b '<baseDN>' > ldap_dump.txt${NC}"
}

svc_rsync() {
    section "rsync (873)"
    have rsync && run "rsync --list-only rsync://$IP/" "$OUTDIR/other/rsync_modules.txt"
    echo -e "${YEL}[i] Anonymous modules are common. Pull one: rsync -av rsync://$IP/<module> loot/rsync/${NC}"
}

svc_rmi() {
    section "Java RMI (1099)"
    run "nmap -p1099 --script rmi-dumpregistry,rmi-vuln-classloader -Pn $IP -oN $OUTDIR/other/rmi.nmap" "$OUTDIR/other/rmi.nmap"
    echo -e "${YEL}[i] Deeper: remote-method-guesser  ->  java -jar rmg.jar enum $IP 1099${NC}"
}

svc_mssql() {
    section "MSSQL (1433)"
    run "nmap -p1433 --script ms-sql-info,ms-sql-ntlm-info,ms-sql-empty-password -Pn $IP -oN $OUTDIR/other/mssql.nmap" "$OUTDIR/other/mssql.nmap"
    echo -e "${YEL}[i] Login: impacket-mssqlclient <user>:<pass>@$IP   (add -windows-auth for domain)${NC}"
    echo -e "${YEL}[i] Then:  enable_xp_cmdshell  ->  xp_cmdshell 'whoami'${NC}"
}

svc_oracle() {
    section "Oracle TNS (1521)"
    run "nmap -p1521 --script oracle-tns-version,oracle-sid-brute -Pn $IP -oN $OUTDIR/other/oracle.nmap" "$OUTDIR/other/oracle.nmap"
    echo -e "${YEL}[i] SIDs then creds: odat sidguesser -s $IP ; odat passwordguesser -s $IP${NC}"
    echo -e "${YEL}[i] Login: sqlplus <user>/<pass>@$IP:1521/<SID>${NC}"
}

svc_mysql() {
    section "MySQL (3306)"
    run "nmap -p3306 --script mysql-info,mysql-empty-password,mysql-users -Pn $IP -oN $OUTDIR/other/mysql.nmap" "$OUTDIR/other/mysql.nmap"
    echo -e "${YEL}[i] Login: mysql -h $IP -u root -p${NC}"
}

svc_distcc() {
    section "distcc (3632)"
    run "nmap -p3632 --script distcc-cve2004-2687 --script-args='distcc-cve2004-2687.cmd=id' -Pn $IP -oN $OUTDIR/other/distcc.nmap" "$OUTDIR/other/distcc.nmap"
    echo -e "${YEL}[i] If the script returns a uid, that is command execution as the distcc user.${NC}"
}

svc_rdp() {
    section "RDP (3389)"
    run "nmap -p3389 --script rdp-ntlm-info -Pn $IP -oN $OUTDIR/other/rdp.nmap" "$OUTDIR/other/rdp.nmap"
    echo -e "${YEL}[i] Connect: xfreerdp /v:$IP /u:<user> /p:<pass> +clipboard /dynamic-resolution${NC}"
}

svc_postgres() {
    section "PostgreSQL (5432)"
    echo -e "${YEL}[i] Login: psql -h $IP -U postgres     (blank/postgres password is common)${NC}"
    echo -e "${YEL}[i] Then:  COPY x FROM PROGRAM 'id';   for command execution as the postgres user.${NC}"
}

svc_vnc() {
    section "VNC (5900/5901)"
    run "nmap -p5900,5901 --script vnc-info,vnc-title -Pn $IP -oN $OUTDIR/other/vnc.nmap" "$OUTDIR/other/vnc.nmap"
    echo -e "${YEL}[i] Connect: vncviewer $IP::5900   A stored ~/.vnc/passwd cracks with vncpwd.${NC}"
}

svc_winrm() {
    section "WinRM (5985/5986)"
    have nxc && run "nxc winrm $IP" "$OUTDIR/other/winrm.txt"
    echo -e "${YEL}[i] Test creds: nxc winrm $IP -u <user> -p <pass>${NC}"
    echo -e "${YEL}[i] Shell:      evil-winrm -i $IP -u <user> -p <pass>${NC}"
}

svc_redis() {
    section "Redis (6379)"
    have redis-cli && run "redis-cli -h $IP info" "$OUTDIR/other/redis.txt"
    echo -e "${YEL}[i] redis-cli -h $IP  then:  keys *  |  config get dir  |  config get dbfilename${NC}"
}

svc_irc() {
    section "IRC (6667/6697)"
    run "nmap -p6667,6697 --script irc-info,irc-unrealircd-backdoor -Pn $IP -oN $OUTDIR/other/irc.nmap" "$OUTDIR/other/irc.nmap"
    echo -e "${YEL}[i] Note the daemon and version; some builds shipped with a backdoor.${NC}"
}

svc_elastic() {
    section "Elasticsearch (9200)"
    run "curl -sSi --max-time 15 http://$IP:9200/" "$OUTDIR/other/elastic_root.txt"
    run "curl -sS --max-time 20 'http://$IP:9200/_cat/indices?v'" "$OUTDIR/other/elastic_indices.txt"
    echo -e "${YEL}[i] Read one: curl -sS 'http://$IP:9200/<index>/_search?pretty&size=20'${NC}"
}

svc_memcached() {
    section "memcached (11211)"
    run "nmap -p11211 --script memcached-info -Pn $IP -oN $OUTDIR/other/memcached.nmap" "$OUTDIR/other/memcached.nmap"
    echo -e "${YEL}[i] By hand: nc $IP 11211  then  stats items / stats cachedump <slab> 0 / get <key>${NC}"
}

svc_mongo() {
    section "MongoDB (27017)"
    run "nmap -p27017 --script mongodb-info,mongodb-databases -Pn $IP -oN $OUTDIR/other/mongo.nmap" "$OUTDIR/other/mongo.nmap"
    echo -e "${YEL}[i] Connect: mongosh --host $IP --port 27017   then  show dbs${NC}"
}

svc_docker() {
    section "Docker API (2375/2376)"
    run "curl -sSi --max-time 15 http://$IP:2375/version" "$OUTDIR/other/docker.txt"
    echo -e "${RED}[!] An unauthenticated Docker API is root on the host: docker -H tcp://$IP:2375 run -v /:/mnt ...${NC}"
}

has 21   && spawn ftp        svc_ftp
has 22   && spawn ssh        svc_ssh
has 23   && spawn telnet     svc_telnet
has 25   && spawn smtp       svc_smtp
has 53   && spawn dns        svc_dns
has 79   && spawn finger     svc_finger
has 88   && spawn kerberos   svc_kerberos
{ has 110 || has 143 || has 993 || has 995; } && spawn mail  svc_mail
has 111  && spawn rpc        svc_rpc
{ has 512 || has 513 || has 514; }            && spawn rserv svc_rservices
{ has 445 || has 139; }                       && spawn smb   svc_smb
has 873  && spawn rsync      svc_rsync
{ has 389 || has 636; }                       && spawn ldap  svc_ldap
has 1099 && spawn rmi        svc_rmi
has 1433 && spawn mssql      svc_mssql
has 1521 && spawn oracle     svc_oracle
has 2375 && spawn docker     svc_docker
has 3306 && spawn mysql      svc_mysql
has 3389 && spawn rdp        svc_rdp
has 3632 && spawn distcc     svc_distcc
has 5432 && spawn postgres   svc_postgres
{ has 5900 || has 5901; }                     && spawn vnc   svc_vnc
{ has 5985 || has 5986; }                     && spawn winrm svc_winrm
has 6379 && spawn redis      svc_redis
{ has 6667 || has 6697; }                     && spawn irc   svc_irc
has 9200 && spawn elastic    svc_elastic
has 11211 && spawn memcached svc_memcached
has 27017 && spawn mongo     svc_mongo
drain

# ============================================================== WEB ===========
WEB_PORTS=""
for p in 80 443 8000 8080 8443 8888 5000; do
    has "$p" && WEB_PORTS="$WEB_PORTS $p"
done
# pick up http on non-standard ports from the version scan
if [[ -f "$OUTDIR/nmap/detailed.nmap" ]]; then
    while read -r p; do
        [[ " $WEB_PORTS " == *" $p "* ]] || WEB_PORTS="$WEB_PORTS $p"
    done < <(grep -iE '^[0-9]+/tcp\s+open\s+.*http' "$OUTDIR/nmap/detailed.nmap" | grep -oP '^[0-9]+')
fi

web_port() {
    local p="$1" scheme="http" url
    case "$p" in 443|8443|9443) scheme="https" ;; esac
    # nmap labels TLS services "ssl/http" or "https"; trust that over the port number
    if [[ -f "$OUTDIR/nmap/detailed.nmap" ]] &&
       grep -qiE "^$p/tcp[[:space:]]+open[[:space:]]+(ssl/http|https)" "$OUTDIR/nmap/detailed.nmap"; then
        scheme="https"
    fi
    url="$scheme://$IP:$p"
    section "Web ($p) -> $url"

    need whatweb && run "whatweb -a3 $url" "$OUTDIR/web/whatweb_$p.txt"
    run "nmap -p$p --script http-enum,http-title,http-headers,http-methods,http-robots.txt -Pn $IP -oN $OUTDIR/web/nmap_http_$p.nmap" "$OUTDIR/web/nmap_http_$p.nmap"
    run "curl -sSik --max-time 15 $url/robots.txt"

    if [[ -z "$DIRLIST" ]]; then
        echo -e "${YEL}[!] Skipping directory brute force: no wordlist.${NC}"
    elif have feroxbuster; then
        run "feroxbuster -u $url -w $DIRLIST -t 50 -d 2 -C 404,403 -q -o $OUTDIR/web/ferox_$p.txt -x php,html,txt,asp,aspx" "$OUTDIR/web/ferox_$p.txt"
    elif have ffuf; then
        run "ffuf -u $url/FUZZ -w $DIRLIST -mc all -fc 404 -t 50 -e .php,.html,.txt,.asp,.aspx -o $OUTDIR/web/ffuf_$p.json -of json" "$OUTDIR/web/ffuf_$p.json"
    elif have gobuster; then
        run "gobuster dir -u $url -w $DIRLIST -t 50 -x php,html,txt,asp,aspx -o $OUTDIR/web/gobuster_$p.txt" "$OUTDIR/web/gobuster_$p.txt"
    else
        echo -e "${YEL}[!] No directory brute tool found (feroxbuster / ffuf / gobuster).${NC}"
    fi

    if [[ -n "$TARGET_HOST" ]]; then
        echo -e "${YEL}[i] vhost fuzz: ffuf -u $url -H 'Host: FUZZ.$TARGET_HOST' -w <subdomains.txt> -fs <baseline-size>${NC}"
    fi

    [[ $DO_NIKTO -eq 1 ]] && need nikto && run "nikto -h $url -maxtime 120s" "$OUTDIR/web/nikto_$p.txt"
    return 0
}

for p in $WEB_PORTS; do
    spawn "web_$p" web_port "$p"
done
drain

# ---- collect the backgrounded UDP scan ----
if [[ -n "$UDP_PID" ]]; then
    section "UDP top-ports scan"
    echo -e "${GRN}[*] Waiting for the background UDP scan to finish...${NC}"
    wait "$UDP_PID" || true
    [[ -f "$PARTS/udp.out" ]] && cat "$PARTS/udp.out"
fi

# ---- UDP-only services, once a UDP scan exists ----
if [[ -f "$OUTDIR/nmap/udp.nmap" ]]; then
    udp_has() { grep -qE "^$1/udp\s+(open|open\|filtered)" "$OUTDIR/nmap/udp.nmap" 2>/dev/null; }

    if udp_has 69; then
        section "TFTP (69/udp)"
        run "nmap -sU -p69 --script tftp-enum -Pn $IP -oN $OUTDIR/other/tftp.nmap" "$OUTDIR/other/tftp.nmap"
        echo -e "${YEL}[i] TFTP cannot list files. Guess names: tftp $IP -c get <filename>${NC}"
    fi
    if udp_has 123; then
        section "NTP (123/udp)"
        run "nmap -sU -p123 --script ntp-info,ntp-monlist -Pn $IP -oN $OUTDIR/other/ntp.nmap" "$OUTDIR/other/ntp.nmap"
    fi
    if udp_has 161; then
        section "SNMP (161/udp)"
        [[ -f "$SNMP_COMMS" ]] && have onesixtyone && run "onesixtyone -c $SNMP_COMMS $IP" "$OUTDIR/other/onesixtyone.txt"
        have snmpwalk && run "snmpwalk -v2c -c public $IP" "$OUTDIR/other/snmpwalk.txt"
        echo -e "${YEL}[i] Useful OIDs: 1.3.6.1.2.1.25.4.2.1.2 (procs), 1.3.6.1.2.1.25.6.3.1.2 (installed sw)${NC}"
    fi
    if udp_has 500; then
        section "IKE / IPsec (500/udp)"
        have ike-scan && run "ike-scan -M $IP" "$OUTDIR/other/ike.txt"
        echo -e "${YEL}[i] Aggressive mode hands over a crackable hash: ike-scan -M -A $IP${NC}"
    fi
fi

# ============================================================== SUMMARY =======
section "Done"
exec 3>&-
rm -rf "$PARTS"
echo -e "${GRN}Output directory : $OUTDIR/${NC}"
echo -e "${GRN}Command log      : $CMDLOG   (every command run, in order)${NC}"
[[ -n "$PORTS" ]] && echo -e "${GRN}Open TCP ports   : $PORTS${NC}"
if [[ -f "$OUTDIR/nmap/detailed.nmap" ]]; then
    echo -e "${GRN}Next             : open playbook.html, go to the scan planner, and drop in${NC}"
    echo -e "${GRN}                   $OUTDIR/nmap/detailed.nmap${NC}"
    echo -e "${GRN}                   It routes the box to a track and lists per-service commands.${NC}"
fi
echo -e "${YEL}Reminders:${NC}"
echo -e "  - If the app redirects to a hostname, add it to /etc/hosts and re-run web enum."
echo -e "  - Nothing found on dirs? Re-run with a bigger wordlist (e.g. raft-large)."
echo -e "  - searchsploit every version string before trying anything: searchsploit <product> <ver>"

#!/usr/bin/env bash
###############################################################################
# oscp-enum.sh
# Structured, self-documenting enumeration runner for OSCP-style targets.
#
# Design goals:
#   1. Cover the standard services you meet on exam/lab boxes.
#   2. PRINT every command before it runs, and log it to commands.log, so you
#      learn the syntax instead of hiding it behind a black box.
#   3. Only enumerate ports that are actually open (saves time).
#   4. Nothing here breaks OSCP tool restrictions: no autopwn, no sqlmap, no
#      vulnerability scanners. Enumeration only.
#
# Usage:
#   ./oscp-enum.sh <ip> [hostname] [-u] [-n]
#     <ip>        target IP (required)
#     [hostname]  optional vhost/FQDN, used for zone transfer and vhost hints
#     -u          also run a UDP top-ports scan (needs sudo)
#     -n          also run nikto on web ports (slow)
#
# Handy tools it will use if present (install what you are missing):
#   nmap, netexec (nxc), enum4linux-ng, smbclient, smbmap, whatweb,
#   feroxbuster|ffuf|gobuster, onesixtyone, snmpwalk, ldapsearch, dig,
#   rpcinfo, showmount, redis-cli, nikto
###############################################################################

set -o pipefail

# ---------------------------------------------------------------- args --------
IP=""
TARGET_HOST=""
DO_UDP=0
DO_NIKTO=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--udp)   DO_UDP=1; shift ;;
        -n|--nikto) DO_NIKTO=1; shift ;;
        -h|--help)  sed -n '2,25p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
        -*)         echo "Unknown option: $1"; exit 1 ;;
        *)
            if   [[ -z "$IP" ]];          then IP="$1"
            elif [[ -z "$TARGET_HOST" ]]; then TARGET_HOST="$1"
            else echo "Unexpected argument: $1"; exit 1
            fi
            shift ;;
    esac
done

if [[ -z "$IP" ]]; then
    echo "Usage: $0 <ip> [hostname] [-u] [-n]"
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
: > "$CMDLOG"

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
# echoes the command, logs it, then runs it (optionally tee to a file)
run() {
    local cmd="$1"; local out="${2:-}"
    echo -e "${CYN}[cmd]${NC} $cmd"
    echo "$cmd" >> "$CMDLOG"
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

if ! have nmap; then
    echo -e "${RED}[!] nmap not found; it drives every stage of this script. Install: apt install nmap${NC}"
    exit 1
fi

echo -e "${GRN}[*] Target: $IP  ${TARGET_HOST:+(host: $TARGET_HOST)}${NC}"
if [[ -n "$DIRLIST" ]]; then
    echo -e "${GRN}[*] Wordlist: $DIRLIST${NC}"
else
    echo -e "${YEL}[!] No wordlist found; web directory brute-forcing will be skipped."
    echo -e "    Install one: apt install seclists${NC}"
fi

# ============================================================== PORT SCAN =====
section "Port scan: $IP"

run "nmap -p- --min-rate 10000 -T4 -Pn $IP -oN $OUTDIR/nmap/allports.nmap"

PORTS=$(grep -oP '^\d+(?=/tcp\s+open)' "$OUTDIR/nmap/allports.nmap" | paste -sd, -)

if [[ -z "$PORTS" ]]; then
    echo -e "${YEL}[!] No open TCP ports on full sweep. Consider UDP (-u), or the host may be filtering.${NC}"
else
    echo -e "${GRN}[+] Open TCP ports: $PORTS${NC}"
    run "nmap -sCV -p$PORTS -Pn $IP -oN $OUTDIR/nmap/detailed.nmap"
fi

if [[ $DO_UDP -eq 1 ]]; then
    section "UDP top-ports scan"
    need nmap && run "sudo nmap -sU --top-ports 100 -T4 -Pn $IP -oN $OUTDIR/nmap/udp.nmap"
fi

# ============================================================== SERVICES ======

# ---- FTP 21 ----
if has 21; then
    section "FTP (21)"
    run "nmap -p21 --script ftp-anon,ftp-syst -Pn $IP -oN $OUTDIR/other/ftp.nmap"
    echo -e "${YEL}[i] Anonymous: ftp $IP   (user: anonymous, pass: anything). Try mget *.${NC}"
fi

# ---- SSH 22 ----
if has 22; then
    section "SSH (22)"
    run "nmap -p22 --script ssh2-enum-algos,ssh-auth-methods -Pn $IP -oN $OUTDIR/other/ssh.nmap"
    echo -e "${YEL}[i] Note the version for known CVEs. Look out for reused creds / stray private keys.${NC}"
fi

# ---- SMTP 25 ----
if has 25; then
    section "SMTP (25)"
    run "nmap -p25 --script smtp-commands,smtp-enum-users -Pn $IP -oN $OUTDIR/other/smtp.nmap"
    echo -e "${YEL}[i] User enum: smtp-user-enum -M VRFY -U users.txt -t $IP${NC}"
fi

# ---- DNS 53 ----
if has 53; then
    section "DNS (53)"
    run "dig @$IP version.bind chaos txt"
    if [[ -n "$TARGET_HOST" ]]; then
        run "dig axfr @$IP $TARGET_HOST" "$OUTDIR/other/dns_axfr.txt"
    else
        echo -e "${YEL}[i] Zone transfer needs a domain: dig axfr @$IP <domain>${NC}"
    fi
fi

# ---- Kerberos 88 (AD indicator) ----
if has 88; then
    section "Kerberos (88) - very likely a Domain Controller"
    echo -e "${YEL}[i] AD box. Pull the domain from SMB/LDAP output and add it to /etc/hosts.${NC}"
    echo -e "${YEL}[i] User enum : kerbrute userenum -d <domain> --dc $IP users.txt${NC}"
    echo -e "${YEL}[i] AS-REP    : impacket-GetNPUsers <domain>/ -no-pass -usersfile users.txt -dc-ip $IP${NC}"
    echo -e "${YEL}[i] Kerberoast: impacket-GetUserSPNs <domain>/<user>:<pass> -dc-ip $IP -request${NC}"
fi

# ---- POP3/IMAP 110/143/993/995 ----
if has 110 || has 143 || has 993 || has 995; then
    section "POP3/IMAP (110/143/993/995)"
    run "nmap -p110,143,993,995 --script pop3-capabilities,imap-capabilities -Pn $IP -oN $OUTDIR/other/mail.nmap"
fi

# ---- RPCbind / NFS 111 ----
if has 111; then
    section "RPCbind / NFS (111)"
    have rpcinfo  && run "rpcinfo -p $IP" "$OUTDIR/other/rpcinfo.txt"
    run "nmap -p111 --script nfs-ls,nfs-showmount,nfs-statfs -Pn $IP -oN $OUTDIR/other/nfs.nmap"
    have showmount && run "showmount -e $IP" "$OUTDIR/other/showmount.txt"
    echo -e "${YEL}[i] Mount a share: sudo mount -t nfs $IP:/<share> /mnt/nfs -o nolock${NC}"
fi

# ---- SMB 139/445 ----
if has 445 || has 139; then
    section "SMB (139/445)"
    run "nmap -p139,445 --script 'smb-os-discovery,smb-enum-shares,smb-enum-users,smb-security-mode,smb2-security-mode,smb-protocols' -Pn $IP -oN $OUTDIR/smb/nmap_smb.nmap"
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
fi

# ---- SNMP 161/udp (only meaningful after a UDP scan) ----
if [[ $DO_UDP -eq 1 ]] && grep -q '^161/udp' "$OUTDIR/nmap/udp.nmap" 2>/dev/null; then
    section "SNMP (161/udp)"
    [[ -f "$SNMP_COMMS" ]] && have onesixtyone && run "onesixtyone -c $SNMP_COMMS $IP" "$OUTDIR/other/onesixtyone.txt"
    have snmpwalk && run "snmpwalk -v2c -c public $IP" "$OUTDIR/other/snmpwalk.txt"
    echo -e "${YEL}[i] Useful OIDs: 1.3.6.1.2.1.25.4.2.1.2 (procs), 1.3.6.1.2.1.25.6.3.1.2 (installed sw)${NC}"
fi

# ---- LDAP 389/636 ----
if has 389 || has 636; then
    section "LDAP (389/636)"
    run "nmap -p389 --script ldap-rootdse -Pn $IP -oN $OUTDIR/other/ldap.nmap"
    have ldapsearch && run "ldapsearch -x -H ldap://$IP -s base -b '' namingContexts" "$OUTDIR/other/ldap_base.txt"
    echo -e "${YEL}[i] Dump: ldapsearch -x -H ldap://$IP -b '<baseDN>' > ldap_dump.txt${NC}"
fi

# ---- MSSQL 1433 ----
if has 1433; then
    section "MSSQL (1433)"
    run "nmap -p1433 --script ms-sql-info,ms-sql-ntlm-info,ms-sql-empty-password -Pn $IP -oN $OUTDIR/other/mssql.nmap"
    echo -e "${YEL}[i] Login: impacket-mssqlclient <user>:<pass>@$IP   (add -windows-auth for domain)${NC}"
fi

# ---- MySQL 3306 ----
if has 3306; then
    section "MySQL (3306)"
    run "nmap -p3306 --script mysql-info,mysql-empty-password,mysql-users -Pn $IP -oN $OUTDIR/other/mysql.nmap"
    echo -e "${YEL}[i] Login: mysql -h $IP -u root -p${NC}"
fi

# ---- PostgreSQL 5432 ----
if has 5432; then
    section "PostgreSQL (5432)"
    echo -e "${YEL}[i] Login: psql -h $IP -U postgres     (blank/postgres password is common)${NC}"
fi

# ---- Redis 6379 ----
if has 6379; then
    section "Redis (6379)"
    have redis-cli && run "redis-cli -h $IP info" "$OUTDIR/other/redis.txt"
    echo -e "${YEL}[i] redis-cli -h $IP  then:  keys *  |  config get dir  |  config get dbfilename${NC}"
fi

# ---- RDP 3389 ----
if has 3389; then
    section "RDP (3389)"
    run "nmap -p3389 --script rdp-ntlm-info -Pn $IP -oN $OUTDIR/other/rdp.nmap"
    echo -e "${YEL}[i] Connect: xfreerdp /v:$IP /u:<user> /p:<pass> +clipboard /dynamic-resolution${NC}"
fi

# ---- WinRM 5985/5986 ----
if has 5985 || has 5986; then
    section "WinRM (5985/5986)"
    have nxc && run "nxc winrm $IP" "$OUTDIR/other/winrm.txt"
    echo -e "${YEL}[i] Test creds: nxc winrm $IP -u <user> -p <pass>${NC}"
    echo -e "${YEL}[i] Shell:      evil-winrm -i $IP -u <user> -p <pass>${NC}"
fi

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

for p in $WEB_PORTS; do
    scheme="http"
    case "$p" in 443|8443|9443) scheme="https" ;; esac
    # nmap labels TLS services "ssl/http" or "https"; trust that over the port number
    if [[ -f "$OUTDIR/nmap/detailed.nmap" ]] &&
       grep -qiE "^$p/tcp[[:space:]]+open[[:space:]]+(ssl/http|https)" "$OUTDIR/nmap/detailed.nmap"; then
        scheme="https"
    fi
    url="$scheme://$IP:$p"
    section "Web ($p) -> $url"

    need whatweb && run "whatweb -a3 $url" "$OUTDIR/web/whatweb_$p.txt"
    run "nmap -p$p --script http-enum,http-title,http-headers,http-methods,http-robots.txt -Pn $IP -oN $OUTDIR/web/nmap_http_$p.nmap"
    run "curl -sSik --max-time 15 $url/robots.txt"

    if [[ -z "$DIRLIST" ]]; then
        echo -e "${YEL}[!] Skipping directory brute force: no wordlist.${NC}"
    elif have feroxbuster; then
        run "feroxbuster -u $url -w $DIRLIST -t 50 -d 2 -C 404,403 -q -o $OUTDIR/web/ferox_$p.txt -x php,html,txt,asp,aspx"
    elif have ffuf; then
        run "ffuf -u $url/FUZZ -w $DIRLIST -mc all -fc 404 -t 50 -e .php,.html,.txt,.asp,.aspx -o $OUTDIR/web/ffuf_$p.json -of json"
    elif have gobuster; then
        run "gobuster dir -u $url -w $DIRLIST -t 50 -x php,html,txt,asp,aspx -o $OUTDIR/web/gobuster_$p.txt"
    else
        echo -e "${YEL}[!] No directory brute tool found (feroxbuster / ffuf / gobuster).${NC}"
    fi

    if [[ -n "$TARGET_HOST" ]]; then
        echo -e "${YEL}[i] vhost fuzz: ffuf -u $url -H 'Host: FUZZ.$TARGET_HOST' -w <subdomains.txt> -fs <baseline-size>${NC}"
    fi

    [[ $DO_NIKTO -eq 1 ]] && need nikto && run "nikto -h $url -maxtime 120s" "$OUTDIR/web/nikto_$p.txt"
done

# ============================================================== SUMMARY =======
section "Done"
echo -e "${GRN}Output directory : $OUTDIR/${NC}"
echo -e "${GRN}Command log      : $CMDLOG   (every command run, in order)${NC}"
[[ -n "$PORTS" ]] && echo -e "${GRN}Open TCP ports   : $PORTS${NC}"
echo -e "${YEL}Reminders:${NC}"
echo -e "  - If the app redirects to a hostname, add it to /etc/hosts and re-run web enum."
echo -e "  - Nothing found on dirs? Re-run with a bigger wordlist (e.g. raft-large)."
echo -e "  - searchsploit every version string before trying anything: searchsploit <product> <ver>"

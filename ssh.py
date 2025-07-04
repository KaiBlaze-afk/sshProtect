#!/usr/bin/env python3
import subprocess
import re
import sys
import time
from datetime import datetime, timedelta
import os

# CONFIG
KNOWN_IP_FILE = "known_ips.txt"
HONEYPOT_CONF = "honeypot.conf"
HONEYPOT_SCRIPT = os.path.abspath("honeypot.sh")
BAN_THRESHOLD = 5
BAN_DURATION = timedelta(minutes=2)

# REGEX
FAILED_REGEX = re.compile(r"(?P<datetime>\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2}).*sshd.*Failed password for (invalid user )?(?P<user>\S+) from (?P<ip>[\d.]+)")
SUCCESS_REGEX = re.compile(r"(?P<datetime>\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2}).*sshd.*Accepted password for (?P<user>\S+) from (?P<ip>[\d.]+)")

# TRACKING
failed_attempts = {}
blocked_ips = set()

def load_known_ips():
    if not os.path.exists(KNOWN_IP_FILE):
        return set()
    with open(KNOWN_IP_FILE, "r") as f:
        return set(line.strip() for line in f if line.strip())

def load_honeypotted_ips():
    if not os.path.exists(HONEYPOT_CONF):
        return set()
    with open(HONEYPOT_CONF, "r") as f:
        return set(
            line.strip().split()[2]  # get IP from "Match Address <IP>"
            for line in f
            if line.strip().startswith("Match Address")
        )

def remove_from_honeypot_conf(ip):
    if not os.path.exists(HONEYPOT_CONF):
        return
    with open(HONEYPOT_CONF, "r") as f:
        lines = f.readlines()
    with open(HONEYPOT_CONF, "w") as f:
        skip = False
        for line in lines:
            if line.strip().startswith(f"Match Address {ip}"):
                skip = True
                continue
            if skip and line.strip().startswith("ForceCommand"):
                skip = False
                print(f"[+] Removed {ip} from honeypot.conf")
                continue
            if not skip:
                f.write(line)
    subprocess.run(["systemctl", "reload", "ssh"], check=True)

def add_to_honeypot(ip):
    honeypotted_ips = load_honeypotted_ips()
    if ip in honeypotted_ips:
        return  # Already added
    with open(HONEYPOT_CONF, "a") as f:
        f.write(f"\nMatch Address {ip}\n    ForceCommand {HONEYPOT_SCRIPT}\n")
    subprocess.run(["systemctl", "reload", "ssh"], check=True)
    print(f"[⚠️] Routed NEW IP to honeypot: {ip}")

def setup_honeypot_for_new_ip(ip):
    print(f"[~] Preparing honeypot for new IP: {ip}")
    subprocess.run(["iptables", "-I", "INPUT", "-s", ip, "-p", "tcp", "--dport", "22", "-j", "DROP"], check=True)
    time.sleep(2)
    add_to_honeypot(ip)
    subprocess.run(["iptables", "-D", "INPUT", "-s", ip, "-p", "tcp", "--dport", "22", "-j", "DROP"], check=True)
    print(f"[✓] IP redirected to honeypot on next attempt: {ip}")

def block_ip(ip):
    subprocess.run(["iptables", "-A", "INPUT", "-s", ip, "-p", "tcp", "--dport", "22", "-j", "DROP"], check=True)
    blocked_ips.add(ip)
    print(f"[!] Blocked IP: {ip}")

def unblock_expired_ips():
    now = datetime.now()
    expired = []
    for ip in list(blocked_ips):
        result = subprocess.run(
            ["iptables", "-C", "INPUT", "-s", ip, "-p", "tcp", "--dport", "22", "-j", "DROP"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode == 0:
            subprocess.run(["iptables", "-D", "INPUT", "-s", ip, "-p", "tcp", "--dport", "22", "-j", "DROP"], check=True)
            expired.append(ip)
            print(f"[+] Unblocked IP: {ip}")
    for ip in expired:
        blocked_ips.discard(ip)

def print_row(status, dt, user, ip):
    print(f"{status:<9} {dt:<15} {user:<15} {ip:<15}")

def print_header():
    print("=" * 60)
    print_row("STATUS", "TIMESTAMP", "USER", "IP ADDRESS")
    print("=" * 60)

def monitor_journal():
    known_ips = load_known_ips()
    honeypotted_ips = load_honeypotted_ips()

    proc = subprocess.Popen(["journalctl", "-u", "ssh", "-f", "--no-pager"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    print_header()

    while True:
        line = proc.stdout.readline()
        if not line:
            time.sleep(0.1)
            continue

        unblock_expired_ips()

        fail = FAILED_REGEX.search(line)
        if fail:
            dt = fail.group("datetime")
            user = fail.group("user")
            ip = fail.group("ip")
            print_row("FAILED", dt, user, ip)

            if ip in blocked_ips:
                continue

            failed_attempts[ip] = failed_attempts.get(ip, 0) + 1
            if failed_attempts[ip] >= BAN_THRESHOLD:
                block_ip(ip)
                failed_attempts[ip] = 0
            continue

        success = SUCCESS_REGEX.search(line)
        if success:
            dt = success.group("datetime")
            user = success.group("user")
            ip = success.group("ip")
            print_row("SUCCESS", dt, user, ip)

            if ip in known_ips:
                if ip in honeypotted_ips:
                    remove_from_honeypot_conf(ip)
                    honeypotted_ips.discard(ip)
            else:
                if ip not in honeypotted_ips:
                    setup_honeypot_for_new_ip(ip)
                    honeypotted_ips.add(ip)

            failed_attempts[ip] = 0

if __name__ == "__main__":
    if subprocess.getoutput("whoami") != "root":
        print("Run as root: sudo python3 ssh_guard.py")
        sys.exit(1)
    try:
        monitor_journal()
    except KeyboardInterrupt:
        print("\n[!] Exiting monitor.")

#!/usr/bin/env python3
import subprocess
import re

def list_blocked_ips():
    try:
        result = subprocess.run(["iptables", "-L", "INPUT", "-n", "--line-numbers"],
                                capture_output=True, text=True, check=True)
        lines = result.stdout.strip().split("\n")

        blocked_entries = []
        for line in lines:
            if "tcp" in line and "dpt:22" in line and "DROP" in line:
                match_ip = re.search(r"(\d+\.\d+\.\d+\.\d+)", line)
                match_line = re.match(r"^\s*(\d+)", line)
                if match_ip and match_line:
                    blocked_entries.append((int(match_line.group(1)), match_ip.group(1)))

        return blocked_entries

    except subprocess.CalledProcessError as e:
        print("❌ Failed to retrieve iptables rules:", e)
        return []

def remove_ip_by_line_number(line_number):
    try:
        subprocess.run(["iptables", "-D", "INPUT", str(line_number)],
                       check=True)
        print(f"✅ Unblocked IP at line {line_number}.")

        # Clear logs after successful unblock
        print("🧹 Clearing journal logs...")
        subprocess.run(["journalctl", "--rotate"], check=True)
        subprocess.run(["journalctl", "--vacuum-time=1s"], check=True)
        print("🧼 Logs cleared.")

    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to unblock IP at line {line_number}: {e}")

def main():
    blocked = list_blocked_ips()
    if not blocked:
        print("✅ No SSH IPs are currently blocked.")
        return

    print("\n🚫 Blocked SSH IPs:")
    for idx, (line_num, ip) in enumerate(blocked, 1):
        print(f"{idx}. {ip} (iptables line {line_num})")

    try:
        choice = input("\nEnter serial number of IP to unblock (or press Enter to skip): ").strip()
        if not choice:
            print("➡️ No action taken.")
            return
        selected = int(choice)
        if 1 <= selected <= len(blocked):
            line_number = blocked[selected - 1][0]
            remove_ip_by_line_number(line_number)
        else:
            print("❌ Invalid selection.")
    except ValueError:
        print("❌ Please enter a valid number.")

if __name__ == "__main__":
    if subprocess.getoutput("whoami") != "root":
        print("❌ This script must be run as root. Use: sudo python3 ssh_block_manager.py")
    else:
        main()

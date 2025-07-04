#!/bin/bash

# Welcome message
echo "Welcome to Ubuntu 20.04.6 LTS"

# Fake filesystem structure:
# Use associative arrays to represent directories and files
# Keys: path, Values: content or list of children

declare -A FS_TYPE    # "dir" or "file"
declare -A FS_CONTENT # file content or directory children (space-separated)

# Initialize fake filesystem

# Root directory
FS_TYPE["/"]="dir"
FS_CONTENT["/"]="home etc var usr bin lib tmp"

# /home directory
FS_TYPE["/home"]="dir"
FS_CONTENT["/home"]="ubuntu"

# /home/ubuntu directory
FS_TYPE["/home/ubuntu"]="dir"
FS_CONTENT["/home/ubuntu"]="Desktop Documents Downloads Music Pictures Public Templates Videos .bashrc .profile"

# Sample files in /home/ubuntu
FS_TYPE["/home/ubuntu/.bashrc"]="file"
FS_CONTENT["/home/ubuntu/.bashrc"]="# ~/.bashrc: executed by bash(1) for non-login shells.\n\n# You may uncomment the following lines if you want 'ls' to be colorized:\n# export LS_OPTIONS='--color=auto'\n# eval \"\`dircolors\`\"\n# alias ls='ls $LS_OPTIONS'\n"

FS_TYPE["/home/ubuntu/.profile"]="file"
FS_CONTENT["/home/ubuntu/.profile"]="export PATH=\"\$HOME/bin:\$PATH\"\n"

# /etc directory
FS_TYPE["/etc"]="dir"
FS_CONTENT["/etc"]="passwd hosts hostname os-release"

# /etc/passwd file (simplified)
FS_TYPE["/etc/passwd"]="file"
FS_CONTENT["/etc/passwd"]="ubuntu:x:1000:1000:Ubuntu User:/home/ubuntu:/bin/bash\nroot:x:0:0:root:/root:/bin/bash\n"

# /etc/hosts file
FS_TYPE["/etc/hosts"]="file"
FS_CONTENT["/etc/hosts"]="127.0.0.1 localhost\n127.0.1.1 honeypot\n"

# /etc/hostname file
FS_TYPE["/etc/hostname"]="file"
FS_CONTENT["/etc/hostname"]="honeypot\n"

# /etc/os-release file
FS_TYPE["/etc/os-release"]="file"
FS_CONTENT["/etc/os-release"]="NAME=\"Ubuntu\"\nVERSION=\"20.04.6 LTS (Focal Fossa)\"\nID=ubuntu\nID_LIKE=debian\nPRETTY_NAME=\"Ubuntu 20.04.6 LTS\"\nVERSION_ID=\"20.04\"\nHOME_URL=\"https://www.ubuntu.com/\"\nSUPPORT_URL=\"https://help.ubuntu.com/\"\nBUG_REPORT_URL=\"https://bugs.launchpad.net/ubuntu/\"\n"

# /var directory
FS_TYPE["/var"]="dir"
FS_CONTENT["/var"]="log"

# /var/log directory
FS_TYPE["/var/log"]="dir"
FS_CONTENT["/var/log"]="syslog auth.log"

# /var/log/syslog file
FS_TYPE["/var/log/syslog"]="file"
FS_CONTENT["/var/log/syslog"]="Jul  3 10:45:00 honeypot systemd[1]: Started Session 1234 of user ubuntu.\n"

# /var/log/auth.log file
FS_TYPE["/var/log/auth.log"]="file"
FS_CONTENT["/var/log/auth.log"]="Jul  3 10:45:00 honeypot sshd[1234]: Accepted password for ubuntu from 192.168.1.100 port 54321 ssh2\n"

# /usr directory
FS_TYPE["/usr"]="dir"
FS_CONTENT["/usr"]="bin lib share"

# /bin directory (simulate some commands here)
FS_TYPE["/bin"]="dir"
FS_CONTENT["/bin"]="bash ls cat echo date uptime uname ps df free whoami"

# Current working directory variable
CWD="/home/ubuntu"

# Helper function to join paths cleanly
join_path() {
    local base="$1"
    local add="$2"
    if [[ "$add" == /* ]]; then
        echo "$add"
    else
        if [[ "$base" == "/" ]]; then
            echo "/$add"
        else
            echo "$base/$add"
        fi
    fi
}

# Normalize path (handle . and ..)
normalize_path() {
    local path="$1"
    local -a parts newparts
    IFS='/' read -ra parts <<< "$path"
    for part in "${parts[@]}"; do
        case "$part" in
            ""|".") ;;
            "..") if [[ ${#newparts[@]} -gt 0 ]]; then
                      unset 'newparts[${#newparts[@]}-1]'
                  fi
                  ;;
            *) newparts+=("$part") ;;
        esac
    done
    local result="/"
    local first=1
    for p in "${newparts[@]}"; do
        if [[ $first -eq 1 ]]; then
            result+="$p"
            first=0
        else
            result+="/$p"
        fi
    done
    echo "$result"
}

# Check if path exists and is directory or file
fs_exists() {
    local path="$1"
    [[ -n "${FS_TYPE[$path]}" ]]
}

fs_is_dir() {
    local path="$1"
    [[ "${FS_TYPE[$path]}" == "dir" ]]
}

fs_is_file() {
    local path="$1"
    [[ "${FS_TYPE[$path]}" == "file" ]]
}

# List directory contents
fs_ls() {
    local path="$1"
    if ! fs_exists "$path"; then
        echo "ls: cannot access '$path': No such file or directory"
        return 1
    fi
    if ! fs_is_dir "$path"; then
        echo "$path"
        return 0
    fi
    echo "${FS_CONTENT[$path]}"
}

# Read file contents
fs_cat() {
    local path="$1"
    if ! fs_exists "$path"; then
        echo "cat: $path: No such file or directory"
        return 1
    fi
    if ! fs_is_file "$path"; then
        echo "cat: $path: Is a directory"
        return 1
    fi
    echo -e "${FS_CONTENT[$path]}"
}

# Main command loop
while true; do
    # Show prompt
    read -rp "$USER@honeypot:$CWD$ " input_line
    [[ -z "$input_line" ]] && continue

    # Parse command and args
    cmd=$(echo "$input_line" | awk '{print $1}')
    args="${input_line#$cmd}"
    args="${args#"${args%%[![:space:]]*}"}"  # trim leading spaces

    case "$cmd" in
        ls)
            # Support ls with optional path
            target="$CWD"
            if [[ -n "$args" ]]; then
                # Support multiple args? For simplicity, just first arg
                target_path=$(normalize_path "$(join_path "$CWD" "$args")")
            else
                target_path="$CWD"
            fi
            output=$(fs_ls "$target_path")
            if [[ $? -eq 0 ]]; then
                # Format output like ls - list items in columns
                echo "$output" | tr ' ' '\n' | column
            else
                echo "$output"
            fi
            ;;
        pwd)
            echo "$CWD"
            ;;
        cd)
            if [[ -z "$args" ]]; then
                # cd to home
                CWD="/home/$USER"
            else
                target_path=$(normalize_path "$(join_path "$CWD" "$args")")
                if fs_exists "$target_path" && fs_is_dir "$target_path"; then
                    CWD="$target_path"
                else
                    echo "bash: cd: $args: No such file or directory"
                fi
            fi
            ;;
        cat)
            if [[ -z "$args" ]]; then
                echo "cat: missing file operand"
            else
                target_path=$(normalize_path "$(join_path "$CWD" "$args")")
                fs_cat "$target_path"
            fi
            ;;
        echo)
            echo "$args"
            ;;
        whoami)
            echo "$USER"
            ;;
        date)
            date "+%a %b %e %H:%M:%S %Z %Y"
            ;;
        uname)
            if [[ "$args" == "-a" ]]; then
                echo "Linux honeypot 5.4.0-42-generic #46-Ubuntu SMP Fri Jul 10 00:24:02 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux"
            else
                echo "Linux"
            fi
            ;;
        uptime)
            echo " 10:45:00 up 1 day,  3:23,  1 user,  load average: 0.00, 0.01, 0.05"
            ;;
        df)
            if [[ "$args" == "-h" ]]; then
                echo -e "Filesystem      Size  Used Avail Use% Mounted on\n/dev/sda1        50G   15G   33G  31% /"
            else
                echo "Filesystem     1K-blocks    Used Available Use% Mounted on"
                echo "/dev/sda1      52428800 15728640 34603008  31% /"
            fi
            ;;
        free)
            if [[ "$args" == "-m" ]]; then
                echo -e "              total        used        free      shared  buff/cache   available\nMem:           7977        1234        4567         123        2175        6345"
            else
                echo "              total        used        free      shared  buff/cache   available"
                echo "Mem:           8160000     1260000     4670000      123000     2220000     6450000"
            fi
            ;;
        ps)
            if [[ "$args" == "aux" ]]; then
                echo -e "USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND"
                echo "ubuntu    1234  0.0  0.1  123456  2345 pts/0    Ss   10:00   0:00 bash"
            else
                echo "  PID TTY          TIME CMD"
                echo " 1234 pts/0    00:00:00 bash"
            fi
            ;;
        exit|logout)
            echo "logout"
            break
            ;;
        *)
            echo "bash: $cmd: command not found"
            ;;
    esac
done

#!/bin/bash
set -e

PKG_NAME="serverpulse-motd"
PKG_VERSION="1.6.0"
PKG_ARCH="all"
BUILD_DIR="${PKG_NAME}"
DEB_FILE="${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"
BIN_FILE="serverpulse-motd"
PROFILE_FILE="serverpulse.sh"

rm -rf "$BUILD_DIR" "$DEB_FILE"

mkdir -p "$BUILD_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/usr/local/bin"
mkdir -p "$BUILD_DIR/etc/profile.d"

cat > "$BUILD_DIR/DEBIAN/control" <<CONTROL
Package: $PKG_NAME
Version: $PKG_VERSION
Section: admin
Priority: optional
Architecture: $PKG_ARCH
Maintainer: Ali Mustofa <hai.alimustofa@gmail.com>
Depends: bash, coreutils, procps, iproute2
Recommends: curl, ufw, apt
Description: ServerPulse MOTD dashboard for Ubuntu
 ServerPulse installs a colorful optimized system dashboard shown when users login via SSH.
 This version uses /etc/profile.d instead of PAM and includes cache plus parallel processing.
CONTROL

cat > "$BUILD_DIR/etc/profile.d/$PROFILE_FILE" <<'PROFILE'
#!/bin/bash

# ServerPulse SSH Login Dashboard
# Run only once for interactive SSH sessions.

case "$-" in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac

if [ -n "$SERVERPULSE_SHOWN" ]; then
    return 0 2>/dev/null || exit 0
fi

export SERVERPULSE_SHOWN=1

if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ]; then
    if [ -x /usr/local/bin/serverpulse-motd ]; then
        /usr/local/bin/serverpulse-motd
    fi
fi
PROFILE

cat > "$BUILD_DIR/usr/local/bin/$BIN_FILE" <<'SCRIPT'
#!/bin/bash

export LC_ALL=C

# =========================
# Cache Config
# =========================
CACHE_DIR="/tmp/serverpulse-cache-${USER:-default}"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

PUBLIC_IP_TTL=300
FAILED_LOGIN_TTL=300
APT_TTL=1800

# =========================
# Colors
# =========================
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
GRAY="\033[0;37m"
RESET="\033[0m"

line() {
    echo -e "${CYAN}======================================================================${RESET}"
}

dash() {
    echo -e "${GRAY}----------------------------------------------------------------------${RESET}"
}

usage_color() {
    local percent="$1"

    if [ "$percent" -ge 80 ] 2>/dev/null; then
        echo "$RED"
    elif [ "$percent" -ge 60 ] 2>/dev/null; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

status_color() {
    local value="$1"

    case "$value" in
        active|running|enabled|No|0|0%)
            echo -e "${GREEN}${value}${RESET}"
            ;;
        inactive|disabled|failed|Yes)
            echo -e "${RED}${value}${RESET}"
            ;;
        not-installed|unknown|N/A)
            echo -e "${YELLOW}${value}${RESET}"
            ;;
        *)
            echo -e "${WHITE}${value}${RESET}"
            ;;
    esac
}

bar() {
    local percent="$1"
    local total=20
    local filled=0
    local empty=20
    local color

    [ -z "$percent" ] && percent=0

    if [ "$percent" -lt 0 ] 2>/dev/null; then
        percent=0
    fi

    if [ "$percent" -gt 100 ] 2>/dev/null; then
        percent=100
    fi

    filled=$((percent * total / 100))
    empty=$((total - filled))
    color=$(usage_color "$percent")

    printf "["
    printf "${color}"
    for ((i=0; i<filled; i++)); do
        printf "█"
    done
    printf "${RESET}"
    for ((i=0; i<empty; i++)); do
        printf "."
    done
    printf "]"
}

human_bytes() {
    local bytes="$1"

    awk -v b="$bytes" 'BEGIN {
        if (b >= 1099511627776) printf "%.1f TB", b/1099511627776;
        else if (b >= 1073741824) printf "%.1f GB", b/1073741824;
        else if (b >= 1048576) printf "%.1f MB", b/1048576;
        else if (b >= 1024) printf "%.1f KB", b/1024;
        else printf "%.0f B", b;
    }'
}

cache_get_or_run() {
    local cache_file="$1"
    local ttl="$2"
    shift 2

    local now
    local modified

    if [ -f "$cache_file" ]; then
        now=$(date +%s)
        modified=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)

        if [ $((now - modified)) -lt "$ttl" ]; then
            cat "$cache_file"
            return
        fi
    fi

    "$@" > "${cache_file}.tmp" 2>/dev/null || echo "N/A" > "${cache_file}.tmp"
    mv "${cache_file}.tmp" "$cache_file" 2>/dev/null || true
    cat "$cache_file" 2>/dev/null || echo "N/A"
}

get_public_ip() {
    curl -4 -s --max-time 1 https://api.ipify.org 2>/dev/null ||
    curl -4 -s --max-time 1 https://ifconfig.me 2>/dev/null ||
    curl -s --max-time 1 https://api.ipify.org 2>/dev/null ||
    curl -s --max-time 1 https://ifconfig.me 2>/dev/null ||
    echo "N/A"
}

get_failed_login() {
    journalctl _COMM=sshd --since today --no-pager 2>/dev/null |
        grep -Ei "Failed password|Invalid user|authentication failure" |
        wc -l
}

get_pending_update() {
    if command -v apt >/dev/null 2>&1; then
        apt list --upgradable 2>/dev/null | grep -c upgradable || true
    else
        echo "N/A"
    fi
}

get_security_fix() {
    if command -v apt >/dev/null 2>&1; then
        apt list --upgradable 2>/dev/null | grep -Ei "security|ubuntu-security" | wc -l || true
    else
        echo "N/A"
    fi
}

# =========================
# Basic Info - Fast
# =========================
HOSTNAME=$(hostname 2>/dev/null || echo "N/A")

OS_VERSION=$(
    lsb_release -ds 2>/dev/null ||
    grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' ||
    echo "N/A"
)

KERNEL=$(uname -r 2>/dev/null || echo "N/A")

IP_ADDRESS=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$IP_ADDRESS" ] && IP_ADDRESS="N/A"

UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
[ -z "$UPTIME" ] && UPTIME="N/A"

# =========================
# CPU Info - Fast
# =========================
CPU_LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo "N/A")
CPU_CORES=$(nproc 2>/dev/null || echo "N/A")

CPU_USAGE=$(top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)/ {
    for (i=1; i<=NF; i++) {
        if ($i ~ /id/) {
            gsub(/[^0-9.]/, "", $i)
            printf "%.0f", 100 - $i
        }
    }
}')

[ -z "$CPU_USAGE" ] && CPU_USAGE="0"

# =========================
# Memory Info - Fast
# =========================
MEM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%.1f", $2/1024}')
MEM_USED=$(free -m 2>/dev/null | awk '/Mem:/ {printf "%.1f", $3/1024}')
MEM_PERCENT=$(free 2>/dev/null | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')

[ -z "$MEM_TOTAL" ] && MEM_TOTAL="0.0"
[ -z "$MEM_USED" ] && MEM_USED="0.0"
[ -z "$MEM_PERCENT" ] && MEM_PERCENT="0"

# =========================
# Swap Info - Fast
# =========================
SWAP_TOTAL_MB=$(free -m 2>/dev/null | awk '/Swap:/ {print $2}')
SWAP_USED_MB=$(free -m 2>/dev/null | awk '/Swap:/ {print $3}')

if [ -z "$SWAP_TOTAL_MB" ] || [ "$SWAP_TOTAL_MB" -eq 0 ] 2>/dev/null; then
    SWAP_TOTAL="0 B"
    SWAP_USED="0 B"
    SWAP_PERCENT="0"
else
    SWAP_TOTAL=$(awk -v mb="$SWAP_TOTAL_MB" 'BEGIN {printf "%.1f G", mb/1024}')
    SWAP_USED=$(awk -v mb="$SWAP_USED_MB" 'BEGIN {printf "%.1f G", mb/1024}')
    SWAP_PERCENT=$(awk -v used="$SWAP_USED_MB" -v total="$SWAP_TOTAL_MB" 'BEGIN {printf "%.0f", used/total*100}')
fi

# =========================
# Disk Info - Fast
# =========================
DISK_TOTAL=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')
DISK_PERCENT=$(df / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
INODE_PERCENT=$(df -i / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')

[ -z "$DISK_TOTAL" ] && DISK_TOTAL="N/A"
[ -z "$DISK_USED" ] && DISK_USED="N/A"
[ -z "$DISK_PERCENT" ] && DISK_PERCENT="0"
[ -z "$INODE_PERCENT" ] && INODE_PERCENT="0"

ROOT_DEV=$(df / 2>/dev/null | awk 'NR==2 {print $1}' | sed 's#/dev/##')

if [ -n "$ROOT_DEV" ] && [ -f /proc/diskstats ]; then
    DISK_READ_MB=$(awk -v dev="$ROOT_DEV" '$3==dev {printf "%.0f", $6*512/1024/1024}' /proc/diskstats 2>/dev/null)
    DISK_WRITE_MB=$(awk -v dev="$ROOT_DEV" '$3==dev {printf "%.0f", $10*512/1024/1024}' /proc/diskstats 2>/dev/null)

    [ -z "$DISK_READ_MB" ] && DISK_READ_MB="0"
    [ -z "$DISK_WRITE_MB" ] && DISK_WRITE_MB="0"

    DISK_IO="Read ${DISK_READ_MB}MB | Write ${DISK_WRITE_MB}MB"
else
    DISK_IO="N/A"
fi

# =========================
# GPU Info - Optimized
# =========================
if command -v nvidia-smi >/dev/null 2>&1; then
    GPU_AVAILABLE="Yes"

    GPU_QUERY=$(nvidia-smi --query-gpu=name,driver_version,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit --format=csv,noheader,nounits 2>/dev/null | head -n 1)

    GPU_NAME=$(echo "$GPU_QUERY" | awk -F', ' '{print $1}')
    GPU_DRIVER=$(echo "$GPU_QUERY" | awk -F', ' '{print $2}')
    GPU_UTIL=$(echo "$GPU_QUERY" | awk -F', ' '{print $3}')
    GPU_MEM_USED=$(echo "$GPU_QUERY" | awk -F', ' '{print $4}')
    GPU_MEM_TOTAL=$(echo "$GPU_QUERY" | awk -F', ' '{print $5}')
    GPU_TEMP=$(echo "$GPU_QUERY" | awk -F', ' '{print $6}')
    GPU_POWER_DRAW=$(echo "$GPU_QUERY" | awk -F', ' '{print $7}')
    GPU_POWER_LIMIT=$(echo "$GPU_QUERY" | awk -F', ' '{print $8}')

    GPU_CUDA=$(nvidia-smi 2>/dev/null | grep -oP 'CUDA Version:[[:space:]]*\K[0-9.]+' | head -n 1)
    GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)

    [ -z "$GPU_NAME" ] && GPU_NAME="N/A"
    [ -z "$GPU_DRIVER" ] && GPU_DRIVER="N/A"
    [ -z "$GPU_CUDA" ] && GPU_CUDA="N/A"
    [ -z "$GPU_UTIL" ] && GPU_UTIL="0"
    [ -z "$GPU_MEM_USED" ] && GPU_MEM_USED="0"
    [ -z "$GPU_MEM_TOTAL" ] && GPU_MEM_TOTAL="0"
    [ -z "$GPU_TEMP" ] && GPU_TEMP="N/A"
    [ -z "$GPU_POWER_DRAW" ] && GPU_POWER_DRAW="N/A"
    [ -z "$GPU_POWER_LIMIT" ] && GPU_POWER_LIMIT="N/A"
    [ -z "$GPU_COUNT" ] && GPU_COUNT="1"

    if [ "$GPU_MEM_TOTAL" -gt 0 ] 2>/dev/null; then
        GPU_MEM_PERCENT=$(awk -v used="$GPU_MEM_USED" -v total="$GPU_MEM_TOTAL" 'BEGIN {printf "%.0f", used/total*100}')
    else
        GPU_MEM_PERCENT="0"
    fi
else
    GPU_AVAILABLE="No"
    GPU_COUNT="0"
    GPU_NAME="No NVIDIA GPU detected"
    GPU_DRIVER="N/A"
    GPU_CUDA="N/A"
    GPU_UTIL="0"
    GPU_MEM_USED="0"
    GPU_MEM_TOTAL="0"
    GPU_MEM_PERCENT="0"
    GPU_TEMP="N/A"
    GPU_POWER_DRAW="N/A"
    GPU_POWER_LIMIT="N/A"
fi

# =========================
# SSH Info - Fast Part
# =========================
SSH_USERS=$(who 2>/dev/null | wc -l)

LAST_LOGIN=$(last -n 1 -w 2>/dev/null | head -n 1 | awk '{print $1" from "$3}')
[ -z "$LAST_LOGIN" ] && LAST_LOGIN="N/A"

# =========================
# Security Fast Part
# =========================
if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED="Yes"
else
    REBOOT_REQUIRED="No"
fi

if command -v ufw >/dev/null 2>&1; then
    FIREWALL=$(ufw status 2>/dev/null | head -n 1 | awk -F': ' '{print $2}')
    [ -z "$FIREWALL" ] && FIREWALL="inactive"
else
    FIREWALL="not-installed"
fi

# =========================
# Network Info - Fast
# =========================
INTERFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
[ -z "$INTERFACE" ] && INTERFACE="N/A"

if [ "$INTERFACE" != "N/A" ] && [ -d "/sys/class/net/$INTERFACE/statistics" ]; then
    RX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    TX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo 0)

    RX_HUMAN=$(human_bytes "$RX_BYTES")
    TX_HUMAN=$(human_bytes "$TX_BYTES")

    RX_TX="${RX_HUMAN} / ${TX_HUMAN}"
else
    RX_TX="N/A"
fi

DNS=$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')
[ -z "$DNS" ] && DNS="N/A"

GATEWAY=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
[ -z "$GATEWAY" ] && GATEWAY="N/A"

# =========================
# Heavy Data - Parallel + Cache
# =========================
TMP_PUBLIC_IP="$CACHE_DIR/public_ip.result"
TMP_FAILED_LOGIN="$CACHE_DIR/failed_login.result"
TMP_PENDING_UPDATE="$CACHE_DIR/pending_update.result"
TMP_SECURITY_FIX="$CACHE_DIR/security_fix.result"

(
    cache_get_or_run "$CACHE_DIR/public_ip.cache" "$PUBLIC_IP_TTL" get_public_ip
) > "$TMP_PUBLIC_IP" 2>/dev/null &

PID_PUBLIC_IP=$!

(
    cache_get_or_run "$CACHE_DIR/failed_login.cache" "$FAILED_LOGIN_TTL" get_failed_login
) > "$TMP_FAILED_LOGIN" 2>/dev/null &

PID_FAILED_LOGIN=$!

(
    cache_get_or_run "$CACHE_DIR/pending_update.cache" "$APT_TTL" get_pending_update
) > "$TMP_PENDING_UPDATE" 2>/dev/null &

PID_PENDING_UPDATE=$!

(
    cache_get_or_run "$CACHE_DIR/security_fix.cache" "$APT_TTL" get_security_fix
) > "$TMP_SECURITY_FIX" 2>/dev/null &

PID_SECURITY_FIX=$!

wait "$PID_PUBLIC_IP" 2>/dev/null || true
wait "$PID_FAILED_LOGIN" 2>/dev/null || true
wait "$PID_PENDING_UPDATE" 2>/dev/null || true
wait "$PID_SECURITY_FIX" 2>/dev/null || true

PUBLIC_IP=$(cat "$TMP_PUBLIC_IP" 2>/dev/null || echo "N/A")
FAILED_LOGIN=$(cat "$TMP_FAILED_LOGIN" 2>/dev/null || echo "0")
PENDING_UPDATE=$(cat "$TMP_PENDING_UPDATE" 2>/dev/null || echo "N/A")
SECURITY_FIX=$(cat "$TMP_SECURITY_FIX" 2>/dev/null || echo "N/A")

[ -z "$PUBLIC_IP" ] && PUBLIC_IP="N/A"
[ -z "$FAILED_LOGIN" ] && FAILED_LOGIN="0"
[ -z "$PENDING_UPDATE" ] && PENDING_UPDATE="N/A"
[ -z "$SECURITY_FIX" ] && SECURITY_FIX="N/A"

# =========================
# Output
# =========================
echo
LOGIN_USER="${USER:-$(whoami 2>/dev/null || echo user)}"
echo -e "${CYAN}⚡ Welcome ${GREEN}${LOGIN_USER}${RESET}"
line

echo -e "${WHITE}Hostname       :${RESET} ${GREEN}${HOSTNAME}${RESET}"
echo -e "${WHITE}OS Version     :${RESET} ${OS_VERSION}"
echo -e "${WHITE}Kernel         :${RESET} ${KERNEL}"
echo -e "${WHITE}IP Address     :${RESET} ${GREEN}${IP_ADDRESS}${RESET}"
echo -e "${WHITE}Public IP      :${RESET} ${GREEN}${PUBLIC_IP}${RESET}"
echo -e "${WHITE}Uptime         :${RESET} ${YELLOW}${UPTIME}${RESET}"

dash

echo -e "${CYAN}CPU & Memory${RESET}"
echo -e "${WHITE}CPU Load       :${RESET} ${CPU_LOAD}"
echo -e "${WHITE}CPU Usage      :${RESET} $(bar "$CPU_USAGE") ${CPU_USAGE}%"
echo -e "${WHITE}CPU Cores      :${RESET} ${CPU_CORES}"
echo -e "${WHITE}Memory         :${RESET} $(bar "$MEM_PERCENT") ${MEM_PERCENT}% (${MEM_USED} G / ${MEM_TOTAL} G)"
echo -e "${WHITE}Swap           :${RESET} $(bar "$SWAP_PERCENT") ${SWAP_PERCENT}% (${SWAP_USED} / ${SWAP_TOTAL})"

dash

echo -e "${CYAN}Disk${RESET}"
echo -e "${WHITE}Disk Usage     :${RESET} $(bar "$DISK_PERCENT") ${DISK_PERCENT}% (${DISK_USED} / ${DISK_TOTAL})"
echo -e "${WHITE}Inode Usage    :${RESET} $(bar "$INODE_PERCENT") ${INODE_PERCENT}%"
echo -e "${WHITE}Disk I/O       :${RESET} ${DISK_IO}"

dash

echo -e "${CYAN}GPU${RESET}"
if [ "$GPU_AVAILABLE" = "Yes" ]; then
    echo -e "${WHITE}- GPU Count     :${RESET} ${GPU_COUNT}"
    echo -e "${WHITE}- GPU Name      :${RESET} ${GREEN}${GPU_NAME}${RESET}"
    echo -e "${WHITE}- Driver        :${RESET} ${GPU_DRIVER}"
    echo -e "${WHITE}- CUDA          :${RESET} ${GPU_CUDA}"
    echo -e "${WHITE}- GPU Usage     :${RESET} $(bar "$GPU_UTIL") ${GPU_UTIL}%"
    echo -e "${WHITE}- GPU Memory    :${RESET} $(bar "$GPU_MEM_PERCENT") ${GPU_MEM_PERCENT}% (${GPU_MEM_USED} MiB / ${GPU_MEM_TOTAL} MiB)"
    echo -e "${WHITE}- GPU Temp      :${RESET} ${YELLOW}${GPU_TEMP}°C${RESET}"
    echo -e "${WHITE}- GPU Power     :${RESET} ${GPU_POWER_DRAW}W / ${GPU_POWER_LIMIT}W"
else
    echo -e "${WHITE}- Status        :${RESET} ${YELLOW}No NVIDIA GPU detected${RESET}"
fi

dash

echo -e "${CYAN}SSH${RESET}"
echo -e "${WHITE}SSH Users      :${RESET} ${SSH_USERS} active session"
echo -e "${WHITE}Last Login     :${RESET} ${LAST_LOGIN}"
echo -e "${WHITE}Failed Login   :${RESET} $(status_color "$FAILED_LOGIN") attempts today"

dash

echo -e "${CYAN}Security${RESET}"
echo -e "${WHITE}- Pending Update:${RESET} ${YELLOW}${PENDING_UPDATE}${RESET} packages"
echo -e "${WHITE}- Security Fix  :${RESET} ${RED}${SECURITY_FIX}${RESET} packages"
echo -e "${WHITE}- Reboot Needed :${RESET} $(status_color "$REBOOT_REQUIRED")"
echo -e "${WHITE}- Firewall      :${RESET} $(status_color "$FIREWALL")"

dash

echo -e "${CYAN}Network${RESET}"
echo -e "${WHITE}- Interface     :${RESET} ${INTERFACE}"
echo -e "${WHITE}- RX/TX         :${RESET} ${RX_TX}"
echo -e "${WHITE}- DNS           :${RESET} ${DNS}"
echo -e "${WHITE}- Gateway       :${RESET} ${GATEWAY}"

line
echo -e "${YELLOW}💡 Managed by   :${RESET} ${CYAN}https://alimustofa.my.id${RESET}"
line
echo

SCRIPT

cat > "$BUILD_DIR/DEBIAN/postinst" <<'POSTINST'
#!/bin/bash
set -e

# Remove old ServerPulse MOTD location to prevent double output from Ubuntu MOTD/PAM.
rm -f /etc/update-motd.d/99-serverpulse

chown root:root /usr/local/bin/serverpulse-motd
chmod 755 /usr/local/bin/serverpulse-motd

chown root:root /etc/profile.d/serverpulse.sh
chmod 755 /etc/profile.d/serverpulse.sh

# Prevent OpenSSH static MOTD duplication.
# ServerPulse is shown by /etc/profile.d/serverpulse.sh instead.
if [ -f /etc/ssh/sshd_config ]; then
    if grep -q '^#*PrintMotd ' /etc/ssh/sshd_config; then
        sed -i 's/^#*PrintMotd .*/PrintMotd no/' /etc/ssh/sshd_config
    else
        echo 'PrintMotd no' >> /etc/ssh/sshd_config
    fi

    if command -v sshd >/dev/null 2>&1; then
        sshd -t
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    fi
fi

exit 0
POSTINST

cat > "$BUILD_DIR/DEBIAN/prerm" <<'PRERM'
#!/bin/bash
set -e

rm -f /usr/local/bin/serverpulse-motd
rm -f /etc/update-motd.d/99-serverpulse
rm -f /etc/profile.d/serverpulse.sh

exit 0
PRERM

cat > "$BUILD_DIR/DEBIAN/postrm" <<'POSTRM'
#!/bin/bash
set -e

exit 0
POSTRM

chmod 755 "$BUILD_DIR/DEBIAN/postinst"
chmod 755 "$BUILD_DIR/DEBIAN/prerm"
chmod 755 "$BUILD_DIR/DEBIAN/postrm"
chmod 755 "$BUILD_DIR/usr/local/bin/$BIN_FILE"
chmod 755 "$BUILD_DIR/etc/profile.d/$PROFILE_FILE"

dpkg-deb --build "$BUILD_DIR" "$DEB_FILE"

echo
echo "Build done: $DEB_FILE"
echo
echo "Install:"
echo "sudo dpkg -i $DEB_FILE"
echo
echo "Test manual:"
echo "/usr/local/bin/serverpulse-motd"
echo
echo "Test SSH:"
echo "exit"
echo "ssh user@server-ip"
echo
#!/usr/bin/env bash
# ==========================================================================
#  Fortnite STW Telegram Bot — hardened installer
#  Re-runnable: running it again upgrades the code and keeps your config.
# ==========================================================================
set -Eeuo pipefail

# Bump this on every release. The bot compares it — and the checksum of this
# file — against the published copy to decide whether an update is available.
BOT_VERSION="2.2.0"
UPDATE_URL="https://github.com/Plus98ir/Fortnite_Missions/releases/latest/download/install_fortnite_bot.sh"
# Default art pack (square PNGs, same names as in ART_DIR). Override with
# ART_URL in bot.env, or set ART_URL="" there to keep only your own art.
ART_URL_DEFAULT="https://github.com/Plus98ir/Fortnite_Missions/releases/latest/download/art.zip"

UNATTENDED="no"
for arg in "$@"; do
    case "$arg" in
        --unattended|-y|--yes) UNATTENDED="yes" ;;
        --version|-V) echo "$BOT_VERSION"; exit 0 ;;
        --help|-h) echo "usage: $0 [--unattended] [--version]"; exit 0 ;;
    esac
done

APP_USER="fnbot"
APP_DIR="/opt/fortnite_bot"
CONF_DIR="/etc/fortnite_bot"
CONF_FILE="$CONF_DIR/bot.env"
DATA_DIR="/var/lib/fortnite_bot"
SERVICE="fortnite-bot"
UNIT="/etc/systemd/system/${SERVICE}.service"
UPD_UNIT="/etc/systemd/system/${SERVICE}-update.service"
UPD_PATH="/etc/systemd/system/${SERVICE}-update.path"
SHA_FILE="$CONF_DIR/installer.sha256"
LEGACY_DIR="/root/fortnite_bot"

c_ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
die()    { c_err "❌ $*"; exit 1; }

trap 'c_err "Installation failed on line $LINENO."' ERR

[[ $EUID -eq 0 ]] || die "Please run as root (sudo bash $0)."
command -v apt-get >/dev/null 2>&1 || die "This installer supports Debian/Ubuntu only."
command -v systemctl >/dev/null 2>&1 || die "systemd is required."

# Only clear when we actually have a terminal: under systemd (the updater)
# there is no TERM and `clear` would fail the whole run.
if [[ -t 1 ]]; then clear || true; fi
echo "===================================================="
echo "    Fortnite STW Telegram Bot — Installer"
echo "===================================================="
echo ""

# --------------------------------------------------------------------------
# 1. Configuration
# --------------------------------------------------------------------------
BOT_TOKEN=""; ADMIN_CHAT_ID=""; PROXY_URL=""
REUSE="n"
if [[ -f "$CONF_FILE" ]]; then
    if [[ "$UNATTENDED" == "yes" || ! -t 0 ]]; then
        REUSE="y"      # no terminal to ask: keep what is already configured
    else
        read -r -p "Existing config found. Keep it? (Y/n): " REUSE_ANS
        REUSE_ANS="${REUSE_ANS:-y}"
        [[ "${REUSE_ANS,,}" == "y" ]] && REUSE="y"
    fi
elif [[ "$UNATTENDED" == "yes" ]]; then
    die "--unattended needs an existing config at $CONF_FILE."
fi

if [[ "$REUSE" == "y" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$CONF_FILE"; set +a
    c_ok "✅ Reusing existing configuration."
else
    read -r -s -p "Telegram Bot Token: " BOT_TOKEN; echo ""
    read -r -p  "Admin Chat ID (numeric): " ADMIN_CHAT_ID

    [[ -n "$BOT_TOKEN" ]] || die "Token cannot be empty."
    [[ "$BOT_TOKEN" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]] \
        || die "Token format looks wrong (expected 123456789:AA...)."
    [[ "$ADMIN_CHAT_ID" =~ ^[0-9]+$ ]] || die "Admin Chat ID must be numeric."

    read -r -p "Use a proxy? (y/N): " USE_PROXY
    if [[ "${USE_PROXY,,}" == "y" ]]; then
        read -r -p "Proxy type (http/socks5) [socks5]: " PROXY_TYPE
        PROXY_TYPE="${PROXY_TYPE:-socks5}"
        [[ "$PROXY_TYPE" =~ ^(http|https|socks5|socks5h)$ ]] \
            || die "Unsupported proxy type."
        read -r -p "Proxy host/IP: " PROXY_HOST
        read -r -p "Proxy port: " PROXY_PORT
        [[ "$PROXY_PORT" =~ ^[0-9]{1,5}$ ]] || die "Invalid port."
        read -r -p "Proxy username (blank if none): " PROXY_USER
        PROXY_PASS=""
        if [[ -n "$PROXY_USER" ]]; then
            read -r -s -p "Proxy password: " PROXY_PASS; echo ""
        fi

        # Percent-encode credentials so special characters cannot break the URL.
        urlenc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
        if [[ -n "$PROXY_USER" ]]; then
            PROXY_URL="${PROXY_TYPE}://$(urlenc "$PROXY_USER"):$(urlenc "$PROXY_PASS")@${PROXY_HOST}:${PROXY_PORT}"
        else
            PROXY_URL="${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}"
        fi
        # Never print the password back to the terminal.
        c_ok "✅ Proxy set: ${PROXY_TYPE}://${PROXY_HOST}:${PROXY_PORT}"
    else
        c_warn "ℹ️  No proxy — connecting directly."
    fi
fi
echo ""

# --------------------------------------------------------------------------
# 2. System packages
# --------------------------------------------------------------------------
echo "[1/7] Installing system packages…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-dev ca-certificates curl \
    fonts-dejavu-core >/dev/null

# --------------------------------------------------------------------------
# 3. Dedicated unprivileged user + directories
# --------------------------------------------------------------------------
echo "[2/7] Creating service account and directories…"
if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi
install -d -m 0755 "$APP_DIR"
install -d -m 0750 -o root -g "$APP_USER" "$CONF_DIR"
install -d -m 0700 -o "$APP_USER" -g "$APP_USER" "$DATA_DIR"

# --------------------------------------------------------------------------
# 4. Application files
# --------------------------------------------------------------------------
echo "[3/7] Writing application files…"

@@SCRAPER@@

@@BOT@@

@@IMAGE@@

cat > "$APP_DIR/requirements.txt" <<'REQ_EOF'
python-telegram-bot[job-queue,rate-limiter,socks]>=21.0,<23.0
requests[socks]>=2.31
beautifulsoup4>=4.12
cloudscraper>=1.2.71
Pillow>=10.0
REQ_EOF

install -d -m 0755 "$APP_DIR/art" "$APP_DIR/art/rewards" "$APP_DIR/art/weekly" "$APP_DIR/art/zones"
chmod 0644 "$APP_DIR"/*.py "$APP_DIR/requirements.txt"
chown -R root:root "$APP_DIR"

# --------------------------------------------------------------------------
# 5. Virtualenv (keeps the system Python untouched)
# --------------------------------------------------------------------------
echo "[4/7] Building virtualenv and installing dependencies…"
[[ -x "$APP_DIR/venv/bin/python" ]] || python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --quiet --upgrade pip wheel
"$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"

# --------------------------------------------------------------------------
# 6. Secrets file (0640, root:fnbot — never world readable)
# --------------------------------------------------------------------------
echo "[5/7] Writing configuration…"
if [[ "$REUSE" != "y" ]]; then
    umask 077
    cat > "$CONF_FILE" <<ENV_EOF
# Fortnite STW bot configuration — KEEP PRIVATE (mode 0640)
BOT_TOKEN="${BOT_TOKEN}"
ADMIN_CHAT_ID="${ADMIN_CHAT_ID}"
PROXY_URL="${PROXY_URL}"
DATA_DIR="${DATA_DIR}"

# --- tuning -------------------------------------------------------------
MAX_USERS="200"
# Missions are cached until the next 00:00 UTC reset, so repeat button
# presses are instant. These two only affect the window right after a
# reset, while the upstream site is still publishing the new data.
CACHE_SETTLE_MINUTES="20"
CACHE_SETTLE_TTL="300"
REQUEST_TIMEOUT="15"
BROADCAST_DELAY="0.06"
LOG_LEVEL="INFO"
DEFAULT_LANG="en"
# Missions per picture in image mode (about MIN+1 each, spread evenly, never
# fewer than MIN unless the whole list is shorter); longer lists go as an album.
IMAGE_MIN_CARDS="5"
IMAGE_MAX_CARDS="10"
# Drop your own square PNGs in ART_DIR to replace the drawn icons. Several
# names are tried per slot (first hit wins), e.g. bomb|deliver|dtb:
#   page     : background   (full-page backdrop for every picture)
#   missions (root or scenes/): evacuate repair|repair_shelter lightning|van
#              balloon (= Retrieve the Data) radar storm|atlas atlas_1..atlas_4 (Category 1-4)
#              survive trap_storm resupply rocket
#              bomb encampments eliminate rescue refuel|refuel_homebase
#              titan|hunt_the_titan   (missing/empty file = drawn icon)
#   rewards/ : vbucks reperk perkup (+ uncommon_/rare_/epic_/legendary_perkup)
#              flux (+ rare_/epic_/legendary_flux) ampup fireup frostup perk
#              lightning_bottle eye_storm storm_shard pure_drop flux manual
#              designs|weapon_designs trap_designs material venture_xp survivor_xp schematic_xp|schematic hero_xp xp
#              candy gold ticket lead survivor defender hero trap schematic
#   weekly/  : weapon|schematic hero survivor trap defender core|perk
#   zones/ (or zone/): stonewood plankerton canny_valley twine_peaks ventures
#              (or the Ventures zone name itself, e.g. hexsylvania)
# Names are matched loosely: "V-Bucks.png" = "v_bucks.png" = "vbucks.png".
# Re-download after changing art.zip:  fnbot art   (fnbot art --force)
ART_DIR="/opt/fortnite_bot/art"
# Art pack (.zip of PNGs) downloaded into ART_DIR on install/update.
# Files you replaced yourself are never overwritten. "" = disabled.
ART_URL="${ART_URL_DEFAULT}"

# 🔥 Top Missions: best N missions of every zone, ranked by value
# (V-Bucks > X-Ray > Mythic > Legendary lead/hero/defender > Legendary
# survivor/schematic > Legendary Perk-Up/Flux > RE-PERK > evo mats).
TOP_PER_ZONE="5"

# Second weekly-reward source (optional). When the two disagree the admin is
# asked to confirm; /setweekly pins the right one by hand.
WEEKLY_URL2=""

# --- schedule (UTC) -----------------------------------------------------
# Daily alert: 1 minute after the 00:00 UTC shop/mission reset.
DAILY_RESET_UTC="00:01"
# Weekly alert: 2 minutes after the reset.
WEEKLY_RESET_UTC="00:02"
# 0=Mon 1=Tue 2=Wed 3=Thu 4=Fri 5=Sat 6=Sun
WEEKLY_RESET_WEEKDAY="3"

# --- season dates (update once per season) ------------------------------
SEASON_START_UTC="2026-08-20T07:30:00+00:00"
SEASON_END_UTC="2026-11-01T07:30:00+00:00"
ENV_EOF
    umask 022
fi
# Keys added by newer releases, so an upgraded install gets them too.
ensure_conf() {
    grep -q "^$1=" "$CONF_FILE" 2>/dev/null || printf '%s="%s"\n' "$1" "$2" >> "$CONF_FILE"
}
ensure_conf UPDATE_URL "$UPDATE_URL"
ensure_conf IMAGE_MAX_CARDS "10"
ensure_conf IMAGE_MIN_CARDS "5"
ensure_conf WEEKLY_URL2 ""
ensure_conf TOP_PER_ZONE "5"
ensure_conf ART_DIR "$APP_DIR/art"
ensure_conf ART_URL "$ART_URL_DEFAULT"
# BOT_VERSION always reflects the installer that ran last.
if grep -q '^BOT_VERSION=' "$CONF_FILE" 2>/dev/null; then
    sed -i "s|^BOT_VERSION=.*|BOT_VERSION=\"$BOT_VERSION\"|" "$CONF_FILE"
else
    printf 'BOT_VERSION="%s"\n' "$BOT_VERSION" >> "$CONF_FILE"
fi

chown root:"$APP_USER" "$CONF_FILE"
chmod 0640 "$CONF_FILE"

# Compact list layout fits more missions per picture.
if grep -qE '^IMAGE_MAX_CARDS="(12|20)"' "$CONF_FILE" 2>/dev/null; then
    sed -i 's|^IMAGE_MAX_CARDS=.*|IMAGE_MAX_CARDS="10"|' "$CONF_FILE"
fi

# Retire the old fixed-TTL cache setting (superseded by reset-boundary caching).
if grep -q '^CACHE_TTL=' "$CONF_FILE" 2>/dev/null; then
    sed -i 's|^CACHE_TTL=.*|CACHE_SETTLE_TTL="300"|' "$CONF_FILE"
fi

# Move the old built-in schedule to the new one (custom values are kept).
if grep -q '^DAILY_RESET_UTC="00:05"' "$CONF_FILE" 2>/dev/null; then
    sed -i 's|^DAILY_RESET_UTC=.*|DAILY_RESET_UTC="00:01"|' "$CONF_FILE"
    c_ok "✅ Daily alert moved to 00:01 UTC."
fi
if grep -q '^WEEKLY_RESET_UTC="00:10"' "$CONF_FILE" 2>/dev/null; then
    sed -i 's|^WEEKLY_RESET_UTC=.*|WEEKLY_RESET_UTC="00:02"|' "$CONF_FILE"
    c_ok "✅ Weekly alert moved to 00:02 UTC."
fi

# Migrate the old users file, if any.
if [[ -f "$LEGACY_DIR/users.json" && ! -f "$DATA_DIR/users.json" ]]; then
    cp "$LEGACY_DIR/users.json" "$DATA_DIR/users.json"
    chown "$APP_USER":"$APP_USER" "$DATA_DIR/users.json"
    chmod 0600 "$DATA_DIR/users.json"
    c_ok "✅ Migrated users.json from $LEGACY_DIR"
fi

# --------------------------------------------------------------------------
# 7. Systemd unit (sandboxed)
# --------------------------------------------------------------------------
echo "[6/7] Installing systemd service…"
cat > "$UNIT" <<UNIT_EOF
[Unit]
Description=Fortnite STW Telegram Bot
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${CONF_FILE}
ExecStart=${APP_DIR}/venv/bin/python ${APP_DIR}/vbucks_bot.py
Restart=always
RestartSec=10
UMask=0077

# --- sandboxing ---
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectProc=invisible
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
ReadWritePaths=${DATA_DIR}

[Install]
WantedBy=multi-user.target
UNIT_EOF
chmod 0644 "$UNIT"

# Privileged updater. Triggered by a path unit when the bot drops a request
# file. The URL comes from the root-owned config, never from the request, so
# the unprivileged bot cannot make this run an arbitrary script.
cat > /usr/local/bin/fnbot-update <<'UPD_EOF'
#!/usr/bin/env bash
set -uo pipefail
CONF="/etc/fortnite_bot/bot.env"
DATA="/var/lib/fortnite_bot"
SERVICE="fortnite-bot"
REQUEST="$DATA/update.request"
RESULT="$DATA/update.result"
LOG="$DATA/update.log"

rm -f "$REQUEST"
# shellcheck disable=SC1090
set -a; . "$CONF"; set +a
OLD="${BOT_VERSION:-unknown}"

finish() {   # $1=status  $2=error
    printf '{"status":"%s","old":"%s","error":"%s"}' "$1" "$OLD" "${2//\"/}" > "$RESULT"
    chown fnbot:fnbot "$RESULT" 2>/dev/null || true
    chmod 0640 "$RESULT"
    systemctl restart "$SERVICE" || true
    [[ "$1" == "ok" ]] && exit 0 || exit 1
}

if [[ -z "${UPDATE_URL:-}" ]]; then finish fail "UPDATE_URL is not set"; fi

TMP="$(mktemp /tmp/fnbot-installer.XXXXXX.sh)"
trap 'rm -f "$TMP"' EXIT
P=(); if [[ -n "${PROXY_URL:-}" ]]; then P=(--proxy "$PROXY_URL"); fi

{ echo "=== $(date -Is) update from $OLD ==="; } >> "$LOG"
if ! curl -fsSL --max-time 90 "${P[@]}" "$UPDATE_URL" -o "$TMP" 2>>"$LOG"; then
    finish fail "download failed"
fi
if ! head -c 2 "$TMP" | grep -q '#!'; then
    finish fail "the downloaded file is not a script"
fi
if ! bash "$TMP" --unattended >>"$LOG" 2>&1; then
    finish fail "the installer exited with an error, see $LOG"
fi
finish ok ""
UPD_EOF
chmod 0755 /usr/local/bin/fnbot-update

cat > "$UPD_UNIT" <<UPDUNIT_EOF
[Unit]
Description=Update the Fortnite STW Telegram bot

[Service]
Type=oneshot
Environment=TERM=dumb
Environment=DEBIAN_FRONTEND=noninteractive
ExecStart=/usr/local/bin/fnbot-update
TimeoutStartSec=900
UPDUNIT_EOF

cat > "$UPD_PATH" <<UPDPATH_EOF
[Unit]
Description=Watch for a Fortnite bot update request

[Path]
PathExists=${DATA_DIR}/update.request
Unit=${SERVICE}-update.service

[Install]
WantedBy=multi-user.target
UPDPATH_EOF
chmod 0644 "$UPD_UNIT" "$UPD_PATH"

# Management helper
cat > /usr/local/bin/fnbot <<'CLI_EOF'
#!/usr/bin/env bash
set -euo pipefail
SERVICE="fortnite-bot"
case "${1:-help}" in
  start)   systemctl start  "$SERVICE" ;;
  stop)    systemctl stop   "$SERVICE" ;;
  restart) systemctl restart "$SERVICE" ;;
  status)  systemctl status "$SERVICE" --no-pager ;;
  logs)    journalctl -u "$SERVICE" -f -n 100 ;;
  config)  ${EDITOR:-nano} /etc/fortnite_bot/bot.env && systemctl restart "$SERVICE" ;;
  update)  /usr/local/bin/fnbot-update ;;
  art)     /usr/local/bin/fnbot-art "${2:-}" && systemctl restart "$SERVICE" ;;
  version) grep '^BOT_VERSION=' /etc/fortnite_bot/bot.env | cut -d'"' -f2 ;;
  errors)  journalctl -u "$SERVICE" -n 200 --no-pager \
             | grep -iE "error|exception|refused|timed out|unauthor|fatal" | tail -n 30 ;;
  test)
      set -a; . /etc/fortnite_bot/bot.env; set +a
      P=(); if [[ -n "${PROXY_URL:-}" ]]; then P=(--proxy "$PROXY_URL"); fi
      echo "--- direct ---"
      printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$BOT_TOKEN" \
        | curl -sS -K - --max-time 15 \
        | sed -e 's/[0-9]\{6,\}:[A-Za-z0-9_-]\{20,\}/***TOKEN***/g' || true
      echo ""
      [[ ${#P[@]} -eq 0 ]] && { echo "(no proxy configured)"; exit 0; }
      echo "--- via proxy ---"
      printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$BOT_TOKEN" \
        | curl -sS -K - --max-time 20 "${P[@]}" \
        | sed -e 's/[0-9]\{6,\}:[A-Za-z0-9_-]\{20,\}/***TOKEN***/g'
      echo ""
      ;;
  uninstall)
      systemctl disable --now "$SERVICE" || true
      systemctl disable --now "${SERVICE}-update.path" 2>/dev/null || true
      rm -f "/etc/systemd/system/${SERVICE}.service" \
            "/etc/systemd/system/${SERVICE}-update.service" \
            "/etc/systemd/system/${SERVICE}-update.path" \
            /usr/local/bin/fnbot /usr/local/bin/fnbot-update /usr/local/bin/fnbot-art
      systemctl daemon-reload
      echo "Service removed. Data kept in /var/lib/fortnite_bot, config in /etc/fortnite_bot."
      ;;
  *) echo "usage: fnbot {start|stop|restart|status|logs|errors|test|update|art [--force]|version|config|uninstall}" ;;
esac
CLI_EOF
chmod 0755 /usr/local/bin/fnbot

# --------------------------------------------------------------------------
# 8. Start
# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
# Connectivity pre-flight: try direct AND via proxy, then advise.
# --------------------------------------------------------------------------
echo "Checking Telegram API reachability…"

tg_check() {
    # The token goes in on stdin, never argv, so it never shows up in `ps`.
    local out rc=0
    out="$(mktemp)"
    printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$BOT_TOKEN" \
        | curl -sS -K - --max-time 15 "$@" -o "$out" 2>/dev/null || rc=1
    if [[ $rc -eq 0 ]] && grep -q '"ok":true' "$out"; then
        rm -f "$out"; return 0
    fi
    if [[ $rc -eq 0 ]] && grep -q '"ok":false' "$out"; then
        c_err "   Telegram answered but rejected the token:"
        sed -e 's/[0-9]\{6,\}:[A-Za-z0-9_-]\{20,\}/***TOKEN***/g' "$out"
        rm -f "$out"; return 2
    fi
    rm -f "$out"; return 1
}

DIRECT_OK="n"
PROXY_OK="n"
if tg_check; then DIRECT_OK="y"; fi
if [[ -n "${PROXY_URL:-}" ]]; then
    if tg_check --proxy "$PROXY_URL"; then PROXY_OK="y"; fi
fi

if [[ -n "${PROXY_URL:-}" && "$PROXY_OK" == "y" ]]; then
    c_ok "✅ Telegram reachable through the proxy."
elif [[ -n "${PROXY_URL:-}" && "$DIRECT_OK" == "y" ]]; then
    c_warn "⚠️  The proxy is NOT reachable, but a DIRECT connection works."
    c_warn "    Nothing is listening on your proxy address, or the port is wrong."
    if [[ -t 0 ]]; then
        read -r -p "    Disable the proxy and connect directly? (Y/n): " DROP
        if [[ "${DROP:-y}" =~ ^[Yy]?$ ]]; then
            sed -i 's|^PROXY_URL=.*|PROXY_URL=""|' "$CONF_FILE"
            PROXY_URL=""
            c_ok "✅ Proxy disabled — using a direct connection."
        fi
    else
        c_warn "    Run 'fnbot config' and set PROXY_URL=\"\" to go direct."
    fi
elif [[ -n "${PROXY_URL:-}" ]]; then
    c_err "❌ Neither the proxy nor a direct connection reached api.telegram.org."
    c_err "   Check that the proxy is running:  ss -ltnp | grep <port>"
elif [[ "$DIRECT_OK" == "y" ]]; then
    c_ok "✅ Telegram reachable and token accepted."
else
    c_warn "⚠️  Could not reach api.telegram.org directly."
    c_warn "    The bot will keep retrying; a proxy may be required here."
fi
echo ""

# Remember the checksum of the published installer, so the bot can tell later
# whether the code on GitHub changed even if the version number did not.
SHA_TMP="$(mktemp)"
SHA_PROXY=()
if [[ -n "${PROXY_URL:-}" ]]; then SHA_PROXY=(--proxy "$PROXY_URL"); fi
if curl -fsSL --max-time 30 "${SHA_PROXY[@]}" "$UPDATE_URL" -o "$SHA_TMP" 2>/dev/null \
   && head -c 2 "$SHA_TMP" | grep -q '#!'; then
    sha256sum "$SHA_TMP" | awk '{print $1}' > "$SHA_FILE"
    chown root:"$APP_USER" "$SHA_FILE"; chmod 0640 "$SHA_FILE"
    c_ok "✅ Recorded the published installer checksum."
else
    c_warn "ℹ️  Could not fetch the published installer; update checks compare versions only."
fi
rm -f "$SHA_TMP"

# --------------------------------------------------------------------------
# Art pack: download ART_URL and unpack the PNGs into ART_DIR.
# Never fatal. Re-extracts only when the zip changes, and never overwrites
# a PNG the admin replaced by hand (tracked in .art_manifest).
# --------------------------------------------------------------------------
cat > /usr/local/bin/fnbot-art <<'ART_SH_EOF'
#!/usr/bin/env bash
# Download ART_URL (a .zip of PNGs) and unpack it into ART_DIR.
# Layout: <name>.png at the root, rewards/, weekly/, zones/ sub-folders
# (an extra top folder such as art/ is stripped). Never fatal. Re-extracts
# only when the zip changed; PNGs replaced by hand are kept (.art_manifest).
set -uo pipefail
CONF_FILE="/etc/fortnite_bot/bot.env"
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
conf_get() { grep -m1 "^$1=" "$CONF_FILE" 2>/dev/null | cut -d'"' -f2; }
[[ "${1:-}" == "--force" ]] && FORCE=1 || FORCE=0
url="$(conf_get ART_URL)"
dir="$(conf_get ART_DIR)"; dir="${dir:-/opt/fortnite_bot/art}"
proxy_url="$(conf_get PROXY_URL)"
if [[ -z "$url" ]]; then warn "ℹ️  ART_URL is empty — skipping the art pack."; exit 0; fi
[[ "$url" =~ ^https?:// ]] || { warn "⚠️  ART_URL is not an http(s) URL — skipped."; exit 0; }
install -d -m 0755 "$dir" "$dir/rewards" "$dir/weekly" "$dir/zones" "$dir/scenes"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
proxy=(); [[ -n "$proxy_url" ]] && proxy=(--proxy "$proxy_url")
code="$(curl -sSL --max-time 180 --retry 2 "${proxy[@]}" -w '%{http_code}' -o "$tmp" "$url" 2>/dev/null || true)"
if [[ "$code" != "200" ]]; then
    warn "⚠️  Could not download the art pack (HTTP ${code:-error}): $url"
    warn "    Upload art.zip to the latest GitHub release, or fix ART_URL (fnbot config)."
    exit 0
fi
python3 - "$tmp" "$dir" "$FORCE" > "$tmp.out" 2>&1 <<'ART_PY_EOF'
import hashlib, json, os, re, sys, zipfile
zpath, root = sys.argv[1], os.path.realpath(sys.argv[2])
force = len(sys.argv) > 3 and sys.argv[3] == "1"
MAX_FILE, MAX_TOTAL = 8 << 20, 150 << 20
SUBDIRS = ("rewards", "weekly", "zones", "zone", "scenes", "missions")
man_path = os.path.join(root, ".art_manifest")
def sha(b): return hashlib.sha256(b).hexdigest()
# Checksums of the first published pack: those files count as ours even on
# servers whose manifest no longer lists them.
LEGACY = {
    "rewards/defender.png": "f0a68b508535c9285fa46072c401a25442a9c688c7b5465267a0ce87c8036b37",
    "rewards/gold.png": "37fcc4bb1d77b3bcb1a35245200ba268931d3be8fde087b7f4626f3194ea6cd0",
    "rewards/hero.png": "0e98129eef47a9f401469d289d1de5c9bcf8530e27d4867d9dcd98d80ce1cbcf",
    "rewards/material.png": "bafdc84b119e9ce49a2ef744d6a39f58324b066a3ba24b50498bd4a83f691275",
    "rewards/perk.png": "daed22ea36d0bad09291f556561db86ddd49b2f2673f97fd71940da47453f463",
    "rewards/schematic.png": "6ffc7f6efb0f90211581c0f4833c2b1372177291c19045d7fa7380fc70074e58",
    "rewards/survivor.png": "0007cba1a1909b1cbc080615f5bc4d4d9e33889852b8aef056b28b07db2e75cc",
    "rewards/trap.png": "7c9ecbd7449425c72d40cb193eb6282da17752aae991fef3f80812ad264d1e6e",
    "rewards/vbucks.png": "44e3c3b36235c731b199f469c8c610c197087af410e044bd0a4e0dde794d358a",
    "rewards/xp.png": "f5cef127ff6218234bd1e3288941183923db4564f97078bdcf6cccc300eaf4f2",
    "weekly/core.png": "0c642e943ea53cbfc9ac6b42084491e7044cfdfdfd514248d35bf19226a0ca24",
    "weekly/hero.png": "3f997aaea24f08d6766c8787f40d1105f735e1382659bcfc67a72854c9c6d55b",
    "weekly/survivor.png": "c4fe9a1bd0ff73397dedb5002f1427e6626fa6dec81130fea340006f1ffa7d8d",
    "weekly/trap.png": "b8d169aeea65bfa6cbc5dde0c6aa69edc861e794988c52c9e13325846dd2f30c",
    "weekly/weapon.png": "27eb2b8df07ec7b2c9660bf5d9da4db51955300757c8e2828e352415c7e021e5",
    "zones/canny.png": "6b174c7e0dd0a5bbe2877c62d16f4057bb51375355bbd0aeb12c6407529eb0ed",
    "zones/plankerton.png": "27f949f4508162808d5b76b2416275f4dfe7ce8782502403be9208c2ec67edc3",
    "zones/stonewood.png": "7454bfd34634eafd764689ca594c9cf6d45c75ae549a9525051f2e6915f2076f",
    "zones/twine.png": "152690a24dc35f997b77be493ee72900a050dac96b236dd82ef4b3cb0f0fd56a",
    "zones/ventures.png": "1407a3fde4735225dae9ce2aba442e703fb287ffad6dbf1045ce2f4c138ced68",
    "bomb.png": "1b7af3daf228db0aef1556078dd3dac534b33a5175e8ac75f60f91eec94cf9d2",
    "data.png": "f318ecde22ac0cc5324ae07aec5c461e4c6508f34af10d99f31835936dad24c8",
    "eliminate.png": "2353c89b595bc45fe0e42517e96dafed23402383fdef2fa4579dc70b6820fc7a",
    "encampments.png": "477701c7fadf9372eba45788d8cffe0551618c75d11a461ee53fbdc3d6acf873",
    "evacuate.png": "11bce19f9692ebd3e27e6d2c842b7c6b4e80a8fcd274ba2f47b66f9bb3896a6f",
    "lightning.png": "8ad9168b866d071a3b29cc1a0a4242453d6be5d2d92ab9c6fb85de9c195cff8f",
    "radar.png": "e2205ac6dd04b9a99137f5a6350b14a10248034e4553555758203672d88bd34b",
    "repair.png": "e46a66cb87dc8a98f281fc8d6ad6edd45843f36edb2f94d52fe7d036f5c40f25",
    "rescue.png": "1f33f45ea939bea2cac802fc29379cdb06e0d85df3865ea4b259a9fd659d8d94",
    "storm.png": "e1092644fdeebff7ceb020c9afa07c5e0e850dd51bf8506074bb9681e1e06065",
}
try:
    with open(man_path) as f: man = json.load(f)
except Exception:
    man = {}
with open(zpath, "rb") as f: zsum = sha(f.read())
if man.get("_zip") == zsum and not force:
    print("ART:SAME"); sys.exit(0)
try:
    z = zipfile.ZipFile(zpath)
except zipfile.BadZipFile:
    print("ART:BADZIP"); sys.exit(3)
infos = [i for i in z.infolist() if not i.is_dir()
         and i.filename.lower().endswith(".png")
         and "__MACOSX" not in i.filename]
names = [i.filename.replace("\\", "/") for i in infos]
# Strip one common top folder (art.zip may contain art/...).
tops = {n.split("/", 1)[0] for n in names}
strip = len(tops) == 1 and all("/" in n for n in names) and tops.pop().lower() not in SUBDIRS
new_man, added, kept, total, skipped = {"_zip": zsum}, 0, 0, 0, 0
seen = set()
for info, name in zip(infos, names):
    rel = name.split("/", 1)[1] if strip else name
    parts = rel.split("/")
    if (len(parts) > 2 or any(p in ("", ".", "..") for p in parts)
            or (len(parts) == 2 and parts[0].lower() not in SUBDIRS)):
        skipped += 1; continue
    rel = "/".join(re.sub(r"[\s\-]+", "_", p.strip().lower()) for p in parts)
    if info.file_size > MAX_FILE or total + info.file_size > MAX_TOTAL:
        skipped += 1; continue
    data = z.read(info)
    if not (data.startswith(b"\x89PNG\r\n\x1a\n") or data[:3] == b"\xff\xd8\xff"
            or (data[:4] == b"RIFF" and data[8:12] == b"WEBP")):   # PNG/JPEG/WebP
        skipped += 1; continue
    total += len(data)
    dest = os.path.realpath(os.path.join(root, rel))
    if not dest.startswith(root + os.sep):
        skipped += 1; continue
    new_sum = sha(data)
    seen.add(rel)
    if os.path.exists(dest):
        with open(dest, "rb") as f: cur = sha(f.read())
        if cur not in (man.get(rel), LEGACY.get(rel), new_sum):
            kept += 1; continue          # admin's own file — leave it
    os.makedirs(os.path.dirname(dest), mode=0o755, exist_ok=True)
    tmp = dest + ".tmp"
    with open(tmp, "wb") as f: f.write(data)
    os.chmod(tmp, 0o644); os.replace(tmp, dest)
    new_man[rel] = new_sum; added += 1
# Remove images an older zip installed that this zip no longer has (they
# would shadow the new names, e.g. an old lightning.png over scenes/van.png).
# Files the admin changed since are kept.
removed = 0
for rel, old_sum in list(LEGACY.items()) + list(man.items()):
    if rel == "_zip" or rel in seen:
        continue
    dest = os.path.realpath(os.path.join(root, rel))
    if not dest.startswith(root + os.sep) or not os.path.isfile(dest):
        continue
    with open(dest, "rb") as f: cur = sha(f.read())
    if cur == old_sum:
        os.remove(dest); removed += 1
with open(man_path + ".tmp", "w") as f: json.dump(new_man, f, indent=0)
os.chmod(man_path + ".tmp", 0o644); os.replace(man_path + ".tmp", man_path)
print(f"ART:OK {added} {kept} {skipped} {removed}")
ART_PY_EOF
out="$(cat "$tmp.out" 2>/dev/null)"; rm -f "$tmp.out"
chown -R root:root "$dir" 2>/dev/null || true
case "$out" in
    ART:SAME*)   ok "✅ Art pack already up to date." ;;
    ART:OK*)     read -r _ n k skipped removed <<< "$out"
                 ok "✅ Art pack installed: ${n} image(s) into $dir"
                 [[ "${k:-0}" != "0" ]] && warn "ℹ️  Kept ${k} image(s) you replaced yourself."
                 [[ "${skipped:-0}" != "0" ]] && warn "ℹ️  Skipped ${skipped} file(s) (not PNG / bad path / too big)."
                 [[ "${removed:-0}" != "0" ]] && ok "🧹 Removed ${removed} old image(s) no longer in the art pack."
                 ;;
    ART:BADZIP*) warn "⚠️  ART_URL did not return a valid .zip — art pack skipped." ;;
    *)           warn "⚠️  Art pack could not be unpacked — using drawn icons."; echo "$out" | tail -n 3 ;;
esac
exit 0
ART_SH_EOF
chmod 0755 /usr/local/bin/fnbot-art

echo "Fetching art pack…"
/usr/local/bin/fnbot-art || true

echo "[7/7] Starting service…"

# Disable the old unit if this box ran the previous version.
if systemctl list-unit-files | grep -q '^vbucksbot\.service'; then
    systemctl disable --now vbucksbot.service >/dev/null 2>&1 || true
    c_warn "ℹ️  Old vbucksbot.service disabled."
fi

systemctl daemon-reload
systemctl enable --now "${SERVICE}-update.path" >/dev/null 2>&1 || true
systemctl enable --now "$SERVICE" >/dev/null 2>&1 || true
systemctl restart "$SERVICE"
sleep 3

echo ""
if systemctl is-active --quiet "$SERVICE"; then
    echo "===================================================="
    c_ok " ✅ Bot installed and running."
    echo "===================================================="
    echo " Version: $BOT_VERSION"
    echo " Manage : fnbot {status|logs|restart|update|config}"
    echo " Config : $CONF_FILE  (0640 root:$APP_USER)"
    echo " Data   : $DATA_DIR"
else
    c_err "The service did not start. Relevant log lines:"
    journalctl -u "$SERVICE" -n 80 --no-pager 2>/dev/null \
        | grep -iE "error|exception|refused|timed out|unauthor|proxy|fatal" \
        | tail -n 20 || true
    echo ""
    c_warn "Full log:  journalctl -u $SERVICE -n 80 --no-pager"
    c_warn "Self test: fnbot test"
    exit 1
fi

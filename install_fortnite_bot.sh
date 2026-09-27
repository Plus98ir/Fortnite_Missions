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

cat > "$APP_DIR/vbucks_scraper.py" <<'SCRAPER_PY_EOF'
#!/usr/bin/env python3
"""Data sources for the Fortnite STW Telegram bot.

Design notes
------------
* Every function here is BLOCKING. The bot layer calls them through
  ``asyncio.to_thread`` so the event loop is never stalled.
* Functions return *structured data* (dicts / lists), not pre-formatted
  text. All localisation and HTML escaping happens in the bot layer.
* Every outbound request has an explicit timeout + bounded retries.
* Results are cached with a TTL; if a refresh fails the last good value
  is served instead of an error (``stale-while-error``).
"""

from __future__ import annotations

import json
import logging
import os
import re
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable

import requests
from bs4 import BeautifulSoup
from requests.adapters import HTTPAdapter

try:  # urllib3 v1 / v2
    from urllib3.util.retry import Retry
except ImportError:  # pragma: no cover
    from requests.packages.urllib3.util.retry import Retry  # type: ignore

try:
    import cloudscraper
except Exception:  # pragma: no cover - optional dependency
    cloudscraper = None

log = logging.getLogger(__name__)

# --------------------------------------------------------------------------
# Configuration (all overridable from the systemd EnvironmentFile)
# --------------------------------------------------------------------------
MISSIONS_URL = os.environ.get("MISSIONS_URL", "https://seebot.dev/missions.php")
WEEKLY_URL = os.environ.get("WEEKLY_URL", "https://fortnitedb.com/")
# Optional second weekly source (any page that names the weekly Supercharger).
# When both answer and disagree, the admin is asked to confirm.
WEEKLY_URL2 = os.environ.get("WEEKLY_URL2", "").strip()
SEASON_URL = os.environ.get("SEASON_URL", "https://fortnite.gg/season-countdown")

REQUEST_TIMEOUT = float(os.environ.get("REQUEST_TIMEOUT", "15"))
# Missions change only at the 00:00 UTC reset, so the cache is valid until
# the next reset rather than for a fixed number of minutes. Right after a
# reset the upstream site needs a moment to publish the new data, so during
# a short "settling" window the cache is refreshed more eagerly.
CACHE_SETTLE_MINUTES = int(os.environ.get("CACHE_SETTLE_MINUTES", "20"))
CACHE_SETTLE_TTL = int(os.environ.get("CACHE_SETTLE_TTL", "300"))
WEEKLY_RESET_WEEKDAY = int(os.environ.get("WEEKLY_RESET_WEEKDAY", "3"))
# The cache is mirrored to disk so a restart does not force a re-fetch.
CACHE_DIR = Path(os.environ.get("CACHE_DIR")
                 or os.environ.get("DATA_DIR", "/var/lib/fortnite_bot"))
# Upper bound on what a *display* shows. Fetchers never truncate: filters
# run on the complete list first, otherwise zones sorted late (Twine Peaks,
# Ventures) silently fell off the end before the user's filters saw them.
MAX_ITEMS = int(os.environ.get("MAX_ITEMS", "60"))
# FortniteDB updates the weekly block some time after the Thursday reset,
# so for this many hours the weekly value is re-checked every
# WEEKLY_SETTLE_TTL seconds, and an unchanged reward is not trusted yet.
WEEKLY_SETTLE_HOURS = float(os.environ.get("WEEKLY_SETTLE_HOURS", "8"))
WEEKLY_SETTLE_TTL = int(os.environ.get("WEEKLY_SETTLE_TTL", "900"))

USER_AGENT = os.environ.get(
    "USER_AGENT",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
)

_CRED_RE = re.compile(r"(?P<scheme>[a-z0-9+.-]+://)(?P<user>[^:/@\s]+):(?P<pw>[^@\s]*)@")


def redact_url(url: str | None) -> str:
    """Hide the password part of a proxy URL so it never reaches the logs."""
    if not url:
        return ""
    return _CRED_RE.sub(lambda m: f"{m.group('scheme')}{m.group('user')}:***@", url)


def _scrape_proxy(url: str) -> str:
    """Force remote DNS resolution for SOCKS5 (avoids DNS leaks / blocks)."""
    if url.startswith("socks5://"):
        return "socks5h://" + url[len("socks5://"):]
    return url


_RAW_PROXY = os.environ.get("PROXY_URL", "").strip()
PROXY_URL = _scrape_proxy(_RAW_PROXY) if _RAW_PROXY else ""
PROXIES: dict[str, str] | None = (
    {"http": PROXY_URL, "https": PROXY_URL} if PROXY_URL else None
)


# --------------------------------------------------------------------------
# HTTP session with retry/backoff
# --------------------------------------------------------------------------
def _build_session() -> requests.Session:
    session = requests.Session()
    retry = Retry(
        total=3,
        connect=3,
        read=3,
        backoff_factor=0.8,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=frozenset({"GET", "HEAD"}),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry, pool_maxsize=8)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    session.headers.update({
        "User-Agent": USER_AGENT,
        "Accept": "application/json, text/html;q=0.9, */*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
    })
    if PROXIES:
        session.proxies.update(PROXIES)
    return session


_SESSION = _build_session()


# --------------------------------------------------------------------------
# Reset-boundary cache (valid until the next in-game reset)
# --------------------------------------------------------------------------
def daily_anchor(now: datetime) -> datetime:
    """Start of the current game day (00:00 UTC)."""
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def weekly_anchor(now: datetime) -> datetime:
    """Start of the current game week (the most recent weekly reset)."""
    midnight = daily_anchor(now)
    offset = (midnight.weekday() - WEEKLY_RESET_WEEKDAY) % 7
    return midnight - timedelta(days=offset)


def _disk_path(name: str) -> Path:
    return CACHE_DIR / f"cache-{name}.json"


def _disk_load(name: str) -> tuple[datetime, Any] | None:
    try:
        raw = json.loads(_disk_path(name).read_text("utf-8"))
        return datetime.fromisoformat(raw["fetched"]), raw["value"]
    except FileNotFoundError:
        return None
    except Exception:
        log.debug("unreadable disk cache for %s", name, exc_info=True)
        return None


def _disk_save(name: str, fetched: datetime, value: Any) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        target = _disk_path(name)
        tmp = target.with_suffix(".tmp")
        tmp.write_text(
            json.dumps({"fetched": fetched.isoformat(), "value": value},
                       ensure_ascii=False),
            encoding="utf-8",
        )
        os.replace(tmp, target)
    except Exception:
        log.debug("could not persist cache for %s", name, exc_info=True)


def _disk_drop(name: str) -> None:
    try:
        _disk_path(name).unlink()
    except (FileNotFoundError, OSError):
        pass


class NotReady(Exception):
    """The source has not published the new period's data yet."""


def boundary_cache(anchor_fn, persist: str | None = None, *,
                   settle_minutes: float | None = None,
                   settle_ttl: int | None = None) -> Callable:
    """Cache a result until the next reset boundary.

    A value stays valid for the whole period once fetched, so repeated
    button presses cost nothing. Two safeguards:
      * anything fetched before the current boundary is discarded;
      * inside the settling window after a reset the value is re-fetched
        every CACHE_SETTLE_TTL seconds, in case the source was not yet
        updated when we first asked.
    On a failed refresh the previous value is served instead of an error.
    ``None`` is never cached or written to disk: an empty result is a miss,
    not an answer that should stick for the rest of the period.
    """
    window = (CACHE_SETTLE_MINUTES if settle_minutes is None else settle_minutes) * 60
    ttl = CACHE_SETTLE_TTL if settle_ttl is None else settle_ttl

    def decorator(fn: Callable) -> Callable:
        lock = threading.Lock()
        state: dict[tuple, tuple[datetime, Any]] = {}
        failed_at: dict[tuple, datetime] = {}

        def wrapper(*args, force: bool = False, **kwargs):
            key = (args, tuple(sorted(kwargs.items())))
            now = datetime.now(timezone.utc)
            boundary = anchor_fn(now)
            with lock:
                cached = state.get(key)
                if cached is None and persist and not args and not kwargs:
                    cached = _disk_load(persist)
                    if cached and cached[1] is not None:
                        state[key] = cached
                    else:
                        cached = None      # old builds persisted null
                last_fail = failed_at.get(key)

            if cached and not force:
                fetched, value = cached
                if fetched >= boundary:
                    settling = (now - boundary).total_seconds() < window
                    if not settling or (now - fetched).total_seconds() < ttl:
                        return value
                # Stale, but the source just failed: do not hammer it on
                # every button press — serve the old value for a while.
                if last_fail and (now - last_fail).total_seconds() < ttl:
                    return value

            try:
                value = fn(*args, **kwargs)
                if value is None:
                    raise ValueError(f"{fn.__name__} returned no data")
            except Exception as exc:
                with lock:
                    failed_at[key] = datetime.now(timezone.utc)
                if isinstance(exc, NotReady):
                    log.info("%s: %s", fn.__name__, exc)
                else:
                    log.exception("refresh failed: %s", fn.__name__)
                if cached:
                    log.warning("serving cached data for %s", fn.__name__)
                    return cached[1]
                raise

            stamped = datetime.now(timezone.utc)
            with lock:
                failed_at.pop(key, None)
                state[key] = (stamped, value)
            if persist and not args and not kwargs:
                _disk_save(persist, stamped, value)
            return value

        def clear() -> None:
            with lock:
                state.clear()
                failed_at.clear()
            if persist:
                _disk_drop(persist)

        def peek():
            """Last known value without fetching (memory, then disk)."""
            with lock:
                for (k_args, _), (_, value) in state.items():
                    if not k_args:
                        return value
            if persist:
                cached = _disk_load(persist)
                if cached and cached[1] is not None:
                    return cached[1]
            return None

        wrapper.cache_clear = clear  # type: ignore[attr-defined]
        wrapper.peek = peek  # type: ignore[attr-defined]
        wrapper.__name__ = fn.__name__
        return wrapper

    return decorator


# --------------------------------------------------------------------------
# Mission parsing
# --------------------------------------------------------------------------
VBUCKS_RE = re.compile(r"(v[\s_\-]?bucks|currency_mtxswap)", re.IGNORECASE)


def _extract_json(text: str) -> Any:
    """Accept either a raw JSON body or JSON embedded in a <script> tag."""
    stripped = text.lstrip()
    if stripped[:1] in "[{":
        try:
            return json.loads(stripped)
        except json.JSONDecodeError:
            pass

    soup = BeautifulSoup(text, "html.parser")
    for script in soup.find_all("script"):
        blob = script.string or script.get_text() or ""
        if "powerLevel" not in blob and "alertRewards" not in blob:
            continue
        for opener, closer in (("[", "]"), ("{", "}")):
            start, end = blob.find(opener), blob.rfind(closer)
            if start != -1 and end > start:
                try:
                    return json.loads(blob[start:end + 1])
                except json.JSONDecodeError:
                    continue
    raise ValueError("no mission JSON found in response")


def _as_mission_list(data: Any) -> list[dict]:
    if isinstance(data, dict):
        for key in ("missions", "data", "result", "alerts"):
            if isinstance(data.get(key), list):
                data = data[key]
                break
        else:
            data = [v for v in data.values() if isinstance(v, dict)]
    if not isinstance(data, list):
        return []
    return [m for m in data if isinstance(m, dict)]


def _prettify_item(raw: Any) -> str:
    name = str(raw or "").split(":")[-1].replace("_", " ").strip()
    name = re.sub(r"\s+", " ", name)
    return name.title() if name else "Item"


def _rewards(mission: dict, key: str) -> list[dict]:
    raw = mission.get(key) or []
    if isinstance(raw, dict):
        raw = [raw]
    out: list[dict] = []
    if not isinstance(raw, list):
        return out
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        item = entry.get("itemType") or entry.get("item") or entry.get("name") or ""
        try:
            qty = int(entry.get("quantity", entry.get("qty", 1)) or 1)
        except (TypeError, ValueError):
            qty = 1
        raw_id = str(item)
        # Heroes come as a bare name ("Fleetfoot Ken (Legendary)"); tag them so
        # the icon, the Hero filter and Top Missions scoring see a hero.
        if str(entry.get("rewardType", "")).lower() == "heroes"                 and not re.search(r"hero|hid_", raw_id, re.I):
            raw_id = f"Hero:{raw_id}"
        out.append({"item": _prettify_item(item), "raw": raw_id, "qty": qty})
    return out


def _normalise(mission: dict) -> dict:
    try:
        power = int(mission.get("powerLevel") or mission.get("power") or 0)
    except (TypeError, ValueError):
        power = 0
    return {
        "zone": str(mission.get("zone") or mission.get("zoneTheme") or "Unknown"),
        "name": str(mission.get("name") or mission.get("missionType") or "Mission"),
        "biome": str(mission.get("biome") or ""),
        "power": power,
        "alert": _rewards(mission, "alertRewards"),
        "basic": _rewards(mission, "missionRewards"),
    }


@boundary_cache(daily_anchor, persist="missions")
def _missions() -> list[dict]:
    response = _SESSION.get(MISSIONS_URL, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()
    ctype = (response.headers.get("content-type") or "").lower()
    data = response.json() if "json" in ctype else _extract_json(response.text)
    missions = [_normalise(m) for m in _as_mission_list(data)]
    log.info("fetched %d missions", len(missions))
    return missions


def fetch_vbucks_missions(*, force: bool = False) -> list[dict]:
    """Missions whose *alert* rewards contain V-Bucks."""
    found = []
    for mission in _missions(force=force):
        qty = sum(r["qty"] for r in mission["alert"] if VBUCKS_RE.search(r["raw"]))
        if qty:
            found.append({**mission, "vbucks": qty})
    found.sort(key=lambda m: (-m["vbucks"], ZONE_ORDER(m), m["name"]))
    return found


def fetch_power_missions(power: int = 160, *, force: bool = False) -> list[dict]:
    found = [m for m in _missions(force=force) if m["power"] == power]
    found.sort(key=lambda m: (ZONE_ORDER(m), m["name"]))
    return found


def fetch_all_missions(*, force: bool = False) -> list[dict]:
    """Every map mission in every zone, for the reward finder.

    Story quests and event nodes are left out (they are not map tiles);
    missions that carry an alert are always kept, whatever their name.
    """
    found = [m for m in _missions(force=force)
             if not is_dungeon(m) and (m["alert"] or is_standard_mission(m))]
    found.sort(key=lambda m: (ZONE_ORDER(m), -m["power"], m["name"]))
    return _dedupe(found)


# --- Ventures -------------------------------------------------------------
# A Ventures mission is recognised by its zone/biome/name. Dungeons are
# explicitly excluded: they share the power level but are a separate mode.
VENTURE_RE = re.compile(
    r"venture|mild\s*meadows|scurvy\s*shoals|blasted\s*badlands|"
    r"hexsylvania|frostnite",
    re.IGNORECASE,
)
DUNGEON_RE = re.compile(r"dungeon", re.IGNORECASE)


def is_venture(mission: dict) -> bool:
    blob = f"{mission.get('zone', '')} {mission.get('biome', '')} {mission.get('name', '')}"
    return bool(VENTURE_RE.search(blob))


def is_dungeon(mission: dict) -> bool:
    blob = f"{mission.get('zone', '')} {mission.get('name', '')}"
    return bool(DUNGEON_RE.search(blob))


_ZONE_RANKS = (
    (re.compile(r"stonewood", re.I), 0),
    (re.compile(r"plankerton", re.I), 1),
    (re.compile(r"canny", re.I), 2),
    (re.compile(r"twine", re.I), 3),
)


def ZONE_ORDER(mission: dict) -> tuple:
    """Game order (SW, PL, CV, TP, Ventures, other) instead of A-Z."""
    zone = str(mission.get("zone", ""))
    for pattern, rank in _ZONE_RANKS:
        if pattern.search(zone):
            return (rank, zone)
    return (4 if is_venture(mission) else 5, zone)


def _dedupe(missions: list[dict]) -> list[dict]:
    """Drop exact repeats (same zone, name, biome and rewards)."""
    seen, out = set(), []
    for m in missions:
        key = (m["zone"], m["name"], m["biome"],
               tuple((r["raw"], r["qty"]) for r in m["alert"]),
               tuple((r["raw"], r["qty"]) for r in m["basic"]))
        if key in seen:
            continue
        seen.add(key)
        out.append(m)
    return out


# The source mixes real map missions with story quests and event nodes
# ("Explore the Mist", "Night 1: Rumors of Ghosts", "The Portal (Storm King)").
# Only the standard mission types actually occupy a spot on the zone map, and
# `tile` is 0 for everything, so the type name is the usable signal.
STANDARD_MISSIONS = re.compile(
    r"rescue the survivors|fight (category [0-9]+ )?(the )?storm|trap the storm|"
    r"evacuate the shelter|repair the shelter|build the radar|"
    r"ride the lightning|deliver the bomb|retrieve the data|destroy the encampments|"
    r"eliminate and collect|launch the balloon|refuel the homebase",
    re.IGNORECASE,
)


def is_standard_mission(mission: dict) -> bool:
    return bool(STANDARD_MISSIONS.search(str(mission.get("name", ""))))


def fetch_venture_missions(power: int = 140, *, force: bool = False,
                           standard_only: bool = True) -> list[dict]:
    """Ventures missions at the given power level.

    Dungeons are excluded, and by default so are story quests and event
    nodes — they are not places on the map. Rewards are never used to
    filter: two tiles can legitimately share a mission name with different
    rewards, and both are kept. Only exact repeats are dropped.
    """
    found = [
        m for m in _missions(force=force)
        if m["power"] == power and is_venture(m) and not is_dungeon(m)
        and (not standard_only or is_standard_mission(m))
    ]
    found.sort(key=lambda m: (m["zone"], m["name"]))
    return _dedupe(found)


# --------------------------------------------------------------------------
# Weekly reward (FortniteDB)
# --------------------------------------------------------------------------
# (needle, canonical label, key). Order matters: "Weapon" before "Core", and
# the RE-PERK needles last so "Hero Supercharger" never reads as a perk.
REWARD_MAP = (
    ("WEAPON", "Weapon Supercharger", "weapon"),
    ("HERO", "Hero Supercharger", "hero"),
    ("SURVIVOR", "Survivor Supercharger", "survivor"),
    ("TRAP", "Trap Supercharger", "trap"),
    ("DEFENDER", "Defender Supercharger", "defender"),
    ("RE-PERK", "Core RE-PERK", "core"),
    ("REPERK", "Core RE-PERK", "core"),
    ("CORE", "Core RE-PERK", "core"),
)
WEEKLY_LABELS = {key: label for _, label, key in REWARD_MAP}


def _match_reward(text: str, *, require_marker: bool = True) -> tuple[str, str] | None:
    """(label, key) for a weekly-reward text, or None.

    With ``require_marker`` the text must name a Supercharger / RE-PERK, so
    ordinary "RE-PERK!" alert rows elsewhere on the page never match.
    """
    upper = re.sub(r"\s+", " ", text or "").upper()
    if require_marker and "SUPERCHARGER" not in upper and "RE-PERK" not in upper \
            and "REPERK" not in upper:
        return None
    for needle, label, key in REWARD_MAP:
        if needle in upper:
            return label, key
    return None


def _weekly_fetch_html(url: str = WEEKLY_URL) -> str:
    if cloudscraper is not None:
        try:
            scraper = cloudscraper.create_scraper(browser={"custom": USER_AGENT})
            if PROXIES:
                scraper.proxies.update(PROXIES)
            response = scraper.get(url, timeout=REQUEST_TIMEOUT)
            response.raise_for_status()
            return response.text
        except Exception:
            log.warning("cloudscraper failed, falling back to plain request",
                        exc_info=True)
    response = _SESSION.get(url, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


_WEEKLY_HEAD = re.compile(r"weekly\s*(supercharger|reward|quest)", re.I)
_CHALLENGE = re.compile(r"just a moment|cf-chl|challenge-platform|attention required",
                        re.I)


def parse_weekly(html: str) -> dict | None:
    """Pull the weekly reward out of the FortniteDB home page.

    Layout (2026): a ``new_block_block`` whose ``h5.new_block_header`` reads
    "Weekly Supercharger", followed by a content div holding an <img> and the
    reward name ("Core RE-PERK!", "Hero Supercharger", ...). The old parser
    matched the ``_weekly_q_bg`` CSS class and V-Bucks panels by accident.
    """
    soup = BeautifulSoup(html, "html.parser")

    # 1. The dedicated block, found by its heading.
    def is_heading(tag) -> bool:
        if tag.name in ("h1", "h2", "h3", "h4", "h5", "h6", "th", "strong"):
            return True
        classes = " ".join(tag.get("class") or [])
        return tag.name in ("div", "span", "p") and bool(
            re.search(r"header|title|head\b", classes, re.I))

    for head in soup.find_all(is_heading):
        heading = head.get_text(" ", strip=True)
        if not heading or len(heading) > 60 or not _WEEKLY_HEAD.search(heading):
            continue
        block = head.find_parent("div") or head.parent
        body = head.find_next_sibling() or block
        text = body.get_text(" ", strip=True) if body else ""
        if not text or _WEEKLY_HEAD.fullmatch(text.strip()):
            text = block.get_text(" ", strip=True).replace(heading, "", 1).strip()
        # The heading itself says "Supercharger", so the body needs no marker.
        found = _match_reward(text, require_marker=False) or _match_reward(heading)
        if not found:
            continue
        label, key = found
        name = re.sub(r"\s+", " ", text).strip(" !") or label
        return {"label": label, "key": key, "name": name[:60]}

    # 2. Fallback: any small block that names a Supercharger outright.
    for node in soup.find_all(string=re.compile(r"Supercharger|RE-?PERK", re.I)):
        parent = node.find_parent(["div", "td", "li", "section"])
        if not parent:
            continue
        text = parent.get_text(" ", strip=True)
        if len(text) > 120 or not re.search(r"weekly|supercharger", text, re.I):
            continue
        found = _match_reward(text)
        if found:
            return {"label": found[0], "key": found[1], "name": found[0]}
    return None


def _week_id(now: datetime | None = None) -> str:
    return weekly_anchor(now or datetime.now(timezone.utc)).date().isoformat()


def _weekly_sources() -> list[tuple[str, str]]:
    sources = [("FortniteDB", WEEKLY_URL)]
    if WEEKLY_URL2:
        host = re.sub(r"^https?://(www\.)?", "", WEEKLY_URL2).split("/")[0]
        sources.append((host or "source 2", WEEKLY_URL2))
    return sources


@boundary_cache(weekly_anchor, persist="weekly",
                settle_minutes=WEEKLY_SETTLE_HOURS * 60, settle_ttl=WEEKLY_SETTLE_TTL)
def fetch_weekly_reward() -> dict:
    """{"label", "key", "name", "week", "fetched", "sources", "conflict"}.

    Every configured source is asked. A source that still shows last week's
    reward shortly after the reset is ignored (NotReady when none is left),
    so a stale value is never stamped as this week's. When two sources
    disagree the first one wins and ``conflict`` is set for the admin.
    """
    now = datetime.now(timezone.utc)
    week = _week_id(now)
    previous = fetch_weekly_reward.peek()
    settling = (now - weekly_anchor(now)).total_seconds() < WEEKLY_SETTLE_HOURS * 3600
    results: dict[str, dict] = {}
    errors: list[str] = []
    stale = 0
    for name, url in _weekly_sources():
        try:
            html = _weekly_fetch_html(url)
        except Exception as exc:
            errors.append(f"{name}: {exc}")
            continue
        parsed = parse_weekly(html)
        if not parsed:
            errors.append(f"{name}: " + ("bot-check page" if _CHALLENGE.search(html[:5000])
                                         else "weekly block not found"))
            continue
        if isinstance(previous, dict) and previous.get("week") != week and settling \
                and previous.get("label") == parsed["label"]:
            stale += 1
            continue
        results[name] = parsed

    if not results:
        if stale:
            raise NotReady("weekly sources still show last week's reward")
        raise ValueError("; ".join(errors) or "no weekly source answered")

    labels = {name: r["label"] for name, r in results.items()}
    first = next(iter(results.values()))
    value = dict(first)
    value.update(week=week, fetched=now.isoformat(timespec="seconds"),
                 source=next(iter(results)), sources=labels,
                 conflict=len(set(labels.values())) > 1)
    log.info("weekly reward: %s (%s)", value["label"], labels)
    return value


# --- manual override (admin) ---------------------------------------------
def _override_path() -> Path:
    return CACHE_DIR / "weekly-override.json"


def get_weekly_override() -> dict | None:
    try:
        raw = json.loads(_override_path().read_text("utf-8"))
    except Exception:
        return None
    return raw if isinstance(raw, dict) and raw.get("week") == _week_id() else None


def set_weekly_override(key: str | None) -> dict | None:
    """Pin this week's reward (key in WEEKLY_LABELS), or None to go back to auto."""
    path = _override_path()
    if not key:
        try:
            path.unlink()
        except OSError:
            pass
        return None
    if key not in WEEKLY_LABELS:
        raise ValueError(f"unknown weekly reward {key!r}")
    now = datetime.now(timezone.utc)
    value = {"label": WEEKLY_LABELS[key], "key": key, "name": WEEKLY_LABELS[key],
             "week": _week_id(now), "fetched": now.isoformat(timespec="seconds"),
             "source": "manual", "sources": {"manual": WEEKLY_LABELS[key]},
             "conflict": False}
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)
    return value


def get_weekly(*, force: bool = False) -> Any:
    """What the bot shows: the admin's pin for this week, else the sources."""
    return get_weekly_override() or fetch_weekly_reward(force=force)


def weekly_is_current(value: Any) -> bool:
    """True when ``value`` was scraped during the current game week."""
    return isinstance(value, dict) and value.get("week") == _week_id()


# --------------------------------------------------------------------------
# Season countdown (fortnite.gg)
# --------------------------------------------------------------------------
_DATE_RE = re.compile(r"ends? on [A-Za-z]+,\s*([A-Za-z]+ \d{1,2},\s*\d{4})", re.I)


@boundary_cache(daily_anchor)
def fetch_season_end() -> datetime | None:
    response = _SESSION.get(SEASON_URL, timeout=REQUEST_TIMEOUT)
    response.raise_for_status()
    match = _DATE_RE.search(response.text)
    if not match:
        return None
    raw = re.sub(r"\s+", " ", match.group(1)).strip()
    try:
        parsed = datetime.strptime(raw, "%B %d, %Y")
    except ValueError:
        return None
    return parsed.replace(hour=7, minute=30, tzinfo=timezone.utc)


def fetch_text(url: str, *, timeout: float | None = None) -> str:
    """Plain GET through the shared session (proxy, retries, timeout)."""
    response = _SESSION.get(url, timeout=timeout or REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.text


def fetch_bytes(url: str, *, timeout: float | None = None) -> bytes:
    """Raw bytes, so a checksum matches what sha256sum sees on disk."""
    response = _SESSION.get(url, timeout=timeout or REQUEST_TIMEOUT)
    response.raise_for_status()
    return response.content


def clear_all_caches() -> None:
    for fn in (_missions, fetch_weekly_reward, fetch_season_end):
        clear = getattr(fn, "cache_clear", None)
        if clear:
            clear()
SCRAPER_PY_EOF

cat > "$APP_DIR/vbucks_bot.py" <<'BOT_PY_EOF'
#!/usr/bin/env python3
"""Fortnite: Save the World — Telegram bot (bilingual EN/FA).

Secrets are read from the environment only (systemd EnvironmentFile,
mode 0640). Nothing sensitive is ever written into the source files,
the unit file or the logs.
"""

from __future__ import annotations

import asyncio
import csv
import hashlib
import html
import io
import json
import logging
import os
import re
import sys
import tempfile
from datetime import datetime, time as dtime, timezone
from pathlib import Path
from typing import Any, Iterable

from telegram import (
    BotCommand,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    InputFile,
    InputMediaPhoto,
    KeyboardButton,
    ReplyKeyboardMarkup,
    Update,
)
from telegram.constants import ParseMode
from telegram.error import BadRequest, Forbidden, RetryAfter, TelegramError
from telegram.ext import (
    ApplicationBuilder,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    Defaults,
    MessageHandler,
    filters,
)
from telegram.request import HTTPXRequest

import vbucks_scraper as src
import vbucks_image as vimg
from vbucks_scraper import redact_url

try:
    from telegram.ext import AIORateLimiter
except ImportError:  # pragma: no cover
    AIORateLimiter = None  # type: ignore

E = html.escape

# ==========================================================================
# Configuration
# ==========================================================================
BOT_TOKEN = os.environ.get("BOT_TOKEN", "").strip()
ADMIN_ID = os.environ.get("ADMIN_CHAT_ID", "").strip()
PROXY_URL = os.environ.get("PROXY_URL", "").strip()

DATA_DIR = Path(os.environ.get("DATA_DIR", "/var/lib/fortnite_bot"))
USERS_FILE = DATA_DIR / "users.json"

MAX_USERS = int(os.environ.get("MAX_USERS", "200"))
BROADCAST_DELAY = float(os.environ.get("BROADCAST_DELAY", "0.06"))
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()

DAILY_RESET_UTC = os.environ.get("DAILY_RESET_UTC", "00:01")
WEEKLY_RESET_UTC = os.environ.get("WEEKLY_RESET_UTC", "00:02")
# 0 = Monday ... 6 = Sunday. STW weekly reset is Thursday.
WEEKLY_RESET_WEEKDAY = int(os.environ.get("WEEKLY_RESET_WEEKDAY", "3"))

SEASON_START_UTC = os.environ.get("SEASON_START_UTC", "2026-08-20T07:30:00+00:00")
SEASON_END_UTC = os.environ.get("SEASON_END_UTC", "2026-11-01T07:30:00+00:00")

DEFAULT_LANG = os.environ.get("DEFAULT_LANG", "en")

# --- self-update ----------------------------------------------------------
# The bot runs unprivileged, so it cannot install anything itself. It writes
# a request file; a root-owned systemd path unit notices it and runs the
# installer, which writes the outcome back for the bot to report.
BOT_VERSION = os.environ.get("BOT_VERSION", "0.0.0")
UPDATE_URL = os.environ.get("UPDATE_URL", "").strip()
INSTALLER_SHA_FILE = Path(os.environ.get("INSTALLER_SHA_FILE",
                                         "/etc/fortnite_bot/installer.sha256"))
UPDATE_REQUEST = DATA_DIR / "update.request"
UPDATE_RESULT = DATA_DIR / "update.result"

TOKEN_RE = re.compile(r"^\d{6,12}:[A-Za-z0-9_-]{30,}$")
MAX_BROADCAST_CHARS = 3000


# ==========================================================================
# Logging (with credential redaction)
# ==========================================================================
class RedactFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        try:
            message = record.getMessage()
        except Exception:
            return True
        cleaned = redact_url(message)
        if BOT_TOKEN and BOT_TOKEN in cleaned:
            cleaned = cleaned.replace(BOT_TOKEN, "***TOKEN***")
        if cleaned != message:
            record.msg = cleaned
            record.args = ()
        return True


logging.basicConfig(
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
    level=getattr(logging, LOG_LEVEL, logging.INFO),
)
for handler in logging.getLogger().handlers:
    handler.addFilter(RedactFilter())
logging.getLogger("httpx").setLevel(logging.WARNING)
log = logging.getLogger("fortnite-bot")


def _parse_hhmm(value: str, fallback: tuple[int, int]) -> dtime:
    try:
        hour, minute = (int(x) for x in value.split(":", 1))
        return dtime(hour=hour, minute=minute, tzinfo=timezone.utc)
    except Exception:
        log.warning("bad time %r, using %02d:%02d", value, *fallback)
        return dtime(hour=fallback[0], minute=fallback[1], tzinfo=timezone.utc)


def _parse_dt(value: str) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


# ==========================================================================
# Filter definitions
# ==========================================================================
ZONES = ["Stonewood", "Plankerton", "Canny Valley", "Twine Peaks",
         "Ventures", "Other"]
ZONE_PATTERNS = {
    "Stonewood": re.compile(r"stonewood", re.I),
    "Plankerton": re.compile(r"plankerton", re.I),
    "Canny Valley": re.compile(r"canny", re.I),
    "Twine Peaks": re.compile(r"twine", re.I),
    # Ventures rotates its map name, so reuse the scraper's cycle pattern.
    "Ventures": src.VENTURE_RE,
}

# Each pattern must match BOTH the display name ("Gold", "PERK-UP! (Rare)") and
# the raw item id from the source ("AccountResource:eventcurrency_scaling",
# "reagent_alteration_upgrade_r"). Matching only the pretty English words
# missed most rewards: Gold, Perk-Up, Leads, Flux and rarity are all ids.
_RARITY_ID = r"(?:^|[_:\s])%s(?=[_\s|)]|$)"
REWARD_FILTERS: list[tuple[str, re.Pattern]] = [
    ("V-Bucks", re.compile(r"v[\s_\-]?bucks|currency_mtxswap", re.I)),
    ("Survivor", re.compile(r"survivor(?!\s*xp)|worker|manager|\blead\b", re.I)),
    ("Hero", re.compile(r"\bhero\b(?!\s*xp)|\bhid_", re.I)),
    ("Defender", re.compile(r"defender|\bdid_", re.I)),
    ("Schematic", re.compile(r"schematic(?!\s*xp)|\bsid_|\bweapon\b", re.I)),
    ("Trap", re.compile(r"\btraps?\b(?! designs)|\bsid_(?:floor|wall|ceiling)_", re.I)),
    ("Evo Mat", re.compile(r"reagent_(?:c_t0|people|weapons|traps|evolverarity)|"
                           r"evolution|evo[_\s-]|pure drop|rain|lightning in|"
                           r"training|designs|eye of the storm|storm shard|flux", re.I)),
    ("Perk-Up", re.compile(r"perk-?up|re-?perk|alteration_upgrade|alteration_generic",
                           re.I)),
    ("Gold", re.compile(r"\bgold\b|eventcurrency_scaling", re.I)),
    ("XP", re.compile(r"\bxp\b|personnelxp|heroxp|schematicxp|phoenixxp", re.I)),
    ("Legendary", re.compile(r"legendary|" + _RARITY_ID % "sr", re.I)),
    ("Epic", re.compile(r"\bepic\b|" + _RARITY_ID % "vr", re.I)),
]
REWARD_NAMES = [name for name, _ in REWARD_FILTERS]

DEFAULT_PREFS: dict[str, Any] = {
    "lang": DEFAULT_LANG,
    "notify": True,
    "banned": False,
    "zones": [],        # empty == all zones
    "rewards": [],      # empty == all rewards
    "image_mode": False,
}
EDITABLE = set(DEFAULT_PREFS)


def zone_key(zone: str) -> str:
    for name, pattern in ZONE_PATTERNS.items():
        if pattern.search(zone or ""):
            return name
    return "Other"


_FILTER_BY_NAME = dict(REWARD_FILTERS)
# Rarity filters narrow the type filters: "Legendary" + "Survivor" means a
# LEGENDARY SURVIVOR, not "any survivor or anything legendary". They look at
# alert rewards only (every Twine mission has an "(Epic)" basic reward).
RARITY_FILTERS = {"Legendary", "Epic"}
ALERT_ONLY = RARITY_FILTERS


def _reward_haystack(mission: dict, alert_only: bool = False) -> str:
    """Rewards of a mission as raw id + display name (alert, then basic)."""
    rewards = list(mission.get("alert") or [])
    if not alert_only:
        rewards += mission.get("basic") or []
    return " | ".join(f"{r.get('raw', '')} | {r.get('item', '')}" for r in rewards)


def mission_matches_rewards(mission: dict, selected: list[str]) -> bool:
    """Types are OR-ed; a selected rarity must hold for the SAME reward."""
    selected = [n for n in selected if n in _FILTER_BY_NAME]
    if not selected:
        return True
    rarities = [_FILTER_BY_NAME[n] for n in selected if n in RARITY_FILTERS]
    types = [_FILTER_BY_NAME[n] for n in selected if n not in RARITY_FILTERS]
    alert = mission.get("alert") or []
    pool = alert if rarities else alert + (mission.get("basic") or [])
    for r in pool:
        text = f"{r.get('raw', '')} | {r.get('item', '')}"
        if types and not any(p.search(text) for p in types):
            continue
        if rarities and not any(p.search(text) for p in rarities):
            continue
        return True
    return False


def apply_filters(missions: list[dict], prefs: dict, **_ignored) -> list[dict]:
    """Zone and reward filters, applied to every mission list alike.

    Walks the COMPLETE list: fetchers no longer truncate, so every zone is
    checked before anything is cut for display.
    """
    zones = set(prefs.get("zones") or [])
    rewards = [r for r in (prefs.get("rewards") or []) if r in _FILTER_BY_NAME]
    return [m for m in missions
            if (not zones or zone_key(m.get("zone", "")) in zones)
            and mission_matches_rewards(m, rewards)]


# --------------------------------------------------------------------------
# Result caches. Mission rewards are fixed for the whole game day, so the
# filtered list, the rendered picture and Telegram's file_id for it are kept
# until the next 00:00 UTC reset; the first request after a reset rebuilds
# them. Entries are tied to the exact mission list object they came from, so
# a refreshed list (settling window, admin refresh) never serves old data.
# --------------------------------------------------------------------------
class DayCache:
    def __init__(self, max_entries: int = 512) -> None:
        self._day: str = ""
        self._data: dict = {}
        self._max = max_entries

    def _roll(self) -> None:
        day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        if day != self._day:
            self._day = day
            self._data.clear()

    def get(self, key, source) -> Any:
        self._roll()
        hit = self._data.get(key)
        if hit is None or hit[0] is not source:
            return None
        return hit[1]

    def put(self, key, source, value) -> None:
        self._roll()
        if len(self._data) >= self._max:
            self._data.pop(next(iter(self._data)))
        self._data[key] = (source, value)

    def clear(self) -> None:
        self._data.clear()


FILTER_CACHE = DayCache()
TOP_CACHE = DayCache(8)
PHOTO_CACHE = DayCache(256)   # key -> {"png": bytes, "file_id": str | None}


def filter_key(kind: str, prefs: dict) -> tuple:
    return (kind, tuple(sorted(prefs.get("zones") or [])),
            tuple(sorted(prefs.get("rewards") or [])))


def cached_filter(missions: list[dict], prefs: dict, kind: str) -> list[dict]:
    key = filter_key(kind, prefs)
    hit = FILTER_CACHE.get(key, missions)
    if hit is None:
        hit = apply_filters(missions, prefs)
        FILTER_CACHE.put(key, missions, hit)
    return hit


# Notable alert rewards, the way daily STW summaries list them: V-Bucks,
# X-Ray tickets, Mythic anything, Legendary heroes/survivors/leads/defenders/
# schematics, Legendary Perk-Up and Legendary Flux.
TOP_RE = re.compile(
    r"v[\s_\-]?bucks|mtxswap|x-?ray|xrayllama|mythic|"
    r"alteration_upgrade_sr|legendary perk|evolverarity_sr|legendary flux", re.I)
TOP_ITEM_RE = re.compile(r"worker:|hero:|defender:|schematic:|survivor|\blead\b|"
                         r"hero|defender|schematic", re.I)
LEGENDARY_RE = re.compile(r"legendary|(?:^|[_:\s])sr(?=[_\s|)]|$)", re.I)


def is_top_reward(r: dict) -> bool:
    text = f"{r.get('raw', '')} | {r.get('item', '')}"
    if TOP_RE.search(text):
        return True
    raw = str(r.get("raw", ""))
    looks_item = bool(re.match(r"(worker|hero|defender|schematic):", raw, re.I)) \
        or bool(re.search(r"survivor|lead|defender|schematic|hero", str(r.get("item", "")), re.I))
    return looks_item and bool(LEGENDARY_RE.search(text)) and not re.search(r"\bxp\b", text, re.I)


TOP_PER_ZONE = int(os.environ.get("TOP_PER_ZONE", "5"))
_TOP_SCORES = (
    (re.compile(r"v[\s_\-]?bucks|mtxswap", re.I), 10000),
    (re.compile(r"x-?ray|xrayllama", re.I), 9000),
    (re.compile(r"mythic", re.I), 8000),
    (re.compile(r"storm shard|reagent_c_t04", re.I), 3500),
    (re.compile(r"eye of the storm|reagent_c_t03", re.I), 3400),
    (re.compile(r"lightning in a bottle|reagent_c_t02", re.I), 3300),
    (re.compile(r"pure drop|reagent_c_t01", re.I), 3000),
    (re.compile(r"re-?perk|alteration_generic", re.I), 4000),
)
_LEG_ITEM = re.compile(r"(\blead\b|manager|hero:|\bhid_|defender|\bdid_)", re.I)
_ANY_ITEM = re.compile(r"worker:|survivor(?!\s*xp)|schematic:|\bsid_", re.I)


def reward_score(r: dict) -> int:
    """Value of one alert reward: V-Bucks > X-Ray > Mythic > Legendary
    lead/hero/defender > Legendary survivor/schematic > Legendary Perk-Up
    / Flux > RE-PERK > evo mats > Epic items. Quantity breaks ties."""
    text = f"{r.get('raw', '')} | {r.get('item', '')}"
    qty = int(r.get("qty") or 1)
    for pattern, base in _TOP_SCORES[:3]:
        if pattern.search(text):
            return base + min(qty, 999)
    legendary = bool(LEGENDARY_RE.search(text))
    if legendary and _LEG_ITEM.search(text):
        return 7000
    if legendary and _ANY_ITEM.search(text):
        return 6000
    if re.search(r"perk-?up|alteration_upgrade", text, re.I) and legendary:
        return 5000 + min(qty, 999)
    if re.search(r"flux|evolverarity", text, re.I) and legendary:
        return 4800 + min(qty, 99)
    for pattern, base in _TOP_SCORES[3:]:
        if pattern.search(text):
            return base + min(qty, 999)
    if re.search(r"\bepic\b|(?:^|[_:])vr(?=[_\s|)]|$)", text, re.I) and \
            (_LEG_ITEM.search(text) or _ANY_ITEM.search(text)):
        return 2000
    return 0


def mission_score(m: dict) -> int:
    scores = sorted((reward_score(r) for r in m.get("alert") or []), reverse=True)
    return (scores[0] + sum(scores[1:]) // 100) if scores and scores[0] else 0


def top_missions(missions: list[dict]) -> list[dict]:
    """The best TOP_PER_ZONE missions of every zone, highest value first."""
    out: list[dict] = []
    for _, group in group_by_zone([m for m in missions if mission_score(m) > 0]):
        ranked = sorted(group, key=lambda m: (-mission_score(m), -m.get("power", 0)))
        out += ranked[:max(1, TOP_PER_ZONE)]
    return out


def group_by_zone(missions: list[dict]) -> list[tuple[str, list[dict]]]:
    order = ["Stonewood", "Plankerton", "Canny Valley", "Twine Peaks", "Ventures", "Other"]
    groups: dict[str, list[dict]] = {}
    for m in missions:
        groups.setdefault(zone_key(m.get("zone", "")), []).append(m)
    return [(z, groups[z]) for z in order if z in groups]


def unfiltered(prefs: dict | None) -> dict:
    """Same user settings minus zone/reward filters (those are finder-only)."""
    return {**(prefs or DEFAULT_PREFS), "zones": [], "rewards": []}


def filters_active(prefs: dict) -> bool:
    return bool(prefs.get("zones") or prefs.get("rewards"))


# ==========================================================================
# Localisation
# ==========================================================================
TEXTS: dict[str, dict[str, str]] = {
    "en": {
        "welcome": "Welcome! Use the menu below for Fortnite STW updates.",
        "lang_selected": "🇬🇧 English selected.",
        "btn_vbucks": "💎 V-Bucks Missions",
        "btn_160": "⚡ Power 160 Missions",
        "btn_v140": "🌴 Ventures 140 Missions",
        "btn_weekly": "🛠 Weekly Reward",
        "btn_timer": "⏱ Season Timers",
        "btn_filters": "⚙️ My Filters",
        "btn_lang": "🌐 Language (زبان)",
        "btn_image_on": "🖼 Image mode: ON",
        "btn_image_off": "📝 Text mode",
        "image_on": "🖼 Mission lists now arrive as a picture.",
        "image_off": "📝 Mission lists now arrive as text.",
        "image_failed": "⚠️ Could not draw the picture, so here is the text version.",
        "image_caption": "{} — {} missions",
        "btn_notify_on": "🔔 Alerts: ON",
        "btn_notify_off": "🔕 Alerts: OFF",
        "notify_on": "🔔 Daily and weekly alerts are ON.",
        "notify_off": "🔕 Alerts are OFF. You can turn them back on anytime.",
        "fetching": "⏳ Fetching data…",
        "error": "❌ Could not fetch the data right now. Please try again in a moment.",
        "timer_prompt": "⏱ Pick a season to see the remaining time:",
        "timer_bp": "🏆 Battle Pass",
        "timer_venture": "⚡ Ventures",
        "timer_updated": "Updated 🔄",
        "season_ended": "⚠️ The <b>{}</b> has ended — waiting for the next one.",
        "vbucks_title": "💎 <b>Today's V-Bucks Missions</b>",
        "vbucks_none": "❌ No V-Bucks missions available today.",
        "p160_title": "⚡ <b>Today's Power 160 Missions</b>",
        "p160_none": "❌ No Power 160 missions available today.",
        "v140_title": "🌴 <b>Ventures — Power 140 Missions</b>",
        "v140_none": "❌ No Ventures 140 missions today (dungeons excluded).",
        "weekly_title": "🛠 <b>This Week's Reward</b>",
        "weekly_none": "❌ Could not determine this week's reward.",
        "weekly_stale": "⏳ <i>FortniteDB has not published this week's reward yet — showing last week's. Try again a bit later.</i>",
        "weekly_week": "Week of {}",
        "weekly_caption": "🛠 This week's reward: {}",
        "btn_finder": "🔎 Reward Finder",
        "btn_top": "🔥 Top Missions",
        "top_title": "🔥 <b>Top Missions</b>",
        "top_zone": "🔥 Top — {}",
        "top_none": "❌ No notable missions today.",
        "top_caption": "🔥 Best missions of each zone today — {} in {} zone(s)",
        "finder_title": "🔎 <b>Reward Finder — all zones</b>",
        "finder_none": "❌ No mission in any zone has the rewards you picked today.",
        "finder_need": "🔎 Pick at least one reward in ⚙️ My Filters first — the finder then searches every mission in every zone (Stonewood → Twine Peaks and Ventures).",
        "more_hidden": "➕ <i>{} more not shown. Narrow your filters to see them.</i>",
        "daily_title": "🔔 <b>Fortnite Daily Reset</b>",
        "weekly_push": "🚨 <b>Fortnite Weekly Reset</b>",
        "alerts_label": "🎁 Alert rewards",
        "basic_label": "📦 Basic rewards",
        "none": "None",
        "full": "⚠️ The bot has reached its user limit. Please try again later.",
        "filtered_out": "🔍 Nothing matched your filters ({} hidden).",
        "filter_hint": "🔍 <i>Filters are active.</i>",
        "filters_title": (
            "⚙️ <b>My Filters</b>\n\n"
            "These filters are used only by 🔎 Reward Finder.\n"
            "V-Bucks, Power 160, Ventures and the daily alerts always show everything."
        ),
        "filters_zones": "— Zones —",
        "filters_rewards": "— Rewards —",
        "filters_reset": "♻️ Reset",
        "filters_close": "✅ Done",
        "filters_saved": "⚙️ Filters saved.",
        "help": (
            "<b>Commands</b>\n"
            "/start — open the menu\n"
            "/menu — show the keyboard again\n"
            "/filters — set zone and reward filters\n"
            "/alerts — toggle daily/weekly alerts\n"
            "/help — this message"
        ),
        "admin_panel": "👑 <b>Admin panel</b>",
        "admin_stat": (
            "📊 <b>Stats</b>\n\n"
            "Users: <code>{}</code>\n"
            "Subscribed: <code>{}</code>\n"
            "Banned: <code>{}</code>\n"
            "With filters: <code>{}</code>"
        ),
        "admin_new": "👤 <b>New user</b>\n\nName: {}\nUsername: {}\nID: <code>{}</code>",
        "admin_bc_usage": "Usage: <code>/broadcast your message here</code>",
        "admin_bc_prompt": (
            "📢 <b>Broadcast</b>\n\n"
            "Send me the message now and I will show you a preview "
            "before anything goes out.\n"
            "Send /cancel to abort."
        ),
        "admin_bc_none": "⚠️ Nobody is subscribed to alerts, so there is no one to send to.",
        "admin_bc_long": "❌ Message too long (max {} characters).",
        "admin_bc_confirm": "📢 Send this to <b>{}</b> users?\n\n──────\n{}",
        "admin_bc_sent": "✅ Broadcast finished. Sent: <code>{}</code> — failed: <code>{}</code>",
        "admin_bc_cancel": "🚫 Broadcast cancelled.",
        "admin_bc_expired": "⚠️ Nothing pending.",
        "admin_ban_usage": "Usage: <code>/ban 123456789</code>",
        "admin_unban_usage": "Usage: <code>/unban 123456789</code>",
        "admin_bad_id": "❌ That is not a valid numeric ID.",
        "admin_ban_self": "❌ You cannot ban yourself.",
        "admin_ban_ok": "🚫 User <code>{}</code> banned.",
        "admin_unban_ok": "✅ User <code>{}</code> unbanned.",
        "admin_unknown": "❌ User <code>{}</code> not found.",
        "admin_banned_list": "🚫 <b>Banned users</b>\n\n{}",
        "admin_banned_empty": "✅ No banned users.",
        "admin_export": "📤 User export ({} rows).",
        "admin_import_help": (
            "📥 <b>Import users</b>\n\n"
            "Send me the <code>users-*.csv</code> file from /export, or a "
            "<code>users.json</code> backup.\n"
            "Existing users are updated, new ones are added. "
            "Nobody is ever deleted."
        ),
        "admin_import_ok": (
            "✅ <b>Import finished</b>\n\n"
            "Added: <code>{}</code>\nUpdated: <code>{}</code>\n"
            "Skipped (limit reached): <code>{}</code>"
        ),
        "admin_import_bad": "❌ Could not read that file. Expecting the CSV from /export or a users.json.",
        "admin_import_empty": "⚠️ No valid user rows found in that file.",
        "admin_import_big": "❌ File too large (max {} KB).",
        "adm_import": "📥 Import",
        "adm_update": "⬆️ Update",
        "upd_checking": "⏳ Checking for a new version…",
        "upd_none": "✅ <b>Up to date</b>\n\nVersion <code>{}</code>. The published installer matches what is running.",
        "upd_found": "⬆️ <b>Update available</b>\n\nInstalled: <code>{}</code>\nPublished: <code>{}</code>\n{}\n\nUpdating restarts the bot. Settings and users are kept.",
        "upd_code_changed": "The code changed even though the version is the same.",
        "upd_version_changed": "A newer version is published.",
        "upd_failed": "❌ Could not check for updates: <code>{}</code>",
        "upd_no_url": "⚠️ No update URL is configured. Set <code>UPDATE_URL</code> in the config.",
        "upd_started": "⬆️ Update started. The bot restarts in a moment and reports back here.",
        "upd_queued_already": "⏳ An update is already queued.",
        "upd_report_ok": "✅ <b>Update finished</b>\n\nNow running <code>{}</code> (was <code>{}</code>).",
        "upd_report_fail": "❌ <b>Update failed</b>\n\nStill running <code>{}</code>.\n<code>{}</code>",
        "admin_refreshed": "♻️ Caches cleared.",
        "btn_admin": "👑 Admin",
        "adm_stats": "📊 Stats",
        "adm_export": "📤 Export",
        "adm_banned": "🚫 Banned",
        "adm_refresh": "♻️ Refresh",
        "adm_bc_help": "📢 Broadcast",
        "adm_weekly": "🛠 Weekly reward",
        "wk_admin": ("🛠 <b>Weekly reward — week of {}</b>\n\n"
                     "Showing: <b>{}</b> ({})\n{}\n\n"
                     "If the game shows something else, pick the right one:"),
        "wk_sources": "Sources: {}",
        "wk_conflict": "⚠️ <b>The sources disagree.</b>",
        "wk_auto": "🔄 Auto (sources)",
        "wk_send": "📢 Send to users",
        "wk_set_ok": "✅ Weekly reward set to {}.",
        "wk_auto_ok": "🔄 Back to automatic sources.",
        "wk_sent": "📢 Weekly reward sent: {} delivered, {} failed.",
        "yes": "✅ Send",
        "no": "🚫 Cancel",
        "progress": "📊 Progress",
        "remaining": "⏳ Remaining",
        "ends": "🗓 Ends",
        "next": "🚀 Next",
        "days": "days",
    },
    "fa": {
        "welcome": "خوش آمدید! از منوی زیر برای دریافت اطلاعات فورتنایت استفاده کنید.",
        "lang_selected": "🇮🇷 زبان فارسی انتخاب شد.",
        "btn_vbucks": "💎 ماموریت‌های ویباکس",
        "btn_160": "⚡ ماموریت‌های پاور ۱۶۰",
        "btn_v140": "🌴 ماموریت‌های ونچر ۱۴۰",
        "btn_weekly": "🛠 جایزه هفتگی",
        "btn_timer": "⏱ تایمر سیزن‌ها",
        "btn_filters": "⚙️ فیلترهای من",
        "btn_lang": "🌐 Language (زبان)",
        "btn_image_on": "🖼 حالت عکس: روشن",
        "btn_image_off": "📝 حالت متن",
        "image_on": "🖼 لیست مأموریت‌ها از این پس به‌صورت عکس می‌آید.",
        "image_off": "📝 لیست مأموریت‌ها از این پس متنی می‌آید.",
        "image_failed": "⚠️ عکس ساخته نشد؛ نسخه متنی را می‌فرستم.",
        "image_caption": "{} — {} مأموریت",
        "btn_notify_on": "🔔 اعلان‌ها: روشن",
        "btn_notify_off": "🔕 اعلان‌ها: خاموش",
        "notify_on": "🔔 اعلان‌های روزانه و هفتگی روشن شد.",
        "notify_off": "🔕 اعلان‌ها خاموش شد. هر وقت خواستی دوباره روشنش کن.",
        "fetching": "⏳ در حال دریافت اطلاعات…",
        "error": "❌ فعلاً نتوانستم اطلاعات را بگیرم. چند لحظه بعد دوباره تلاش کن.",
        "timer_prompt": "⏱ یکی از سیزن‌ها را برای دیدن زمان باقی‌مانده انتخاب کن:",
        "timer_bp": "🏆 بتل‌پس",
        "timer_venture": "⚡ ونچر",
        "timer_updated": "به‌روزرسانی شد 🔄",
        "season_ended": "⚠️ زمان <b>{}</b> تمام شده — منتظر شروع بعدی هستیم.",
        "vbucks_title": "💎 <b>ماموریت‌های ویباکس امروز</b>",
        "vbucks_none": "❌ امروز ماموریت ویباکس موجود نیست.",
        "p160_title": "⚡ <b>ماموریت‌های پاور ۱۶۰ امروز</b>",
        "p160_none": "❌ امروز ماموریت پاور ۱۶۰ موجود نیست.",
        "v140_title": "🌴 <b>ماموریت‌های ونچر — پاور ۱۴۰</b>",
        "v140_none": "❌ امروز ماموریت ونچر ۱۴۰ موجود نیست (دانجن‌ها حذف شدند).",
        "weekly_title": "🛠 <b>جایزه این هفته</b>",
        "weekly_none": "❌ جایزه این هفته مشخص نشد.",
        "weekly_stale": "⏳ <i>سایت FortniteDB هنوز جایزه این هفته را منتشر نکرده؛ جایزه هفته قبل نمایش داده شده. کمی بعد دوباره امتحان کن.</i>",
        "weekly_week": "هفته {}",
        "weekly_caption": "🛠 جایزه این هفته: {}",
        "btn_finder": "🔎 جستجوی جایزه",
        "btn_top": "🔥 ماموریت‌های برتر",
        "top_title": "🔥 <b>ماموریت‌های برتر امروز</b>",
        "top_zone": "🔥 Top — {}",
        "top_none": "❌ امروز ماموریت برجسته‌ای نیست.",
        "top_caption": "🔥 بهترین ماموریت‌های هر زون امروز — {} ماموریت در {} زون",
        "finder_title": "🔎 <b>جستجوی جایزه — همه زون‌ها</b>",
        "finder_none": "❌ امروز در هیچ زونی ماموریتی با جوایز انتخابی تو نیست.",
        "finder_need": "🔎 اول در ⚙️ فیلترهای من حداقل یک جایزه انتخاب کن؛ بعد این بخش همه ماموریت‌های همه زون‌ها (استون‌وود تا توئین پیکس و ونچر) را می‌گردد.",
        "more_hidden": "➕ <i>{} مورد دیگر نمایش داده نشد. فیلترها را محدودتر کن.</i>",
        "daily_title": "🔔 <b>ریست روزانه فورتنایت</b>",
        "weekly_push": "🚨 <b>ریست هفتگی فورتنایت</b>",
        "alerts_label": "🎁 جوایز آلرت",
        "basic_label": "📦 جوایز پایه",
        "none": "ندارد",
        "full": "⚠️ ظرفیت ربات پر شده است. بعداً دوباره تلاش کن.",
        "filtered_out": "🔍 چیزی با فیلترهای تو مطابقت نداشت ({} مورد پنهان شد).",
        "filter_hint": "🔍 <i>فیلترها فعال هستند.</i>",
        "filters_title": (
            "⚙️ <b>فیلترهای من</b>\n\n"
            "این فیلترها فقط برای 🔎 جستجوی جایزه استفاده می‌شوند.\n"
            "ویباکس، پاور ۱۶۰، ونچر و اعلان‌های روزانه همیشه همه چیز را نشان می‌دهند."
        ),
        "filters_zones": "— زون‌ها —",
        "filters_rewards": "— جوایز —",
        "filters_reset": "♻️ بازنشانی",
        "filters_close": "✅ تمام",
        "filters_saved": "⚙️ فیلترها ذخیره شد.",
        "help": (
            "<b>دستورها</b>\n"
            "/start — باز کردن منو\n"
            "/menu — نمایش دوباره کیبورد\n"
            "/filters — تنظیم فیلتر زون و جایزه\n"
            "/alerts — روشن/خاموش کردن اعلان‌ها\n"
            "/help — همین پیام"
        ),
        "admin_panel": "👑 <b>پنل مدیریت</b>",
        "admin_stat": (
            "📊 <b>آمار</b>\n\n"
            "کاربران: <code>{}</code>\n"
            "مشترک اعلان: <code>{}</code>\n"
            "مسدود: <code>{}</code>\n"
            "دارای فیلتر: <code>{}</code>"
        ),
        "admin_new": "👤 <b>کاربر جدید</b>\n\nنام: {}\nیوزرنیم: {}\nآیدی: <code>{}</code>",
        "admin_bc_usage": "طرز استفاده: <code>/broadcast متن پیام</code>",
        "admin_bc_prompt": (
            "📢 <b>پیام همگانی</b>\n\n"
            "متن پیام را همین حالا بفرست؛ قبل از ارسال "
            "پیش‌نمایش نشان می‌دهم.\n"
            "برای لغو /cancel بزن."
        ),
        "admin_bc_none": "⚠️ هیچ کاربری مشترک اعلان نیست؛ کسی برای ارسال وجود ندارد.",
        "admin_bc_long": "❌ پیام خیلی بلند است (حداکثر {} کاراکتر).",
        "admin_bc_confirm": "📢 این پیام برای <b>{}</b> کاربر ارسال شود؟\n\n──────\n{}",
        "admin_bc_sent": "✅ ارسال تمام شد. موفق: <code>{}</code> — ناموفق: <code>{}</code>",
        "admin_bc_cancel": "🚫 ارسال لغو شد.",
        "admin_bc_expired": "⚠️ پیامی در انتظار نیست.",
        "admin_ban_usage": "طرز استفاده: <code>/ban 123456789</code>",
        "admin_unban_usage": "طرز استفاده: <code>/unban 123456789</code>",
        "admin_bad_id": "❌ آیدی عددی معتبر نیست.",
        "admin_ban_self": "❌ نمی‌توانی خودت را مسدود کنی.",
        "admin_ban_ok": "🚫 کاربر <code>{}</code> مسدود شد.",
        "admin_unban_ok": "✅ کاربر <code>{}</code> آزاد شد.",
        "admin_unknown": "❌ کاربر <code>{}</code> پیدا نشد.",
        "admin_banned_list": "🚫 <b>کاربران مسدود</b>\n\n{}",
        "admin_banned_empty": "✅ کاربر مسدودی وجود ندارد.",
        "admin_export": "📤 خروجی کاربران ({} ردیف).",
        "admin_import_help": (
            "📥 <b>بازگرداندن کاربران</b>\n\n"
            "فایل <code>users-*.csv</code> که از خروجی گرفتی یا یک "
            "<code>users.json</code> را برایم بفرست.\n"
            "کاربران موجود به‌روز و جدیدها اضافه می‌شوند. "
            "هیچ کاربری حذف نمی‌شود."
        ),
        "admin_import_ok": (
            "✅ <b>بازگردانی انجام شد</b>\n\n"
            "افزوده: <code>{}</code>\nبه‌روز: <code>{}</code>\n"
            "رد شده (سقف ظرفیت): <code>{}</code>"
        ),
        "admin_import_bad": "❌ فایل خوانده نشد. فایل CSV خروجی یا users.json لازم است.",
        "admin_import_empty": "⚠️ هیچ ردیف معتبری در فایل پیدا نشد.",
        "admin_import_big": "❌ فایل خیلی بزرگ است (حداکثر {} کیلوبایت).",
        "adm_import": "📥 بازگرداندن",
        "adm_update": "⬆️ به‌روزرسانی",
        "upd_checking": "⏳ در حال بررسی نسخه جدید…",
        "upd_none": "✅ <b>به‌روز است</b>\n\nنسخه <code>{}</code>. نسخه منتشرشده با چیزی که اجرا می‌شود یکی است.",
        "upd_found": "⬆️ <b>به‌روزرسانی موجود است</b>\n\nنصب‌شده: <code>{}</code>\nمنتشرشده: <code>{}</code>\n{}\n\nبا به‌روزرسانی ربات ری‌استارت می‌شود. تنظیمات و کاربران حفظ می‌شوند.",
        "upd_code_changed": "کد تغییر کرده است، هرچند شماره نسخه یکی است.",
        "upd_version_changed": "نسخه جدیدتری منتشر شده است.",
        "upd_failed": "❌ بررسی به‌روزرسانی ناموفق بود: <code>{}</code>",
        "upd_no_url": "⚠️ آدرس به‌روزرسانی تنظیم نشده. <code>UPDATE_URL</code> را در تنظیمات بگذار.",
        "upd_started": "⬆️ به‌روزرسانی شروع شد. ربات تا لحظاتی دیگر ری‌استارت می‌شود و نتیجه را همینجا می‌گوید.",
        "upd_queued_already": "⏳ یک به‌روزرسانی از قبل در صف است.",
        "upd_report_ok": "✅ <b>به‌روزرسانی تمام شد</b>\n\nالان روی <code>{}</code> (قبلاً <code>{}</code>).",
        "upd_report_fail": "❌ <b>به‌روزرسانی ناموفق بود</b>\n\nهنوز روی <code>{}</code>.\n<code>{}</code>",
        "admin_refreshed": "♻️ کش پاک شد.",
        "btn_admin": "👑 Admin",
        "adm_stats": "📊 آمار",
        "adm_export": "📤 خروجی",
        "adm_banned": "🚫 مسدودها",
        "adm_refresh": "♻️ رفرش",
        "adm_bc_help": "📢 پیام همگانی",
        "adm_weekly": "🛠 جایزه هفتگی",
        "wk_admin": ("🛠 <b>جایزه هفتگی — هفته {}</b>\n\n"
                     "نمایش فعلی: <b>{}</b> ({})\n{}\n\n"
                     "اگر داخل بازی چیز دیگری است، گزینه درست را انتخاب کن:"),
        "wk_sources": "منابع: {}",
        "wk_conflict": "⚠️ <b>منابع با هم اختلاف دارند.</b>",
        "wk_auto": "🔄 خودکار (منابع)",
        "wk_send": "📢 ارسال برای کاربران",
        "wk_set_ok": "✅ جایزه هفتگی روی {} تنظیم شد.",
        "wk_auto_ok": "🔄 برگشت به منابع خودکار.",
        "wk_sent": "📢 جایزه هفتگی ارسال شد: {} موفق، {} ناموفق.",
        "yes": "✅ ارسال",
        "no": "🚫 لغو",
        "progress": "📊 پیشرفت",
        "remaining": "⏳ باقی‌مانده",
        "ends": "🗓 پایان",
        "next": "🚀 بعدی",
        "days": "روز",
    },
}


def t(lang: str, key: str) -> str:
    return TEXTS.get(lang, TEXTS["en"]).get(key, TEXTS["en"].get(key, key))


# ==========================================================================
# Storage — atomic writes, schema migration, 0600 permissions
# ==========================================================================
class UserStore:
    def __init__(self, path: Path, max_users: int) -> None:
        self.path = path
        self.max_users = max_users
        self._users: dict[str, dict[str, Any]] = {}
        self._lock = asyncio.Lock()

    # ---- disk ------------------------------------------------------------
    @staticmethod
    def _sanitise(raw: Any) -> dict[str, Any]:
        record = dict(DEFAULT_PREFS)
        if isinstance(raw, str):                       # legacy v1: {id: "fa"}
            record["lang"] = raw if raw in TEXTS else DEFAULT_LANG
            return record
        if not isinstance(raw, dict):
            return record
        lang = raw.get("lang")
        record["lang"] = lang if lang in TEXTS else DEFAULT_LANG
        record["notify"] = bool(raw.get("notify", True))
        record["banned"] = bool(raw.get("banned", False))
        zones = raw.get("zones")
        record["zones"] = [z for z in zones if z in ZONES] if isinstance(zones, list) else []
        rewards = raw.get("rewards")
        record["rewards"] = (
            [r for r in rewards if r in REWARD_NAMES] if isinstance(rewards, list) else []
        )
        record["image_mode"] = bool(raw.get("image_mode", False))
        return record

    def load(self) -> None:
        try:
            raw = json.loads(self.path.read_text("utf-8"))
        except FileNotFoundError:
            raw = {}
        except (OSError, json.JSONDecodeError):
            log.exception("users file unreadable — keeping a .bad backup")
            try:
                self.path.rename(self.path.with_suffix(".bad"))
            except OSError:
                pass
            raw = {}

        users: dict[str, dict[str, Any]] = {}
        if isinstance(raw, list):                       # legacy v0: [id, id]
            users = {str(u): dict(DEFAULT_PREFS) for u in raw}
        elif isinstance(raw, dict):
            body = raw.get("users") if isinstance(raw.get("users"), dict) else raw
            for key, value in (body or {}).items():
                users[str(key)] = self._sanitise(value)
        self._users = users
        log.info("loaded %d users", len(users))

    def _write(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=str(self.path.parent), prefix=".users-",
                                   suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump({"version": 3, "users": self._users}, fh,
                          ensure_ascii=False)
                fh.flush()
                os.fsync(fh.fileno())
            os.chmod(tmp, 0o600)
            os.replace(tmp, self.path)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

    async def _flush(self) -> None:
        try:
            await asyncio.to_thread(self._write)
        except Exception:
            log.exception("could not persist users file")

    # ---- api -------------------------------------------------------------
    def record(self, chat_id: Any) -> dict[str, Any]:
        found = self._users.get(str(chat_id))
        return dict(found) if found else dict(DEFAULT_PREFS)

    def exists(self, chat_id: Any) -> bool:
        return str(chat_id) in self._users

    def lang(self, chat_id: Any) -> str:
        found = self._users.get(str(chat_id))
        return found["lang"] if found else DEFAULT_LANG

    def notify_enabled(self, chat_id: Any) -> bool:
        found = self._users.get(str(chat_id))
        return bool(found["notify"]) if found else True

    def is_banned(self, chat_id: Any) -> bool:
        found = self._users.get(str(chat_id))
        return bool(found and found.get("banned"))

    def count(self) -> int:
        return len(self._users)

    def subscribed(self) -> int:
        return sum(1 for r in self._users.values()
                   if r["notify"] and not r.get("banned"))

    def banned_ids(self) -> list[str]:
        return [k for k, r in self._users.items() if r.get("banned")]

    def with_filters(self) -> int:
        return sum(1 for r in self._users.values() if filters_active(r))

    def items(self) -> list[tuple[str, dict[str, Any]]]:
        return [(k, dict(v)) for k, v in self._users.items()]

    async def upsert(self, chat_id: Any, **fields: Any) -> tuple[bool, bool]:
        """Create and/or patch a record. Returns (created, rejected_because_full)."""
        key = str(chat_id)
        unknown = set(fields) - EDITABLE
        if unknown:
            raise ValueError(f"unknown fields: {unknown}")
        async with self._lock:
            record = self._users.get(key)
            created = record is None
            changed = created
            if created:
                if key != ADMIN_ID and len(self._users) >= self.max_users:
                    return False, True
                record = dict(DEFAULT_PREFS)
                self._users[key] = record
            for name, value in fields.items():
                if value is not None and record.get(name) != value:
                    record[name] = value
                    changed = True
            if changed:
                await self._flush()
            return created, False

    async def merge(self, incoming: dict[str, dict]) -> tuple[int, int, int]:
        """Import records. Existing rows are updated, none are deleted."""
        added = updated = skipped = 0
        async with self._lock:
            for key, record in incoming.items():
                if key in self._users:
                    self._users[key] = record
                    updated += 1
                elif len(self._users) >= self.max_users:
                    skipped += 1
                else:
                    self._users[key] = record
                    added += 1
            if added or updated:
                await self._flush()
        return added, updated, skipped

    async def remove(self, chat_id: Any) -> None:
        async with self._lock:
            if self._users.pop(str(chat_id), None) is not None:
                await self._flush()


store = UserStore(USERS_FILE, MAX_USERS)


def is_admin(chat_id: Any) -> bool:
    return bool(ADMIN_ID) and str(chat_id) == ADMIN_ID


# ==========================================================================
# Keyboards
# ==========================================================================
def main_keyboard(lang: str, chat_id: Any) -> ReplyKeyboardMarkup:
    notify = store.notify_enabled(chat_id)
    image = bool(store.record(chat_id).get("image_mode"))
    rows = [
        [KeyboardButton(t(lang, "btn_vbucks")), KeyboardButton(t(lang, "btn_160"))],
        [KeyboardButton(t(lang, "btn_v140")), KeyboardButton(t(lang, "btn_weekly"))],
        [KeyboardButton(t(lang, "btn_top")), KeyboardButton(t(lang, "btn_finder"))],
        [KeyboardButton(t(lang, "btn_filters")), KeyboardButton(t(lang, "btn_timer"))],
        [KeyboardButton(t(lang, "btn_notify_on" if notify else "btn_notify_off")),
         KeyboardButton(t(lang, "btn_image_on" if image else "btn_image_off"))],
        [KeyboardButton(t(lang, "btn_lang"))],
    ]
    if is_admin(chat_id):
        rows.append([KeyboardButton(t(lang, "btn_admin"))])
    return ReplyKeyboardMarkup(rows, resize_keyboard=True)


def timer_keyboard(lang: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[
        InlineKeyboardButton(t(lang, "timer_bp"), callback_data="timer_bp"),
        InlineKeyboardButton(t(lang, "timer_venture"), callback_data="timer_venture"),
    ]])


def lang_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[
        InlineKeyboardButton("🇬🇧 English", callback_data="setlang_en"),
        InlineKeyboardButton("🇮🇷 فارسی", callback_data="setlang_fa"),
    ]])


def filters_keyboard(lang: str, prefs: dict) -> InlineKeyboardMarkup:
    zones = prefs.get("zones") or []
    rewards = prefs.get("rewards") or []
    rows: list[list[InlineKeyboardButton]] = [
        [InlineKeyboardButton(t(lang, "filters_zones"), callback_data="flt:noop")]
    ]
    row: list[InlineKeyboardButton] = []
    for index, zone in enumerate(ZONES):
        mark = "✅" if zone in zones else "⬜"
        row.append(InlineKeyboardButton(f"{mark} {zone}", callback_data=f"flt:z:{index}"))
        if len(row) == 2:
            rows.append(row)
            row = []
    if row:
        rows.append(row)

    rows.append([InlineKeyboardButton(t(lang, "filters_rewards"),
                                      callback_data="flt:noop")])
    row = []
    for index, name in enumerate(REWARD_NAMES):
        mark = "✅" if name in rewards else "⬜"
        row.append(InlineKeyboardButton(f"{mark} {name}", callback_data=f"flt:r:{index}"))
        if len(row) == 2:
            rows.append(row)
            row = []
    if row:
        rows.append(row)

    rows.append([
        InlineKeyboardButton(t(lang, "filters_reset"), callback_data="flt:reset"),
        InlineKeyboardButton(t(lang, "filters_close"), callback_data="flt:close"),
    ])
    return InlineKeyboardMarkup(rows)


def admin_keyboard(lang: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton(t(lang, "adm_stats"), callback_data="adm:stats"),
         InlineKeyboardButton(t(lang, "adm_export"), callback_data="adm:export")],
        [InlineKeyboardButton(t(lang, "adm_import"), callback_data="adm:import"),
         InlineKeyboardButton(t(lang, "adm_banned"), callback_data="adm:banned")],
        [InlineKeyboardButton(t(lang, "adm_refresh"), callback_data="adm:refresh"),
         InlineKeyboardButton(t(lang, "adm_update"), callback_data="adm:update")],
        [InlineKeyboardButton(t(lang, "adm_bc_help"), callback_data="adm:bchelp"),
         InlineKeyboardButton(t(lang, "adm_weekly"), callback_data="wk:show")],
    ])


WEEKLY_KEYS = ("weapon", "hero", "survivor", "trap", "defender", "core")
LEGACY_WEEKLY_KEYS = {"schematic": "weapon", "perk": "core"}


def weekly_keyboard(lang: str, current_key: str = "") -> InlineKeyboardMarkup:
    rows, row = [], []
    for key in WEEKLY_KEYS:
        mark = "✅ " if key == current_key else ""
        row.append(InlineKeyboardButton(f"{mark}{src.WEEKLY_LABELS[key]}",
                                        callback_data=f"wk:set:{key}"))
        if len(row) == 2:
            rows.append(row)
            row = []
    rows.append([InlineKeyboardButton(t(lang, "wk_auto"), callback_data="wk:auto"),
                 InlineKeyboardButton(t(lang, "wk_send"), callback_data="wk:send")])
    return InlineKeyboardMarkup(rows)


def weekly_admin_text(lang: str, reward: Any) -> str:
    label, key, _ = weekly_parts(reward)
    week = reward.get("week", "?") if isinstance(reward, dict) else "?"
    source = reward.get("source", "?") if isinstance(reward, dict) else "?"
    sources = reward.get("sources") if isinstance(reward, dict) else None
    extra = []
    if sources:
        extra.append(t(lang, "wk_sources").format(
            E(", ".join(f"{k}: {v}" for k, v in sources.items()))))
    if isinstance(reward, dict) and reward.get("conflict"):
        extra.append(t(lang, "wk_conflict"))
    return t(lang, "wk_admin").format(E(week), E(label or "?"), E(source),
                                      "\n".join(extra))


def confirm_keyboard(lang: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[
        InlineKeyboardButton(t(lang, "yes"), callback_data="adm:bcsend"),
        InlineKeyboardButton(t(lang, "no"), callback_data="adm:bccancel"),
    ]])


def _button_set(key: str) -> set[str]:
    return {TEXTS[lang][key] for lang in TEXTS}


BTN_VBUCKS = _button_set("btn_vbucks")
BTN_160 = _button_set("btn_160")
BTN_V140 = _button_set("btn_v140")
BTN_WEEKLY = _button_set("btn_weekly")
BTN_TIMER = _button_set("btn_timer")
BTN_LANG = _button_set("btn_lang")
BTN_FILTERS = _button_set("btn_filters")
BTN_FINDER = _button_set("btn_finder")
BTN_TOP = _button_set("btn_top")
BTN_ADMIN = _button_set("btn_admin")
BTN_NOTIFY = _button_set("btn_notify_on") | _button_set("btn_notify_off")
BTN_IMAGE = _button_set("btn_image_on") | _button_set("btn_image_off")
ALL_BUTTONS = (BTN_VBUCKS | BTN_160 | BTN_V140 | BTN_WEEKLY | BTN_TIMER
               | BTN_LANG | BTN_FILTERS | BTN_ADMIN | BTN_NOTIFY | BTN_IMAGE
               | BTN_FINDER | BTN_TOP)


# ==========================================================================
# Formatting (HTML — every dynamic value is escaped)
# ==========================================================================
SEP = "───────────────────"


def mission_icon(name: str) -> str:
    upper = name.upper()
    if "RIDE THE LIGHTNING" in upper:
        return "🚚"
    if "CATEGORY" in upper or "STORM SHIELD" in upper:
        return "🌀"
    if "RETRIEVE" in upper or "RETRIVE" in upper:
        return "🎈"
    if "FIGHT THE STORM" in upper:
        return "⛈️"
    if "RADAR" in upper:
        return "📡"
    if "EVACUATE" in upper:
        return "🏠"
    if "REPAIR" in upper:
        return "🛠️"
    if "DELIVER" in upper or "BOMB" in upper or "DTB" in upper:
        return "💣"
    if "ENCAMPMENT" in upper:
        return "⛺"
    if "RESCUE" in upper:
        return "🆘"
    return "🎯"


REWARD_EMOJI = {
    "vbucks": "💎", "reperk": "🔄", "ampup": "⚡", "fireup": "🔥", "frostup": "❄️",
    "perkup": "⏫", "lightning_bottle": "🧪", "eye_storm": "👁", "storm_shard": "💠",
    "pure_drop": "💧", "flux": "🔷", "manual": "📘", "designs": "📐",
    "venture_xp": "⭐", "survivor_xp": "⭐", "schematic_xp": "⭐", "hero_xp": "⭐",
    "xp": "⭐", "candy": "🍬", "gold": "🪙", "ticket": "🎟", "lead": "🎖",
    "survivor": "👤", "defender": "🛡", "hero": "🦸", "trap": "🧩",
    "schematic": "📜",
}


def reward_emoji(reward: dict) -> str:
    names = vimg.reward_kind(f"{reward.get('raw', '')} | {reward.get('item', '')}")[0]
    return REWARD_EMOJI.get(names[0], "▪️") if names else "▪️"


MISSION_SEP = "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"


def _reward_lines(mission: dict, lang: str) -> list[str]:
    """Alert rewards one per line, basic rewards collapsed onto one."""
    lines = []
    for r in mission.get("alert") or []:
        lines.append(f"   {reward_emoji(r)} {E(r['item'])} <code>x{r['qty']:,}</code>")
    basic = mission.get("basic") or []
    if basic:
        joined = " \u00b7 ".join(
            E(r["item"]) + (f" x{r['qty']:,}" if int(r.get("qty") or 1) > 1 else "")
            for r in basic[:6])
        lines.append(f"   \U0001f4e6 <i>{joined}</i>")
    if not lines:
        lines.append(f"   \u2014 {E(t(lang, 'none'))}")
    return lines


def _empty_note(lang: str, hidden: int) -> str:
    return t(lang, "filtered_out").format(hidden) if hidden else ""


def format_missions(missions: list[dict], lang: str, prefs: dict | None = None,
                    *, title_key: str = "p160_title",
                    none_key: str = "p160_none") -> str:
    """Compact layout: power and name first, then place, then rewards."""
    prefs = prefs or DEFAULT_PREFS
    total = len(missions)
    shown = cached_filter(missions, prefs, title_key)
    parts = [t(lang, title_key)]
    if filters_active(prefs):
        parts.append(t(lang, "filter_hint"))
    parts.append("")
    if not shown:
        parts.append(_empty_note(lang, total - len(shown)) or t(lang, none_key))
        return "\n".join(parts)
    cap = max(1, src.MAX_ITEMS)
    extra = len(shown) - cap
    for i, m in enumerate(shown[:cap]):
        if i:
            parts.append(MISSION_SEP)
        place = E(m["zone"])
        if m["biome"]:
            place += f" \u00b7 {E(m['biome'])}"
        block = [
            f"{mission_icon(m['name'])} <b>{m['power']}</b>  <code>{E(m['name'])}</code>",
            f"\U0001f30d <i>{place}</i>",
        ]
        block.extend(_reward_lines(m, lang))
        parts.append("\n".join(block))
    if extra > 0:
        parts.append("")
        parts.append(t(lang, "more_hidden").format(extra))
    return "\n".join(parts).rstrip()


def format_vbucks(missions: list[dict], lang: str, prefs: dict | None = None) -> str:
    return format_missions(missions, lang, prefs, title_key="vbucks_title",
                           none_key="vbucks_none")


def format_power(missions: list[dict], lang: str, power: int = 160,
                 prefs: dict | None = None) -> str:
    return format_missions(missions, lang, prefs)


def format_venture(missions: list[dict], lang: str,
                   prefs: dict | None = None) -> str:
    return format_missions(missions, lang, prefs, title_key="v140_title",
                           none_key="v140_none")


WEEKLY_ICONS = (("HERO", "🦸"), ("WEAPON", "⚔️"), ("TRAP", "🧩"),
                ("SURVIVOR", "👥"), ("DEFENDER", "🛡️"), ("PERK", "🛠️"), ("CORE", "🛠️"))


def weekly_parts(reward: Any) -> tuple[str, str, bool]:
    """(label, image key, is_current_week) from new dicts or old plain strings."""
    if isinstance(reward, dict):
        label = str(reward.get("label") or reward.get("name") or "")
        key = str(reward.get("key") or "")
        key = LEGACY_WEEKLY_KEYS.get(key, key)
        return label, key, src.weekly_is_current(reward)
    return str(reward or ""), "", bool(reward)


def format_weekly(reward: Any, lang: str) -> str:
    label, _, current = weekly_parts(reward)
    if not label:
        return f"{t(lang, 'weekly_title')}\n\n{t(lang, 'weekly_none')}"
    upper = label.upper()
    icon = next((sym for needle, sym in WEEKLY_ICONS if needle in upper), "🚀")
    lines = [t(lang, "weekly_title"), "", f"{icon} <b>{E(label)}</b>"]
    if isinstance(reward, dict) and reward.get("week"):
        lines.append(f"🗓 <i>{E(t(lang, 'weekly_week').format(reward['week']))}</i>")
    if not current:
        lines += ["", t(lang, "weekly_stale")]
    return "\n".join(lines)


def render_weekly_card(reward: Any, title: str) -> bytes | None:
    label, key, _ = weekly_parts(reward)
    if not label:
        return None
    week = reward.get("week", "") if isinstance(reward, dict) else ""
    return vimg.render_weekly(label, key=key, title=title,
                              footer=f"Week of {week}" if week else None)


async def send_weekly(update: Update, lang: str, prefs: dict, reward: Any) -> None:
    """Weekly reward as a picture in image mode, text otherwise."""
    text = format_weekly(reward, lang)
    label, _, current = weekly_parts(reward)
    if not label or not prefs.get("image_mode") or not vimg.available():
        await reply(update, text)
        return
    png = await asyncio.to_thread(render_weekly_card, reward, "This Week's Reward")
    if not png:
        await reply(update, text)
        return
    caption = t(lang, "weekly_caption").format(E(label))
    if not current:
        caption += "\n\n" + t(lang, "weekly_stale")
    try:
        await update.effective_message.reply_photo(
            photo=InputFile(io.BytesIO(png), filename="weekly.png"), caption=caption)
    except TelegramError:
        log.exception("weekly photo failed; falling back to text")
        await reply(update, text)


def progress_bar(percent: float, length: int = 10) -> str:
    filled = max(0, min(length, round(length * percent / 100)))
    return "🟦" * filled + "⬛" * (length - filled)


# --------------------------------------------------------------------------
# Season maths
# --------------------------------------------------------------------------
VENTURE_CYCLES = [
    {"name": "Mild Meadows 🌸", "start": (1, 24), "end": (4, 5)},
    {"name": "Scurvy Shoals 🏴‍☠️", "start": (4, 5), "end": (6, 20)},
    {"name": "Blasted Badlands 🏜", "start": (6, 20), "end": (9, 3)},
    {"name": "Hexsylvania 🎃", "start": (9, 3), "end": (11, 20)},
    {"name": "Frostnite ❄️", "start": (11, 20), "end": (1, 24)},
]


def venture_window(now: datetime | None = None):
    now = now or datetime.now(timezone.utc)
    for year_offset in (-1, 0):
        for index, cycle in enumerate(VENTURE_CYCLES):
            sm, sd = cycle["start"]
            em, ed = cycle["end"]
            try:
                start = datetime(now.year + year_offset, sm, sd, tzinfo=timezone.utc)
                wraps = (em, ed) <= (sm, sd)
                end = datetime(start.year + (1 if wraps else 0), em, ed,
                               tzinfo=timezone.utc)
            except ValueError:
                continue
            if start <= now < end:
                nxt = VENTURE_CYCLES[(index + 1) % len(VENTURE_CYCLES)]["name"]
                return cycle["name"], start, end, nxt
    return None


def battlepass_window():
    """Season end from fortnite.gg, falling back to the configured date.

    The live lookup is best-effort: if the site is unreachable or its
    wording changed, SEASON_END_UTC from the config is used instead.
    """
    start = _parse_dt(SEASON_START_UTC)
    end = None
    try:
        end = src.fetch_season_end()
    except Exception:
        log.warning("season lookup failed; using the configured end date",
                    exc_info=True)
    if end is None:
        end = _parse_dt(SEASON_END_UTC)
    return start, end


def format_countdown(kind: str, lang: str) -> str:
    now = datetime.now(timezone.utc)

    if kind == "timer_bp":
        label = "Battle Pass" if lang == "en" else "بتل‌پس"
        name = "Current Season" if lang == "en" else "سیزن جاری"
        start, end = battlepass_window()
        nxt = "TBA"
    else:
        label = "Ventures" if lang == "en" else "ونچر"
        window = venture_window(now)
        if not window:
            return t(lang, "error")
        name, start, end, nxt = window

    if end is None:
        return t(lang, "error")
    remaining = end - now
    if remaining.total_seconds() <= 0:
        return t(lang, "season_ended").format(E(label))

    lines = [f"🌐 <b>Fortnite {E(label)}</b> — {E(name)}", ""]
    if start and end > start:
        percent = max(0.0, min(100.0,
                               (now - start).total_seconds()
                               / (end - start).total_seconds() * 100))
        lines += [f"{t(lang, 'progress')}: <b>{percent:.1f}%</b>",
                  progress_bar(percent), ""]

    days = remaining.days
    hours, rest = divmod(remaining.seconds, 3600)
    minutes, seconds = divmod(rest, 60)
    lines += [
        f"{t(lang, 'remaining')}: <b>{days}</b> {t(lang, 'days')}",
        f"⏱ <code>{days:02d} : {hours:02d} : {minutes:02d} : {seconds:02d}</code>",
        "",
        f"{t(lang, 'ends')}: {end.strftime('%Y-%m-%d %H:%M')} UTC",
        f"{t(lang, 'next')}: {E(str(nxt))}",
    ]
    return "\n".join(lines)


# ==========================================================================
# Telegram send helpers
# ==========================================================================
TELEGRAM_LIMIT = 4000


def chunks(text: str, limit: int = TELEGRAM_LIMIT) -> Iterable[str]:
    """Split on line boundaries so HTML tags are never cut in half."""
    if len(text) <= limit:
        yield text
        return
    buffer = ""
    for block in text.split("\n"):
        if len(buffer) + len(block) + 1 > limit and buffer:
            yield buffer
            buffer = ""
        buffer += block + "\n"
    if buffer.strip():
        yield buffer


def image_rewards(mission: dict, kind: str) -> list[dict]:
    """Alert rewards as chips (V-Bucks first), basic rewards as small icons."""
    rows: list[dict] = []
    for reward in mission.get("alert") or []:
        rows.append({
            "item": reward["item"], "raw": reward.get("raw", ""),
            "qty": reward["qty"],
            "key": "vbucks" if src.VBUCKS_RE.search(reward["raw"]) else "",
        })
    rows.sort(key=lambda r: r["key"] != "vbucks")
    for reward in mission.get("basic") or []:
        rows.append({"item": reward["item"], "raw": reward.get("raw", ""),
                     "qty": reward["qty"], "key": "", "basic": True})
    return rows


def _page_label(missions: list[dict], n: int, total: int) -> str:
    """"Twine Peaks 3/4" — the zone(s) on a page plus its position."""
    zones: list[str] = []
    for m in missions:
        z = zone_key(m.get("zone", ""))
        z = m.get("zone", z) if z == "Other" else z
        if z not in zones:
            zones.append(z)
    label = " · ".join(zones)
    return f"{label} {n}/{total}" if total > 1 else label


def render_pages(missions: list[dict], lang: str, kind: str, title: str,
                 label: str | None = None) -> list[tuple[bytes, str]]:
    """[(png, caption)] — one entry per picture, caption names zone + page."""
    payloads = [{
        "zone": m["zone"], "name": m["name"], "power": m["power"],
        "biome": m["biome"], "rewards": image_rewards(m, kind),
    } for m in missions]
    chunks = vimg.split_pages(payloads)   # landscape pages, split by height
    out = []
    for n, payload in enumerate(chunks, 1):
        page_title = f"{title}  ({n}/{len(chunks)})" if len(chunks) > 1 else title
        png = vimg.render(payload, title=page_title, kind=kind)
        if not png:
            return []
        cap = f"{label} {n}/{len(chunks)}" if (label and len(chunks) > 1) else \
            (label or _page_label(payload, n, len(chunks)))
        out.append((png, cap))
    return out


def render_card(missions: list[dict], lang: str, kind: str, title: str) -> bytes | None:
    payload = [{
        "zone": m["zone"],
        "name": m["name"],
        "power": m["power"],
        "biome": m["biome"],
        "rewards": image_rewards(m, kind),
    } for m in missions]
    return vimg.render(payload, title=title, kind=kind)


async def reply(update: Update, text: str, **kwargs) -> None:
    message = update.effective_message
    if message is None:
        return
    for part in chunks(text):
        try:
            await message.reply_text(part, **kwargs)
        except TelegramError:
            log.exception("send failed")
            break
        kwargs.pop("reply_markup", None)


async def send_photo_cached(update: Update, key: tuple, source, build_pages,
                            caption: str, filename: str) -> bool:
    """Send one or more pictures, reusing the day's renders and file_ids.

    ``build_pages`` returns [(png, page caption)]; several pages go out as an
    album (max 10 each). Every picture carries its own caption, e.g.
    "Twine Peaks 3/4"; the first one also gets ``caption`` as a header.
    """
    entry = PHOTO_CACHE.get(key, source)
    message = update.effective_message
    pages = entry.get("pages") if entry else None
    if not pages:
        pages = await asyncio.to_thread(build_pages)
        if not pages:
            return False
    caps = [(f"{caption}\n{c}" if i == 0 else c) for i, (_, c) in enumerate(pages)]
    file_ids = entry.get("file_ids") if entry else None
    if file_ids:
        try:
            await _send_album(message, file_ids, caps)
            return True
        except TelegramError:
            log.debug("cached file_ids rejected; re-uploading", exc_info=True)
    uploads = [InputFile(io.BytesIO(p), filename=f"{n}-{filename}", attach=True)
               for n, (p, _) in enumerate(pages, 1)]
    try:
        file_ids = await _send_album(message, uploads, caps)
    except TelegramError:
        # An album can be refused as a whole; send the pages one by one.
        log.warning("album send failed; sending pages one by one", exc_info=True)
        file_ids = []
        try:
            for n, (p, _) in enumerate(pages):
                sent = await message.reply_photo(
                    photo=InputFile(io.BytesIO(p), filename=f"{n + 1}-{filename}"),
                    caption=caps[n])
                if sent is not None and getattr(sent, "photo", None):
                    file_ids.append(sent.photo[-1].file_id)
        except TelegramError:
            log.exception("photo send failed")
            return False
        if len(file_ids) != len(pages):
            file_ids = []
    PHOTO_CACHE.put(key, source, {"pages": pages, "file_ids": file_ids or None})
    return True


async def _send_album(message, photos: list, captions: list[str]) -> list[str]:
    """Send photos (InputFile or file_id); returns the file_ids Telegram gave."""
    ids: list[str] = []
    for start in range(0, len(photos), 10):
        group = photos[start:start + 10]
        caps = captions[start:start + 10]
        if len(group) == 1:
            sent = [await message.reply_photo(photo=group[0], caption=caps[0])]
        else:
            media = [InputMediaPhoto(media=p, caption=c) for p, c in zip(group, caps)]
            sent = await message.reply_media_group(media=media)
        for msg in sent or []:
            if msg is not None and getattr(msg, "photo", None):
                ids.append(msg.photo[-1].file_id)
    return ids if len(ids) == len(photos) else []


def format_top(groups: list[tuple[str, list[dict]]], lang: str) -> str:
    parts = [t(lang, "top_title"), ""]
    for zone, missions in groups:
        parts.append(f"━━━ <b>{E(zone)}</b> ━━━")
        body = format_missions(missions, lang, unfiltered(None), title_key="top_title",
                               none_key="top_none")
        parts.append(body.split("\n", 2)[2] if body.count("\n") >= 2 else body)
        parts.append("")
    return "\n".join(parts).rstrip()


async def send_top(update: Update, lang: str, prefs: dict, missions: list[dict]) -> None:
    """Notable missions, one picture per zone (text when images are off)."""
    tops = TOP_CACHE.get(("top",), missions)
    if tops is None:
        tops = top_missions(missions)
        TOP_CACHE.put(("top",), missions, tops)
    if not tops:
        await reply(update, t(lang, "top_none"))
        return
    groups = group_by_zone(tops)
    if not prefs.get("image_mode") or not vimg.available():
        await reply(update, format_top(groups, lang))
        return

    def build() -> list[tuple[bytes, str]]:
        pages: list[tuple[bytes, str]] = []
        for zone, group in groups:
            pages += render_pages(group, lang, "top", f"Top Missions — {zone}",
                                  label=f"🔥 {zone}")
        return pages

    ok = await send_photo_cached(
        update, ("top", lang), missions, build,
        t(lang, "top_caption").format(len(tops), len(groups)), "top.png")
    if not ok:
        await reply(update, format_top(groups, lang))


async def send_missions(update: Update, lang: str, prefs: dict,
                        missions: list[dict], *, kind: str, title_key: str,
                        none_key: str) -> None:
    """Send a mission list as a picture or as text, per the user's choice."""
    shown = cached_filter(missions, prefs, title_key)
    if not prefs.get("image_mode") or not shown or not vimg.available():
        await reply(update, format_missions(missions, lang, prefs, title_key=title_key,
                                            none_key=none_key))
        return

    title = re.sub(r"<[^>]+>", "", t(lang, title_key))
    key = ("img", lang) + filter_key(title_key, prefs)
    ok = await send_photo_cached(
        update, key, missions, lambda: render_pages(shown, lang, kind, title),
        t(lang, "image_caption").format(title, len(shown)), f"{kind}.png")
    if not ok:
        await reply(update, t(lang, "image_failed"))
        await reply(update, format_missions(missions, lang, prefs, title_key=title_key,
                                            none_key=none_key))


async def safe_fetch(update: Update, lang: str, fn, *args, **kwargs):
    await reply(update, t(lang, "fetching"))
    try:
        return await asyncio.to_thread(fn, *args, **kwargs)
    except Exception:
        log.exception("data source failed")
        await reply(update, t(lang, "error"))
        return None


# ==========================================================================
# Handlers — user
# ==========================================================================
async def send_vbucks(update, lang, prefs, missions) -> None:
    await send_missions(update, lang, unfiltered(prefs), missions, kind="vbucks",
                        title_key="vbucks_title", none_key="vbucks_none")


async def send_power(update, lang, prefs, missions) -> None:
    await send_missions(update, lang, unfiltered(prefs), missions, kind="power",
                        title_key="p160_title", none_key="p160_none")


async def send_venture(update, lang, prefs, missions) -> None:
    await send_missions(update, lang, unfiltered(prefs), missions, kind="venture",
                        title_key="v140_title", none_key="v140_none")


async def notify_admin_new_user(context: ContextTypes.DEFAULT_TYPE,
                                update: Update) -> None:
    if not ADMIN_ID:
        return
    user = update.effective_user
    chat_id = update.effective_chat.id
    if user is None or is_admin(chat_id):
        return
    lang = store.lang(ADMIN_ID)
    username = f"@{user.username}" if user.username else t(lang, "no_username")
    try:
        await context.bot.send_message(
            chat_id=int(ADMIN_ID),
            text=t(lang, "admin_new").format(
                E(user.first_name or "?"), E(username), user.id),
        )
    except TelegramError:
        log.debug("admin notification failed", exc_info=True)


async def _register(update: Update, context: ContextTypes.DEFAULT_TYPE) -> str | None:
    """Create/refresh the record. Returns the language, or None if blocked."""
    chat_id = update.effective_chat.id
    if store.is_banned(chat_id):
        return None
    created, full = await store.upsert(chat_id)
    lang = store.lang(chat_id)
    if full:
        await reply(update, t(lang, "full"))
        return None
    if created:
        await notify_admin_new_user(context, update)
    return lang


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    lang = await _register(update, context)
    if lang is None:
        return
    await reply(update, t(lang, "welcome"),
                reply_markup=main_keyboard(lang, update.effective_chat.id))


async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id
    if store.is_banned(chat_id):
        return
    await reply(update, t(store.lang(chat_id), "help"))


async def menu_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    lang = await _register(update, context)
    if lang is None:
        return
    await reply(update, t(lang, "welcome"),
                reply_markup=main_keyboard(lang, update.effective_chat.id))


async def toggle_alerts(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id
    if store.is_banned(chat_id):
        return
    new_state = not store.notify_enabled(chat_id)
    _, full = await store.upsert(chat_id, notify=new_state)
    lang = store.lang(chat_id)
    if full:
        await reply(update, t(lang, "full"))
        return
    await reply(update, t(lang, "notify_on" if new_state else "notify_off"),
                reply_markup=main_keyboard(lang, chat_id))


async def toggle_image(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id
    if store.is_banned(chat_id):
        return
    new_state = not store.record(chat_id).get("image_mode")
    _, full = await store.upsert(chat_id, image_mode=new_state)
    lang = store.lang(chat_id)
    if full:
        await reply(update, t(lang, "full"))
        return
    await reply(update, t(lang, "image_on" if new_state else "image_off"),
                reply_markup=main_keyboard(lang, chat_id))


async def filters_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    lang = await _register(update, context)
    if lang is None:
        return
    prefs = store.record(update.effective_chat.id)
    await reply(update, t(lang, "filters_title"),
                reply_markup=filters_keyboard(lang, prefs))


async def venture_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    lang = await _register(update, context)
    if lang is None:
        return
    prefs = store.record(update.effective_chat.id)
    data = await safe_fetch(update, lang, src.fetch_venture_missions, 140)
    if data is not None:
        await reply(update, format_venture(data, lang, prefs))


async def on_text(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    chat_id = update.effective_chat.id
    text = (update.effective_message.text or "").strip()

    lang = await _register(update, context)
    if lang is None:
        return
    prefs = store.record(chat_id)

    # The admin pressed "Broadcast" and is now typing the message.
    if is_admin(chat_id) and context.user_data.get("awaiting_broadcast"):
        if text and text not in ALL_BUTTONS:
            context.user_data.pop("awaiting_broadcast", None)
            await prepare_broadcast(update, context, text)
            return
        context.user_data.pop("awaiting_broadcast", None)

    if text in BTN_ADMIN and is_admin(chat_id):
        await reply(update, t(lang, "admin_panel"),
                    reply_markup=admin_keyboard(lang))
    elif text in BTN_VBUCKS:
        data = await safe_fetch(update, lang, src.fetch_vbucks_missions)
        if data is not None:
            await send_vbucks(update, lang, prefs, data)
    elif text in BTN_160:
        data = await safe_fetch(update, lang, src.fetch_power_missions, 160)
        if data is not None:
            await send_power(update, lang, prefs, data)
    elif text in BTN_V140:
        data = await safe_fetch(update, lang, src.fetch_venture_missions, 140)
        if data is not None:
            await send_venture(update, lang, prefs, data)
    elif text in BTN_WEEKLY:
        data = await safe_fetch(update, lang, src.get_weekly)
        if data is not None:
            await send_weekly(update, lang, prefs, data)
    elif text in BTN_TOP:
        data = await safe_fetch(update, lang, src.fetch_all_missions)
        if data is not None:
            await send_top(update, lang, prefs, data)
    elif text in BTN_FINDER:
        if not prefs.get("rewards"):
            await reply(update, t(lang, "finder_need"),
                        reply_markup=filters_keyboard(lang, prefs))
            return
        data = await safe_fetch(update, lang, src.fetch_all_missions)
        if data is not None:
            await send_missions(update, lang, prefs, data, kind="finder",
                                title_key="finder_title", none_key="finder_none")
    elif text in BTN_TIMER:
        await reply(update, t(lang, "timer_prompt"),
                    reply_markup=timer_keyboard(lang))
    elif text in BTN_FILTERS:
        await reply(update, t(lang, "filters_title"),
                    reply_markup=filters_keyboard(lang, prefs))
    elif text in BTN_NOTIFY:
        await toggle_alerts(update, context)
    elif text in BTN_IMAGE:
        await toggle_image(update, context)
    elif text in BTN_LANG:
        await reply(update, "Select your language / زبان خود را انتخاب کنید:",
                    reply_markup=lang_keyboard())


# ==========================================================================
# Handlers — admin commands
# ==========================================================================
def _admin_lang() -> str:
    return store.lang(ADMIN_ID)


async def admin_stats(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_chat.id):
        return
    lang = _admin_lang()
    await reply(update, t(lang, "admin_stat").format(
        store.count(), store.subscribed(), len(store.banned_ids()),
        store.with_filters()))


async def admin_setweekly(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """/setweekly weapon|hero|survivor|trap|defender|core|auto"""
    if not is_admin(update.effective_chat.id):
        return
    alang = _admin_lang()
    arg = (context.args[0].lower() if context.args else "")
    if arg in WEEKLY_KEYS:
        await asyncio.to_thread(src.set_weekly_override, arg)
    elif arg == "auto":
        await asyncio.to_thread(src.set_weekly_override, None)
    try:
        reward = await asyncio.to_thread(src.get_weekly)
    except Exception:
        reward = None
    await reply(update, weekly_admin_text(alang, reward) if reward
                else t(alang, "weekly_none"),
                reply_markup=weekly_keyboard(alang, weekly_parts(reward)[1] if reward else ""))


async def admin_refresh(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_chat.id):
        return
    await asyncio.to_thread(src.clear_all_caches)
    await reply(update, t(_admin_lang(), "admin_refreshed"))


def _users_csv() -> tuple[bytes, int]:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(["chat_id", "lang", "notify", "banned",
                     "zones", "rewards", "image_mode"])
    rows = store.items()
    for chat_id, record in rows:
        writer.writerow([
            chat_id, record["lang"], int(record["notify"]),
            int(record.get("banned", False)),
            "|".join(record.get("zones") or []),
            "|".join(record.get("rewards") or []),
            int(record.get("image_mode", False)),
        ])
    return buffer.getvalue().encode("utf-8-sig"), len(rows)


async def admin_export(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_chat.id):
        return
    lang = _admin_lang()
    payload, rows = await asyncio.to_thread(_users_csv)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M")
    try:
        await context.bot.send_document(
            chat_id=int(ADMIN_ID),
            document=InputFile(io.BytesIO(payload), filename=f"users-{stamp}.csv"),
            caption=t(lang, "admin_export").format(rows),
        )
    except TelegramError:
        log.exception("export failed")


MAX_IMPORT_BYTES = 512 * 1024


def parse_import(payload: bytes) -> dict[str, dict]:
    """Accept the /export CSV or any users.json schema (v0..v3)."""
    text = payload.decode("utf-8-sig", errors="replace")
    stripped = text.lstrip()
    out: dict[str, dict] = {}

    if stripped[:1] in "[{":
        data = json.loads(stripped)
        if isinstance(data, list):
            for entry in data:
                if str(entry).isdigit():
                    out[str(entry)] = dict(DEFAULT_PREFS)
        elif isinstance(data, dict):
            body = data.get("users") if isinstance(data.get("users"), dict) else data
            for key, value in (body or {}).items():
                if str(key).isdigit():
                    out[str(key)] = UserStore._sanitise(value)
        return out

    reader = csv.DictReader(io.StringIO(text))
    truthy = {"1", "true", "yes", "on"}
    for row in reader:
        chat_id = (row.get("chat_id") or "").strip()
        if not chat_id.isdigit():
            continue
        notify_raw = (row.get("notify") or "1").strip().lower()
        banned_raw = (row.get("banned") or "0").strip().lower()
        out[chat_id] = UserStore._sanitise({
            "lang": (row.get("lang") or DEFAULT_LANG).strip(),
            "notify": notify_raw in truthy,
            "banned": banned_raw in truthy,
            "zones": [z for z in (row.get("zones") or "").split("|") if z],
            "rewards": [r for r in (row.get("rewards") or "").split("|") if r],
            "image_mode": (row.get("image_mode") or "0").strip().lower() in truthy,
        })
    return out


async def admin_import(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Restore users from a CSV/JSON document sent by the admin."""
    if not is_admin(update.effective_chat.id):
        return
    lang = _admin_lang()
    document = update.effective_message.document
    if document is None:
        await reply(update, t(lang, "admin_import_help"))
        return
    if (document.file_size or 0) > MAX_IMPORT_BYTES:
        await reply(update, t(lang, "admin_import_big").format(
            MAX_IMPORT_BYTES // 1024))
        return
    try:
        handle = await context.bot.get_file(document.file_id)
        payload = bytes(await handle.download_as_bytearray())
    except TelegramError:
        log.exception("import download failed")
        await reply(update, t(lang, "error"))
        return
    try:
        incoming = await asyncio.to_thread(parse_import, payload)
    except Exception:
        log.exception("import parse failed")
        await reply(update, t(lang, "admin_import_bad"))
        return
    if not incoming:
        await reply(update, t(lang, "admin_import_empty"))
        return
    added, updated, skipped = await store.merge(incoming)
    log.info("import: +%d ~%d skip=%d", added, updated, skipped)
    await reply(update, t(lang, "admin_import_ok").format(added, updated, skipped))


def installed_sha() -> str:
    """Checksum of the installer this deployment was built from."""
    try:
        return INSTALLER_SHA_FILE.read_text("utf-8").split()[0].strip()
    except (OSError, IndexError):
        return ""


def check_update() -> dict:
    """Download the published installer and describe how it differs.

    Blocking; call it in a worker thread. Raises on network errors.
    """
    payload = src.fetch_bytes(UPDATE_URL, timeout=25)
    if not payload.lstrip().startswith(b"#!"):
        raise ValueError("the update URL did not return a shell script")
    text = payload.decode("utf-8", errors="replace")
    match = re.search(r'^BOT_VERSION="([^"]+)"', text, re.M)
    remote_version = match.group(1) if match else "?"
    remote_sha = hashlib.sha256(payload).hexdigest()
    local_sha = installed_sha()
    return {
        "version": remote_version,
        "sha": remote_sha,
        "version_changed": remote_version != BOT_VERSION and remote_version != "?",
        "code_changed": bool(local_sha) and remote_sha != local_sha,
        "known": bool(local_sha),
    }


async def admin_update(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Check whether a newer installer is published."""
    if not is_admin(update.effective_chat.id):
        return
    lang = _admin_lang()
    if not UPDATE_URL:
        await reply(update, t(lang, "upd_no_url"))
        return
    await reply(update, t(lang, "upd_checking"))
    try:
        info = await asyncio.to_thread(check_update)
    except Exception as exc:
        log.exception("update check failed")
        await reply(update, t(lang, "upd_failed").format(E(str(exc)[:200])))
        return

    if not (info["version_changed"] or info["code_changed"]):
        await reply(update, t(lang, "upd_none").format(E(BOT_VERSION)))
        return

    reason = t(lang, "upd_version_changed" if info["version_changed"]
               else "upd_code_changed")
    keyboard = InlineKeyboardMarkup([[
        InlineKeyboardButton(t(lang, "adm_update"), callback_data="adm:upgrade"),
        InlineKeyboardButton(t(lang, "no"), callback_data="adm:bccancel"),
    ]])
    await reply(update, t(lang, "upd_found").format(
        E(BOT_VERSION), E(info["version"]), reason), reply_markup=keyboard)


async def request_update(lang: str) -> str:
    """Drop the trigger file the root-owned updater watches for.

    The URL is deliberately NOT passed here: the privileged script reads
    UPDATE_URL from the root-owned config, so an unprivileged bot process
    can never point the updater at a different script.
    """
    if UPDATE_REQUEST.exists():
        return t(lang, "upd_queued_already")
    try:
        await asyncio.to_thread(
            UPDATE_REQUEST.write_text,
            json.dumps({"from": ADMIN_ID, "version": BOT_VERSION}), "utf-8")
    except OSError as exc:
        log.exception("could not queue the update")
        return t(lang, "upd_failed").format(E(str(exc)[:200]))
    return t(lang, "upd_started")


async def report_update_result(application) -> None:
    """After a restart, tell the admin how the update went."""
    if not ADMIN_ID.isdigit() or not UPDATE_RESULT.exists():
        return
    try:
        data = json.loads(UPDATE_RESULT.read_text("utf-8"))
    except (OSError, json.JSONDecodeError):
        data = {}
    try:
        UPDATE_RESULT.unlink()
    except OSError:
        pass
    lang = _admin_lang()
    if data.get("status") == "ok":
        text = t(lang, "upd_report_ok").format(E(BOT_VERSION),
                                               E(str(data.get("old", "?"))))
    else:
        text = t(lang, "upd_report_fail").format(
            E(BOT_VERSION), E(str(data.get("error", "unknown"))[:300]))
    try:
        await application.bot.send_message(chat_id=int(ADMIN_ID), text=text)
    except TelegramError:
        log.debug("update report failed", exc_info=True)


async def admin_banned(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_chat.id):
        return
    lang = _admin_lang()
    ids = store.banned_ids()
    if not ids:
        await reply(update, t(lang, "admin_banned_empty"))
        return
    body = "\n".join(f"• <code>{E(i)}</code>" for i in ids[:100])
    await reply(update, t(lang, "admin_banned_list").format(body))


async def _set_ban(update: Update, context: ContextTypes.DEFAULT_TYPE,
                   banned: bool) -> None:
    if not is_admin(update.effective_chat.id):
        return
    lang = _admin_lang()
    args = context.args or []
    if not args:
        await reply(update, t(lang, "admin_ban_usage" if banned
                              else "admin_unban_usage"))
        return
    target = args[0].strip().lstrip("#")
    if not target.isdigit():
        await reply(update, t(lang, "admin_bad_id"))
        return
    if banned and target == ADMIN_ID:
        await reply(update, t(lang, "admin_ban_self"))
        return
    if not store.exists(target):
        await reply(update, t(lang, "admin_unknown").format(E(target)))
        return
    await store.upsert(target, banned=banned)
    await reply(update, t(lang, "admin_ban_ok" if banned
                          else "admin_unban_ok").format(E(target)))


async def admin_ban(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await _set_ban(update, context, True)


async def admin_unban(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await _set_ban(update, context, False)


async def prepare_broadcast(update: Update, context: ContextTypes.DEFAULT_TYPE,
                            body: str) -> None:
    """Stash the draft and show a preview with confirm/cancel buttons."""
    lang = _admin_lang()
    body = (body or "").strip()
    if not body:
        await reply(update, t(lang, "admin_bc_usage"))
        return
    if len(body) > MAX_BROADCAST_CHARS:
        await reply(update, t(lang, "admin_bc_long").format(MAX_BROADCAST_CHARS))
        return
    recipients = store.subscribed()
    if recipients == 0:
        await reply(update, t(lang, "admin_bc_none"))
        return
    context.bot_data["pending_broadcast"] = body
    await reply(update, t(lang, "admin_bc_confirm").format(recipients, E(body)),
                reply_markup=confirm_keyboard(lang))


async def admin_broadcast(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_chat.id):
        return
    context.user_data.pop("awaiting_broadcast", None)
    await prepare_broadcast(update, context, " ".join(context.args or []))


async def admin_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_admin(update.effective_chat.id):
        return
    context.user_data.pop("awaiting_broadcast", None)
    context.bot_data.pop("pending_broadcast", None)
    await reply(update, t(_admin_lang(), "admin_bc_cancel"))


# ==========================================================================
# Callbacks
# ==========================================================================
async def _show_filters(query, lang: str, prefs: dict) -> None:
    try:
        await query.edit_message_text(t(lang, "filters_title"),
                                      reply_markup=filters_keyboard(lang, prefs))
    except BadRequest as exc:
        if "not modified" not in str(exc).lower():
            log.debug("filter edit failed: %s", exc)
    except TelegramError:
        log.debug("filter edit failed", exc_info=True)


async def on_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if query is None or query.message is None:
        return
    chat_id = query.message.chat.id
    data = query.data or ""

    if store.is_banned(chat_id):
        await query.answer()
        return

    lang = store.lang(chat_id)

    # ---- language --------------------------------------------------------
    if data.startswith("setlang_"):
        new_lang = data.split("_", 1)[1]
        if new_lang not in TEXTS:
            await query.answer()
            return
        await store.upsert(chat_id, lang=new_lang)
        await query.answer()
        try:
            await query.message.reply_text(
                t(new_lang, "lang_selected"),
                reply_markup=main_keyboard(new_lang, chat_id))
        except TelegramError:
            log.debug("lang reply failed", exc_info=True)
        return

    # ---- countdown -------------------------------------------------------
    if data in ("timer_bp", "timer_venture"):
        await query.answer(t(lang, "timer_updated"))
        try:
            body = await asyncio.to_thread(format_countdown, data, lang)
        except Exception:
            log.exception("countdown failed")
            body = t(lang, "error")
        try:
            await query.edit_message_text(body, reply_markup=timer_keyboard(lang))
        except BadRequest as exc:
            if "not modified" not in str(exc).lower():
                log.debug("edit failed: %s", exc)
        except TelegramError:
            log.debug("edit failed", exc_info=True)
        return

    # ---- filters ---------------------------------------------------------
    if data.startswith("flt:"):
        action = data.split(":")
        prefs = store.record(chat_id)
        if action[1] == "noop":
            await query.answer()
            return
        if action[1] == "close":
            await query.answer(t(lang, "filters_saved"))
            try:
                await query.edit_message_reply_markup(reply_markup=None)
            except TelegramError:
                pass
            return
        if action[1] == "reset":
            await store.upsert(chat_id, zones=[], rewards=[])
        elif action[1] in ("z", "r") and len(action) > 2 and action[2].isdigit():
            index = int(action[2])
            pool = ZONES if action[1] == "z" else REWARD_NAMES
            field = "zones" if action[1] == "z" else "rewards"
            if index < len(pool):
                selected = list(prefs.get(field) or [])
                name = pool[index]
                if name in selected:
                    selected.remove(name)
                else:
                    selected.append(name)
                await store.upsert(chat_id, **{field: selected})
        await query.answer()
        await _show_filters(query, lang, store.record(chat_id))
        return

    # ---- weekly reward (admin) -------------------------------------------
    if data.startswith("wk:"):
        if not is_admin(chat_id):
            await query.answer()
            return
        alang = _admin_lang()
        parts = data.split(":")
        if parts[1] == "set" and len(parts) > 2 and parts[2] in WEEKLY_KEYS:
            await asyncio.to_thread(src.set_weekly_override, parts[2])
            await query.answer(t(alang, "wk_set_ok").format(src.WEEKLY_LABELS[parts[2]]))
        elif parts[1] == "auto":
            await asyncio.to_thread(src.set_weekly_override, None)
            await query.answer(t(alang, "wk_auto_ok"))
        elif parts[1] == "send":
            await query.answer()
            try:
                reward = await asyncio.to_thread(src.get_weekly)
            except Exception:
                await query.message.reply_text(t(alang, "error"))
                return
            sent, failed = await broadcast_weekly(context, reward)
            await query.message.reply_text(t(alang, "wk_sent").format(sent, failed))
            return
        else:
            await query.answer()
        try:
            reward = await asyncio.to_thread(src.get_weekly)
        except Exception:
            reward = None
        text = weekly_admin_text(alang, reward) if reward else t(alang, "weekly_none")
        markup = weekly_keyboard(alang, weekly_parts(reward)[1] if reward else "")
        try:
            if parts[1] == "show":
                await query.message.reply_text(text, reply_markup=markup)
            else:
                await query.edit_message_text(text, reply_markup=markup)
        except BadRequest as exc:
            if "not modified" not in str(exc).lower():
                log.debug("weekly admin edit failed: %s", exc)
        return

    # ---- admin -----------------------------------------------------------
    if data.startswith("adm:"):
        if not is_admin(chat_id):
            await query.answer()
            return
        action = data.split(":", 1)[1]
        alang = _admin_lang()

        if action == "stats":
            await query.answer()
            await query.message.reply_text(t(alang, "admin_stat").format(
                store.count(), store.subscribed(), len(store.banned_ids()),
                store.with_filters()))
        elif action == "export":
            await query.answer()
            await admin_export(update, context)
        elif action == "update":
            await query.answer()
            await admin_update(update, context)
        elif action == "upgrade":
            await query.answer()
            try:
                await query.edit_message_reply_markup(reply_markup=None)
            except TelegramError:
                pass
            await query.message.reply_text(await request_update(alang))
        elif action == "import":
            await query.answer()
            await query.message.reply_text(t(alang, "admin_import_help"))
        elif action == "banned":
            await query.answer()
            ids = store.banned_ids()
            body = ("\n".join(f"• <code>{E(i)}</code>" for i in ids[:100])
                    if ids else None)
            await query.message.reply_text(
                t(alang, "admin_banned_list").format(body) if body
                else t(alang, "admin_banned_empty"))
        elif action == "refresh":
            await asyncio.to_thread(src.clear_all_caches)
            await query.answer(t(alang, "admin_refreshed"))
        elif action == "bchelp":
            await query.answer()
            context.user_data["awaiting_broadcast"] = True
            await query.message.reply_text(t(alang, "admin_bc_prompt"))
        elif action == "bccancel":
            context.bot_data.pop("pending_broadcast", None)
            await query.answer()
            try:
                await query.edit_message_text(t(alang, "admin_bc_cancel"))
            except TelegramError:
                pass
        elif action == "bcsend":
            body = context.bot_data.pop("pending_broadcast", None)
            if not body:
                await query.answer(t(alang, "admin_bc_expired"), show_alert=True)
                return
            await query.answer()
            try:
                await query.edit_message_reply_markup(reply_markup=None)
            except TelegramError:
                pass
            payload = f"📢 {E(body)}"
            log.info("admin broadcast starting")
            sent, failed = await broadcast(context, lambda record: payload)
            await query.message.reply_text(
                t(alang, "admin_bc_sent").format(sent, failed))
        return


# ==========================================================================
# Scheduled broadcasts
# ==========================================================================
async def broadcast(context: ContextTypes.DEFAULT_TYPE, builders) -> tuple[int, int]:
    """Send one or more messages to every subscriber, in the given order.

    Order matters: the phone notification previews the LAST message, so the
    caller puts the most interesting one (V-Bucks) at the end.
    """
    if callable(builders):
        builders = [builders]
    sent = failed = 0
    stale: list[str] = []
    for chat_id, record in store.items():
        if not record["notify"] or record.get("banned"):
            continue
        delivered = False
        for builder in builders:
            try:
                body = builder(record)
            except Exception:
                log.exception("broadcast builder failed for %s", chat_id)
                continue
            if not body:
                continue
            try:
                if isinstance(body, dict):
                    try:
                        await context.bot.send_photo(
                            chat_id=int(chat_id),
                            photo=InputFile(io.BytesIO(body["photo"]),
                                            filename="weekly.png"),
                            caption=body.get("caption"))
                    except (Forbidden, RetryAfter):
                        raise
                    except TelegramError:
                        log.debug("photo broadcast failed; sending text",
                                  exc_info=True)
                        body = body["text"]
                if isinstance(body, str):
                    for part in chunks(body):
                        await context.bot.send_message(chat_id=int(chat_id), text=part)
                delivered = True
            except Forbidden:
                stale.append(chat_id)      # blocked the bot / deleted the chat
                break
            except RetryAfter as exc:
                await asyncio.sleep(float(exc.retry_after) + 1)
                try:
                    if isinstance(body, dict):
                        body = body["text"]
                    await context.bot.send_message(chat_id=int(chat_id),
                                                   text=next(iter(chunks(body))))
                    delivered = True
                except TelegramError:
                    failed += 1
            except TelegramError:
                failed += 1
            await asyncio.sleep(BROADCAST_DELAY)
        if delivered:
            sent += 1

    for chat_id in stale:
        await store.remove(chat_id)
    if stale:
        log.info("removed %d unreachable chats", len(stale))
    log.info("broadcast done: sent=%d failed=%d", sent, failed)
    return sent, failed


async def daily_job(context: ContextTypes.DEFAULT_TYPE) -> None:
    try:
        vbucks = await asyncio.to_thread(src.fetch_vbucks_missions, force=True)
        power = await asyncio.to_thread(src.fetch_power_missions, 160, force=True)
        venture = await asyncio.to_thread(src.fetch_venture_missions, 140)
    except Exception:
        log.exception("daily fetch failed — skipping broadcast")
        return

    # Three separate messages, V-Bucks last: the phone notification shows the
    # last one, and that is the one people actually care about.
    def build_power(record: dict) -> str:
        lang = record["lang"]
        return (f"{t(lang, 'daily_title')}\n{SEP}\n\n"
                f"{format_power(power, lang, 160, unfiltered(record))}")

    def build_venture(record: dict) -> str:
        return format_venture(venture, record["lang"], unfiltered(record))

    def build_vbucks(record: dict) -> str:
        return format_vbucks(vbucks, record["lang"], unfiltered(record))

    await broadcast(context, [build_power, build_venture, build_vbucks])


WEEKLY_RETRY_SECONDS = 900


async def weekly_job(context: ContextTypes.DEFAULT_TYPE) -> None:
    """Weekly alert. FortniteDB publishes the new reward some time after the
    reset, so keep retrying every 15 min until this week's value is there
    (up to WEEKLY_SETTLE_HOURS), instead of broadcasting last week's."""
    attempt = int((context.job.data or {}).get("attempt", 0)) if context.job else 0
    if attempt == 0 and datetime.now(timezone.utc).weekday() != WEEKLY_RESET_WEEKDAY:
        return
    max_attempts = int(src.WEEKLY_SETTLE_HOURS * 3600 // WEEKLY_RETRY_SECONDS) + 1
    try:
        reward = await asyncio.to_thread(src.get_weekly, force=True)
    except Exception:
        log.warning("weekly fetch failed (attempt %d)", attempt + 1, exc_info=True)
        reward = None

    if not src.weekly_is_current(reward) and attempt + 1 < max_attempts:
        log.info("weekly reward not published yet — retry in %ds", WEEKLY_RETRY_SECONDS)
        context.job_queue.run_once(weekly_job, WEEKLY_RETRY_SECONDS,
                                   data={"attempt": attempt + 1},
                                   name="weekly-retry")
        return
    if not reward:
        log.error("weekly reward unavailable — skipping broadcast")
        return
    await broadcast_weekly(context, reward)
    # Sources can be wrong (FortniteDB has lagged the game before): let the
    # admin confirm or correct, then re-send with one tap.
    if ADMIN_ID:
        alang = _admin_lang()
        try:
            await context.bot.send_message(
                chat_id=int(ADMIN_ID), text=weekly_admin_text(alang, reward),
                reply_markup=weekly_keyboard(alang, weekly_parts(reward)[1]))
        except TelegramError:
            log.debug("could not notify admin about weekly reward", exc_info=True)


async def broadcast_weekly(context: ContextTypes.DEFAULT_TYPE, reward: Any):
    label = weekly_parts(reward)[0]
    png = None
    if vimg.available():
        png = await asyncio.to_thread(render_weekly_card, reward, "This Week's Reward")

    def build(record: dict):
        lang = record["lang"]
        text = (f"{t(lang, 'weekly_push')}\n{SEP}\n\n"
                f"{format_weekly(reward, lang)}")
        if png and record.get("image_mode"):
            caption = f"{t(lang, 'weekly_push')}\n\n" + \
                t(lang, "weekly_caption").format(E(label))
            return {"photo": png, "caption": caption, "text": text}
        return text

    return await broadcast(context, build)


async def post_init(application) -> None:
    await report_update_result(application)
    try:
        await _set_commands(application)
    except Exception:
        # A transient network/proxy hiccup must not abort startup.
        log.warning("could not register the command list", exc_info=True)


async def _set_commands(application) -> None:
    await application.bot.set_my_commands([
        BotCommand("start", "Menu / منو"),
        BotCommand("menu", "Show keyboard / نمایش کیبورد"),
        BotCommand("filters", "Filters / فیلترها"),
        BotCommand("venture", "Ventures 140 / ونچر ۱۴۰"),
        BotCommand("alerts", "Toggle alerts / اعلان‌ها"),
        BotCommand("image", "Image or text / عکس یا متن"),
        BotCommand("help", "Help / راهنما"),
    ])


def build_defaults() -> Defaults:
    """Disable link previews across PTB versions.

    PTB <= 21 uses ``disable_web_page_preview``; PTB >= 22 replaced it with
    ``link_preview_options``. Try the modern form first, then fall back.
    """
    base = {"tzinfo": timezone.utc, "parse_mode": ParseMode.HTML}
    try:
        from telegram import LinkPreviewOptions
        return Defaults(link_preview_options=LinkPreviewOptions(is_disabled=True),
                        **base)
    except (ImportError, TypeError):
        pass
    try:
        return Defaults(disable_web_page_preview=True, **base)
    except TypeError:
        log.warning("this PTB version supports neither link-preview option")
        return Defaults(**base)


async def on_error(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    log.error("unhandled error", exc_info=context.error)


# ==========================================================================
# Entrypoint
# ==========================================================================
def main() -> None:
    if not BOT_TOKEN or not TOKEN_RE.match(BOT_TOKEN):
        sys.exit("FATAL: BOT_TOKEN is missing or malformed (expected 123456:AA...).")
    if not ADMIN_ID.isdigit():
        sys.exit("FATAL: ADMIN_CHAT_ID must be numeric.")

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    store.load()

    builder = ApplicationBuilder().token(BOT_TOKEN).defaults(build_defaults())

    if AIORateLimiter is not None:
        builder = builder.rate_limiter(AIORateLimiter())

    if PROXY_URL:
        request = HTTPXRequest(proxy=PROXY_URL, connect_timeout=20,
                               read_timeout=40, pool_timeout=10)
        get_updates = HTTPXRequest(proxy=PROXY_URL, connect_timeout=20,
                                   read_timeout=70, pool_timeout=10)
        builder = builder.request(request).get_updates_request(get_updates)
        log.info("using proxy %s", redact_url(PROXY_URL))

    application = builder.post_init(post_init).build()

    queue = application.job_queue
    if queue is None:
        sys.exit("FATAL: job-queue extra is not installed "
                 "(pip install 'python-telegram-bot[job-queue]').")
    queue.run_daily(daily_job, time=_parse_hhmm(DAILY_RESET_UTC, (0, 1)),
                    name="daily-reset")
    # Runs every day and filters by weekday internally: this avoids the
    # Monday/Sunday indexing difference between PTB versions.
    queue.run_daily(weekly_job, time=_parse_hhmm(WEEKLY_RESET_UTC, (0, 2)),
                    name="weekly-reset")

    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("help", help_cmd))
    application.add_handler(CommandHandler("menu", menu_cmd))
    application.add_handler(CommandHandler("filters", filters_cmd))
    application.add_handler(CommandHandler("venture", venture_cmd))
    application.add_handler(CommandHandler("alerts", toggle_alerts))
    application.add_handler(CommandHandler("image", toggle_image))
    application.add_handler(CommandHandler("stats", admin_stats))
    application.add_handler(CommandHandler("refresh", admin_refresh))
    application.add_handler(CommandHandler("setweekly", admin_setweekly))
    application.add_handler(CommandHandler("update", admin_update))
    application.add_handler(CommandHandler("broadcast", admin_broadcast))
    application.add_handler(CommandHandler("cancel", admin_cancel))
    application.add_handler(CommandHandler("ban", admin_ban))
    application.add_handler(CommandHandler("unban", admin_unban))
    application.add_handler(CommandHandler("banned", admin_banned))
    application.add_handler(CommandHandler("export", admin_export))
    application.add_handler(CommandHandler("import", admin_import))
    if ADMIN_ID.isdigit():
        application.add_handler(MessageHandler(
            filters.Document.ALL & filters.Chat(int(ADMIN_ID)), admin_import))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_text))
    application.add_handler(CallbackQueryHandler(on_callback))
    application.add_error_handler(on_error)

    log.info("bot starting: version=%s users=%d max=%d image=%s",
             BOT_VERSION, store.count(), MAX_USERS, vimg.available())
    # bootstrap_retries=-1: if Telegram is unreachable at startup, keep
    # retrying forever instead of crashing into a systemd restart loop.
    application.run_polling(drop_pending_updates=True,
                            bootstrap_retries=-1,
                            allowed_updates=["message", "callback_query"])


if __name__ == "__main__":
    main()
BOT_PY_EOF

cat > "$APP_DIR/vbucks_image.py" <<'IMAGE_PY_EOF'
#!/usr/bin/env python3
"""Renders mission lists as a light, readable PNG card.

Design
------
Light paper background, white cards with a coloured spine, and a small
set of icons drawn here from primitives — circles, polygons, lines. The
icons are original shapes standing for a *category* (a cut gem for
currency, a figure for survivors, a shield for defenders). No game art,
logos or screenshots are reproduced.

Rules:
* Stay well under 100 kB. A 128-colour palette on a light background
  gets six cards to roughly 40 kB.
* Never raise. ``render()`` returns None and the bot falls back to text.
* DejaVu has no emoji or Persian glyphs, so text is stripped of what it
  cannot draw. Mission and reward names from the source are ASCII.
"""

from __future__ import annotations

import io
import logging
import math
import os
import re
from pathlib import Path

log = logging.getLogger(__name__)

try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:  # pragma: no cover - Pillow is optional
    Image = ImageDraw = ImageFont = None  # type: ignore

# --------------------------------------------------------------------------
# Light palette
# --------------------------------------------------------------------------
PAPER = (244, 245, 250)
CARD = (255, 255, 255)
BORDER = (226, 229, 240)
INK = (23, 20, 48)
BODY = (43, 37, 64)
MUTED = (110, 104, 133)
WHITE = (255, 255, 255)

AMBER = (232, 145, 12)
AMBER_SOFT = (255, 243, 219)
VIOLET = (98, 78, 200)
VIOLET_SOFT = (238, 235, 252)
GREEN = (22, 150, 105)
GREEN_SOFT = (226, 246, 238)
SLATE = (120, 128, 156)

ACCENTS = {
    "top": ((255, 110, 60), (255, 230, 220)),
    "finder": ((80, 200, 230), (220, 245, 250)),
    "vbucks": (AMBER, AMBER_SOFT),
    "power": (VIOLET, VIOLET_SOFT),
    "venture": (GREEN, GREEN_SOFT),
}

# Rarity colours. Tiering loot by colour is a genre-wide convention; these
# values are our own.
RARITY = {
    "mythic": (245, 205, 70),
    "legendary": (247, 148, 47),
    "epic": (168, 90, 240),
    "rare": (58, 150, 240),
    "uncommon": (78, 190, 96),
    "common": (150, 156, 178),
}
_RARITY_RE = re.compile(r"\((mythic|legendary|epic|rare|uncommon|common)\)", re.I)


def split_rarity(name: str) -> tuple:
    """"Survivor (Epic)" -> ("Survivor", purple)."""
    match = _RARITY_RE.search(name or "")
    if not match:
        return name, None
    cleaned = _RARITY_RE.sub("", name).replace("  ", " ").strip()
    return cleaned, RARITY[match.group(1).lower()]


FONT_DIRS = (
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/dejavu",
    "/usr/share/fonts/TTF",
)

# Optional hand-made artwork. Drop square PNGs in here and they replace the
# drawn icons; anything missing falls back to the vector version. The full
# list of names is in bot.env (ART_DIR comment) and in ART_NAMES below.
ART_DIR = Path(os.environ.get("ART_DIR", "/opt/fortnite_bot/art"))
_ART_CACHE: dict = {}


_ART_INDEX: dict = {}


def _norm(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", str(name).lower())


# Folder aliases: mission art may sit at the root or in scenes/ (missions/),
# zone art in zones/ or zone/.
_SUB_ALIASES = {"": ("", "scenes", "missions"), "zones": ("zones", "zone")}


def _art_index(sub: str) -> dict:
    """{normalised name: path} for ART_DIR/<sub>/*.png, so "V-Bucks.png",
    "v_bucks.png" and "vbucks.png" all match the slug "vbucks". Empty
    (0-byte) files are ignored."""
    if sub not in _ART_INDEX:
        index = {}
        for folder_name in _SUB_ALIASES.get(sub, (sub,)):
            folder = ART_DIR / folder_name if folder_name else ART_DIR
            try:
                for path in sorted(folder.iterdir()):
                    if path.suffix.lower() == ".png" and path.is_file() \
                            and path.stat().st_size > 0:
                        index.setdefault(_norm(path.stem), path)
            except OSError:
                pass
        _ART_INDEX[sub] = index
    return _ART_INDEX[sub]


def art(slug, size: int, sub: str = ""):
    """Load art/<sub>/<slug>.png resized to size, or None.

    ``slug`` may be a list of candidates tried in order, so art packs can use
    any of the common names (bomb / deliver / dtb …).
    """
    if isinstance(slug, (list, tuple)):
        for candidate in slug:
            found = art(candidate, size, sub)
            if found is not None:
                return found
        return None
    key = (sub, slug, size)
    if key in _ART_CACHE:
        return _ART_CACHE[key]
    path = _art_index(sub).get(_norm(slug))
    image = None
    try:
        if path is not None:
            image = Image.open(path).convert("RGBA").resize(
                (size, size), Image.LANCZOS)
    except Exception:
        log.debug("could not load art %s", path, exc_info=True)
        image = None
    _ART_CACHE[key] = image
    return image


WIDTH = 900
MARGIN = 24
HEADER_H = 86
CARD_PAD = 20
ROW_H = 32
FOOTER_H = 40
MAX_CARDS = int(os.environ.get("IMAGE_MAX_CARDS", "10"))   # hard cap per picture
MIN_CARDS = int(os.environ.get("IMAGE_MIN_CARDS", "5"))    # fewest per picture
MAX_REWARDS = 7

_UNSUPPORTED = re.compile(
    "[\U0001F000-\U0001FAFF\u2190-\u27BF\uFE0F\u200d\u200c\uE000-\uF8FF]"
)


# --------------------------------------------------------------------------
# Fonts
# --------------------------------------------------------------------------
_FONT_CACHE: dict[tuple[int, bool], object] = {}


def _font_path(bold: bool) -> str | None:
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for directory in FONT_DIRS:
        candidate = os.path.join(directory, name)
        if os.path.exists(candidate):
            return candidate
    return None


def _font(size: int, bold: bool = False):
    key = (size, bold)
    if key in _FONT_CACHE:
        return _FONT_CACHE[key]
    if ImageFont is None:
        return None
    path = _font_path(bold)
    if not path:
        return None
    try:
        font = ImageFont.truetype(path, size)
    except Exception:
        log.debug("could not load %s", path, exc_info=True)
        return None
    _FONT_CACHE[key] = font
    return font


def available() -> bool:
    return Image is not None and _font(14) is not None


def _safe(text: str, limit: int = 64) -> str:
    cleaned = _UNSUPPORTED.sub("", str(text or "")).strip()
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned[:limit - 1] + "…" if len(cleaned) > limit else cleaned


def _fit(draw, text: str, font, max_width: int) -> str:
    if draw.textlength(text, font=font) <= max_width:
        return text
    while text and draw.textlength(text + "…", font=font) > max_width:
        text = text[:-1]
    return text + "…"


def _darken(colour, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in colour)


def _lighten(colour, amount):
    return tuple(max(0, min(255, int(c + (255 - c) * amount))) for c in colour)


# ==========================================================================
# Icon set — original shapes drawn from primitives
# ==========================================================================
def _star_points(cx, cy, outer, inner, points=5, rotation=-90):
    coords = []
    for i in range(points * 2):
        radius = outer if i % 2 == 0 else inner
        angle = math.radians(rotation + i * 180 / points)
        coords.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return coords


def ic_gem(d, x, y, s, c):
    """Currency: a faceted gem, lit from the upper left."""
    top, mid, bot = y + s * .14, y + s * .42, y + s * .92
    l, r, cx = x + s * .06, x + s * .94, x + s * .50
    ql, qr = x + s * .28, x + s * .72
    light, dark = _lighten(c, .42), _darken(c, .72)
    # crown
    d.polygon([(l, mid), (ql, top), (cx, mid)], fill=light)
    d.polygon([(ql, top), (qr, top), (cx, mid)], fill=_lighten(c, .18))
    d.polygon([(qr, top), (r, mid), (cx, mid)], fill=dark)
    # pavilion
    d.polygon([(l, mid), (cx, mid), (cx, bot)], fill=c)
    d.polygon([(cx, mid), (r, mid), (cx, bot)], fill=dark)
    d.line([(l, mid), (r, mid)], fill=_lighten(c, .55), width=1)
    d.line([(ql, top), (cx, bot)], fill=_lighten(c, .30), width=1)
    d.line([(qr, top), (cx, bot)], fill=_darken(c, .85), width=1)
    # sparkle
    d.line([(x + s * .34, y + s * .26), (x + s * .40, y + s * .32)],
           fill=WHITE, width=max(1, int(s * .06)))


def ic_person(d, x, y, s, c):
    d.ellipse([x + s * .32, y + s * .08, x + s * .68, y + s * .44], fill=c)
    d.rounded_rectangle([x + s * .18, y + s * .50, x + s * .82, y + s * .96],
                        radius=max(3, int(s * .26)), fill=c)
    d.rectangle([x + s * .18, y + s * .80, x + s * .82, y + s * .96], fill=c)


def ic_hero(d, x, y, s, c):
    d.polygon([(x + s * .22, y + s * .44), (x + s * .78, y + s * .44),
               (x + s * .96, y + s * .98), (x + s * .04, y + s * .98)],
              fill=_darken(c, .82))
    d.polygon([(x + s * .30, y + s * .46), (x + s * .70, y + s * .46),
               (x + s * .80, y + s * .96), (x + s * .20, y + s * .96)], fill=c)
    d.ellipse([x + s * .34, y + s * .06, x + s * .66, y + s * .38], fill=c)
    d.polygon([(x + s * .38, y + s * .54), (x + s * .62, y + s * .54),
               (x + s * .50, y + s * .80)], fill=WHITE)


def ic_shield(d, x, y, s, c):
    d.polygon([(x + s * .50, y + s * .08), (x + s * .92, y + s * .24),
               (x + s * .84, y + s * .70), (x + s * .50, y + s * .96),
               (x + s * .16, y + s * .70), (x + s * .08, y + s * .24)], fill=c)
    d.line([(x + s * .50, y + s * .22), (x + s * .50, y + s * .80)],
           fill=WHITE, width=max(1, int(s * .08)))


def ic_blueprint(d, x, y, s, c):
    d.rounded_rectangle([x + s * .14, y + s * .12, x + s * .86, y + s * .92],
                        radius=max(2, int(s * .12)), fill=c)
    for i, w in enumerate((.55, .70, .42)):
        ty = y + s * (.30 + i * .19)
        d.line([(x + s * .26, ty), (x + s * (.26 + w * .62), ty)], fill=WHITE, width=2)


def ic_trap(d, x, y, s, c):
    d.rounded_rectangle([x + s * .12, y + s * .14, x + s * .88, y + s * .90],
                        radius=max(2, int(s * .14)), fill=c)
    d.polygon([(x + s * .50, y + s * .30), (x + s * .72, y + s * .72),
               (x + s * .28, y + s * .72)], fill=WHITE)


def ic_drop(d, x, y, s, c):
    d.ellipse([x + s * .22, y + s * .42, x + s * .78, y + s * .94], fill=c)
    d.polygon([(x + s * .50, y + s * .08), (x + s * .78, y + s * .62),
               (x + s * .22, y + s * .62)], fill=c)


def ic_chevron(d, x, y, s, c):
    d.ellipse([x + s * .08, y + s * .08, x + s * .92, y + s * .92], fill=c)
    d.line([(x + s * .30, y + s * .58), (x + s * .50, y + s * .36),
            (x + s * .70, y + s * .58)], fill=WHITE, width=max(2, int(s * .13)))


def ic_star(d, x, y, s, c):
    d.polygon(_star_points(x + s * .50, y + s * .52, s * .44, s * .19), fill=c)


def ic_coin(d, x, y, s, c):
    d.ellipse([x + s * .10, y + s * .38, x + s * .74, y + s * .70], fill=c)
    d.ellipse([x + s * .26, y + s * .22, x + s * .90, y + s * .54], fill=c,
              outline=WHITE, width=1)


def ic_dot(d, x, y, s, c):
    d.ellipse([x + s * .30, y + s * .30, x + s * .70, y + s * .70], fill=c)


REWARD_ICONS = (
    (re.compile(r"v[\s_\-]?bucks|mtxswap", re.I), ic_gem),
    (re.compile(r"hero", re.I), ic_hero),
    (re.compile(r"defender", re.I), ic_shield),
    (re.compile(r"survivor|worker|lead", re.I), ic_person),
    (re.compile(r"schematic|weapon|blueprint", re.I), ic_blueprint),
    (re.compile(r"trap", re.I), ic_trap),
    (re.compile(r"perk", re.I), ic_chevron),
    (re.compile(r"rain|lightning|training|evolution|evo|flux|ore|crystal", re.I), ic_drop),
    (re.compile(r"\bxp\b|experience", re.I), ic_star),
    (re.compile(r"gold|coin|ticket|voucher", re.I), ic_coin),
)


def reward_icon(name: str):
    for pattern, drawer in REWARD_ICONS:
        if pattern.search(name or ""):
            return drawer
    return ic_dot


# --- mission-type marks ---------------------------------------------------
def mi_truck(d, x, y, s, c):
    d.rounded_rectangle([x + s * .06, y + s * .34, x + s * .62, y + s * .70],
                        radius=max(2, int(s * .10)), fill=c)
    d.polygon([(x + s * .62, y + s * .44), (x + s * .84, y + s * .44),
               (x + s * .94, y + s * .70), (x + s * .62, y + s * .70)], fill=c)
    for cx in (.26, .78):
        d.ellipse([x + s * (cx - .10), y + s * .66, x + s * (cx + .10), y + s * .86],
                  fill=c)


def mi_storm(d, x, y, s, c):
    d.ellipse([x + s * .10, y + s * .24, x + s * .58, y + s * .58], fill=c)
    d.ellipse([x + s * .40, y + s * .16, x + s * .90, y + s * .58], fill=c)
    d.rectangle([x + s * .18, y + s * .44, x + s * .84, y + s * .58], fill=c)
    d.polygon([(x + s * .56, y + s * .60), (x + s * .34, y + s * .94),
               (x + s * .50, y + s * .74), (x + s * .38, y + s * .74)], fill=c)


def mi_radar(d, x, y, s, c):
    d.pieslice([x + s * .06, y + s * .10, x + s * .94, y + s * .98], 200, 340, fill=c)
    d.line([(x + s * .50, y + s * .52), (x + s * .50, y + s * .94)], fill=c,
           width=max(2, int(s * .14)))


def mi_balloon(d, x, y, s, c):
    d.ellipse([x + s * .22, y + s * .08, x + s * .78, y + s * .66], fill=c)
    d.line([(x + s * .50, y + s * .66), (x + s * .50, y + s * .94)], fill=c, width=2)


def mi_house(d, x, y, s, c):
    d.polygon([(x + s * .50, y + s * .10), (x + s * .94, y + s * .46),
               (x + s * .06, y + s * .46)], fill=c)
    d.rectangle([x + s * .18, y + s * .46, x + s * .82, y + s * .92], fill=c)


def mi_bomb(d, x, y, s, c):
    d.ellipse([x + s * .12, y + s * .34, x + s * .80, y + s * .94], fill=c)
    d.line([(x + s * .68, y + s * .34), (x + s * .90, y + s * .10)], fill=c,
           width=max(2, int(s * .14)))


def mi_target(d, x, y, s, c):
    d.ellipse([x + s * .10, y + s * .18, x + s * .90, y + s * .94], outline=c,
              width=max(2, int(s * .14)))
    d.ellipse([x + s * .38, y + s * .46, x + s * .62, y + s * .68], fill=c)


MISSION_ICONS = (
    (re.compile(r"ride the lightning", re.I), mi_truck),
    (re.compile(r"storm|category", re.I), mi_storm),
    (re.compile(r"radar", re.I), mi_radar),
    (re.compile(r"retrieve|retrive|balloon|data", re.I), mi_balloon),
    (re.compile(r"shelter|evacuate|repair", re.I), mi_house),
    (re.compile(r"bomb|dtb|deliver", re.I), mi_bomb),
)


def mission_icon(name: str):
    for pattern, drawer in MISSION_ICONS:
        if pattern.search(name or ""):
            return drawer
    return mi_target


# ==========================================================================
# Rendering
# ==========================================================================
def _card_height(mission: dict) -> int:
    rewards = min(len(mission.get("rewards") or []), MAX_REWARDS)
    return CARD_PAD + 28 + 24 + max(1, rewards) * ROW_H + CARD_PAD - 8


def render(missions: list[dict], *, title: str, kind: str = "vbucks",
           footer: str | None = None) -> bytes | None:
    """First page only (kept for callers that want one picture)."""
    pages = render_pages(missions, title=title, kind=kind, footer=footer)
    return pages[0] if pages else None


def render_pages(missions: list[dict], *, title: str, kind: str = "vbucks",
                 footer: str | None = None) -> list[bytes]:
    """Every mission, split into landscape pages (one PNG each).

    Nothing is dropped: a long list becomes several pictures instead of a
    "+N more" note. Pages hold IMAGE_MIN_CARDS..IMAGE_MAX_CARDS missions,
    spread evenly (5 + 5, never 4 + 1).
    """
    if not available() or not missions:
        return []
    chunks = split_pages(missions)
    pages = []
    try:
        for n, chunk in enumerate(chunks, 1):
            head = f"{title}  ({n}/{len(chunks)})" if len(chunks) > 1 else title
            pages.append(_render(chunk, head, kind, footer, hidden=0))
    except Exception:
        log.exception("image rendering failed")
        return []
    return pages


def _header_mark(draw, x, y, s, kind):
    marker = {"vbucks": ic_gem, "power": ic_shield}.get(kind, ic_drop)
    marker(draw, x, y, s, WHITE)


# ==========================================================================
# Mission scenes — painted with layered shapes, gradients and highlights.
# Original artwork: the idea is shared with the game, the drawing is ours.
# ==========================================================================
def _vgrad(size, top, bottom):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for i in range(size):
        r = i / max(1, size - 1)
        d.line([(0, i), (size, i)],
               fill=tuple(int(a + (b - a) * r) for a, b in zip(top, bottom)))
    return img


def _glow(d, cx, cy, r, colour, steps=6):
    """Soft radial halo, drawn as widening translucent-ish rings."""
    for i in range(steps, 0, -1):
        f = i / steps
        rr = r * f
        tint = tuple(int(c * (1.15 - f * .55)) for c in colour)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=tint)



def _striped_ellipse(d, cx, cy, rx, ry, base, stripe, gores=6):
    """An ellipse painted with vertical gores — reads as a balloon."""
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=base)
    for g in range(gores):
        if g % 2:
            continue
        x0 = cx - rx + (2 * rx) * g / gores
        x1 = cx - rx + (2 * rx) * (g + 1) / gores
        top, bottom = [], []
        steps = 14
        for i in range(steps + 1):
            x = x0 + (x1 - x0) * i / steps
            t = max(0.0, 1 - ((x - cx) / rx) ** 2)
            dy = ry * math.sqrt(t)
            top.append((x, cy - dy))
            bottom.append((x, cy + dy))
        d.polygon(top + bottom[::-1], fill=stripe)


NIGHT_TOP, NIGHT_BOT = (64, 74, 128), (24, 28, 54)
DUSK_TOP, DUSK_BOT = (108, 92, 150), (46, 40, 78)
GROUND, GROUND_D = (72, 96, 74), (46, 62, 50)
GREY, GREY_L, GREY_D = (172, 180, 198), (214, 220, 232), (108, 116, 136)
RED, RED_D = (228, 72, 64), (160, 40, 38)
WOOD, WOOD_D, WOOD_L = (162, 112, 66), (108, 72, 42), (198, 150, 98)
METAL, GLASS = (198, 206, 222), (126, 200, 236)
ORANGE, ORANGE_D, CREAM = (240, 146, 54), (196, 104, 32), (246, 242, 232)
BOLT, BOLT_D = (255, 232, 130), (246, 196, 60)
PURPLE, PURPLE_L, PURPLE_D = (132, 92, 200), (176, 138, 238), (76, 50, 132)


def _skyline(d, s, colour, horizon=.72):
    """Distant blocks — reads as a town on the horizon."""
    widths = (.10, .07, .13, .08, .11, .06, .12)
    x = -0.02
    for i, w in enumerate(widths):
        h = .10 + (.07 if i % 2 else .13)
        d.rectangle([s * x, s * (horizon - h), s * (x + w), s * horizon], fill=colour)
        x += w + .02


def _hills(d, s, colour, horizon=.74):
    d.ellipse([-s * .25, s * (horizon - .18), s * .55, s * (horizon + .30)], fill=colour)
    d.ellipse([s * .45, s * (horizon - .12), s * 1.25, s * (horizon + .30)], fill=colour)


def _ground(d, s, height=.80, colour=GROUND, dark=GROUND_D):
    d.rectangle([0, s * height, s, s], fill=colour)
    d.rectangle([0, s * height, s, s * (height + .03)], fill=dark)


def sc_shelter(d, s):
    """Evacuate the Shelter: a bunker with a siren and exit arrows."""
    _hills(d, s, (58, 72, 96), .72)
    _ground(d, s, .78)
    # dome, lit from the upper left
    d.pieslice([s * .18, s * .30, s * .82, s * .94], 180, 360, fill=GREY)
    d.pieslice([s * .24, s * .34, s * .62, s * .88], 180, 360, fill=GREY_L)
    d.rectangle([s * .18, s * .62, s * .82, s * .80], fill=GREY)
    d.rectangle([s * .14, s * .78, s * .86, s * .84], fill=GREY_D)
    # doorway
    d.rounded_rectangle([s * .42, s * .58, s * .58, s * .80], radius=s * .06,
                        fill=GREY_D)
    d.rounded_rectangle([s * .45, s * .62, s * .55, s * .80], radius=s * .04,
                        fill=(38, 42, 56))
    # siren + halo
    _glow(d, s * .50, s * .26, s * .13, RED_D)
    d.ellipse([s * .45, s * .21, s * .55, s * .31], fill=RED)
    d.ellipse([s * .465, s * .225, s * .515, s * .265], fill=(255, 168, 160))
    # exit arrows
    for side in (-1, 1):
        bx = s * (.50 + side * .33)
        d.polygon([(bx + side * s * .13, s * .70), (bx, s * .62), (bx, s * .78)],
                  fill=RED)
        d.rectangle([min(bx, bx - side * s * .10), s * .67,
                     max(bx, bx - side * s * .10), s * .73], fill=RED_D)


def sc_repair(d, s):
    """Repair the Shelter: a worn house, scaffolding and a wrench."""
    _skyline(d, s, (74, 62, 82), .74)
    _ground(d, s, .80, (86, 78, 60), (58, 52, 40))
    d.polygon([(s * .50, s * .22), (s * .88, s * .50), (s * .12, s * .50)],
              fill=WOOD_D)
    d.polygon([(s * .50, s * .22), (s * .50, s * .50), (s * .12, s * .50)],
              fill=WOOD)
    d.rectangle([s * .20, s * .50, s * .80, s * .82], fill=WOOD)
    d.rectangle([s * .20, s * .50, s * .50, s * .82], fill=WOOD_L)
    # boarded window + door
    d.rectangle([s * .28, s * .56, s * .44, s * .68], fill=(60, 66, 84))
    d.line([(s * .26, s * .58), (s * .46, s * .66)], fill=WOOD_D, width=max(2, int(s * .03)))
    d.rounded_rectangle([s * .56, s * .62, s * .70, s * .82], radius=s * .03, fill=WOOD_D)
    # scaffolding
    for fx in (.14, .86):
        d.line([(s * fx, s * .42), (s * fx, s * .86)], fill=METAL, width=max(2, int(s * .035)))
    for fy in (.56, .74):
        d.line([(s * .14, s * fy), (s * .86, s * fy)], fill=METAL, width=max(2, int(s * .028)))
    # wrench
    d.line([(s * .60, s * .40), (s * .78, s * .24)], fill=GREY_L, width=max(3, int(s * .055)))
    d.ellipse([s * .74, s * .18, s * .88, s * .32], fill=GREY_L)
    d.ellipse([s * .775, s * .215, s * .845, s * .285], fill=(86, 92, 110))


def sc_truck(d, s):
    """Ride the Lightning: a pickup under a lightning strike."""
    _skyline(d, s, (44, 50, 74), .74)
    _ground(d, s, .80, (64, 72, 92), (42, 48, 64))
    _glow(d, s * .56, s * .22, s * .22, (108, 116, 178))
    d.polygon([(s * .58, s * .04), (s * .36, s * .40), (s * .52, s * .40),
               (s * .42, s * .66), (s * .74, s * .30), (s * .57, s * .30)],
              fill=BOLT)
    d.polygon([(s * .58, s * .04), (s * .44, s * .28), (s * .52, s * .28)], fill=BOLT_D)
    # flatbed + cab
    d.rounded_rectangle([s * .10, s * .58, s * .58, s * .78], radius=s * .05, fill=WOOD_D)
    d.rounded_rectangle([s * .10, s * .58, s * .58, s * .66], radius=s * .04, fill=WOOD)
    d.polygon([(s * .58, s * .50), (s * .78, s * .50), (s * .90, s * .68),
               (s * .58, s * .68)], fill=WOOD)
    d.polygon([(s * .62, s * .53), (s * .76, s * .53), (s * .84, s * .65),
               (s * .62, s * .65)], fill=GLASS)
    d.rectangle([s * .10, s * .72, s * .90, s * .80], fill=WOOD_D)
    d.ellipse([s * .86, s * .60, s * .94, s * .68], fill=BOLT)
    for cx in (.24, .74):
        d.ellipse([s * (cx - .10), s * .74, s * (cx + .10), s * .94], fill=(34, 36, 46))
        d.ellipse([s * (cx - .045), s * .795, s * (cx + .045), s * .885], fill=GREY_D)


def sc_balloon(d, s):
    """Retrieve the Data: a gored balloon lifting a transmitter."""
    d.ellipse([s * .06, s * .10, s * .40, s * .20], fill=(56, 62, 96))
    d.ellipse([s * .64, s * .18, s * .96, s * .28], fill=(56, 62, 96))
    _glow(d, s * .50, s * .34, s * .30, (70, 78, 124), steps=4)
    _striped_ellipse(d, s * .50, s * .34, s * .25, s * .27, CREAM, ORANGE, gores=6)
    # neck tapering to the basket
    d.polygon([(s * .40, s * .54), (s * .60, s * .54), (s * .55, s * .66),
               (s * .45, s * .66)], fill=ORANGE_D)
    d.line([(s * .43, s * .63), (s * .40, s * .74)], fill=GREY_D, width=max(2, int(s * .016)))
    d.line([(s * .57, s * .63), (s * .60, s * .74)], fill=GREY_D, width=max(2, int(s * .016)))
    # transmitter crate
    d.rounded_rectangle([s * .36, s * .72, s * .64, s * .90], radius=s * .045, fill=METAL)
    d.rounded_rectangle([s * .36, s * .72, s * .64, s * .78], radius=s * .035, fill=GREY_L)
    d.ellipse([s * .43, s * .795, s * .57, s * .875], fill=GLASS)
    d.ellipse([s * .465, s * .82, s * .535, s * .855], fill=(40, 120, 160))
    d.line([(s * .50, s * .72), (s * .50, s * .60)], fill=GREY_L, width=max(2, int(s * .016)))
    d.ellipse([s * .465, s * .565, s * .535, s * .635], fill=RED)

def sc_radar(d, s):
    """Build the Radar: a dish sweeping signal arcs."""
    _hills(d, s, (52, 66, 88), .74)
    _ground(d, s, .82)
    d.pieslice([s * .10, s * .18, s * .70, s * .78], 205, 345, fill=GREY_L)
    d.pieslice([s * .18, s * .26, s * .62, s * .70], 205, 345, fill=GREY)
    d.line([(s * .40, s * .52), (s * .40, s * .86)], fill=GREY_D, width=max(3, int(s * .055)))
    d.polygon([(s * .26, s * .88), (s * .54, s * .88), (s * .48, s * .80),
               (s * .32, s * .80)], fill=GREY_D)
    for r in (.16, .25, .34):
        d.arc([s * (.66 - r), s * (.34 - r), s * (.66 + r), s * (.34 + r)],
              295, 65, fill=GLASS, width=max(2, int(s * .028)))
    d.ellipse([s * .62, s * .30, s * .70, s * .38], fill=BOLT)


def sc_storm(d, s):
    """Fight / Trap the Storm: a funnel under a charged cloud."""
    _ground(d, s, .86, (56, 58, 86), (38, 40, 62))
    _glow(d, s * .50, s * .34, s * .40, PURPLE_D, steps=5)
    # funnel
    d.polygon([(s * .24, s * .40), (s * .76, s * .40), (s * .60, s * .88),
               (s * .44, s * .88)], fill=PURPLE)
    d.polygon([(s * .30, s * .42), (s * .54, s * .42), (s * .53, s * .86),
               (s * .46, s * .86)], fill=PURPLE_L)
    for i, (yy, ww) in enumerate(((.50, .20), (.62, .15), (.74, .10))):
        d.arc([s * (.50 - ww), s * (yy - .045), s * (.50 + ww), s * (yy + .045)],
              0, 360, fill=PURPLE_D if i % 2 else PURPLE_L,
              width=max(2, int(s * .022)))
    # cloud
    d.ellipse([s * .10, s * .18, s * .56, s * .46], fill=PURPLE)
    d.ellipse([s * .38, s * .10, s * .92, s * .44], fill=PURPLE_L)
    d.ellipse([s * .22, s * .22, s * .64, s * .46], fill=PURPLE_L)
    d.rectangle([s * .18, s * .32, s * .88, s * .44], fill=PURPLE)
    d.polygon([(s * .72, s * .44), (s * .58, s * .70), (s * .69, s * .58),
               (s * .60, s * .58)], fill=BOLT)

def sc_bomb(d, s):
    """Deliver the Bomb: a payload on a cart with a lit fuse."""
    _skyline(d, s, (48, 52, 70), .74)
    _ground(d, s, .82)
    d.ellipse([s * .16, s * .38, s * .70, s * .90], fill=(52, 54, 70))
    d.ellipse([s * .24, s * .44, s * .46, s * .62], fill=(88, 92, 112))
    d.rectangle([s * .54, s * .30, s * .66, s * .44], fill=GREY_D)
    d.line([(s * .62, s * .32), (s * .84, s * .14)], fill=WOOD_L,
           width=max(2, int(s * .035)))
    _glow(d, s * .86, s * .12, s * .12, ORANGE_D, steps=4)
    d.ellipse([s * .81, s * .07, s * .91, s * .17], fill=BOLT)


def sc_rescue(d, s):
    """Rescue the Survivors: a caged survivor signalling with a flare."""
    _hills(d, s, (48, 66, 62), .76)
    _ground(d, s, .84)
    _glow(d, s * .50, s * .30, s * .26, (210, 150, 60), steps=4)
    # flare
    d.ellipse([s * .455, s * .16, s * .545, s * .25], fill=BOLT)
    d.line([(s * .50, s * .25), (s * .50, s * .36)], fill=BOLT_D, width=max(2, int(s * .022)))
    # cage
    d.rounded_rectangle([s * .22, s * .38, s * .78, s * .86], radius=s * .06,
                        fill=(52, 58, 78), outline=GREY_D, width=max(2, int(s * .022)))
    # survivor inside
    d.ellipse([s * .43, s * .46, s * .57, s * .60], fill=CREAM)
    d.rounded_rectangle([s * .38, s * .62, s * .62, s * .84], radius=s * .07, fill=CREAM)
    for bx in (.32, .43, .54, .65):
        d.line([(s * bx, s * .40), (s * bx, s * .84)], fill=GREY,
               width=max(2, int(s * .022)))
    d.line([(s * .22, s * .60), (s * .78, s * .60)], fill=GREY_D,
           width=max(2, int(s * .018)))

SCENES = (
    (re.compile(r"evacuate", re.I), sc_shelter),
    (re.compile(r"repair the shelter", re.I), sc_repair),
    (re.compile(r"ride the lightning", re.I), sc_truck),
    (re.compile(r"retrieve|retrive|data|balloon|launch", re.I), sc_balloon),
    (re.compile(r"radar", re.I), sc_radar),
    (re.compile(r"storm|category", re.I), sc_storm),
    (re.compile(r"bomb|dtb|deliver", re.I), sc_bomb),
    (re.compile(r"rescue|survivor", re.I), sc_rescue),
    (re.compile(r"encampment|eliminate", re.I), sc_storm),
    (re.compile(r"refuel|homebase", re.I), sc_repair),
)


def mission_scene(name: str):
    for pattern, drawer in SCENES:
        if pattern.search(name or ""):
            return drawer
    return sc_storm


# --------------------------------------------------------------------------
# Art names. Each entry lists the file names tried, first hit wins, so an art
# pack may use any of them. Missing files fall back to the drawn version.
# --------------------------------------------------------------------------
SCENE_SLUGS = (
    (re.compile(r"evacuate", re.I), ["evacuate"]),
    (re.compile(r"repair the shelter", re.I), ["repair", "repair_shelter"]),
    (re.compile(r"resupply|supply drop", re.I), ["resupply"]),
    (re.compile(r"rocket", re.I), ["rocket"]),
    (re.compile(r"ride the lightning", re.I), ["lightning", "van", "rtl"]),
    (re.compile(r"retrieve|retrive|data", re.I), ["balloon", "data", "retrieve"]),  # game icon = balloon
    (re.compile(r"balloon|launch", re.I), ["balloon", "data"]),
    (re.compile(r"radar", re.I), ["radar"]),
    (re.compile(r"encampment", re.I), ["encampments", "encampment", "camps"]),
    (re.compile(r"eliminate", re.I), ["eliminate", "eac"]),
    (re.compile(r"trap the storm", re.I), ["trap_storm", "storm", "atlas"]),
    (re.compile(r"survive the storm", re.I), ["survive", "survive_the_storm", "storm"]),
    (re.compile(r"storm|category", re.I), ["storm", "atlas"]),
    (re.compile(r"bomb|dtb|deliver", re.I), ["bomb", "deliver", "dtb"]),
    (re.compile(r"rescue|survivor", re.I), ["rescue"]),
    (re.compile(r"refuel|homebase", re.I), ["refuel", "refuel_homebase", "homebase"]),
    (re.compile(r"titan", re.I), ["titan", "hunt_the_titan", "hunt"]),
)

# (pattern on "raw id | display name", art names, drawer, default colour)
# Order matters: specific before general ("Epic Perk-Up" before "Epic").
_C = {
    "vbucks": (86, 170, 255), "perk": (160, 110, 240), "reperk": (230, 120, 60),
    "amp": (250, 210, 70), "fire": (245, 120, 50), "frost": (110, 200, 245),
    "water": (70, 150, 245), "nature": (110, 200, 90),
    "evo": (150, 110, 235), "xp": (120, 210, 120), "gold": (245, 190, 60),
    "candy": (240, 110, 170), "person": (240, 150, 60), "hero": (240, 150, 60),
    "vxp": (60, 210, 200), "sxp": (245, 160, 70), "schxp": (90, 160, 245),
    "hxp": (240, 90, 90),
    "def": (240, 150, 60), "schem": (90, 170, 240), "trap": (90, 170, 240),
}


def ic_lead(d, x, y, s, c):
    ic_person(d, x, y + s * .06, s * .94, c)
    d.polygon(_star_points(x + s * .80, y + s * .20, s * .20, s * .09), fill=BOLT)


def ic_amp(d, x, y, s, c):
    """Amp-Up: disc with a lightning bolt."""
    d.ellipse([x + s * .06, y + s * .06, x + s * .94, y + s * .94], fill=c)
    d.polygon([(x + s * .56, y + s * .16), (x + s * .30, y + s * .54), (x + s * .48, y + s * .54),
               (x + s * .40, y + s * .86), (x + s * .70, y + s * .44), (x + s * .52, y + s * .44)],
              fill=WHITE)


def ic_fire(d, x, y, s, c):
    """Fire-Up: disc with a flame."""
    d.ellipse([x + s * .06, y + s * .06, x + s * .94, y + s * .94], fill=c)
    d.polygon([(x + s * .50, y + s * .14), (x + s * .70, y + s * .46), (x + s * .72, y + s * .66),
               (x + s * .50, y + s * .84), (x + s * .28, y + s * .66), (x + s * .32, y + s * .46),
               (x + s * .42, y + s * .56)], fill=WHITE)
    d.ellipse([x + s * .42, y + s * .56, x + s * .58, y + s * .76], fill=BOLT)


def ic_frost(d, x, y, s, c):
    """Frost-Up: disc with a snowflake."""
    d.ellipse([x + s * .06, y + s * .06, x + s * .94, y + s * .94], fill=c)
    w = max(2, int(s * .08))
    cx, cy, r = x + s * .5, y + s * .5, s * .30
    for a in (90, 30, 150):
        dx, dy = r * math.cos(math.radians(a)), r * math.sin(math.radians(a))
        d.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=WHITE, width=w)


def ic_up(d, x, y, s, c):
    """Perk-Up family: a disc with a double chevron."""
    d.ellipse([x + s * .06, y + s * .06, x + s * .94, y + s * .94], fill=c)
    w = max(2, int(s * .11))
    for dy in (.10, -.10):
        d.line([(x + s * .30, y + s * (.58 + dy)), (x + s * .50, y + s * (.38 + dy)),
                (x + s * .70, y + s * (.58 + dy))], fill=WHITE, width=w)


def ic_reperk(d, x, y, s, c):
    """RE-PERK: a disc with a circular arrow."""
    d.ellipse([x + s * .06, y + s * .06, x + s * .94, y + s * .94], fill=c)
    w = max(2, int(s * .10))
    d.arc([x + s * .26, y + s * .26, x + s * .74, y + s * .74], 30, 320, fill=WHITE, width=w)
    d.polygon([(x + s * .70, y + s * .22), (x + s * .80, y + s * .46),
               (x + s * .56, y + s * .42)], fill=WHITE)


def ic_bottle(d, x, y, s, c):
    d.rounded_rectangle([x + s * .40, y + s * .06, x + s * .60, y + s * .24],
                        radius=max(1, int(s * .04)), fill=_darken(c, .7))
    d.ellipse([x + s * .16, y + s * .26, x + s * .84, y + s * .96], fill=c)
    d.polygon([(x + s * .56, y + s * .34), (x + s * .38, y + s * .64),
               (x + s * .52, y + s * .64), (x + s * .44, y + s * .88),
               (x + s * .66, y + s * .54), (x + s * .52, y + s * .54)], fill=BOLT)


def ic_eye(d, x, y, s, c):
    d.ellipse([x + s * .04, y + s * .24, x + s * .96, y + s * .76], fill=c)
    d.ellipse([x + s * .32, y + s * .28, x + s * .68, y + s * .72], fill=WHITE)
    d.ellipse([x + s * .42, y + s * .38, x + s * .58, y + s * .62], fill=_darken(c, .5))


def ic_shard(d, x, y, s, c):
    d.polygon([(x + s * .50, y + s * .04), (x + s * .80, y + s * .40),
               (x + s * .50, y + s * .96), (x + s * .20, y + s * .40)], fill=c)
    d.polygon([(x + s * .50, y + s * .04), (x + s * .80, y + s * .40),
               (x + s * .50, y + s * .50)], fill=_lighten(c, .35))


def ic_flux(d, x, y, s, c):
    pts = [(x + s * (.50 + .44 * math.cos(math.radians(a))),
            y + s * (.50 + .44 * math.sin(math.radians(a)))) for a in range(-90, 270, 60)]
    d.polygon(pts, fill=c)
    d.ellipse([x + s * .36, y + s * .36, x + s * .64, y + s * .64], fill=_lighten(c, .45))


def ic_book(d, x, y, s, c):
    d.rounded_rectangle([x + s * .14, y + s * .10, x + s * .86, y + s * .92],
                        radius=max(2, int(s * .08)), fill=c)
    d.rectangle([x + s * .14, y + s * .10, x + s * .28, y + s * .92], fill=_darken(c, .7))
    d.line([(x + s * .38, y + s * .36), (x + s * .76, y + s * .36)], fill=WHITE, width=2)


def ic_candy(d, x, y, s, c):
    d.polygon([(x + s * .04, y + s * .30), (x + s * .30, y + s * .50),
               (x + s * .04, y + s * .70)], fill=_darken(c, .8))
    d.polygon([(x + s * .96, y + s * .30), (x + s * .70, y + s * .50),
               (x + s * .96, y + s * .70)], fill=_darken(c, .8))
    d.ellipse([x + s * .24, y + s * .26, x + s * .76, y + s * .74], fill=c)
    d.arc([x + s * .32, y + s * .34, x + s * .68, y + s * .66], 200, 340, fill=WHITE,
          width=max(1, int(s * .07)))


def ic_xp(d, x, y, s, c):
    ic_star(d, x, y, s, c)


REWARD_KINDS = (
    (re.compile(r"v[\s_\-]?bucks|mtxswap", re.I), ["vbucks"], ic_gem, "vbucks"),
    (re.compile(r"re-?perk|alteration_generic", re.I), ["reperk", "perk"], ic_reperk, "reperk"),
    (re.compile(r"amp-?up|alteration_ele_nature|ele_energy", re.I), ["ampup", "amp_up", "perk"], ic_amp, "amp"),
    (re.compile(r"fire-?up|ele_fire", re.I), ["fireup", "fire_up", "perk"], ic_fire, "fire"),
    (re.compile(r"frost-?up|ele_water", re.I), ["frostup", "frost_up", "perk"], ic_frost, "frost"),
    (re.compile(r"perk-?up|alteration_upgrade|\bperk\b", re.I), ["perkup", "perk"], ic_up, "perk"),
    (re.compile(r"lightning in a bottle|reagent_c_t02", re.I), ["lightning_bottle", "material"], ic_bottle, "evo"),
    (re.compile(r"eye of the storm|reagent_c_t03", re.I), ["eye_storm", "material"], ic_eye, "evo"),
    (re.compile(r"storm shard|reagent_c_t04", re.I), ["storm_shard", "material"], ic_shard, "evo"),
    (re.compile(r"pure drop|drop of rain|reagent_c_t01", re.I), ["pure_drop", "material"], ic_drop, "water"),
    (re.compile(r"flux|evolverarity", re.I), ["flux", "material"], ic_flux, "evo"),
    (re.compile(r"training manual|reagent_people", re.I), ["manual", "material"], ic_book, "evo"),
    (re.compile(r"trap designs|reagent_traps", re.I), ["trap_designs", "trap", "designs", "material"], ic_book, "schem"),
    (re.compile(r"designs|reagent_weapons", re.I), ["weapon_designs", "designs", "material"], ic_book, "schem"),
    (re.compile(r"venture\s*xp|phoenixxp", re.I), ["venture_xp", "xp"], ic_xp, "vxp"),
    (re.compile(r"survivor\s*xp|personnelxp", re.I), ["survivor_xp", "xp"], ic_xp, "sxp"),
    (re.compile(r"schematic\s*xp|schematicxp", re.I), ["schematic_xp", "schematic", "xp"], ic_xp, "schxp"),
    (re.compile(r"hero\s*xp|heroxp", re.I), ["hero_xp", "xp"], ic_xp, "hxp"),
    (re.compile(r"\bxp\b|experience", re.I), ["xp"], ic_xp, "xp"),
    (re.compile(r"candy", re.I), ["candy", "gold"], ic_candy, "candy"),
    (re.compile(r"\bgold\b|eventcurrency_scaling|coin", re.I), ["gold"], ic_coin, "gold"),
    (re.compile(r"ticket|voucher", re.I), ["ticket", "gold"], ic_coin, "gold"),
    (re.compile(r"\blead\b|manager", re.I), ["lead", "survivor"], ic_lead, "person"),
    (re.compile(r"survivor|worker", re.I), ["survivor"], ic_person, "person"),
    (re.compile(r"defender|\bdid_", re.I), ["defender"], ic_shield, "def"),
    (re.compile(r"\bhero\b|\bhid_", re.I), ["hero"], ic_hero, "hero"),
    (re.compile(r"sid_(?:floor|wall|ceiling)_|\btrap\b", re.I), ["trap", "schematic"], ic_trap, "trap"),
    (re.compile(r"schematic|\bsid_|weapon", re.I), ["schematic"], ic_blueprint, "schem"),
)

# Every art name the renderer looks for (for docs / the installer comment).
ART_NAMES = sorted({n for _, names in SCENE_SLUGS for n in names} | {"background"}) + \
    sorted({f"rewards/{n}" for _, names, _, _ in REWARD_KINDS for n in names}) + \
    [f"weekly/{k}" for k in ("weapon", "hero", "survivor", "trap", "defender", "core")]


def reward_kind(text: str):
    """(art names, drawer, colour) for a reward, matched on raw id + name."""
    for pattern, names, drawer, colour in REWARD_KINDS:
        if pattern.search(text or ""):
            return names, drawer, _C[colour]
    return [], ic_dot, SLATE


_TIER_WORD = re.compile(r"\b(mythic|legendary|epic|rare|uncommon|common)\b", re.I)
_TIER_ID = (("_sr", "legendary"), ("_vr", "epic"), ("_uc", "uncommon"),
            ("_r", "rare"), ("_c", "common"))


def rarity_of(text: str) -> str:
    """"Epic Perk-Up!" / "reagent_alteration_upgrade_vr" -> "epic"."""
    m = _TIER_WORD.search(text or "")
    if m:
        return m.group(1).lower()
    raw = (text or "").split("|")[0].strip().lower()
    for suffix, tier in _TIER_ID:
        if raw.endswith(suffix) or f"{suffix}_" in raw:
            return tier
    return ""


def scene_names(name: str) -> list:
    """Art names for a mission; Category N storms try atlas_N first."""
    names = list(_slug(SCENE_SLUGS, name, []))
    m = re.search(r"category\s*(\d)", name or "", re.I)
    if m:
        names = [f"atlas_{m.group(1)}"] + names
    elif re.search(r"fight the storm", name or "", re.I):
        names = names + ["atlas_1"]
    return names


def _slug(table, name, default):
    for pattern, slug in table:
        if pattern.search(name or ""):
            return slug
    return default


def _scene_plate(size, name):
    """Draw at 3x and downsample: cheap anti-aliasing for the curves."""
    custom = art(scene_names(name), size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1],
                                           radius=max(6, size // 7), fill=255)
    if custom is not None:
        plate = Image.new("RGB", (size, size), NIGHT_BOT)
        plate.paste(custom, (0, 0), custom)
        return plate, mask
    scale = 3
    big = _vgrad(size * scale, NIGHT_TOP, NIGHT_BOT)
    mission_scene(name)(ImageDraw.Draw(big), size * scale)
    return big.resize((size, size), Image.LANCZOS), mask


_RARITY_TINTED = {_C[k] for k in ("person", "evo", "perk", "schem", "trap")}


def _icon(text: str, size: int, colour=None):
    """RGBA reward icon: art pack file if present, else drawn at 3x.
    Rarity only tints items/materials; Amp-Up, Gold, XP… keep their colour."""
    names, drawer, default = reward_kind(text)
    if default not in _RARITY_TINTED:
        colour = None
    if names and names[0] in ("perkup", "flux"):
        tier = rarity_of(text)
        if tier:
            names = [f"{tier}_{names[0]}"] + names
    custom = art(names, size, "rewards")
    if custom is not None:
        return custom
    big = Image.new("RGBA", (size * 3, size * 3), (0, 0, 0, 0))
    drawer(ImageDraw.Draw(big), 0, 0, size * 3, colour or default)
    return big.resize((size, size), Image.LANCZOS)


def _bolt(d, x, y, s, c):
    d.polygon([(x + s * .62, y), (x + s * .18, y + s * .56), (x + s * .46, y + s * .56),
               (x + s * .34, y + s), (x + s * .82, y + s * .40), (x + s * .52, y + s * .40)],
              fill=c)


# ==========================================================================
# Compact list layout (one row per mission, rewards as icon chips)
# ==========================================================================
CREAM_T = (245, 240, 228)
DIM = (178, 172, 208)
EDGE = (84, 72, 140)
BG_PAGE = (26, 22, 46)
ROW_FILL = (24, 20, 50, 228)
ROW_EDGE = (126, 108, 214, 230)
VB_FILL = (92, 22, 150, 235)
VB_EDGE = (214, 150, 255, 255)
ZONE_H = 48
ICON_A, LINE_A = 40, 50     # alert reward icon / line height
ICON_B, LINE_B = 26, 34     # basic reward icon / line height


ZONE_ART = (
    (re.compile(r"stonewood", re.I), ["stonewood", "sw"]),
    (re.compile(r"plankerton", re.I), ["plankerton", "pl"]),
    (re.compile(r"canny", re.I), ["canny_valley", "canny", "cv"]),
    (re.compile(r"twine", re.I), ["twine_peaks", "twine", "tp"]),
)


def zone_art(zone: str, size: int):
    """zones/<name>.png for a zone; Ventures zones try their own name first."""
    names = _slug(ZONE_ART, zone, None)
    if names is None:
        first = re.sub(r"\s*venture\s*zone\s*", "", zone or "", flags=re.I)
        names = [first, zone, "ventures", "venture"]
    return art(names, size, "zones")


def _short(label: str, limit: int = 18) -> str:
    return label if len(label) <= limit else label[:limit - 1] + "…"


def _reward_label(item: str) -> str:
    label = split_rarity(item)[0].replace("!", "").strip()
    return re.sub(r"\bXp\b", "XP", label)


def _background(w: int, h: int, accent) -> "Image.Image":
    """art/background.png (cover-cropped) or a drawn storm-night backdrop."""
    custom = None
    for name in ("background", "bg"):
        path = ART_DIR / f"{name}.png"
        if path.is_file():
            try:
                custom = Image.open(path).convert("RGB")
                break
            except Exception:
                log.debug("bad background %s", path, exc_info=True)
    if custom is not None:
        scale = max(w / custom.width, h / custom.height)
        custom = custom.resize((int(custom.width * scale) + 1, int(custom.height * scale) + 1),
                               Image.LANCZOS)
        left, top = (custom.width - w) // 2, (custom.height - h) // 2
        bg = custom.crop((left, top, left + w, top + h)).convert("RGBA")
        shade = Image.new("RGBA", (w, h), (12, 10, 26, 120))
        return Image.alpha_composite(bg, shade)

    bg = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(bg)
    top, bot = (22, 20, 52), (46, 22, 70)
    for y in range(h):
        r = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * r) for a, b in zip(top, bot)))
    # soft glows
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    for cx, cy, rad, col in ((w * .85, 60, 320, (130, 70, 220)),
                             (w * .10, h * .55, 360, (40, 120, 200)),
                             (w * .70, h * .95, 300, (170, 60, 190))):
        for i in range(12, 0, -1):
            rr = rad * i / 12
            g.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=col + (int(9 * (13 - i) / 12),))
    # faint grid + deterministic star specks, blended on their own layer
    specks = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(specks)
    for x in range(0, w, 48):
        d.line([(x, 0), (x, h)], fill=(160, 140, 255, 14))
    for y in range(0, h, 48):
        d.line([(0, y), (w, y)], fill=(160, 140, 255, 14))
    seed = 1234567
    for _ in range(int(w * h / 9000)):
        seed = (seed * 1103515245 + 12345) & 0x7fffffff
        x = seed % w
        seed = (seed * 1103515245 + 12345) & 0x7fffffff
        y = seed % h
        d.point((x, y), fill=(255, 255, 255, 110))
    return Image.alpha_composite(Image.alpha_composite(bg, glow), specks)


def _layout_row(draw, m, x0, limit, fonts):
    """Place every reward of a mission; chips wrap to new lines, never cut.

    Returns (ops, height). Alert chips: icon + quantity + full name.
    Basic rewards: smaller icon + full name on their own line(s).
    """
    f_qty, f_name, f_basic = fonts
    ops, y = [], 50
    rewards = m.get("rewards") or []
    alert = [r for r in rewards if not r.get("basic")]
    basic = [r for r in rewards if r.get("basic")]

    cx = x0
    for r in alert:
        raw_name = str(r.get("item", "Item"))
        label, rarity = split_rarity(raw_name)
        label = _safe(_reward_label(raw_name), 40)
        qty = int(r.get("qty") or 1)
        qty_txt = f"{qty:,} " if qty > 1 else ""
        need = ICON_A + 10 + draw.textlength(qty_txt, font=f_qty) \
            + draw.textlength(label, font=f_name) + 26
        if cx + need > limit and cx > x0:
            cx, y = x0, y + LINE_A
        ops.append(("alert", r, raw_name, rarity, qty_txt, label, cx, y))
        cx += need
    if not alert:
        ops.append(("none", None, "", None, "", "-", cx, y))
    y += LINE_A

    if basic:
        cx, seen = x0, set()
        for r in basic:
            label = _safe(_reward_label(str(r.get("item", ""))), 40)
            if not label or label in seen:
                continue
            seen.add(label)
            qty = int(r.get("qty") or 1)
            if qty > 1:
                label = f"{qty:,} {label}"
            need = ICON_B + 8 + draw.textlength(label, font=f_basic) + 24
            if cx + need > limit and cx > x0:
                cx, y = x0, y + LINE_B
            ops.append(("basic", r, "", None, "", label, cx, y))
            cx += need
        y += LINE_B
    return ops, max(y + 10, 124)


def _title_parts(title: str):
    """"Reward Finder  (3/3)" -> ("Reward Finder", "(3/3)")."""
    m = re.match(r"^(.*?)\s*(\(\d+/\d+\))\s*$", title)
    return (m.group(1), m.group(2)) if m else (title, "")


W, PAD, BADGE, TOP = 1280, 20, 92, 104
X0 = PAD + 16 + BADGE + 18
LIMIT = W - PAD - 14


def _fonts():
    return (_font(20, True), _font(18, True), _font(15))


def _measure(missions, zone_icons=True):
    """[(entry), ...] and the bottom y of the last row."""
    probe = ImageDraw.Draw(Image.new("RGB", (4, 4)))
    fonts = _fonts()
    y, last_zone, plan = TOP, None, []
    for index, m in enumerate(missions):
        zone = _safe(m.get("zone", ""), 40).upper()
        if zone != last_zone:
            zicon = zone_art(m.get("zone", ""), 30) if zone_icons else None
            plan.append(("zone", zone, y, zicon))
            y += ZONE_H
            last_zone = zone
        ops, h = _layout_row(probe, m, X0, LIMIT, fonts)
        plan.append(("row", m, y, index, ops, h))
        y += h + 10
    return plan, y


def split_pages(missions: list[dict]) -> list[list[dict]]:
    """Missions spread evenly over pictures: about MIN_CARDS + 1 per picture,
    never fewer than MIN_CARDS (no 4 + 1 split). MAX_CARDS is kept when it
    can be without breaking the minimum (7 missions with max 6 -> one picture)."""
    n = len(missions)
    if n == 0:
        return []
    lo, hi = max(1, MIN_CARDS), max(1, MAX_CARDS, MIN_CARDS)
    pages = -(-n // (lo + 1))
    while pages > 1 and n // pages < lo:
        pages -= 1
    while -(-n // pages) > hi and n // (pages + 1) >= lo:
        pages += 1
    size, extra = divmod(n, pages)
    out, start = [], 0
    for i in range(pages):
        end = start + size + (1 if i < extra else 0)
        out.append(missions[start:end])
        start = end
    return out


def _render(missions, title, kind, footer, hidden):
    accent = ACCENTS.get(kind, ACCENTS["vbucks"])[0]
    f_title = _font(32, True)
    f_zone = _font(17, True)
    f_name = _font(21, True)
    f_dim = _font(17)
    f_small = _font(14)
    f_qty, f_rew, f_basic = _fonts()
    x0, limit = X0, LIMIT

    plan, y = _measure(missions)
    note = footer or ""
    height = y + PAD - 4 + (26 if note else 0)

    canvas = _background(W, height, accent)
    layer = Image.new("RGBA", (W, height), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    # title banner
    ld.rounded_rectangle([PAD, 16, W - PAD, 86], radius=18, fill=(14, 12, 34, 225),
                         outline=accent + (255,), width=3)
    ld.rounded_rectangle([PAD + 6, 22, W - PAD - 6, 80], radius=14,
                         outline=accent + (70,), width=1)
    for entry in plan:
        if entry[0] == "zone":
            _, zone, zy, zicon = entry
            shift = 38 if zicon is not None else 0
            zw = ld.textlength(zone, font=f_zone) + shift
            ld.rounded_rectangle([PAD, zy + 4, PAD + zw + 30, zy + 40], radius=18,
                                 fill=(14, 12, 34, 230), outline=accent + (235,), width=2)
            continue
        _, m, ry, index, ops, h = entry
        has_vb = any(r.get("key") == "vbucks" for r in (m.get("rewards") or [])
                     if not r.get("basic"))
        ld.rounded_rectangle([PAD, ry, W - PAD, ry + h], radius=16,
                             fill=VB_FILL if has_vb else ROW_FILL,
                             outline=VB_EDGE if has_vb else ROW_EDGE, width=2)
        # badge well
        by = ry + (h - BADGE) // 2
        ld.rounded_rectangle([PAD + 14, by - 2, PAD + 18 + BADGE, by + BADGE + 2], radius=18,
                             fill=(10, 8, 26, 235), outline=ROW_EDGE[:3] + (120,), width=1)
    ld.rounded_rectangle([6, 6, W - 7, height - 7], radius=20, outline=ROW_EDGE, width=2)

    image = Image.alpha_composite(canvas, layer)
    draw = ImageDraw.Draw(image)

    # title: bolt + text, page counter in the accent colour
    main, count = _title_parts(_safe(title, 60))
    gap = 12 if count else 0
    tw = draw.textlength(main, font=f_title) + gap + draw.textlength(count, font=f_title)
    tx = (W - tw - 44) / 2
    _bolt(draw, tx, 32, 34, BOLT)
    tx += 44
    draw.text((tx, 32), main, font=f_title, fill=CREAM_T)
    if count:
        draw.text((tx + draw.textlength(main, font=f_title) + gap, 32), count,
                  font=f_title, fill=accent)

    for entry in plan:
        if entry[0] == "zone":
            _, zone, zy, zicon = entry
            shift = 38 if zicon is not None else 0
            if zicon is not None:
                image.paste(zicon, (PAD + 12, zy + 7), zicon)
            draw.text((PAD + 15 + shift, zy + 12), zone, font=f_zone, fill=accent)
            continue
        _, m, y, index, ops, h = entry
        plate, mask = _scene_plate(BADGE, m.get("name", ""))
        image.paste(plate, (PAD + 16, y + (h - BADGE) // 2), mask)

        x = x0
        power = m.get("power") or 0
        if power:
            _bolt(draw, x, y + 12, 22, BOLT)
            draw.text((x + 28, y + 12), str(power), font=f_name, fill=CREAM_T)
            x += 28 + draw.textlength(str(power), font=f_name) + 16
        name = _safe(m.get("name", ""), 60)
        biome = _safe(m.get("biome", ""), 40)
        draw.text((x, y + 12), name, font=f_name, fill=CREAM_T)
        if biome:
            nx = x + draw.textlength(name, font=f_name)
            draw.text((nx, y + 15), _fit(draw, f"  -  {biome}", f_dim, max(40, limit - nx)),
                      font=f_dim, fill=DIM)

        for kind_, r, raw_name, rarity, qty_txt, label, cx, oy in ops:
            cy = y + oy
            if kind_ == "none":
                draw.text((cx, cy + 10), label, font=f_dim, fill=DIM)
            elif kind_ == "alert":
                ico = _icon(f"{r.get('raw', '')} | {raw_name}", ICON_A, rarity)
                image.paste(ico, (int(cx), cy), ico)
                tx = cx + ICON_A + 10
                if qty_txt:
                    draw.text((tx, cy + 10), qty_txt, font=f_qty, fill=CREAM_T)
                    tx += draw.textlength(qty_txt, font=f_qty)
                draw.text((tx, cy + 11), label, font=f_rew, fill=rarity or DIM)
            else:
                ico = _icon(f"{r.get('raw', '')} | {r.get('item', '')}", ICON_B)
                image.paste(ico, (int(cx), cy), ico)
                draw.text((cx + ICON_B + 8, cy + 5), label, font=f_basic, fill=DIM)

    if note:
        draw.text((PAD, height - 32), _fit(draw, _safe(note, 120), f_small, W - 2 * PAD),
                  font=f_small, fill=DIM)
    buffer = io.BytesIO()
    image.convert("RGB").save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


# ==========================================================================
# Weekly reward card
# ==========================================================================
WEEKLY_DRAWN = {
    "weapon": (ic_blueprint, (90, 170, 240)), "hero": (ic_hero, (240, 150, 60)),
    "survivor": (ic_person, (240, 150, 60)), "trap": (ic_trap, (90, 170, 240)),
    "defender": (ic_shield, (240, 150, 60)), "core": (ic_reperk, (230, 120, 60)),
}
WEEKLY_ART_NAMES = {"weapon": ["weapon", "schematic"], "core": ["core", "core_reperk", "reperk", "perk"],
                    "hero": ["hero"], "survivor": ["survivor"], "trap": ["trap"],
                    "defender": ["defender"]}
WEEKLY_REWARD_ART = {"weapon": ["schematic"], "hero": ["hero"], "survivor": ["survivor"],
                     "trap": ["trap"], "defender": ["defender"], "core": ["reperk", "perk"]}


def render_weekly(label: str, *, key: str = "", title: str = "This Week's Reward",
                  footer: str | None = None) -> bytes | None:
    """Weekly reward card in the same style as the mission pictures:
    title banner, one framed row with the art in a badge well."""
    if not available() or not label:
        return None
    try:
        accent = AMBER
        ICON = 220
        f_title, f_label = _font(32, True), _font(44, True)
        f_sub, f_small = _font(19), _font(16, True)
        probe = ImageDraw.Draw(Image.new("RGB", (4, 4)))

        tx = PAD + 16 + ICON + 16 + 36
        words, lines, cur = _safe(label, 48).split(), [], ""
        for w in words:
            trial = f"{cur} {w}".strip()
            if probe.textlength(trial, font=f_label) > W - PAD - 30 - tx and cur:
                lines.append(cur)
                cur = w
            else:
                cur = trial
        lines.append(cur)

        row_top = TOP
        row_h = max(ICON + 32, 56 * len(lines) + 120)
        H = row_top + row_h + PAD + 6

        canvas = _background(W, H, accent)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ld.rounded_rectangle([PAD, 16, W - PAD, 86], radius=18, fill=(14, 12, 34, 225),
                             outline=accent + (255,), width=3)
        ld.rounded_rectangle([PAD + 6, 22, W - PAD - 6, 80], radius=14,
                             outline=accent + (70,), width=1)
        ld.rounded_rectangle([PAD, row_top, W - PAD, row_top + row_h], radius=16,
                             fill=ROW_FILL, outline=ROW_EDGE, width=2)
        iy = row_top + (row_h - ICON) // 2
        ld.rounded_rectangle([PAD + 14, iy - 4, PAD + 18 + ICON, iy + ICON + 4], radius=22,
                             fill=(10, 8, 26, 235), outline=accent + (200,), width=2)
        ld.rounded_rectangle([6, 6, W - 7, H - 7], radius=20, outline=ROW_EDGE, width=2)
        image = Image.alpha_composite(canvas, layer)
        draw = ImageDraw.Draw(image)

        t = _safe(title, 50)
        bw = draw.textlength(t, font=f_title)
        bx = (W - bw - 44) / 2
        _bolt(draw, bx, 32, 34, BOLT)
        draw.text((bx + 44, 32), t, font=f_title, fill=CREAM_T)

        pic = art(WEEKLY_ART_NAMES.get(key, [key]), ICON - 16, "weekly") if key else None
        if pic is None and key:
            pic = art(WEEKLY_REWARD_ART.get(key, []), ICON - 16, "rewards")
        if pic is None:
            drawer, colour = WEEKLY_DRAWN.get(key, (ic_star, BOLT))
            size = ICON - 16
            big = Image.new("RGBA", (size * 3, size * 3), (0, 0, 0, 0))
            drawer(ImageDraw.Draw(big), size * .3, size * .3, size * 2.4, colour)
            pic = big.resize((size, size), Image.LANCZOS)
        mask = Image.new("L", pic.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, pic.size[0] - 1, pic.size[1] - 1],
                                               radius=16, fill=255)
        alpha = pic.getchannel("A") if pic.mode == "RGBA" else None
        if alpha is not None:
            from PIL import ImageChops
            mask = ImageChops.multiply(mask, alpha)
        image.paste(pic, (PAD + 24, iy + 8), mask)

        block_h = 56 * len(lines) + 34 + (40 if footer else 0)
        ty = row_top + (row_h - block_h) // 2
        for line in lines:
            draw.text((tx, ty), line, font=f_label, fill=BOLT)
            ty += 56
        draw.text((tx, ty + 6), "Complete 10 mission alerts in a 160+ zone",
                  font=f_sub, fill=DIM)
        if footer:
            chip = _safe(footer, 60)
            cw = draw.textlength(chip, font=f_small)
            cy = ty + 44
            draw.rounded_rectangle([tx, cy, tx + cw + 28, cy + 30], radius=15,
                                   fill=(14, 12, 34), outline=accent, width=2)
            draw.text((tx + 14, cy + 6), chip, font=f_small, fill=accent)

        buffer = io.BytesIO()
        image.convert("RGB").save(buffer, format="PNG", optimize=True)
        return buffer.getvalue()
    except Exception:
        log.exception("weekly rendering failed")
        return None
IMAGE_PY_EOF

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

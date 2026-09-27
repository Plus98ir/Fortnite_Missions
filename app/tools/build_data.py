#!/usr/bin/env python3
"""Build app/data/data.json (+ icons) with the Telegram bot's own code.

The three bot modules are taken straight out of install_fortnite_bot.sh, so
the app shows exactly what the bot shows: same lists, same Top Missions
ranking, same filter matching, same icons (art pack or the bot's drawings).

The art pack is the bot's art.zip (latest release by default), unpacked with
the installer's own unpacker; the background is copied next to the data.

usage: python app/tools/build_data.py [--installer PATH] [--art-zip PATH|URL] [--out app/data]
Env (optional): SEASON_START_UTC, SEASON_END_UTC, WEEKLY_URL2, TOP_PER_ZONE, ART_URL.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # repo root
APP = ROOT / "app"
MODULES = (("vbucks_scraper.py", "SCRAPER_PY_EOF"),
           ("vbucks_image.py", "IMAGE_PY_EOF"),
           ("vbucks_bot.py", "BOT_PY_EOF"))
# Icons are rendered at 2x the size the app shows them, for sharp phones.
ART_URL = "https://github.com/Plus98ir/Fortnite_Missions/releases/latest/download/art.zip"
SCENE_PX, ALERT_PX, BASIC_PX, ZONE_PX, WEEKLY_PX = 184, 80, 52, 60, 440


def extract_modules(installer: Path, dest: Path) -> None:
    text = installer.read_text(encoding="utf-8")
    for name, tag in MODULES:
        start = text.index(f"<<'{tag}'\n") + len(f"<<'{tag}'\n")
        end = text.index(f"\n{tag}\n", start)
        (dest / name).write_text(text[start:end] + "\n", encoding="utf-8")


def unpack_art(installer: Path, source: str, work: Path) -> Path:
    """art.zip -> work/art with the same code fnbot-art runs on servers."""
    text = installer.read_text(encoding="utf-8")
    start = text.index("<<'ART_PY_EOF'\n") + len("<<'ART_PY_EOF'\n")
    script = work / "unpack_art.py"
    script.write_text(text[start:text.index("\nART_PY_EOF\n", start)] + "\n", encoding="utf-8")
    zpath = work / "art.zip"
    if re.match(r"https?://", source):
        with urllib.request.urlopen(source, timeout=120) as r:
            zpath.write_bytes(r.read())
    else:
        shutil.copy(source, zpath)
    art = work / "art"
    art.mkdir()
    res = subprocess.run([sys.executable, str(script), str(zpath), str(art), "1"],
                         capture_output=True, text=True)
    print("art:", (res.stdout or res.stderr).strip())
    return art


class Icons:
    """Writes each distinct PNG once, named by its content hash."""

    def __init__(self, out: Path) -> None:
        self.dir = out / "icons"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.used: set[str] = set()
        self.memo: dict = {}

    def save(self, image) -> str:
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        data = buffer.getvalue()
        name = hashlib.sha1(data).hexdigest()[:14] + ".png"
        path = self.dir / name
        if not path.exists():
            path.write_bytes(data)
        self.used.add(name)
        return f"data/icons/{name}"

    def prune(self) -> None:
        for path in self.dir.glob("*.png"):
            if path.name not in self.used:
                path.unlink()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--installer", default=str(ROOT / "install_fortnite_bot.sh"))
    ap.add_argument("--out", default=str(APP / "data"))
    ap.add_argument("--art-zip", default=os.environ.get("ART_URL") or ART_URL)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    work = Path(tempfile.mkdtemp(prefix="fnapp-"))
    extract_modules(Path(args.installer), work)
    data_dir = work / "state"
    data_dir.mkdir()
    override = APP / "weekly-override.json"      # same file /setweekly writes
    if override.is_file():
        shutil.copy(override, data_dir / "weekly-override.json")
    art_dir = unpack_art(Path(args.installer), args.art_zip, work)
    os.environ.update({
        "DATA_DIR": str(data_dir), "CACHE_DIR": str(data_dir),
        "ART_DIR": str(art_dir), "LOG_LEVEL": "WARNING",
    })
    sys.path.insert(0, str(work))
    import vbucks_scraper as src          # noqa: E402
    import vbucks_image as vimg           # noqa: E402
    import vbucks_bot as bot              # noqa: E402
    from PIL import Image                 # noqa: E402

    if not vimg.available():
        # The bot needs DejaVu fonts only for text; icons do not use them,
        # but available() gates rendering. Point it at any TTF we can find.
        for d in ("/usr/share/fonts/truetype/dejavu", str(APP / "tools" / "fonts")):
            if os.path.isdir(d):
                vimg.FONT_DIRS = (d,) + tuple(vimg.FONT_DIRS)
    icons = Icons(out)

    # ---- missions --------------------------------------------------------
    everything = src.fetch_all_missions()
    lists = {
        "vbucks": src.fetch_vbucks_missions(),
        "p160": src.fetch_power_missions(160),
        "v140": src.fetch_venture_missions(140),
        "all": everything,
        "top": bot.top_missions(everything),
    }

    def mkey(m: dict) -> str:
        return json.dumps([m["zone"], m["name"], m["biome"], m["power"],
                           m["alert"], m["basic"]], sort_keys=True)

    def tags(r: dict) -> list[str]:
        text = f"{r.get('raw', '')} | {r.get('item', '')}"
        return [name for name, pattern in bot.REWARD_FILTERS if pattern.search(text)]

    def reward_icon(r: dict, size: int, rarity) -> str:
        text = f"{r.get('raw', '')} | {r.get('item', '')}"
        names, drawer, _ = vimg.reward_kind(text)
        key = (tuple(names), drawer.__name__, rarity, size, vimg.rarity_of(text))
        if key not in icons.memo:
            icons.memo[key] = icons.save(vimg._icon(text, size, rarity))
        return icons.memo[key]

    def scene_icon(name: str) -> str:
        key = ("scene", tuple(vimg.scene_names(name)), vimg.mission_scene(name).__name__)
        if key not in icons.memo:
            plate, mask = vimg._scene_plate(SCENE_PX, name)
            rgba = plate.convert("RGBA")
            rgba.putalpha(mask)
            icons.memo[key] = icons.save(rgba)
        return icons.memo[key]

    def colour_hex(c) -> str | None:
        return "#%02x%02x%02x" % tuple(c) if c else None

    def reward(r: dict, basic: bool) -> dict:
        label, rarity = vimg.split_rarity(str(r.get("item", "")))
        out = {
            "l": vimg._reward_label(str(r.get("item", ""))),
            "q": int(r.get("qty") or 1),
            "i": reward_icon(r, BASIC_PX if basic else ALERT_PX, None if basic else rarity),
            "e": bot.reward_emoji(r),
            "t": tags(r),
            "raw": str(r.get("item", "")),
        }
        if not basic:
            out["c"] = colour_hex(rarity)
            out["vb"] = bool(src.VBUCKS_RE.search(str(r.get("raw", ""))))
        return out

    index: dict[str, int] = {}
    missions: list[dict] = []
    zones: dict[str, dict] = {}
    for m in [m for group in lists.values() for m in group]:
        k = mkey(m)
        if k in index:
            continue
        index[k] = len(missions)
        alert = [reward(r, False) for r in m.get("alert") or []]   # source order
        missions.append({
            "z": m["zone"], "zk": bot.zone_key(m["zone"]), "n": m["name"],
            "b": m.get("biome", ""), "p": m.get("power", 0),
            "s": scene_icon(m["name"]), "e": bot.mission_icon(m["name"]),
            "a": alert, "k": [reward(r, True) for r in m.get("basic") or []],
        })
        if m["zone"] not in zones:
            zicon = vimg.zone_art(m["zone"], ZONE_PX)
            zones[m["zone"]] = {"key": bot.zone_key(m["zone"]),
                                "i": icons.save(zicon) if zicon is not None else None}

    # ---- weekly ----------------------------------------------------------
    weekly = None
    try:
        value = src.get_weekly()
        label, key, current = bot.weekly_parts(value)
        if label:
            pic = vimg.art(vimg.WEEKLY_ART_NAMES.get(key, [key]), WEEKLY_PX, "weekly") if key else None
            if pic is None and key:
                pic = vimg.art(vimg.WEEKLY_REWARD_ART.get(key, []), WEEKLY_PX, "rewards")
            if pic is None:
                drawer, colour = vimg.WEEKLY_DRAWN.get(key, (vimg.ic_star, vimg.BOLT))
                big = Image.new("RGBA", (WEEKLY_PX * 3, WEEKLY_PX * 3), (0, 0, 0, 0))
                from PIL import ImageDraw
                drawer(ImageDraw.Draw(big), WEEKLY_PX * .3, WEEKLY_PX * .3, WEEKLY_PX * 2.4, colour)
                pic = big.resize((WEEKLY_PX, WEEKLY_PX), Image.LANCZOS)
            upper = label.upper()
            weekly = {
                "label": label, "key": key, "current": bool(current),
                "week": value.get("week", "") if isinstance(value, dict) else "",
                "icon": icons.save(pic),
                "e": next((s for n, s in bot.WEEKLY_ICONS if n in upper), "🚀"),
            }
    except Exception as exc:                               # keep the missions
        print(f"weekly reward unavailable: {exc}", file=sys.stderr)

    # ---- season ----------------------------------------------------------
    start, end = bot.battlepass_window()
    season = {
        "bpStart": start.isoformat() if start else None,
        "bpEnd": end.isoformat() if end else None,
        "ventures": [{"name": c["name"], "start": list(c["start"]), "end": list(c["end"])}
                     for c in bot.VENTURE_CYCLES],
    }

    background = None
    for name in ("background", "bg"):
        src_bg = art_dir / f"{name}.png"
        if src_bg.is_file():
            raw = src_bg.read_bytes()
            ext = "jpg" if raw[:2] == bytes([0xFF, 0xD8]) else "webp" if raw[8:12] == b"WEBP" else "png"
            background = f"bg-{hashlib.sha1(raw).hexdigest()[:10]}.{ext}"
            if not (out / background).exists():
                for old in out.glob("bg-*"):
                    old.unlink()
                (out / background).write_bytes(raw)
            break
    doc = {
        "schema": 1,
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "day": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "missions": missions,
        "lists": {name: [index[mkey(m)] for m in group] for name, group in lists.items()},
        "zones": zones,
        "zoneOrder": ["Stonewood", "Plankerton", "Canny Valley", "Twine Peaks", "Ventures", "Other"],
        "filterZones": list(bot.ZONES),
        "filterRewards": list(bot.REWARD_NAMES),
        "rarityFilters": sorted(bot.RARITY_FILTERS, key=bot.REWARD_NAMES.index),
        "topPerZone": bot.TOP_PER_ZONE,
        "weekly": weekly,
        "season": season,
        "background": f"data/{background}" if background else None,
    }
    target = out / "data.json"
    try:                         # same content as last run: keep the old file
        old = json.loads(target.read_text(encoding="utf-8"))
        unchanged = {k: v for k, v in old.items() if k != "generated"} ==             {k: v for k, v in doc.items() if k != "generated"}
    except (OSError, ValueError):
        unchanged = False
    if not unchanged:
        target.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    icons.prune()
    print(f"missions={len(missions)} vbucks={len(lists['vbucks'])} p160={len(lists['p160'])} "
          f"v140={len(lists['v140'])} top={len(lists['top'])} icons={len(icons.used)} "
          f"weekly={weekly['label'] if weekly else None}")
    return 0 if missions else 1


if __name__ == "__main__":
    sys.exit(main())

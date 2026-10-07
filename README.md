<p align="center">
  <a href="https://Plus98ir.github.io">
    <img src="https://img.shields.io/badge/Website-Plus98ir.github.io-blue?style=for-the-badge&logo=google-chrome" alt="Web Page">
  </a>
</p>

# 🤖 Fortnite STW Missions — Telegram Bot

| **🇺🇸 English** | [🇮🇷 فارسی](README.fa.md) |
| --- | --- |

A Telegram bot for **Fortnite: Save the World** that tracks **V-Bucks missions,
Power 160 missions, Ventures 140 missions, the best missions of the day, the
weekly reward and the season countdowns. It answers in English or Persian, as
text or as ready-made pictures.

> [!IMPORTANT]
> **Terms of use:** this is a free, open-source bot for **personal use only**.
> It is **not for sale** and must not be sold or used commercially.
> Fortnite, its names, icons and artwork are the property of **Epic Games, Inc.**
> This project is not affiliated with or endorsed by Epic Games.
> **You install and use it at your own risk and responsibility.**
> The installer asks you to accept these terms before it installs anything.

---

## 📋 Features

| | |
| --- | --- |
| 💎 **V-Bucks missions** | Every daily mission that pays V-Bucks, with the amount and power level. |
| ⚡ **Power 160 missions** | Endgame missions with full alert and basic reward lists. |
| 🌴 **Ventures 140 missions** | Ventures-only missions at power 140. **Dungeons are excluded.** |
| 🔥 **Top Missions** | The best missions of every zone, ranked by value: V-Bucks, X-Ray, Mythic and Legendary items, Legendary Perk-Up and Flux. |
| 🔎 **Reward Finder** | Search all zones for the reward types, rarities and zones you pick. |
| 🖼 **Image mode** | Lists as clean pictures with mission and reward icons, 5–6 missions per picture, sent as an album. Or switch to plain text. |
| 🛠 **Weekly reward** | Which Supercharger or Core RE-PERK this week's reset grants, with an admin override if the source is late. |
| ⏱ **Season timers** | Battle Pass and Ventures countdowns with a progress bar. |
| 🔔 **Automatic alerts** | Daily push 1 minute after the reset, weekly push 2 minutes after it. Every user can turn them off. |
| 🌐 **Bilingual** | Full English and Persian interface, switchable per user. |
| 👑 **Admin panel** | Stats, broadcast, ban/unban, CSV export and import, cache refresh, weekly override, update check. |
| 🎨 **Art pack** | Every icon and the background can be replaced with your own PNGs. |

---

## 📱 App (Android / iPhone) — v2.0.0

The same missions, Top Missions, Reward Finder, weekly reward and season
timers as the bot, as an app — no Telegram needed:

- **Any phone or browser:** open
  [plus98ir.github.io/Fortnite_Missions/app](https://plus98ir.github.io/Fortnite_Missions/app/)
  and choose **Add to Home screen** (Android: Chrome menu · iPhone: Safari share
  button). It then opens full screen and also works offline.
- **Android APK:** download `FortniteMissions-v2.0.0.apk` from the
  [app release](https://github.com/Plus98ir/Fortnite_Missions/releases/tag/app-v2.0.0)
  and install it (allow "install unknown apps" once).

The data is rebuilt every day right after the 00:00 UTC reset by GitHub
Actions, using the bot's own code, so the app and the bot always show the
same lists. The app asks you to accept the terms of use on first start.

---

## ⚙️ Step 1 — Get a bot token

1. Open Telegram and search for **@BotFather**.
2. Send `/newbot`.
3. Pick a display name for your bot.
4. Pick a unique username ending in `bot` or `_bot` (e.g. `FortniteAlertsBot`).
5. Copy the HTTP API token.

You also need your **numeric chat ID** for the admin account — send
`/start` to [@userinfobot](https://t.me/userinfobot) to get it.

> ⚠️ **Keep your token private.** Never commit it or post it publicly. If it
> leaks, revoke it immediately with `/revoke` in BotFather.

---

## 🚀 Step 2 — Install

On a Debian or Ubuntu server, as root:

```bash
bash <(curl -fsSL https://github.com/Plus98ir/Fortnite_Missions/releases/latest/download/install_fortnite_bot.sh)
```

The installer first shows the **terms of use** and continues only if you type
`yes`. It then asks for your bot token, your admin chat ID and (optionally) a
proxy, and does everything else: system packages, a dedicated service account,
a Python virtualenv, the configuration file, the art pack and a sandboxed
systemd service.

Before starting the service it tests whether Telegram is reachable, so you
find out immediately whether the problem is your token or your network.

**To upgrade**, run `fnbot update` (or press **Update** in the admin panel).
Your configuration, users and your own art are kept.

---

## 🖥 Managing the bot

A helper command is installed as `fnbot`:

```bash
fnbot status        # is it running?
fnbot logs          # follow the live log
fnbot errors        # only the error lines
fnbot test          # check Telegram connectivity, direct and via proxy
fnbot config        # edit the configuration, then restart automatically
fnbot update        # install the latest release, keep config and users
fnbot art [--force] # re-download the art pack
fnbot version
fnbot restart
fnbot uninstall     # remove the service (config and users are kept)
```

---

## 🔧 Configuration

Everything lives in `/etc/fortnite_bot/bot.env` (mode `0640`). Edit it with
`fnbot config`; the service restarts by itself when you save.

| Setting | Default | Meaning |
| --- | --- | --- |
| `BOT_TOKEN` | — | Your BotFather token. |
| `ADMIN_CHAT_ID` | — | Numeric chat ID of the admin. |
| `PROXY_URL` | empty | e.g. `socks5://user:pass@127.0.0.1:1080`. Leave empty for a direct connection. |
| `MAX_USERS` | `200` | Capacity limit. Raise it if you host many users. |
| `DEFAULT_LANG` | `en` | `en` or `fa`. |
| `IMAGE_MIN_CARDS` | `5` | Fewest missions per picture; lists are spread evenly (5 + 5, never 4 + 1). |
| `IMAGE_MAX_CARDS` | `10` | Soft cap of missions per picture. |
| `TOP_PER_ZONE` | `5` | How many missions per zone 🔥 Top Missions shows. |
| `ART_DIR` | `/opt/fortnite_bot/art` | Folder with your own icons and background. |
| `ART_URL` | release `art.zip` | Art pack downloaded on install/update. `""` = off. |
| `WEEKLY_URL2` | empty | Optional second source for the weekly reward. |
| `DAILY_RESET_UTC` | `00:01` | Daily alert time (1 minute after the shop reset). |
| `WEEKLY_RESET_UTC` | `00:02` | Weekly alert time (2 minutes after the reset). |
| `WEEKLY_RESET_WEEKDAY` | `3` | 0 = Monday … 3 = Thursday. |
| `SEASON_START_UTC` | — | Current season start, ISO format. |
| `SEASON_END_UTC` | — | Fallback end date if the live lookup fails. |
| `CACHE_SETTLE_MINUTES` | `20` | How long after a reset to keep re-checking for fresh data. |
| `CACHE_SETTLE_TTL` | `300` | Re-check interval, in seconds, inside that window. |
| `LOG_LEVEL` | `INFO` | `DEBUG` for verbose logging. |

> 📅 Update `SEASON_START_UTC` and `SEASON_END_UTC` once per season. The bot
> tries to read the end date live, but these values are the fallback.

---

## 🎨 Art pack

Pictures use the PNGs in `ART_DIR`; anything missing is drawn by the bot.
Layout: `background.png` at the top, mission icons in `scenes/`, reward icons
in `rewards/`, weekly rewards in `weekly/`, zone icons in `zone/`. Names are
matched loosely (`V-Bucks.png` = `v_bucks.png` = `vbucks.png`); the full list
is in the comment above `ART_DIR` in `bot.env`.

- `fnbot art --force` re-downloads `ART_URL` and unpacks it.
- PNGs you replaced by hand are never overwritten.
- Images an older pack installed and the new pack dropped are removed.

> The default icons depict Fortnite items and are the property of Epic Games.
> They are included only so the bot is usable for personal play.

---

## ⚙️ User filters

Each user opens **⚙️ My Filters** (or `/filters`) and picks zones and reward
types (V-Bucks, Survivor, Hero, Defender, Schematic, Trap, Evo Mat, Perk-Up,
Gold, XP) plus a rarity (Legendary, Epic); rarity and type must both match
the same reward. The filters are used by
**🔎 Reward Finder**; the normal lists and the daily alerts always show
everything.

---

## 👑 Admin panel

Press **👑 Admin**, or use the commands directly:

| Command | What it does |
| --- | --- |
| `/stats` | Users, subscribers, banned accounts, users with filters. |
| `/broadcast <text>` | Message every subscriber. A preview with confirm/cancel is shown first. |
| `/cancel` | Abort a pending broadcast. |
| `/ban <id>` / `/unban <id>` | Block or unblock a user. Banned users are ignored silently. |
| `/banned` | List blocked accounts. |
| `/export` | Download a CSV of all users and their settings. |
| `/import` | Restore users — just send the CSV or a `users.json` back to the bot. |
| `/refresh` | Clear the cache and re-fetch on the next request. |
| `/setweekly <weapon\|hero\|survivor\|trap\|defender\|core\|auto>` | Pin this week's reward by hand when the source is wrong. |
| `/update` | Check for a new release and install it. |

Import **merges**: existing users are updated, new ones added, nobody is ever
deleted.

---

## 🗂 Caching

Missions only change at the reset, so the cache is valid **until the next
reset** rather than for a fixed number of minutes:

| Data | Valid until | Stored on disk |
| --- | --- | --- |
| Missions, filtered lists, pictures | next 00:00 UTC | ✅ (missions) |
| Weekly reward | next weekly reset | ✅ |
| Season end date | next day | in memory |

The first request of the day fetches; everyone after that is served instantly.
If a fetch fails, the previous data is served instead of an error.

---

## 🔒 Security

- Runs as a dedicated unprivileged `fnbot` system user, **not root**.
- The token never touches the source files — it lives only in the
  configuration file (`0640`, `root:fnbot`).
- Proxy credentials are URL-encoded and redacted from all logs.
- The systemd unit is sandboxed: `ProtectSystem=strict`, `NoNewPrivileges`,
  an empty capability set and a syscall filter.
- All Telegram output is HTML-escaped, so scraped mission names can't break
  or inject into messages.
- The art pack is unpacked safely: images only, no path escapes, size limits.

---

## 🌐 Proxy — do you need one?

Only if your server cannot reach `api.telegram.org` directly, which in
practice means a server inside Iran. Servers abroad should leave `PROXY_URL`
empty.

The proxy must be reachable **from the server itself**. `127.0.0.1` refers to
that machine, not to your own computer. Check with:

```bash
ss -ltnp | grep <port>
fnbot test
```

---

## ❓ Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `httpx.ConnectError: All connection attempts failed` | Telegram unreachable. Run `fnbot test`; if the direct connection works, clear `PROXY_URL`. |
| Old icons still show after an update | Run `fnbot art --force`. |
| Battle Pass timer shows an error | The live season lookup failed. Set `SEASON_END_UTC` in the config. |
| Weekly reward is wrong | The source is late. Use `/setweekly` to pin the right one. |
| Service restarts in a loop | `fnbot errors` shows the real reason in the last few lines. |

---

## ⚖️ Disclaimer

- This bot is for **personal use** and is **not for sale**.
- Fortnite and all related names, icons and artwork are trademarks and
  property of **Epic Games, Inc.** This project is unofficial and is not
  affiliated with, sponsored or endorsed by Epic Games.
- Mission data comes from third-party community sites
  ([seebot.dev](https://seebot.dev), [fortnitedb.com](https://fortnitedb.com),
  [fortnite.gg](https://fortnite.gg)) and may be late or wrong.
- The software is provided "as is", without warranty. **All responsibility for
  installing and using it is yours.**

No server? You can try my instance: **@plus98vbucks_bot** — I can't promise
how long it stays up.

<p align="center">
  <a href="https://Plus98ir.github.io">
    <img src="https://img.shields.io/badge/Website-Plus98ir.github.io-blue?style=for-the-badge&logo=google-chrome" alt="Web Page">
  </a>
</p>

# 🤖 Fortnite STW Missions — Telegram Bot

| **🇺🇸 English** | [🇮🇷 فارسی](README.fa.md) |
| --- | --- |

A Telegram bot for **Fortnite: Save the World** that tracks V-Bucks missions,
Power 160 missions, Ventures 140 missions, the weekly reward and the season
countdowns — in English and Persian.

---

## 📋 Features

| | |
| --- | --- |
| 💎 **V-Bucks missions** | Every daily mission that pays V-Bucks, with the amount and power level. |
| ⚡ **Power 160 missions** | Endgame missions with full alert and basic reward lists. |
| 🌴 **Ventures 140 missions** | Ventures-only missions at power 140. **Dungeons are excluded.** |
| 🛠 **Weekly reward** | Which Supercharger or Core RE-PERK this week's reset grants. |
| ⏱ **Season timers** | Battle Pass and Ventures countdowns with a progress bar. |
| ⚙️ **Personal filters** | Each user picks their own zones, reward types and minimum V-Bucks. |
| 🔔 **Automatic alerts** | Daily push 1 minute after the reset, weekly push 2 minutes after it. |
| 🌐 **Bilingual** | Full English and Persian interface, switchable per user. |
| 👑 **Admin panel** | Stats, broadcast, ban/unban, CSV export and import, cache refresh. |

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

The installer asks for your bot token, your admin chat ID and (optionally) a
proxy, then does everything else: system packages, a dedicated service
account, a Python virtualenv, the configuration file and a sandboxed systemd
service.

Before starting the service it tests whether Telegram is reachable, so you
find out immediately whether the problem is your token or your network.

**Re-run the same command to upgrade.** Your configuration and your user list
are preserved — just press `Enter` at the first prompt.

---

## 🖥 Managing the bot

A helper command is installed as `fnbot`:

```bash
fnbot status      # is it running?
fnbot logs        # follow the live log
fnbot errors      # only the error lines
fnbot test        # check Telegram connectivity, direct and via proxy
fnbot config      # edit the configuration, then restart automatically
fnbot update
fnbot restart
fnbot uninstall   # remove the service (config and users are kept)
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

## ⚙️ User filters

Each user opens **⚙️ My Filters** (or `/filters`) and picks:

- **Zones** — Stonewood, Plankerton, Canny Valley, Twine Peaks, Other.
- **Rewards** — V-Bucks, Survivor, Hero, Schematic, Evo Mat, Perk-Up.
- **Minimum V-Bucks** — 0, 50 or 100.

Selecting nothing shows everything. Filters apply to the daily alert too, so
every user gets a personalised push. The Ventures list ignores the zone
filter, because Ventures has its own map.

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

Import **merges**: existing users are updated, new ones added, nobody is ever
deleted.

---

## 🗂 Caching

Missions only change at the reset, so the cache is valid **until the next
reset** rather than for a fixed number of minutes:

| Data | Valid until | Stored on disk |
| --- | --- | --- |
| Missions (V-Bucks / 160 / Ventures) | next 00:00 UTC | ✅ |
| Weekly reward | next weekly reset | ✅ |
| Season end date | next day | in memory |

The first request of the day fetches; everyone after that is served instantly.
The disk copy in `/var/lib/fortnite_bot/` survives restarts. If a fetch fails,
the previous data is served instead of an error.

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
- The user database is written atomically with mode `0600`.

### If you fork this repo

Add a `.gitignore` so you never commit live data:

```gitignore
bot.env
users.json
cache-*.json
*.bad
```

---

## 🌐 Proxy — do you need one?

Only if your server cannot reach `api.telegram.org` directly, which in
practice means a server inside Iran. Servers abroad should leave `PROXY_URL`
empty.

The proxy must be reachable **from the server itself**. `127.0.0.1` refers to
that machine, not to your own computer — a common and confusing mistake. Check
with:

```bash
ss -ltnp | grep <port>
fnbot test
```

---

## ❓ Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `httpx.ConnectError: All connection attempts failed` | Telegram unreachable. Run `fnbot test`; if the direct connection works, clear `PROXY_URL`. |
| `TypeError: Defaults.__init__() got an unexpected keyword argument` | An old build. Re-run the installer. |
| Battle Pass timer shows an error | The live season lookup failed. Set `SEASON_END_UTC` in the config. |
| Ventures list is empty | The upstream zone names changed. Adjust `VENTURE_RE` in `vbucks_scraper.py`. |
| Service restarts in a loop | `fnbot errors` shows the real reason in the last few lines. |

---

## 📎 Notes

- No server? You can try my instance: **@plus98vbucks_bot** — I can't promise
  how long it stays up.
- Data sources: [seebot.dev](https://seebot.dev),
  [fortnitedb.com](https://fortnitedb.com), [fortnite.gg](https://fortnite.gg).
- Not affiliated with Epic Games.

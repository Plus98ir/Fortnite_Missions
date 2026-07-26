<div align="center">

# 🤖 Fortnite STW Alert Weekly Reward - V-Bucks Mission's - 160PL Mission Tracker Telegram Bot

A smart, lightweight Telegram bot designed to instantly fetch and notify players about Fortnite Save the World (STW) Weekly Reward & 160PL missions and daily V-Bucks alerts.

**[English](#) | [فارسی (Persian)](README-Fa.md)**

</div>

---

## 🇬🇧 English Documentation

### 📋 Features
* **Real-Time V-Bucks Alerts:** Automatically detects and notifies when daily missions offer V-Bucks.
* **Supercharger Alerts:** Instantly track and get notified when weekly missions or alert resets offer Hero, Survivor, Weapon, or Trap Superchargers.
* **Weekly Rewards:** Never miss out on rare weekly progression items and top-tier upgrades.
* **160 PL Mission Tracker:** Easily check high-tier PL 160 missions, zone modifiers, and supercharger rewards.
* **Interactive Setup Script:** Quick automated installation via a single terminal command, prompting for your Bot Token.
* **Fast & Lightweight:** Built for minimal resource consumption and instant response times.

### ⚙️ Step 1: Get Your Telegram Bot Token
Before installing the bot, you need to create a Telegram bot via BotFather:
1. Open Telegram and search for `@BotFather`.
2. Start a chat and send the command: `/newbot`
3. Follow the prompts to choose a display name for your bot.
4. Choose a unique username ending in `bot` or `_bot` (e.g., `FortniteAlertsBot`).
5. Copy the HTTP API Token provided by BotFather.


> [!WARNING]
> Keep your bot token secure! Do not share it publicly or push it to GitHub.

### 🚀 Step 2: Installation & Configuration
You can easily install and configure the bot using our automated installation script:

```bash
bash <(curl -s https://raw.githubusercontent.com/Sadiqira/Fortnite_Missions/refs/heads/main/setup.sh)

```
**Note: Configuration for Iranian Servers**

If you are hosting the bot on an Iranian server, you will need to configure a proxy. Please follow these steps:

**1. Set the Proxy URL**
Open the bot file using your text editor:
```bash
nano /root/fortnite_bot/vbucks_bot.py
```
Locate the `PROXY_URL` variable, enter your proxy details, and uncomment the line by removing the `#`:
```python
PROXY_URL = "socks5://username:password@127.0.0.1:port"
```

**2. Enable the Proxy in the Application**
Scroll down to the `if __name__ == '__main__':` section and uncomment the following **two** lines to apply the proxy settings:
```python
# Uncomment if proxy is needed:
t_request = HTTPXRequest(proxy=PROXY_URL)
application = ApplicationBuilder().token(TOKEN).request(t_request).get_updates_request(t_request).build()
```
**3. Reboot vbucksbot.service**
```python
systemctl restart vbucksbot.service
```
* **Also**
* If you don't have a server or prefer to skip the installation and setup process, you can use my bot. Just a heads-up, I am not sure how long it will remain active: 
@plus98vbucks_bot

#!/bin/bash

clear
echo "===================================================="
echo "    Fortnite Telegram Bot - Automated Installer     "
echo "===================================================="
echo ""

# Asking for Telegram Bot Token securely
read -s -p "Please enter your Telegram Bot Token: " BOT_TOKEN
echo ""

if [ -z "$BOT_TOKEN" ]; then
    echo "❌ Error: Token cannot be empty. Installation aborted."
    exit 1
fi

echo "[1/5] Updating system packages and installing prerequisites..."
apt update && apt install -y python3 python3-pip python3-requests python3-bs4 git

echo "[2/5] Installing required Python libraries (Telegram, Cloudscraper)..."
pip3 install requests beautifulsoup4 cloudscraper "python-telegram-bot[job-queue]" --break-system-packages

echo "[3/5] Creating bot files in /root/fortnite_bot ..."
mkdir -p /root/fortnite_bot

# Creating vbucks_scraper.py
cat << 'EOF' > /root/fortnite_bot/vbucks_scraper.py
import cloudscraper
from bs4 import BeautifulSoup
import requests
import json

def get_vbucks_missions():
    url = "https://freethevbucks.com/timed-missions/"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
        missions_found = []
        zones = ["STONEWOOD", "PLANKERTON", "CANNY VALLEY", "TWINE PEAKS"]
        current_zone = "Unknown"
        for element in soup.find_all(True):
            if element.name in ['script', 'style', 'nav', 'header', 'footer']:
                continue
            text = element.get_text(separator=" ", strip=True)
            text = " ".join(text.split())
            text_upper = text.upper()
            if len(text) < 25:
                for zone in zones:
                    if zone in text_upper:
                        current_zone = zone.title()
                        break
            if "V-BUCKS" in text_upper and "(X" in text_upper:
                if len(text) < 70:
                    prefix = text_upper.split("V-BUCKS")[0]
                    if any(c.isdigit() for c in prefix):
                        mission_str = f"{current_zone} | {text}"
                        add_new = True
                        for i, existing in enumerate(missions_found):
                            existing_pure = existing.split(" | ")[1]
                            if text in existing_pure:
                                missions_found[i] = mission_str
                                add_new = False
                                break
                            elif existing_pure in text:
                                add_new = False
                                break
                        if add_new:
                            missions_found.append(mission_str)
        final_message = "✅ **Today's V-Bucks Missions:**\n\n"
        if missions_found:
            for mission in list(dict.fromkeys(missions_found)):
                zone_name, rest_of_text = mission.split(" | ")
                rest_of_text = rest_of_text.replace("V-Bucks", "💎 V-Bucks")
                final_message += f"🌍 {zone_name} ⚡ {rest_of_text}\n"
        else:
            final_message += "❌ No V-Bucks missions available today.\n"
        return final_message
    except Exception as e:
        return f"❌ Error fetching V-Bucks: {e}"

def get_160_missions():
    url = "https://seebot.dev/missions.php"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, text/javascript, */*; q=0.01"
    }
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
        json_data = None
        for script in soup.find_all('script'):
            text = script.string
            if text and "powerLevel" in text:
                if "[" in text and "]" in text:
                    start = text.find('[')
                    end = text.rfind(']') + 1
                    try:
                        json_data = json.loads(text[start:end])
                        break
                    except:
                        continue
        missions_found = []
        if json_data:
            for mission in json_data:
                try:
                    pl = int(mission.get("powerLevel", 0))
                except:
                    pl = 0
                if pl == 160:
                    zone = mission.get("zone", "Unknown")
                    name = mission.get("name", "Mission")
                    biome = mission.get("biome", "")
                    rewards_list = []
                    for r in mission.get("missionRewards", []):
                        rewards_list.append(f"▫️ {r.get('itemType')} `x{r.get('quantity')}`")
                    basic_str = "\n   ".join(rewards_list) if rewards_list else "None"
                    alert_list = []
                    for r in mission.get("alertRewards", []):
                        alert_list.append(f"▪️ {r.get('itemType')} `x{r.get('quantity')}`")
                    alert_str = "\n   ".join(alert_list) if alert_list else "None"
                    mission_info = (
                        f"⚡ **Power 160** | 🌍 **{zone}**\n"
                        f"📌 **Type:** `{name}`\n"
                        f"🗺 **Biome:** `{biome}`\n"
                        f"🎁 **Alert Rewards:**\n   {alert_str}\n"
                        f"📦 **Basic Rewards:**\n   {basic_str}\n"
                        f"───────────────────"
                    )
                    missions_found.append(mission_info)
        final_message = "⚡ **Today's Power 160 Missions:**\n\n"
        if missions_found:
            final_message += "\n".join(missions_found)
        else:
            final_message += "❌ No Power 160 missions available today.\n"
        return final_message
    except Exception as e:
        return f"❌ Error fetching 160 missions: {e}"

def get_weekly_superchargers():
    url = "https://fortnitedb.com/"
    scraper = cloudscraper.create_scraper()
    try:
        response = scraper.get(url, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
        
        weekly_found = []
        for element in soup.find_all(True):
            text = element.get_text(separator=" ", strip=True)
            text_upper = text.upper()
            
            if "SUPERCHARGER" in text_upper:
                if len(text) < 60:
                    cleaned_text = text.replace("Weekly Supercharger", "").strip()
                    if not cleaned_text:
                        cleaned_text = text
                    if "SUPERCHARGER" in cleaned_text.upper() or len(cleaned_text) > 3:
                        weekly_found.append(cleaned_text)
                        
        def get_weekly_superchargers():
    url = "https://fortnitedb.com/"
    scraper = cloudscraper.create_scraper()
    try:
        response = scraper.get(url, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
        
        weekly_found = []
        for element in soup.find_all(True):
            text = element.get_text(separator=" ", strip=True)
            text_upper = text.upper()
            
            # جستجو برای سوپرشارژرها و کور ریپرک
            if "SUPERCHARGER" in text_upper or "CORE REPERK" in text_upper or "REPERK" in text_upper:
                if len(text) < 60:
                    cleaned_text = text.replace("Weekly Supercharger", "").strip()
                    if not cleaned_text:
                        cleaned_text = text
                    weekly_found.append(cleaned_text)
                        
        final_message = "🛠 **This Week's Reward:**\n\n"
        valid_items = []
        
        for item in weekly_found:
            item_lower = item.lower()
            if "survivor" in item_lower and "Survivor Supercharger" not in valid_items:
                valid_items.append("Survivor Supercharger")
            elif "hero" in item_lower and "Hero Supercharger" not in valid_items:
                valid_items.append("Hero Supercharger")
            elif "defender" in item_lower and "Defender Supercharger" not in valid_items:
                valid_items.append("Defender Supercharger")
            elif "weapon" in item_lower and "Weapon Supercharger" not in valid_items:
                valid_items.append("Weapon Supercharger")
            elif "core reperk" in item_lower and "Core Reperk" not in valid_items:
                valid_items.append("Core Reperk")
                
        if valid_items:
            for item in valid_items:
                final_message += f"🎁 {item}\n"
        else:
            unique_items = list(dict.fromkeys(weekly_found))
            for item in unique_items[:3]:
                final_message += f"🎁 {item}\n"
            
        return final_message
    except Exception as e:
        return f"❌ Error fetching FortniteDB Weekly: {e}"
EOF

# Creating vbucks_bot.py (with commented proxy)
cat << EOF > /root/fortnite_bot/vbucks_bot.py
import logging
from datetime import time, timezone
from telegram import Update, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, MessageHandler, filters

# Uncomment the line below if you need a proxy:
# from telegram.request import HTTPXRequest

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

TOKEN = "$BOT_TOKEN"

# Proxy settings (commented by default)
# PROXY_URL = "socks5://username:password@127.0.0.1:port"

USER_CHAT_ID = None

from vbucks_scraper import get_vbucks_missions, get_160_missions, get_weekly_superchargers

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    global USER_CHAT_ID
    USER_CHAT_ID = update.effective_chat.id
    
    keyboard = [
        [KeyboardButton("💎 V-Bucks Missions"), KeyboardButton("⚡ Power 160 Missions")],
        [KeyboardButton("🛠 Weekly Reward")]
    ]
    reply_markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)
    welcome_text = (
        "Hello! 🎮\n"
        "Welcome to Fortnite Monitoring Bot By Sadeq Irani.\n"
        "Your chat ID is saved automatically. You will receive notifications here!"
    )
    await update.message.reply_text(welcome_text, reply_markup=reply_markup)

async def message_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    global USER_CHAT_ID
    USER_CHAT_ID = update.effective_chat.id
    text = update.message.text
    
    if text == "💎 V-Bucks Missions":
        await update.message.reply_text("Fetching V-Bucks missions...")
        data = get_vbucks_missions()
        await update.message.reply_text(data, parse_mode="Markdown")
    elif text == "⚡ Power 160 Missions":
        await update.message.reply_text("Fetching Power 160 missions...")
        data = get_160_missions()
        await update.message.reply_text(data, parse_mode="Markdown")
    elif text == "🛠 Weekly Reward":
        await update.message.reply_text("Fetching Weekly Reward...")
        data = get_weekly_superchargers()
        await update.message.reply_text(data, parse_mode="Markdown")

async def daily_reset_notification(context: ContextTypes.DEFAULT_TYPE):
    global USER_CHAT_ID
    if not USER_CHAT_ID:
        return
    try:
        vbucks_data = get_vbucks_missions()
        missions_160_data = get_160_missions()
        message = (
            "🔔 **Fortnite Daily Reset Update!** 🛒\n"
            "-----------------------------------\n\n"
            f"{vbucks_data}\n\n"
            f"{missions_160_data}"
        )
        await context.bot.send_message(chat_id=USER_CHAT_ID, text=message, parse_mode="Markdown")
    except Exception as e:
        print(f"Error in daily notification: {e}")

async def weekly_reset_notification(context: ContextTypes.DEFAULT_TYPE):
    global USER_CHAT_ID
    if not USER_CHAT_ID:
        return
    if context.job.datetime.weekday() == 2:  # Wednesdays
        try:
            weekly_data = get_weekly_superchargers()
            message = (
                "🚨 **Fortnite Weekly Reset & Superchargers!** 🛠\n"
                "-----------------------------------\n\n"
                f"{weekly_data}"
            )
            await context.bot.send_message(chat_id=USER_CHAT_ID, text=message, parse_mode="Markdown")
        except Exception as e:
            print(f"Error in weekly notification: {e}")

if __name__ == '__main__':
    # Uncomment if proxy is needed:
    # t_request = HTTPXRequest(proxy=PROXY_URL)
    # application = ApplicationBuilder().token(TOKEN).request(t_request).get_updates_request(t_request).build()

    application = ApplicationBuilder().token(TOKEN).build()

    job_queue = application.job_queue
    job_queue.run_daily(daily_reset_notification, time=time(hour=0, minute=0, tzinfo=timezone.utc))
    job_queue.run_daily(weekly_reset_notification, time=time(hour=0, minute=0, tzinfo=timezone.utc))

    application.add_handler(CommandHandler("start", start))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, message_handler))

    print("🤖 Telegram Bot is running...")
    application.run_polling()
EOF

echo "[4/5] Setting up Systemd service for permanent execution..."
cat << 'EOF' > /etc/systemd/system/vbucksbot.service
[Unit]
Description=Fortnite Monitoring Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/fortnite_bot
ExecStart=/usr/bin/python3 /root/fortnite_bot/vbucks_bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[5/5] Enabling and starting the service..."
systemctl daemon-reload
systemctl enable vbucksbot.service
systemctl restart vbucksbot.service

echo ""
echo "===================================================="
echo " ✅ Bot installed and running successfully!"
echo " Check status with: systemctl status vbucksbot.service"
echo "===================================================="

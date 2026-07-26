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
                alert_rewards = mission.get("alertRewards", [])
                for r in alert_rewards:
                    item_type = str(r.get("itemType", "")).upper()
                    
                    if "V-BUCKS" in item_type or "VBUCKS" in item_type:
                        zone = mission.get("zone", "Unknown")
                        name = mission.get("name", "Mission")
                        pl = mission.get("powerLevel", 0)
                        qty = r.get("quantity", 50)
                        
                        # انتخاب آیکون فابریک و اختصاصی بر اساس نوع مأموریت (دقیقاً شبیه خود بازی)
                        name_upper = name.upper()
                        if "RIDE THE LIGHTNING" in name_upper:
                            mission_icon = "🚚"
                        elif "CATEGORY" in name_upper or "STORM" in name_upper:
                            mission_icon = "🌀"
                        elif "RETRIVE" in name_upper or "RETRIEVE" in name_upper:
                            mission_icon = "🎈"
                        elif "FIGHT THE STORM" in name_upper:
                            mission_icon = "⛈️"
                        elif "BUILD THE RADAR" in name_upper:
                            mission_icon = "📡"
                        elif "EVACUATE THE SHELTER" in name_upper:
                            mission_icon = "🏠"
                        elif "REPAIR THE SHELTER" in name_upper:
                            mission_icon = "🛠️"
                        elif "DTB" in name_upper or "BOMB" in name_upper:
                            mission_icon = "💣"
                        else:
                            mission_icon = "🎯"
                        
                        # چینش کامل و خط به خط مورد علاقه شما همراه با آیکون اختصاصی
                        mission_str = (
                            f"🌍 **{zone}**\n"
                            f"{mission_icon} `{name}`\n"
                            f"⚡ Power {pl}\n"
                            f"💎 {qty} V-Bucks\n"
                            f"───────────────────"
                        )
                        missions_found.append(mission_str)
                        
        final_message = "✅ **Today's V-Bucks Missions:**\n\n"
        if missions_found:
            for mission in missions_found:
                final_message += f"{mission}\n"
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
                    
                    # تعیین آیکون فابریک بر اساس نوع مأموریت ۱۶۰
                    name_upper = name.upper()
                    if "RIDE THE LIGHTNING" in name_upper:
                        mission_icon = "🚚"
                    elif "CATEGORY" in name_upper or "STORM" in name_upper:
                        mission_icon = "🌀"
                    elif "RETRIEVE" in name_upper:
                        mission_icon = "🎈"
                    elif "FIGHT THE STORM" in name_upper:
                        mission_icon = "⛈️"
                    elif "DTB" in name_upper or "BOMB" in name_upper:
                        mission_icon = "💣"
                    else:
                        mission_icon = "⚡"

                    rewards_list = []
                    for r in mission.get("missionRewards", []):
                        rewards_list.append(f"▫️ {r.get('itemType')} `x{r.get('quantity')}`")
                    basic_str = "\n   ".join(rewards_list) if rewards_list else "None"
                    
                    alert_list = []
                    for r in mission.get("alertRewards", []):
                        alert_list.append(f"▪️ {r.get('itemType')} `x{r.get('quantity')}`")
                    alert_str = "\n   ".join(alert_list) if alert_list else "None"
                    
                    # فرمت‌دهی چندخطی، مرتب و هماهنگ با وی‌باکس‌ها
                    mission_info = (
                        f"🌍 **{zone}**\n"
                        f"{mission_icon} `{name}`\n"
                        f"⚡ Power {pl}\n"
                        f"🗺 Biome: `{biome}`\n"
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

# Creating vbucks_bot.py (Max 200 users, no photo)
cat << 'EOF' > /root/fortnite_bot/vbucks_bot.py
import logging
import json
import os
from datetime import time, timezone
from telegram import Update, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, MessageHandler, filters

# Uncomment the line below if you need a proxy:
# from telegram.request import HTTPXRequest

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

# Proxy settings (commented by default)
# PROXY_URL = "socks5://username:password@127.0.0.1:port"

USERS_FILE = "/root/fortnite_bot/users.json"
MAX_USERS = 200

from vbucks_scraper import get_vbucks_missions, get_160_missions, get_weekly_superchargers

def load_users():
    if os.path.exists(USERS_FILE):
        with open(USERS_FILE, "r") as f:
            return set(json.load(f))
    return set()

def save_user(chat_id):
    users = load_users()
    if chat_id not in users:
        # ذخیره نهایتاً 200 کاربر
        if len(users) >= MAX_USERS:
            return
        users.add(chat_id)
        with open(USERS_FILE, "w") as f:
            json.dump(list(users), f)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    save_user(chat_id)
    
    keyboard = [
        [KeyboardButton("💎 V-Bucks Missions"), KeyboardButton("⚡ Power 160 Missions")],
        [KeyboardButton("🛠 Weekly Reward")]
    ]
    reply_markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)
    welcome_text = (
        "An easy way to get daily V-Bucks, PL 160 missions, and weekly reward information for high-level STW players.\n\n"
        "Your chat ID is saved automatically. You will receive daily and weekly notifications here!"
    )
    
    await update.message.reply_text(welcome_text, reply_markup=reply_markup)

async def message_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    save_user(chat_id)
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
    users = load_users()
    if not users:
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
        for chat_id in users:
            try:
                await context.bot.send_message(chat_id=chat_id, text=message, parse_mode="Markdown")
            except Exception as e:
                print(f"Failed to send daily notification to {chat_id}: {e}")
    except Exception as e:
        print(f"Error in daily notification data fetch: {e}")

async def weekly_reset_notification(context: ContextTypes.DEFAULT_TYPE):
    users = load_users()
    if not users:
        return
    if context.job.datetime.weekday() == 2:  # Wednesdays
        try:
            weekly_data = get_weekly_superchargers()
            message = (
                "🚨 **Fortnite Weekly Reset & Superchargers!** 🛠\n"
                "-----------------------------------\n\n"
                f"{weekly_data}"
            )
            for chat_id in users:
                try:
                    await context.bot.send_message(chat_id=chat_id, text=message, parse_mode="Markdown")
                except Exception as e:
                    print(f"Failed to send weekly notification to {chat_id}: {e}")
        except Exception as e:
            print(f"Error in weekly notification data fetch: {e}")

if __name__ == '__main__':
    # Uncomment if proxy is needed:
    # t_request = HTTPXRequest(proxy=PROXY_URL)
    # application = ApplicationBuilder().token("YOUR_TOKEN_PLACEHOLDER").request(t_request).get_updates_request(t_request).build()

    import os
    TOKEN = os.environ.get("BOT_TOKEN", "YOUR_TOKEN_PLACEHOLDER")
    
    application = ApplicationBuilder().token(TOKEN).build()

    job_queue = application.job_queue
    job_queue.run_daily(daily_reset_notification, time=time(hour=0, minute=1, tzinfo=timezone.utc))
    job_queue.run_daily(weekly_reset_notification, time=time(hour=0, minute=1, tzinfo=timezone.utc))

    application.add_handler(CommandHandler("start", start))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, message_handler))

    print("🤖 Telegram Bot is running...")
    application.run_polling()
EOF

# Injecting the dynamically read token into the file securely
sed -i "s/YOUR_TOKEN_PLACEHOLDER/$BOT_TOKEN/g" /root/fortnite_bot/vbucks_bot.py


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

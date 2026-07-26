read -p "لطفاً توکن ربات تلگرام خود را وارد کنید (مثلاً 123456:ABC-DEF...): " BOT_TOKEN && apt update && apt install python3-requests python3-bs4 -y && pip3 install requests beautifulsoup4 python-telegram-bot --break-system-packages && cat << 'EOF' > /root/vbucks_scraper.py
import requests
import json
from bs4 import BeautifulSoup

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
EOF

cat << EOF > /root/vbucks_bot.py
import logging
from telegram import Update, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import ApplicationBuilder, ContextTypes, CommandHandler, MessageHandler, filters

# اگر خواستی در آینده پروکسی را فعال کنی، این کامنت‌ها را بردار:
# from telegram.request import HTTPXRequest

# تنظیمات لاگ‌گیری
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

# توکن ربات تلگرام (توسط اسکریپت نصب به صورت خودکار وارد شد)
TOKEN = "$BOT_TOKEN"

# تنظیمات پروکسی (فعلا کامنت است)
# PROXY_URL = "socks5://5oir1q2j:8wiogugrlggs@127.0.0.1:45248"

from vbucks_scraper import get_vbucks_missions, get_160_missions

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    keyboard = [
        [KeyboardButton("💎 V-Bucks Missions"), KeyboardButton("⚡ Power 160 Missions")]
    ]
    reply_markup = ReplyKeyboardMarkup(keyboard, resize_keyboard=True)
    welcome_text = (
        "Hello! 🎮\n"
        "Welcome to Fortnite Monitoring Bot By Sadeq Irani.\n"
        "Please select an option below:"
    )
    await update.message.reply_text(welcome_text, reply_markup=reply_markup)

async def message_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = update.message.text
    if text == "💎 V-Bucks Missions":
        await update.message.reply_text("Fetching V-Bucks missions...")
        data = get_vbucks_missions()
        await update.message.reply_text(data, parse_mode="Markdown")
    elif text == "⚡ Power 160 Missions":
        await update.message.reply_text("Fetching Power 160 missions...")
        data = get_160_missions()
        await update.message.reply_text(data, parse_mode="Markdown")

if __name__ == '__main__':
    # حالت پروکسی (برای استفاده بعدی کافیست کامنت این بخش را بردارید و خط زیر را فعال کنید):
    # t_request = HTTPXRequest(proxy=PROXY_URL)
    # application = ApplicationBuilder().token(TOKEN).request(t_request).get_updates_request(t_request).build()

    # حالت مستقیم (فعلی)
    application = ApplicationBuilder().token(TOKEN).build()

    application.add_handler(CommandHandler("start", start))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, message_handler))

    print("🤖 Telegram Bot is running...")
    application.run_polling()
EOF

cat << 'EOF' > /etc/systemd/system/vbucksbot.service
[Unit]
Description=Fortnite Monitoring Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/vbucks_bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vbucksbot.service
systemctl restart vbucksbot.service
echo "✅ نصب با موفقیت انجام شد و ربات در حال اجراست!"

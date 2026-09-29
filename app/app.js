/* Fortnite Missions app v2.0.0 — same lists, ranking and filters as the bot.
 * data/data.json is built daily by app/tools/build_data.py with the bot's code. */
(function () {
  "use strict";

  var VERSION = "2.0.0";
  var DATA_URL = "data/data.json";

  // ---- strings: the bot's own wording (HTML stripped) -------------------
  var S = {
    en: {
      brand: "Fortnite Missions", brand_sub: "Save the World", langBtn: "فارسی", back: "Back",
      nav_home: "Home", nav_vbucks: "V-Bucks", nav_160: "Power 160", nav_top: "Top", nav_finder: "Finder",
      hero_title: "Daily Missions", hero_sub: "{} missions from Stonewood to Ventures — refreshed at every reset.",
      stat_all: "All missions", stat_160: "Power 160", stat_top: "Top picks",
      sec_today: "Today", sec_missions: "Missions", vb_today: "V-Bucks today", vb_none: "No V-Bucks missions today.",
      weekly_short: "Weekly reward",
      d_days: "Days", d_hours: "Hours", d_min: "Min", d_sec: "Sec",
      btn_vbucks: "💎 V-Bucks Missions", btn_160: "⚡ Power 160 Missions", btn_v140: "🌴 Ventures 140 Missions",
      btn_top: "🔥 Top Missions", btn_finder: "🔎 Reward Finder", btn_weekly: "🛠 Weekly Reward",
      btn_timer: "⏱ Season Timers", btn_filters: "⚙️ My Filters",
      mode_cards: "🖼 Image mode", mode_text: "📝 Text mode",
      vbucks_title: "💎 Today's V-Bucks Missions", p160_title: "⚡ Today's Power 160 Missions",
      v140_title: "🌴 Ventures — Power 140 Missions", top_title: "🔥 Top Missions",
      finder_title: "🔎 Reward Finder — all zones", top_zone: "🔥 Top — {}",
      vbucks_none: "❌ No V-Bucks missions available today.",
      p160_none: "❌ No Power 160 missions available today.",
      v140_none: "❌ No Ventures 140 missions today (dungeons excluded).",
      top_none: "❌ No notable missions today.",
      finder_none: "❌ No mission in any zone has the rewards you picked today.",
      finder_need: "🔎 Pick at least one reward in ⚙️ My Filters first — the finder then searches every mission in every zone (Stonewood → Twine Peaks and Ventures).",
      open_filters: "⚙️ Open My Filters",
      none: "None",
      weekly_title: "🛠 This Week's Reward", weekly_none: "❌ Could not determine this week's reward.",
      weekly_stale: "⏳ FortniteDB has not published this week's reward yet — showing last week's. Try again a bit later.",
      weekly_week: "Week of {}", weekly_sub: "Complete 10 mission alerts in a 160+ zone",
      timer_bp: "🏆 Battle Pass", timer_venture: "⚡ Ventures", current_season: "Current Season",
      progress: "📊 Progress", remaining: "⏳ Remaining", days: "days", ends: "🗓 Ends", next: "🚀 Next",
      season_ended: "⚠️ The {} has ended — waiting for the next one.", tba: "TBA",
      filters_title: "⚙️ My Filters",
      filters_intro: "These filters are used only by 🔎 Reward Finder.\nV-Bucks, Power 160, Ventures and the daily alerts always show everything.",
      filters_zones: "— Zones —", filters_rewards: "— Rewards —", filters_reset: "♻️ Reset", filters_done: "✅ Done",
      missions: "missions", updated: "Updated {} UTC", reset_in: "Next reset in",
      stale: "⏳ Today's missions are still being published — showing the data from {}. It refreshes by itself.",
      offline: "📴 Offline — showing the last saved data.",
      load_fail: "❌ Could not load mission data. Check your connection.", retry: "Retry",
      terms_title: "⚖️ Terms of use",
      terms: [
        "This app is free and open source, for PERSONAL use only. It is NOT for sale and must not be sold or used commercially.",
        "Fortnite, its names, icons and artwork are the property of Epic Games, Inc. This project is not affiliated with or endorsed by Epic Games.",
        "Mission data comes from third-party community sites and may be late or wrong.",
        "You use this app entirely at your own risk and responsibility."
      ],
      terms_ok: "I accept", terms_no: "Decline",
      declined: "You declined the terms, so the app stays closed. Reload the page to see them again.",
      foot: "Personal use only · not for sale · Fortnite names, icons and art © Epic Games, Inc. · Use at your own risk."
    },
    fa: {
      brand: "ماموریت‌های فورتنایت", brand_sub: "نجات جهان", langBtn: "English", back: "بازگشت",
      nav_home: "خانه", nav_vbucks: "ویباکس", nav_160: "پاور ۱۶۰", nav_top: "برتر", nav_finder: "جستجو",
      hero_title: "ماموریت‌های روزانه", hero_sub: "{} ماموریت از استون‌وود تا ونچر — با هر ریست به‌روز می‌شود.",
      stat_all: "همه ماموریت‌ها", stat_160: "پاور ۱۶۰", stat_top: "برترها",
      sec_today: "امروز", sec_missions: "ماموریت‌ها", vb_today: "ویباکس امروز", vb_none: "امروز ماموریت ویباکس نیست.",
      weekly_short: "جایزه هفتگی",
      d_days: "روز", d_hours: "ساعت", d_min: "دقیقه", d_sec: "ثانیه",
      btn_vbucks: "💎 ماموریت‌های ویباکس", btn_160: "⚡ ماموریت‌های پاور ۱۶۰", btn_v140: "🌴 ماموریت‌های ونچر ۱۴۰",
      btn_top: "🔥 ماموریت‌های برتر", btn_finder: "🔎 جستجوی جایزه", btn_weekly: "🛠 جایزه هفتگی",
      btn_timer: "⏱ تایمر سیزن‌ها", btn_filters: "⚙️ فیلترهای من",
      mode_cards: "🖼 حالت عکس", mode_text: "📝 حالت متن",
      vbucks_title: "💎 ماموریت‌های ویباکس امروز", p160_title: "⚡ ماموریت‌های پاور ۱۶۰ امروز",
      v140_title: "🌴 ماموریت‌های ونچر — پاور ۱۴۰", top_title: "🔥 ماموریت‌های برتر امروز",
      finder_title: "🔎 جستجوی جایزه — همه زون‌ها", top_zone: "🔥 Top — {}",
      vbucks_none: "❌ امروز ماموریت ویباکس موجود نیست.",
      p160_none: "❌ امروز ماموریت پاور ۱۶۰ موجود نیست.",
      v140_none: "❌ امروز ماموریت ونچر ۱۴۰ موجود نیست (دانجن‌ها حذف شدند).",
      top_none: "❌ امروز ماموریت برجسته‌ای نیست.",
      finder_none: "❌ امروز در هیچ زونی ماموریتی با جوایز انتخابی تو نیست.",
      finder_need: "🔎 اول در ⚙️ فیلترهای من حداقل یک جایزه انتخاب کن؛ بعد این بخش همه ماموریت‌های همه زون‌ها (استون‌وود تا توئین پیکس و ونچر) را می‌گردد.",
      open_filters: "⚙️ باز کردن فیلترهای من",
      none: "ندارد",
      weekly_title: "🛠 جایزه این هفته", weekly_none: "❌ جایزه این هفته مشخص نشد.",
      weekly_stale: "⏳ سایت FortniteDB هنوز جایزه این هفته را منتشر نکرده؛ جایزه هفته قبل نمایش داده شده. کمی بعد دوباره امتحان کن.",
      weekly_week: "هفته {}", weekly_sub: "۱۰ ماموریت آلرت در زون ۱۶۰+ را کامل کنید",
      timer_bp: "🏆 بتل‌پس", timer_venture: "⚡ ونچر", current_season: "سیزن جاری",
      progress: "📊 پیشرفت", remaining: "⏳ باقی‌مانده", days: "روز", ends: "🗓 پایان", next: "🚀 بعدی",
      season_ended: "⚠️ زمان {} تمام شده — منتظر شروع بعدی هستیم.", tba: "اعلام نشده",
      filters_title: "⚙️ فیلترهای من",
      filters_intro: "این فیلترها فقط برای 🔎 جستجوی جایزه استفاده می‌شوند.\nویباکس، پاور ۱۶۰، ونچر و اعلان‌های روزانه همیشه همه چیز را نشان می‌دهند.",
      filters_zones: "— زون‌ها —", filters_rewards: "— جوایز —", filters_reset: "♻️ بازنشانی", filters_done: "✅ تمام",
      missions: "ماموریت", updated: "به‌روزرسانی {} UTC", reset_in: "ریست بعدی تا",
      stale: "⏳ ماموریت‌های امروز هنوز در حال انتشارند — داده {} نمایش داده شده. خودش به‌روز می‌شود.",
      offline: "📴 آفلاین — آخرین داده ذخیره‌شده نمایش داده شده.",
      load_fail: "❌ داده ماموریت‌ها دریافت نشد. اتصال اینترنت را بررسی کن.", retry: "تلاش دوباره",
      terms_title: "⚖️ شرایط استفاده",
      terms: [
        "این اپ رایگان و متن‌باز است و فقط برای استفاده شخصی ساخته شده. برای فروش نیست و نباید فروخته یا تجاری استفاده شود.",
        "نام، آیکن‌ها و تصاویر فورتنایت تحت انحصار و مالکیت Epic Games هستند و این پروژه هیچ ارتباطی با Epic Games ندارد و مورد تأیید آن نیست.",
        "داده ماموریت‌ها از سایت‌های جامعه کاربری گرفته می‌شود و ممکن است دیر یا اشتباه باشد.",
        "مسئولیت استفاده از این اپ کاملاً با خودتان است."
      ],
      terms_ok: "می‌پذیرم", terms_no: "نمی‌پذیرم",
      declined: "شرایط را نپذیرفتید، پس اپ بسته می‌ماند. برای دیدن دوباره شرایط، صفحه را دوباره بارگذاری کنید.",
      foot: "فقط برای استفاده شخصی · برای فروش نیست · نام، آیکن‌ها و تصاویر فورتنایت متعلق به Epic Games · مسئولیت استفاده با خودتان."
    }
  };

  // ---- storage (never fatal) -----------------------------------------------
  function load(key, fallback) {
    try { var v = localStorage.getItem("fn." + key); return v === null ? fallback : JSON.parse(v); }
    catch (e) { return fallback; }
  }
  function save(key, value) {
    try { localStorage.setItem("fn." + key, JSON.stringify(value)); } catch (e) { /* private mode */ }
  }

  var state = {
    lang: load("lang", /^fa\b/i.test(navigator.language || "") ? "fa" : "en"),
    mode: load("mode", "cards"),
    filters: load("filters", { zones: [], rewards: [] }),
    data: null, offline: false, error: false
  };
  if (!state.filters || !Array.isArray(state.filters.zones)) state.filters = { zones: [], rewards: [] };

  function t(key) { var v = S[state.lang][key]; return v === undefined ? S.en[key] : v; }
  function fmt(s, v) { return String(s).replace("{}", v); }
  function esc(s) {
    return String(s === undefined || s === null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function num(n) { return Number(n).toLocaleString("en-US"); }
  // Dates/times stay left-to-right inside Persian text.
  function fmtLtr(s, v) { return esc(s).replace("{}", '<bdi dir="ltr">' + esc(v) + "</bdi>"); }
  function stamp() { return new Date(state.data.generated).toISOString().slice(0, 16).replace("T", " "); }
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  var $ = function (id) { return document.getElementById(id); };
  var view = $("view");

  // ---- bot logic ports ----------------------------------------------------
  // mission_matches_rewards(): types OR-ed; a selected rarity must hold for
  // the SAME alert reward. Tags were computed with the bot's REWARD_FILTERS.
  function matchesRewards(m, selected) {
    var rar = state.data.rarityFilters;
    var names = selected.filter(function (n) { return state.data.filterRewards.indexOf(n) >= 0; });
    if (!names.length) return true;
    var rarities = names.filter(function (n) { return rar.indexOf(n) >= 0; });
    var types = names.filter(function (n) { return rar.indexOf(n) < 0; });
    var pool = rarities.length ? m.a : m.a.concat(m.k);
    return pool.some(function (r) {
      if (types.length && !types.some(function (n) { return r.t.indexOf(n) >= 0; })) return false;
      if (rarities.length && !rarities.some(function (n) { return r.t.indexOf(n) >= 0; })) return false;
      return true;
    });
  }
  function applyFilters(list) {
    var zones = state.filters.zones, rewards = state.filters.rewards;
    return list.filter(function (m) {
      return (!zones.length || zones.indexOf(m.zk) >= 0) && matchesRewards(m, rewards);
    });
  }
  // venture_window()
  function ventureWindow(now) {
    var cycles = state.data.season.ventures;
    for (var yo = -1; yo <= 0; yo++) {
      for (var i = 0; i < cycles.length; i++) {
        var c = cycles[i], y = now.getUTCFullYear() + yo;
        var start = Date.UTC(y, c.start[0] - 1, c.start[1]);
        var wraps = c.end[0] < c.start[0] || (c.end[0] === c.start[0] && c.end[1] <= c.start[1]);
        var end = Date.UTC(y + (wraps ? 1 : 0), c.end[0] - 1, c.end[1]);
        if (start <= now.getTime() && now.getTime() < end) {
          return { name: c.name, start: start, end: end, next: cycles[(i + 1) % cycles.length].name };
        }
      }
    }
    return null;
  }

  function vbucksToday() {
    var list = missionsOf("vbucks"), total = 0;
    list.forEach(function (m) { m.a.forEach(function (r) { if (r.vb) total += r.q; }); });
    return { missions: list.length, total: total };
  }
  function missionsOf(listName) {
    return (state.data.lists[listName] || []).map(function (i) { return state.data.missions[i]; });
  }

  // ---- rendering ----------------------------------------------------------
  function title(text, count) {
    return '<h1 class="title"><span>' + esc(text) + "</span>" +
      (count !== undefined ? '<span class="count">' + num(count) + " " + esc(t("missions")) + "</span>" : "") + "</h1>";
  }
  function zoneChip(zoneName, label) {
    var z = state.data.zones[zoneName] || {};
    return '<div class="zone' + (z.i ? "" : " plain") + '">' +
      (z.i ? '<img src="' + esc(z.i) + '" alt="" width="26" height="26">' : "") +
      "<span>" + esc(label || zoneName) + "</span></div>";
  }
  function card(m) {
    var alerts = m.a.slice().sort(function (x, y) { return (y.vb ? 1 : 0) - (x.vb ? 1 : 0); });
    var vb = alerts.some(function (r) { return r.vb; });
    var chips = alerts.length ? alerts.map(function (r) {
      return '<span class="chip"><img src="' + esc(r.i) + '" alt="" width="34" height="34" loading="lazy">' +
        (r.q > 1 ? '<span class="q">' + num(r.q) + "</span>" : "") +
        '<span class="l"' + (r.c ? ' style="color:' + esc(r.c) + '"' : "") + ">" + esc(r.l) + "</span></span>";
    }).join("") : '<span class="dash">-</span>';
    var seen = {}, basics = m.k.filter(function (r) {
      if (!r.l || seen[r.l]) return false; seen[r.l] = 1; return true;
    }).map(function (r) {
      return '<span class="basic"><img src="' + esc(r.i) + '" alt="" width="20" height="20" loading="lazy">' +
        esc((r.q > 1 ? num(r.q) + " " : "") + r.l) + "</span>";
    }).join("");
    return '<article class="card' + (vb ? " vb" : "") + '">' +
      '<img class="scene" src="' + esc(m.s) + '" alt="" width="64" height="64" loading="lazy">' +
      '<div class="body"><div class="head">' +
      (m.p ? '<span class="pw">' + m.p + "</span>" : "") +
      '<span class="name">' + esc(m.n) + "</span>" +
      (m.b ? '<span class="biome">– ' + esc(m.b) + "</span>" : "") + "</div>" +
      '<div class="chips">' + chips + "</div>" +
      (basics ? '<div class="basics">' + basics + "</div>" : "") + "</div></article>";
  }
  function cards(list, groupKey) {
    var html = "", last = null;
    list.forEach(function (m) {
      var key = groupKey === "zk" ? m.zk : m.z;
      if (key !== last) {
        html += groupKey === "zk" ? zoneChip(m.z, fmt(t("top_zone"), m.zk)) : zoneChip(m.z);
        last = key;
      }
      html += card(m);
    });
    return html;
  }
  // format_missions() / _reward_lines(), bot text mode
  function textBlock(list) {
    var parts = list.map(function (m) {
      var place = esc(m.z) + (m.b ? " · " + esc(m.b) : "");
      var lines = [m.e + " <b>" + m.p + "</b>  <code>" + esc(m.n) + "</code>", "🌍 <i>" + place + "</i>"];
      m.a.forEach(function (r) { lines.push("   " + r.e + " " + esc(r.raw) + " <code>x" + num(r.q) + "</code>"); });
      if (m.k.length) {
        lines.push("   📦 <i>" + m.k.slice(0, 6).map(function (r) {
          return esc(r.raw) + (r.q > 1 ? " x" + num(r.q) : "");
        }).join(" · ") + "</i>");
      }
      if (!m.a.length && !m.k.length) lines.push("   — " + esc(t("none")));
      return lines.join("\n");
    });
    return '<div class="txt" dir="ltr">' + parts.join('\n<span class="sep">┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄</span>\n') + "</div>";
  }
  function listPage(titleKey, noneKey, list, groupKey) {
    var html = title(t(titleKey), list.length);
    if (!list.length) return html + '<p class="note">' + esc(t(noneKey)) + "</p>";
    return html + (state.mode === "text" ? textBlock(list) : '<div class="list">' + cards(list, groupKey) + "</div>");
  }

  function statusNotes() {
    var d = state.data, out = "";
    if (state.offline) out += '<p class="note warn">' + esc(t("offline")) + "</p>";
    if (d && d.day !== new Date().toISOString().slice(0, 10)) out += '<p class="note warn">' + fmtLtr(t("stale"), d.day) + "</p>";
    return out;
  }

  var pages = {
    "": function () {
      var vb = vbucksToday(), d = state.data, w = d.weekly, all = (d.lists.all || []).length;
      function tile(route, key, cls, count) {
        var label = t(key), ic = label.split(" ")[0];
        return '<a class="tile ' + cls + '" href="#/' + route + '"><span class="ic">' + ic + "</span>" +
          (count !== undefined ? '<span class="n">' + num(count) + "</span>" : "") +
          '<span class="lb">' + esc(label.slice(ic.length + 1)) + "</span></a>";
      }
      function stat(route, n, key) {
        return (route ? '<a class="stat" href="#/' + route + '">' : '<div class="stat">') + "<b>" + num(n) + "</b><span>" +
          esc(t(key)) + "</span>" + (route ? "</a>" : "</div>");
      }
      // V-Bucks and the weekly reward change by themselves (daily / weekly):
      // shown in full here, side by side, nothing to open.
      var vbRows = missionsOf("vbucks").map(function (m) {
        var q = m.a.reduce(function (sum, r) { return sum + (r.vb ? r.q : 0); }, 0);
        return '<li><img src="' + esc(m.s) + '" alt="" width="40" height="40" loading="lazy"><span class="t"><b>' + esc(m.n) +
          "</b><small>" + esc(m.z) + ' · <span class="pw">' + m.p + "</span></small></span>" +
          '<span class="q">' + num(q) + "</span></li>";
      }).join("");
      var today = '<div class="today">' +
        '<section class="panel vbp"><div class="ph"><span>💎 ' + esc(t("vb_today")) + "</span><b>" + num(vb.total) + "</b></div>" +
        (vbRows ? '<ul class="vbl">' + vbRows + "</ul>" : '<p class="none">' + esc(t("vb_none")) + "</p>") + "</section>" +
        '<section class="panel wkp"><div class="ph"><span>🛠 ' + esc(t("weekly_short")) + "</span></div>" +
        (w ? '<img src="' + esc(w.icon) + '" alt="" width="120" height="120"><b dir="ltr">' + esc(w.label) + "</b>" +
          "<small>" + esc(t("weekly_sub")) + "</small>" +
          (w.week ? '<span class="chip-week">' + fmtLtr(t("weekly_week"), w.week) + "</span>" : "") +
          (w.current ? "" : '<small class="warn">' + esc(t("weekly_stale")) + "</small>")
          : '<p class="none">' + esc(t("weekly_none")) + "</p>") + "</section></div>";
      return statusNotes() + '<div class="home">' +
        '<div class="lead"><a class="hero" href="#/top"><span class="art"></span>' +
        '<span class="tag">⏱ ' + esc(t("reset_in")) + ' <b id="reset-clock">--:--:--</b></span>' +
        "<h1>" + esc(t("hero_title")) + "</h1><p>" + esc(t("hero_sub")).replace("{}", "<b>" + num(all) + "</b>") + "</p>" +
        '<span class="cta">' + esc(t("btn_top")) + "</span></a>" +
        '<div class="stats">' + stat("", all, "stat_all") +
        stat("p160", (d.lists.p160 || []).length, "stat_160") + stat("top", (d.lists.top || []).length, "stat_top") + "</div></div>" +
        '<div class="side"><div class="sec"><h2>' + esc(t("sec_today")) + "</h2><span>" + fmtLtr(t("updated"), stamp()) + "</span></div>" +
        today + "</div>" +
        '<div class="tms"><div class="sec"><h2>' + esc(t("btn_timer").replace(/^\S+\s/, "")) + "</h2></div>" +
        '<div class="timers"><section class="timer" id="t-bp"></section><section class="timer" id="t-vn"></section></div></div>' +
        '<div class="wide"><div class="sec"><h2>' + esc(t("sec_missions")) + "</h2></div>" +
        '<nav class="grid">' +
        tile("vbucks", "btn_vbucks", "t-vbucks", (d.lists.vbucks || []).length) +
        tile("p160", "btn_160", "t-p160", (d.lists.p160 || []).length) +
        tile("v140", "btn_v140", "t-v140", (d.lists.v140 || []).length) +
        tile("top", "btn_top", "t-top", (d.lists.top || []).length) +
        tile("finder", "btn_finder", "t-finder") + tile("filters", "btn_filters", "t-filters") + "</nav>" +
        '<div class="toggle" role="group">' +
        '<button type="button" data-mode="cards" aria-pressed="' + (state.mode === "cards") + '">' + esc(t("mode_cards")) + "</button>" +
        '<button type="button" data-mode="text" aria-pressed="' + (state.mode === "text") + '">' + esc(t("mode_text")) + "</button></div></div></div>";
    },
    vbucks: function () { return statusNotes() + listPage("vbucks_title", "vbucks_none", missionsOf("vbucks")); },
    p160: function () { return statusNotes() + listPage("p160_title", "p160_none", missionsOf("p160")); },
    v140: function () { return statusNotes() + listPage("v140_title", "v140_none", missionsOf("v140")); },
    top: function () { return statusNotes() + listPage("top_title", "top_none", missionsOf("top"), "zk"); },
    finder: function () {
      if (!state.filters.rewards.length) {
        return title(t("finder_title")) + '<div class="note">' + esc(t("finder_need")) +
          '<div><a class="btn primary" href="#/filters">' + esc(t("open_filters")) + "</a></div></div>";
      }
      return statusNotes() + listPage("finder_title", "finder_none", applyFilters(missionsOf("all")));
    },
    weekly: function () {
      var w = state.data.weekly, html = title(t("weekly_title"));
      if (!w) return html + '<p class="note err">' + esc(t("weekly_none")) + "</p>";
      if (!w.current) html += '<p class="note warn">' + esc(t("weekly_stale")) + "</p>";
      return html + '<div class="weekly"><img src="' + esc(w.icon) + '" alt="" width="132" height="132">' +
        '<div><h2 dir="ltr">' + esc(w.e + " " + w.label) + "</h2><p>" + esc(t("weekly_sub")) + "</p>" +
        (w.week ? '<span class="chip-week">' + fmtLtr(t("weekly_week"), w.week) + "</span>" : "") + "</div></div>";
    },
    timers: function () {
      return title(t("btn_timer")) + '<div class="timers"><section class="timer" id="t-bp"></section><section class="timer" id="t-vn"></section></div>';
    },
    filters: function () {
      var f = state.filters, d = state.data;
      function opts(kind, names) {
        return '<div class="opts">' + names.map(function (n) {
          return '<button type="button" class="opt" data-kind="' + kind + '" data-name="' + esc(n) +
            '" aria-pressed="' + (f[kind].indexOf(n) >= 0) + '">' + esc(n) + "</button>";
        }).join("") + "</div>";
      }
      return title(t("filters_title")) + '<p class="intro">' + esc(t("filters_intro")) + "</p>" +
        '<div class="fgroup"><h3>' + esc(t("filters_zones")) + "</h3>" + opts("zones", d.filterZones) + "</div>" +
        '<div class="fgroup"><h3>' + esc(t("filters_rewards")) + "</h3>" + opts("rewards", d.filterRewards) + "</div>" +
        '<div class="row"><a class="btn primary" href="#/finder">' + esc(t("btn_finder")) + "</a>" +
        '<button type="button" class="btn ghost" id="f-reset">' + esc(t("filters_reset")) + "</button></div>";
    }
  };

  // ---- timers (format_countdown) -----------------------------------------
  function timerHtml(label, name, start, end, next) {
    var now = Date.now();
    if (!end) return "<h2>" + esc(label) + '</h2><p class="note err">' + esc(t("load_fail")) + "</p>";
    var left = end - now;
    if (left <= 0) return "<h2>" + esc(label) + '</h2><p class="note warn">' + esc(fmt(t("season_ended"), label)) + "</p>";
    var pct = start && end > start ? Math.max(0, Math.min(100, (now - start) / (end - start) * 100)) : null;
    var s = Math.floor(left / 1000), days = Math.floor(s / 86400);
    var h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
    return "<h2>🌐 Fortnite " + esc(label) + " — " + esc(name) + "</h2>" +
      (pct !== null ? '<div class="kv"><span>' + esc(t("progress")) + "</span><b>" + pct.toFixed(1) + "%</b></div>" +
        '<div class="progress"><span style="width:' + pct.toFixed(2) + '%"></span></div>' : "") +
      '<div class="digits">' + [[days, "d_days"], [h, "d_hours"], [m, "d_min"], [sec, "d_sec"]].map(function (x) {
        return "<div><b>" + pad(x[0]) + "</b><span>" + esc(t(x[1])) + "</span></div>";
      }).join("") + "</div>" +
      '<div class="kv rem"><span>' + esc(t("remaining")) + "</span><b>" + days + " " + esc(t("days")) + "</b></div>" +
      '<div class="kv"><span>' + esc(t("ends")) + "</span><b>" + new Date(end).toISOString().slice(0, 16).replace("T", " ") + " UTC</b></div>" +
      '<div class="kv"><span>' + esc(t("next")) + "</span><b>" + esc(next) + "</b></div>";
  }
  function tick() {
    var clock = $("reset-clock");
    if (clock) {
      var now = new Date(), next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
      var s = Math.max(0, Math.floor((next - now.getTime()) / 1000));
      clock.textContent = pad(Math.floor(s / 3600)) + ":" + pad(Math.floor(s % 3600 / 60)) + ":" + pad(s % 60);
    }
    var bp = $("t-bp"), vn = $("t-vn");
    if (bp && state.data) {
      var se = state.data.season;
      bp.innerHTML = timerHtml(state.lang === "fa" ? "بتل‌پس" : "Battle Pass", t("current_season"),
        se.bpStart ? Date.parse(se.bpStart) : null, se.bpEnd ? Date.parse(se.bpEnd) : null, t("tba"));
    }
    if (vn && state.data) {
      var w = ventureWindow(new Date());
      vn.innerHTML = w ? timerHtml(state.lang === "fa" ? "ونچر" : "Ventures", w.name, w.start, w.end, w.next)
        : timerHtml("Ventures", "", null, null, "");
    }
  }

  // ---- routing / chrome ---------------------------------------------------
  function route() { return (location.hash.replace(/^#\/?/, "").split("?")[0]) || ""; }
  function render() {
    var r = route();
    document.documentElement.lang = state.lang;
    document.documentElement.dir = state.lang === "fa" ? "rtl" : "ltr";
    $("brand").textContent = t("brand");
    $("brand-sub").textContent = t("brand_sub");
    dock(r);
    $("lang").textContent = t("langBtn");
    $("back").hidden = r === "";
    $("back").setAttribute("aria-label", t("back"));
    $("foot-terms").textContent = t("foot");
    if (load("terms", "") !== "yes") return showTerms();
    if (!state.data) {
      view.innerHTML = state.error
        ? '<div class="note err">' + esc(t("load_fail")) + '<div><button class="btn primary" id="retry" type="button">' +
          esc(t("retry")) + "</button></div></div>"
        : '<div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div>';
      return;
    }
    var page = pages[r] || pages[""];
    view.dataset.page = pages[r] ? r || "home" : "home";
    view.innerHTML = page();
    $("foot-status").innerHTML = fmtLtr(t("updated"), stamp());
    var vb = vbucksToday();
    $("vb-total").textContent = num(vb.total);
    $("vb-pill").hidden = !vb.total || r !== "";
    tick();
  }

  function dock(r) {
    var el = $("dock"), items = [["", "🏠", "nav_home"], ["p160", "⚡", "nav_160"], ["vbucks", "💎", "nav_vbucks", "mid"],
      ["top", "🔥", "nav_top"], ["finder", "🔎", "nav_finder"]];
    el.hidden = load("terms", "") !== "yes";
    el.innerHTML = items.map(function (x) {
      return '<a href="#/' + x[0] + '"' + (x[3] ? ' class="mid"' : "") + (r === x[0] ? ' aria-current="page"' : "") +
        '><span class="i">' + x[1] + "</span><span>" + esc(t(x[2])) + "</span></a>";
    }).join("");
  }

  function showTerms() {
    var box = $("terms");
    $("terms-title").textContent = t("terms_title");
    $("terms-list").innerHTML = t("terms").map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("");
    $("terms-ok").textContent = t("terms_ok");
    $("terms-no").textContent = t("terms_no");
    $("terms-lang").textContent = t("langBtn");
    box.hidden = false;
    view.innerHTML = "";
  }

  document.addEventListener("click", function (ev) {
    var el = ev.target.closest("button, a");
    if (!el) return;
    if (el.id === "lang" || el.id === "terms-lang") {
      state.lang = state.lang === "fa" ? "en" : "fa"; save("lang", state.lang);
      if (el.id === "terms-lang") showTerms();
      render();
    } else if (el.id === "back") {
      location.hash = "#/";
    } else if (el.id === "terms-ok") {
      save("terms", "yes"); $("terms").hidden = true; render();
    } else if (el.id === "terms-no") {
      $("terms").hidden = true; view.innerHTML = '<p class="blocked">' + esc(t("declined")) + "</p>";
    } else if (el.id === "retry") {
      state.error = false; render(); fetchData();
    } else if (el.id === "f-reset") {
      state.filters = { zones: [], rewards: [] }; save("filters", state.filters); render();
    } else if (el.dataset.mode) {
      state.mode = el.dataset.mode; save("mode", state.mode); render();
    } else if (el.dataset.kind) {
      var list = state.filters[el.dataset.kind], n = el.dataset.name, at = list.indexOf(n);
      if (at >= 0) list.splice(at, 1); else list.push(n);
      save("filters", state.filters);
      el.setAttribute("aria-pressed", String(at < 0));
    }
  });
  window.addEventListener("hashchange", function () { render(); window.scrollTo(0, 0); view.focus({ preventScroll: true }); });

  // ---- data -------------------------------------------------------------------
  function useData(d, offline) {
    if (!d || !d.missions) throw new Error("bad data");
    state.data = d; state.offline = !!offline; state.error = false;
    if (d.background) document.body.style.setProperty("--bg", 'url("' + d.background + '")');
    render();
  }
  function fetchData() {
    return fetch(DATA_URL, { cache: "no-cache" })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (d) { useData(d, navigator.onLine === false); })
      .catch(function () {
        // The service worker answers from its cache when it can; this is
        // only reached with nothing cached at all.
        if (!state.data) { state.error = true; render(); } else { state.offline = true; render(); }
      });
  }

  render();
  fetchData();
  setInterval(tick, 1000);
  // New game day: fetch again shortly after 00:00 UTC.
  setInterval(function () {
    if (state.data && state.data.day !== new Date().toISOString().slice(0, 10)) fetchData();
  }, 5 * 60 * 1000);
  document.addEventListener("visibilitychange", function () {
    if (!document.hidden && state.data && state.data.day !== new Date().toISOString().slice(0, 10)) fetchData();
  });

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("sw.js").catch(function () { /* not fatal */ });
    });
  }
  window.FN_APP = { version: VERSION, state: state, applyFilters: applyFilters, ventureWindow: ventureWindow };
})();

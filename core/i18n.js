// 界面文字的英文和繁体中文。键是简体原文；没翻到的条目回落到原文。
// 每一条是 [英文, 繁体]。繁体按台湾用法（復原、設定、六線譜、聲部、時值、格）。
.pragma library

var STRINGS = {
    "和弦助手": ["Chord Assist", "和弦助手"],

    // 时值
    "四分": ["quarter", "四分"],
    "八分": ["eighth", "八分"],
    "十六分": ["16th", "十六分"],
    "音符": ["note", "音符"],
    "时值": ["Duration", "時值"],

    // 当前位置
    "位置": ["Position", "位置"],
    "第 %1 小节 第 %2 拍": ["Bar %1 · beat %2", "第 %1 小節 第 %2 拍"],
    "第 ": ["Bar ", "第 "],
    " 小节 第 ": [" · beat ", " 小節 第 "],
    " 拍": ["", " 拍"],
    "记号": ["Symbol", "記號"],
    "无": ["none", "無"],
    "旋律": ["Melody", "旋律"],
    "休止符": ["rest", "休止符"],
    "第二声部": ["Voice 2", "第二聲部"],
    "空": ["none", "空"],
    "在谱面上选中一个旋律音": ["Select a melody note in the score", "在譜面上選取一個旋律音"],
    "（%1 弦 %2 品）": [" (str %1, fr %2)", "（%1 弦 %2 格）"],
    "（": [" (", "（"],
    " 弦 ": [" str ", " 弦 "],
    " 品）": [" fr)", " 格）"],
    " 品": [" fr", " 格"],

    // 顶栏与左栏
    "跟随选区": ["Follow selection", "跟隨選取"],
    "锁定和弦": ["Lock chord", "鎖定和弦"],
    "刷新": ["Refresh", "重新整理"],
    "贴底": ["Dock bottom", "貼底"],
    "组成音": ["Tones", "組成音"],
    "只留三和弦": ["triad only", "只留三和弦"],
    "把位": ["Frets", "把位"],
    "旋律所在弦不参与": ["Skip melody string", "旋律所在弦不參與"],
    "← → 上/下一个旋律音 · Shift+←→ 移把位 · Esc 关闭":
        ["← → prev/next melody note · Shift+←→ move frets · Esc close",
         "← → 上/下一個旋律音 · Shift+←→ 移把位 · Esc 關閉"],

    // 状态与提醒
    "请先在谱面上选中一个旋律音或休止符（在联动的六线谱上选，弦品更准）":
        ["Select a melody note or rest in the score first (select on the linked TAB staff for accurate string/fret)",
         "請先在譜面上選取一個旋律音或休止符（在連動的六線譜上選，弦格更準）"],
    "这个乐器没有调弦信息，按标准 EADGBE 算的":
        ["This instrument has no tuning data; using standard EADGBE", "這個樂器沒有調弦資訊，按標準 EADGBE 算的"],
    "旋律音的弦是猜的（在六线谱上选音会更准）":
        ["The melody string is a guess (select the note on the TAB staff for accuracy)", "旋律音的弦是猜的（在六線譜上選音會更準）"],
    "第二声部有个从前面延过来的音，写入会把它截断":
        ["Voice 2 has a note held over from before; writing here will cut it short", "第二聲部有個從前面延過來的音，寫入會把它截斷"],
    "第二声部在这个%1音符的时值内已经有音，写入会盖掉它":
        ["Voice 2 already has a note within this %1 note; writing will overwrite it", "第二聲部在這個%1音符的時值內已經有音，寫入會蓋掉它"],
    "后面没有旋律音了": ["No more melody notes after this", "後面沒有旋律音了"],
    "前面没有旋律音了": ["No melody notes before this", "前面沒有旋律音了"],
    "失败": ["failed", "失敗"],
    "；": ["; ", "；"],

    // 和弦解析（core/theory.js 产生）
    "和弦认不出来": ["Chord not recognized", "和弦認不出來"],
    "和弦为空": ["Empty chord", "和弦為空"],
    "认不出根音": ["Root note not recognized", "認不出根音"],
    "看不懂的后缀：": ["Unknown suffix: ", "看不懂的後綴："],

    // 写入 / 删除 / 改时值
    "和弦助手：写入 ": ["Chord Assist: write ", "和弦助手：寫入 "],
    "和弦助手：删除 ": ["Chord Assist: remove ", "和弦助手：刪除 "],
    "和弦助手：改时值 ": ["Chord Assist: duration ", "和弦助手：改時值 "],
    "已写入 ": ["Wrote ", "已寫入 "],
    "，替换了同弦上的 ": [", replacing ", "，取代了同弦上的 "],
    "。再点一次删掉，Ctrl+Z 撤销": [". Click again to remove; Ctrl+Z undoes", "。再點一次刪掉，Ctrl+Z 復原"],
    "已删掉 ": ["Removed ", "已刪掉 "],
    "。Ctrl+Z 撤销": [". Ctrl+Z undoes", "。Ctrl+Z 復原"],
    "写入失败: ": ["Write failed: ", "寫入失敗: "],
    "删除失败: ": ["Remove failed: ", "刪除失敗: "],
    "改时值失败: ": ["Duration change failed: ", "改時值失敗: "],
    "这一拍第二声部改成%1音符": ["Voice 2 on this beat is now a %1 note", "這一拍第二聲部改成%1音符"],
    "，盖掉了后面 %1 个第二声部的音": [", overwriting %1 later voice-2 note(s)", "，蓋掉了後面 %1 個第二聲部的音"]
};

// 系统区域设置 → 界面语言。目前界面上只提供 EN / 中 两档，"中"就是繁体；
// 简体（zh-Hans）的字典和 t() 都还在，只是不在开关里出现，以后要开只改这里和开关。
function detect(localeName) {
    var n = String(localeName || "").replace(/-/g, "_");
    if (n.indexOf("zh") === 0) { return "zh-Hant"; }
    return "en";
}

function t(key, lang) {
    if (!lang || lang === "zh-Hans") { return key; }
    var e = STRINGS[key];
    if (!e) { return key; }
    var v = lang === "en" ? e[0] : e[1];
    return (v === undefined || v === null) ? key : v;
}

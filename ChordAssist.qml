//=============================================================================
//  和弦助手 Chord Assist  v0.3
//
//  指弹编曲流程里「旋律敲完之后」那一步：
//  在谱面上选中一个旋律音（或休止符）→ 面板按这一拍的和弦记号，在把位窗口里标出可选音
//  → 点哪个格子，就立刻把那个音写进同一位置的第二声部；再点一次就删掉。
//
//  乐理和指板的计算全在 core/*.js 里，纯函数。这个文件只管界面和跟 MuseScore 打交道。
//
//  v0.2：不用 pluginType: "dialog"（4.6.3 那个外壳不能改大小），插件自己开一个普通 Window。
//  v0.3：去掉「选型 → 切分 → 插入」三步，改成点格子直接写；时值在面板里选（默认八分）；
//        跟随选区时自动读谱面上的和弦记号；←/→ 在面板里就能跳到上/下一个旋律音；
//        控件全部自己画成扁平圆角的，不再用系统原生样式。
//=============================================================================

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import MuseScore 3.0
import FileIO 3.0

import "core/theory.js"    as Theory
import "core/fretboard.js" as FB
import "core/instance.js"  as Instance
import "core/i18n.js"      as I18n

MuseScore {
    id: root

    title: "和弦助手"
    description: "选中旋律音，按和弦记号在把位窗口里提示可选音；点哪个格子就把那个音写进第二声部"
    version: "0.3"
    requiresScore: true
    categoryCode: "composing-arranging-tools"

    FileIO { id: fio }   // 只用来存界面语言（settings.json）

    // ---- 配色（照 VS Code 深色主题） --------------------------------------
    readonly property color cBg:       "#1e1e1e"
    readonly property color cPanel:    "#252526"
    readonly property color cPanel2:   "#2d2d30"
    readonly property color cLine:     "#3c3c3c"
    readonly property color cText:     "#d4d4d4"
    readonly property color cDim:      "#9d9d9d"
    readonly property color cAccent:   "#0e639c"
    readonly property color cAccentHi: "#1177bb"
    readonly property color cBtn:      "#3a3d41"
    readonly property color cBtnHi:    "#45494e"
    readonly property color cWarn:     "#e0a03c"
    readonly property color cErr:      "#f48771"
    readonly property color cCell:     "#2a2d32"
    readonly property color cCellOut:  "#222326"
    readonly property color cMelody:   "#f0f2f5"

    // ---- 状态 ----------------------------------------------------------
    property var  fb: null                  // 指板模型
    property var  anchor: null              // 锚点 {tick, staffIdx, voice, isRest, pitch, string, fret, measureNo, beat, ...}
    property string chordText: "Am7"
    property string scoreChord: ""          // 谱面上锚点处生效的和弦记号（上次读到的）
    property bool chordLocked: false        // 勾上后面板里的和弦不再跟谱面
    property var  mods: []                  // 扩展音按钮
    property var  offDegrees: ({})          // 被关掉的音级 label -> true
    property int  winCenter: 5
    property int  winSpan: 3
    property var  grid: []                  // grid[string][fret] = cell
    property var  spec: null                // 生效的 ChordSpec
    property var  written: []               // 锚点处第二声部已有的音 [{pitch, string, fret, el}]
    property int  noteDen: 8                // 新写入的音的时值分母：4 / 8 / 16
    property int  writtenDen: -1            // 锚点处第二声部已有和弦的时值分母（不是单纯 1/4、1/8、1/16 时为 -1）
    // 时值按钮亮哪个：这一拍已有和弦就亮它的，否则亮下次写入要用的
    readonly property int shownDen: (written.length && writtenDen > 0) ? writtenDen : noteDen
    property bool blockMelodyString: true
    property bool followSelection: true
    property string statusMsg: ""
    property string overwriteMsg: ""
    property int  targetVoice: 1            // voice 索引 0 起算，1 = 第二声部
    property int  melodyVoice: 0            // 旋律在 voice 1
        property bool suppressRefresh: false    // 自己写谱期间挡掉跟随
    property string lastSelSig: ""          // 上次读到的选区，定时器靠它判断选区变没变
    property int  pollTicks: 0
    property bool placed: false             // 第一次弹出时已经贴到主窗口底部了
    property string lang: I18n.detect(Qt.locale().name)   // 界面语言："zh-Hans" | "zh-Hant" | "en"

    // 只画把位窗口里的品，再加上空弦那一列（开放弦是指弹常用音，一直显示、可以点）。
    // 格子高度跟着横条高度缩放，宽度按高度配比，不会被裁掉。
    readonly property int winLo: fb ? FB.windowFromCenter(winCenter, winSpan, fb.frets).lo : 0
    readonly property int winHi: fb ? FB.windowFromCenter(winCenter, winSpan, fb.frets).hi : 0
    readonly property var shownFrets: {
        var out = [0];
        for (var f = Math.max(1, winLo); f <= winHi; f++) { out.push(f); }
        return out;
    }
    readonly property int cellH: Math.max(18, Math.min(36, Math.floor((fretPanel.height - 26) / Math.max(1, fb ? fb.nStrings : 6)) - 2))
    readonly property int cellW: Math.max(30, Math.min(56, Math.round(cellH * 1.5)))
    readonly property int gridW: 36 + shownFrets.length * (cellW + 2) + (winLo > 0 ? 8 : 0)

    // 空弦列和把位窗口不相连时中间空一点
    function fretGap(f) { return (winLo > 0 && f === winLo) ? 8 : 0; }

    // =====================================================================
    //  与 MuseScore 打交道
    // =====================================================================

    // el.type 在 apiversion 1 下是整数，v2 下是 "NOTE" 这样的字符串。两种都认。
    function isType(el, name) {
        if (!el) { return false; }
        var t = el.type;
        if (t === name) { return true; }
        try { return t === Element[name]; } catch (e) { return false; }
    }

    function currentStringData(staffIdx) {
        try {
            var st = curScore.staves[staffIdx];
            var instr = st.part.instruments[0];
            return instr.stringData;
        } catch (e) {
            return null;
        }
    }

    // ---- 界面语言：字典在 core/i18n.js，手动选的存在插件目录的 settings.json 里 ----
    function tr(s) { return I18n.t(s, lang); }

    // theory.js 的提示里有一条带参数（"看不懂的后缀：xxx"），只翻前缀
    function trWarn(w) {
        var prefix = "看不懂的后缀：";
        return w.indexOf(prefix) === 0 ? tr(prefix) + w.substring(prefix.length) : tr(w);
    }

    // Qt.resolvedUrl 给的是 file:///C:/...，FileIO 要纯路径
    function localPath(rel) {
        var u = Qt.resolvedUrl(rel).toString();
        var pth = decodeURIComponent(u.replace(/^file:\/\//, ""));
        if (/^\/[A-Za-z]:/.test(pth)) { pth = pth.substring(1); }
        return pth;
    }

    function loadLang() {
        try {
            fio.source = localPath("settings.json");
            if (!fio.exists()) { return; }
            var o = JSON.parse(fio.read());
            if (o && (o.lang === "en" || o.lang === "zh-Hant" || o.lang === "zh-Hans")) { lang = o.lang; }
        } catch (e) { }
    }

    function setLang(code) {
        lang = code;
        try {
            fio.source = localPath("settings.json");
            fio.write(JSON.stringify({ lang: code }, null, 2));
        } catch (e) { }
    }

    function newCursor(voice) {
        var c = curScore.newCursor();
        c.staffIdx = anchor.staffIdx;
        c.voice = voice;
        return c;
    }

    function noteName(pitch) {
        return Theory.pcName(pitch % 12) + (Math.floor(pitch / 12) - 1);
    }

    function noteLabel(pitch, string, fret) {
        var s = noteName(pitch);
        if (string >= 0 && fret >= 0) { s += tr("（%1 弦 %2 品）").arg(string + 1).arg(fret); }
        return s;
    }

    function denLabel(d) { return d === 4 ? tr("四分") : (d === 16 ? tr("十六分") : tr("八分")); }

    // 从选区读锚点：优先音符，其次休止符。选中的是第二声部里的音（比如刚写进去的）时，
    // 锚点改成同一位置的旋律音，面板不会因为点了自己写的音就乱跳。
    // 选中的音在五线谱上时 string 会是 -1，那就按音高猜一个位置。
    function readAnchor() {
        if (!curScore) { return null; }
        var note = null, rest = null;
        try {
            var els = curScore.selection.elements;
            for (var i = 0; i < els.length; i++) {
                if (!note && isType(els[i], "NOTE")) { note = els[i]; }
                else if (!rest && isType(els[i], "REST")) { rest = els[i]; }
            }
        } catch (e) { return null; }
        var el = note ? note : rest;
        if (!el) { return null; }

        var staffIdx = el.staffIdx;
        var tick, voice;
        try { tick = note ? note.parent.parent.tick : rest.parent.tick; } catch (e2) { return null; }
        try { voice = el.voice; } catch (e3) { voice = 0; }

        if (voice !== melodyVoice) {
            try {
                var c = curScore.newCursor();
                c.staffIdx = staffIdx;
                c.voice = melodyVoice;
                c.rewindToTick(tick);
                var m = c.element;
                if (m && isType(m, "CHORD")) {
                    var ns = m.notes;
                    var top = ns[0];
                    for (var k = 1; k < ns.length; k++) { if (ns[k].pitch > top.pitch) { top = ns[k]; } }
                    note = top; rest = null; voice = melodyVoice;
                } else if (m && isType(m, "REST")) {
                    note = null; rest = m; voice = melodyVoice;
                }
            } catch (e4) { }
        }

        var sd = currentStringData(staffIdx);
        var hasTuning = false;
        try { hasTuning = !!(sd && sd.strings && sd.strings.length > 0); } catch (eSd) { }
        var board = FB.fromApiStringData(sd);   // 读不到就退回标准调弦

        var pitch = -1, str = -1, fr = -1, guessed = false;
        if (note) {
            pitch = note.pitch;
            try { str = note.string; } catch (e5) { }
            try { fr = note.fret; } catch (e6) { }
            if (str === undefined || str === null || str < 0 || fr < 0) {
                str = -1; fr = -1;
                var g = FB.guessMelodyPosition(board, pitch);
                if (g) { str = g.string; fr = g.fret; guessed = true; }
            }
        }

        var mb = measureAndBeat(tick);
        return {
            tick: tick, staffIdx: staffIdx, voice: voice, isRest: !note,
            pitch: pitch, string: str, fret: fr, guessed: guessed,
            measureNo: mb.measureNo, beat: mb.beat, beatDen: mb.beatDen,
            measureTick: mb.measureTick, measureTicks: mb.measureTicks,
            hasTuning: hasTuning, board: board
        };
    }

    // 走一遍小节，算出 tick 落在第几小节第几拍，顺带拿拍号分母
    function measureAndBeat(tick) {
        var out = { measureNo: 1, beat: 1, beatDen: 4, measureTick: 0, measureTicks: 0 };
        try {
            var c = curScore.newCursor();
            c.staffIdx = 0;
            c.voice = 0;
            c.rewind(0);
            var mTick = c.tick;
            var m = c.measure;
            var nextTick = -1;
            while (c.nextMeasure()) {
                if (c.tick > tick) { nextTick = c.tick; break; }
                mTick = c.tick;
                m = c.measure;
            }
            out.measureTick = mTick;
            out.measureTicks = (nextTick > mTick) ? (nextTick - mTick) : 0;
            if (m) {
                try { out.measureNo = m.no + 1; } catch (e1) { }
                try {
                    var ts = m.timesigNominal;
                    if (ts && ts.denominator) { out.beatDen = ts.denominator; }
                } catch (e2) { }
                // 最后一小节没有「下一小节」可减，用拍号算
                if (out.measureTicks === 0) {
                    try {
                        var ts2 = m.timesigActual ? m.timesigActual : m.timesigNominal;
                        if (ts2 && ts2.numerator && ts2.denominator) {
                            out.measureTicks = Math.round(ts2.numerator / ts2.denominator * 4 * division);
                        }
                    } catch (e3) { }
                }
            }
            var beatTicks = 4 * division / out.beatDen;
            out.beat = Math.floor((tick - mTick) / beatTicks) + 1;
        } catch (e) { }
        return out;
    }

    // 谱面上写在小节上方的和弦记号：往回找离锚点最近的那个
    function harmonyAt(tick) {
        if (!curScore) { return ""; }
        var best = "", bestTick = -1;
        try {
            var seg = curScore.firstSegment();
            while (seg) {
                if (seg.tick > tick) { break; }
                var anns = seg.annotations;
                for (var a = 0; a < anns.length; a++) {
                    if (isType(anns[a], "HARMONY")) {
                        var txt = "";
                        try { txt = anns[a].plainText; } catch (e1) { }
                        if (!txt) { try { txt = anns[a].text; } catch (e2) { } }
                        if (txt && seg.tick >= bestTick) { best = txt; bestTick = seg.tick; }
                    }
                }
                seg = seg.next;
            }
        } catch (e) { }
        return best;
    }

    // 锚点处第二声部已经有的音（只认正好从这个 tick 开始的和弦）
    function readWritten() {
        var out = [];
        if (!anchor || !curScore) { return out; }
        try {
            var c = newCursor(targetVoice);
            c.rewindToTick(anchor.tick);
            var el = c.element;
            var wd = -1;
            if (el && isType(el, "CHORD") && c.tick === anchor.tick) {
                var ns = el.notes;
                for (var i = 0; i < ns.length; i++) {
                    var s = -1, f = -1;
                    try { s = ns[i].string; f = ns[i].fret; } catch (e1) { }
                    if (s === undefined || s === null) { s = -1; }
                    if (f === undefined || f === null) { f = -1; }
                    out.push({ pitch: ns[i].pitch, string: s, fret: f, el: ns[i] });
                }
                try {
                    var dur = el.duration;
                    if (dur && dur.numerator === 1) { wd = dur.denominator; }
                } catch (e2) { }
            }
            writtenDen = wd;
        } catch (e) { }
        return out;
    }

    function writtenSig(list) {
        var parts = [];
        for (var i = 0; i < list.length; i++) { parts.push(list[i].pitch + "/" + list[i].string + "/" + list[i].fret); }
        return parts.sort().join(",");
    }

    function writtenText(list) {
        if (!list || !list.length) { return tr("空"); }
        var sorted = list.slice().sort(function (a, b) { return a.pitch - b.pitch; });
        var parts = [];
        for (var i = 0; i < sorted.length; i++) { parts.push(noteLabel(sorted[i].pitch, sorted[i].string, sorted[i].fret)); }
        return parts.join("  ");
    }

    // 格子对应的已写入音：有弦品信息按弦品配，没有的按音高配
    function findWritten(list, string, fret, pitch) {
        for (var i = 0; i < list.length; i++) {
            var w = list[i];
            if (w.string >= 0) {
                if (w.string === string && w.fret === fret) { return w; }
            } else if (w.pitch === pitch) {
                return w;
            }
        }
        return null;
    }

    // 第一次往这个位置写音时，第二声部这里会不会盖掉别的东西
    function checkOverwrite() {
        overwriteMsg = "";
        if (!anchor || written.length) { return; }     // 已有和弦时是往里加音，不覆盖
        try {
            var dur = Math.round(4 * division / noteDen);
            var p = newCursor(targetVoice);
            p.rewindToTick(anchor.tick);
            var guard = 0;
            while (p.prev() && guard++ < 64) {
                var e = p.element;
                if (e && (isType(e, "CHORD") || isType(e, "REST"))) {
                    if (isType(e, "CHORD") && p.tick + e.duration.ticks > anchor.tick) {
                        overwriteMsg = tr("第二声部有个从前面延过来的音，写入会把它截断");
                    }
                    break;
                }
            }
            var c = newCursor(targetVoice);
            c.rewindToTick(anchor.tick);
            var guard2 = 0;
            while (c.next() && guard2++ < 64) {
                if (c.tick >= anchor.tick + dur) { break; }
                var e2 = c.element;
                if (e2 && isType(e2, "CHORD")) {
                    overwriteMsg = tr("第二声部在这个%1音符的时值内已经有音，写入会盖掉它").arg(denLabel(noteDen));
                    break;
                }
            }
        } catch (err) { }
    }

    function warnings() {
        var out = [];
        if (!anchor) { return out; }
        if (!anchor.hasTuning) { out.push(tr("这个乐器没有调弦信息，按标准 EADGBE 算的")); }
        if (anchor.guessed) { out.push(tr("旋律音的弦是猜的（在六线谱上选音会更准）")); }
        if (overwriteMsg) { out.push(overwriteMsg); }
        return out;
    }

    // =====================================================================
    //  计算
    // =====================================================================

    function rebuild() {
        if (!anchor) { return; }
        fb = anchor.board;

        var base = Theory.parseChord(chordText);
        if (!base.ok) {
            spec = base;
            grid = [];
            statusMsg = tr(base.error || "和弦认不出来");
            return;
        }
        var s = Theory.applyMods(base, mods);

        // 关掉的音级
        var keep = [];
        for (var i = 0; i < s.degrees.length; i++) {
            if (!offDegrees[s.degrees[i].label]) { keep.push(s.degrees[i].label); }
        }
        var eff = Theory.filterDegrees(s, keep);
        spec = s;                       // 显示用（含被关掉的），高亮用 eff

        var pcMap = Theory.pitchClassMap(eff);
        var win = FB.windowFromCenter(winCenter, winSpan, fb.frets);

        var cells = FB.buildGrid(fb, eff, pcMap, {
            loFret: win.lo, hiFret: win.hi,
            melodyString: anchor.string, melodyFret: anchor.fret,
            blockMelodyString: blockMelodyString
        });

        // 建 grid[string][fret] 索引，界面按坐标取格子
        var g = [];
        for (var st = 0; st < fb.nStrings; st++) {
            var row = [];
            for (var f = 0; f <= fb.frets; f++) { row.push(null); }
            g.push(row);
        }
        for (var k = 0; k < cells.length; k++) {
            if (cells[k].fret === 0) { cells[k].inWindow = true; }   // 空弦一直可用
            g[cells[k].string][cells[k].fret] = cells[k];
        }
        grid = g;

        statusMsg = "";
        if (s.warnings && s.warnings.length) { statusMsg = s.warnings.map(trWarn).join(tr("；")); }
        checkOverwrite();
    }

    // =====================================================================
    //  交互
    // =====================================================================

    function moveWindow(delta) {
        var c = winCenter + delta;
        if (c < 0) { c = 0; }
        if (fb && c > fb.frets) { c = fb.frets; }
        winCenter = c;
        rebuild();
    }

    function setSpan(n) { winSpan = n; rebuild(); }

    function setDen(d) {
        noteDen = d;
        written = readWritten();
        if (anchor && written.length && writtenDen !== d) { rewriteDuration(d); }
        checkOverwrite();
    }

    // 这一拍第二声部已经有和弦：按新时值重写一遍（同一步撤销里删掉，再用同样的音、弦、品写回）。
    // 变长会盖掉后面紧挨着的第二声部音（和新写一个长音一样），变短会在后面留休止符。
    function rewriteDuration(d) {
        var notes = [];
        for (var i = 0; i < written.length; i++) {
            notes.push({ pitch: written[i].pitch, string: written[i].string, fret: written[i].fret });
        }
        var covered = 0;
        try {
            var newTicks = Math.round(4 * division / d);
            var scan = newCursor(targetVoice);
            scan.rewindToTick(anchor.tick);
            var guard = 0;
            while (scan.next() && guard++ < 64) {
                if (scan.tick >= anchor.tick + newTicks) { break; }
                var e = scan.element;
                if (e && isType(e, "CHORD")) { covered++; }
            }
        } catch (e0) { }

        var ok = false;
        try {
            suppressRefresh = true;
            curScore.startCmd(tr("和弦助手：改时值 ") + denLabel(d));
            for (var k = 0; k < written.length; k++) { removeElement(written[k].el); }
            var c = newCursor(targetVoice);
            c.rewindToTick(anchor.tick);
            c.setDuration(1, d);
            c.addNote(notes[0].pitch);
            for (var j = 1; j < notes.length; j++) { c.addNote(notes[j].pitch, true); }
            // 钉回弦品：按音高逐个配
            c.rewindToTick(anchor.tick);
            var el = c.element;
            if (el && isType(el, "CHORD")) {
                var ns = el.notes;
                var used = [];
                for (var a = 0; a < ns.length; a++) {
                    for (var b = 0; b < notes.length; b++) {
                        if (used.indexOf(b) >= 0 || notes[b].pitch !== ns[a].pitch) { continue; }
                        if (notes[b].string >= 0 && notes[b].fret >= 0) {
                            ns[a].string = notes[b].string;
                            ns[a].fret = notes[b].fret;
                        }
                        used.push(b);
                        break;
                    }
                }
            }
            curScore.endCmd();
            ok = true;
        } catch (err) {
            statusMsg = tr("改时值失败: ") + err;
            try { curScore.endCmd(true); } catch (e2) { }
        } finally {
            suppressRefresh = false;
        }
        written = readWritten();
        if (ok) {
            statusMsg = tr("这一拍第二声部改成%1音符").arg(denLabel(d))
                        + (covered ? tr("，盖掉了后面 %1 个第二声部的音").arg(covered) : "") + tr("。Ctrl+Z 撤销");
        }
    }

    function toggleMod(m) {
        var out = [];
        var found = false;
        for (var i = 0; i < mods.length; i++) {
            if (mods[i] === m) { found = true; } else { out.push(mods[i]); }
        }
        if (!found) { out.push(m); }
        mods = out;
        rebuild();
    }

    function toggleDegree(label) {
        var o = {};
        for (var k in offDegrees) { if (offDegrees.hasOwnProperty(k)) { o[k] = offDegrees[k]; } }
        o[label] = !o[label];
        offDegrees = o;
        rebuild();
    }

    function onlyTriad() {
        var o = {};
        if (spec && spec.ok) {
            for (var i = 0; i < spec.degrees.length; i++) {
                var l = spec.degrees[i].label;
                if (["1", "3", "b3", "5", "b5", "#5", "2", "4"].indexOf(l) < 0) { o[l] = true; }
            }
        }
        offDegrees = o;
        rebuild();
    }

    function cellClickable(cell) {
        return !!(cell && cell.inWindow && !cell.blocked && !cell.isMelody && cell.degree !== null);
    }

    // 点格子：没写过就写进去；写过了就删掉；同一根弦上已有别的品位就替换
    function clickCell(cell) {
        if (!anchor || !cellClickable(cell)) { return; }
        written = readWritten();                 // 以谱面为准，别信缓存
        var same = findWritten(written, cell.string, cell.fret, cell.pitch);
        if (same) { removeCellNote(same); return; }
        var onString = null;
        for (var i = 0; i < written.length; i++) {
            if (written[i].string === cell.string) { onString = written[i]; break; }
        }
        addCellNote(cell, onString);
    }

    function sfKeys(list) {
        var keys = [];
        for (var i = 0; i < list.length; i++) { keys.push(list[i].string + ":" + list[i].fret); }
        return keys;
    }

    // 刚加进和弦的那个音：MuseScore 自己挑的弦不一定是我们点的那根，把弦和品钉回去。
    // string 和 fret 要一起写，只写 string 品位会留在旧值上。
    function pinNewNote(cell, beforeKeys) {
        var c = newCursor(targetVoice);
        c.rewindToTick(anchor.tick);
        var el = c.element;
        if (!el || !isType(el, "CHORD")) { return false; }
        var ns = el.notes;
        var pick = null, fallback = null;
        for (var i = 0; i < ns.length; i++) {
            if (ns[i].pitch !== cell.pitch) { continue; }
            var key = "?";
            try { key = ns[i].string + ":" + ns[i].fret; } catch (e) { }
            if (beforeKeys.indexOf(key) < 0) { pick = ns[i]; break; }
            fallback = ns[i];
        }
        if (!pick) { pick = fallback; }
        if (!pick) { return false; }
        pick.string = cell.string;
        pick.fret = cell.fret;
        return true;
    }

    function addCellNote(cell, replace) {
        var label = noteLabel(cell.pitch, cell.string, cell.fret);
        var ok = false;
        try {
            suppressRefresh = true;
            curScore.startCmd(tr("和弦助手：写入 ") + label);
            var before = sfKeys(written);
            var c = newCursor(targetVoice);
            c.rewindToTick(anchor.tick);
            if (written.length === 0) {
                // 这里还没有第二声部的和弦：按选好的时值新建一个
                c.setDuration(1, noteDen);
                c.addNote(cell.pitch);
            } else if (replace && written.length > 1) {
                // 同一根弦换品位，和弦里还有别的音：先删旧的再加新的
                removeElement(replace.el);
                c.rewindToTick(anchor.tick);
                c.addNote(cell.pitch, true);
            } else {
                // 往已有的和弦里加一个音（同弦替换且只剩这一个音时也走这里，删旧的放在后面，
                // 不然和弦变成休止符就加不进去了）
                c.addNote(cell.pitch, true);
            }
            pinNewNote(cell, before);
            if (replace && written.length <= 1) { removeElement(replace.el); }
            curScore.endCmd();
            ok = true;
        } catch (e) {
            statusMsg = tr("写入失败: ") + e;
            try { curScore.endCmd(true); } catch (e2) { }
        } finally {
            suppressRefresh = false;
        }
        written = readWritten();
        checkOverwrite();
        if (ok) {
            statusMsg = tr("已写入 ") + label + (replace ? tr("，替换了同弦上的 ") + noteName(replace.pitch) : "")
                        + tr("。再点一次删掉，Ctrl+Z 撤销");
        }
    }

    function removeCellNote(w) {
        var label = noteLabel(w.pitch, w.string, w.fret);
        var ok = false;
        try {
            suppressRefresh = true;
            curScore.startCmd(tr("和弦助手：删除 ") + label);
            var last = written.length <= 1;
            removeElement(w.el);
            if (last) {
                // 和弦里最后一个音删掉后 MuseScore 会留一个休止符；第二声部的休止符再删一次就变成不显示的空拍
                var c = newCursor(targetVoice);
                c.rewindToTick(anchor.tick);
                var r = c.element;
                if (r && isType(r, "REST") && c.tick === anchor.tick) { removeElement(r); }
            }
            curScore.endCmd();
            ok = true;
        } catch (e) {
            statusMsg = tr("删除失败: ") + e;
            try { curScore.endCmd(true); } catch (e2) { }
        } finally {
            suppressRefresh = false;
        }
        written = readWritten();
        checkOverwrite();
        if (ok) { statusMsg = tr("已删掉 ") + label + tr("。Ctrl+Z 撤销"); }
    }

    // ←/→：跳到上一个 / 下一个旋律音（或休止符），在谱面上选中它，面板跟着过去
    function gotoMelody(dir) {
        if (!anchor || !curScore) { return; }
        var target = null;
        try {
            var c = newCursor(melodyVoice);
            c.rewindToTick(anchor.tick);
            var guard = 0;
            while (guard++ < 5000) {
                var moved = dir > 0 ? c.next() : c.prev();
                if (!moved || !c.segment) { break; }
                var e = c.element;
                if (!e) { continue; }
                if (isType(e, "CHORD")) {
                    var ns = e.notes;
                    target = ns[0];
                    for (var i = 1; i < ns.length; i++) { if (ns[i].pitch > target.pitch) { target = ns[i]; } }
                    break;
                }
                if (isType(e, "REST")) { target = e; break; }
            }
        } catch (err) { }
        if (!target) {
            statusMsg = dir > 0 ? tr("后面没有旋律音了") : tr("前面没有旋律音了");
            return;
        }
        try { curScore.selection.select(target, false); } catch (e2) { }
        refreshFromScore(false);
    }

    // =====================================================================
    //  生命周期
    // =====================================================================

    // 贴到 MuseScore 主窗口底部，宽度跟主窗口一样（留 8 px 边）。
    // 插件引擎的根上下文里有 ui（主程序的 UiEngine），ui.rootItem 是主窗口的根 Item，
    // mapToGlobal 给的是屏幕上的逻辑坐标，和 Window 的 x/y 同一套。
    function snapToBottom() {
        try {
            var r = ui.rootItem;
            if (!r || !r.width) { return false; }
            var g = r.mapToGlobal(0, 0);
            var margin = 8;
            // 不改宽度：按现在的宽度在主窗口底部居中；比主窗口还宽才缩到主窗口的宽度
            if (win.width > r.width - 2 * margin) { win.width = Math.max(win.minimumWidth, r.width - 2 * margin); }
            win.x = Math.round(g.x + (r.width - win.width) / 2);
            win.y = Math.round(g.y + r.height - win.height - margin);
            return true;
        } catch (e) {
            return false;
        }
    }

    function showWindow() {
        if (!placed) { placed = snapToBottom(); }
        win.show();
        win.raise();
        win.requestActivate();
        rootRect.forceActiveFocus();
    }

    onRun: {
        // 已经有一个窗口开着（或被关掉藏起来了），就把它叫出来、按当前选区刷新，不再开新的
        var prev = Instance.plugin;
        if (prev && prev !== root) {
            try { prev.refreshFromScore(true); prev.showWindow(); return; } catch (e) { }
        }
        Instance.plugin = root;
        loadLang();
        refreshFromScore(true);
        showWindow();
    }

    // 选区的简短签名。范围选区只看起止位置，不去取 elements（全选大谱时那是几千个对象）
    function selectionSig() {
        try {
            if (!curScore) { return ""; }
            var sel = curScore.selection;
            if (sel.isRange) {
                return "R" + (sel.startSegment ? sel.startSegment.tick : -1) + ":" + sel.startStaff
                       + ":" + (sel.endSegment ? sel.endSegment.tick : -1) + ":" + sel.endStaff;
            }
            var els = sel.elements;
            var rest = null;
            for (var i = 0; i < els.length; i++) {
                if (isType(els[i], "NOTE")) {
                    var n = els[i];
                    return "N" + n.staffIdx + ":" + n.parent.parent.tick + ":" + n.pitch + ":" + n.string;
                }
                if (!rest && isType(els[i], "REST")) { rest = els[i]; }
            }
            if (rest) { return "S" + rest.staffIdx + ":" + rest.parent.tick; }
            return "E" + els.length;
        } catch (e) {
            return "";
        }
    }

    // 跟随选区。4.x 里 onScoreStateChanged 不会触发，所以定时看一眼。
    // 每隔一次顺便看看锚点处的和弦记号和第二声部有没有被改（Ctrl+K 加记号、Ctrl+Z 撤销）。
    Timer {
        interval: 600
        repeat: true
        running: win.visible && followSelection
        onTriggered: {
            if (suppressRefresh) { return; }
            if (selectionSig() !== lastSelSig) { refreshFromScore(false); return; }
            if (!anchor) { return; }
            if (++pollTicks % 2 !== 0) { return; }
            var changed = false;
            if (harmonyAt(anchor.tick) !== scoreChord) { syncChord(false); changed = true; }
            var w = readWritten();
            if (writtenSig(w) !== writtenSig(written)) { written = w; changed = true; }
            if (changed) { rebuild(); }
        }
    }

    // 面板里的和弦跟谱面记号的规则：谱面有记号以谱面为准；手改过的只在当前这个记号的范围内保留，
    // 锚点走进另一个记号的范围（或记号本身被改了）就换成谱面的；勾了「锁定」就完全不跟。
    // force = 手动打开 / 点刷新，这时不管锁没锁都重读一次。
    function syncChord(force) {
        if (!anchor) { return; }
        var h = harmonyAt(anchor.tick);
        if (chordLocked && !force) { return; }
        if (force || h !== scoreChord) {
            scoreChord = h;
            if (h) {
                chordText = h;
                mods = [];
                offDegrees = ({});
            }
        }
    }

    function refreshFromScore(force) {
        lastSelSig = selectionSig();
        var a = readAnchor();
        if (!a) {
            if (anchor) {
                // 选中的不是音符也不是休止符（比如刚 Ctrl+K 完，选中的是和弦记号）：锚点不动，只重读和弦
                syncChord(force);
                written = readWritten();
                rebuild();
                return;
            }
            statusMsg = tr("请先在谱面上选中一个旋律音或休止符（在联动的六线谱上选，弦品更准）");
            anchor = null;
            grid = [];
            written = [];
            return;
        }
        anchor = a;
        if (a.fret >= 0) { winCenter = a.fret; }
        syncChord(force);
        written = readWritten();
        rebuild();
    }

    onScoreStateChanged: function (state) {
        if (!followSelection || suppressRefresh) { return; }
        if (state.undoRedo) { return; }
        if (state.selectionChanged) { refreshFromScore(false); }
    }

    // =====================================================================
    //  自己画的扁平控件（系统原生样式的按钮和勾选框在深色面板上太突兀）
    // =====================================================================

    component FlatButton: Rectangle {
        id: btn
        property string text: ""
        property bool primary: false
        property int padding: 12
        signal clicked()
        implicitWidth: btnLbl.implicitWidth + padding * 2
        implicitHeight: 28
        radius: 6
        color: !enabled ? cPanel2
               : primary ? (btnMa.containsMouse ? cAccentHi : cAccent)
                         : (btnMa.containsMouse ? cBtnHi : cBtn)
        Text {
            id: btnLbl
            anchors.centerIn: parent
            text: btn.text
            color: btn.enabled ? "#ffffff" : cDim
            font.pixelSize: 12
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // 勾选框：checked 由外面绑定，点击只发 toggled，外面改状态后绑定自己会更新
    component FlatCheck: Item {
        id: chk
        property string text: ""
        property bool checked: false
        signal toggled(bool value)
        implicitWidth: chkRow.implicitWidth
        implicitHeight: 22
        Row {
            id: chkRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle {
                width: 16; height: 16; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: chk.checked ? cAccent : "transparent"
                border.color: chk.checked ? cAccent : "#6b6f76"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    visible: chk.checked
                    text: "✓"; color: "#ffffff"; font.pixelSize: 11; font.bold: true
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chk.text; color: cDim; font.pixelSize: 12
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chk.toggled(!chk.checked)
        }
    }

    // 小开关（扩展音、把位跨度、时值这类一排里选一个或多个）
    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool on: false
        property color activeColor: cAccent
        property color activeText: "#ffffff"
        property int minWidth: 0
        signal clicked()
        width: Math.max(minWidth, chipTxt.implicitWidth + 16)
        height: 24
        radius: 5
        color: on ? activeColor : (chipMa.containsMouse ? cPanel2 : "transparent")
        border.color: on ? activeColor : cLine
        border.width: 1
        Text {
            id: chipTxt
            anchors.centerIn: parent
            text: chip.text
            color: chip.on ? chip.activeText : cText
            font.pixelSize: 11
            font.bold: chip.on
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component SectionLabel: Text {
        color: cDim
        font.pixelSize: 11
        font.letterSpacing: 1
    }

    // 「当前位置」那一行里的一项：小字说明 + 值
    component Kv: Row {
        property string caption: ""
        property string value: ""
        property color valueColor: cText
        spacing: 5
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.caption; color: cDim; font.pixelSize: 10 }
        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.value; color: parent.valueColor
               font.pixelSize: 12; font.bold: true }
    }

    // =====================================================================
    //  界面：一条矮而宽的横条，贴在谱面下方用，尽量少挡谱
    // =====================================================================

    Window {
        id: win
        title: tr("和弦助手")
        width: 1180
        height: 230
        minimumWidth: 900
        minimumHeight: 170
        visible: false
        color: cBg
        // 标题栏和按钮要明确写上：在 Windows 上，flags 只要不是单纯的 Qt.Window，Qt 就不会自动加标题栏，窗口会拖不动。
        // 置顶只在 MuseScore 是当前应用时生效，切到别的应用就不挡着。
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint
               | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
               | (Qt.application.state === Qt.ApplicationActive ? Qt.WindowStaysOnTopHint : 0)

        Rectangle {
            id: rootRect
            anchors.fill: parent
            color: cBg
            focus: true

            // 独立窗口里，MuseScore 的全局快捷键（方向键挪选区、Esc……）会先抢键。
            // 这里把自己要用的键认领下来，它们才会送到下面的 Keys.onPressed。
            Keys.onShortcutOverride: function (event) {
                if (chordField.activeFocus) { event.accepted = true; return; }
                var k = event.key;
                if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Escape) {
                    event.accepted = true;
                }
            }

            Keys.onPressed: function (event) {
                if (chordField.activeFocus) {
                    if (event.key === Qt.Key_Escape) { rootRect.forceActiveFocus(); event.accepted = true; }
                    return;
                }
                switch (event.key) {
                case Qt.Key_Left:
                    if (event.modifiers & Qt.ShiftModifier) { moveWindow(-1); } else { gotoMelody(-1); }
                    event.accepted = true; break;
                case Qt.Key_Right:
                    if (event.modifiers & Qt.ShiftModifier) { moveWindow(1); } else { gotoMelody(1); }
                    event.accepted = true; break;
                case Qt.Key_Escape:
                    // 只是把窗口藏起来，插件对象还在；下次从菜单运行会把它叫回来
                    win.close();
                    event.accepted = true; break;
                default:
                    break;
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 12

                // ======== 左：指板（空弦列 + 把位窗口里的品） ========
                Rectangle {
                    id: fretPanel
                    Layout.fillHeight: true
                    Layout.preferredWidth: gridW + 20
                    Layout.minimumWidth: gridW + 20
                    color: cPanel
                    radius: 6
                    clip: true

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        // 品位刻度
                        Row {
                            spacing: 2
                            Item { width: 34; height: 14 }
                            Repeater {
                                model: shownFrets
                                Item {
                                    width: cellW + fretGap(modelData); height: 14
                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: (cellW - implicitWidth) / 2
                                        text: modelData
                                        color: cText
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }

                        // 六根弦
                        Repeater {
                            model: fb ? fb.nStrings : 0
                            Row {
                                property int strIdx: index
                                spacing: 2

                                Item {
                                    width: 34; height: cellH
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (strIdx + 1) + "·" + Theory.pcName(fb.open[strIdx] % 12)
                                        color: (anchor && anchor.string === strIdx) ? cWarn : cDim
                                        font.pixelSize: 10
                                    }
                                }

                                Repeater {
                                    model: shownFrets
                                    Item {
                                        property int fret: modelData
                                        width: cellW + fretGap(fret); height: cellH
                                        // 这些属性放在 delegate 根上，下面的 Text / MouseArea 才看得见
                                        property var cell: (grid.length > strIdx && grid[strIdx].length > fret)
                                                           ? grid[strIdx][fret] : null
                                        property var wn: cell ? findWritten(written, strIdx, fret, cell.pitch) : null
                                        property bool clickable: cellClickable(cell)
                                        property color degColor: (cell && cell.degree !== null) ? Theory.degreeColor(cell.degree) : cLine

                                        Rectangle {
                                            anchors.right: parent.right
                                            width: cellW; height: cellH; radius: 5

                                            color: {
                                                if (!cell) { return cCellOut; }
                                                if (cell.isMelody) { return cMelody; }
                                                if (wn) { return degColor; }
                                                if (clickable && cellMa.containsMouse) { return "#34383e"; }
                                                return cCell;
                                            }
                                            border.width: (clickable && cellMa.containsMouse) ? 2 : 1
                                            border.color: {
                                                if (!cell) { return "transparent"; }
                                                if (cell.isMelody) { return cMelody; }
                                                if (wn) { return "#ffffff"; }
                                                if (cell.blocked) { return "#3a3d43"; }
                                                if (cell.degree !== null) { return degColor; }
                                                return "transparent";
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: cell !== null && (cell.isMelody || cell.degree !== null)
                                                text: cell ? (cell.isMelody ? "M" : Theory.prettyDegree(cell.degree || "")) : ""
                                                color: {
                                                    if (!cell) { return cDim; }
                                                    if (cell.isMelody || wn) { return "#1e1e1e"; }
                                                    if (cell.blocked) { return "#5a5e66"; }
                                                    return degColor;
                                                }
                                                font.pixelSize: cellH >= 24 ? 12 : 10
                                                font.bold: wn !== null || (cell && cell.isMelody)
                                            }

                                            MouseArea {
                                                id: cellMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: { clickCell(cell); rootRect.forceActiveFocus(); }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ======== 右：控件四行 ========
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    // 行 1：和弦 · 扩展音 · 开关。用 Flow 不用 RowLayout：标签变长（英文）或窗口变窄时整行换行，
                    // 不会把中间的扩展音挤成一列
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        // 不用 QtQuick.Controls 的 TextField：系统原生样式会无视自定义背景，画出来一个白框
                        Rectangle {
                            width: 120
                            height: 26
                            color: cBg; radius: 6
                            border.color: chordField.activeFocus ? cAccentHi : cLine
                            border.width: 1
                            TextInput {
                                id: chordField
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                text: chordText
                                color: cText
                                selectionColor: cAccent
                                selectByMouse: true
                                clip: true
                                font.pixelSize: 16
                                font.bold: true
                                onTextChanged: { chordText = text; rebuild(); }
                                onAccepted: rootRect.forceActiveFocus()
                                // 不然 Backspace、方向键、Ctrl+Z 会被 MuseScore 的全局快捷键抢走
                                Keys.onShortcutOverride: function (event) { event.accepted = true; }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onPressed: function (mouse) { chordField.forceActiveFocus(); mouse.accepted = false; }
                            }
                        }

                        Repeater {
                            model: Theory.AVAILABLE_MODS
                            Chip {
                                text: modelData
                                on: mods.indexOf(modelData) >= 0
                                onClicked: toggleMod(modelData)
                            }
                        }
                        Item { width: 8; height: 1 }

                        FlatCheck {
                            text: tr("跟随选区")
                            checked: followSelection
                            onToggled: { followSelection = value; }
                        }
                        FlatCheck {
                            text: tr("锁定和弦")
                            checked: chordLocked
                            onToggled: { chordLocked = value; if (!value) { syncChord(false); rebuild(); } }
                        }
                        Repeater {
                            // 只给 EN / 中 两档，"中"是繁体；简体的支持还在，只是先不放出来
                            model: [["en", "EN"], ["zh-Hant", "中"]]
                            Chip { text: modelData[1]; on: lang === modelData[0]; onClicked: setLang(modelData[0]) }
                        }
                        FlatButton { text: tr("刷新"); implicitHeight: 24; onClicked: refreshFromScore(true) }
                        FlatButton { text: tr("贴底"); implicitHeight: 24; onClicked: { snapToBottom(); rootRect.forceActiveFocus(); } }
                    }

                    // 行 2：组成音 · 把位 · 时值（窄的时候自动换行）
                    Flow {
                        Layout.fillWidth: true
                        spacing: 16

                        Row {
                            spacing: 4
                            SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: tr("组成音") }
                            Repeater {
                                model: (spec && spec.ok) ? spec.degrees : []
                                Chip {
                                    text: Theory.prettyDegree(modelData.label)
                                    on: !offDegrees[modelData.label]
                                    activeColor: Theory.degreeColor(modelData.label)
                                    activeText: "#1e1e1e"
                                    minWidth: 32
                                    onClicked: toggleDegree(modelData.label)
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                leftPadding: 4
                                text: tr("只留三和弦"); color: "#7aa7d9"; font.pixelSize: 11
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: onlyTriad() }
                            }
                        }

                        Row {
                            spacing: 4
                            SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: tr("把位") }
                            FlatButton { text: "◂"; padding: 7; implicitHeight: 24; onClicked: moveWindow(-1) }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: fb ? (winLo + "–" + winHi + tr(" 品")) : "—"
                                color: cText; font.pixelSize: 12; font.bold: true
                            }
                            FlatButton { text: "▸"; padding: 7; implicitHeight: 24; onClicked: moveWindow(1) }
                            Repeater {
                                model: [1, 2, 3, 4, 5]
                                Chip {
                                    text: "±" + modelData
                                    on: winSpan === modelData
                                    onClicked: setSpan(modelData)
                                }
                            }
                        }

                        Row {
                            spacing: 4
                            SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: tr("时值") }
                            Repeater {
                                model: [4, 8, 16]
                                Chip {
                                    text: denLabel(modelData)
                                    on: shownDen === modelData
                                    onClicked: setDen(modelData)
                                }
                            }
                        }
                    }

                    // 行 3：当前位置
                    Flow {
                        Layout.fillWidth: true
                        spacing: 18
                        Kv {
                            caption: tr("位置")
                            value: anchor ? tr("第 %1 小节 第 %2 拍").arg(anchor.measureNo).arg(anchor.beat) : "—"
                        }
                        Kv {
                            caption: tr("记号")
                            value: scoreChord ? scoreChord : tr("无")
                            valueColor: scoreChord ? cText : cDim
                        }
                        Kv {
                            caption: tr("旋律")
                            value: !anchor ? "—" : anchor.isRest ? tr("休止符") : noteLabel(anchor.pitch, anchor.string, anchor.fret)
                            valueColor: (anchor && !anchor.isRest) ? cMelody : cDim
                        }
                        Kv {
                            caption: tr("第二声部")
                            value: writtenText(written)
                            valueColor: (written && written.length) ? "#89d185" : cDim
                        }
                        Text {
                            visible: !anchor
                            color: cWarn; font.pixelSize: 12
                            text: tr("在谱面上选中一个旋律音")
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // 行 4：状态 · 提醒 · 开关。地方不够时先藏快捷键提示
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            Layout.fillWidth: true
                            color: statusMsg.indexOf("✗") === 0 || statusMsg.indexOf(tr("失败")) >= 0 ? cErr : cDim
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            text: statusMsg
                        }
                        Text {
                            color: cWarn
                            font.pixelSize: 11
                            elide: Text.ElideLeft
                            Layout.maximumWidth: 360
                            // 依赖 anchor / overwriteMsg，它们变了这里会重算
                            text: {
                                var w = warnings();
                                return w.length ? ("⚠ " + w.join("  ·  ")) : "";
                            }
                        }
                        FlatCheck {
                            text: tr("旋律所在弦不参与")
                            checked: blockMelodyString
                            onToggled: { blockMelodyString = value; rebuild(); }
                        }
                        Text {
                            visible: win.width >= 1250
                            color: cDim; font.pixelSize: 10
                            text: tr("← → 上/下一个旋律音 · Shift+←→ 移把位 · Esc 关闭")
                        }
                    }
                }
            }
        }
    }
}

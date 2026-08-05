//=============================================================================
//  和弦助手 Chord Assist  v0.1
//
//  指弹编曲流程里「旋律敲完之后」那一步：
//  选中旋律音 → 面板按和弦在把位窗口里高亮可选音 → 点选成型 → 切分时值 → 回车写入第二声部。
//
//  乐理和指板的计算全在 core/*.js 里，纯函数，可以用 node test/test.js 单独测。
//  这个文件只管界面和跟 MuseScore 打交道。
//=============================================================================

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MuseScore 3.0

import "core/theory.js"    as Theory
import "core/fretboard.js" as FB
import "core/shape.js"     as ShapeLib
import "core/slots.js"     as SlotsLib

MuseScore {
    id: root

    title: "和弦助手"
    description: "按和弦在把位窗口里提示可选音，点选成型后一次性写入第二声部"
    version: "0.1"
    pluginType: "dialog"
    requiresScore: true
    categoryCode: "composing-arranging-tools"

    width: 940
    height: 640
    implicitWidth: 940
    implicitHeight: 640

    // ---- 配色 ----------------------------------------------------------
    readonly property color cBg:      "#1e2126"
    readonly property color cPanel:   "#15171a"
    readonly property color cLine:    "#33373d"
    readonly property color cText:    "#e8eaed"
    readonly property color cDim:     "#9aa0a6"
    readonly property color cCell:    "#23272d"
    readonly property color cCellOut: "#1a1c20"

    // ---- 状态 ----------------------------------------------------------
    property var  fb: null                  // 指板模型
    property var  anchor: null              // 锚点 {tick, staffIdx, pitch, string, fret, measureNo, beat, beatDen}
    property string chordText: "Am7"
    property var  mods: []                  // 扩展音按钮
    property var  offDegrees: ({})          // 被关掉的音级 label -> true
    property int  winCenter: 5
    property int  winSpan: 3
    property var  grid: []                  // grid[string][fret] = cell
    property var  cellList: []
    property var  spec: null                // 生效的 ChordSpec
    property var  shape: null
    property var  slotList: []
    property int  focusedSlot: 0
    property int  totalBeats: 2
    property bool blockMelodyString: true
    property bool followSelection: true
    property string statusMsg: ""
    property string overwriteMsg: ""
    property int  targetVoice: 1            // voice 索引 0 起算，1 = 第二声部
    property int  melodyVoice: 0            // 旋律在 voice 1
    property int  displayFrets: 15
    property bool suppressRefresh: false    // 自己写谱期间挡掉 scoreStateChanged 回调
    property bool autoAdvance: true         // 插入后自动跳到下一个旋律音

    readonly property int cellW: 46
    readonly property int cellH: 30

    // =====================================================================
    //  与 MuseScore 打交道
    // =====================================================================

    // el.type 在 apiversion 1 下是整数，v2 下是 "NOTE" 这样的字符串。
    // 这个插件按 v1 写，但万一被当成 v2 加载，用 === 比整数会一声不响全部失配，
    // 整个插件看起来「什么都没选中」。所以两种都认。
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

    // 从选区读锚点。选中的音在五线谱上时 string 会是 -1，那就按音高猜一个位置。
    function readAnchor() {
        if (!curScore) { return null; }
        var note = null;
        try {
            var els = curScore.selection.elements;
            for (var i = 0; i < els.length; i++) {
                if (isType(els[i], "NOTE")) { note = els[i]; break; }
            }
        } catch (e) { return null; }
        if (!note) { return null; }

        var staffIdx = note.staffIdx;
        var tick, voice;
        try { tick = note.parent.parent.tick; } catch (e2) { return null; }
        try { voice = note.voice; } catch (e3) { voice = 0; }

        var sd = currentStringData(staffIdx);
        var hasTuning = false;
        try { hasTuning = !!(sd && sd.strings && sd.strings.length > 0); } catch (eSd) { }
        var board = FB.fromApiStringData(sd);   // 读不到就退回标准调弦

        var str = -1, fr = -1;
        try { str = note.string; } catch (e4) { }
        try { fr = note.fret; } catch (e5) { }

        var guessed = false;
        if (str === undefined || str === null || str < 0 || fr < 0) {
            var g = FB.guessMelodyPosition(board, note.pitch);
            if (g) { str = g.string; fr = g.fret; guessed = true; }
        }

        var mb = measureAndBeat(tick);

        return {
            tick: tick, staffIdx: staffIdx, voice: voice,
            pitch: note.pitch, string: str, fret: fr, guessed: guessed,
            measureNo: mb.measureNo, beat: mb.beat, beatDen: mb.beatDen,
            measureTick: mb.measureTick, measureTicks: mb.measureTicks,
            hasTuning: hasTuning, board: board
        };
    }

    // 插入前把能预见的问题都摆出来，别让用户按了回车才发现不对
    function preflight() {
        var out = [];
        if (!anchor) { return ["没有锚点"]; }

        if (anchor.voice === targetVoice) {
            out.push("你选中的音本身就在第二声部，插入会覆盖它 —— 确认一下是不是点错了行");
        }
        if (!anchor.hasTuning) {
            out.push("这个乐器没有调弦信息，按标准 EADGBE 算的");
        }
        if (anchor.guessed) {
            out.push("旋律音的弦是猜的（在六线谱上选音会更准）");
        }
        if (shape && shape.warnings.length > 0) {
            for (var i = 0; i < shape.warnings.length; i++) { out.push(shape.warnings[i]); }
        }
        // 跨小节：MuseScore 会自动拆开加连音线，不算错，但提前说一声
        if (anchor.measureTicks > 0) {
            var used = anchor.tick - anchor.measureTick;
            var need = 0;
            for (var k = 0; k < slotList.length; k++) {
                need += SlotsLib.fracToTicks(slotList[k].frac, division);
            }
            if (used + need > anchor.measureTicks) {
                out.push("总时值超出本小节，会跨到下一小节（MuseScore 自动拆分加连音线）");
            }
        }
        if (overwriteMsg) { out.push(overwriteMsg.replace("⚠ ", "")); }
        return out;
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

    // 目标区间里已经有东西吗
    function checkOverwrite() {
        overwriteMsg = "";
        if (!anchor || !slotList.length) { return; }
        var totalTicks = 0;
        for (var i = 0; i < slotList.length; i++) {
            totalTicks += SlotsLib.fracToTicks(slotList[i].frac, division);
        }
        try {
            var c = curScore.newCursor();
            c.staffIdx = anchor.staffIdx;
            c.voice = targetVoice;
            c.rewindToTick(anchor.tick);
            var hit = 0;
            while (c.segment && c.tick < anchor.tick + totalTicks) {
                var el = c.element;
                if (el && isType(el, "CHORD")) { hit++; }
                if (!c.next()) { break; }
            }
            if (hit > 0) {
                overwriteMsg = "⚠ 这一段第二声部已经有 " + hit + " 个和弦，插入会覆盖掉";
            }
        } catch (e) { }
    }

    // =====================================================================
    //  重新计算
    // =====================================================================

    function rebuild(resuggest) {
        if (!anchor) { return; }
        fb = anchor.board;

        var base = Theory.parseChord(chordText);
        if (!base.ok) {
            spec = base;
            grid = [];
            cellList = [];
            statusMsg = base.error || "和弦认不出来";
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
        cellList = cells;

        // 建 grid[string][fret] 索引，界面按坐标取格子
        var g = [];
        for (var st = 0; st < fb.nStrings; st++) {
            var row = [];
            for (var f = 0; f <= fb.frets; f++) { row.push(null); }
            g.push(row);
        }
        for (var k = 0; k < cells.length; k++) {
            g[cells[k].string][cells[k].fret] = cells[k];
        }
        grid = g;

        if (resuggest || !shape || shape.notes.length === 0) {
            shape = ShapeLib.suggest(fb, eff, cells, { maxNotes: 4 });
            rebuildSlots(true);
        } else {
            shape = ShapeLib.analyze(shape, fb);
        }

        statusMsg = "";
        if (s.warnings && s.warnings.length) { statusMsg = s.warnings.join("；"); }
        checkOverwrite();
    }

    function rebuildSlots(refill) {
        var beatDen = anchor ? anchor.beatDen : 4;
        var total = SlotsLib.beatsToFrac(totalBeats, beatDen);
        var n = slotList.length > 0 && !refill ? slotList.length : 2;
        var sl = SlotsLib.makeSlots(total, n);
        if (shape) { sl = SlotsLib.defaultFill(sl, shape); }
        slotList = sl;
        focusedSlot = 0;
        checkOverwrite();
    }

    // =====================================================================
    //  交互
    // =====================================================================

    function onCellClicked(cell) {
        if (!cell || !cell.inWindow || cell.blocked || cell.isMelody) { return; }
        if (cell.degree === null) { return; }
        var sh = ShapeLib.toggleCell(shape, cell, fb);
        shape = ShapeLib.autoBass(sh, spec, fb);
        // 指型变了，重新按默认规则铺一次格子内容
        slotList = SlotsLib.defaultFill(slotList, shape);
        checkOverwrite();
    }

    function moveWindow(delta) {
        var c = winCenter + delta;
        if (c < 0) { c = 0; }
        if (fb && c > fb.frets) { c = fb.frets; }
        winCenter = c;
        rebuild(false);
    }

    function setSpan(n) { winSpan = n; rebuild(false); }

    function toggleMod(m) {
        var out = [];
        var found = false;
        for (var i = 0; i < mods.length; i++) {
            if (mods[i] === m) { found = true; } else { out.push(mods[i]); }
        }
        if (!found) { out.push(m); }
        mods = out;
        rebuild(true);
    }

    function toggleDegree(label) {
        var o = {};
        for (var k in offDegrees) { if (offDegrees.hasOwnProperty(k)) { o[k] = offDegrees[k]; } }
        o[label] = !o[label];
        offDegrees = o;
        rebuild(true);
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
        rebuild(true);
    }

    function splitSlot() {
        var r = SlotsLib.split(slotList, focusedSlot);
        if (!r.ok) { statusMsg = r.error; return; }
        slotList = r.slots;
        statusMsg = "";
        checkOverwrite();
    }

    function mergeSlot() {
        var r = SlotsLib.merge(slotList, focusedSlot);
        if (!r.ok) { statusMsg = r.error; return; }
        slotList = r.slots;
        if (focusedSlot >= slotList.length) { focusedSlot = slotList.length - 1; }
        statusMsg = "";
        checkOverwrite();
    }

    function toggleSlotString(s) {
        slotList = SlotsLib.toggleString(slotList, focusedSlot, s);
    }

    function toggleSlotAll() {
        slotList = SlotsLib.toggleAll(slotList, focusedSlot, shape);
    }

    function changeBeats(d) {
        var b = totalBeats + d;
        if (b < 1) { b = 1; }
        if (b > 16) { b = 16; }
        totalBeats = b;
        rebuildSlots(true);
    }

    // =====================================================================
    //  写入
    // =====================================================================

    function doInsert() {
        if (!anchor || !shape || shape.notes.length === 0) {
            statusMsg = "还没选音";
            return;
        }
        var plan = SlotsLib.toInsertPlan(slotList, shape, division);
        var count = 0;
        for (var i = 0; i < plan.length; i++) { count += plan[i].notes.length; }
        if (count === 0) { statusMsg = "每一格都是空的，没东西可插"; return; }

        var endTick = -1;
        try {
            suppressRefresh = true;
            curScore.startCmd("和弦助手插入");

            var cur = curScore.newCursor();
            cur.staffIdx = anchor.staffIdx;
            cur.voice = targetVoice;
            cur.rewindToTick(anchor.tick);

            var ticks = [];
            var t = anchor.tick;
            for (var k = 0; k < plan.length; k++) {
                var p = plan[k];
                cur.setDuration(p.frac.n, p.frac.d);
                if (p.isRest) {
                    cur.addRest();
                } else {
                    cur.addNote(p.notes[0].pitch);
                    for (var j = 1; j < p.notes.length; j++) {
                        cur.addNote(p.notes[j].pitch, true);
                    }
                }
                ticks.push(t);
                t += p.ticks;
            }

            // 回填弦与品，把指型钉住。
            // MuseScore 自己不会因为 pitch 就选中我们要的弦（fretChords 只保证不冲突），
            // 所以这一步是必须的。string 和 fret 要一起写，只写 string 品位会留在旧值上。
            applyFingering(ticks, plan);

            curScore.endCmd();
            endTick = t;
            statusMsg = "已插入 " + count + " 个音，占 " + totalBeats + " 拍。Ctrl+Z 可撤销。";
            overwriteMsg = "";
        } catch (e) {
            statusMsg = "插入失败: " + e;
            try { curScore.endCmd(true); } catch (e2) { }
        } finally {
            suppressRefresh = false;
        }

        // 挪到下一个旋律音。要等 suppressRefresh 放开之后再做，
        // 不然 select() 触发的 scoreStateChanged 会被自己挡掉
        if (endTick >= 0 && autoAdvance) {
            advanceTo(endTick);
        }
    }

    // 插入完成后往后找下一个旋律音，选中它，面板跟着挪过去。
    // 这样配完一个和弦可以直接配下一个，不用回谱面重新点。
    function findNextMelodyNote(fromTick) {
        if (!anchor) { return null; }
        try {
            var c = curScore.newCursor();
            c.staffIdx = anchor.staffIdx;
            c.voice = melodyVoice;
            c.rewindToTick(fromTick);
            while (c.segment) {
                if (c.tick >= fromTick) {
                    var el = c.element;
                    if (el && isType(el, "CHORD")) {
                        var notes = el.notes;
                        var top = notes[0];
                        for (var i = 1; i < notes.length; i++) {
                            if (notes[i].pitch > top.pitch) { top = notes[i]; }
                        }
                        return top;
                    }
                }
                if (!c.next()) { break; }
            }
        } catch (e) { }
        return null;
    }

    function advanceTo(tick) {
        var note = findNextMelodyNote(tick);
        if (!note) {
            statusMsg += "  后面没有旋律音了。";
            return;
        }
        try { curScore.selection.select(note, false); } catch (e) { }
        // pickChord=true：新位置多半有新的和弦记号，顺手读进来
        refreshFromScore(true);
    }

    function applyFingering(ticks, plan) {
        for (var i = 0; i < ticks.length; i++) {
            if (plan[i].isRest) { continue; }
            try {
                var c = curScore.newCursor();
                c.staffIdx = anchor.staffIdx;
                c.voice = targetVoice;
                c.rewindToTick(ticks[i]);
                var el = c.element;
                if (!el || !isType(el, "CHORD")) { continue; }

                var notes = el.notes;
                var wanted = plan[i].notes.slice();
                for (var n = 0; n < notes.length; n++) {
                    for (var w = 0; w < wanted.length; w++) {
                        if (wanted[w] && wanted[w].pitch === notes[n].pitch) {
                            notes[n].string = wanted[w].string;
                            notes[n].fret = wanted[w].fret;
                            wanted[w] = null;
                            break;
                        }
                    }
                }
            } catch (e) { }
        }
    }

    // =====================================================================
    //  生命周期
    // =====================================================================

    onRun: {
        refreshFromScore(true);
    }

    function refreshFromScore(pickChord) {
        var a = readAnchor();
        if (!a) {
            statusMsg = "请先在谱面上选中一个旋律音（在联动的六线谱上选，弦品信息更准）";
            anchor = null;
            grid = [];
            return;
        }
        anchor = a;
        winCenter = a.fret >= 0 ? a.fret : 5;

        // pickChord 只在手动打开/刷新时为真。跟随选区时保留用户设好的
        // 和弦文本、扩展音和音级开关，只把指型按新把位重推一遍。
        if (pickChord) {
            var h = harmonyAt(a.tick);
            if (h) { chordText = h; }
            mods = [];
            offDegrees = ({});
        }
        shape = null;
        rebuild(true);
    }

    onScoreStateChanged: function (state) {
        if (!followSelection) { return; }
        if (suppressRefresh) { return; }         // 自己写谱引发的回调，别跟着跳
        if (state.undoRedo) { return; }          // 撤销重做时也不跟
        if (state.selectionChanged) {
            // 这里只读不写，不会触发递归
            refreshFromScore(false);
        }
    }

    // =====================================================================
    //  界面
    // =====================================================================

    Rectangle {
        id: rootRect
        anchors.fill: parent
        color: cBg
        focus: true

        Keys.onPressed: function (event) {
            if (chordField.activeFocus) {
                if (event.key === Qt.Key_Escape) { rootRect.forceActiveFocus(); event.accepted = true; }
                return;
            }
            switch (event.key) {
            case Qt.Key_Left:
                if (event.modifiers & Qt.ShiftModifier) { moveWindow(-1); }
                else if (focusedSlot > 0) { focusedSlot--; }
                event.accepted = true; break;
            case Qt.Key_Right:
                if (event.modifiers & Qt.ShiftModifier) { moveWindow(1); }
                else if (focusedSlot < slotList.length - 1) { focusedSlot++; }
                event.accepted = true; break;
            case Qt.Key_BracketLeft:  splitSlot(); event.accepted = true; break;
            case Qt.Key_BracketRight: mergeSlot(); event.accepted = true; break;
            case Qt.Key_Space:        toggleSlotAll(); event.accepted = true; break;
            case Qt.Key_Return:
            case Qt.Key_Enter:        doInsert(); event.accepted = true; break;
            case Qt.Key_Escape:
                // 老式插件用 Qt.quit()，MU4 之后 MuseScore 根对象自己有 quit()
                try { root.quit(); } catch (e) { Qt.quit(); }
                event.accepted = true; break;
            default:
                if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) {
                    toggleSlotString(event.key - Qt.Key_1);
                    event.accepted = true;
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // ---------------- 顶栏 ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "和弦助手"
                    color: cText; font.pixelSize: 15; font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    color: cDim; font.pixelSize: 12
                    elide: Text.ElideRight
                    text: anchor
                        ? ("锚点 第 " + anchor.measureNo + " 小节 第 " + anchor.beat + " 拍  ·  旋律 "
                           + Theory.pcName(anchor.pitch % 12) + (Math.floor(anchor.pitch / 12) - 1)
                           + " (" + (anchor.string + 1) + " 弦 " + anchor.fret + " 品"
                           + (anchor.guessed ? "，猜的" : "") + ")")
                        : "没有锚点"
                }
                CheckBox {
                    id: followCb
                    checked: followSelection
                    onToggled: followSelection = checked
                    contentItem: Text {
                        text: "跟随选区"
                        color: cDim; font.pixelSize: 12
                        leftPadding: followCb.indicator.width + 4
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                CheckBox {
                    id: advanceCb
                    checked: autoAdvance
                    onToggled: autoAdvance = checked
                    contentItem: Text {
                        text: "插入后接着下一个"
                        color: cDim; font.pixelSize: 12
                        leftPadding: advanceCb.indicator.width + 4
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Button { text: "刷新"; onClicked: refreshFromScore(true) }
                Button {
                    text: "插入 " + insertCount() + " 个音"
                    enabled: anchor !== null && shape !== null && insertCount() > 0
                    onClicked: doInsert()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: cLine }

            // ---------------- 主体 ----------------
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                // ======== 左栏 ========
                ColumnLayout {
                    Layout.preferredWidth: 260
                    Layout.fillHeight: true
                    spacing: 8

                    Text { text: "和弦"; color: cDim; font.pixelSize: 12 }
                    TextField {
                        id: chordField
                        Layout.fillWidth: true
                        text: chordText
                        color: cText
                        font.pixelSize: 18
                        background: Rectangle { color: cPanel; border.color: cLine; radius: 4 }
                        onTextChanged: { chordText = text; rebuild(true); }
                        onAccepted: rootRect.forceActiveFocus()
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: Theory.AVAILABLE_MODS
                            Rectangle {
                                width: modTxt.width + 14; height: 22; radius: 3
                                color: mods.indexOf(modelData) >= 0 ? "#3a4250" : cPanel
                                border.color: mods.indexOf(modelData) >= 0 ? "#5a7ab0" : cLine
                                Text {
                                    id: modTxt; anchors.centerIn: parent
                                    text: modelData; color: cText; font.pixelSize: 11
                                }
                                MouseArea { anchors.fill: parent; onClicked: toggleMod(modelData) }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "组成音"; color: cDim; font.pixelSize: 12 }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "只留三和弦"; color: "#7aa7d9"; font.pixelSize: 11
                            font.underline: true
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: onlyTriad() }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 5
                        Repeater {
                            model: (spec && spec.ok) ? spec.degrees : []
                            Rectangle {
                                width: 34; height: 26; radius: 4
                                property bool on: !offDegrees[modelData.label]
                                color: on ? Theory.degreeColor(modelData.label) : "transparent"
                                border.color: on ? "transparent" : cLine
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: Theory.prettyDegree(modelData.label)
                                    color: parent.on ? "#15171a" : cDim
                                    font.pixelSize: 12; font.bold: true
                                }
                                MouseArea { anchors.fill: parent; onClicked: toggleDegree(modelData.label) }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        color: cDim; font.pixelSize: 11; wrapMode: Text.WordWrap
                        text: (spec && spec.ok)
                              ? (spec.root + " 为根音，共 " + spec.degrees.length + " 个音级")
                              : (spec ? ("✗ " + spec.error) : "")
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: cLine }

                    Text { text: "把位窗口"; color: cDim; font.pixelSize: 12 }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            text: fb ? (FB.windowFromCenter(winCenter, winSpan, fb.frets).lo
                                        + " – " + FB.windowFromCenter(winCenter, winSpan, fb.frets).hi + " 品") : "—"
                            color: cText; font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Button { text: "◂"; implicitWidth: 28; onClicked: moveWindow(-1) }
                        Button { text: "▸"; implicitWidth: 28; onClicked: moveWindow(1) }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: [1, 2, 3, 4, 5]
                            Rectangle {
                                width: 32; height: 22; radius: 3
                                color: winSpan === modelData ? "#3a4250" : cPanel
                                border.color: winSpan === modelData ? "#5a7ab0" : cLine
                                Text { anchors.centerIn: parent; text: "±" + modelData
                                       color: cText; font.pixelSize: 11 }
                                MouseArea { anchors.fill: parent; onClicked: setSpan(modelData) }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: cLine }

                    CheckBox {
                        id: blockCb
                        Layout.fillWidth: true
                        checked: blockMelodyString
                        onToggled: { blockMelodyString = checked; rebuild(true); }
                        contentItem: Text {
                            text: "旋律所在弦不参与指型"
                            color: cDim; font.pixelSize: 11
                            leftPadding: blockCb.indicator.width + 4
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        color: shape && shape.playable ? cDim : "#e0a03c"
                        font.pixelSize: 11; wrapMode: Text.WordWrap
                        text: shape
                              ? ("指型 " + shape.notes.length + " 个音，跨度 " + shape.span + " 品"
                                 + (shape.warnings.length ? "\n⚠ " + shape.warnings.join("\n⚠ ") : ""))
                              : ""
                    }

                    Item { Layout.fillHeight: true }
                }

                // ======== 指板 ========
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: cPanel
                    border.color: cLine
                    radius: 4

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        // 品位刻度
                        Row {
                            spacing: 2
                            Item { width: 46; height: 16 }
                            Repeater {
                                model: displayFrets + 1
                                Item {
                                    width: cellW; height: 16
                                    Text {
                                        anchors.centerIn: parent
                                        text: index
                                        color: {
                                            if (!fb) { return cDim; }
                                            var w = FB.windowFromCenter(winCenter, winSpan, fb.frets);
                                            return (index >= w.lo && index <= w.hi) ? cText : "#4a4f57";
                                        }
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
                                    width: 46; height: cellH
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (strIdx + 1) + " · " + Theory.pcName(fb.open[strIdx] % 12)
                                        color: (anchor && anchor.string === strIdx) ? "#e0a03c" : cDim
                                        font.pixelSize: 11
                                    }
                                }

                                Repeater {
                                    model: displayFrets + 1
                                    Rectangle {
                                        property var cell: (grid.length > strIdx && grid[strIdx].length > index)
                                                           ? grid[strIdx][index] : null
                                        property var picked: {
                                            if (!shape) { return null; }
                                            var n = ShapeLib.noteOnString(shape, strIdx);
                                            return (n && n.fret === index) ? n : null;
                                        }

                                        width: cellW; height: cellH; radius: 3

                                        color: {
                                            if (!cell) { return cCellOut; }
                                            if (cell.isMelody) { return "#f0f2f5"; }
                                            if (picked) { return Theory.degreeColor(cell.degree); }
                                            if (!cell.inWindow) { return cCellOut; }
                                            return cCell;
                                        }
                                        border.width: 1
                                        border.color: {
                                            if (!cell) { return "transparent"; }
                                            if (picked && picked.isBass) { return "#ffffff"; }
                                            if (cell.blocked) { return "#3a3d43"; }
                                            return "transparent";
                                        }
                                        opacity: (cell && !cell.inWindow) ? 0.35 : 1.0

                                        Text {
                                            anchors.centerIn: parent
                                            visible: cell !== null && (cell.isMelody || cell.degree !== null)
                                            text: cell ? (cell.isMelody ? "M" : Theory.prettyDegree(cell.degree || "")) : ""
                                            color: {
                                                if (!cell) { return cDim; }
                                                if (cell.isMelody) { return "#15171a"; }
                                                if (picked) { return "#15171a"; }
                                                return Theory.degreeColor(cell.degree);
                                            }
                                            font.pixelSize: 12
                                            font.bold: picked !== null || (cell && cell.isMelody)
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: (cell && cell.inWindow && cell.degree !== null
                                                          && !cell.blocked && !cell.isMelody)
                                                         ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: onCellClicked(cell)
                                        }
                                    }
                                }
                            }
                        }

                        Item { width: 1; height: 8 }

                        Row {
                            spacing: 14
                            Row {
                                spacing: 5
                                Rectangle { width: 12; height: 12; radius: 2; color: "#f0f2f5"
                                            anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "M = 旋律音"; color: cDim; font.pixelSize: 10 }
                            }
                            Row {
                                spacing: 5
                                Rectangle { width: 12; height: 12; radius: 2; color: "#e05260"
                                            border.color: "#ffffff"; border.width: 1
                                            anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "白框 = bass"; color: cDim; font.pixelSize: 10 }
                            }
                            Text {
                                text: "颜色 = 音级（1 红 · 3 橙 · 5 绿 · 7 蓝 · 9 紫）"
                                color: cDim; font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: cLine }

            // ---------------- 时值与切分 ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { text: "时值与切分"; color: cDim; font.pixelSize: 12 }
                Button { text: "−"; implicitWidth: 28; onClicked: changeBeats(-1) }
                Text { text: totalBeats + " 拍"; color: cText; font.pixelSize: 14 }
                Button { text: "+"; implicitWidth: 28; onClicked: changeBeats(1) }
                Text {
                    color: cDim; font.pixelSize: 11
                    text: slotList.length + " 格 · 当前第 " + (focusedSlot + 1) + " 格"
                }
                Button { text: "拆分 ["; onClicked: splitSlot() }
                Button { text: "合并 ]"; onClicked: mergeSlot() }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    color: "#e0a03c"
                    font.pixelSize: 11
                    elide: Text.ElideLeft
                    // 依赖 anchor / shape / slotList / overwriteMsg，它们变了这里会重算
                    text: {
                        var w = preflight();
                        return w.length ? ("⚠ " + w.join("  ·  ")) : "";
                    }
                }
            }

            Rectangle {
                id: slotsBar
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                color: cPanel
                border.color: cLine
                radius: 4

                Row {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    // 每一格
                    Repeater {
                        model: slotList.length
                        Rectangle {
                            id: slotBox
                            property int slotIdx: index
                            // 宽度按外层 Rectangle 算：Row 是 positioner，它的宽度由内容决定，
                            // 拿 parent.width 会绕回来变成循环绑定
                            width: Math.max(70, (slotsBar.width - 12 - (slotList.length - 1) * 4) / slotList.length)
                            height: slotsBar.height - 12
                            radius: 3
                            color: focusedSlot === slotIdx ? "#252a31" : "#1a1d21"
                            border.color: focusedSlot === slotIdx ? "#5a7ab0" : cLine

                            MouseArea {
                                anchors.fill: parent
                                onClicked: { focusedSlot = slotIdx; rootRect.forceActiveFocus(); }
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 5
                                spacing: 3

                                Text {
                                    text: SlotsLib.fracLabel(slotList[slotIdx].frac)
                                    color: cDim; font.pixelSize: 10
                                }

                                // 指型里的每个音一行勾选
                                Repeater {
                                    model: shape ? ShapeLib.sortedNotes(shape).reverse() : []

                                    // 外面套一层 Item：MouseArea 直接当 Row 的孩子会被
                                    // positioner 当成一列内容排进去，点不到该点的地方
                                    Item {
                                        width: slotBox.width - 10
                                        height: 14
                                        property bool on: slotList[slotIdx].strings.indexOf(modelData.string) >= 0

                                        Row {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 4

                                            Rectangle {
                                                width: 11; height: 11; radius: 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: on ? Theory.degreeColor(modelData.degree) : "transparent"
                                                border.color: on ? "transparent" : cLine
                                                border.width: 1
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: (modelData.string + 1) + "弦 "
                                                      + Theory.prettyDegree(modelData.degree)
                                                      + (modelData.isBass ? " ·B" : "")
                                                color: on ? cText : cDim
                                                font.pixelSize: 10
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                focusedSlot = slotIdx;
                                                slotList = SlotsLib.toggleString(slotList, slotIdx, modelData.string);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------------- 底栏 ----------------
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    color: statusMsg.indexOf("✗") === 0 || statusMsg.indexOf("失败") >= 0 ? "#e07070" : cDim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    text: statusMsg
                }
                Text {
                    color: cDim; font.pixelSize: 10
                    text: "← → 切格 · [ ] 拆分/合并 · 1–6 开关弦 · Space 全选 · Shift+←→ 移窗口 · Enter 插入 · Esc 关闭"
                }
            }
        }
    }

    function insertCount() {
        if (!shape || !slotList.length) { return 0; }
        var n = 0;
        for (var i = 0; i < slotList.length; i++) { n += slotList[i].strings.length; }
        return n;
    }
}

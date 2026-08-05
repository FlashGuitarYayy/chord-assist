//=============================================================================
//  Chord Assist · 环境探针
//
//  作用：在你的 MuseScore 上把插件 API 的实际行为测一遍，输出一份报告。
//  主插件的写谱逻辑依赖这里的结论，所以请先跑这个。
//
//  它只读不写；只有点了「写入测试」按钮才会动谱面，而且写完能 Ctrl+Z 撤销。
//=============================================================================

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MuseScore 3.0

MuseScore {
    id: root

    title: "Chord Assist · 环境探针"
    description: "检测插件 API 在当前 MuseScore 上的实际行为，为和弦助手提供依据"
    version: "0.1"
    pluginType: "dialog"
    requiresScore: false
    categoryCode: "composing-arranging-tools"

    width: 820
    height: 680
    implicitWidth: 820
    implicitHeight: 680

    property string reportText: ""

    //-------------------------------------------------------------------------
    // 工具
    //-------------------------------------------------------------------------

    // el.type 在 apiversion 1 下是整数，v2 下是 "NOTE" 这样的字符串。
    // 这个插件按 v1 写，但万一被当成 v2 加载，用 === 比整数会一声不响全部失配，
    // 整个插件看起来「什么都没选中」。所以两种都认。
    function isType(el, name) {
        if (!el) { return false; }
        var t = el.type;
        if (t === name) { return true; }
        try { return t === Element[name]; } catch (e) { return false; }
    }

    function line(s) { reportText += s + "\n"; }
    function head(s) { reportText += "\n=== " + s + " ===\n"; }

    // 任何一次读取都可能因为版本差异抛异常，统一包一层
    function probe(label, fn) {
        try {
            var v = fn();
            if (v === undefined) { v = "undefined"; }
            if (v === null) { v = "null"; }
            line("  " + label + ": " + v);
            return v;
        } catch (e) {
            line("  " + label + ": 【读不到】 " + e);
            return null;
        }
    }

    function yesno(b) { return b ? "是" : "否"; }

    //-------------------------------------------------------------------------
    // 只读扫描
    //-------------------------------------------------------------------------

    function scan() {
        reportText = "";
        line("Chord Assist 环境探针  ·  " + new Date().toLocaleString());

        head("1. 宿主版本");
        probe("mscoreVersion", function () {
            return mscoreMajorVersion + "." + mscoreMinorVersion + "." + mscoreUpdateVersion;
        });
        probe("division (每四分音符 tick 数)", function () { return division; });

        head("2. JS 引擎能力");
        // 设计文档里说 QML 的 JS 是阉割版（那是 MuseScore 3 / Qt5 时代的情况），
        // 这里实测一下，决定内核能不能用现代语法
        function tryEval(label, code) {
            try {
                var r = eval(code);
                line("  " + label + ": 可用 (" + r + ")");
                return true;
            } catch (e) {
                line("  " + label + ": 不可用 — " + e);
                return false;
            }
        }
        tryEval("箭头函数", "(() => 41 + 1)()");
        tryEval("let / const", "(function(){ let a = 1; const b = 2; return a + b; })()");
        tryEval("模板字符串", "(function(){ var x = 7; return `v${x}`; })()");
        tryEval("展开语法", "Math.max(...[1, 9, 3])");
        tryEval("Object.assign", "JSON.stringify(Object.assign({}, {a:1}))");
        tryEval("Array.fill", "[0,0,0].fill(5).join('')");
        tryEval("Array.includes", "[1,2,3].includes(2)");
        tryEval("正则后行断言", "/(?<=a)b/.test('ab')");

        head("3. 当前乐谱");
        if (!curScore) {
            line("  没有打开乐谱 —— 后面的检测跳过。打开一份吉他谱再点重新扫描。");
            return;
        }
        probe("谱名", function () { return curScore.scoreName; });
        probe("小节数", function () { return curScore.nmeasures; });
        probe("谱表数 nstaves", function () { return curScore.nstaves; });
        probe("轨道数 ntracks", function () { return curScore.ntracks; });
        probe("有和弦记号 hasHarmonies", function () { return yesno(curScore.hasHarmonies); });
        probe("和弦记号数量", function () { return curScore.harmonyCount; });

        head("4. 声部与谱表");
        try {
            for (var p = 0; p < curScore.parts.length; p++) {
                var part = curScore.parts[p];
                line("  声部 " + p + ": " + part.partName
                     + "  | 五线谱=" + yesno(part.hasPitchedStaff)
                     + "  六线谱=" + yesno(part.hasTabStaff)
                     + "  | track " + part.startTrack + "–" + part.endTrack);

                // 调弦表 —— 设计文档说这个拿不到，实测一下
                try {
                    var instr = part.instruments[0];
                    var sd = instr.stringData;
                    if (sd && sd.strings && sd.strings.length > 0) {
                        var t = [];
                        for (var s = 0; s < sd.strings.length; s++) {
                            t.push(sd.strings[s].pitch + (sd.strings[s].open ? "(空弦)" : ""));
                        }
                        line("    调弦 stringData.strings (低→高): [" + t.join(", ") + "]  品数=" + sd.frets);
                        line("    ↑ 注意这里 index 0 是最低音弦；Note.string 的 0 是最高音弦，方向相反");
                    } else {
                        line("    stringData: 空（这个乐器没有弦信息）");
                    }
                } catch (e) {
                    line("    stringData: 【读不到】 " + e);
                }
            }
        } catch (e) {
            line("  声部遍历失败: " + e);
        }

        head("5. 当前选中的内容");
        var sel = null;
        try { sel = curScore.selection; } catch (e) { line("  selection 读不到: " + e); }
        if (!sel) { return; }

        probe("是范围选择", function () { return yesno(sel.isRange); });
        var n = null;
        try {
            var els = sel.elements;
            line("  选中元素数: " + els.length);
            for (var i = 0; i < els.length && i < 5; i++) {
                var el = els[i];
                line("  [" + i + "] type=" + el.type + " name=" + el.name);
                if (isType(el, "NOTE")) {
                    if (!n) { n = el; }
                }
            }
        } catch (e) {
            line("  元素遍历失败: " + e);
        }

        if (!n) {
            line("");
            line("  没选中音符。请在谱上点一个旋律音（最好在六线谱上点），再点重新扫描 —");
            line("  这样才能测到 string / fret。");
            return;
        }

        head("6. 选中音符的细节（关键）");
        probe("pitch", function () { return n.pitch; });
        probe("tpc", function () { return n.tpc; });
        var st = probe("string", function () { return n.string; });
        var fr = probe("fret", function () { return n.fret; });
        probe("staffIdx", function () { return n.staffIdx; });
        probe("voice", function () { return n.voice; });
        probe("所在 chord 的 tick", function () { return n.parent.parent.tick; });
        probe("时值 durationType", function () { return n.parent.durationTypeWithDots; });

        line("");
        if (st === null || st < 0) {
            line("  ⚠ string 是 " + st + " —— 说明这个音在五线谱上，MuseScore 只给六线谱的音算弦品。");
            line("    （依据：src/engraving/dom/chord.cpp cmdUpdateNotes，fretChords 只对 TAB 谱跑）");
            line("    对策：在联动的六线谱上选音，或者让插件按音高自己猜一个位置。");
        } else {
            line("  ✓ string=" + st + " fret=" + fr + " 都拿到了。");
            line("    按 Note.string 口径，这是第 " + (st + 1) + " 弦第 " + fr + " 品。");
        }

        head("7. 附近的和弦记号");
        try {
            var tick = n.parent.parent.tick;
            var found = 0;
            var seg = curScore.firstSegment();
            while (seg) {
                var anns = seg.annotations;
                for (var a = 0; a < anns.length; a++) {
                    var an = anns[a];
                    if (isType(an, "HARMONY")) {
                        found++;
                        if (found <= 8) {
                            var txt = "?";
                            try { txt = an.text; } catch (e1) { }
                            var plain = "(本版本无 plainText)";
                            try { if (an.plainText !== undefined) { plain = an.plainText; } } catch (e2) { }
                            line("  tick=" + seg.tick + "  text=\"" + txt + "\"  plainText=\"" + plain + "\"");
                        }
                    }
                }
                seg = seg.next;
            }
            line("  共找到 " + found + " 个和弦记号");
            if (found > 0) {
                line("  ✓ 插件可以直接读你写在小节上方的和弦，不用再手敲一遍");
            }
        } catch (e) {
            line("  扫描和弦记号失败: " + e);
        }

        head("8. 下一步");
        line("  只读部分到此为止。点「写入测试」会真的往谱子里写两个音，");
        line("  用来验证 addNote / string / fret 的实际行为。写完可以 Ctrl+Z 撤销。");
    }

    //-------------------------------------------------------------------------
    // 写入测试
    //-------------------------------------------------------------------------

    function writeTest() {
        if (!curScore) { reportText += "\n没有乐谱，测不了。\n"; return; }

        var n = null;
        try {
            var els = curScore.selection.elements;
            for (var i = 0; i < els.length; i++) {
                if (isType(els[i], "NOTE")) { n = els[i]; break; }
            }
        } catch (e) { }

        if (!n) {
            reportText += "\n请先选中一个音符，我拿它的位置当锚点。\n";
            return;
        }

        var staffIdx = n.staffIdx;
        var tick = n.parent.parent.tick;

        head("9. 写入测试");
        line("  锚点: staffIdx=" + staffIdx + " tick=" + tick + " 目标 voice=2");

        // 写两个音进 voice 2：一个根音一个五度，八分音符
        var p1 = 45;    // A2，落在 5 弦空弦
        var p2 = 52;    // E3，落在 4 弦 2 品

        try {
            curScore.startCmd("和弦助手探针写入测试");

            var cur = curScore.newCursor();
            cur.staffIdx = staffIdx;
            cur.voice = 1;                       // voice 索引 0 起算，1 就是第 2 声部
            cur.rewindToTick(tick);

            line("  定位后 cursor.tick=" + cur.tick + "  track=" + cur.track);

            cur.setDuration(1, 8);
            cur.addNote(p1);
            line("  addNote(" + p1 + ") 之后 cursor.tick=" + cur.tick
                 + "  → 游标" + (cur.tick > tick ? "自动前进了" : "没动"));
            cur.addNote(p2, true);
            line("  addNote(" + p2 + ", addToChord=true) 之后 cursor.tick=" + cur.tick);

            curScore.endCmd();
        } catch (e) {
            line("  写入抛异常: " + e);
            try { curScore.endCmd(true); } catch (e2) { }
            return;
        }

        // 读回来看看变成了什么
        try {
            var c2 = curScore.newCursor();
            c2.staffIdx = staffIdx;
            c2.voice = 1;
            c2.rewindToTick(tick);
            var el = c2.element;
            if (!el) {
                line("  读回失败：那个位置没有元素");
                return;
            }
            line("  读回 element type=" + el.type + " (" + el.name + ")");
            if (isType(el, "CHORD")) {
                var notes = el.notes;
                line("  和弦里有 " + notes.length + " 个音"
                     + (notes.length === 2 ? "  ✓ addToChord 有效" : "  ⚠ 预期 2 个"));
                for (var k = 0; k < notes.length; k++) {
                    line("    音 " + k + ": pitch=" + notes[k].pitch
                         + " string=" + notes[k].string + " fret=" + notes[k].fret);
                }

                // 试着改弦：把第一个音钉到 6 弦（Note.string = 5）
                head("10. 能不能指定弦");
                var target = notes[0];
                var before = "string=" + target.string + " fret=" + target.fret + " pitch=" + target.pitch;
                try {
                    curScore.startCmd("和弦助手探针改弦");
                    target.string = 5;                   // 6 弦
                    target.fret = target.pitch - 40;     // 低 E = 40，自己算品位
                    curScore.endCmd();

                    var c3 = curScore.newCursor();
                    c3.staffIdx = staffIdx;
                    c3.voice = 1;
                    c3.rewindToTick(tick);
                    var el3 = c3.element;
                    var after = "读不到";
                    if (el3 && isType(el3, "CHORD")) {
                        var nn = el3.notes[0];
                        after = "string=" + nn.string + " fret=" + nn.fret + " pitch=" + nn.pitch;
                    }
                    line("  改之前: " + before);
                    line("  改之后: " + after);
                    if (after.indexOf("string=5") >= 0) {
                        line("  ✓ string/fret 可写，指型能钉住");
                    } else {
                        line("  ⚠ 写进去没留住 —— 主插件要退回「只写 pitch，让 MuseScore 自动分弦」的方案");
                    }
                } catch (e3) {
                    line("  改弦抛异常: " + e3);
                    line("  ⚠ string/fret 在这个版本上不可写");
                }
            } else {
                line("  ⚠ 那个位置不是和弦，而是 " + el.name);
            }
        } catch (e4) {
            line("  读回抛异常: " + e4);
        }

        line("");
        line("  测试写入完成。按 Ctrl+Z 撤销（可能要按两次：写音一次、改弦一次）。");
    }

    onRun: {
        scan();
    }

    //-------------------------------------------------------------------------
    // 界面
    //-------------------------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: "#1e2126"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "环境探针"
                    color: "#e8eaed"
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: "先在谱上选一个音（六线谱上最好），再点重新扫描"
                    color: "#9aa0a6"
                    font.pixelSize: 12
                }

                Button {
                    text: "重新扫描"
                    onClicked: root.scan()
                }
                Button {
                    text: "写入测试"
                    onClicked: root.writeTest()
                }
                Button {
                    text: "全选"
                    onClicked: { reportArea.selectAll(); reportArea.copy(); }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#15171a"
                border.color: "#33373d"
                border.width: 1
                radius: 4

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true

                    TextArea {
                        id: reportArea
                        text: root.reportText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextArea.NoWrap
                        color: "#d6d9dd"
                        font.family: "monospace"
                        font.pixelSize: 12
                        background: null
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "报告贴回对话里，我据此定主插件的写谱方案。"
                color: "#9aa0a6"
                font.pixelSize: 12
            }
        }
    }
}

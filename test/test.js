// 纯 JS 内核的测试。跑法：node test/test.js
// 不依赖任何第三方包，也不需要 MuseScore。

var Theory = require("../core/theory.js");
var FB = require("../core/fretboard.js");
var Shape = require("../core/shape.js");
var Slots = require("../core/slots.js");

var pass = 0, fail = 0;
var failures = [];

function ok(cond, name, detail) {
    if (cond) { pass++; } else { fail++; failures.push(name + (detail ? "  → " + detail : "")); }
}
function eq(actual, expected, name) {
    var a = JSON.stringify(actual), e = JSON.stringify(expected);
    ok(a === e, name, "得到 " + a + "，期望 " + e);
}
function section(t) { console.log("\n── " + t + " ──"); }

// ===========================================================================
section("和弦解析");
// ===========================================================================

function degs(sym) {
    var s = Theory.parseChord(sym);
    if (!s.ok) { return "ERR:" + s.error; }
    return s.degrees.map(function (d) { return d.label; }).join(" ");
}
function semis(sym) {
    var s = Theory.parseChord(sym);
    if (!s.ok) { return null; }
    return s.degrees.map(function (d) { return d.semi; });
}

eq(degs("C"), "1 3 5", "C = 大三和弦");
eq(degs("Cm"), "1 b3 5", "Cm = 小三和弦");
eq(degs("Am"), "1 b3 5", "Am");
eq(degs("C7"), "1 3 5 b7", "C7 = 属七");
eq(degs("Cmaj7"), "1 3 5 7", "Cmaj7 = 大七");
eq(degs("CM7"), "1 3 5 7", "CM7 = 大七（大写 M）");
eq(degs("Cm7"), "1 b3 5 b7", "Cm7 = 小七（小写 m）");
eq(degs("Am7"), "1 b3 5 b7", "Am7");
eq(degs("Cdim"), "1 b3 b5", "Cdim");
eq(degs("Cdim7"), "1 b3 b5 bb7", "Cdim7 有重降七");
eq(degs("Cm7b5"), "1 b3 b5 b7", "Cm7b5 半减");
eq(degs("Caug"), "1 3 #5", "Caug");
eq(degs("C+"), "1 3 #5", "C+ 等价 Caug");
eq(degs("C6"), "1 3 5 6", "C6");
eq(degs("Cm6"), "1 b3 5 6", "Cm6");
eq(degs("C9"), "1 3 5 b7 9", "C9 含小七");
eq(degs("Cmaj9"), "1 3 5 7 9", "Cmaj9 含大七");
eq(degs("Cm9"), "1 b3 5 b7 9", "Cm9");
eq(degs("C11"), "1 3 5 b7 9 11", "C11");
eq(degs("C13"), "1 3 5 b7 9 13", "C13 按惯例省 11");
eq(degs("Csus2"), "1 2 5", "Csus2 没有三音");
eq(degs("Csus4"), "1 4 5", "Csus4 没有三音");
eq(degs("C7sus4"), "1 4 5 b7", "C7sus4");
eq(degs("Cadd9"), "1 3 5 9", "Cadd9 有三音无七音");
eq(degs("C5"), "1 5", "C5 强力和弦");
eq(degs("C7b9"), "1 3 5 b7 b9", "C7b9");
eq(degs("C7#9"), "1 3 5 b7 #9", "C7#9");
eq(degs("C7#11"), "1 3 5 b7 #11", "C7#11");

// unicode 花体
eq(degs("CΔ7"), "1 3 5 7", "CΔ7 = Cmaj7");
eq(degs("Cø"), "1 b3 b5 b7", "Cø = Cm7b5");
eq(degs("C°"), "1 b3 b5", "C° = Cdim");
eq(degs("E♭m7"), "1 b3 5 b7", "E♭m7 用 unicode 降号");

// 半音数
eq(semis("C9"), [0, 4, 7, 10, 14], "九音记 14 不是 2");
eq(semis("Cmaj7"), [0, 4, 7, 11], "大七 11 个半音");

// 根音
ok(Theory.parseChord("A").rootPc === 9, "A 的 pc = 9");
ok(Theory.parseChord("Bb").rootPc === 10, "Bb 的 pc = 10");
ok(Theory.parseChord("F#").rootPc === 6, "F# 的 pc = 6");
ok(Theory.parseChord("E♭").rootPc === 3, "E♭ 的 pc = 3");

// 斜杠低音
var cg = Theory.parseChord("C/G");
ok(cg.ok && cg.bassPc === 7, "C/G 的低音是 G");
var cd = Theory.parseChord("C/D");
ok(cd.degrees.some(function (d) { return d.label === "bass"; }), "C/D 的 D 不在和弦里，作为附加低音带上");

// 错误输入
ok(!Theory.parseChord("").ok, "空串报错");
ok(!Theory.parseChord("Hm7").ok, "H 不是合法根音");
ok(Theory.parseChord("Cxyz").warnings.length > 0, "认不出的后缀要给警告");

// 扩展音按钮（音级集合运算，不拼字符串）
function modDegs(sym, mods) {
    var s = Theory.applyMods(Theory.parseChord(sym), mods);
    return s.degrees.map(function (d) { return d.label; }).join(" ");
}
eq(modDegs("C", ["7"]), "1 3 5 b7", "C 加 7");
eq(modDegs("C", ["maj7"]), "1 3 5 7", "C 加 maj7");
eq(modDegs("Cm7", ["maj7"]), "1 b3 5 7", "Cm7 换成 maj7，小七被顶掉");
eq(modDegs("C7", ["9"]), "1 3 5 b7 9", "C7 加 9");
eq(modDegs("C", ["7", "9", "13"]), "1 3 5 b7 9 13", "叠加多个");
eq(modDegs("C", ["sus4"]), "1 4 5", "sus4 顶掉三音");
eq(modDegs("Cm", ["sus2"]), "1 2 5", "sus2 顶掉小三度");
eq(modDegs("C7", ["7"]), "1 3 5 b7", "重复加同一个 mod 是幂等的");
eq(modDegs("C", []), "1 3 5", "空 mods 原样返回");
eq(modDegs("Csus2", ["9"]), "1 2 5", "sus2 已占 pc 2，9 音不重复加");

// pitchClassMap
var am7map = Theory.pitchClassMap(Theory.parseChord("Am7"));
eq(am7map[9], "1", "Am7: A 是根音");
eq(am7map[0], "b3", "Am7: C 是三音");
eq(am7map[4], "5", "Am7: E 是五音");
eq(am7map[7], "b7", "Am7: G 是七音");

// ===========================================================================
section("指板 —— 弦号方向（最容易写反的地方）");
// ===========================================================================

var g = FB.standardGuitar(19);

eq(g.open[0], 64, "Note.string 0 = 1 弦 = 高 E = 64");
eq(g.open[1], 59, "Note.string 1 = 2 弦 = B = 59");
eq(g.open[2], 55, "Note.string 2 = 3 弦 = G = 55");
eq(g.open[3], 50, "Note.string 3 = 4 弦 = D = 50");
eq(g.open[4], 45, "Note.string 4 = 5 弦 = A = 45");
eq(g.open[5], 40, "Note.string 5 = 6 弦 = 低 E = 40");

// 用 API 的 stringData 形状构造（低→高），必须翻转
var fromApi = FB.fromApiStringData({
    strings: [{ pitch: 40, open: false }, { pitch: 45, open: false }, { pitch: 50, open: false },
              { pitch: 55, open: false }, { pitch: 59, open: false }, { pitch: 64, open: false }],
    frets: 19
});
eq(fromApi.open[0], 64, "fromApiStringData 把低→高翻成 Note.string 口径");
eq(fromApi.open[5], 40, "fromApiStringData 最后一根是低 E");

// 对照设计稿截图里的四个旋律音
eq(FB.fretFor(g, 0, 69), 5, "A4(69) 在 1 弦 5 品");
eq(FB.fretFor(g, 0, 72), 8, "C5(72) 在 1 弦 8 品");
eq(FB.fretFor(g, 0, 71), 7, "B4(71) 在 1 弦 7 品");
eq(FB.fretFor(g, 1, 64), 5, "E4(64) 在 2 弦 5 品");

eq(FB.pitchAt(g, 2, 2), 57, "3 弦 2 品 = A(57)");
eq(FB.pitchAt(g, 3, 2), 52, "4 弦 2 品 = E(52)");
eq(FB.pitchAt(g, 4, 3), 48, "5 弦 3 品 = C(48)");
eq(FB.pitchAt(g, 5, 3), 43, "6 弦 3 品 = G(43)");

eq(FB.fretFor(g, 0, 40), -1, "低 E 弹不到 1 弦上");
eq(FB.fretFor(g, 5, 100), -1, "超出品数返回 -1");

// 窗口
eq(FB.windowFromCenter(5, 3, 19), { lo: 2, hi: 8, center: 5, span: 3 }, "以 5 品为心 ±3 → 2-8 品");
eq(FB.windowFromCenter(1, 3, 19).lo, 0, "贴到琴枕时窗口整体右移，不出负数");
eq(FB.windowFromCenter(1, 3, 19).hi, 6, "左边顶住后右边补齐");
eq(FB.windowFromCenter(18, 3, 19).hi, 19, "右边不超过最大品");

// ===========================================================================
section("指板 —— 高亮网格");
// ===========================================================================

var am7 = Theory.parseChord("Am7");
var map = Theory.pitchClassMap(am7);
var win = FB.windowFromCenter(5, 3, 19);
var cells = FB.buildGrid(g, am7, map, {
    loFret: win.lo, hiFret: win.hi,
    melodyString: 0, melodyFret: 5, blockMelodyString: true
});

function cellAt(cs, s, f) {
    for (var i = 0; i < cs.length; i++) { if (cs[i].string === s && cs[i].fret === f) { return cs[i]; } }
    return null;
}

eq(cellAt(cells, 2, 2).degree, "1", "Am7：3 弦 2 品是根音");
eq(cellAt(cells, 3, 2).degree, "5", "Am7：4 弦 2 品是五音");
eq(cellAt(cells, 4, 3).degree, "b3", "Am7：5 弦 3 品是三音");
eq(cellAt(cells, 5, 3).degree, "b7", "Am7：6 弦 3 品是七音");
eq(cellAt(cells, 1, 5).degree, "5", "Am7：2 弦 5 品(E)是五音");
eq(cellAt(cells, 3, 5).degree, "b7", "Am7：4 弦 5 品(G)是七音");

ok(cellAt(cells, 0, 5).isMelody === true, "旋律音那格被标出来");
ok(cellAt(cells, 0, 7).blocked === true, "旋律所在的 1 弦其他格被禁用");
ok(cellAt(cells, 2, 2).blocked === false, "别的弦不受影响");
ok(cellAt(cells, 2, 12).inWindow === false, "窗口外的格子 inWindow 为 false");

var cands = FB.candidates(cells);
ok(cands.length > 0, "窗口内有候选音");
ok(cands.every(function (c) { return c.string !== 0; }), "候选里不含被旋律占用的 1 弦");
ok(cands.every(function (c) { return c.fret >= 2 && c.fret <= 8; }), "候选都在窗口内");

// ===========================================================================
section("指型");
// ===========================================================================

var sh = Shape.emptyShape();
sh = Shape.toggleCell(sh, cellAt(cells, 4, 3), g);      // 5 弦 3 品 C
sh = Shape.toggleCell(sh, cellAt(cells, 3, 2), g);      // 4 弦 2 品 E
eq(sh.notes.length, 2, "点两格得到两个音");

sh = Shape.toggleCell(sh, cellAt(cells, 4, 7), g);      // 同一根弦换一格
eq(sh.notes.length, 2, "同弦再点是替换不是新增");
eq(Shape.noteOnString(sh, 4).fret, 7, "替换成新的品位");

sh = Shape.toggleCell(sh, cellAt(cells, 4, 7), g);      // 同一格再点
eq(sh.notes.length, 1, "点同一格是取消");

// bass 规则
var sh2 = Shape.emptyShape();
sh2 = Shape.toggleCell(sh2, cellAt(cells, 5, 5), g);    // 6 弦 5 品 = A(45) 根音
sh2 = Shape.toggleCell(sh2, cellAt(cells, 3, 2), g);    // 4 弦 2 品 = E(52)
sh2 = Shape.toggleCell(sh2, cellAt(cells, 2, 5), g);    // 3 弦 5 品 = C(60)
sh2 = Shape.autoBass(sh2, am7, g);
var bassNote = sh2.notes.filter(function (n) { return n.isBass; })[0];
eq(bassNote.pitch, 45, "autoBass 取最低的根音 A(45)");

// 跨度
var wide = Shape.emptyShape();
wide = Shape.toggleCell(wide, { string: 5, fret: 2, pitch: 42, degree: "1" }, g);
wide = Shape.toggleCell(wide, { string: 0, fret: 9, pitch: 73, degree: "3" }, g);
ok(wide.span === 8, "跨度按有品位的音算");
ok(wide.playable === false, "跨 8 品按不了");
ok(wide.warnings.length > 0, "给出警告");

var open = Shape.emptyShape();
open = Shape.toggleCell(open, { string: 4, fret: 0, pitch: 45, degree: "1" }, g);
open = Shape.toggleCell(open, { string: 2, fret: 2, pitch: 57, degree: "1" }, g);
eq(open.span, 1, "空弦不计入跨度");

// ===========================================================================
section("自动配音");
// ===========================================================================

// 把一次完整的配音跑通，返回结果供断言
function voice(symbol, melodyPitch, melodyString, span) {
    var sp = Theory.parseChord(symbol);
    var pm = Theory.pitchClassMap(sp);
    var mf = FB.fretFor(g, melodyString, melodyPitch);
    var w = FB.windowFromCenter(mf, span === undefined ? 3 : span, g.frets);
    var cs = FB.buildGrid(g, sp, pm, {
        loFret: w.lo, hiFret: w.hi,
        melodyString: melodyString, melodyFret: mf,
        blockMelodyString: true
    });
    return { spec: sp, cells: cs, win: w, melodyString: melodyString,
             shape: Shape.suggest(g, sp, cs, {}) };
}

function degreesOf(sh) {
    return sh.notes.map(function (n) { return n.degree; }).sort().join(" ");
}
function bassOf(sh) {
    var b = sh.notes.filter(function (n) { return n.isBass; })[0];
    return b ? b : null;
}

var sug = Shape.suggest(g, am7, cells, { maxNotes: 4 });
ok(sug.notes.length >= 2, "suggest 能给出指型");
ok(sug.notes.filter(function (n) { return n.isBass; }).length === 1, "推荐的指型有且只有一个 bass");
ok(sug.playable, "推荐的指型按得下来");
ok(sug.notes.every(function (n) { return n.string !== 0; }), "推荐的指型不占旋律的弦");
var strs = sug.notes.map(function (n) { return n.string; });
ok(strs.length === strs.filter(function (v, i) { return strs.indexOf(v) === i; }).length, "一弦一音");

// 这几条是配音引擎的硬要求，换成穷举打分就是为了稳定满足它们
var cases = [
    { sym: "Am7",   pitch: 69, str: 0, wantBass: 9,  need: ["b3", "b7"] },
    { sym: "C",     pitch: 72, str: 0, wantBass: 0,  need: ["3"] },
    { sym: "Cmaj7", pitch: 72, str: 0, wantBass: 0,  need: ["3", "7"] },
    { sym: "G7",    pitch: 71, str: 0, wantBass: 7,  need: ["3", "b7"] },
    { sym: "Dm7",   pitch: 74, str: 0, wantBass: 2,  need: ["b3", "b7"] },
    { sym: "Fmaj7", pitch: 69, str: 0, wantBass: 5,  need: ["3", "7"] },
    { sym: "Em",    pitch: 76, str: 0, wantBass: 4,  need: ["b3"] },
    { sym: "Bm7b5", pitch: 74, str: 0, wantBass: 11, need: ["b3", "b5", "b7"] }
];

for (var ci = 0; ci < cases.length; ci++) {
    var cse = cases[ci];
    var v = voice(cse.sym, cse.pitch, cse.str);
    var sh3 = v.shape;
    var tag = cse.sym + "（旋律 " + cse.pitch + "）";

    ok(sh3.notes.length >= 2, tag + " 配出了指型", "只有 " + sh3.notes.length + " 个音");
    ok(sh3.playable, tag + " 按得下来", "跨度 " + sh3.span);

    var b = bassOf(sh3);
    ok(b !== null && ((b.pitch % 12) + 12) % 12 === cse.wantBass,
       tag + " 的 bass 是根音", b ? ("bass pc=" + (b.pitch % 12)) : "没有 bass");

    // bass 必须是整个指型里最低的音
    var lowest = sh3.notes.slice().sort(function (x, y) { return x.pitch - y.pitch; })[0];
    ok(b && b.pitch === lowest.pitch, tag + " 的 bass 就是最低音");

    for (var ni = 0; ni < cse.need.length; ni++) {
        var want = cse.need[ni];
        ok(degreesOf(sh3).split(" ").indexOf(want) >= 0,
           tag + " 包含定调音 " + want, "实际 " + degreesOf(sh3));
    }

    // 通用不变量
    var ss = sh3.notes.map(function (n) { return n.string; });
    ok(ss.length === ss.filter(function (x, i) { return ss.indexOf(x) === i; }).length,
       tag + " 一弦一音");
    ok(sh3.notes.every(function (n) { return n.string !== cse.str; }),
       tag + " 不占旋律的弦");
    ok(sh3.notes.every(function (n) { return n.fret >= v.win.lo && n.fret <= v.win.hi; }),
       tag + " 所有音在把位窗口内");
    ok(sh3.notes.every(function (n) { return FB.pitchAt(g, n.string, n.fret) === n.pitch; }),
       tag + " 弦品与音高自洽");
}

// 打分函数本身：定调音齐全的应该赢过缺三音的
var vc = voice("C", 72, 0);
var withThird = [], noThird = [];
for (var q = 0; q < vc.cells.length; q++) {
    var cc = vc.cells[q];
    if (!cc.inWindow || cc.degree === null || cc.blocked || cc.isMelody) { continue; }
    if (cc.string === 4 && cc.degree === "1") { withThird.push(cc); noThird.push(cc); }
    if (cc.string === 3 && cc.degree === "3") { withThird.push(cc); }
    if (cc.string === 3 && cc.degree === "5") { noThird.push(cc); }
}
if (withThird.length === 2 && noThird.length === 2) {
    var o = { maxNotes: 4, minNotes: 2, maxSpan: 4, bassStrings: [5, 4, 3],
              wantBassPc: 0, essentials: Shape.essentialLabels(vc.spec) };
    ok(Shape.scoreVoicing(withThird, vc.spec, g, o) > Shape.scoreVoicing(noThird, vc.spec, g, o),
       "打分：有三音的配置赢过没三音的");
}

// 窗口给得很窄时不该崩，也不该给出按不了的东西
var tight = voice("Am7", 69, 0, 1);
ok(tight.shape.notes.length === 0 || tight.shape.playable, "窗口只有 ±1 品时要么给不出、要么给得出且能按");

// ===========================================================================
section("时值切分");
// ===========================================================================

eq(Slots.beatsToFrac(2, 4), { n: 1, d: 2 }, "4/4 里 2 拍 = 二分音符");
eq(Slots.beatsToFrac(1, 4), { n: 1, d: 4 }, "1 拍 = 四分音符");
eq(Slots.beatsToFrac(3, 4), { n: 3, d: 4 }, "3 拍 = 附点二分");

ok(Slots.isRepresentable({ n: 1, d: 4 }), "1/4 可写");
ok(Slots.isRepresentable({ n: 3, d: 8 }), "3/8 附点四分可写");
ok(Slots.isRepresentable({ n: 7, d: 16 }), "7/16 双附点可写");
ok(!Slots.isRepresentable({ n: 5, d: 16 }), "5/16 写不出来");
ok(!Slots.isRepresentable({ n: 1, d: 3 }), "1/3 三连音不在此列");

var total = Slots.beatsToFrac(2, 4);
var sl = Slots.makeSlots(total, 2);
eq(sl.length, 2, "2 拍默认切 2 格");
eq(sl[0].frac, { n: 1, d: 4 }, "每格 1 拍");
eq(Slots.totalOf(sl), total, "总和等于设定时值");

var r = Slots.split(sl, 0);
ok(r.ok, "第 1 格可以拆");
eq(r.slots.length, 3, "拆完变 3 格");
eq(r.slots[0].frac, { n: 1, d: 8 }, "拆出来是八分");
eq(Slots.totalOf(r.slots), total, "拆分不改变总时值");

var r2 = Slots.split(r.slots, 1);
eq(r2.slots.length, 4, "再拆一格 → 4 格");
eq(Slots.totalOf(r2.slots), total, "还是 2 拍");

var m = Slots.merge(r2.slots, 0);
ok(m.ok, "相邻等长可以合并");
eq(m.slots.length, 3, "合并后少一格");
eq(Slots.totalOf(m.slots), total, "合并不改变总时值");

// 不等长合并
var uneven = [{ frac: { n: 1, d: 4 }, strings: [] }, { frac: { n: 1, d: 16 }, strings: [] }];
var mu = Slots.merge(uneven, 0);
ok(!mu.ok, "1/4 + 1/16 = 5/16 写不出来，拒绝合并");
ok(mu.error.length > 0, "拒绝时给出原因");

var dotted = [{ frac: { n: 1, d: 4 }, strings: [] }, { frac: { n: 1, d: 8 }, strings: [] }];
var md = Slots.merge(dotted, 0);
ok(md.ok, "1/4 + 1/8 = 3/8 附点四分，可以合并");

// 内容操作
var sl2 = Slots.makeSlots(total, 4);
sl2 = Slots.toggleString(sl2, 0, 3);
sl2 = Slots.toggleString(sl2, 0, 5);
eq(sl2[0].strings, [3, 5], "勾选的弦排好序");
sl2 = Slots.toggleString(sl2, 0, 3);
eq(sl2[0].strings, [5], "再点一次取消");

// 用户描述的场景：第一格全响，后三格只留一个音
var filled = Slots.defaultFill(Slots.makeSlots(total, 4), sug);
ok(filled[0].strings.length === sug.notes.length, "第一格全响");
ok(filled[1].strings.indexOf(sug.notes.filter(function (n) { return n.isBass; })[0].string) < 0,
   "后面的格子不含 bass");

// 写谱计划
var plan = Slots.toInsertPlan(filled, sug, 480);
eq(plan.length, 4, "计划有 4 格");
eq(plan[0].ticks, 240, "1/8 在 division=480 时是 240 tick");
ok(plan[0].notes.length > 0, "第一格有音");
ok(plan[0].notes[0].pitch <= plan[0].notes[plan[0].notes.length - 1].pitch, "每格的音按音高排序");
var sumTicks = plan.reduce(function (a, p) { return a + p.ticks; }, 0);
eq(sumTicks, 960, "四格共 960 tick = 2 拍");

// ===========================================================================
console.log("\n" + (fail === 0 ? "全部通过" : "有失败"));
console.log("通过 " + pass + " / " + (pass + fail));
if (fail > 0) {
    console.log("\n失败项：");
    failures.forEach(function (f) { console.log("  ✗ " + f); });
    process.exit(1);
}

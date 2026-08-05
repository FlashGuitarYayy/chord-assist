// slots.js —— 时值切分
//
// 纯计算模块。
//
// 一个 Slot 是指型作用时间轴上的一格：
//   { frac: {n, d},        占整全音符的比例，(1,4) = 四分音符
//     strings: [0,2,4] }   这一格要响的弦（Note.string 口径）
//
// 不变量：所有格子的 frac 之和恒等于用户设定的总时值。拆分和合并都不改变总和。

function gcd(a, b) { while (b) { var t = a % b; a = b; b = t; } return a; }

function reduce(f) {
    var g = gcd(Math.abs(f.n), Math.abs(f.d)) || 1;
    return { n: f.n / g, d: f.d / g };
}

function addFrac(a, b) { return reduce({ n: a.n * b.d + b.n * a.d, d: a.d * b.d }); }
function eqFrac(a, b) { var x = reduce(a), y = reduce(b); return x.n === y.n && x.d === y.d; }

function isPowerOfTwo(x) { return x > 0 && (x & (x - 1)) === 0; }

// 能不能写成一个音符的时值：分子为 1（普通）、3（附点）、7（双附点），分母是 2 的幂
function isRepresentable(f) {
    var r = reduce(f);
    if (r.n <= 0 || r.d <= 0) { return false; }
    if (!isPowerOfTwo(r.d)) { return false; }
    if (r.n === 1) { return r.d <= 64; }
    if (r.n === 3) { return r.d >= 2 && r.d <= 64; }
    if (r.n === 7) { return r.d >= 4 && r.d <= 64; }
    return false;
}

function fracLabel(f) {
    var r = reduce(f);
    var names = { 1: "全", 2: "二分", 4: "四分", 8: "八分", 16: "十六分", 32: "三十二分" };
    if (r.n === 1 && names[r.d]) { return names[r.d]; }
    if (r.n === 3 && names[r.d / 2]) { return "附点" + names[r.d / 2]; }
    if (r.n === 7 && names[r.d / 4]) { return "双附点" + names[r.d / 4]; }
    return r.n + "/" + r.d;
}

// frac → tick 数。division 是每个四分音符的 tick 数（MuseScore 全局常量）
function fracToTicks(f, division) {
    return Math.round(f.n / f.d * 4 * division);
}

// 拍数 → frac。beatDen 取自拍号分母：4/4 传 4，6/8 传 8
function beatsToFrac(beats, beatDen) {
    return reduce({ n: beats, d: beatDen || 4 });
}

// ---------------------------------------------------------------------------

function makeSlots(totalFrac, count) {
    var slots = [];
    var n = count || 1;
    for (var i = 0; i < n; i++) {
        slots.push({ frac: reduce({ n: totalFrac.n, d: totalFrac.d * n }), strings: [] });
    }
    return slots;
}

function totalOf(slots) {
    var t = { n: 0, d: 1 };
    for (var i = 0; i < slots.length; i++) { t = addFrac(t, slots[i].frac); }
    return t;
}

// 把第 i 格对半拆开，内容复制到两半
function split(slots, i) {
    if (i < 0 || i >= slots.length) { return { slots: slots, ok: false, error: "格子不存在" }; }
    var half = reduce({ n: slots[i].frac.n, d: slots[i].frac.d * 2 });
    if (!isRepresentable(half)) {
        return { slots: slots, ok: false, error: "再拆下去写不出这个时值了" };
    }
    var out = slots.slice();
    var a = { frac: half, strings: slots[i].strings.slice() };
    var b = { frac: half, strings: slots[i].strings.slice() };
    out.splice(i, 1, a, b);
    return { slots: out, ok: true };
}

// 把第 i 格和后一格并回去，内容取并集
function merge(slots, i) {
    if (i < 0 || i >= slots.length - 1) { return { slots: slots, ok: false, error: "后面没有格子了" }; }
    var sum = addFrac(slots[i].frac, slots[i + 1].frac);
    if (!isRepresentable(sum)) {
        return { slots: slots, ok: false, error: "并起来是 " + sum.n + "/" + sum.d + "，写不成一个音符" };
    }
    var union = {};
    var k;
    for (k = 0; k < slots[i].strings.length; k++) { union[slots[i].strings[k]] = true; }
    for (k = 0; k < slots[i + 1].strings.length; k++) { union[slots[i + 1].strings[k]] = true; }
    var strs = [];
    for (var s in union) { if (union.hasOwnProperty(s)) { strs.push(parseInt(s, 10)); } }
    strs.sort(function (a, b) { return a - b; });

    var out = slots.slice();
    out.splice(i, 2, { frac: sum, strings: strs });
    return { slots: out, ok: true };
}

function toggleString(slots, i, string) {
    if (i < 0 || i >= slots.length) { return slots; }
    var out = slots.slice();
    var cur = out[i].strings.slice();
    var idx = cur.indexOf(string);
    if (idx >= 0) { cur.splice(idx, 1); } else { cur.push(string); cur.sort(function (a, b) { return a - b; }); }
    out[i] = { frac: out[i].frac, strings: cur };
    return out;
}

function setStrings(slots, i, strings) {
    if (i < 0 || i >= slots.length) { return slots; }
    var out = slots.slice();
    var cur = strings.slice();
    cur.sort(function (a, b) { return a - b; });
    out[i] = { frac: out[i].frac, strings: cur };
    return out;
}

// 全选 / 全清
function toggleAll(slots, i, shape) {
    if (i < 0 || i >= slots.length) { return slots; }
    var all = shape.notes.map(function (n) { return n.string; });
    if (slots[i].strings.length >= all.length) { return setStrings(slots, i, []); }
    return setStrings(slots, i, all);
}

// 新建指型后的默认填法：第一格全响，后面的格子只留 bass 以外的高音
function defaultFill(slots, shape, mode) {
    var all = shape.notes.map(function (n) { return n.string; }).sort(function (a, b) { return a - b; });
    var bass = shape.notes.filter(function (n) { return n.isBass; }).map(function (n) { return n.string; });
    var nonBass = all.filter(function (s) { return bass.indexOf(s) < 0; });

    var out = [];
    for (var i = 0; i < slots.length; i++) {
        var pick;
        if (mode === "all") {
            pick = all.slice();
        } else if (i === 0) {
            pick = all.slice();                                     // 第一格：bass + 和弦音
        } else {
            pick = nonBass.length > 0 ? nonBass.slice() : all.slice();  // 之后只点和弦音
        }
        out.push({ frac: slots[i].frac, strings: pick });
    }
    return out;
}

// 生成写谱用的计划：每格算出实际要写的音
function toInsertPlan(slots, shape, division) {
    var byString = {};
    for (var i = 0; i < shape.notes.length; i++) { byString[shape.notes[i].string] = shape.notes[i]; }

    var plan = [];
    for (var k = 0; k < slots.length; k++) {
        var notes = [];
        for (var j = 0; j < slots[k].strings.length; j++) {
            var n = byString[slots[k].strings[j]];
            if (n) { notes.push({ string: n.string, fret: n.fret, pitch: n.pitch, degree: n.degree }); }
        }
        notes.sort(function (a, b) { return a.pitch - b.pitch; });
        plan.push({
            frac: slots[k].frac,
            ticks: fracToTicks(slots[k].frac, division),
            notes: notes,
            isRest: notes.length === 0
        });
    }
    return plan;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        reduce: reduce, addFrac: addFrac, eqFrac: eqFrac,
        isRepresentable: isRepresentable, fracLabel: fracLabel,
        fracToTicks: fracToTicks, beatsToFrac: beatsToFrac,
        makeSlots: makeSlots, totalOf: totalOf,
        split: split, merge: merge,
        toggleString: toggleString, setStrings: setStrings, toggleAll: toggleAll,
        defaultFill: defaultFill, toInsertPlan: toInsertPlan
    };
}

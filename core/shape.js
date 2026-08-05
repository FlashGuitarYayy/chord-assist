// shape.js —— 指型的构建与校验
//
// 纯计算模块。弦号一律是 Note.string 口径（0 = 1 弦 = 高 E）。
//
// ChordShape = {
//   notes: [ {string, fret, pitch, degree, isBass} ],   一根弦最多一个音
//   span, lowestString, playable, warnings
// }

function emptyShape() {
    return { notes: [], span: 0, playable: true, warnings: [] };
}

function cloneShape(shape) {
    var out = { notes: [], span: shape.span, playable: shape.playable, warnings: shape.warnings.slice() };
    for (var i = 0; i < shape.notes.length; i++) {
        var n = shape.notes[i];
        out.notes.push({ string: n.string, fret: n.fret, pitch: n.pitch, degree: n.degree, isBass: n.isBass === true });
    }
    return out;
}

function noteOnString(shape, string) {
    for (var i = 0; i < shape.notes.length; i++) {
        if (shape.notes[i].string === string) { return shape.notes[i]; }
    }
    return null;
}

// 点一格：空弦位就加，同弦不同品就替换，同一格再点就移除
function toggleCell(shape, cell, fb) {
    var out = cloneShape(shape);
    var existing = noteOnString(out, cell.string);
    if (existing && existing.fret === cell.fret) {
        out.notes = out.notes.filter(function (n) { return n.string !== cell.string; });
    } else {
        out.notes = out.notes.filter(function (n) { return n.string !== cell.string; });
        out.notes.push({
            string: cell.string, fret: cell.fret, pitch: cell.pitch,
            degree: cell.degree, isBass: existing ? existing.isBass === true : false
        });
    }
    return analyze(out, fb);
}

function removeString(shape, string, fb) {
    var out = cloneShape(shape);
    out.notes = out.notes.filter(function (n) { return n.string !== string; });
    return analyze(out, fb);
}

// 按音高从低到高（Note.string 越大音越低，所以倒着排）
function sortedNotes(shape) {
    var ns = shape.notes.slice();
    ns.sort(function (a, b) { return a.pitch - b.pitch; });
    return ns;
}

// bass 规则：整个指型里最低的根音；没有根音就取最低的那个音
function autoBass(shape, spec, fb) {
    var out = cloneShape(shape);
    for (var i = 0; i < out.notes.length; i++) { out.notes[i].isBass = false; }

    var ns = sortedNotes(out);
    if (ns.length === 0) { return analyze(out, fb); }

    var target = null;
    var wantPc = null;
    if (spec && spec.ok) {
        wantPc = (spec.bassPc !== null && spec.bassPc !== undefined) ? spec.bassPc : spec.rootPc;
    }
    if (wantPc !== null) {
        for (var j = 0; j < ns.length; j++) {
            if (((ns[j].pitch % 12) + 12) % 12 === wantPc) { target = ns[j]; break; }
        }
    }
    if (!target) { target = ns[0]; }

    for (var k = 0; k < out.notes.length; k++) {
        if (out.notes[k].string === target.string) { out.notes[k].isBass = true; }
    }
    return analyze(out, fb);
}

function setBass(shape, string, fb) {
    var out = cloneShape(shape);
    for (var i = 0; i < out.notes.length; i++) {
        out.notes[i].isBass = (out.notes[i].string === string);
    }
    return analyze(out, fb);
}

// 跨度与可按性
function analyze(shape, fb) {
    var out = cloneShape(shape);
    out.warnings = [];

    var fretted = out.notes.filter(function (n) { return n.fret > 0; });
    var span = 0;
    if (fretted.length > 0) {
        var lo = fretted[0].fret, hi = fretted[0].fret;
        for (var i = 1; i < fretted.length; i++) {
            if (fretted[i].fret < lo) { lo = fretted[i].fret; }
            if (fretted[i].fret > hi) { hi = fretted[i].fret; }
        }
        span = hi - lo + 1;
    }
    out.span = span;

    // 一弦一音（toggleCell 已保证，这里兜底）
    var seen = {};
    for (var j = 0; j < out.notes.length; j++) {
        var s = out.notes[j].string;
        if (seen[s]) { out.warnings.push("第 " + (s + 1) + " 弦上有两个音"); }
        seen[s] = true;
    }

    if (span > 5) {
        out.warnings.push("跨度 " + span + " 品，按不过来");
    } else if (span === 5) {
        out.warnings.push("跨度 5 品，偏大");
    }

    // 中间跳过的弦：右手可以跳弦，扫弦就不行，只做提示
    if (out.notes.length >= 2) {
        var strs = out.notes.map(function (n) { return n.string; }).sort(function (a, b) { return a - b; });
        for (var k = 1; k < strs.length; k++) {
            if (strs[k] - strs[k - 1] > 1) {
                out.warnings.push("第 " + strs[k - 1] + "–" + (strs[k] + 1) + " 弦之间有空档，扫弦会带到空弦");
                break;
            }
        }
    }

    out.playable = (span <= 4);
    return out;
}

// ---------------------------------------------------------------------------
// 自动配音
// ---------------------------------------------------------------------------
//
// 做法是穷举 + 打分，不是贪心。每根弦要么不响、要么从窗口里的候选中选一个，
// 组合数最多几千种，算得起。贪心的问题是选早了没法回头 —— 比如为了先占住
// 一个三音，把后面唯一能放根音 bass 的弦占掉了。

// 定调的音级：这几个音决定了和弦听起来是什么，缺了就不像
function essentialLabels(spec) {
    var out = [];
    if (!spec || !spec.ok) { return out; }
    for (var i = 0; i < spec.degrees.length; i++) {
        var l = spec.degrees[i].label;
        if (["3", "b3", "2", "4"].indexOf(l) >= 0) { out.push(l); }        // 三音或替代它的 sus
        if (["7", "b7", "bb7"].indexOf(l) >= 0) { out.push(l); }           // 七音
        if (["b5", "#5", "b9", "#9", "#11", "b13"].indexOf(l) >= 0) { out.push(l); }  // 变化音
    }
    return out;
}

function scoreVoicing(notes, spec, fb, opts) {
    var i;
    var n = notes.length;
    if (n < opts.minNotes || n > opts.maxNotes) { return -1e9; }

    var score = 0;

    // --- bass：最低的那个音是不是该在的音
    var lowest = notes[0];
    for (i = 1; i < notes.length; i++) {
        if (notes[i].pitch < lowest.pitch) { lowest = notes[i]; }
    }
    var lowPc = ((lowest.pitch % 12) + 12) % 12;
    if (opts.wantBassPc !== null && lowPc === opts.wantBassPc) {
        score += 120;
    } else if (lowest.degree === "5") {
        score += 35;                       // 五音在低音也说得过去
    } else {
        score -= 25;                       // 三音/七音在最低音，转位味道重
    }
    // bass 落在粗弦上更像指弹的拇指
    if (opts.bassStrings.indexOf(lowest.string) >= 0) { score += 25; }

    // --- 定调音级有没有覆盖到
    var have = {};
    for (i = 0; i < notes.length; i++) { have[notes[i].degree] = (have[notes[i].degree] || 0) + 1; }
    var ess = opts.essentials;
    var missing = 0;
    for (i = 0; i < ess.length; i++) {
        if (have[ess[i]]) { score += 45; } else { missing++; }
    }
    score -= missing * 55;

    // --- 张力音有一点加分，但不该压过定调音
    for (var k in have) {
        if (!have.hasOwnProperty(k)) { continue; }
        if (["9", "11", "13", "6"].indexOf(k) >= 0) { score += 12; }
        if (have[k] > 1) { score -= 18 * (have[k] - 1); }     // 同一个音级重复，浪费手指
    }

    // --- 按得舒不舒服
    var fretted = [], openCount = 0;
    for (i = 0; i < notes.length; i++) {
        if (notes[i].fret > 0) { fretted.push(notes[i].fret); } else { openCount++; }
    }
    if (fretted.length > 0) {
        var lo = Math.min.apply(null, fretted);
        var hi = Math.max.apply(null, fretted);
        var span = hi - lo + 1;
        if (span > opts.maxSpan) { return -1e9; }
        score -= (span - 1) * 16;
    }
    score += openCount * 8;                 // 空弦不占手指

    // --- 音数：指弹伴奏 3–4 个音最顺手
    if (n === 3 || n === 4) { score += 25; }

    // --- 弦是否连着。跳弦右手能弹，但连着的更好扒
    var strs = notes.map(function (x) { return x.string; }).sort(function (a, b) { return a - b; });
    for (i = 1; i < strs.length; i++) {
        if (strs[i] - strs[i - 1] > 1) { score -= 6 * (strs[i] - strs[i - 1] - 1); }
    }

    return score;
}

// 自动预选一个像样的指型，让用户开面板就能直接回车
function suggest(fb, spec, cells, opts) {
    opts = opts || {};
    var o = {
        maxNotes: opts.maxNotes || 4,
        minNotes: opts.minNotes || 2,
        maxSpan: opts.maxSpan || 4,
        bassStrings: opts.bassStrings || [5, 4, 3],
        wantBassPc: null,
        essentials: essentialLabels(spec)
    };
    if (spec && spec.ok) {
        o.wantBassPc = (spec.bassPc !== null && spec.bassPc !== undefined) ? spec.bassPc : spec.rootPc;
    }

    var avail = cells.filter(function (c) {
        return c.inWindow && c.degree !== null && !c.blocked && !c.isMelody;
    });
    if (avail.length === 0) { return emptyShape(); }

    // 按弦分组，弦号从大到小（低音弦在前），枚举时先定 bass
    var byString = [];
    for (var s = fb.nStrings - 1; s >= 0; s--) {
        var onThis = avail.filter(function (c) { return c.string === s; });
        if (onThis.length > 0) { byString.push(onThis); }
    }
    if (byString.length === 0) { return emptyShape(); }

    var best = null, bestScore = -Infinity;

    function walk(idx, chosen) {
        if (chosen.length > o.maxNotes) { return; }

        // 剪枝：已选的音跨度就超了，再加只会更糟
        if (chosen.length >= 2) {
            var fs = chosen.filter(function (x) { return x.fret > 0; }).map(function (x) { return x.fret; });
            if (fs.length > 1 && Math.max.apply(null, fs) - Math.min.apply(null, fs) + 1 > o.maxSpan) { return; }
        }

        if (idx >= byString.length) {
            if (chosen.length < o.minNotes) { return; }
            var sc = scoreVoicing(chosen, spec, fb, o);
            if (sc > bestScore) { bestScore = sc; best = chosen.slice(); }
            return;
        }

        // 这根弦不响
        walk(idx + 1, chosen);

        // 或者响其中一个候选
        var opts2 = byString[idx];
        for (var i = 0; i < opts2.length; i++) {
            chosen.push(opts2[i]);
            walk(idx + 1, chosen);
            chosen.pop();
        }
    }

    walk(0, []);

    if (!best) { return emptyShape(); }

    var shape = emptyShape();
    for (var j = 0; j < best.length; j++) {
        shape.notes.push({
            string: best[j].string, fret: best[j].fret, pitch: best[j].pitch,
            degree: best[j].degree, isBass: false
        });
    }
    shape = autoBass(shape, spec, fb);
    shape.score = bestScore;
    return shape;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        emptyShape: emptyShape,
        cloneShape: cloneShape,
        noteOnString: noteOnString,
        toggleCell: toggleCell,
        removeString: removeString,
        sortedNotes: sortedNotes,
        autoBass: autoBass,
        setBass: setBass,
        analyze: analyze,
        suggest: suggest,
        essentialLabels: essentialLabels,
        scoreVoicing: scoreVoicing
    };
}

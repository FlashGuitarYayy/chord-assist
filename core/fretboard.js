// fretboard.js —— 指板模型与高亮计算
//
// 纯计算模块，可在 node 里测试。
//
// ============================ 弦号的坑 ============================
// MuseScore 里有两套相反的弦索引，写错了整个插件就是错的：
//
//   stringData.strings[i]   i = 0 是最低音弦（低 E，MIDI 40）
//   Note.string = N         N = 0 是最高音弦（高 E，MIDI 64），也就是吉他说的「1 弦」
//
// 依据 src/engraving/dom/stringdata.cpp:489
//     instrString strg = m_stringTable.at(strings - string - 1);
//
// 本文件一律使用 Note.string 的口径（0 = 1 弦 = 高 E），
// 只在 fromApiStringData() 这一个函数里做翻转。
// ==================================================================

var STANDARD_TUNING_LOW_TO_HIGH = [40, 45, 50, 55, 59, 64];   // E A D G B e

// 从插件 API 的 stringData 构造（低→高 翻成 Note.string 口径）
function fromApiStringData(sd) {
    var lowToHigh = [];
    var openOnly = [];
    if (sd && sd.strings && sd.strings.length > 0) {
        for (var i = 0; i < sd.strings.length; i++) {
            lowToHigh.push(sd.strings[i].pitch);
            openOnly.push(sd.strings[i].open === true);
        }
    } else {
        lowToHigh = STANDARD_TUNING_LOW_TO_HIGH.slice();
        for (var j = 0; j < lowToHigh.length; j++) { openOnly.push(false); }
    }
    var frets = (sd && sd.frets > 0) ? sd.frets : 19;
    return makeFretboard(lowToHigh, openOnly, frets);
}

// pitchesLowToHigh 按 stringData 的顺序传入，内部翻转
function makeFretboard(pitchesLowToHigh, openOnlyLowToHigh, frets) {
    var n = pitchesLowToHigh.length;
    var open = [];        // 按 Note.string 索引
    var openOnly = [];
    for (var s = 0; s < n; s++) {
        open.push(pitchesLowToHigh[n - 1 - s]);
        openOnly.push(openOnlyLowToHigh ? (openOnlyLowToHigh[n - 1 - s] === true) : false);
    }
    return {
        nStrings: n,
        frets: frets || 19,
        open: open,
        openOnly: openOnly
    };
}

function standardGuitar(frets) {
    return makeFretboard(STANDARD_TUNING_LOW_TO_HIGH, null, frets || 19);
}

// 吉他口语的「第 N 弦」↔ Note.string
function stringLabel(fb, noteString) { return String(noteString + 1); }
function labelToNoteString(label) { return parseInt(label, 10) - 1; }

function pitchAt(fb, noteString, fret) {
    if (noteString < 0 || noteString >= fb.nStrings) { return -1; }
    if (fb.openOnly[noteString] && fret !== 0) { return -1; }
    return fb.open[noteString] + fret;
}

// 某音高落在某弦上是几品；不可行返回 -1
function fretFor(fb, noteString, pitch) {
    if (noteString < 0 || noteString >= fb.nStrings) { return -1; }
    var f = pitch - fb.open[noteString];
    if (f < 0 || f > fb.frets) { return -1; }
    if (fb.openOnly[noteString] && f !== 0) { return -1; }
    return f;
}

// 某音高在整块指板上的所有可弹位置
function positionsForPitch(fb, pitch) {
    var out = [];
    for (var s = 0; s < fb.nStrings; s++) {
        var f = fretFor(fb, s, pitch);
        if (f >= 0) { out.push({ string: s, fret: f }); }
    }
    return out;
}

// 把位窗口：以 center 为中心上下各 span 品，再夹到 [0, frets]
function windowFromCenter(center, span, maxFret) {
    var lo = center - span;
    var hi = center + span;
    if (lo < 0) { hi -= lo; lo = 0; }
    if (hi > maxFret) {
        var over = hi - maxFret;
        hi = maxFret;
        lo = Math.max(0, lo - over);
    }
    return { lo: lo, hi: hi, center: center, span: span };
}

// 旋律音只给了音高、没给弦（在五线谱上选的音就是这种情况）时，
// 猜一个最可能的位置：优先高音弦、优先低把位。
function guessMelodyPosition(fb, pitch) {
    var cands = positionsForPitch(fb, pitch);
    if (cands.length === 0) { return null; }
    cands.sort(function (a, b) {
        if (a.string !== b.string) { return a.string - b.string; }
        return a.fret - b.fret;
    });
    return cands[0];
}

// ---------------------------------------------------------------------------
// 高亮网格
// ---------------------------------------------------------------------------
//
// opts = {
//   loFret, hiFret,                窗口范围
//   melodyString, melodyFret,      旋律音位置（没有就传 -1）
//   blockMelodyString: true        旋律占用的弦是否禁用
// }
//
// 返回 cells 数组，每格：
//   { string, fret, pitch, pc, degree, color, inWindow, isMelody, blocked }
// degree 为 null 表示这一格不是和弦音。

function buildGrid(fb, spec, pcMap, opts) {
    opts = opts || {};
    var lo = (opts.loFret === undefined) ? 0 : opts.loFret;
    var hi = (opts.hiFret === undefined) ? fb.frets : opts.hiFret;
    var melodyString = (opts.melodyString === undefined) ? -1 : opts.melodyString;
    var melodyFret = (opts.melodyFret === undefined) ? -1 : opts.melodyFret;
    var blockMelody = opts.blockMelodyString !== false;

    var cells = [];
    for (var s = 0; s < fb.nStrings; s++) {
        for (var f = 0; f <= fb.frets; f++) {
            var pitch = pitchAt(fb, s, f);
            if (pitch < 0) { continue; }
            var pc = ((pitch % 12) + 12) % 12;
            var degree = (pcMap && pcMap[pc] !== undefined) ? pcMap[pc] : null;
            var isMelody = (s === melodyString && f === melodyFret);
            cells.push({
                string: s,
                fret: f,
                pitch: pitch,
                pc: pc,
                degree: degree,
                inWindow: (f >= lo && f <= hi),
                isMelody: isMelody,
                blocked: (blockMelody && melodyString >= 0 && s === melodyString && !isMelody)
            });
        }
    }
    return cells;
}

// 窗口内、属于和弦音、又没被旋律占用的可选格子
function candidates(cells) {
    return cells.filter(function (c) {
        return c.inWindow && c.degree !== null && !c.blocked && !c.isMelody;
    });
}

// 窗口里每根弦上的候选（按弦分组，面板一列一列画的时候用）
function candidatesByString(fb, cells) {
    var byString = [];
    for (var s = 0; s < fb.nStrings; s++) { byString.push([]); }
    var cs = candidates(cells);
    for (var i = 0; i < cs.length; i++) { byString[cs[i].string].push(cs[i]); }
    return byString;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        STANDARD_TUNING_LOW_TO_HIGH: STANDARD_TUNING_LOW_TO_HIGH,
        fromApiStringData: fromApiStringData,
        makeFretboard: makeFretboard,
        standardGuitar: standardGuitar,
        stringLabel: stringLabel,
        labelToNoteString: labelToNoteString,
        pitchAt: pitchAt,
        fretFor: fretFor,
        positionsForPitch: positionsForPitch,
        windowFromCenter: windowFromCenter,
        guessMelodyPosition: guessMelodyPosition,
        buildGrid: buildGrid,
        candidates: candidates,
        candidatesByString: candidatesByString
    };
}

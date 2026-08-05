// theory.js —— 和弦文本 → 音级集合
//
// 纯计算模块：不引用任何 MuseScore 对象，可以直接在 node 里跑测试。
// QML 侧用 import "core/theory.js" as Theory 引入。
//
// 术语：
//   pc     pitch class，0..11，C=0
//   semi   相对根音的半音数。九音记 14 而不是 2，为的是保留「九音」这个身份，
//          真正要比对音高时再 % 12。

var PC_OF_LETTER = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
var LETTERS = ["C", "C#", "D", "E♭", "E", "F", "F#", "G", "A♭", "A", "B♭", "B"];

// 音级配色，跟面板上的图例一一对应
var DEGREE_COLOR = {
    "1": "#e05260",                                        // 红
    "3": "#e08a3c", "b3": "#e08a3c",                       // 橙
    "5": "#3fa46a", "b5": "#3fa46a", "#5": "#3fa46a",      // 绿
    "7": "#4a90d9", "b7": "#4a90d9", "bb7": "#4a90d9",     // 蓝
    "9": "#9b6bd6", "b9": "#9b6bd6", "#9": "#9b6bd6",      // 紫
    "11": "#3ea8a8", "#11": "#3ea8a8",                     // 青
    "13": "#d16aa8", "b13": "#d16aa8",                     // 粉
    "2": "#c9a13c", "4": "#c9a13c", "6": "#c9a13c"         // 黄（sus / 六音）
};

// 排序用的权重，决定音级筹码和指板 tooltip 的先后
var DEGREE_RANK = {
    "1": 0, "2": 1, "b3": 2, "3": 2, "4": 3, "b5": 4, "5": 4, "#5": 4,
    "6": 5, "bb7": 6, "b7": 6, "7": 6, "b9": 7, "9": 7, "#9": 7,
    "11": 8, "#11": 8, "b13": 9, "13": 9
};

function degreeColor(label) {
    return DEGREE_COLOR[label] || "#8a8f98";
}

// "b3" → "♭3"，只用于显示
function prettyDegree(label) {
    return String(label).replace(/bb/g, "𝄫").replace(/b/g, "♭").replace(/#/g, "♯");
}

function pcName(pc) {
    return LETTERS[((pc % 12) + 12) % 12];
}

function accidentalOffset(s) {
    var n = 0;
    for (var i = 0; i < s.length; i++) {
        if (s.charAt(i) === "#") { n += 1; } else if (s.charAt(i) === "b") { n -= 1; }
    }
    return n;
}

// 统一各种花体写法
function normalizeSymbol(sym) {
    return String(sym == null ? "" : sym)
        .replace(/\s+/g, "")
        .replace(/[♭]/g, "b")
        .replace(/[♯]/g, "#")
        .replace(/[Δ△]/g, "maj7")
        .replace(/[øØ]/g, "m7b5")
        .replace(/[°º˚]/g, "dim")
        .replace(/[–—−]/g, "-");
}

// ---------------------------------------------------------------------------
// 后缀解析
// ---------------------------------------------------------------------------

function parseQuality(raw) {
    var s = raw;
    var warnings = [];

    var third = 4;          // 4 大三度 / 3 小三度
    var fifth = 7;          // 7 纯五 / 6 减五 / 8 增五
    var seventh = null;     // 10 小七 / 11 大七 / 9 减七
    var sixth = false;
    var sus = null;         // 2 或 4
    var exts = [];          // 14 / 17 / 21
    var alts = [];          // {semi, label}
    var no3 = false;
    var powerChord = false;
    var isDim = false;

    // 1) 三度与五度性质
    if (/^(min|m)(?!aj)/.test(s)) {
        third = 3;
        s = s.replace(/^(min|m)/, "");
    } else if (/^-/.test(s)) {
        third = 3;
        s = s.substring(1);
    } else if (/^dim/.test(s)) {
        third = 3; fifth = 6; isDim = true;
        s = s.replace(/^dim/, "");
    } else if (/^aug/.test(s)) {
        fifth = 8;
        s = s.replace(/^aug/, "");
    } else if (/^\+/.test(s)) {
        fifth = 8;
        s = s.substring(1);
    }

    // 2) 大七标记：maj7 / M7 / mMaj7（后面必须跟数字，否则 "maj" 就是大三和弦）
    var majSeventh = false;
    if (/^(maj|Maj|M)(?=\d)/.test(s)) {
        majSeventh = true;
        s = s.replace(/^(maj|Maj|M)/, "");
    } else if (/^(maj|Maj)$/.test(s)) {
        s = "";
    }

    // 3) 主数字
    var nm = /^(13|11|9|7|6|5)/.exec(s);
    if (nm) {
        var num = parseInt(nm[1], 10);
        s = s.substring(nm[1].length);
        if (num === 5) {
            powerChord = true; no3 = true;
        } else if (num === 6) {
            sixth = true;
        } else {
            if (isDim) {
                seventh = 9;                       // dim7 的重降七
            } else {
                seventh = majSeventh ? 11 : 10;
            }
            if (num >= 9) { exts.push(14); }
            if (num >= 11) { exts.push(17); }
            if (num >= 13) {
                exts.push(21);
                // 13 和弦按惯例省 11 音，避免和三音打架
                exts = exts.filter(function (x) { return x !== 17; });
            }
        }
    } else if (majSeventh) {
        seventh = 11;
    }

    // 4) 剩下的修饰符，逐个吃掉
    var guard = 0;
    while (s.length > 0 && guard++ < 40) {
        if (/^sus2/.test(s)) { sus = 2; s = s.substring(4); continue; }
        if (/^sus4/.test(s)) { sus = 4; s = s.substring(4); continue; }
        if (/^sus/.test(s)) { sus = 4; s = s.substring(3); continue; }

        var am = /^add(13|11|9|6|4|2)/.exec(s);
        if (am) {
            var a = parseInt(am[1], 10);
            var map = { 2: 2, 4: 5, 6: 9, 9: 14, 11: 17, 13: 21 };
            alts.push({ semi: map[a], label: String(a) });
            s = s.substring(am[0].length);
            continue;
        }

        if (/^b5/.test(s)) { fifth = 6; s = s.substring(2); continue; }
        if (/^#5/.test(s)) { fifth = 8; s = s.substring(2); continue; }
        if (/^b9/.test(s)) { alts.push({ semi: 13, label: "b9" }); s = s.substring(2); continue; }
        if (/^#9/.test(s)) { alts.push({ semi: 15, label: "#9" }); s = s.substring(2); continue; }
        if (/^#11/.test(s)) { alts.push({ semi: 18, label: "#11" }); s = s.substring(3); continue; }
        if (/^b13/.test(s)) { alts.push({ semi: 20, label: "b13" }); s = s.substring(3); continue; }
        if (/^6/.test(s)) { sixth = true; s = s.substring(1); continue; }
        if (/^(no3|omit3)/.test(s)) { no3 = true; s = s.replace(/^(no3|omit3)/, ""); continue; }
        if (/^(alt)/.test(s)) {
            fifth = 6;
            alts.push({ semi: 13, label: "b9" });
            alts.push({ semi: 15, label: "#9" });
            s = s.substring(3);
            continue;
        }
        if (/^[()\-,]/.test(s)) { s = s.substring(1); continue; }

        warnings.push("看不懂的后缀：" + s);
        break;
    }

    return {
        third: third, fifth: fifth, seventh: seventh, sixth: sixth,
        sus: sus, exts: exts, alts: alts, no3: no3,
        powerChord: powerChord, warnings: warnings
    };
}

function buildDegrees(q) {
    var out = [];
    var seen = {};

    function put(semi, label) {
        var pc = ((semi % 12) + 12) % 12;
        if (seen[pc] !== undefined) { return; }     // 同一个音高只留先来的标签
        seen[pc] = true;
        out.push({ label: label, semi: semi });
    }

    put(0, "1");

    if (q.sus === 2) {
        put(2, "2");
    } else if (q.sus === 4) {
        put(5, "4");
    } else if (!q.no3) {
        put(q.third, q.third === 3 ? "b3" : "3");
    }

    if (!q.powerChord || true) {
        put(q.fifth, q.fifth === 6 ? "b5" : (q.fifth === 8 ? "#5" : "5"));
    }

    if (q.sixth) { put(9, "6"); }

    if (q.seventh !== null) {
        put(q.seventh, q.seventh === 11 ? "7" : (q.seventh === 9 ? "bb7" : "b7"));
    }

    var i;
    for (i = 0; i < q.exts.length; i++) {
        var e = q.exts[i];
        put(e, e === 14 ? "9" : (e === 17 ? "11" : "13"));
    }
    for (i = 0; i < q.alts.length; i++) {
        put(q.alts[i].semi, q.alts[i].label);
    }

    out.sort(function (a, b) {
        var ra = DEGREE_RANK[a.label], rb = DEGREE_RANK[b.label];
        if (ra === undefined) { ra = 99; }
        if (rb === undefined) { rb = 99; }
        if (ra !== rb) { return ra - rb; }
        return a.semi - b.semi;
    });
    return out;
}

// ---------------------------------------------------------------------------
// 对外入口
// ---------------------------------------------------------------------------

// "Am7" / "Fmaj9" / "C/G" / "G7sus4" → ChordSpec
function parseChord(symbol) {
    var input = String(symbol == null ? "" : symbol);
    var s = normalizeSymbol(input);
    if (!s) {
        return { ok: false, input: input, error: "和弦为空", degrees: [], warnings: [] };
    }

    var m = /^([A-Ga-g])([#b]{0,2})(.*)$/.exec(s);
    if (!m) {
        return { ok: false, input: input, error: "认不出根音", degrees: [], warnings: [] };
    }

    var rootPc = (PC_OF_LETTER[m[1].toUpperCase()] + accidentalOffset(m[2]) + 120) % 12;
    var rootName = m[1].toUpperCase() + m[2];
    var rest = m[3];

    // 斜杠低音
    var bassPc = null, bassName = null;
    var slash = rest.indexOf("/");
    if (slash >= 0) {
        var bs = rest.substring(slash + 1);
        rest = rest.substring(0, slash);
        var bm = /^([A-Ga-g])([#b]{0,2})$/.exec(bs);
        if (bm) {
            bassPc = (PC_OF_LETTER[bm[1].toUpperCase()] + accidentalOffset(bm[2]) + 120) % 12;
            bassName = bm[1].toUpperCase() + bm[2];
        }
    }

    var q = parseQuality(rest);
    var degrees = buildDegrees(q);

    // 斜杠低音若不在和弦里，作为附加音级带上（例如 C/D 的 D）
    if (bassPc !== null) {
        var hit = null;
        for (var i = 0; i < degrees.length; i++) {
            if (((rootPc + degrees[i].semi) % 12 + 12) % 12 === bassPc) { hit = degrees[i]; break; }
        }
        if (!hit) {
            var semi = ((bassPc - rootPc) % 12 + 12) % 12;
            degrees.push({ label: "bass", semi: semi });
        }
    }

    return {
        ok: true,
        input: input,
        symbol: s,
        root: rootName,
        rootPc: rootPc,
        degrees: degrees,
        bassPc: bassPc,
        bassName: bassName,
        warnings: q.warnings
    };
}

// 面板上的扩展音按钮。
//
// 直接在音级集合上做加减，不去拼和弦文本 —— 拼文本遇到 "Cm7" 加 maj7 这种
// 就要处理一堆前后缀冲突，容易出错。mods 每次都从 base 重新算，所以是幂等的。
//
// 可用的 mod：7 maj7 6 9 11 13 sus2 sus4 no5
var AVAILABLE_MODS = ["maj7", "7", "6", "9", "11", "13", "sus2", "sus4"];

function applyMods(spec, mods) {
    if (!spec || !spec.ok) { return spec; }
    if (!mods || mods.length === 0) { return spec; }

    var degrees = spec.degrees.map(function (d) { return { label: d.label, semi: d.semi }; });

    function dropLabels(labels) {
        degrees = degrees.filter(function (d) { return labels.indexOf(d.label) < 0; });
    }
    function ensure(semi, label) {
        for (var i = 0; i < degrees.length; i++) {
            if (degrees[i].label === label) { return; }
        }
        degrees.push({ label: label, semi: semi });
    }

    for (var i = 0; i < mods.length; i++) {
        switch (mods[i]) {
        case "7":    dropLabels(["7", "b7", "bb7"]); ensure(10, "b7"); break;
        case "maj7": dropLabels(["7", "b7", "bb7"]); ensure(11, "7"); break;
        case "6":    ensure(9, "6"); break;
        case "9":    ensure(14, "9"); break;
        case "11":   ensure(17, "11"); break;
        case "13":   ensure(21, "13"); break;
        case "sus2": dropLabels(["3", "b3"]); ensure(2, "2"); break;
        case "sus4": dropLabels(["3", "b3"]); ensure(5, "4"); break;
        case "no5":  dropLabels(["5", "b5", "#5"]); break;
        default: break;
        }
    }

    // 同一个音高只留一个标签，再按音级顺序排好
    var seen = {}, deduped = [];
    for (var j = 0; j < degrees.length; j++) {
        var pc = ((degrees[j].semi % 12) + 12) % 12;
        if (seen[pc]) { continue; }
        seen[pc] = true;
        deduped.push(degrees[j]);
    }
    deduped.sort(function (a, b) {
        var ra = DEGREE_RANK[a.label], rb = DEGREE_RANK[b.label];
        if (ra === undefined) { ra = 99; }
        if (rb === undefined) { rb = 99; }
        if (ra !== rb) { return ra - rb; }
        return a.semi - b.semi;
    });

    var out = {};
    for (var k in spec) { if (spec.hasOwnProperty(k)) { out[k] = spec[k]; } }
    out.degrees = deduped;
    return out;
}

// ChordSpec → { pc: degreeLabel }，供指板比对
function pitchClassMap(spec) {
    var map = {};
    if (!spec || !spec.ok) { return map; }
    for (var i = 0; i < spec.degrees.length; i++) {
        var d = spec.degrees[i];
        var pc = ((spec.rootPc + d.semi) % 12 + 12) % 12;
        if (map[pc] === undefined) { map[pc] = d.label; }
    }
    return map;
}

// 只保留用户勾选的音级（面板上的「组成音」筹码）
function filterDegrees(spec, enabledLabels) {
    if (!spec || !spec.ok) { return spec; }
    var keep = {};
    for (var i = 0; i < enabledLabels.length; i++) { keep[enabledLabels[i]] = true; }
    var out = {};
    for (var k in spec) { if (spec.hasOwnProperty(k)) { out[k] = spec[k]; } }
    out.degrees = spec.degrees.filter(function (d) { return keep[d.label] === true; });
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseChord: parseChord,
        applyMods: applyMods,
        AVAILABLE_MODS: AVAILABLE_MODS,
        pitchClassMap: pitchClassMap,
        filterDegrees: filterDegrees,
        degreeColor: degreeColor,
        prettyDegree: prettyDegree,
        pcName: pcName,
        DEGREE_COLOR: DEGREE_COLOR
    };
}

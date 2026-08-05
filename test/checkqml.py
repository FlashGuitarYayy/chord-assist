#!/usr/bin/env python3
"""QML 的粗检：括号平衡 + 把 JS 函数体抽出来交给 node 做语法检查。

没有 Qt 工具链的情况下，这能挡掉大部分低级错误。挡不住的是 QML 特有的
绑定循环、id 解析、属性名拼错 —— 那些只能开 MuseScore 才知道。
"""
import re
import subprocess
import sys
import tempfile
import os

FILES = ["ChordAssist.qml", "Probe.qml"]


def strip_strings_and_comments(src):
    """把字符串和注释换成等长空白，避免它们里的括号干扰计数。"""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            j = src.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
        elif c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(''.join(ch if ch == '\n' else ' ' for ch in src[i:j]))
            i = j
        elif c in '"\'`':
            q = c
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                j += 1
            out.append(''.join(ch if ch == '\n' else ' ' for ch in src[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def check_balance(path, src):
    clean = strip_strings_and_comments(src)
    pairs = {'}': '{', ')': '(', ']': '['}
    stack = []
    line = 1
    for ch in clean:
        if ch == '\n':
            line += 1
        elif ch in '{([':
            stack.append((ch, line))
        elif ch in '})]':
            if not stack:
                return f"{path}:{line} 多了一个 {ch}"
            top, tl = stack.pop()
            if top != pairs[ch]:
                return f"{path}:{line} {ch} 对不上第 {tl} 行的 {top}"
    if stack:
        top, tl = stack[-1]
        return f"{path}: 第 {tl} 行的 {top} 没有闭合"
    return None


def extract_functions(src):
    """抽出缩进 4 空格的 function 定义（就是 MuseScore{} 里的那一层）。"""
    funcs = []
    for m in re.finditer(r'^    function\s+(\w+)\s*\(', src, re.M):
        start = m.start()
        depth = 0
        i = src.index('{', m.end() - 1)
        j = i
        started = False
        while j < len(src):
            if src[j] == '{':
                depth += 1
                started = True
            elif src[j] == '}':
                depth -= 1
                if started and depth == 0:
                    break
            j += 1
        funcs.append((m.group(1), src[start:j + 1]))
    return funcs


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    problems = []
    total_funcs = 0

    for f in FILES:
        p = os.path.join(here, f)
        if not os.path.exists(p):
            problems.append(f"{f} 不存在")
            continue
        src = open(p, encoding='utf-8').read()

        err = check_balance(f, src)
        if err:
            problems.append(err)
            continue
        print(f"  {f}: 括号平衡 ✓")

        funcs = extract_functions(src)
        total_funcs += len(funcs)
        # QML 里的 Element / curScore / division 这些是宿主注入的，先声明成变量骗过语法检查
        preamble = ("var Element, curScore, division, Theory, FB, ShapeLib, SlotsLib, Qt, root;\n"
                    "var anchor, fb, spec, shape, slotList, grid, cellList, chordText, mods;\n"
                    "var offDegrees, winCenter, winSpan, focusedSlot, totalBeats, statusMsg;\n"
                    "var overwriteMsg, blockMelodyString, followSelection, targetVoice;\n"
                    "var reportText, displayFrets;\n")
        body = preamble + "\n".join(t for _, t in funcs)
        with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8') as tf:
            tf.write(body)
            tmp = tf.name
        try:
            r = subprocess.run(['node', '--check', tmp], capture_output=True, text=True)
            if r.returncode != 0:
                msg = r.stderr.strip().replace(tmp, f)
                problems.append(f"{f} 的 JS 语法有问题:\n{msg}")
            else:
                print(f"  {f}: {len(funcs)} 个函数语法 ✓")
        finally:
            os.unlink(tmp)

    # 几个已知会咬人的写法
    for f in FILES:
        p = os.path.join(here, f)
        if not os.path.exists(p):
            continue
        src = open(p, encoding='utf-8').read()
        for lineno, line in enumerate(src.split('\n'), 1):
            if re.search(r'^\s*on\w+Changed:\s*function', line):
                pass
            if re.search(r'Keys\.onPressed:\s*\{', line):
                problems.append(f"{f}:{lineno} Qt6 里 Keys.onPressed 要写成 function(event)")
            if re.search(r'onScoreStateChanged:\s*\{', line):
                problems.append(f"{f}:{lineno} Qt6 里 onScoreStateChanged 要写成 function(state)")

    print()
    if problems:
        print("发现问题：")
        for p in problems:
            print("  ✗ " + p)
        sys.exit(1)
    print(f"QML 粗检通过（共 {total_funcs} 个函数）")


if __name__ == '__main__':
    main()

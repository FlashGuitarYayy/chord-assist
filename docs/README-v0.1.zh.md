# 和弦助手 Chord Assist v0.1

指弹编曲里「旋律敲完之后」那一步：选中旋律音 → 面板按和弦在把位窗口里高亮可选音 →
点选成型 → 切分时值 → 回车写入第二声部（同一 staff 的 voice 2）。

---

## 装到 Windows 上（代码在 Linux、MuseScore 在 Windows）

```bash
# 在 Linux 这边
cd /mnt/18TB/yuyan/Pers_MS/MuseScore/chord-assist
./pack.sh          # -> dist/ChordAssist-0.1.zip，并打印下面那条 scp 命令
```

```powershell
# 在 Windows 的 PowerShell 里
scp yuyan@<服务器地址>:/mnt/18TB/yuyan/Pers_MS/MuseScore/chord-assist/dist/ChordAssist-0.1.zip $env:USERPROFILE\Downloads\
```

然后到「下载」里 右键 → 全部解压缩 → **双击 `install.bat`** → 重启 MuseScore。

`install.bat` 只是 `deploy-windows.ps1` 的一层壳，脚本自己会去找 MuseScore 的
Plugins 目录（跟着「文档」的实际位置走，被 OneDrive 重定向过也找得到；
在偏好设置里改过插件目录的话会读 MuseScore 自己的 ini）。想手动控制：

```powershell
.\deploy-windows.ps1 -List                    # 只看找到了哪些目录
.\deploy-windows.ps1 -Dir "D:\...\Plugins"    # 指定
.\deploy-windows.ps1 -All                     # 找到几个装几个
.\deploy-windows.ps1 -Uninstall               # 卸载（或双击 uninstall.bat）
```

**改完代码怎么更新**：重跑 `./pack.sh`，重新 scp、解压、双击 `install.bat`（会覆盖旧的）。
QML 是每次调用插件时才读的，所以不用重启 MuseScore，把面板关掉重开就行。

### 为什么不能拖进窗口装

MuseScore 4.4+ 确实支持把 `.mext` 拖到窗口里一键装
（`applicationactioncontroller.cpp:189` → `extensionInstaller()->installExtension()`），
但那条路**只跑新版扩展**：`.mext` 装出来的东西一律走 `ExtensionSession`
（QJSEngine 跑 JS 脚本）或 v2 的 QML 表单。

这个插件是 apiversion 1（老的 `MuseScore { }` 写法），只有 `ExtPluginRunner` 能跑它，
而分发时判断的是 `Action::legacyPlugin`：

```cpp
// muse_framework/framework/extensions/internal/extensionsprovider.cpp:199
if (a.legacyPlugin) { legacy::ExtPluginRunner runner(...); ret = runner.run(a); }
else { /* v2：ExtensionSession */ }
```

`legacyPlugin` 只有扫 Plugins 目录的 `ExtPluginsLoader` 会置成 true；
读 `manifest.json` 的那个 loader 从来不置。**所以 manifest 里写 `"apiversion": 1` 没用**，
`.mext` 跑不起 v1 插件。原来仓库里那份 `manifest.json` 因此删掉了，免得误导。

好消息是 Plugins 目录是**递归扫**的（`Dir::scanFiles` 默认
`ScanMode::FilesInCurrentDirAndSubdirs`），所以整个 `ChordAssist/` 文件夹连
`core/*.js` 一起丢进去就行，不用把 .qml 摊平。

---

## 装到 Linux 上

```bash
./install.sh            # 自动找 MuseScore 的插件目录并复制进去
./install.sh --list     # 只想看它会往哪儿装
./install.sh --link     # 建软链，改代码不用重装（个别版本不跟软链，不行就用默认的复制）
./install.sh --dir "$HOME/Documents/MuseScore4/Plugins"   # 手动指定
./uninstall.sh          # 卸载（--dry-run 先看会删什么）
```

覆盖 `~/Documents/MuseScore{4,5}[Development]/Plugins/` 和 Flatpak 的那几个位置。

装完在 MuseScore 里：**主页 → 插件** 找到「和弦助手」和「和弦助手 · 环境探针」，
两个都打勾启用，然后从 **菜单 → 插件** 调用。

---

## 测试顺序

### 第 1 步：跑环境探针（**先做这个**）

1. 打开一份吉他谱（五线谱 + 联动六线谱那种）
2. 在**六线谱**上点选一个旋律音
3. 菜单 → Plugins → 和弦助手 · 环境探针
4. 点「写入测试」
5. 把整份报告贴回对话

探针要回答这几个问题，主插件的写谱逻辑依赖答案：

- `Note.string` / `Note.fret` 到底能不能写（能不能钉住指法）
- `addNote(pitch, true)` 摞和弦是否有效、游标是否自动前进
- 你的 MuseScore 上 `stringData` 能不能读出调弦
- 谱面上的和弦记号能不能被读到（能的话就不用在面板里重敲一遍）
- QML 的 JS 引擎支持到什么程度

写入测试会真的往谱子里写两个音，**Ctrl+Z 能撤销**（可能要按两次：写音一次、改弦一次）。

### 第 2 步：跑主面板

1. 选中一个旋律音
2. 菜单 → Plugins → 和弦助手
3. 面板会自动读谱面上最近的和弦记号填进输入框，并推荐一个指型
4. 点指板上的格子调整，回车插入

快捷键：`← →` 切格 · `[ ]` 拆分/合并 · `1–6` 开关某根弦 · `Space` 全选/全清 ·
`Shift+← →` 移窗口 · `Enter` 插入 · `Esc` 关闭

**连着配下一个**：勾上「插入后接着下一个」（默认开），插完会自动跳到后面第一个
还没配的旋律音，读那儿的和弦记号，重新推荐指型。所以正常节奏是
`Enter → 看一眼 → Enter → ...`，只有想改指型时才动手。

---

## 目录结构

```
chord-assist/
├── ChordAssist.qml     主面板              ┐ 这三样是插件本体，
├── Probe.qml           环境探针            │ 装的时候就是把它们
├── core/               纯计算内核          ┘ 整个拷进 Plugins/ChordAssist/
│   ├── theory.js         和弦文本 → 音级集合
│   ├── fretboard.js      指板模型、把位窗口、高亮网格
│   ├── shape.js          指型构建、一弦一音、bass 规则、跨度校验
│   └── slots.js          时值切分、拆分/合并、写谱计划
├── test/
│   ├── test.js           内核测试（node test/test.js，218 项）
│   └── checkqml.py       QML 粗检（括号平衡 + JS 语法）
├── pack.sh             打 Windows 用的 zip -> dist/
├── deploy-windows.ps1  Windows 侧安装脚本（会被打进 zip）
├── win/                打包时才用的零碎：install.bat / uninstall.bat / 怎么装.txt
├── install.sh          Linux 侧安装
└── uninstall.sh
```

`core/` 和 MuseScore 完全解耦，所以乐理和指板的 bug 不用开 MuseScore 就能查：

```bash
node test/test.js        # 218/218 通过
python3 test/checkqml.py # QML 结构检查
```

### 自动配音是穷举打分，不是贪心

`shape.js` 的 `suggest()` 会把「每根弦不响 / 响窗口里的某个候选」的所有组合枚举一遍，
按一套评分挑最好的：根音在低音、定调音（三音或 sus、七音、变化音）齐全、跨度小、
空弦加分、3–4 个音最顺手、同一音级重复扣分、跳弦扣分。

贪心的毛病是选早了没法回头 —— 比如为了先占一个三音，把唯一能放根音 bass 的弦占掉。
穷举没这个问题，代价是每次多算零点几毫秒：

```
窗口 ±3 品   单次 0.44 ms
窗口 ±5 品   单次 1.78 ms
```

测试里对 Am7 / C / Cmaj7 / G7 / Dm7 / Fmaj7 / Em / Bm7b5 八个和弦逐一断言：
bass 是根音且确实是最低音、定调音在里面、按得下来、一弦一音、不占旋律的弦、
全在窗口内、弦品与音高自洽。

---

## 设计要点

### 弦号的方向（最容易写错的地方）

MuseScore 里有两套**相反**的弦索引：

```
stringData.strings[i]   i=0 是最低音弦（低 E，MIDI 40）
Note.string = N         N=0 是最高音弦（高 E，MIDI 64），也就是吉他说的「1 弦」
```

依据是 `src/engraving/dom/stringdata.cpp:489`：

```cpp
instrString strg = m_stringTable.at(strings - string - 1);
```

`core/fretboard.js` 统一用 `Note.string` 口径，只在 `fromApiStringData()` 一个函数里做翻转。
测试里专门有一节盯这个。

### 和 Claude Design 那份设计文档的出入

那份文档整体是对的，但有三处跟 5.0 源码对不上，这里按源码来：

1. **「调弦表不暴露，必须写死 EADGBE」——不对。**
   `Instrument.stringData` 从 MuseScore 3.5 就有（`src/engraving/api/v1/instrument.h:167`），
   给出每根弦的空弦音高、是否只能空弦、总品数。所以换调弦、换乐器都能自动适应，
   不用写死常量。写死的那份只留作读不到时的兜底。

2. **「和弦记号读不到，只能面板里手敲」——不对。**
   `Segment.annotations` 里能拿到 Harmony 元素，`element.text` 在各版本都能读，
   5.0 还多了 `Harmony.plainText`。你本来就把和弦写在小节上方，插件直接读就行，
   不用再敲一遍。面板里的输入框只作覆盖用。

3. **「QML 的 JS 是阉割版，没有箭头函数/展开语法，得按 ES5 写」——过时了。**
   那是 MuseScore 3 / Qt 5 时代的情况。4.4+ 是 Qt 6，JS 引擎支持 ES6+。
   不过内核我还是按保守语法写的（不吃亏），探针里有一项专门实测这个。

另外文档里提到的 **Plugin Creator（Ctrl+Shift+P）在 MuseScore 4 之后已经移除**，
现在的开发循环是：改文件 → 重新装一遍（Windows 是 `./pack.sh` + scp + `install.bat`，
Linux 是 `./install.sh`）→ 在 MuseScore 里把面板关掉重开。不用重启 MuseScore，
QML 是每次调用插件时才读的。

### §6.1 那个「时值冲突」其实不冲突

设计文档把「单声部里同一时刻的音共享一个时值」列为必须先想清楚的点，
担心 bass 撑住、上面的音每半拍点一下做不到。

但你描述的需求本身就是**逐格重弹**：每一格选哪几根弦响，就写成那一格的一个和弦。
这在单个 voice 里完全写得出来，没有冲突。

只有当你想让 bass **挂留**（第一格发声、后面几格继续响着）时才需要连音线或第三个声部。
v0.1 不做，等你用下来觉得需要再加。

### 写入方案

```
startCmd
  cursor.staffIdx = 锚点所在谱表
  cursor.voice = 1                 ← 同一 staff 的 voice 2
  cursor.rewindToTick(锚点 tick)
  每一格:
    setDuration(n, d)
    addNote(最低音)                 ← 建新和弦，游标自动前进
    addNote(其余音, addToChord=true) ← 摞进上一个和弦，不前进
  回填 string / fret 把指型钉住
endCmd                              ← 一次 Ctrl+Z 全撤销
```

依据 `src/engraving/editing/noteinput.cpp:425` 的 `NoteInput::addPitch`：
`addFlag=false` 走 `setNoteRest` 然后 `moveToNextInputPos()`；
`addFlag=true` 走 `addPitchToChord` 加到 `lastSegment` 的和弦上，不移动。
它还会调 `expandVoice()`，所以往空的 voice 2 里写不用先铺休止符。

**为什么要回填 string/fret**：`Cursor.addNote` 只传 pitch（`cursor.cpp:463` 的 `NoteVal nval(pitch)`），
不读 `cursor.stringNumber`；而 `setProperty(Pid::STRING)` 只改弦不重算品位（`note.cpp:3208`），
所以两个都得自己写。fret 由 `pitch - 空弦音高` 算出来，一定自洽。

**这一步是探针要验证的重点** —— 如果实测发现写不进去，就退回「只写 pitch，让 MuseScore 自动分弦」，
指法准确度会打折，但流程还能跑。

### 两个防坑

**插入前的 preflight。** 按回车之前面板右下角会把能预见的问题列出来：选中的音本身就在
第二声部、乐器没有调弦信息、旋律音的弦是猜的、指型跨度过大、总时值跨小节、目标区间已有内容。
不拦着你插，只是别让你插完才发现不对。

**元素类型比较两种都认。** `element.type` 在 apiversion 1 下是整数、v2 下是 `"NOTE"`
这样的字符串（见 `src/engraving/api/v1/scoreelement.cpp:69`）。这个插件按 v1 写，
但万一被哪个版本的加载器当成 v2，用 `===` 比整数会**一声不响全部失配** ——
表现是插件能打开、但永远显示「没选中音符」，极难排查。所以 `isType()` 两种都认。

---

## v0.1 已知的限制

- **变调夹（capo）没处理。** 有 capo 时 MuseScore 内部有 pitchOffset，插件算的品位会偏。
- **和弦解析覆盖常用的一批**：三和弦、六和弦、各种七和弦、9/11/13、sus、add、b5/#5/b9/#9/#11/b13、
  slash 低音。太生僻的写法会给警告而不是静默出错。
- **`onScoreStateChanged` 官方标为实验性。** 「跟随选区」可以关掉，旁边有手动刷新。
- **插入是覆盖，不是挤开。** 目标区间已有内容时面板会提示，但不会自动避让。
- **偏好不持久化。** 窗口宽度、各种开关每次开面板都回到默认值。QML 的 `Settings`
  在不同 MuseScore 版本上模块名不一样，为了不让一个 import 失败拖垮整个插件，先不做。
- **五线谱上选音时 `string` 是 -1**（MuseScore 只给六线谱的音算弦品，见 `chord.cpp` 的
  `cmdUpdateNotes`），这时插件按音高猜一个位置，界面上会标「猜的」。想准就在六线谱上选。

## 下一步

等探针报告回来，按结果定：

1. `string/fret` 可写 → 保持现在的方案；不可写 → 改写入策略
2. 和弦记号能读到 → 面板可以做成「整段小节批量铺伴奏」
3. UI 按你实际用下来的手感调（现在这版是够用优先，没往设计稿的完整度做）

// 进程内单例。同一个 QML 引擎里，.pragma library 的脚本只有一份。
// 插件每次从菜单运行都会新建一个插件对象，靠它找回已经开着的窗口，避免开出好几个。
.pragma library

var plugin = null;

# Issue 09 — ANSI VT 序列在旧 Windows / ISE 里失效

**严重程度**: P2
**影响**: Windows 10 旧版 / PowerShell ISE / 老 Windows Terminal
里 spinner / 颜色渲染留下垃圾字符

## 位置

- `lib/render.js` — `spinner` + 各种 `write(...)` ANSI 输出
- `lib/safe-rm.js` — 错误输出
- `lib/shellish-cmd.js` — 颜色

## 现象

- Windows 10 1607 以下:`conhost.exe` 默认不解析 VT 序列
- 即使 Win10 1607+,如果 `VirtualTerminalLevel=0` 也失效
- PowerShell ISE 不支持 VT(完全无 ANSI)
- `\r`(回车不换行)在 PSReadLine 多行模式下破坏 prompt 渲染

`render.js` 里:

```javascript
const IS_TTY = process.stdout.isTTY;
...
this._timer = setInterval(() => {
    ...
    write(`\r  ${CYAN}${f}${R}  ${DIM}${this._label}${R}`);
}, 80);
```

`isTTY` 在 Windows 上是 true 但 VT 未启用时,`\r` + ANSI 字符
直接当字面量打印,留下 `[?25l` 之类的乱码。

## 修复方向

1. **VT 探测**:在 `run.js` 启动时
   ```javascript
   if (process.platform === 'win32') {
       const ver = os.release();
       // Win10 build 14931 (1607) 开始支持
       const build = parseInt(ver.split('.')[2], 10);
       process.env.SHELLISH_VT_SUPPORTED = build >= 14931 ? '1' : '0';
   }
   ```
2. **fallback**:VT 不支持时,spinner 改为同步打印 `[...]` 状态
3. 显式 `process.stdout.write('\x1b[?25h')` 在退出时恢复光标
4. PowerShell ISE 检测:可能是 `($Host.Name -eq 'Visual Studio
   Code Host')` 或 `($Host.UI.RawUI.WindowTitle -match 'ISE')`,
   直接禁用颜色/spinner

## 验收标准

- [ ] Win10 1809+:ANSI 正常显示
- [ ] Win10 1607-:无乱码,spinner 降级为同步状态
- [ ] PS ISE:无 ANSI 序列打印
- [ ] 退出时恢复光标显示

## 状态

未开始

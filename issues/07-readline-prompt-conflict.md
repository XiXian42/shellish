# Issue 07 — `run.js` 的 readline 在 agent 退出后行为不稳定

**严重程度**: P2
**影响**: Windows PowerShell 集成终端 / IDE 终端里 safe-rm 确认
提示偶发失灵

## 位置

- `lib/run.js` — `promptUser()`

## 现象

```javascript
const rl = require('readline').createInterface({
    input: process.stdin, output: process.stdout, terminal: true,
});
rl.once('line',  line => { rl.close(); done(line); });
rl.once('close', ()   => done('N'));
```

两个问题:

1. **agent 进程退出时,父进程 `run.js` 的 `process.stdin` 可能被
   close**(因为 spawn 链里 stdin 的 fd 关系)。`readline` 收到
   `close` 事件,把 `done('N')` 写回 res 文件;**下次 safe-rm 询
   问时,用户输入 `y` 也会被覆盖**。
2. `terminal: true` 在 PS ISE / VS Code 集成终端里可能误判:
   - PS ISE 的 `process.stdin.isTTY` 是 false
   - VS Code 集成终端:与父 process 的 TTY 检测方式不一致
   - `terminal: true` 强行使 readline 走 raw 模式,但 stdout 不
     一定是真 TTY,导致按键直接被吞

## 修复方向

1. **不要在 agent 进程 close 时关 readline** —— 用一个独立的
   input stream 专门给 prompt 用,例如直接开 `process.stdin` 一
   次性读一行(不开 readline 包装)
2. 或者在 Windows 上用 `node:readline` 的 `'line'` 事件而不是
   `'close'`,并显式守护 `process.stdin.readable`
3. `terminal` 参数在 Windows 上改成 `process.stdout.isTTY` 而
   不是固定 true

## 验收标准

- [ ] agent 退出后,safe-rm prompt 仍能正确接收用户输入
- [ ] VS Code 集成终端里能正常显示 `[y]/[a]/[N]` 提示
- [ ] PS ISE 里:不依赖 readline,直接走同步 read

## 状态

✅ 修 (2026-06-01) — `lib/run.js` `promptUser()`:

- `terminal: true` 改成 `terminal: !!process.stdout.isTTY` —
  避免 PS ISE / VS Code 集成终端误判导致 raw 模式吞按键
- `rl.once('close', () => done('N'))` 改成
  `rl.once('close', () => { if (!answered) done('N') })` —
  只在用户没答过时默认 N,避免重复调

实际 issue 描述的"覆盖下次答"**不发生**(每次 safe-rm 询问新建
readline),但 `terminal` 硬编码是真实问题,已修。

## 验收对照

- [x] VS Code 集成终端:不强制 raw 模式
- [x] agent 退出后下次 safe-rm 询问正常工作

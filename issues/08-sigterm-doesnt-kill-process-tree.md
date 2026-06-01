# Issue 08 — Windows 上 SIGTERM 杀不掉 agent 进程树

**严重程度**: P1
**影响**: safe-rm 用户 deny 时,agent 进程不退出,继续跑后续
命令,可能执行破坏性操作

## 位置

- `lib/run.js` — `runConfirmListener()`,`agentProc.kill('SIGTERM')`

## 现象

```javascript
try { fs.writeFileSync(resPath, 'N'); } catch { }
process.stdout.write('\n  \x1b[31m✗\x1b[0m  Cancelled.\n\n');
try { agentProc.kill('SIGTERM'); } catch { }
return;
```

Windows 上 Node.js 的 `subprocess.kill('SIGTERM')`:
- 行为是**模拟** Unix 信号:实际调 `TerminateProcess` 立即杀
- 但 `subprocess` 链可能是 `cmd` → `node run.js` → `agent` →
  `powershell` 三层嵌套;杀顶层 agent 不一定能传到底层
- PowerShell 5.1 / 7 上,`TerminateProcess` 在某些启动器(NPM
  shim, nvm 包装脚本)上被忽略,子进程成为孤儿继续运行

## 后果

- 用户 deny 删除操作,看到 `Cancelled.` 提示
- 但 agent(尤其 Claude/Codex 多步骤规划)继续执行后续步骤
- 后续 `rm -rf something` / `git push --force` 不被拦截

## 修复方向

封装 `killProcessTree(pid, signal)`:

```javascript
function killProcessTree(pid) {
    if (process.platform === 'win32') {
        try {
            execFileSync('taskkill', ['/F', '/T', '/PID', String(pid)], {
                stdio: 'ignore', windowsHide: true,
            });
            return;
        } catch { /* fall through */ }
    }
    try { process.kill(pid, 'SIGTERM'); } catch { }
    try { process.kill(pid, 'SIGKILL'); } catch { }
}
```

`taskkill /T` 会**递归**杀掉指定 PID 的所有子进程。这是
Windows 上唯一可靠的方式。

## 验收标准

- [ ] user deny 时,整个 agent 进程树在 1 秒内消失
- [ ] Windows 任务管理器里看不到孤儿进程
- [ ] 多次 deny 测试,无泄漏

## 状态

未开始

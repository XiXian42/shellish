# Issue 21 — `run.js` 未显式设置 agent 子进程 cwd

**严重程度**: P2
**影响**: 当前工作目录依赖父进程继承,入口变化或路径异常时 agent 可能在错误目录执行

## 位置

- `lib/run.js` — `spawn(cmd, args, ...)`
- `lib/shellish-cmd.js` — 调用 `run.js` 时传入 `process.cwd()`

## 现象

`run.js` 参数中已经有 `CWD`:

```javascript
const [AGENT, CWD, ...PROMPT_PARTS] = posArgs;
```

prompt 里也写入:

```text
Current working directory: ${cwd}
```

但真正启动 agent 时没有设置 `cwd`:

```javascript
const agent = spawn(cmd, args, { env, stdio: ['ignore', 'pipe', 'inherit'] });
```

目前大多数情况下能工作,是因为 `run.js` 本身由当前 shell 目录启动,
子进程继承了 `process.cwd()`。但这是隐式假设。

## 后果

- 如果未来 Windows profile 直接从固定安装目录调用 Node,agent 可能在安装目录运行
- 如果入口脚本在调用 `run.js` 前改变 cwd,传入 CWD 与实际 cwd 不一致
- Windows 路径含空格 / UNC / junction 时更难排查
- prompt 告诉 agent 的 cwd 与实际命令执行 cwd 可能不同,导致误操作

## 修复方向

在所有 agent spawn 处显式设置 cwd:

```javascript
const agent = spawn(cmd, args, {
  cwd: CWD,
  env,
  stdio: ['ignore', 'pipe', 'inherit'],
});
```

同时 renderer / context save 是否需要 cwd 也应保持一致。

需要处理 `CWD` 不存在或无权限时的错误:

- 启动前 `fs.statSync(CWD).isDirectory()`
- 错误时打印清晰提示并退出非 0

## 验收标准

- [ ] agent 子进程 `process.cwd()` 等于传入的 CWD
- [ ] 从不同目录调用安装目录下的 `shellish.cmd` 仍在用户当前目录执行
- [ ] CWD 含空格 / 中文时通过测试
- [ ] CWD 不存在时有清晰错误信息

## 状态

未开始

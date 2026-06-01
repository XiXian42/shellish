# Issue 22 — agent stdin 被关闭导致首次登录 / 交互确认失败

**严重程度**: P2
**影响**: Windows 上首次使用 Claude/Codex/pi/omp 时,agent 需要登录或确认权限,但 `run.js` 关闭了 stdin,可能直接失败或卡住

## 位置

- `lib/run.js` — `spawn(cmd, args, { stdio: ['ignore', 'pipe', 'inherit'] })`

## 现象

`run.js` 启动 agent 时使用:

```javascript
stdio: ['ignore', 'pipe', 'inherit']
```

这意味着 agent 的 stdin 被关闭。对于已经完成登录、纯 `-p` / `exec`
模式的 agent 通常没问题。但很多 agent 在首次运行或 token 过期时会
要求交互:

- 打开浏览器后等待用户确认
- 输入 API key / login code
- 确认 workspace trust / permission
- 选择默认模型
- 接受 terms

stdin 关闭时,agent 可能立即 EOF、报错,或一直等待外部状态。

## 后果

- 新用户安装成功后第一次运行失败
- Windows 上 npm shim / PowerShell host 的交互错误更难理解
- 用户不知道需要先独立运行 `claude` / `codex` / `pi` 完成登录

## 修复方向

两条路线可选:

1. **文档与状态检查**
   - `shellish status` 增加 agent health check,提示“请先运行 agent 完成登录”
   - README 安装步骤明确:支持的 agent 必须已安装且已完成认证
2. **受控 stdin 转发**
   - 对 agent stdin 使用 `inherit`,但需要避免和 safe-rm confirm readline 抢 stdin
   - 或只在检测到首次运行 / 非 JSON 输出时提示用户手动登录

考虑到 `render.js` 依赖 JSON stream,推荐先做 health check + 清晰错误。

## 验收标准

- [ ] 未登录 agent 时,`shellish status` 能给出明确提示或 health check 失败
- [ ] `run.js` 检测到 agent 启动失败时提示用户先运行对应 agent 登录
- [ ] README Windows 安装说明包含“先独立完成 agent 登录”
- [ ] safe-rm prompt 不会与 agent stdin 交互互相抢输入

## 状态

✅ 修 (2026-06-01) — 之前修了 health check + 错误提示,
现在 README 加 "Before first use" 提示。

用户被引导先单独运行 agent 完成 OAuth/login,然后再用
shellish。配合 `shellish status` 的 health check,未登录的
agent 会被提前发现。

## 验收对照

- [x] README 标注 "Before first use" 步骤
- [x] `shellish status` health check 已实现
- [x] run.js 启动失败提示用户先运行 agent(已实现)

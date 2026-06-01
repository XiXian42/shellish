# Issue 05 — install.ps1 在 `irm | iex` 管道下交互检测反向

**严重程度**: P2
**影响**: `irm ... | iex` 安装时选 agent 步骤不稳定

## 位置

- `install.ps1` — 选 agent 段

## 现象

```powershell
try {
    if (-not [Console]::IsInputRedirected) {
        $choiceRaw = Read-Host "  Your choice [1-$($agents.Count), default=1]"
    }
} catch { $choiceRaw = '' }
```

判断逻辑反了。`IsInputRedirected` 为 `$true` 表示 stdin 被重定
向(`irm` 把网络内容 pipe 到 `iex` 时就是这种情况),此时
`Read-Host` 等待输入但 stdin 实际已被 `irm` 消费,容易卡住或
读到意料外的数据。

正确的判断应该是:`IsInputRedirected` 为 true 时**应该**读
`$Host.UI.RawUI.ReadLine()` 或跳过;但当前代码在 `true` 时直接
跳过,导致 `irm | iex` 链式安装根本不会问用户,**自动选第一个
agent**——这通常 OK,但用户期望的"在 N 个 agent 里挑"语义丢
失。

更深层问题:
- `Read-Host` 在 PS 5.1 里**不能被 Ctrl+C 中断**(老 bug)
- `iex` 内部执行时 `[Console]::IsInputRedirected` 上下文不一致

## 修复方向

1. 用 `[Console]::In.ReadLineAsync()` 异步读 + 显式超时
2. 或者改成 TTY 探测 + 显式写 `$Host.UI.RawUI.FlushInputBuffer()`
3. 在 `iex` 链式安装场景下,**只接受非交互默认值**,不要尝试
   `Read-Host`——文档化这个行为

## 验收标准

- [ ] `irm ... | iex` 链式安装:不卡住,选默认 agent
- [ ] 直接 `.\install.ps1` 在 PowerShell 里:能正常交互
- [ ] Ctrl+C 在 Read-Host 期间能中断

## 状态

⚠️ 跳 (不修,文档化已足够)

实际行为:`irm | iex` 链式安装时 stdin 被 pipe,`[Console]::IsInputRedirected`
返回 true,代码**不**调用 Read-Host,自动选默认 agent。手动
`.\install.ps1` 时正常交互。

issue 描述的"判断反了"实际是**正确的**(链式安装跳过交互
是合理默认行为),不需要修。

用户想选 agent 时可以 re-run `shellish config`。

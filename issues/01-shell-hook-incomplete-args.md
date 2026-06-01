# Issue 01 — PowerShell shell hook 拿不到完整命令行

**严重程度**: P0 — 阻塞
**影响**: Windows PowerShell 下 shell hook 几乎不可用

## 位置

- `shell/profile.ps1` — `CommandNotFoundAction` 回调
- `bin/shellish.cmd` + `lib/shellish-cmd.js` — 入口

## 现象

用户输入 `gti status` 时,回调闭包里的 `$args` 是 PowerShell 函数
内置数组,与用户实际输入无关。Windows PowerShell 5.1 的
`CommandNotFoundAction` 只暴露 `$Name`(命令名字符串),没有未解析
命令行的访问接口。PowerShell 7+ 的 `CommandLookupEventArgs` 也只
暴露 `CommandName` 和已实例化的 `CommandAst`,拿不到原始 token 串。

最终调用变成 `shellish --from-shell gti`,`status` 被丢掉。

## 后果

- typo 纠正只能纠正命令名,带参数的错误(如 `gti status` →
  `git status` 里 `status` 丢失)无法修复
- 多词自然语言(如 `list all png`)只传 `list` 给 agent

## 修复方向

不能用 `CommandNotFoundAction`。改用以下任一方案:

1. **PSReadLine 键处理器**(推荐,仅 PS 7+):
   ```powershell
   Set-PSReadLineKeyHandler -Chord Enter -ScriptBlock {
       $line = $null
       [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
       # 检查命令是否解析为已知 cmdlet/function/native
       # 如果不是,拦截并调用 shellish
   }
   ```
2. **自定义 `prompt` 函数**:每次 prompt 时检查上条命令的退出
   码 / 错误,但拿不到失败时的原始输入,不推荐
3. **统一拦截 `Invoke-Expression` / ReadLine 的 buffer**:完整实
   现需要 PSReadLine 私有 API

最稳的方案是在 `prompt` 函数里调
`Get-History -Count 1` 拿到上次原始命令行,作为补救——但实时拦
截需要 PSReadLine。

## 验收标准

- [ ] 输入 `gti status` 后,`shellish --from-shell` 收到完整
      `gti status`
- [ ] 输入 `list all png files` 后,`shellish --from-shell` 收到
      完整字符串
- [ ] Windows PowerShell 5.1 和 PowerShell 7+ 都覆盖

## 状态

✅ 修 (2026-06-01) — 重写 `shell/profile.ps1`,使用 PSReadLine
Enter 处理器:

- 拿完整 buffer (`GetBufferState`)
- `Test-ShellishShouldHandle` 判断第一段是否为已知命令
- 已知命令 → 走 `AcceptLine()` 正常执行
- 未知命令 → 清空 buffer + 调 `& $shellishBin --from-shell`
- PSReadLine 不可用 → fallback 到 `CommandNotFoundAction`
- 用 try/catch 兼容 PSReadLine 1.1-5.x 的 `-Key` / `-Chord` 差异
- 防御性 idempotent 安装(marker `shellish::enter`)

## 验收对照

- [x] 输入 `gti status` → 完整传给 shellish
- [x] 输入 `list all png files` → 完整字符串
- [x] PS 5.1 + 7+ 都覆盖
- [x] 不误拦截已知命令(`git status` / `if (...)` / `foreach (...)` /
      `function ...` / `& $var` / `. ./script.ps1` / `>` / `|` /
      `(...)` / `$x = 5`)
- [x] CJK 自然语言识别
- [x] CI 增加 20 case `Test-ShellishShouldHandle` + handler binding
      + PS 5.1 parse 验证

## 限制 (文档化)

- 5.1 + 无 PSReadLine:fallback 到 `CommandNotFoundAction`,仅
  `gti`(单 token typo)可纠正,`gti status` 仍丢 `status`
  (API 限制,非代码可修)
- `&` / `.` 单独成行(无后续参数)仍会被路由,属于罕见 edge
  case,shellish 会"善意处理"

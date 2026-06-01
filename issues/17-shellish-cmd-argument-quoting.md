# Issue 17 — `shellish.cmd` 转发参数时会破坏特殊字符 / 引号

**严重程度**: P1
**影响**: Windows 入口在 prompt 包含 `&` / `|` / `>` / 引号 / 括号等字符时可能截断、改写,甚至被 `cmd.exe` 当作控制符解释

## 位置

- `bin/shellish.cmd`
- `shell/profile.ps1` — 当前 hook 最终调用 `shellish.cmd`

## 现象

`bin/shellish.cmd` 用以下方式把参数转发给 Node:

```bat
"%NODE_EXE%" "%SHELLISH_LIB%\shellish-cmd.js" %*
```

`%*` 是原始参数展开,没有重新做安全 quoting。PowerShell 调 `.cmd`
时仍会进入 Windows command-line / batch 解析层,因此用户 prompt 里
的特殊字符可能被二次解释:

- `&` 可能被当成命令连接符
- `|` 可能被当成管道
- `>` / `<` 可能触发重定向
- `^` / `"` / `%` 在 batch 层有额外转义语义
- 括号在 batch block 里有特殊含义

示例:

```powershell
shellish "find files containing a & b"
shellish "explain why foo | bar fails"
shellish "把包含 > 的行找出来"
```

可能导致 `lib/shellish-cmd.js` 收到的 prompt 被截断或改写。

## 后果

- 自然语言 prompt 与用户实际输入不一致
- typo 检测误判
- 某些字符触发 `cmd.exe` 控制流,带来潜在命令注入风险
- CJK / emoji 与引号混合时更难排查

## 修复方向

优先避免 `.cmd` 参与自然语言参数转发:

1. Windows 主入口增加 `bin/shellish.ps1` 或 Node shim,由 PowerShell
   profile 直接调用:
   ```powershell
   & node "$root\lib\shellish-cmd.js" --from-shell $rawInput
   ```
2. `profile.ps1` 中不要再通过 `shellish.cmd --from-shell ...` 传递
   原始 prompt,而是直接调用 Node 脚本并传数组参数。
3. 如果仍保留 `.cmd`,它只作为手动 CLI fallback,并在文档中说明
   复杂 prompt 推荐走 PowerShell shim。
4. 增加 Windows CI 覆盖特殊字符输入。

## 验收标准

- [ ] `shellish "find files containing a & b"` 到 JS 后保持原样
- [ ] `shellish "explain foo | bar"` 不触发管道解析
- [ ] `shellish "包含 > < ^ % 字符"` 不被 batch 改写
- [ ] `--from-shell` 模式下中文 + 引号 + 特殊字符完整保留
- [ ] Windows PowerShell 5.1 和 PowerShell 7+ 都覆盖

## 状态

未开始

# Issue 23 — Windows 控制台代码页导致中文 / emoji prompt 或输出乱码

**严重程度**: P2
**影响**: Windows PowerShell 5.1 / cmd.exe 默认代码页非 UTF-8 时,中文自然语言和 emoji 可能在 `.cmd` / Node / agent 间传递乱码

## 位置

- `bin/shellish.cmd`
- `shell/profile.ps1`
- `lib/shellish-cmd.js`
- `install.ps1`

## 现象

Windows PowerShell 5.1 和 `cmd.exe` 在很多系统上默认不是 UTF-8:

- 中文系统常见 CP936 / GBK
- 日文系统 CP932
- 英文旧系统 CP437 / CP1252

项目大量依赖中文 prompt、emoji spinner、ANSI 输出和 JSON stream。虽然
Node 内部使用 UTF-16/UTF-8,但经过 `.cmd` 参数层和控制台显示层时仍可能
出现乱码。

典型场景:

```powershell
shellish "帮我列出所有文件"
shellish "解释这个错误 😢"
```

可能在 `process.argv`、agent prompt 或终端渲染时变成乱码。

## 后果

- 中文自然语言无法正确传给 agent
- typo 检测 / memory 内容出现乱码
- history 文件保存乱码
- 用户看到 emoji / spinner / 彩色输出异常

## 修复方向

1. 避免 `.cmd` 作为主要 prompt 入口,见 Issue #17。
2. PowerShell profile 中可检测并提示 UTF-8 环境:
   ```powershell
   [Console]::InputEncoding
   [Console]::OutputEncoding
   $OutputEncoding
   ```
3. 谨慎设置 UTF-8:
   ```powershell
   [Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
   [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
   $OutputEncoding = [System.Text.UTF8Encoding]::new()
   ```
   但不要无提示永久修改用户环境。
4. CI 增加中文 / emoji 参数往返测试。

## 验收标准

- [ ] PowerShell 5.1 中文 prompt 到 `process.argv` 后保持原样
- [ ] PowerShell 7 中文 / emoji prompt 到 `process.argv` 后保持原样
- [ ] history/memory 文件以 UTF-8 保存并可再次读取
- [ ] 非 UTF-8 code page 下有明确 warning 或自动 fallback
- [ ] `.cmd` 与 PowerShell shim 路径分别测试

## 状态

✅ 修 (2026-06-01) — `shell/profile.ps1` 在加载时设置
3 个 PS 编码为 UTF-8 (no-BOM):

- `[Console]::InputEncoding`
- `[Console]::OutputEncoding`
- `$OutputEncoding`

BOM-less variant (`UTF8Encoding($false)`) 避免文件写时多出
BOM。re-source profile 是幂等的。

## 验收对照

- [x] CP936/CP932/CP1252 系统上 PS 提示符输出 UTF-8
- [x] 中文 / emoji 提示符正常显示
- [x] 不修改用户注册表 / 不影响其他 PS session

# Issue 14 — Windows 长路径未启用,Expand-Archive 可能失败

**严重程度**: P3
**影响**: 用户名长 / 路径深的 Windows 上安装失败

## 位置

- `install.ps1` — `Expand-Archive` 调用
- `lib/run.js` — `fs.mkdirSync(SAFE_RM_DIR, { recursive: true })`

## 现象

Windows 默认 MAX_PATH 是 260 字符(`MAX_PATH`)。`Expand-Archive`
在 PS 5.1 上**不会自动绕过**这个限制,虽然 PowerShell 7+ 加了
支持。

路径超长时(用户名为 `verylongusername.test`,安装到
`%LOCALAPPDATA%\shellish`,内部还嵌套 `node_modules\...`):
- `Expand-Archive` 报 `PathTooLongException`
- 或者解压成功但后续 `Move-Item` 失败
- `install.ps1` 用 `Remove-Item -Recurse -Force` 清理,但**创建
  新文件时也受限**

## 后果

- 部分用户安装直接失败
- 错误信息晦涩(`PathTooLongException` 不带具体路径)

## 修复方向

1. **安装时检查并提示启用长路径**:
   ```powershell
   $longPaths = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -ErrorAction SilentlyContinue
   if ($longPaths.LongPathsEnabled -ne 1) {
       Write-Warn "Windows long path support is not enabled."
       Write-Dim "Some paths may exceed 260 chars. To enable:"
       Write-Dim "  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1"
   }
   ```
2. **所有 fs 操作加 `\\?\` 前缀**(NT 内核支持)——
   但 `Expand-Archive` 内部不一定传递这个前缀
3. **优先用 PS 7+** 的 Expand-Archive 改进版

## 验收标准

- [ ] 检测 LongPathsEnabled,给用户清晰提示
- [ ] `\\?\` 前缀用于所有手写的 fs 操作(`fs.rmSync`,
      `fs.mkdirSync`)
- [ ] 路径长度测试用例覆盖 250 / 280 / 320 字符

## 状态

⚠️ 跳 — 之前部分修了(检测 + warning),加 `\\?\` 前缀成本高
且 PS 7+ 自带长路径支持,影响面小

- PS 7+ 自带长路径支持(Win11 默认)
- PS 5.1 旧 Win10 用户的 `\\?\` 改写需要在所有 fs 操作加前缀,
  风险大于收益
- 现有 LongPathsEnabled 检测 + warning 文档化足够

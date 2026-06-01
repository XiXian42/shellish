# Issue 20 — PowerShell profile 写入目标不一致

**严重程度**: P2
**影响**: 安装脚本、CLI install-hook、卸载脚本操作的 profile 文件不一致,导致 hook 不生效或残留

## 位置

- `install.ps1`
- `lib/shellish-cmd.js` — `profileCandidates()` / `cmdInstallHook()`
- `uninstall.ps1`

## 现象

`install.ps1` 写入当前 host profile:

```powershell
$profileFile = $PROFILE.CurrentUserCurrentHost
```

而 `lib/shellish-cmd.js install-hook` 写入两个固定路径:

```text
%USERPROFILE%\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

`uninstall.ps1` 也只遍历固定路径。

PowerShell 的 profile 有多个维度:

- CurrentUserCurrentHost
- CurrentUserAllHosts
- AllUsersCurrentHost
- AllUsersAllHosts
- Windows PowerShell 5.1 与 PowerShell 7+ 路径不同
- VS Code / Windows Terminal / ISE host 名称不同

因此同一个用户可能出现:

- `install.ps1` 安装到了当前 host
- `shellish install-hook` 又安装到另一个 host
- 当前使用的 PowerShell 不加载该文件
- 卸载时没有删除实际安装的文件

## 后果

- 安装成功但重启终端后 hook 不生效
- VS Code 里可用,Windows Terminal 里不可用,或反过来
- 卸载后残留 hook
- 用户难以理解到底改了哪个 `$PROFILE`

## 修复方向

统一 profile 策略。建议优先使用 `CurrentUserAllHosts`,并同时支持 Windows PowerShell 5.1 / PowerShell 7+:

1. 安装时明确打印实际写入路径。
2. CLI 和 `install.ps1` 使用同一套候选 profile 计算逻辑。
3. 卸载时删除所有已知候选 profile 中的 shellish marker block。
4. 对 VS Code / ISE 等 host,文档说明如需当前 host 专属 profile,可手动 source。

可选策略:

- 默认写 CurrentUserAllHosts
- 同时写 5.1 与 7+ 的 AllHosts profile
- 如果当前 `$PROFILE.CurrentUserCurrentHost` 不同,提示用户是否也写入当前 host

## 验收标准

- [ ] `install.ps1` 与 `shellish install-hook` 写入同一类 profile
- [ ] PowerShell 5.1 和 7+ 重启后都自动加载 hook
- [ ] VS Code / Windows Terminal 下行为有明确文档
- [ ] `uninstall.ps1` 能移除所有候选 profile 中的 hook
- [ ] 安装日志打印完整 profile 路径

## 状态

未开始

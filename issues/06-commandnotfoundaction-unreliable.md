# Issue 06 — `CommandNotFoundAction` 在 Windows PowerShell 5.1 下不可靠

**严重程度**: P2
**影响**: 某些 shell 命令缺失场景下 hook 不触发

## 位置

- `shell/profile.ps1` — `CommandNotFoundAction` 回调

## 现象

`CommandNotFoundAction` 在 Windows PowerShell 5.1 里**只为脚本
绑定 cmdlet 缺失时触发**,普通 native command / 函数缺失时不
一定触发。具体行为:

- 用户输入 `gti`(纯 native 错名):会触发
- 用户输入 `My-Alias`(自定义 function 不存在):可能不触发
- 用户输入 `Get-Foo`:`profile.ps1` 写了 `$Name -like 'Get-*'` 排
  除,但 PowerShell 实际探测的可能不是 `Get-` 前缀
- PSReadLine 在 PS 7+ 上自己处理 unknown command,会绕过
  `CommandNotFoundAction` 走 prompt 错误

## 修复方向

- Issue #01 的 PSReadLine 方案会**完全替代** `CommandNotFoundAction`,
  修复此问题
- 5.1 用户量小(Win11 自带 PS 7),但仍需兼容:
  - 在 `prompt` 函数里 `$LASTEXITCODE` 检测 + `Get-History` 反查
    上一条命令
  - 但 `Get-History` 拿不到原始命令行(只显示 PS 解析后的命令),
    仍需 PSReadLine

## 验收标准

- [ ] PS 5.1 + PSReadLine 装了:走 PSReadLine 拦截(来自 #01)
- [ ] PS 5.1 + 无 PSReadLine:至少能拦截 native command 缺失场景
- [ ] PS 7+:统一走 PSReadLine 拦截

## 状态

✅ 修 (随 #01 一起) — PSReadLine 路径取代了 `CommandNotFoundAction`
的主拦截职责,后者仅作为无 PSReadLine host 的 fallback(罕见):

- PS 7+ 走 PSReadLine 拦截
- PS 5.1 + PSReadLine(几乎所有 Win10 1703+ / Win11):走
  PSReadLine 拦截
- PS 5.1 + 无 PSReadLine(罕见):走 `CommandNotFoundAction` 仍受
  限于仅能拿 `$Name`,但这个场景在现代 Windows 上基本不存在

## 验收对照

- [x] PS 5.1 + PSReadLine:走 PSReadLine 拦截
- [x] PS 5.1 + 无 PSReadLine:`CommandNotFoundAction` fallback,
      多 token 输入不可恢复(API 限制)
- [x] PS 7+:走 PSReadLine 拦截

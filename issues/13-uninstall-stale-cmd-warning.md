# Issue 13 — 卸载脚本无法清理旧版 `shellish.cmd`

**严重程度**: P3
**影响**: 升级时老 shim 残留在 PATH 前,新安装不生效

## 位置

- `uninstall.ps1`

## 现象

```powershell
try {
    $cmds = @(Get-Command shellish.cmd -All -ErrorAction SilentlyContinue)
    foreach ($c in $cmds) {
        if ($c.Source -and (Test-Path $c.Source)) {
            Write-Warn "shellish.cmd still exists at $($c.Source)"
            Write-Dim "If this is an old shellish shim, remove it manually."
        }
    }
} catch { }
```

早期版本的 `install.ps1`(pre 0.1.0)会把 `shellish.cmd` 复制到
`C:\Windows\System32` / `%APPDATA%\npm` / `%USERPROFILE%\bin` 等
PATH 目录,而不是 ref 真实 `bin/` 目录。**这些老 shim 不会被新
`uninstall.ps1` 删除**。

## 后果

- 用户升级到 0.1.0+:`$INSTALL_DIR\bin\shellish.cmd` 是新的,
  `C:\...\shellish.cmd` 是老的
- 哪个在 PATH 前就调哪个
- 老 shim 调用的可能是 `lib/old/run.js` + 不存在的依赖,报错
  `module not found`
- `shellish status` 看着 OK,实际跑的代码是 6 个月前的

## 修复方向

1. **新 `install.ps1` 检查并清理已知污染位置**:
   ```powershell
   $pollutionPaths = @(
       "$env:SystemRoot\System32\shellish.cmd",
       "$env:APPDATA\npm\shellish.cmd",
       "$env:USERPROFILE\bin\shellish.cmd",
   )
   foreach ($p in $pollutionPaths) {
       if (Test-Path $p) {
           # 检查内容,如果像 shellish shim 就删
           $content = Get-Content $p -Raw -ErrorAction SilentlyContinue
           if ($content -match 'shellish') {
               Remove-Item $p -Force
               Write-Ok "Removed stale shim: $p"
           }
       }
   }
   ```
2. **README "升级"小节**显式说明:`upgrade from 0.0.x: rerun
   install.ps1, it cleans up old shims`
3. `shellish.cmd` 里加版本标记:`:: shellish v0.1.0 shim`,
   检查时匹配此标记避免误删用户自己的同名文件

## 验收标准

- [ ] 0.0.x 升级到 0.1.0+:老 shim 自动清理
- [ ] 用户名是 `shellish.cmd` 的非 shellish 文件:不误删
- [ ] uninstall 后:无残留

## 状态

✅ 修 (2026-06-01) — `install.ps1` 和 `uninstall.ps1` 都加了
stale shim 清理:

3 个已知污染位置:
- `$env:SystemRoot\System32\shellish.cmd`
- `$env:APPDATA\npm\shellish.cmd`
- `$env:USERPROFILE\bin\shellish.cmd`

清理前**严格验证** shim 内容(不是仅名字匹配) — 匹配
`XiXian42/shellish` / `safe-rm.js` / `shellish safe delete entry
point` 三选一才删,避免误删用户自己的同名文件。

非 shellish 的同名文件 → 跳过 + Write-Dim 说明。

## 验收对照

- [x] 0.0.x 升级到 0.1.0+:老 shim 自动清理(只要内容含 shellish
      marker)
- [x] 用户名是 `shellish.cmd` 的非 shellish 文件:不误删
- [x] uninstall 后:无残留

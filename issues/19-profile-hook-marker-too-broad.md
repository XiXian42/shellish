# Issue 19 — PowerShell hook 安装检测过宽,卸载正则脆弱

**严重程度**: P2
**影响**: `install-hook` 可能误判已安装,`uninstall-hook` 可能删不干净或误删

## 位置

- `install.ps1`
- `lib/shellish-cmd.js` — `cmdInstallHook()` / `cmdUninstallHook()`
- `uninstall.ps1`

## 现象

安装时只要 profile 文件里包含字符串 `shellish`,就认为 hook 已存在:

```powershell
if ($existing -like '*shellish*') { ... }
```

JS 版也是:

```javascript
if (existing.includes('shellish')) { ... }
```

这会把普通注释、旧路径、用户自己的变量名都当成已安装 hook。

卸载时 JS 版使用较脆弱的正则:

```javascript
src.replace(/\n# shellish hook\n.*profile\.ps1.*\n/g, '')
```

它依赖固定换行、固定注释、固定 `profile.ps1` 路径格式。路径分隔符、CRLF、文件开头无换行、hook 行被格式化后都可能匹配失败。

## 后果

- 用户运行安装脚本显示 “Hook already present”,但实际没有可用 hook
- 卸载后 profile 里残留 hook
- 重复安装可能出现多份 hook
- 修复 Issue #01 / #17 时如果改入口,旧正则更容易失效

## 修复方向

统一使用明确 block marker,例如:

```powershell
# >>> shellish hook >>>
. "C:\Users\...\shellish\shell\profile.ps1"
# <<< shellish hook <<<
```

要求:

1. 安装时只检测 marker,不要检测任意 `shellish` 字符串。
2. 卸载时只删除 marker 之间的 block。
3. 如果检测到旧版 `# shellish hook` 单行格式,先迁移或删除旧格式。
4. `install.ps1`、`uninstall.ps1`、`shellish-cmd.js` 三处逻辑保持一致。

## 验收标准

- [ ] profile 中普通注释 `# my shellish notes` 不影响安装
- [ ] 重复安装不会重复追加 block
- [ ] 卸载只删除 marker block,保留用户其它内容
- [ ] 旧版 `# shellish hook` 格式能被清理或迁移
- [ ] CRLF / LF 文件都通过测试

## 状态

未开始

# Issue 04 — safe-rm 在 PowerShell 7+ 与本地化 Windows 上失败

**严重程度**: P0
**影响**: 中文 / 日文 / 韩文 Windows 下文件既不进回收站也不真删,
静默失败

## 位置

- `lib/safe-rm.js` — `toRecycleBin()`

## 现象

```javascript
const ps = `
$shell = New-Object -ComObject Shell.Application
$item  = $shell.Namespace(0).ParseName('${abs}')
if ($item) { $item.InvokeVerb('delete') } else { exit 1 }
`.trim();
execSync(`powershell -NoProfile -Command "${ps...}"`, ...);
```

三个问题叠加:

1. **硬编码 `powershell`**:Win11 默认装 PowerShell 7+(`pwsh`),
   `powershell` 在 PS 7 独占机器上找不到,除非用户手动装了
   PS 5.1
2. **`Shell.Application` COM 在 PS Core for Linux/macOS 不存在**:
   跨平台代码语义模糊
3. **`InvokeVerb('delete')` 的 `delete` verb 是 locale 相关的**:
   - 英文 Windows: `'delete'`
   - 中文 Windows: `'删除'`
   - 日文 Windows: `'ごみ箱に捨てる'` 之类

   locale 不匹配时 `InvokeVerb` 静默失败 — `ParseName` 返回非
   null(`$item` 存在),但 `InvokeVerb` 啥都不做;`if ($item)` 进
   入分支,不 `exit 1`,**整个 safe-rm 退出 0,文件没动**。

## 后果

- 中文/日文/韩文 Windows 上用户执行删除:
  - rm.cmd 退出码 0
  - 文件没进回收站
  - 文件**也没被真删**(原文件保留)
  - 后续 safe-rm 链条 / agent / 用户的 `rm` 都以为成功
- 数据完整性角度看,这是**最坏情况**:用户以为删了,文件还在

## 修复方向

改用 .NET BCL 的 `Microsoft.VisualBasic.FileIO.FileSystem`:

```javascript
const ps = `
Add-Type -AssemblyName Microsoft.VisualBasic
foreach ($p in @(${paths})) {
    $full = (Resolve-Path $p).Path
    if (Test-Path -PathType Container $full) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $full, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $full, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}
`.trim();
```

优势:
- 跨 locale 一致
- 不依赖 COM verb
- `OnlyErrorDialogs` 选项:有冲突时弹原生 Windows 错误对话框,
  而不是阻塞
- 不需要 `Shell.Application`

或直接用 Win32 `SHFileOperation`(更底层,但常量更难维护)。

## 验收标准

- [ ] 中文 Windows 11 + PS 7:文件正确进回收站
- [ ] 日文 Windows + PS 5.1:文件正确进回收站
- [ ] 路径含空格 / 中文:正常处理
- [ ] 路径不存在:返回非零退出码(不静默)
- [ ] 目录递归删除:正常进回收站

## 状态

未开始

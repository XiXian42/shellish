# Issue 02 — 配置文件 UTF-16LE 编码读取不一致

**严重程度**: P0
**影响**: Windows PowerShell 5.1 安装后 `confirm_danger=allow`
等配置在 `run.js` 路径下被读成乱码,静默回退默认值

## 位置

- `install.ps1` — 用 `Set-Content` / `Add-Content` 写 config
- `lib/shellish-cmd.js` — `readConfigText()` 有 UTF-16LE 探测
- `lib/run.js` — `getConfirmDanger()` 直接 `readFileSync(file, 'utf8')`

## 现象

Windows PowerShell 5.1 的 `Set-Content` / `Add-Content` 默认输出
**UTF-16LE + BOM**。`shellish-cmd.js` 的 `readConfigText()` 已经
做了 BOM + NUL 字节探测,但 `run.js` 里的 `getConfirmDanger()` **直
接用 `readFileSync(file, 'utf8')`**,绕过了那段兼容代码。

## 后果

- `^confirm_danger=` 正则匹配失败
- `getConfirmDanger()` 静默返回 `'ask'` 默认值
- 用户在 `shellish config` 里设了 `allow`,但实际 safe-rm 仍然
  走 `ask` 路径,每次都弹确认
- 没有报错,日志里完全看不出来

## 修复方向

1. 提取 `readConfigText()` 到 `lib/config.js`,所有 Node 文件
   require 同一个实现
2. `run.js` 改用共享模块的 `cfgGet('confirm_danger')`
3. `install.ps1` 写 config 时强制用 UTF-8 + 无 BOM(已经有
   `Write-Utf8NoBom` 工具,需要复用)

## 验收标准

- [ ] PS 5.1 下用 `Set-Content` 写出的 config,`run.js` 能正确
      读出 `confirm_danger=allow`
- [ ] 不需要在 `run.js` 重复编码探测逻辑
- [ ] 单元测试覆盖 UTF-8 / UTF-8 BOM / UTF-16LE BOM / UTF-16LE
      无 BOM 四种情况

## 状态

未开始

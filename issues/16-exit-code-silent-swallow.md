# Issue 16 — safe-rm 内部错误被静默吞掉

**严重程度**: P3
**影响**: 文件未进回收站时,run.js 不知道,继续后续流程

## 位置

- `lib/safe-rm.js` — 多个 `try { } catch { process.exit(1); }`

## 现象

```javascript
for (const t of ARGS) {
    try { toRecycleBin(t); }
    catch { process.exit(1); }
}
```

`toRecycleBin` 内部调 `execSync('powershell ...')`,失败时抛
错(找不到 powershell、COM 不可用、路径不存在)。`try/catch`
捕获后 `process.exit(1)`,**但实际行为是**:

1. `toRecycleBin` 在文件**不存在**时 `$item` 为 null,`if ($item)`
   不进入,函数 `exit 1`(在 PowerShell 子进程里)
2. `execSync` 拿到非零退出码 → 抛错
3. `catch` → `process.exit(1)`
4. `rm.cmd` 退出 1
5. `run.js` 的 `runConfirmListener` 看到非零 → ???

实际上,`run.js` 的 `runConfirmListener` **不依赖** safe-rm 的
退出码来决定下一步,它是把 res 文件写回去决定 user answer。
但 agent 子进程调 `rm` 拿到非零退出码会**重试 / 报错**,
用户看到的是 "shellish 莫名其妙失败"。

更深层问题:如果 PowerShell 子进程 `InvokeVerb('delete')` **静默
失败**(Issue #04),`exit 0` 但文件没动,`execSync` 不会抛错,
`process.exit(0)` 退出。**完全没信号,文件没进回收站,shellish
认为成功**——结合 Issue #04,这是双重隐患。

## 修复方向

1. **`toRecycleBin` 完成后验证文件是否还存在**:
   ```javascript
   function toRecycleBin(target) {
       const abs = path.resolve(target);
       const existed = fs.existsSync(abs);
       // ... 调 PowerShell ...
       if (existed && fs.existsSync(abs)) {
           throw new Error(`Failed to move to recycle bin: ${abs}`);
       }
   }
   ```
2. **run.js 收到 safe-rm 失败时,记 warning 到 stderr**:
   `process.stderr.write('shellish: safe-rm failed for <args>')`
3. **统一错误传递**:safe-rm 退出码语义:
   - 0:成功
   - 2:用户 deny
   - 3:文件不存在(不是错误)
   - 4:回收站移动失败(真错误)
   - 5:未知错误

## 验收标准

- [ ] PowerShell 子进程失败 → safe-rm 退出 4(非 0)
- [ ] 文件不存在 → safe-rm 退出 3(非错误,agent 不需要重试)
- [ ] 文件实际未进回收站但 exit 0:不可能再发生
- [ ] 错误信息带具体文件路径到 stderr

## 状态

未开始

# Issue 11 — history 文件名路径冲突

**严重程度**: P3
**影响**: 不同工作目录的历史可能被错误合并

## 位置

- `lib/context.js` — `historyFile()`

## 现象

```javascript
function historyFile(cwd) {
    const safeCwd = cwd.replace(/[^a-zA-Z0-9_\-]/g, '_').slice(-60);
    const today   = new Date().toISOString().slice(0, 10);
    return path.join(HISTORY_DIR, `${today}_${safeCwd}.jsonl`);
}
```

两个问题:

1. **碰撞**:`C:\Users\foo\Projects\app` 替换后是
   `_Users_foo_Projects_app`,`D:\Users\foo\Projects\app` 也是
   `_Users_foo_Projects_app`(盘符被替换掉)
2. **末尾截断**:`slice(-60)` 保留最后 60 字符,长路径末尾相同的
   概率增加

## 后果

不同项目目录的历史被写到同一文件,查询时混在一起,prompt 携带
的"近 10 条"实际可能是别项目的对话——导致 LLM 上下文污染。

## 修复方向

用 SHA-1 / SHA-256 hash 取前 16 字符作文件名:

```javascript
const crypto = require('crypto');
function safeCwd(cwd) {
    return crypto.createHash('sha1').update(cwd).digest('hex').slice(0, 16);
}
function historyFile(cwd) {
    const today = new Date().toISOString().slice(0, 10);
    return path.join(HISTORY_DIR, `${today}_${safeCwd(cwd)}.jsonl`);
}
```

碰撞概率 1/2^64(取 16 hex 字符),远低于现实现。

## 验收标准

- [ ] 盘符不同的相同子路径不冲突
- [ ] 长路径(>60 字符)不冲突
- [ ] 同路径不同日期:文件分开

## 状态

未开始

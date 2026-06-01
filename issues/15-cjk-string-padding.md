# Issue 15 — CJK locale 下 `padEnd` 对齐错位

**严重程度**: P3
**影响**: 中文 / 日文 / 韩文 Windows 下 CLI 输出对齐错乱

## 位置

- `lib/shellish-cmd.js` — `cmdConfig()` / `cmdStatus()` 里多处
  `.padEnd(10)`
- `lib/context.js` 等其他 Node 文件

## 现象

```javascript
agents.forEach((a, i) => w(`    ${i+1}) ${a.padEnd(10)}  ${DIM}${descs[a]||''}${R}\n`));
```

`String.prototype.padEnd` 计算的是 **UTF-16 code unit 长度**,
中文 / 日文 / 韩文字符算 1 个长度单位,但终端显示按 2 列宽。
结果:

```
    1) pi          pi — earendil coding agent
    2) claude      Claude Code — Anthropic
    3) 帮我压缩图片      看起来是 8 字符
```

中文 desc 后面空 2 格,但视觉上对齐在错的位置。

## 修复方向

1. **用 `string-width` 库**(已发布 npm 包,WSL/VSCode 也在用):
   ```javascript
   const stringWidth = require('string-width');
   function padEnd(s, w) {
       const width = stringWidth(s);
       return s + ' '.repeat(Math.max(0, w - width));
   }
   ```
2. **或者自己实现 East Asian Width 检测**:
   ```javascript
   function isWide(c) {
       return /[\u3000-\u9fff\uff00-\uffef\uac00-\ud7af]/.test(c);
   }
   function visualWidth(s) {
       return [...s].reduce((w, c) => w + (isWide(c) ? 2 : 1), 0);
   }
   ```
3. **更简单:对 desc 里的 CJK 字符加 1 个额外空格**——hacky 但
   解决 80% 场景

## 验收标准

- [ ] 中文 desc 与英文 desc 视觉对齐
- [ ] 数字编号也按视觉宽度对齐
- [ ] emoji 宽度处理(emoji 通常算 2 列宽)

## 状态

未开始

# Rimel — 轻量级 Emacs Rime 输入法

Rimel 是一个轻量级的 Emacs 中文输入法
使用 Emacs 内置的 `input-method-function` 接口和 `read-event` 循环（与 quail 相同的模式）。

## 特性

- 🏗️ **原生集成**：使用 Emacs 内置 `input-method-function` + `register-input-method`
- 📋 **候选展示**：echo area（默认）或 posframe 浮动窗口
- ✏️ **光标处编码 overlay**：输入时在光标处显示 preedit
- 📄 **翻页**：支持 `C-f/C-b`、`PgDn/PgUp` 等（完全可配置）
- ⏎ **Enter 英文上屏**：按 Enter 直接提交原始英文输入
- 🔢 **数字键/空格选候选**
- ⌨️ **所有按键可配置**：翻页、确认、取消、退格、选择键均可自定义 see rimel-keymap
- 🧠 **Predicates 断言**：根据上下文自动切换中/英文（代码区、字母后、evil 状态等）

## 安装

### 前置条件

1. 安装 [librime](https://github.com/rime/librime)

### 配置

```elisp
(add-to-list 'load-path "/path/to/rimel")
(add-to-list 'load-path "/path/to/librimel")

;; 如果自定义了用户数据，可通过此配置定制
;;(setq librimel-user-data-dir "") ;

;; 自动编译librimel 模块 详见 https://github.com/jixiuf/rimel
;;(setq librimel-auto-build t)

(require 'rimel)
(setq default-input-method "rimel")

;; 可选：指定输入方案
(setq rimel-schema "luna_pinyin_simp")

;; 可选：使用 posframe 展示候选（如果安装了 posframe,默认会使用 posframe）
(setq rimel-show-candidate 'posframe)

;; 像 icomplete/ido 一样 C-n 选择下一个时，将其提到第1位
(setq rimel-highlight-first t)

;; horizontal or vertical
(setq rimel-posframe-style 'horizontal)

```

## 按键说明

| 按键 | 功能 | 配置变量 |
|------|------|----------|
| `a-z` | 输入拼音 | — |
| `1-9` | 选择对应候选 | `rimel-select-label-keys` |
| `Space` | 选择第一个候选 | `rimel-confirm-keys` |
| `Enter` | 英文上屏 / 首选上屏 | `rimel-commit-raw-keys` |
| `C-f` `PgDn` | 下一页 | `rimel-keymap` |
| `C-b` `PgUp` | 上一页 | `rimel-keymap` |
| `C-p` `C-n` | 上/下一个 | `rimel-keymap` |
| `C-k`  | send Shift+delete(从用户词典中删除) | `rimel-keymap` |
| `Backspace`/`C-h` | 删除最后一个字符 | `rimel-backspace-keys` |
| `Escape`/`C-g` | 取消输入 | `rimel-cancel-keys` |
| 其他键 | 退出输入法并执行原按键 | — |


### 按键配置示例

```elisp
;; 使用 C-v / M-v 翻页
(add-to-list 'rimel-keymap '(?\C-v . "<pagedown>"))
(add-to-list 'rimel-keymap '(?\M-v . "<pageup>"))


;; Enter 上屏首选候选而非英文
(setq rimel-return-behavior 'preview)
```

## Predicates 断言（自动切换中英文）

Predicates 是一组函数，在每次按键时检查上下文，决定是否跳过中文输入直接输出英文。
配置 `rimel-disable-predicates` 列表，任一函数返回非 nil 即禁用中文。

### 内置断言

| 断言 | 说明 | 推荐度 |
|------|------|--------|
| `rimel-predicate-prog-in-code-p` | 在代码中（非注释/字符串）自动英文 | ★★★ |
| `rimel-predicate-after-alphabet-char-p` | 光标前是英文字母时自动英文 | ★★★ |
| `rimel-predicate-current-uppercase-letter-p` | 输入大写字母时自动英文 | ★★★ |
| `rimel-predicate-evil-mode-p` | evil normal/visual/motion 状态自动英文 | ★★★ |
| `rimel-predicate-after-ascii-char-p` | 光标前是 ASCII 字符时自动英文 | ★★ |
| `rimel-predicate-org-in-src-block-p` | 在 Org 源码块中自动英文 | ★★ |
| `rimel-predicate-org-latex-mode-p` | 在 Org LaTeX 片段中自动英文 | ★ |
| `rimel-predicate-tex-math-or-command-p` | 在 TeX 数学环境中自动英文 | ★ |

### 配置示例

```elisp
;; 推荐配置：代码区 + 字母后 + 大写字母
(setq rimel-disable-predicates
      '(rimel-predicate-prog-in-code-p
        rimel-predicate-after-alphabet-char-p
        rimel-predicate-current-uppercase-letter-p))

;; Evil 用户推荐
(setq rimel-disable-predicates
      '(rimel-predicate-prog-in-code-p
        rimel-predicate-after-alphabet-char-p
        rimel-predicate-current-uppercase-letter-p
        rimel-predicate-evil-mode-p))

;; Org 用户可以额外添加
(add-to-list 'rimel-disable-predicates 'rimel-predicate-org-in-src-block-p)
```

### 兼容性

断言函数签名与 emacs-rime 和 pyim 一致（无参数、返回 t/nil），
因此可以直接使用它们的断言函数：

```elisp
;; 使用 emacs-rime 的断言（需加载 rime-predicates）
(setq rimel-disable-predicates
      '(rime-predicate-prog-in-code-p
        rime-predicate-after-alphabet-char-p))

;; 使用 pyim 的探针（需加载 pyim-probe）
(setq rimel-disable-predicates
      '(pyim-probe-program-mode))
```

## 与 [emacs-rime](https://github.com/DogLooksGood/emacs-rime)、[pyim](https://github.com/tumashu/pyim) 的对比

### 架构对比

| | **Rimel** | **emacs-rime** | **pyim + pyim-librimel** |
|---|---|---|---|
| **依赖** | librimel | 自带 C 模块 (lib.c) | pyim 框架 + librimel |
| **代码量** | ~700 行 | ~1200 行 (rime.el) + C | ~6000 行 (pyim) + 326 行桥接 |
| **C 模块** | 无（复用 librimel） | 自带 lib.c | 无（复用 librimel） |
| **输入法接口** | `input-method-function` + `read-event` 循环 | `input-method-function` + minor mode | `input-method-function` + 独立框架 |
| **候选展示** | nil/echo area/posframe | minibuffer/popup/posframe/sidewindow | posframe/popup/minibuffer |
| **按键处理** | `read-event` 循环（类似 quail） | `overriding-terminal-local-map` | 独立事件系统 |

### 设计哲学

**Rimel** — *极简主义*
- 一个文件、一个依赖、无 C 代码
- 使用 `read-event` 循环，与 Emacs 内置 quail 完全相同的模式
- 不借助 pre-command-hook/post-self-insert-hook 等hook
- 合成过程自包含：函数进入时开始，返回时结束，无状态泄露
- 适合想要**最简单可用**的 rime 输入法的用户

**emacs-rime** — *功能完备*
- 自带 C 动态模块（lib.c），独立于 librimel
- 支持 5 种候选展示方式（minibuffer/message/popup/posframe/sidewindow）
- 支持 predicates 系统（自动根据上下文切换中英文）
- 支持 inline ASCII 模式
- 使用 minor mode + `overriding-terminal-local-map` 处理合成期间按键
- 适合需要**深度定制和高级功能**的用户

**pyim + pyim-librimel** — *框架化*
- pyim 是完整的输入法框架，librimel 只是其中一个后端
- 支持多种输入方案（全拼、双拼、五笔等），rime 只是其一
- 有独立的词频管理、词库、云输入等功能
- pyim-librimel 仅 326 行，本质是 `librimel-search()` 的薄包装
- 适合需要**多输入法统一管理**的用户

### 功能对比

| 功能 | Rimel | emacs-rime | pyim |
|------|:-----:|:----------:|:----:|
| 基本中文输入 | ✅ | ✅ | ✅ |
| 候选翻页 | ✅ | ✅ | ✅ |
| Enter 英文上屏 | ✅ | ✅ | ✅ |
| 多种候选展示 | echo area / posframe | 5 种 | 3 种 |
| Predicates 自动切换 | ✅ (8 个内置) | ✅ (20 个) | ✅ (probe) |
| Inline ASCII | ❌ | ✅ | ❌ |
| 多输入方案后端 | ❌ | ❌ | ✅ |
| 词频学习 | rime 内置 | rime 内置 | rime + pyim |
| 自定义按键 | ✅ 全部可配 | 部分 | 部分 |
| 零额外 C 代码 | ✅ | ❌ | ✅ |
| 安装复杂度 | 低 | 中 | 高 |

### 如何选择？

- **想要最简单、最轻量的 rime 体验（含 predicates）** → Rimel
- **需要 inline ASCII、多种候选 UI（5 种）** → emacs-rime
- **需要多输入法后端（五笔+拼音+rime）统一管理** → pyim

## librimel 开发

librimel 是 Emacs 动态模块，提供了 librime 库绑定。

### 依赖

1. Emacs 需要启用动态模块支持（编译时使用 `--with-modules`）
2. librime 版本 > 1.3.2

### Linux 编译

```bash
export EMACS_MAJOR_VERSION=26  # 按实际情况更改
make
```

### Mac 编译

1. 安装 Xcode，参考：[[https://github.com/rime/librime/blob/master/README-mac.md]]
2. 设置环境变量 `RIME_PATH`：
   ```bash
   export RIME_PATH=~/Develop/others/librime
   ```
3. 编译：
   ```bash
   export EMACS_MAJOR_VERSION=26
   make
   ```

### Windows (msys2) 编译

```bash
pacman -Sy --overwrite "*" --needed base-devel zip \
       ${MINGW_PACKAGE_PREFIX}-gcc                 \
       ${MINGW_PACKAGE_PREFIX}-librime             \
       ${MINGW_PACKAGE_PREFIX}-librime-data        \
       ${MINGW_PACKAGE_PREFIX}-rime-wubi           \
       ${PACKAGE_PREFIX}-rime-emoji                \
       ${MINGW_PACKAGE_PREFIX}-rime-double-pinyin

# 链接 opencc 文件
ln -s ${MINGW_PREFIX}/share/opencc/* ${MINGW_PREFIX}/share/rime-data/opencc

export EMACS_MAJOR_VERSION=26
make
```

### 加载时自动编译

```elisp
(let ((librimel-auto-build t))
  (require 'librimel nil t))
```

### 部署 Rime

手动修改 librime 配置后，调用 `(librimel-deploy)` 重新部署。

### 同步 Rime 词库

1. 在 `$HOME/.emacs.d/rime/installation.yaml` 中设置 `sync_dir`
2. 添加到 `after-init-hook`：
   ```elisp
   (add-hook 'after-init-hook #'librimel-sync)
   ```

参考：[[https://github.com/rime/home/wiki/UserGuide#%E5%90%8C%E6%AD%A5%E7%94%A8%E6%88%B6%E8%B3%87%E6%96%99][Rime 同步用户资料]]

## License

GPL-3.0

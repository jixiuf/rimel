# Rimel — 基于 liberime 的轻量级 Emacs Rime 输入法

Rimel 是一个轻量级的 Emacs 中文输入法，直接基于 [liberime](https://github.com/merrickluo/liberime) 动态模块，
使用 Emacs 内置的 `input-method-function` 接口和 `read-event` 循环（与 quail 相同的模式）。

## 特性

- 📦 **单文件**：仅 `rimel.el` 一个文件，约 500 行
- 🔌 **依赖少**：仅依赖 liberime（无需额外 C 模块）
- 🏗️ **原生集成**：使用 Emacs 内置 `input-method-function` + `register-input-method`
- 📋 **Echo area 候选展示**：`[ni hao] 1.你好 2.你 3.拟 (1+)`
- ✏️ **光标处编码 overlay**：输入时在光标处显示 preedit
- 📄 **翻页**：支持 `]/[`、`=/−`、`./,`、`C-v/M-v`、`PgDn/PgUp` 等（完全可配置）
- ⏎ **Enter 英文上屏**：按 Enter 直接提交原始英文输入
- 🔢 **数字键/空格选候选**
- ⌨️ **所有按键可配置**：翻页、确认、取消、退格、选择键均可自定义

## 安装

### 前置条件

1. 安装 [librime](https://github.com/rime/librime)
2. melpa上安装 [liberime](https://github.com/merrickluo/liberime) 并确保可用

### 配置

```elisp
(add-to-list 'load-path "/path/to/rimel")
(add-to-list 'load-path "/path/to/liberime")
(require 'rimel)

;; 可选：指定输入方案
(setq rimel-schema "luna_pinyin_simp")
(setq default-input-method "rimel")
```

## 按键说明

| 按键 | 功能 | 配置变量 |
|------|------|----------|
| `a-z` | 输入拼音 | — |
| `1-9` | 选择对应候选 | `rimel-select-label-keys` |
| `Space` | 选择第一个候选 | `rimel-confirm-keys` |
| `Enter` | 英文上屏 / 首选上屏 | `rimel-commit-raw-keys` |
| `]/=/.`/`PgDn` | 下一页 | `rimel-page-down-keys` |
| `[/-/,`/`PgUp` | 上一页 | `rimel-page-up-keys` |
| `Backspace`/`C-h` | 删除最后一个字符 | `rimel-backspace-keys` |
| `Escape`/`C-g` | 取消输入 | `rimel-cancel-keys` |
| 其他键 | 退出输入法并执行原按键 | — |

## 配置变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `rimel-schema` | `nil` | Rime 方案 ID（如 `"luna_pinyin_simp"`），nil 用默认 |
| `rimel-return-behavior` | `'raw` | Enter 行为：`raw` 英文上屏、`preview` 首选上屏 |
| `rimel-page-down-keys` | `'(next ?\] ?= ?.)` | 下翻页键（支持 symbol 和 character） |
| `rimel-page-up-keys` | `'(prior ?\[ ?- ?,)` | 上翻页键 |
| `rimel-confirm-keys` | `'(?\s)` | 确认键 |
| `rimel-commit-raw-keys` | `'(return ?\r)` | 提交原始输入键 |
| `rimel-backspace-keys` | `'(backspace ?\C-? 127 ?\C-h)` | 退格键 |
| `rimel-cancel-keys` | `'(escape ?\C-g)` | 取消键 |
| `rimel-select-label-keys` | `'(?1 ... ?9)` | 候选选择键 |

### 按键配置示例

```elisp
;; 使用 C-v / M-v 翻页
(setq rimel-page-down-keys '(next ?\C-v ?\] ?=))
(setq rimel-page-up-keys '(prior ?\M-v ?\[ ?-))

;; 使用 C-n / C-p 翻页
(setq rimel-page-down-keys '(next ?\C-n))
(setq rimel-page-up-keys '(prior ?\C-p))

;; Enter 上屏首选候选而非英文
(setq rimel-return-behavior 'preview)
```

## 与 emacs-rime、pyim 的对比

### 架构对比

| | **Rimel** | **emacs-rime** | **pyim + pyim-liberime** |
|---|---|---|---|
| **依赖** | liberime | 自带 C 模块 (lib.c) | pyim 框架 + liberime |
| **代码量** | ~500 行 | ~1200 行 (rime.el) + C | ~6000 行 (pyim) + 326 行桥接 |
| **C 模块** | 无（复用 liberime） | 自带 lib.c | 无（复用 liberime） |
| **输入法接口** | `input-method-function` + `read-event` 循环 | `input-method-function` + minor mode | `input-method-function` + 独立框架 |
| **候选展示** | echo area | minibuffer/popup/posframe/sidewindow | posframe/popup/minibuffer |
| **按键处理** | `read-event` 循环（类似 quail） | `overriding-terminal-local-map` | 独立事件系统 |

### 设计哲学

**Rimel** — *极简主义*
- 一个文件、一个依赖、无 C 代码
- 使用 `read-event` 循环，与 Emacs 内置 quail 完全相同的模式
- 不借助 pre-command-hook/post-self-insert-hook 等hook
- 合成过程自包含：函数进入时开始，返回时结束，无状态泄露
- 适合想要**最简单可用**的 rime 输入法的用户

**emacs-rime** — *功能完备*
- 自带 C 动态模块（lib.c），独立于 liberime
- 支持 5 种候选展示方式（minibuffer/message/popup/posframe/sidewindow）
- 支持 predicates 系统（自动根据上下文切换中英文）
- 支持 inline ASCII 模式
- 使用 minor mode + `overriding-terminal-local-map` 处理合成期间按键
- 适合需要**深度定制和高级功能**的用户

**pyim + pyim-liberime** — *框架化*
- pyim 是完整的输入法框架，liberime 只是其中一个后端
- 支持多种输入方案（全拼、双拼、五笔等），rime 只是其一
- 有独立的词频管理、词库、云输入等功能
- pyim-liberime 仅 326 行，本质是 `liberime-search()` 的薄包装
- 适合需要**多输入法统一管理**的用户

### 功能对比

| 功能 | Rimel | emacs-rime | pyim |
|------|:-----:|:----------:|:----:|
| 基本中文输入 | ✅ | ✅ | ✅ |
| 候选翻页 | ✅ | ✅ | ✅ |
| Enter 英文上屏 | ✅ | ✅ | ✅ |
| 多种候选展示 | echo area | 5 种 | 3 种 |
| Predicates 自动切换 | ❌ | ✅ | ✅ (probe) |
| Inline ASCII | ❌ | ✅ | ❌ |
| 多输入方案后端 | ❌ | ❌ | ✅ |
| 词频学习 | rime 内置 | rime 内置 | rime + pyim |
| 自定义按键 | ✅ 全部可配 | 部分 | 部分 |
| 零额外 C 代码 | ✅ | ❌ | ✅ |
| 安装复杂度 | 低 | 中 | 高 |

### 如何选择？

- **想要最简单、最轻量的 rime 体验** → Rimel
- **需要 predicates、inline ASCII、多种候选 UI** → emacs-rime
- **需要多输入法后端（五笔+拼音+rime）统一管理** → pyim

## License

GPL-3.0

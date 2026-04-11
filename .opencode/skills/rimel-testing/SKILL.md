---
name: rimel-testing
description: Ensure rimel test coverage stays in sync with code changes. Covers Elisp ERT tests, C unit tests, integration tests, CI workflow, and the three-tier testing architecture.
---

## Project Testing Architecture

rimel is an Emacs input method backed by a C dynamic module (librime binding).
Tests are split into three tiers that run independently:

| Tier | File | What it tests | Needs librime? |
|------|------|---------------|----------------|
| Elisp unit | `test/rimel-test.el` | Pure Elisp logic with mocked C functions | No |
| C unit | `test/test_librimel.c` | Internal C helpers (`_copy_string`, linked list) | No |
| Integration | `test/librimel-test.el` | Real C module + librime end-to-end | Yes |

## Running Tests

```sh
make test              # Elisp unit tests (79 tests, mocked, fast)
make test-c            # C unit tests (standalone binary)
make test-integration  # Integration tests (needs librime + compiled .so)
make test-all          # Elisp unit + C unit
```

## When to Update Tests

After ANY code change, evaluate which test tiers are affected:

### Elisp changes (`rimel.el` or `librimel.el`)

1. **If you add/modify a pure function** (predicates, formatters, key parsing, display logic):
   - Add or update tests in `test/rimel-test.el`
   - Use `rimel-test--reset-mocks` before each test
   - Mock C functions via `rimel-test--mock-*` variables
   - Name tests `rimel-test-<descriptive-name>`

2. **If you add a new `declare-function` for a C module function**:
   - Add a corresponding mock in `test/rimel-test.el` (in the mock infrastructure section near the top)
   - Add the `declare-function` to BOTH `librimel.el` AND `rimel.el` if the function is used in `rimel.el`

3. **If you add a new defcustom**:
   - Add tests covering its default value behavior and edge cases
   - If it affects formatting, test through `rimel--format-candidates`

### C changes (`src/*.c`)

1. **If you add/modify internal helper functions** (`_copy_string`, linked list ops, etc.):
   - Add tests in `test/test_librimel.c`
   - Since helpers are `static`, copy the function signature into the test file
   - Use the `TEST(name)` / `ASSERT()` / `ASSERT_STR_EQ()` macros

2. **If you add a new DEFUN (new Emacs-facing C function)**:
   - Register it in `librimel_init()` in `src/librimel-core.c`
   - Add `declare-function` in `librimel.el`
   - Add a mock stub in `test/rimel-test.el` mock infrastructure
   - Add an integration test in `test/librimel-test.el`
   - If the function uses `_get_session()`, test with both default and explicit session

3. **If you change DEFUN naming** (the string passed to `DEFUN` macro):
   - Ensure the name matches the `declare-function` in Elisp
   - Convention: public API uses `librimel-<name>`, internal uses `librimel--<name>`

### CI changes (`.github/workflows/test.yml`)

Key constraints to remember:

- **byte-compile job**: Must `--eval "(provide 'librimel-core)"` BEFORE loading `librimel.el`, because `librimel-load` uses a local `load-path` that won't find external stubs
- **rimel.el byte-compile**: Every C function called in `rimel.el` needs a `declare-function` in that file, not just in `librimel.el`

## Mock Infrastructure Pattern

In `test/rimel-test.el`, C functions are mocked before `(require 'librimel)`:

```elisp
;; 1. Provide the feature so librimel-load doesn't try to dlopen
(provide 'librimel-core)

;; 2. Define mock return value variables
(defvar rimel-test--mock-context nil)

;; 3. Define stub functions
(unless (fboundp 'librimel-get-context)
  (defun librimel-get-context (&optional _session-id)
    rimel-test--mock-context))

;; 4. Load the real packages
(require 'librimel)
(require 'rimel)
```

## Integration Test Pattern

In `test/librimel-test.el`:

```elisp
;; Use ert-skip for graceful degradation when librime is unavailable
(defun librimel-test--skip-unless-rime ()
  (unless (featurep 'librimel-core)
    (ert-skip "librimel-core module not loaded"))
  (librimel-test--setup)
  (unless librimel-test--session-id
    (ert-skip "Cannot initialize librime")))

;; Always call at test start
(ert-deftest librimel-test-example ()
  (librimel-test--skip-unless-rime)
  ;; ... test body ...
  (librimel-clear-composition))  ; clean up composition state
```

## Test Entry Points

Both test files provide a `-run` function for CI:

- `rimel-test-run` — runs all `^rimel-test-` tests, exits with code
- `librimel-test-run` — runs all `^librimel-test-` tests with setup/teardown

## Checklist Before Finishing

- [ ] Run `make test` — all Elisp unit tests pass
- [ ] Run `make test-c` — all C unit tests pass  
- [ ] If C module was changed: run `make test-integration`
- [ ] If new C function added: mock exists in `test/rimel-test.el`, integration test in `test/librimel-test.el`
- [ ] If new Elisp function added: ERT test in `test/rimel-test.el`
- [ ] No byte-compile warnings: `emacs --batch -Q -L . --eval "(provide 'librimel-core)" --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile librimel.el rimel.el`

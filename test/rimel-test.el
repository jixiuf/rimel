;;; rimel-test.el --- Tests for rimel -*- lexical-binding: t; -*-

;; Copyright (C) 2024 jixiuf

;; Author: jixiuf

;;; Commentary:

;; ERT test suite for rimel.  Tests pure Elisp logic by mocking the
;; C dynamic module functions from librimel-core, so librime does NOT
;; need to be installed.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; ---------------------------------------------------------------------------
;; Mock infrastructure -- stub out every C function before loading rimel
;; ---------------------------------------------------------------------------

;; Prevent librimel.el from actually loading the C module
(provide 'librimel-core)

;; Stub all C functions that librimel.el / rimel.el declare
(defvar rimel-test--mock-context nil
  "Value returned by the mocked `librimel-get-context'.")
(defvar rimel-test--mock-commit nil
  "Value returned by the mocked `librimel-get-commit'.")
(defvar rimel-test--mock-input nil
  "Value returned by the mocked `librimel-get-input'.")
(defvar rimel-test--mock-status nil
  "Value returned by the mocked `librimel-get-status'.")
(defvar rimel-test--mock-schema-list nil
  "Value returned by the mocked `librimel-get-schema-list'.")
(defvar rimel-test--mock-process-key-result t
  "Value returned by the mocked `librimel-process-key'.")
(defvar rimel-test--mock-search-result nil
  "Value returned by the mocked `librimel-search'.")
(defvar rimel-test--processed-keys nil
  "List of keys passed to mocked `librimel-process-key', in reverse order.")
(defvar rimel-test--session-counter 1000
  "Counter for mock session IDs.")

(unless (fboundp 'librimel--start)
  (defun librimel--start (_shared _user) (cl-incf rimel-test--session-counter)))
(unless (fboundp 'librimel-finalize)
  (defun librimel-finalize () t))
(unless (fboundp 'librimel-create-session)
  (defun librimel-create-session () (cl-incf rimel-test--session-counter)))
(unless (fboundp 'librimel-destroy-session)
  (defun librimel-destroy-session (_id) t))
(unless (fboundp 'librimel-process-key)
  (defun librimel-process-key (keycode &optional _mask _session-id)
    (push keycode rimel-test--processed-keys)
    rimel-test--mock-process-key-result))
(unless (fboundp 'librimel-get-context)
  (defun librimel-get-context (&optional _session-id)
    rimel-test--mock-context))
(unless (fboundp 'librimel-get-commit)
  (defun librimel-get-commit (&optional _session-id)
    (prog1 rimel-test--mock-commit
      (setq rimel-test--mock-commit nil))))
(unless (fboundp 'librimel-get-input)
  (defun librimel-get-input (&optional _session-id)
    rimel-test--mock-input))
(unless (fboundp 'librimel-get-status)
  (defun librimel-get-status (&optional _session-id)
    rimel-test--mock-status))
(unless (fboundp 'librimel-clear-composition)
  (defun librimel-clear-composition (&optional _session-id) t))
(unless (fboundp 'librimel-commit-composition)
  (defun librimel-commit-composition (&optional _session-id) t))
(unless (fboundp 'librimel-select-candidate)
  (defun librimel-select-candidate (_num &optional _session-id) t))
(unless (fboundp 'librimel--select-schema)
  (defun librimel--select-schema (schema-id &optional _session-id)
    (not (null schema-id))))
(unless (fboundp 'librimel-get-schema-list)
  (defun librimel-get-schema-list ()
    rimel-test--mock-schema-list))
(unless (fboundp 'librimel-search)
  (defun librimel-search (_string &optional _limit _session-id)
    rimel-test--mock-search-result))
(unless (fboundp 'librimel-get-user-config)
  (defun librimel-get-user-config (_config _option &optional _type) nil))
(unless (fboundp 'librimel-set-user-config)
  (defun librimel-set-user-config (_config _option _value &optional _type) t))
(unless (fboundp 'librimel-get-schema-config)
  (defun librimel-get-schema-config (_config _option &optional _type _sid) nil))
(unless (fboundp 'librimel-set-schema-config)
  (defun librimel-set-schema-config (_config _option _value &optional _type _sid) t))
(unless (fboundp 'librimel-get-sync-dir)
  (defun librimel-get-sync-dir () "/tmp/rime-sync"))
(unless (fboundp 'librimel-sync-user-data)
  (defun librimel-sync-user-data () t))

;; Now load our packages (they will find the stubs)
(require 'librimel)
(require 'rimel)

;; ---------------------------------------------------------------------------
;; Helper to reset mock state
;; ---------------------------------------------------------------------------
(defun rimel-test--reset-mocks ()
  "Reset all mock variables to clean state."
  (setq rimel-test--mock-context nil
        rimel-test--mock-commit nil
        rimel-test--mock-input nil
        rimel-test--mock-status nil
        rimel-test--mock-schema-list nil
        rimel-test--mock-process-key-result t
        rimel-test--mock-search-result nil
        rimel-test--processed-keys nil
        rimel-test--session-counter 1000))

;; ---------------------------------------------------------------------------
;; Sample data builders
;; ---------------------------------------------------------------------------
(defun rimel-test--make-context (&optional preedit candidates
                                           highlighted page-no
                                           last-page-p page-size
                                           commit-text-preview)
  "Build a mock context alist."
  (let ((ctx `((commit-text-preview . ,(or commit-text-preview "preview"))
               (composition . ((length . ,(length (or preedit "")))
                               (cursor-pos . ,(length (or preedit "")))
                               (sel-start . 0)
                               (sel-end . ,(length (or preedit "")))
                               (preedit . ,(or preedit "test"))))
               (menu . ((highlighted-candidate-index . ,(or highlighted 0))
                        (last-page-p . ,(if last-page-p t nil))
                        (num-candidates . ,(length (or candidates '("a" "b"))))
                        (page-no . ,(or page-no 0))
                        (page-size . ,(or page-size 5))
                        (candidates . ,(or candidates '("a" "b"))))))))
    ctx))


;; ===========================================================================
;; Tests for rimel--composable-key-p
;; ===========================================================================

(ert-deftest rimel-test-composable-key-lowercase ()
  "Lowercase a-z should be composable."
  (dolist (ch (number-sequence ?a ?z))
    (should (rimel--composable-key-p ch))))

(ert-deftest rimel-test-composable-key-uppercase-not ()
  "Uppercase letters should NOT be composable."
  (dolist (ch (number-sequence ?A ?Z))
    (should-not (rimel--composable-key-p ch))))

(ert-deftest rimel-test-composable-key-digits-not ()
  "Digits should NOT be composable (they are label selection keys)."
  (dolist (ch (number-sequence ?0 ?9))
    (should-not (rimel--composable-key-p ch))))

(ert-deftest rimel-test-composable-key-punctuation ()
  "Chinese punctuation chars should be composable."
  (dolist (ch '(?, ?. ?/ ?< ?> ?? ?\; ?: ?\' ?\" ?\[ ?\] ?{ ?}
                   ?\\ ?| ?! ?@ ?# ?$ ?% ?^ ?& ?* ?\( ?\) ?- ?_ ?+ ?= ?` ?~))
    (should (rimel--composable-key-p ch))))

(ert-deftest rimel-test-composable-key-non-integer ()
  "Non-integer keys should not be composable."
  (should-not (rimel--composable-key-p 'return))
  (should-not (rimel--composable-key-p nil)))

;; ===========================================================================
;; Tests for rimel--event-in-p
;; ===========================================================================

(ert-deftest rimel-test-event-in-p ()
  "Test event membership in key lists."
  (should (rimel--event-in-p ?1 '(?1 ?2 ?3)))
  (should-not (rimel--event-in-p ?4 '(?1 ?2 ?3)))
  (should (rimel--event-in-p 'return '(return ?\r)))
  (should-not (rimel--event-in-p 'escape '(return ?\r))))

;; ===========================================================================
;; Tests for rimel--format-candidates
;; ===========================================================================

(ert-deftest rimel-test-format-candidates-basic ()
  "Basic candidate formatting."
  (let ((rimel-select-label-keys '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9))
        (rimel-highlight-first nil)
        (ctx (rimel-test--make-context "wo" '("wo" "our") 0 0 t)))
    (let ((result (rimel--format-candidates ctx)))
      (should (stringp result))
      (should (string-match "1\\.wo" result))
      (should (string-match "2\\.our" result))
      ;; Page indicator
      (should (string-match "(1)" result)))))

(ert-deftest rimel-test-format-candidates-with-preedit ()
  "Candidate formatting with preedit shown."
  (let ((rimel-select-label-keys '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9))
        (rimel-highlight-first nil)
        (ctx (rimel-test--make-context "wo" '("wo" "our") 0 0 t)))
    (let ((result (rimel--format-candidates ctx " " t)))
      (should (stringp result))
      (should (string-match "\\[wo\\]" result)))))

(ert-deftest rimel-test-format-candidates-not-last-page ()
  "Page indicator should show + when not last page."
  (let ((rimel-select-label-keys '(?1 ?2 ?3 ?4 ?5))
        (rimel-highlight-first nil)
        (ctx (rimel-test--make-context "test" '("a" "b" "c") 0 0 nil)))
    (let ((result (rimel--format-candidates ctx)))
      (should (string-match "(1\\+)" result)))))

(ert-deftest rimel-test-format-candidates-page-2 ()
  "Page indicator on page 2."
  (let ((rimel-select-label-keys '(?1 ?2 ?3 ?4 ?5))
        (rimel-highlight-first nil)
        (ctx (rimel-test--make-context "test" '("d" "e") 0 1 t)))
    (let ((result (rimel--format-candidates ctx)))
      (should (string-match "(2)" result)))))

(ert-deftest rimel-test-format-candidates-highlight-first ()
  "When rimel-highlight-first is non-nil, rotate candidates."
  (let ((rimel-select-label-keys '(?1 ?2 ?3 ?4 ?5))
        (rimel-highlight-first t)
        (ctx (rimel-test--make-context "test" '("a" "b" "c" "d") 2 0 t)))
    (let ((result (rimel--format-candidates ctx)))
      (should (stringp result))
      ;; "c" should appear first (highlighted idx=2 rotated to front)
      ;; The first label "1." should be followed by "c"
      (should (string-match "1\\.c" result)))))

(ert-deftest rimel-test-format-candidates-nil-context ()
  "Empty context should return nil."
  (should-not (rimel--format-candidates nil))
  (should-not (rimel--format-candidates '((menu . nil)))))

(ert-deftest rimel-test-format-candidates-with-separator ()
  "Custom separator."
  (let ((rimel-select-label-keys '(?1 ?2 ?3))
        (rimel-highlight-first nil)
        (ctx (rimel-test--make-context "wo" '("a" "b") 0 0 t)))
    (let ((result (rimel--format-candidates ctx "\n")))
      (should (string-match "\n" result)))))

(ert-deftest rimel-test-format-candidates-with-comment ()
  "Candidates with :comment text property."
  (let ((rimel-select-label-keys '(?1 ?2))
        (rimel-highlight-first nil)
        (cand1 (propertize "wang" :comment "adj"))
        (ctx (rimel-test--make-context "w" nil 0 0 t)))
    ;; Override candidates
    (setf (alist-get 'candidates (alist-get 'menu ctx)) (list cand1 "wu"))
    (setf (alist-get 'num-candidates (alist-get 'menu ctx)) 2)
    (let ((result (rimel--format-candidates ctx)))
      (should (string-match "wang(adj)" result)))))

;; ===========================================================================
;; Tests for rimel--should-enable-p / predicates
;; ===========================================================================

(ert-deftest rimel-test-should-enable-no-predicates ()
  "With no predicates, input should always be enabled."
  (let ((rimel-disable-predicates nil))
    (should (rimel--should-enable-p))))

(ert-deftest rimel-test-should-enable-predicate-returns-nil ()
  "When all predicates return nil, input is enabled."
  (let ((rimel-disable-predicates (list (lambda () nil) (lambda () nil))))
    (should (rimel--should-enable-p))))

(ert-deftest rimel-test-should-enable-predicate-disables ()
  "When any predicate returns non-nil, input is disabled."
  (let ((rimel-disable-predicates (list (lambda () nil) (lambda () t))))
    (should-not (rimel--should-enable-p))))

;; ===========================================================================
;; Tests for rimel-predicate-current-uppercase-letter-p
;; ===========================================================================

(ert-deftest rimel-test-predicate-uppercase ()
  "Uppercase key should trigger predicate."
  (let ((rimel--current-input-key ?A))
    (should (rimel-predicate-current-uppercase-letter-p)))
  (let ((rimel--current-input-key ?Z))
    (should (rimel-predicate-current-uppercase-letter-p))))

(ert-deftest rimel-test-predicate-lowercase-not-uppercase ()
  "Lowercase key should not trigger uppercase predicate."
  (let ((rimel--current-input-key ?a))
    (should-not (rimel-predicate-current-uppercase-letter-p)))
  (let ((rimel--current-input-key nil))
    (should-not (rimel-predicate-current-uppercase-letter-p))))

;; ===========================================================================
;; Tests for rimel-predicate-after-alphabet-char-p
;; ===========================================================================

(ert-deftest rimel-test-predicate-after-alphabet ()
  "After a Latin letter the predicate should trigger."
  (with-temp-buffer
    (insert "hello")
    (should (rimel-predicate-after-alphabet-char-p))))

(ert-deftest rimel-test-predicate-after-digit-not-alphabet ()
  "After a digit, the alphabet predicate should NOT trigger."
  (with-temp-buffer
    (insert "hello123")
    (should-not (rimel-predicate-after-alphabet-char-p))))

(ert-deftest rimel-test-predicate-after-alphabet-at-bob ()
  "At beginning of buffer, predicate should not trigger."
  (with-temp-buffer
    (should-not (rimel-predicate-after-alphabet-char-p))))

;; ===========================================================================
;; Tests for rimel-predicate-after-ascii-char-p
;; ===========================================================================

(ert-deftest rimel-test-predicate-after-ascii ()
  "After any printable ASCII char the predicate should trigger."
  (with-temp-buffer
    (insert "hello123!")
    (should (rimel-predicate-after-ascii-char-p))))

(ert-deftest rimel-test-predicate-after-space-not-ascii ()
  "Space (0x20) is below #x21, should not trigger."
  (with-temp-buffer
    (insert " ")
    (should-not (rimel-predicate-after-ascii-char-p))))

(ert-deftest rimel-test-predicate-after-chinese-not-ascii ()
  "After a Chinese character, predicate should not trigger."
  (with-temp-buffer
    (insert "你好")
    (should-not (rimel-predicate-after-ascii-char-p))))

;; ===========================================================================
;; Tests for rimel-predicate-prog-in-code-p
;; ===========================================================================

(ert-deftest rimel-test-predicate-prog-in-code ()
  "In code area of prog-mode, should return non-nil."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun foo ()")
    (should (rimel-predicate-prog-in-code-p))))

(ert-deftest rimel-test-predicate-prog-in-string ()
  "In a string within prog-mode, should return nil."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(defun foo () \"inside string")
    (syntax-ppss-flush-cache (point-min))
    (should-not (rimel-predicate-prog-in-code-p))))

(ert-deftest rimel-test-predicate-prog-in-comment ()
  "In a comment within prog-mode, should return nil."
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert ";; this is a comment")
    (syntax-ppss-flush-cache (point-min))
    (should-not (rimel-predicate-prog-in-code-p))))

(ert-deftest rimel-test-predicate-prog-in-text-mode ()
  "In text-mode (not prog-mode), should return nil."
  (with-temp-buffer
    (text-mode)
    (insert "hello")
    (should-not (rimel-predicate-prog-in-code-p))))

;; ===========================================================================
;; Tests for rimel--feed-key-string (key parsing)
;; ===========================================================================

(ert-deftest rimel-test-feed-key-string-hex ()
  "Hex keycodes should be parsed correctly."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "0xFF52")
  (should (equal (car rimel-test--processed-keys) #xff52)))

(ert-deftest rimel-test-feed-key-string-single-char ()
  "Single character keycode."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "a")
  (should (equal (car rimel-test--processed-keys) ?a)))

(ert-deftest rimel-test-feed-key-string-symbol-left ()
  "Symbol <left> should map to XK_Left."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<left>")
  (should (equal (car rimel-test--processed-keys) #xff51)))

(ert-deftest rimel-test-feed-key-string-symbol-right ()
  "<right> should map to XK_Right."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<right>")
  (should (equal (car rimel-test--processed-keys) #xff53)))

(ert-deftest rimel-test-feed-key-string-symbol-up ()
  "<up> should map to XK_Up."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<up>")
  (should (equal (car rimel-test--processed-keys) #xff52)))

(ert-deftest rimel-test-feed-key-string-symbol-down ()
  "<down> should map to XK_Down."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<down>")
  (should (equal (car rimel-test--processed-keys) #xff54)))

(ert-deftest rimel-test-feed-key-string-symbol-return ()
  "<return> should map to XK_Return."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<return>")
  (should (equal (car rimel-test--processed-keys) #xff0d)))

(ert-deftest rimel-test-feed-key-string-symbol-backspace ()
  "<backspace> should map to XK_BackSpace."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<backspace>")
  (should (equal (car rimel-test--processed-keys) #xff08)))

(ert-deftest rimel-test-feed-key-string-symbol-space ()
  "<space> should map to 0x0020."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<space>")
  (should (equal (car rimel-test--processed-keys) #x0020)))

(ert-deftest rimel-test-feed-key-string-symbol-tab ()
  "<tab> should map to XK_Tab."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<tab>")
  (should (equal (car rimel-test--processed-keys) #xff09)))

(ert-deftest rimel-test-feed-key-string-symbol-escape ()
  "<escape> should map to XK_Escape."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<escape>")
  (should (equal (car rimel-test--processed-keys) #xff1b)))

(ert-deftest rimel-test-feed-key-string-symbol-home ()
  "<home> should map to XK_Home."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<home>")
  (should (equal (car rimel-test--processed-keys) #xff50)))

(ert-deftest rimel-test-feed-key-string-symbol-end ()
  "<end> should map to XK_End."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<end>")
  (should (equal (car rimel-test--processed-keys) #xff57)))

(ert-deftest rimel-test-feed-key-string-symbol-delete ()
  "<delete> should map to XK_Delete."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<delete>")
  (should (equal (car rimel-test--processed-keys) #xffff)))

(ert-deftest rimel-test-feed-key-string-symbol-pageup ()
  "<pageup> should map to XK_Prior."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<pageup>")
  (should (equal (car rimel-test--processed-keys) #xff55)))

(ert-deftest rimel-test-feed-key-string-symbol-pagedown ()
  "<pagedown> should map to XK_Next."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string "<pagedown>")
  (should (equal (car rimel-test--processed-keys) #xff56)))

(ert-deftest rimel-test-feed-key-string-list ()
  "List of keycodes should all be fed."
  (rimel-test--reset-mocks)
  (rimel--feed-key-string '("<left>" "<right>"))
  (should (= (length rimel-test--processed-keys) 2))
  ;; Reverse order because we push
  (should (equal (nth 0 rimel-test--processed-keys) #xff53))  ; right (last pushed)
  (should (equal (nth 1 rimel-test--processed-keys) #xff51))) ; left (first pushed)

(ert-deftest rimel-test-feed-key-string-unknown-symbol ()
  "Unknown symbol should signal error."
  (rimel-test--reset-mocks)
  (should-error (rimel--feed-key-string "<nonexistent>")))

;; ===========================================================================
;; Tests for rimel--get-commit
;; ===========================================================================

(ert-deftest rimel-test-get-commit-nil ()
  "When no commit, should return nil."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-commit nil)
  (should-not (rimel--get-commit)))

(ert-deftest rimel-test-get-commit-empty ()
  "Empty string commit should return nil."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-commit "")
  (should-not (rimel--get-commit)))

(ert-deftest rimel-test-get-commit-value ()
  "Non-empty commit should be returned."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-commit "hello")
  (should (equal (rimel--get-commit) "hello")))

;; ===========================================================================
;; Tests for rimel--commit-raw
;; ===========================================================================

(ert-deftest rimel-test-commit-raw-mode-raw ()
  "With raw behavior, should return input."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-input "nihao")
  (let ((rimel-return-behavior 'raw))
    (should (equal (rimel--commit-raw) "nihao"))))

(ert-deftest rimel-test-commit-raw-mode-preview ()
  "With preview behavior, should return commit-text-preview."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-context
        (rimel-test--make-context "nihao" '("a") 0 0 t 5 "first"))
  (let ((rimel-return-behavior 'preview))
    (should (equal (rimel--commit-raw) "first"))))

(ert-deftest rimel-test-commit-raw-nil-input ()
  "With no input, should return empty string."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-input nil)
  (let ((rimel-return-behavior 'raw))
    (should (equal (rimel--commit-raw) ""))))

;; ===========================================================================
;; Tests for rimel--show-preedit / rimel--clear-preedit
;; ===========================================================================

(ert-deftest rimel-test-show-preedit-creates-overlay ()
  "Showing preedit should create an overlay."
  (with-temp-buffer
    (insert "hello")
    (goto-char (point-max))
    (rimel--show-preedit "test")
    (should rimel--preedit-overlay)
    (should (overlayp rimel--preedit-overlay))
    (should (string-equal (overlay-get rimel--preedit-overlay 'after-string)
                          ;; The after-string has the face applied
                          "test"))
    ;; Verify the text property
    (let ((str (overlay-get rimel--preedit-overlay 'after-string)))
      (should (eq (get-text-property 0 'face str) 'rimel-preedit-face)))
    (rimel--clear-preedit)
    (should-not rimel--preedit-overlay)))

(ert-deftest rimel-test-show-preedit-nil ()
  "Nil preedit should not create overlay."
  (with-temp-buffer
    (rimel--show-preedit nil)
    (should-not rimel--preedit-overlay)))

(ert-deftest rimel-test-show-preedit-empty ()
  "Empty string preedit should not create overlay."
  (with-temp-buffer
    (rimel--show-preedit "")
    (should-not rimel--preedit-overlay)))

(ert-deftest rimel-test-clear-preedit-when-none ()
  "Clearing when no overlay should not error."
  (let ((rimel--preedit-overlay nil))
    (rimel--clear-preedit)
    (should-not rimel--preedit-overlay)))

;; ===========================================================================
;; Tests for rimel--clear-state
;; ===========================================================================

(ert-deftest rimel-test-clear-state ()
  "rimel--clear-state should clean up everything."
  (with-temp-buffer
    (insert "test")
    (rimel--show-preedit "preedit")
    (should rimel--preedit-overlay)
    (rimel--clear-state)
    (should-not rimel--preedit-overlay)))

;; ===========================================================================
;; Tests for librimel.el utility functions
;; ===========================================================================

(ert-deftest rimel-test-librimel-get-preedit ()
  "librimel-get-preedit should extract preedit from context."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-context
        (rimel-test--make-context "hello" '("a") 0 0 t))
  (should (equal (librimel-get-preedit) "hello")))

(ert-deftest rimel-test-librimel-get-preedit-nil ()
  "librimel-get-preedit with nil context."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-context nil)
  (should-not (librimel-get-preedit)))

(ert-deftest rimel-test-librimel-get-page-size ()
  "librimel-get-page-size should extract page-size from context."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-context
        (rimel-test--make-context "test" '("a" "b") 0 0 t 7))
  (should (equal (librimel-get-page-size) 7)))

(ert-deftest rimel-test-librimel-current-schema-id ()
  "librimel-current-schema-id should return schema_id from status."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-status '((schema_id . "luna_pinyin_simp")
                                  (schema_name . "pinyin")))
  (should (equal (librimel-current-schema-id) "luna_pinyin_simp")))

(ert-deftest rimel-test-librimel-current-schema-id-nil ()
  "librimel-current-schema-id with nil status."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-status nil)
  (should-not (librimel-current-schema-id)))

(ert-deftest rimel-test-librimel-select-schema ()
  "librimel-select-schema should call C function."
  (should (librimel-select-schema "luna_pinyin_simp")))

(ert-deftest rimel-test-librimel-clear-commit ()
  "librimel-clear-commit should consume the commit."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-commit "hello")
  (librimel-clear-commit)
  ;; After clearing, get-commit should return nil
  (should-not (librimel-get-commit)))

;; ===========================================================================
;; Tests for librimel--find-rime-data
;; ===========================================================================

(ert-deftest rimel-test-find-rime-data-not-found ()
  "Should return nil when no rime data directory exists."
  (should-not (librimel--find-rime-data '("/nonexistent/path"))))

(ert-deftest rimel-test-find-rime-data-found ()
  "Should find existing directory."
  (let ((dir (make-temp-file "rimel-test-rime-data" t)))
    (unwind-protect
        (should (equal (librimel--find-rime-data
                        (list (file-name-directory dir))
                        (list (file-name-nondirectory dir)))
                       dir))
      (delete-directory dir))))

;; ===========================================================================
;; Tests for rimel-input-method (high-level flow)
;; ===========================================================================

(ert-deftest rimel-test-input-method-non-composable ()
  "Non-composable key should pass through."
  (rimel-test--reset-mocks)
  (let ((rimel-disable-predicates nil))
    (should (equal (rimel-input-method ?A) '(?A)))))

(ert-deftest rimel-test-input-method-read-only ()
  "In read-only buffer, key should pass through."
  (rimel-test--reset-mocks)
  (with-temp-buffer
    (setq buffer-read-only t)
    (let ((rimel-disable-predicates nil)
          (input-method-function nil))
      (should (equal (rimel-input-method ?a) '(?a))))))

(ert-deftest rimel-test-input-method-disabled-by-predicate ()
  "When predicate disables input, key should pass through."
  (rimel-test--reset-mocks)
  (let ((rimel-disable-predicates (list (lambda () t))))
    (should (equal (rimel-input-method ?a) '(?a)))))

(ert-deftest rimel-test-input-method-immediate-commit ()
  "When rime immediately commits (auto-select), return committed text."
  (rimel-test--reset-mocks)
  (setq rimel-test--mock-commit "auto")
  (let ((rimel-disable-predicates nil)
        (rimel--session-id 1))
    (should (equal (rimel-input-method ?a) '(?a ?u ?t ?o)))))

;; ===========================================================================
;; Tests for rimel-activate / rimel-deactivate
;; ===========================================================================

(ert-deftest rimel-test-activate-deactivate ()
  "Activate should set input-method-function, deactivate should clear it."
  (rimel-test--reset-mocks)
  (with-temp-buffer
    (let ((rimel--session-id 1001))
      (rimel-activate "rimel")
      (should (eq input-method-function #'rimel-input-method))
      (should (eq deactivate-current-input-method-function #'rimel-deactivate))
      (rimel-deactivate)
      (should-not (local-variable-p 'input-method-function)))))

;; ===========================================================================
;; Tests for rimel-predicate-org-in-src-block-p (without org loaded)
;; ===========================================================================

(ert-deftest rimel-test-predicate-org-src-block-not-org-mode ()
  "Outside org-mode, should return nil."
  (with-temp-buffer
    (emacs-lisp-mode)
    (should-not (rimel-predicate-org-in-src-block-p))))

;; ===========================================================================
;; Tests for rimel-predicate-tex-math-or-command-p
;; ===========================================================================

(ert-deftest rimel-test-predicate-tex-not-tex-mode ()
  "Outside tex-mode, should return nil."
  (with-temp-buffer
    (text-mode)
    (should-not (rimel-predicate-tex-math-or-command-p))))

;; ===========================================================================
;; Tests for display backends
;; ===========================================================================

(ert-deftest rimel-test-echo-area-show ()
  "Echo area display should call message."
  (rimel-test--reset-mocks)
  (let ((rimel-inline-preedit 'candidate)
        (rimel-select-label-keys '(?1 ?2 ?3 ?4 ?5))
        (rimel-highlight-first nil)
        (ctx (rimel-test--make-context "wo" '("wo" "our") 0 0 t)))
    ;; Just make sure it doesn't error
    (rimel--echo-area-show ctx)))

(ert-deftest rimel-test-show-candidates-echo-area ()
  "rimel--show-candidates should dispatch to echo area."
  (rimel-test--reset-mocks)
  (let ((rimel-show-candidate 'echo-area)
        (rimel-inline-preedit nil)
        (rimel-select-label-keys '(?1 ?2 ?3))
        (rimel-highlight-first nil)
        (ctx (rimel-test--make-context "wo" '("a") 0 0 t)))
    (rimel--show-candidates ctx)))

(ert-deftest rimel-test-hide-candidates-echo-area ()
  "rimel--hide-candidates in echo-area mode should not error."
  (let ((rimel-show-candidate 'echo-area))
    (rimel--hide-candidates)))

;; ===========================================================================
;; Tests for register-input-method
;; ===========================================================================

(ert-deftest rimel-test-input-method-registered ()
  "The 'rimel' input method should be registered."
  (should (assoc "rimel" input-method-alist)))

;; ===========================================================================
;; Tests for librimel--finalize-on-exit
;; ===========================================================================

(ert-deftest rimel-test-finalize-on-exit-hook ()
  "librimel--finalize-on-exit should be on kill-emacs-hook."
  (should (memq #'librimel--finalize-on-exit kill-emacs-hook)))

;; ===========================================================================
;; Entry point for CI
;; ===========================================================================

(defun rimel-test-run ()
  "Run all rimel tests and exit with appropriate code."
  (setq load-prefer-newer t)
  (let ((stats (ert-run-tests-batch "^rimel-test-")))
    (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1))))

(provide 'rimel-test)

;;; rimel-test.el ends here

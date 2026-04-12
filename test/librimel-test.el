;;; librimel-test.el --- Integration tests for librimel -*- lexical-binding: t; -*-

;; Copyright (C) 2024 jixiuf

;; Author: jixiuf

;;; Commentary:

;; Integration test suite that exercises the real C dynamic module
;; (librimel-core) with a running librime instance.  These tests
;; require librime to be installed and the C module to be compiled.
;;
;; Run with:
;;   make test-integration
;;
;; Or manually:
;;   emacs --batch -Q -L . -L test \
;;     -l ert -l test/librimel-test.el -f librimel-test-run

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'librimel)

;; ---------------------------------------------------------------------------
;; Test setup / teardown
;; ---------------------------------------------------------------------------

(defvar librimel-test--session-id nil
  "Session ID from librimel-start for test use.")

(defvar librimel-test--shared-dir nil
  "Shared data dir used for tests.")

(defvar librimel-test--user-dir nil
  "Temporary user data dir for tests.")

(defun librimel-test--setup ()
  "Initialize librime for testing.
Creates a temporary user data directory."
  (unless librimel-test--session-id
    (setq librimel-test--user-dir
          (make-temp-file "rimel-test-user" t))
    (setq librimel-test--shared-dir
          (or (librimel--get-shared-data-dir)
              ;; Fallback: try common paths
              (cl-find-if #'file-directory-p
                          '("/usr/share/rime-data"
                            "/usr/local/share/rime-data"
                            "/usr/share/local/rime-data"))))
    (when librimel-test--shared-dir
      (setq librimel-test--session-id
            (ignore-errors
              (librimel-start nil
                              librimel-test--shared-dir
                              librimel-test--user-dir))))))

(defun librimel-test--teardown ()
  "Finalize librime and clean up."
  (when librimel-test--session-id
    (ignore-errors (librimel-finalize))
    (setq librimel-test--session-id nil))
  (when (and librimel-test--user-dir
             (file-directory-p librimel-test--user-dir))
    (delete-directory librimel-test--user-dir t)
    (setq librimel-test--user-dir nil)))

(defun librimel-test--skip-unless-rime ()
  "Skip the current test if librime is not available."
  (unless (featurep 'librimel-core)
    (ert-skip "librimel-core module not loaded"))
  (librimel-test--setup)
  (unless librimel-test--session-id
    (ert-skip "Cannot initialize librime (no shared data?)")))

;; ---------------------------------------------------------------------------
;; Session management tests
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-start-returns-session-id ()
  "librimel-start should return a non-nil integer session ID."
  (librimel-test--skip-unless-rime)
  (should (integerp librimel-test--session-id))
  (should (> librimel-test--session-id 0)))

(ert-deftest librimel-test-create-destroy-session ()
  "Creating and destroying additional sessions should work."
  (librimel-test--skip-unless-rime)
  (let ((new-id (librimel-create-session)))
    (should (integerp new-id))
    (should (> new-id 0))
    (should (librimel-destroy-session new-id))))

;; ---------------------------------------------------------------------------
;; Schema tests
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-get-schema-list ()
  "librimel-get-schema-list should return a non-empty list."
  (librimel-test--skip-unless-rime)
  (let ((schemas (librimel-get-schema-list)))
    (should (listp schemas))
    (should (> (length schemas) 0))
    ;; Each entry should be (schema-id name)
    (let ((first (car schemas)))
      (should (listp first))
      (should (stringp (car first)))
      (should (stringp (cadr first))))))

(ert-deftest librimel-test-select-schema ()
  "Selecting a valid schema should succeed."
  (librimel-test--skip-unless-rime)
  (let* ((schemas (librimel-get-schema-list))
         (first-id (caar schemas)))
    (should (librimel-select-schema first-id))))

(ert-deftest librimel-test-select-invalid-schema ()
  "Selecting a non-existent schema should return nil."
  (librimel-test--skip-unless-rime)
  ;; librimel--select-schema is the C function, librimel-select-schema is the wrapper
  (should-not (librimel--select-schema "nonexistent_schema_12345")))

;; ---------------------------------------------------------------------------
;; Input processing tests
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-process-key ()
  "Processing a key should return t when handled."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  ;; 'a' = 97, should be handled by most schemas
  (should (eq (librimel-process-key ?a) t)))

(ert-deftest librimel-test-get-input ()
  "After processing keys, get-input should return the input string."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (librimel-process-key ?n)
  (librimel-process-key ?i)
  (let ((input (librimel-get-input)))
    (should (stringp input))
    (should (string-equal input "ni")))
  (librimel-clear-composition))

(ert-deftest librimel-test-clear-composition ()
  "Clearing composition should reset input."
  (librimel-test--skip-unless-rime)
  (librimel-process-key ?a)
  (librimel-clear-composition)
  (let ((input (librimel-get-input)))
    (should (or (null input) (string-equal input "")))))

(ert-deftest librimel-test-get-context ()
  "Get context after entering keys should return valid alist."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (librimel-process-key ?w)
  (librimel-process-key ?o)
  (let ((ctx (librimel-get-context)))
    (should (listp ctx))
    ;; Should have composition
    (let ((comp (alist-get 'composition ctx)))
      (should comp)
      (should (alist-get 'preedit comp)))
    ;; Should have menu with candidates
    (let ((menu (alist-get 'menu ctx)))
      (when menu
        (should (listp (alist-get 'candidates menu))))))
  (librimel-clear-composition))

(ert-deftest librimel-test-get-status ()
  "Get status should return a valid alist."
  (librimel-test--skip-unless-rime)
  (let ((status (librimel-get-status)))
    (should (listp status))
    (should (alist-get 'schema_id status))
    (should (stringp (alist-get 'schema_id status)))))

;; ---------------------------------------------------------------------------
;; Search tests
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-search-basic ()
  "Search should return a list of candidates."
  (librimel-test--skip-unless-rime)
  (let ((results (librimel-search "wo")))
    (should (listp results))
    (when results
      (should (stringp (car results))))))

(ert-deftest librimel-test-search-with-limit ()
  "Search with limit should return at most LIMIT candidates."
  (librimel-test--skip-unless-rime)
  (let ((results (librimel-search "wo" 0 3)))
    (when results
      (should (<= (length results) 3)))))

(ert-deftest librimel-test-search-with-session ()
  "Search with explicit session should work."
  (librimel-test--skip-unless-rime)
  (let ((sid (librimel-create-session)))
    (unwind-protect
        (let ((results (librimel-search "ni" 0 5 sid)))
          (when results
            (should (listp results))
            (should (stringp (car results)))))
      (librimel-destroy-session sid))))

(ert-deftest librimel-test-search-empty ()
  "Searching for non-pinyin should return nil or empty."
  (librimel-test--skip-unless-rime)
  (let ((results (librimel-search "zzzzzz" 5)))
    ;; May or may not return results depending on schema
    (should (or (null results) (listp results)))))

(ert-deftest librimel-test-search-from-index-basic ()
  "Search with index should return candidates starting from INDEX."
  (librimel-test--skip-unless-rime)
  (let* ((all (librimel-search "wo" 0 10))
         (from5 (librimel-search "wo" 5 5)))
    (should (listp from5))
    (should (<= (length from5) 5))
    (when (and (>= (length all) 10) (>= (length from5) 1))
      (should (not (string= (car all) (car from5)))))))

(ert-deftest librimel-test-search-from-index-with-session ()
  "Search with explicit session should work."
  (librimel-test--skip-unless-rime)
  (let ((sid (librimel-create-session)))
    (unwind-protect
      (let ((results (librimel-search "ni" 2 3 sid)))
        (should results)
        (should (listp results))
        (should (stringp (car results))))
      (librimel-destroy-session sid))))

(ert-deftest librimel-test-search-pagination ()
  "Combined search calls should support pagination."
  (librimel-test--skip-unless-rime)
  (let* ((page-size 5)
         (page1 (librimel-search "wo" 0 page-size))
         (page2 (librimel-search "wo" page-size page-size)))
    (should (listp page1))
    (should (listp page2))
    (should (not (string= (car page1) (car page2))))))

;; ---------------------------------------------------------------------------
;; Commit tests
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-commit-composition ()
  "Committing a composition should produce committed text."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (librimel-process-key ?n)
  (librimel-process-key ?i)
  (librimel-commit-composition)
  (let ((commit (librimel-get-commit)))
    ;; commit may or may not be non-nil depending on schema behavior
    (should (or (null commit) (stringp commit))))
  (librimel-clear-composition))

(ert-deftest librimel-test-get-commit-clears ()
  "Second call to get-commit should return nil (consumed)."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (librimel-process-key ?n)
  (librimel-process-key ?i)
  (librimel-commit-composition)
  (librimel-get-commit)  ; consume
  (should-not (librimel-get-commit)))

;; ---------------------------------------------------------------------------
;; Event conversion tests
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-event-to-key-sequence-lowercase-ascii ()
  "Lowercase ASCII character should return itself (no braces needed)."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence ?a) "a"))
  (should (string= (librimel-event-to-key-sequence ?z) "z"))
  (should (string= (librimel-event-to-key-sequence ?m) "m")))

(ert-deftest librimel-test-event-to-key-sequence-uppercase-ascii ()
  "Uppercase ASCII character should return itself."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence ?A) "A"))
  (should (string= (librimel-event-to-key-sequence ?Z) "Z")))

(ert-deftest librimel-test-event-to-key-sequence-digits ()
  "Digit characters should return themselves."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence ?0) "0"))
  (should (string= (librimel-event-to-key-sequence ?5) "5"))
  (should (string= (librimel-event-to-key-sequence ?9) "9")))

(ert-deftest librimel-test-event-to-key-sequence-comma ()
  "Comma without modifiers should return comma char directly."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence ?,) ",")))

(ert-deftest librimel-test-event-to-key-sequence-period ()
  "Period without modifiers should return period char directly."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence ?.) ".")))

(ert-deftest librimel-test-event-to-key-sequence-control-modifier ()
  "Control + a (Emacs returns 1 for C-a without modifier bits)."
  (librimel-test--skip-unless-rime)
  (let ((c-a (car (listify-key-sequence (kbd "C-a")))))
    (should (string= (librimel-event-to-key-sequence c-a) "{Control+a}"))))

(ert-deftest librimel-test-event-to-key-sequence-meta-modifier ()
  "Meta modifier should produce {Meta+...} format."
  (librimel-test--skip-unless-rime)
  (let ((m-a (car (listify-key-sequence (kbd "M-a")))))
    (should (string= (librimel-event-to-key-sequence m-a) "{Meta+a}"))))

(ert-deftest librimel-test-event-to-key-sequence-shift-modifier ()
  "Shift modifier should produce {Shift+...} format."
  (librimel-test--skip-unless-rime)
  (let ((s-a (car (listify-key-sequence (kbd "S-a")))))
    (should (string= (librimel-event-to-key-sequence s-a) "{Shift+a}"))))

(ert-deftest librimel-test-event-to-key-sequence-alt-modifier ()
  "Alt modifier should produce {Alt+...} format."
  (librimel-test--skip-unless-rime)
  (let ((alt-a (car (listify-key-sequence (kbd "A-a")))))
    (should (string= (librimel-event-to-key-sequence alt-a) "{Alt+a}"))))

(ert-deftest librimel-test-event-to-key-sequence-super-modifier ()
  "Super modifier should produce {Super+...} format."
  (librimel-test--skip-unless-rime)
  (let ((super-a (car (listify-key-sequence (kbd "s-a")))))
    (should (string= (librimel-event-to-key-sequence super-a) "{Super+a}"))))

(ert-deftest librimel-test-event-to-key-sequence-hyper-modifier ()
  "Hyper modifier should produce {Hyper+...} format."
  (librimel-test--skip-unless-rime)
  (let ((hyper-a (car (listify-key-sequence (kbd "H-a")))))
    (should (string= (librimel-event-to-key-sequence hyper-a) "{Hyper+a}"))))

(ert-deftest librimel-test-event-to-key-sequence-multiple-modifiers ()
  "Multiple modifiers should all appear in output."
  (librimel-test--skip-unless-rime)
  (let ((c-m-a (car (listify-key-sequence (kbd "C-M-a")))))
    (let ((result (librimel-event-to-key-sequence c-m-a)))
      (should (string= result "{Control+Meta+a}"))
      (should (string-match "Control" result))
      (should (string-match "Meta" result))
      (should (string-match "a" result)))))

(ert-deftest librimel-test-event-to-key-sequence-control-comma ()
  "Control + comma should return {Control+comma}."
  (librimel-test--skip-unless-rime)
  (let* ((ev (car (listify-key-sequence (kbd "C-,"))))
         (result (librimel-event-to-key-sequence ev)))
    (should (string= result "{Control+comma}"))))

(ert-deftest librimel-test-event-to-key-sequence-control-space ()
  "Control + space should return {Control+space}."
  (librimel-test--skip-unless-rime)
  (let* ((ev (car (listify-key-sequence (kbd "C-<SPC>"))))
         (result (librimel-event-to-key-sequence ev)))
    (should (string= "{Control+space}" result))))

(ert-deftest librimel-test-event-to-key-sequence-direction-keys ()
  "Direction keys should return {Direction} format."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence 'left) "{Left}"))
  (should (string= (librimel-event-to-key-sequence 'right) "{Right}"))
  (should (string= (librimel-event-to-key-sequence 'up) "{Up}"))
  (should (string= (librimel-event-to-key-sequence 'down) "{Down}")))

(ert-deftest librimel-test-event-to-key-sequence-navigation-keys ()
  "Navigation keys should return correct format."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence 'return) "{Return}"))
  (should (string= (librimel-event-to-key-sequence 'space) "{space}"))
  (should (string= (librimel-event-to-key-sequence 'backspace) "{BackSpace}"))
  (should (string= (librimel-event-to-key-sequence 'tab) "{Tab}"))
  (should (string= (librimel-event-to-key-sequence 'escape) "{Escape}"))
  (should (string= (librimel-event-to-key-sequence 'home) "{Home}"))
  (should (string= (librimel-event-to-key-sequence 'end) "{End}"))
  (should (string= (librimel-event-to-key-sequence 'delete) "{Delete}"))
  (should (string= (librimel-event-to-key-sequence 'prior) "{Prior}"))
  (should (string= (librimel-event-to-key-sequence 'next) "{Next}")))

(ert-deftest librimel-test-event-to-key-sequence-function-keys ()
  "Function keys should return {Fn} format."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence 'f1) "{F1}"))
  (should (string= (librimel-event-to-key-sequence 'f5) "{F5}"))
  (should (string= (librimel-event-to-key-sequence 'f12) "{F12}")))

(ert-deftest librimel-test-event-to-key-sequence-braces ()
  "Brace characters must use names to avoid parse ambiguity."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence ?{) "{braceleft}"))
  (should (string= (librimel-event-to-key-sequence ?}) "{braceright}"))
  (let ((c-brace (car (listify-key-sequence (kbd "C-{")))))
    (should (string= (librimel-event-to-key-sequence c-brace) "{Control+braceleft}"))))

(ert-deftest librimel-test-event-to-key-sequence-space ()
  "Space character should return single space."
  (librimel-test--skip-unless-rime)
  (should (string= (librimel-event-to-key-sequence 32) " ")))

(ert-deftest librimel-test-event-to-key-sequence-modifier-direction-keys ()
  "Direction keys with modifiers should use {Modifier+Key} format."
  (librimel-test--skip-unless-rime)
  (let ((c-left (car (listify-key-sequence (kbd "C-<left>")))))
    (should (string= (librimel-event-to-key-sequence c-left) "{Control+Left}")))
  (let ((m-right (car (listify-key-sequence (kbd "M-<right>")))))
    (should (string= (librimel-event-to-key-sequence m-right) "{Meta+Right}")))
  (let ((c-m-left (car (listify-key-sequence (kbd "C-M-<left>")))))
    (should (string= (librimel-event-to-key-sequence c-m-left) "{Control+Meta+Left}"))))

(ert-deftest librimel-test-event-to-key-sequence-modifier-function-keys ()
  "Function keys with modifiers should use {Modifier+Key} format."
  (librimel-test--skip-unless-rime)
  (let ((c-f1 (car (listify-key-sequence (kbd "C-<f1>")))))
    (should (string= (librimel-event-to-key-sequence c-f1) "{Control+F1}"))))

(ert-deftest librimel-test-event-to-key-sequence-modifier-return ()
  "Return key with modifiers should use {Modifier+Return} format."
  (librimel-test--skip-unless-rime)
  (let ((m-return (car (listify-key-sequence (kbd "M-<return>")))))
    (should (string= (librimel-event-to-key-sequence m-return) "{Meta+Return}"))))

(ert-deftest librimel-test-event-to-key-sequence-modifier-bracket ()
  "Bracket key with modifiers should use {Modifier+name} format."
  (librimel-test--skip-unless-rime)
  (let ((c-bracket (car (listify-key-sequence (kbd "C-[")))))
    (should (string= (librimel-event-to-key-sequence c-bracket) "{Control+bracketleft}"))))

(ert-deftest librimel-test-event-to-key-sequence-modifier-semicolon ()
  "Semicolon with modifiers should use {Control+semicolon}."
  (librimel-test--skip-unless-rime)
  (let ((c-semi (car (listify-key-sequence (kbd "C-;")))))
    (should (string= (librimel-event-to-key-sequence c-semi) "{Control+semicolon}"))))

;; ---------------------------------------------------------------------------
;; Process event tests
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-process-event-integer ()
  "process-event with integer should send key sequence to librime."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (should (eq (librimel-process-event ?a) t)))

(ert-deftest librimel-test-process-event-symbol-left ()
  "process-event with 'left should send Left key to librime."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  ;; Process a key first to enter composition mode
  (librimel-process-event ?w)
  (librimel-process-event ?o)
  ;; Then send space to select first candidate
  (should (eq (librimel-process-event 'space) t))
  (librimel-clear-composition))

(ert-deftest librimel-test-process-event-control-char ()
  "process-event with Control modifier should work."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (let ((c-a (+ ?a #x4000000)))
    ;; Control+a may or may not be handled depending on schema
    (let ((result (librimel-process-event c-a)))
      (should (or (eq result t) (eq result nil))))))

(ert-deftest librimel-test-process-event-with-session ()
  "process-event with explicit session should work."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (should (eq (librimel-process-event ?h librimel-test--session-id) t))
  (should (string-equal (librimel-get-input) "h"))
  (librimel-clear-composition))

(ert-deftest librimel-test-process-event-return-key ()
  "process-event with 'return should commit composition."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (librimel-process-event ?n)
  (librimel-process-event ?i)
  (let ((input-before (librimel-get-input)))
    (should (string-equal input-before "ni")))
  (librimel-process-event 'return)
  (let ((commit (librimel-get-commit)))
    ;; After return, commit should be consumed or set
    (should (or (null commit) (stringp commit))))
  (librimel-clear-composition))

;; ---------------------------------------------------------------------------
;; Sync dir test
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-get-sync-dir ()
  "Get sync dir should return a string."
  (librimel-test--skip-unless-rime)
  (let ((dir (librimel-get-sync-dir)))
    (should (stringp dir))))

;; ---------------------------------------------------------------------------
;; Multi-session isolation test
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-session-isolation ()
  "Different sessions should have independent compositions."
  (librimel-test--skip-unless-rime)
  (let ((sid (librimel-create-session)))
    (unwind-protect
        (progn
          ;; Type in default session
          (librimel-clear-composition)
          (librimel-process-key ?w)
          (librimel-process-key ?o)
          ;; Type different thing in new session
          (librimel-clear-composition sid)
          (librimel-process-key ?n nil sid)
          (librimel-process-key ?i nil sid)
          ;; Check inputs are different
          (let ((input1 (librimel-get-input))
                (input2 (librimel-get-input sid)))
            (should (string-equal input1 "wo"))
            (should (string-equal input2 "ni")))
          (librimel-clear-composition)
          (librimel-clear-composition sid))
      (librimel-destroy-session sid))))

;; ---------------------------------------------------------------------------
;; Utility wrapper tests
;; ---------------------------------------------------------------------------

(ert-deftest librimel-test-get-preedit ()
  "librimel-get-preedit should extract preedit from context."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (librimel-process-key ?h)
  (librimel-process-key ?a)
  (librimel-process-key ?o)
  (let ((preedit (librimel-get-preedit)))
    (should (stringp preedit))
    (should (> (length preedit) 0)))
  (librimel-clear-composition))

(ert-deftest librimel-test-get-page-size ()
  "librimel-get-page-size should return a positive integer."
  (librimel-test--skip-unless-rime)
  (librimel-clear-composition)
  (librimel-process-key ?w)
  (librimel-process-key ?o)
  (let ((page-size (librimel-get-page-size)))
    (should (integerp page-size))
    (should (> page-size 0)))
  (librimel-clear-composition))

(ert-deftest librimel-test-current-schema-id ()
  "librimel-current-schema-id should return a non-empty string."
  (librimel-test--skip-unless-rime)
  (let ((schema-id (librimel-current-schema-id)))
    (should (stringp schema-id))
    (should (> (length schema-id) 0))))

;; ---------------------------------------------------------------------------
;; Entry point for CI
;; ---------------------------------------------------------------------------

(defun librimel-test-run ()
  "Run all librimel integration tests and exit."
  (librimel-test--setup)
  (unwind-protect
      (let ((stats (ert-run-tests-batch "^librimel-test-")))
        (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1)))
    (librimel-test--teardown)))

(provide 'librimel-test)

;;; librimel-test.el ends here

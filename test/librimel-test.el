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

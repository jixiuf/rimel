;;; rimel.el --- A lightweight Rime input method for Emacs -*- lexical-binding: t; -*-

;; Author: jixiuf
;; URL: https://github.com/jixiuf/rimel
;; Version: 0.1.0
;; Package-Requires: ((emacs "26.1") (liberime "0.0.6"))
;; Keywords: convenience, Chinese, input-method, rime

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;;; Commentary:

;; Rimel is a lightweight Chinese input method for Emacs based on liberime.
;; It directly uses Emacs' built-in `input-method-function' interface with
;; a read-event loop (similar to quail), providing a native Emacs experience.
;;
;; Features:
;; - Candidate display in echo area
;; - Inline preedit overlay at cursor
;; - Pagination support
;; - Enter key for raw English commit
;; - Number keys / space for candidate selection
;;
;; Usage:
;;   (require 'rimel)
;;   (set-input-method "rimel")

;;; Code:

(require 'cl-lib)
(require 'liberime)

;; Suppress byte-compiler warnings for C dynamic module functions
(declare-function liberime-process-key "ext:liberime-core")
(declare-function liberime-get-context "ext:liberime-core")
(declare-function liberime-get-commit "ext:liberime-core")
(declare-function liberime-get-input "ext:liberime-core")
(declare-function liberime-clear-composition "ext:liberime-core")
(declare-function liberime-select-candidate "ext:liberime-core")

;;; Customization

(defgroup rimel nil
  "Lightweight Rime input method for Emacs."
  :group 'leim
  :prefix "rimel-")

(defcustom rimel-schema nil
  "Rime schema ID to use (e.g., \"luna_pinyin_simp\").
When nil, use the default schema configured in Rime."
  :type '(choice (const :tag "Default" nil) string)
  :group 'rimel)

(defcustom rimel-return-behavior 'raw
  "Behavior of Enter key during composition.
`raw'     - commit the raw input as English (e.g., \"nihao\")
`preview' - commit the first candidate preview"
  :type '(choice (const :tag "Raw English" raw)
                 (const :tag "First candidate" preview))
  :group 'rimel)

(defcustom rimel-page-down-keys '(next ?\] ?= ?.)
  "Keys for next page during candidate selection.
Each element is an event as returned by `read-event': a character
integer (e.g., ?=, ?\\C-v) or a symbol (e.g., `next')."
  :type '(repeat sexp)
  :group 'rimel)

(defcustom rimel-page-up-keys '(prior ?\[ ?- ?,)
  "Keys for previous page during candidate selection.
Each element is an event: a character integer (e.g., ?-, ?\\M-v)
or a symbol (e.g., `prior')."
  :type '(repeat sexp)
  :group 'rimel)

(defcustom rimel-confirm-keys '(?\s)
  "Keys to confirm (select) the first candidate.
Sent to rime as-is; rime typically treats space as confirm."
  :type '(repeat sexp)
  :group 'rimel)

(defcustom rimel-commit-raw-keys '(return ?\r)
  "Keys to commit raw input (English) during composition.
Behavior is controlled by `rimel-return-behavior'."
  :type '(repeat sexp)
  :group 'rimel)

(defcustom rimel-backspace-keys '(backspace ?\C-? 127 ?\C-h)
  "Keys for deleting the last input character during composition."
  :type '(repeat sexp)
  :group 'rimel)

(defcustom rimel-cancel-keys '(escape ?\C-g)
  "Keys to cancel composition and discard all input."
  :type '(repeat sexp)
  :group 'rimel)

(defcustom rimel-select-label-keys '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9)
  "Keys for selecting candidates by position.
The Nth key selects the Nth candidate on the current page."
  :type '(repeat sexp)
  :group 'rimel)

(defface rimel-preedit-face
  '((t (:underline t :inherit font-lock-builtin-face)))
  "Face for the inline preedit string."
  :group 'rimel)

(defface rimel-highlight-face
  '((t (:inherit highlight)))
  "Face for the highlighted candidate."
  :group 'rimel)

;;; Internal variables

(defvar rimel--preedit-overlay nil
  "Overlay for displaying preedit at cursor.")

;;; Activation / Deactivation

(defun rimel-activate (_name)
  "Activate rimel input method.
Called by Emacs when user selects the \"rimel\" input method.
_NAME is the input method name (unused)."
  (unless (liberime-workable-p)
    (liberime-load))
  (when (and rimel-schema (liberime-workable-p))
    (liberime-try-select-schema rimel-schema))
  (setq-local input-method-function #'rimel-input-method)
  (setq-local deactivate-current-input-method-function #'rimel-deactivate))

(defun rimel-deactivate ()
  "Deactivate rimel input method."
  (rimel--clear-state)
  (kill-local-variable 'input-method-function)
  (kill-local-variable 'deactivate-current-input-method-function))

;;; Preedit overlay

(defun rimel--show-preedit (preedit)
  "Display PREEDIT string as overlay at point."
  (rimel--clear-preedit)
  (when (and preedit (not (string-empty-p preedit)))
    (let ((ov (make-overlay (point) (point) nil t t)))
      (overlay-put ov 'rimel t)
      (overlay-put ov 'after-string (propertize preedit 'face 'rimel-preedit-face))
      (setq rimel--preedit-overlay ov))))

(defun rimel--clear-preedit ()
  "Remove preedit overlay."
  (when (overlayp rimel--preedit-overlay)
    (delete-overlay rimel--preedit-overlay)
    (setq rimel--preedit-overlay nil)))

;;; Candidate display (echo area)

(defun rimel--format-candidates (context)
  "Format CONTEXT into a candidate display string for echo area."
  (let* ((composition (alist-get 'composition context))
         (preedit (alist-get 'preedit composition))
         (menu (alist-get 'menu context))
         (candidates (alist-get 'candidates menu))
         (highlighted (alist-get 'highlighted-candidate-index menu))
         (page-no (alist-get 'page-no menu))
         (last-page-p (alist-get 'last-page-p menu)))
    (when candidates
      (let ((parts '())
            (idx 0))
        ;; Preedit
        (when preedit
          (push (format "[%s]" preedit) parts))
        ;; Candidates
        (dolist (cand candidates)
          (let* ((label (nth idx rimel-select-label-keys))
                 (label-str (if label (format "%c." label) (format "%d." (1+ idx))))
                 (comment (get-text-property 0 :comment cand))
                 (text (if comment (format "%s(%s)" cand comment) cand))
                 (item (format "%s%s" label-str text)))
            (push (if (eql idx highlighted)
                      (propertize item 'face 'rimel-highlight-face)
                    item)
                  parts))
          (setq idx (1+ idx)))
        ;; Page indicator
        (push (format "(%d%s)" (1+ (or page-no 0))
                      (if last-page-p "" "+"))
              parts)
        (string-join (nreverse parts) " ")))))

(defun rimel--show-candidates (context)
  "Display candidates from CONTEXT in the echo area."
  (let ((content (rimel--format-candidates context)))
    (when content
      (let ((message-log-max nil))
        (message "%s" content)))))

;;; State management

(defun rimel--clear-state ()
  "Clear all composition state."
  (ignore-errors (liberime-clear-composition))
  (rimel--clear-preedit)
  (let ((message-log-max nil))
    (message nil)))

;;; Core input method

(defun rimel--composable-key-p (key)
  "Return non-nil if KEY should start a rime composition.
Only lowercase letters start composition."
  (and (integerp key)
       (>= key ?a)
       (<= key ?z)))

(defun rimel--event-in-p (event keys)
  "Return non-nil if EVENT is a member of KEYS list.
Works for both character (integer) and symbol events."
  (memq event keys))

(defun rimel--feed-key (key)
  "Send KEY to liberime for processing.  Return non-nil if handled."
  (liberime-process-key key))

(defun rimel--get-commit ()
  "Get committed text from rime, or nil."
  (let ((commit (liberime-get-commit)))
    (when (and commit (not (string-empty-p commit)))
      commit)))

(defun rimel--commit-raw ()
  "Commit raw English input or preview based on `rimel-return-behavior'."
  (let ((result (pcase rimel-return-behavior
                  ('raw (liberime-get-input))
                  ('preview (let* ((ctx (liberime-get-context)))
                              (alist-get 'commit-text-preview ctx))))))
    (liberime-clear-composition)
    (or result "")))

(defun rimel--select-candidate (idx)
  "Select candidate at IDX (0-based).  Return committed text or nil."
  (liberime-select-candidate idx)
  (rimel--get-commit))

(defun rimel-input-method (key)
  "Process KEY through rimel input method.
This function serves as `input-method-function'."
  (if (or buffer-read-only
          (not (rimel--composable-key-p key)))
      (list key)
    ;; Start composition
    (liberime-clear-composition)
    (rimel--feed-key key)
    ;; Check immediate commit (e.g., rime auto-select)
    (let ((commit (rimel--get-commit)))
      (if commit
          (string-to-list commit)
        ;; Enter composition loop
        (rimel--composition-loop)))))

(defun rimel--update-display ()
  "Update preedit overlay and echo area candidates from current rime state."
  (let ((ctx (liberime-get-context)))
    (rimel--show-preedit (alist-get 'preedit (alist-get 'composition ctx)))
    (rimel--show-candidates ctx)))

(defun rimel--feed-key-and-check (key)
  "Send KEY to rime.  Return committed text if any, otherwise update display."
  (rimel--feed-key key)
  (let ((commit (rimel--get-commit)))
    (if commit
        commit
      (rimel--update-display)
      nil)))

(defun rimel--composition-loop ()
  "Main composition loop.  Read events until composition finishes.
Return list of characters to insert, or nil."
  (let ((result nil)
        (continue t))
    (unwind-protect
        (progn
          (rimel--update-display)
          ;; Event loop
          (while continue
            (let ((event (read-event)))
              (cond
               ;; Letter keys - continue composition
               ((rimel--composable-key-p event)
                (let ((commit (rimel--feed-key-and-check event)))
                  (when commit (setq result commit continue nil))))

               ;; Candidate selection by label key (1-9 etc.)
               ((rimel--event-in-p event rimel-select-label-keys)
                (let* ((pos (cl-position event rimel-select-label-keys))
                       (commit (rimel--select-candidate pos)))
                  (if commit
                      (setq result commit continue nil)
                    (rimel--update-display))))

               ;; Confirm key (space etc.) - send to rime
               ((rimel--event-in-p event rimel-confirm-keys)
                (let ((commit (rimel--feed-key-and-check
                               (if (integerp event) event ?\s))))
                  (when commit (setq result commit continue nil))))

               ;; Commit raw input (enter etc.)
               ((rimel--event-in-p event rimel-commit-raw-keys)
                (setq result (rimel--commit-raw) continue nil))

               ;; Backspace - delete last character
               ((rimel--event-in-p event rimel-backspace-keys)
                (rimel--feed-key 65288)
                (let ((input (liberime-get-input)))
                  (if (or (null input) (string-empty-p input))
                      (setq continue nil)
                    (rimel--update-display))))

               ;; Cancel composition (escape etc.)
               ((rimel--event-in-p event rimel-cancel-keys)
                (liberime-clear-composition)
                (setq continue nil))

               ;; Page down
               ((rimel--event-in-p event rimel-page-down-keys)
                (rimel--feed-key 65366)
                (rimel--update-display))

               ;; Page up
               ((rimel--event-in-p event rimel-page-up-keys)
                (rimel--feed-key 65365)
                (rimel--update-display))

               ;; Unhandled key - exit composition, push key back
               (t
                (liberime-clear-composition)
                (setq continue nil)
                (setq unread-command-events
                      (if (characterp event)
                          (cons event unread-command-events)
                        (nconc (listify-key-sequence (vector event))
                               unread-command-events))))))))
      ;; Cleanup (unwind-protect)
      (rimel--clear-preedit)
      (let ((message-log-max nil))
        (message nil)))
    ;; Return result
    (when (and result (not (string-empty-p result)))
      (string-to-list result))))

;;; Registration

;;;###autoload
(register-input-method "rimel" "Chinese" #'rimel-activate "中"
                       "Rime input method via liberime")

(provide 'rimel)

;;; rimel.el ends here

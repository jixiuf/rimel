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

(defcustom rimel-show-candidate (or (require 'posframe nil t) 'echo-area)
  "How to display candidates.
`nil' - don't display candidates
`echo-area' - display in the echo area (default)
`posframe'  - display in a child frame near cursor (requires posframe package)"
  :type '(choice (const :tag "Echo area" echo-area)
                 (const :tag "Posframe" posframe))
  :group 'rimel)

(defcustom rimel-return-behavior 'raw
  "Behavior of Enter key during composition.
`raw'     - commit the raw input as English (e.g., \"nihao\")
`preview' - commit the first candidate preview"
  :type '(choice (const :tag "Raw English" raw)
                 (const :tag "First candidate" preview))
  :group 'rimel)

(defcustom rimel-keymap
  '((home   . "<home>")
    (left   . "<left>")
    (right  . "<right>")
    (up     . "<up>")
    (down   . "<down>")
    (?\C-p  . "<up>")
    (?\C-n  . "<down>")
    (prior  . "<prior>")
    (next   . "<next>")
    (?\C-b  . "<pageup>")
    (?\C-f  . "<pagedown>")
    (?\C-k  . "S-<delete>")
    (end    . "<end>")
    (begin  . "<home>"))
  "Alist of (emacs-key . rime-keycode) mappings for candidate navigation.

Common Emacs keys: `right', `left', `next', `prior', \\=`\\C-f', \\=`\\C-b', etc.

Value format supports:
  \"0xFF52\" - plain hex keycode (with 0x prefix)
  \"C-a\"    - Control + a (modifier + key)
  \"M-a\"     - Alt + a
  \"S-a\"     - Shift + a
  \"s-a\"     - Super + a
  \"H-a\"     - Hyper + a
  \"<left>\"  - symbol key (angle brackets)
  (\"C-a\" \"M-b\") - list of keycodes to try sequentially

Modifiers: C- (Control), M- (Alt), S- (Shift), s- (Super), H- (Hyper)
Key can be: hex (0xFF52), char (a), or symbol (<left>)

Common rime keycodes (hex):
See the hex keycode in https://github.com/rime/librime/blob/master/include/X11/keysymdef.h#L173

The rime-keycode can be a single string, or a list of strings to try sequentially."
  :type '(repeat (cons (sexp :tag "Emacs key")
                       (choice (string :tag "Rime key")
                               (repeat :tag "Rime keys"
                                       (string :tag "Rime key")))))
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

(defcustom rimel-disable-predicates nil
  "List of predicate functions for auto-switching to English.
Each function takes no arguments and returns non-nil to disable
Chinese input (pass through the key as-is).  If ANY predicate
returns non-nil, Chinese input is skipped for that key.

The variable `rimel--current-input-key' holds the key being
processed, available for predicates that need it.

Built-in predicates:
  `rimel-predicate-prog-in-code-p'
  `rimel-predicate-after-alphabet-char-p'
  `rimel-predicate-after-ascii-char-p'
  `rimel-predicate-current-uppercase-letter-p'
  `rimel-predicate-evil-mode-p'
  `rimel-predicate-org-in-src-block-p'
  `rimel-predicate-org-latex-mode-p'
  `rimel-predicate-tex-math-or-command-p'

You can also use predicates from emacs-rime (rime-predicate-*)
or pyim (pyim-probe-*) if those packages are loaded.

Example:
  (setq rimel-disable-predicates
        \\='(rimel-predicate-prog-in-code-p
          rimel-predicate-after-alphabet-char-p
          rimel-predicate-current-uppercase-letter-p))"
  :type '(repeat function)
  :group 'rimel)

(defface rimel-preedit-face
  '((t (:underline t :inherit font-lock-builtin-face)))
  "Face for the inline preedit string."
  :group 'rimel)

(defface rimel-highlight-face
  '((t (:inherit highlight)))
  "Face for the highlighted candidate."
  :group 'rimel)

(defcustom rimel-posframe-style 'vertical
  "Candidate layout style in posframe.
`vertical'   - one candidate per line
`horizontal' - all candidates in one line"
  :type '(choice (const :tag "Vertical" vertical)
                 (const :tag "Horizontal" horizontal))
  :group 'rimel)

(defcustom rimel-posframe-min-width 20
  "Minimum width of the posframe."
  :type 'integer
  :group 'rimel)

(defface rimel-posframe-face
  '((t (:inherit default)))
  "Face for the posframe body text."
  :group 'rimel)

(defface rimel-posframe-border-face
  '((t (:inherit border)))
  "Face for the posframe border."
  :group 'rimel)

;;; Internal variables

(defvar rimel--preedit-overlay nil
  "Overlay for displaying preedit at cursor.")

(defvar rimel--current-input-key nil
  "The key currently being processed by `rimel-input-method'.
Available for use by predicate functions in `rimel-disable-predicates'.")

(defvar rimel--posframe-buffer " *rimel-posframe*"
  "Buffer name for posframe candidate display.")

(declare-function posframe-show "ext:posframe")
(declare-function posframe-hide "ext:posframe")

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

;;; Candidate display

(defun rimel--format-candidates (context &optional separator show-preedit)
  "Format CONTEXT into a candidate display string.
SEPARATOR is placed between candidates (default single space).
When SHOW-PREEDIT is non-nil, include the preedit string."
  (let* ((composition (alist-get 'composition context))
         (preedit (alist-get 'preedit composition))
         (menu (alist-get 'menu context))
         (candidates (alist-get 'candidates menu))
         (highlighted (alist-get 'highlighted-candidate-index menu))
         (page-no (alist-get 'page-no menu))
         (last-page-p (alist-get 'last-page-p menu))
         (sep (or separator " ")))
    (when candidates
      (let ((parts '())
            (idx 0))
        ;; Preedit (only for echo-area, posframe has overlay)
        (when (and show-preedit preedit)
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
        (string-join (nreverse parts) sep)))))

(defun rimel--show-candidates (context)
  "Display candidates from CONTEXT using the configured method."
  (pcase rimel-show-candidate
    ('posframe (rimel--posframe-show context))
    ('echo-area (rimel--echo-area-show context))))

(defun rimel--hide-candidates ()
  "Hide the candidate display."
  (pcase rimel-show-candidate
    ('posframe (rimel--posframe-hide))
    ('echo-area (let ((message-log-max nil)) (message nil)))))

;; Echo area backend

(defun rimel--echo-area-show (context)
  "Display candidates from CONTEXT in the echo area."
  (let ((content (rimel--format-candidates context " " t)))
    (when content
      (let ((message-log-max nil))
        (message "%s" content)))))

;; Posframe backend

(defun rimel--posframe-show (context)
  "Display candidates from CONTEXT in a posframe near cursor."
  (if (not (require 'posframe nil t))
      (rimel--echo-area-show context)
    (let* ((sep (if (eq rimel-posframe-style 'vertical) "\n" " "))
           (content (rimel--format-candidates context sep nil)))
      (if (not content)
          (rimel--posframe-hide)
        (posframe-show
         rimel--posframe-buffer
         :string content
         :position (point)
         :background-color (face-background 'rimel-posframe-face nil t)
         :foreground-color (face-foreground 'rimel-posframe-face nil t)
         :border-width 1
         :border-color (face-background 'rimel-posframe-border-face nil t)
         :min-width rimel-posframe-min-width
         :timeout nil)))))

(defun rimel--posframe-hide ()
  "Hide the posframe candidate display."
  (when (require 'posframe nil t)
    (posframe-hide rimel--posframe-buffer)))

;;; State management

(defun rimel--clear-state ()
  "Clear all composition state."
  (ignore-errors (liberime-clear-composition))
  (rimel--clear-preedit)
  (rimel--hide-candidates))

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

(defun rimel--feed-key (key &optional mask)
  "Send KEY to liberime for processing.  Return non-nil if handled."
  (if mask
      (liberime-process-key key mask)
    (liberime-process-key key)))

(defun rimel--feed-key-string (keycode)
  "Parse KEYCODE string(s) and feed to rime.
Supports formats:
  ?a         - char
  #xFF52     - hex keycode
  \"0xFF52\" - plain hex keycode
  \"C-a\"    - Control + key
  \"M-a\"    - Alt (Mod1) + key
  \"S-a\"    - Shift + key
  \"s-a\"    - Super + key
  \"H-a\"    - Hyper + key
  (\"C-a\" \"M-b\") - list of keycodes to try sequentially
The key after C-/M-/S/s/H- can be a char like \"a\" or a symbol like \"<left>\"."
  (cond
   ((listp keycode)
    (dolist (kc keycode)
      (rimel--feed-key-string kc)))
   ((stringp keycode)
    (let ((case-fold-search nil)
          (modifiers 0)
          (key keycode))
      (when (string-match "^\\([CMsSH]\\)-" keycode)
        (pcase (substring keycode (match-beginning 1) (match-end 1))
          ("C" (setq modifiers (logior modifiers 4)))
          ("M" (setq modifiers (logior modifiers 8)))
          ("s" (setq modifiers (logior modifiers (ash 1 26)))) ; Super
          ("S" (setq modifiers (logior modifiers 1)))
          ("H" (setq modifiers (logior modifiers (ash 1 27))))) ; Hyper
        (setq key (substring keycode (match-end 0))))
      (let ((keyval
             (cond
              ((numberp key) key)       ;#xff52, ?a
              ;; hex keycode like "0xFF52" or "FF52"
              ((string-match "^0x[0-9A-Fa-f]+$" key)
               (string-to-number (substring key 2) 16))
              ;; single char like "a"
              ((= (length key) 1)
               (if (string-match "[0-9A-Z]" key)
                   (+ 64 (- (aref key 0) ?A))
                 (aref key 0)))
              ;; symbol like "<left>"
              ((string-match "^<\\(.+\\)>$" key)
               (let ((sym (downcase (match-string 1 key))))
                 (pcase sym
                   ;; https://github.com/rime/librime/blob/master/include/X11/keysymdef.h#L173
                   ("left" #xff51)
                   ("right" #xff53)
                   ("up" #xff52)
                   ("down" #xff54)
                   ("prior" #xff55)
                   ("pageup" #xff55)
                   ("next" #xff56)
                   ("pagedown" #xff56)
                   ("home" #xff50)
                   ("end" #xff57)
                   ("delete" #xffff)
                   ("backspace" #xff08)
                   ("return" #xff0d)
                   ("comma" #x002c)
                   ("colon" #x003a)
                   ("semicolon" #x003b)
                   ("grave" #x0060)
                   ("less" #x003c)
                   ("equal" #x003d)
                   ("slash" #x002f)
                   ("period" #x002e)
                   ("minus" #x002d)
                   ("plus" #x002b)
                   ("bracketleft" #x005b)
                   ("bracketright" #x005d)
                   ("backslash" #x005c)
                   ("space" #x0020)
                   ("tab" #xff09)
                   ("escape" #xff1b)
                   (_ (user-error "Unknown key symbol: %s" key)))))
                 (t (user-error "Invalid key format: %s" key)))))
             (rimel--feed-key keyval modifiers))))))

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
  (setq rimel--current-input-key key)
  (if (or buffer-read-only
          (not (rimel--composable-key-p key))
          (not (rimel--should-enable-p)))
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

               ;; Key mapping via rimel-keymap
                ((when-let* ((pair (cl-find event rimel-keymap :key #'car :test #'equal))
                             (rime-keycode (cdr pair)))
                   (rimel--feed-key-string rime-keycode)
                   (rimel--update-display)))

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
      (rimel--hide-candidates))
    ;; Return result
    (when (and result (not (string-empty-p result)))
      (string-to-list result))))

;;; Predicates — context-based auto English switching

(defun rimel--should-enable-p ()
  "Return non-nil if Chinese input should be active.
Checks `rimel-disable-predicates'; if any returns non-nil,
Chinese input is disabled for the current key."
  (not (seq-find #'funcall rimel-disable-predicates)))

(defun rimel-predicate-prog-in-code-p ()
  "Return non-nil when cursor is in code (not string/comment).
Only active in `prog-mode' derived buffers."
  (and (derived-mode-p 'prog-mode 'conf-mode)
       (let ((ppss (syntax-ppss)))
         (not (or (nth 3 ppss)    ; in string
                  (nth 4 ppss)))))) ; in comment

(defun rimel-predicate-after-alphabet-char-p ()
  "Return non-nil when the char before point is a Latin letter.
Useful for continuing English words without switching."
  (and (> (point) (point-min))
       (let ((ch (char-before)))
         (and ch
              (or (and (>= ch ?a) (<= ch ?z))
                  (and (>= ch ?A) (<= ch ?Z)))))))

(defun rimel-predicate-after-ascii-char-p ()
  "Return non-nil when the char before point is an ASCII char.
Broader than `rimel-predicate-after-alphabet-char-p' — includes
digits and punctuation."
  (and (> (point) (point-min))
       (let ((ch (char-before)))
         (and ch (>= ch #x21) (<= ch #x7e)))))

(defun rimel-predicate-current-uppercase-letter-p ()
  "Return non-nil when the current input key is an uppercase letter."
  (and rimel--current-input-key
       (integerp rimel--current-input-key)
       (>= rimel--current-input-key ?A)
       (<= rimel--current-input-key ?Z)))

(declare-function evil-normal-state-p "ext:evil-states")
(declare-function evil-visual-state-p "ext:evil-states")
(declare-function evil-motion-state-p "ext:evil-states")
(declare-function evil-operator-state-p "ext:evil-states")

(defun rimel-predicate-evil-mode-p ()
  "Return non-nil in evil normal, visual, motion or operator state.
Returns nil if evil is not loaded or in insert/emacs state."
  (and (fboundp 'evil-normal-state-p)
       (or (evil-normal-state-p)
           (evil-visual-state-p)
           (evil-motion-state-p)
           (evil-operator-state-p))))

(declare-function org-in-src-block-p "ext:org")

(defun rimel-predicate-org-in-src-block-p ()
  "Return non-nil when point is inside an Org source block."
  (and (derived-mode-p 'org-mode)
       (fboundp 'org-in-src-block-p)
       (org-in-src-block-p)))

(declare-function org-inside-LaTeX-fragment-p "ext:org")
(declare-function org-inside-latex-macro-p "ext:org")

(defun rimel-predicate-org-latex-mode-p ()
  "Return non-nil when point is in an Org LaTeX fragment or macro."
  (and (derived-mode-p 'org-mode)
       (or (and (fboundp 'org-inside-LaTeX-fragment-p)
                (org-inside-LaTeX-fragment-p))
           (and (fboundp 'org-inside-latex-macro-p)
                (org-inside-latex-macro-p)))))

(declare-function texmathp "ext:texmathp")

(defun rimel-predicate-tex-math-or-command-p ()
  "Return non-nil in a TeX math environment or after a TeX command.
Supports AUCTeX's `texmathp' if available, otherwise falls back
to detecting $ and \\ prefixes."
  (when (derived-mode-p 'tex-mode 'latex-mode 'TeX-mode 'LaTeX-mode)
    (or (and (fboundp 'texmathp) (texmathp))
        ;; Fallback: check for $ or \ before point
        (and (> (point) (point-min))
             (let ((ch (char-before)))
               (or (eq ch ?$) (eq ch ?\\)))))))

;;; Registration

;;;###autoload
(register-input-method "rimel" "Chinese" #'rimel-activate "中"
                       "Rime input method via liberime")

(provide 'rimel)

;;; rimel.el ends here

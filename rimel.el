;;; rimel.el --- A lightweight Rime input method -*- lexical-binding: t; -*-

;; Author: jixiuf
;; URL: https://github.com/jixiuf/rimel
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.4") (librimel "0.1.0"))
;; Keywords: convenience, Chinese, input-method, rime

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;;; Commentary:

;; Rimel is a lightweight Chinese input method for Emacs based on librimel.
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
(require 'librimel)

;; Suppress byte-compiler warnings for C dynamic module functions
(declare-function librimel-process-key "ext:librimel-core")
(declare-function librimel-get-context "ext:librimel-core")
(declare-function librimel-get-commit "ext:librimel-core")
(declare-function librimel-get-input "ext:librimel-core")
(declare-function librimel-clear-composition "ext:librimel-core")
(declare-function librimel-select-candidate "ext:librimel-core")
(declare-function librimel-get-schema-list "ext:librimel-core")
(declare-function librimel-sync-user-data "ext:librimel-core")
(declare-function librimel-get-candidates "ext:librimel-core")

;;; Customization

(defgroup rimel nil
  "Lightweight Rime input method for Emacs."
  :group 'librimel
  :prefix "rimel-")

(defcustom rimel-deploy-hook nil
  "List of functions to be called after deploying rime."
  :group 'rimel
  :type 'hook)

(defcustom rimel-schema nil
  "Rime schema ID to use (e.g., \"luna_pinyin_simp\").
When nil, use the default schema configured in Rime."
  :type '(choice (const :tag "Default" nil) string)
  :group 'rimel)

(defcustom rimel-shared-data-dir nil
  "Data directory on the system.

More info: https://github.com/rime/home/wiki/SharedData"
  :group 'rimel
  :type 'file)

(defcustom rimel-user-data-dir
  (locate-user-emacs-file "rime/")
  "Data directory on the user home directory."
  :group 'rimel
  :type 'file)

(defcustom rimel-show-candidate
  (or (require 'posframe nil t) 'echo-area)
  "How to display candidates.
nil - don't display candidates
`echo-area' - display in the echo area (default)
`posframe'  - display in a child frame near cursor (requires posframe package)"
  :type '(choice (const :tag "Echo area" echo-area)
                 (const :tag "Posframe" posframe))
  :group 'rimel)

(defcustom rimel-inline-preedit 'candidate
  "Set to not nil to enable inline preedit.
set to \='candidate to inline candidate"
  :type '(choice (const :tag "Inline candidate" candidate)
                 (const :tag "Inline preedit" t)
                 (const :tag "Disable inline preedit" nil))
  :group 'rimel)

(defcustom rimel-return-behavior 'raw
  "Behavior of Enter key during composition.
`raw'     - commit the raw input as English (e.g., \"nihao\")
`preview' - commit the first candidate preview"
  :type '(choice (const :tag "Raw English" raw)
                 (const :tag "First candidate" preview))
  :group 'rimel)

(defcustom rimel-keymap
  '(("<home>"   . "<home>"    )
    ("<left>"   . "<left>"    )
    ("<right>"  . "<right>"   )
    ("<up>"     . "<up>"      )
    ("<down>"   . "<down>"    )
    ("C-p"      . "<up>"      )
    ("C-n"      . "<down>"    )
    ("<prior>"  . "<prior>"   )
    ("<next>"   . "<next>"    )
    ("C-b"      . "<prior>"   )
    ("C-f"      . "<next>"    )
    ("C-k"      . "S-<delete>")
    ("<end>"    . "<end>"     )
    ("C-a"      . "<home>"    )
    ("C-e"      . "<end>"     )
    ("<tab>"    . "<tab>"     ))
  "Keymap for custom keybindings in Rimel.
Both KEY and VALUE must be strings in the format returned by
\\[describe-key] (=describe-key').  This matches the format used
for saving keyboard macros (see =edmacro-mode').
Note: VALUE can be a sequence like \"C-c C-c\", but KEY cannot.

Examples:
    \"H-<left>\"
    \"M-RET\"
    \"C-M-<return>\""
  :type '(repeat (cons (sexp :tag "Emacs key")
                       (string :tag "Rime key")))
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

(defcustom rimel-backspace-keys '(backspace ?\C-? 127)
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

(defcustom rimel-highlight-first nil
  "When non-nil, move the highlighted candidate to the first position.
For example, if candidates are [a b c d e] and c is highlighted,
display as [c d e a b]."
  :type 'boolean
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

(defvar rimel--session-id nil
  "Default session after deploying rime.")
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

;;;###autoload
(defun rimel-activate (_name)
  "Activate rimel input method.
Called by Emacs when user selects the \"rimel\" input method.
_NAME is the input method name (unused)."
  (unless rimel--session-id
    (rimel-deploy))
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
  (when (and preedit (not (string-equal preedit "")))
    (let* ((pos (if (> (point) (point-min)) (1- (point)) (point)))
           (surrounding-face (plist-get (text-properties-at pos) 'face))
           ;; When there is text after point, after-string inherits
           ;; surrounding face automatically -- only use rimel-preedit-face
           ;; to avoid :height stacking.
           ;; At eol, after-string does NOT inherit, so merge surrounding-face.
           (face (if (and surrounding-face (eolp))
                     (cons 'rimel-preedit-face surrounding-face)
                   'rimel-preedit-face))
           (ov (make-overlay (point) (point) nil t t)))
      (overlay-put ov 'rimel t)
      (overlay-put ov 'after-string (propertize preedit 'face face))
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
         (highlighted (or (alist-get 'highlighted-candidate-index menu) 0))
         (page-no (or (alist-get 'page-no menu) 0))
         (page-size (or (alist-get 'page-size menu) 5))
         (pos (+ (* page-no page-size) highlighted))
         (last-page-p (alist-get 'last-page-p menu))
         (sep (or separator " ")))
    (when candidates
      (let ((parts '())
            (idx 0)
            (candidates-list (if (and rimel-highlight-first (> highlighted 0))
                                 (or (librimel-get-candidates pos page-size) candidates)
                               candidates))
            (highlight-idx (if rimel-highlight-first 0 highlighted)))
        ;; Preedit (only for echo-area, posframe has overlay)
        (when (and show-preedit preedit)
          (push (format "[%s]" preedit) parts))
        ;; Candidates
        (dolist (cand candidates-list)
          (let* ((label (nth idx rimel-select-label-keys))
                 (label-str (if label (format "%c." label) (format "%d." (1+ idx))))
                 (comment (get-text-property 0 :comment cand))
                 (text (if comment (format "%s(%s)" cand comment) cand))
                 (item (format "%s%s" label-str text)))
            (push (if (eql idx highlight-idx)
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
  (let ((content (rimel--format-candidates
                  context " " (eq rimel-inline-preedit 'candidate))))
    (when content
      (let ((message-log-max nil))
        (message "%s" content)))))

;; Posframe backend
(defun rimel--at-screen-bottom-p ()
  "At screen bottom or not."
  (let* ((current-line (count-screen-lines (window-start) (point)))
         (window-height (window-body-height)))
    (>= current-line (- window-height 1))))

(defun rimel--posframe-show (context)
  "Display candidates from CONTEXT in a posframe near cursor."
  (if (not (require 'posframe nil t))
      (rimel--echo-area-show context)
    (let* ((sep (if (eq rimel-posframe-style 'vertical) "\n" " "))
           (content (rimel--format-candidates
                     context sep (eq rimel-inline-preedit 'candidate))))
      (if (not content)
          (rimel--posframe-hide)
        (posframe-show
         rimel--posframe-buffer
         :string content
         :x-pixel-offset 2
         ;; for TUI emacs
         :y-pixel-offset (if (rimel--at-screen-bottom-p) -3 1)
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
  (ignore-errors (librimel-clear-composition))
  (rimel--clear-preedit)
  (rimel--hide-candidates))

;;; Core input method

(defun rimel--composable-key-p (key)
  "Return non-nil if KEY should start a rime composition.
Includes lowercase letters and common Chinese punctuation marks."
  (and (integerp key)
       (or (and (>= key ?a) (<= key ?z))
           (memq key '(?+ ?= ?- ?_ ?\( ?\) ?* ?& ?^ ?% ?$ ?# ?@ ?! ?` ?~
                          ?\[ ?\]  ?{  ?}  ?\\  ?|
                          ?\: ?\; ?\'  ?\"
                          ?, ?. ?<  ?>   ?\? ?/
                          ?\,  ?。 ?…  ?—  ?·  ?～  ?、)))))

(defun rimel--event-in-p (event keys)
  "Return non-nil if EVENT is a member of KEYS list.
Works for both character (integer) and symbol events."
  (memq event keys))

(defun rimel--get-commit ()
  "Get committed text from rime, or nil."
  (let ((commit (librimel-get-commit)))
    (when (and commit (not (string-equal commit "")))
      commit)))

(defun rimel--commit-raw ()
  "Commit raw English input or preview based on `rimel-return-behavior'."
  (let ((result (pcase rimel-return-behavior
                  ('raw (librimel-get-input))
                  ('preview (let* ((ctx (librimel-get-context)))
                              (alist-get 'commit-text-preview ctx))))))
    (librimel-clear-composition)
    (or result "")))

(defun rimel--select-candidate (idx)
  "Select candidate at IDX (0-based).  Return committed text or nil."
  (if rimel-highlight-first
      (let* ((ctx (librimel-get-context))
             (menu (alist-get 'menu ctx))
             (highlighted (alist-get 'highlighted-candidate-index menu)))
        (librimel-select-candidate (+ idx (or highlighted 0))))
    (librimel-select-candidate idx))
  (or (rimel--get-commit)
      (rimel--update-display)))

(defun rimel-input-method (key)
  "Process KEY through rimel input method.
This function serves as `input-method-function'."
  (setq rimel--current-input-key key)
  ;; form quail-input-method
  (if (or (and (or buffer-read-only
                   (and (get-char-property (point) 'read-only)
                        (get-char-property (point) 'front-sticky)))
	           (not (or inhibit-read-only
			            (get-char-property (point) 'inhibit-read-only))))
          (not (rimel--composable-key-p key))
          (not (rimel--should-enable-p))
          ;; When an overriding keymap is active (e.g., `set-transient-map'
          ;; used by spatial-window, avy, etc.), pass the key through if
          ;; it has a binding there.  This matches quail's behavior per
          ;; Emacs bug#68338.
          (and overriding-terminal-local-map
               (lookup-key overriding-terminal-local-map (vector key)))
          overriding-local-map)
      (list key)
    ;; Start composition
    (librimel-clear-composition)
    (librimel-process-key key)
    ;; Check immediate commit (e.g., rime auto-select)
    (let ((commit (rimel--get-commit)))
      (if commit
          (string-to-list commit)
        ;; Enter composition loop
        (rimel--composition-loop)))))

(defun rimel--update-display ()
  "Update preedit overlay and echo area candidates from current rime state."
  (let ((ctx (librimel-get-context)))
    (cond
     ((eq rimel-inline-preedit 'candidate)
      (rimel--show-preedit (alist-get 'commit-text-preview ctx)))
     ((eq rimel-inline-preedit t)
      (rimel--show-preedit (alist-get 'preedit (alist-get 'composition ctx)))))
    (rimel--show-candidates ctx))
  nil)

(defun rimel--check-commit ()
  "Return committed text if any, otherwise update display."
  (let ((commit (rimel--get-commit)))
    (if commit
        (progn
          (when-let* ((input (librimel-get-input)))
            (setq unread-command-events
                  (append (string-to-list input) unread-command-events)))
          commit)
      (rimel--update-display)
      nil))
  )
(defun rimel--feed-key-and-check (key)
  "Send KEY to rime.  Return committed text if any, otherwise update display."
  (librimel-process-key key)
  (rimel--check-commit))

(defun rimerl--get-key(pair)
  (car (listify-key-sequence (kbd (car pair)))))

(defun rimel--composition-loop ()
  "Main composition loop.  Read events until composition finishes.
Return list of characters to insert, or nil."
  (let ((result nil)
        (continue t)
        (echo-keystrokes 0))
    (unwind-protect
        (progn
          (rimel--update-display)
          ;; Event loop
          (while continue
            (let ((event (read-event)))
              (cond
               ;; Letter keys - continue composition
               ((rimel--composable-key-p event)
                (when-let* ((commit (rimel--feed-key-and-check event)))
                  (setq result commit continue nil)))

               ;; Candidate selection by label key (1-9 etc.)
               ((rimel--event-in-p event rimel-select-label-keys)
                (when-let* ((pos (cl-position event rimel-select-label-keys))
                            (commit (rimel--select-candidate pos)))
                  (setq result commit continue nil)))

               ;; Confirm key (space etc.) - send to rime
               ((rimel--event-in-p event rimel-confirm-keys)
                (when-let* ((commit (rimel--feed-key-and-check
                                     (if (integerp event) event ?\s))))
                  (setq result commit continue nil)))

               ;; Commit raw input (enter etc.)
               ((rimel--event-in-p event rimel-commit-raw-keys)
                (setq result (rimel--commit-raw) continue nil))

               ;; Backspace - delete last character
               ((rimel--event-in-p event rimel-backspace-keys)
                (librimel-process-key #xff08) ;backspace
                (let ((input (librimel-get-input)))
                  (if (or (null input) (string-equal input ""))
                      (setq continue nil)
                    (rimel--update-display))))

               ;; Cancel composition (escape etc.)
               ((rimel--event-in-p event rimel-cancel-keys)
                (librimel-clear-composition)
                (setq continue nil))

               ;; Key mapping via rimel-keymap
               ((when-let* ((pair (cl-find event rimel-keymap
                                           :key #'rimerl--get-key
                                           :test #'equal))
                            (rime-keycode (cdr pair)))
                  (librimel-process-keys (kbd rime-keycode))
                  (when-let* ((commit (rimel--check-commit)))
                    (setq result commit continue nil))
                  t))

               ;; Unhandled key - exit composition, push key back
               (t
                (librimel-clear-composition)
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
    (when (and result (not (string-equal result "")))
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


;;;###autoload
(defun rimel-select-schema ()
  "Select a rime schema."
  (interactive)
  (let ((schema-list
         (mapcar (lambda (x)
                   (cons (format "%s(%s)" (cadr x) (car x))
                         (car x)))
                 (ignore-errors (librimel-get-schema-list)))))
    (if schema-list
        (let* ((schema-name (completing-read "Rime schema: " schema-list))
               (schema (alist-get schema-name schema-list nil nil #'equal)))
          (librimel-select-schema schema))
      (message "Librimel: no schema has been found, ignored."))))


;;;###autoload
(defun rimel-deploy()
  "Deploy rime."
  (interactive)
  (when-let* ((session-id (librimel-start
                           rimel-schema rimel-shared-data-dir
                           rimel-user-data-dir)))
    (run-hooks 'rimel-deploy-hook)
    (setq rimel--session-id session-id)))

;;;###autoload
(defun rimel-sync ()
  "Sync rime user data.
User should specify sync_dir in installation.yaml file of
`librimel-user-data-dir' directory."
  (interactive)
  (librimel-sync-user-data))

;;; Registration

;;;###autoload
(register-input-method "rimel" "Chinese" #'rimel-activate
                       (if (char-displayable-p 12563) (char-to-string 12563) "中")
                       "Rimel - Rime input method via librimel")

(provide 'rimel)

;;; rimel.el ends here

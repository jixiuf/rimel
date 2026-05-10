;;; rimel-quail.el --- Quail integration for Rimel -*- lexical-binding: t; -*-

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file defines the "rimel-quail" Quail package.  Quail owns key
;; collection and keyboard layout translation; Rimel handles Rime state,
;; candidate display and commit text.

;;; Code:

(require 'quail)
(require 'rimel)

(declare-function quail-add-unread-command-events "quail" (key &optional reset))
(declare-function quail-name "quail")
(declare-function quail-package "quail" (name))
(declare-function liberime-clear-composition "ext:liberime-core")
(declare-function liberime-get-context "ext:liberime-core")
(declare-function liberime-get-input "ext:liberime-core")
(declare-function liberime-process-key "ext:liberime-core")
(declare-function liberime-process-keys "ext:liberime-core")
(defvar input-method-previous-message)
(defvar input-method-use-echo-area)
(defvar quail-current-package)
(defvar quail-guidance-str)
(defvar quail-translation-keymap)

(defconst rimel-quail--input-method-name "rimel-quail"
  "Input method name for the Quail-backed Rimel package.")

(defconst rimel-quail--guidance 'rimel-quail
  "Quail guidance marker for Rimel-owned candidate display.")

(defvar-local rimel-quail--composing nil
  "Non-nil while the current Quail translation owns a Rime composition.")

(defun rimel-quail--map (_key _len)
  "Return a recursive Quail map for Rimel composable keys."
  (mapcar (lambda (key)
            (cons key (cons key 'rimel-quail--map)))
          rimel--composable-keys))

(defun rimel-quail--current-package-p ()
  "Return non-nil when the current Quail package is `rimel-quail'."
  (and (boundp 'quail-current-package)
       quail-current-package
       (equal (quail-name) rimel-quail--input-method-name)))

(defun rimel-quail--current-char ()
  "Return the current translated Quail character, or nil."
  (cond
   ((characterp quail-current-str)
    quail-current-str)
   ((and (stringp quail-current-str)
         (= (length quail-current-str) 1))
    (aref quail-current-str 0))))

(defun rimel-quail--finish (text)
  "Finish Quail translation with TEXT."
  (setq quail-current-str (or text "")
        rimel-quail--composing nil
        quail-translating nil
        quail-guidance-str ""
        input-method-previous-message nil)
  (rimel--hide-candidates)
  t)

(defun rimel-quail--continue ()
  "Continue Quail translation without inserting interim text."
  (setq quail-current-str "")
  nil)

(defun rimel-quail--after-rime-key ()
  "Handle Rime state after sending one key."
  (if-let* ((commit (rimel--get-commit)))
      (rimel-quail--finish commit)
    (rimel-quail--update-display)
    (rimel-quail--continue)))

(defun rimel-quail--show-posframe (context)
  "Show CONTEXT with Rimel posframe display."
  (setq-local input-method-use-echo-area nil)
  (setq input-method-previous-message nil)
  (rimel--posframe-show context))

(defun rimel-quail--update-display ()
  "Update Quail prompt and Rimel display for the current Rime state."
  (when (rimel-quail--current-package-p)
    (if rimel-quail--composing
        (let ((context (liberime-get-context)))
          (rimel--update-preedit context)
          (pcase rimel-show-candidate
            ('echo-area
             (setq-local input-method-use-echo-area t)
             (setq input-method-previous-message
                   (rimel--echo-area-content context)))
            ('posframe
             (rimel-quail--show-posframe context))
            (_
             (setq-local input-method-use-echo-area nil)
             (setq input-method-previous-message nil)
             (rimel--hide-candidates))))
      (setq quail-guidance-str "")
      (setq input-method-previous-message nil)
      (rimel--hide-candidates))))

(defun rimel-quail--start-composition (key)
  "Start a Rime composition with translated KEY."
  (setq rimel--current-input-key last-command-event)
  (if (or (not (rimel--composable-key-p key))
          (not (rimel--should-enable-p)))
      (rimel-quail--finish (char-to-string key))
    (setq rimel-quail--composing t)
    (liberime-clear-composition)
    (liberime-process-key key)
    (rimel-quail--after-rime-key)))

(defun rimel-quail--select-candidate ()
  "Select a Rime candidate from `last-command-event'."
  (if-let* ((pos (cl-position last-command-event rimel-select-label-keys))
            (commit (rimel--select-candidate pos)))
      (rimel-quail--finish commit)
    (rimel-quail--continue)))

(defun rimel-quail--unread-last-event ()
  "Return `last-command-event' to Emacs and finish translation."
  (rimel--clear-state)
  (quail-add-unread-command-events last-command-event)
  (rimel-quail--finish ""))

(defun rimel-quail--update-translation (_control-flag)
  "Update Rime state from the current Quail key."
  (cond
   ((rimel--event-in-p last-command-event rimel-select-label-keys)
    (rimel-quail--select-candidate))
   ((not rimel-quail--composing)
    (if-let* ((key (rimel-quail--current-char)))
        (rimel-quail--start-composition key)
      (rimel-quail--unread-last-event)))
   ((if-let* ((key (rimel-quail--current-char)))
        (if (rimel--composable-key-p key)
            (progn
              (liberime-process-key key)
              (rimel-quail--after-rime-key))
          (rimel-quail--unread-last-event))
      (rimel-quail--unread-last-event)))))

(defun rimel-quail--rime-key-command ()
  "Send the current command event to Rime through `rimel-keymap'."
  (interactive)
  (if-let* ((pair (cl-find last-command-event rimel-keymap
                           :key #'rimel--get-key
                           :test #'equal))
            (rime-keycode (cdr pair)))
      (progn
        (liberime-process-keys (kbd rime-keycode))
        (if-let* ((commit (rimel--get-commit)))
            (rimel-quail--finish commit)
          (rimel-quail--update-display)
          (when (string-empty-p (liberime-get-input))
            (setq quail-translating nil
                  rimel-quail--composing nil))
          (rimel-quail--continue)))
    (rimel-quail--unread-last-event)))

(defun rimel-quail--other-command ()
  "Handle an event that is not part of a Rime composition."
  (interactive)
  (rimel-quail--unread-last-event))

(defun rimel-quail--install-translation-keymap ()
  "Install Rimel-specific commands into the current Quail package."
  (when-let* ((package (quail-package rimel-quail--input-method-name)))
    (let ((map (copy-keymap quail-translation-keymap)))
      (dotimes (key 32)
        (define-key map (vector key) #'rimel-quail--other-command))
      (define-key map (vector 127) #'rimel-quail--other-command)
      (dolist (pair rimel-keymap)
        (define-key map
                    (vector (rimel--get-key pair))
                    #'rimel-quail--rime-key-command))
      (setcar (nthcdr 5 package) map))))

(defun rimel-quail--activate ()
  "Prepare Rimel state for the `rimel-quail' Quail package."
  (when (rimel-quail--current-package-p)
    (rimel--activate-common)
    (setq-local rimel-quail--composing nil)
    (setq-local input-method-use-echo-area
                (eq rimel-show-candidate 'echo-area))
    (rimel-quail--install-translation-keymap)))

(defun rimel-quail--deactivate ()
  "Clear Rimel state for the `rimel-quail' Quail package."
  (when (rimel-quail--current-package-p)
    (rimel--clear-state)
    (setq quail-guidance-str ""
          input-method-previous-message nil)
    (kill-local-variable 'input-method-use-echo-area)
    (kill-local-variable 'rimel-quail--composing)))

(quail-define-package
 rimel-quail--input-method-name
 "Chinese"
 rimel--title
 rimel-quail--guidance
 "Rime input method via Rimel and Quail."
 nil
 t
 nil
 t
 t
 nil
 nil
 nil
 #'rimel-quail--update-translation
 nil
 nil)

(quail-install-map (cons nil (rimel-quail--map "" 0)))

(when-let* ((slot (assoc rimel-quail--input-method-name input-method-alist)))
  (setcdr slot (list "Chinese"
                     #'quail-use-package
                     rimel--title
                     "Rimel - Rime input method via Quail"
                     "rimel-quail")))

(add-hook 'quail-activate-hook #'rimel-quail--activate)
(add-hook 'quail-deactivate-hook #'rimel-quail--deactivate)

(provide 'rimel-quail)

;;; rimel-quail.el ends here

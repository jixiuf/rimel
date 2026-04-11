;;; librimel.el --- Rime elisp binding    -*- lexical-binding: t; -*-

;; Author: jixiuf
;; URL: https://github.com/jixiuf/rimel
;; Version: 0.1.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: convenience, Chinese, input-method, rime

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Commentary:

;; A Emacs dynamic module provide librime bindings for Emacs.

;;; Code:
(require 'cl-lib)


(defgroup librimel nil
  "A Emacs dynamic module provide librime bindings."
  :group 'leim
  :prefix "librimel-")

(defcustom librimel-module-file nil
  "Librimel module file (librimel-core.so) on the system.
When it is nil, librime will auto search module in many path."
  :group 'librimel
  :type 'file)

(defcustom librimel-auto-build nil
  "If set to t, try build when module file not found in the system."
  :group 'librimel
  :type 'boolean)

;; ============================================================================
;; Session management note:
;; ============================================================================
;; - librimel-start returns the default session_id (an integer).
;; - Save this ID if you need to pass it to other functions.
;; - All functions below accept an optional SESSION-ID as the last argument.
;; - When SESSION-ID is nil, the default session is used.
;; - librimel-search is an exception, it always use a separate sessio to avoid
;; - interfering with current input
;; - Use librimel-create-session to create additional independent sessions.
;; - Use librimel-destroy-session to clean up sessions you created.
;; - WARNING: Do NOT destroy the default session returned by librimel-start.
;;
;; Example usage:
;;
;;  librimel-search= always uses a separate session to avoid interfering with
;;  the current input, so now these two have the same effect.
;;
;;   (librimel-search "zhongwen")
;;
;;   (let ((search-session (librimel-create-session)))
;;     (unwind-protect
;;         (librimel-search "zhongwen" nil search-session)
;;       (librimel-destroy-session search-session)))
;; ============================================================================
;; C function declarations for the byte-compiler.
;; use C-h f to see the args and documents of these fucnctions.
(declare-function librimel--start "ext:src/librimel-core.c") ;use librimel-start instead
(declare-function librimel-finalize "ext:src/librimel-core.c")
(declare-function librimel-create-session "ext:src/librimel-core.c")
(declare-function librimel-destroy-session "ext:src/librimel-core.c")
(declare-function librimel-search "ext:src/librimel-core.c")
(declare-function librimel-process-key "ext:src/librimel-core.c")
(declare-function librimel-get-input "ext:src/librimel-core.c")
(declare-function librimel-get-context "ext:src/librimel-core.c")
(declare-function librimel-get-status "ext:src/librimel-core.c")
(declare-function librimel-get-commit "ext:src/librimel-core.c")
(declare-function librimel-commit-composition "ext:src/librimel-core.c")
(declare-function librimel-clear-composition "ext:src/librimel-core.c")
(declare-function librimel-select-candidate "ext:src/librimel-core.c")
(declare-function librimel--select-schema "ext:src/librimel-core.c")
(declare-function librimel-get-schema-list "ext:src/librimel-core.c")
(declare-function librimel-get-user-config "ext:src/librimel-core.c")
(declare-function librimel-set-user-config "ext:src/librimel-core.c")
(declare-function librimel-get-schema-config "ext:src/librimel-core.c")
(declare-function librimel-set-schema-config "ext:src/librimel-core.c")
(declare-function librimel-get-sync-dir "ext:src/librimel-core.c")
(declare-function librimel-sync-user-data "ext:src/librimel-core.c")

(defun librimel--get-library-directory ()
  "Return the librimel package direcory."
  (let ((file (or (locate-library "librimel")
                  (locate-library "librimel-config"))))
    (when (and file (file-exists-p file))
      (file-name-directory file))))

(defun librimel--find-rime-data (parent-dirs &optional names)
  "Find directories listed in NAMES from PARENT-DIRS.

if NAMES is nil, \"rime-data\" as fallback."
  (cl-some (lambda (parent)
             (cl-some (lambda (name)
                        (let ((dir (expand-file-name name parent)))
                          (when (file-directory-p dir)
                            dir)))
                      (or names '("rime-data"))))
           (remove nil (if (fboundp 'xdg-data-dirs)
                           `(,@parent-dirs ,@(xdg-data-dirs))
                         parent-dirs))))

(defun librimel--get-shared-data-dir ()
  "Return user data directory."
  (cl-case system-type
        (gnu/linux
         (librimel--find-rime-data
          '("/usr/share/local"
            "/usr/share"
            ;; GuixOS support
            "~/.guix-home/profile/share"
            "~/.guix-profile/share"
            "/run/current-system/profile/share")))
        (darwin
         "/Library/Input Methods/Squirrel.app/Contents/SharedSupport")
        (windows-nt
         (librimel--find-rime-data
          (list
           (let ((file (executable-find "emacs")))
             (when (and file (file-exists-p file))
               (expand-file-name
                (concat (file-name-directory file)
                        "../share"))))
           "c:/" "d:/" "e:/" "f:/" "g:/")
          '("rime-data"
            "msys32/mingw32/share/rime-data"
            "msys64/mingw64/share/rime-data")))))

(defun librimel--get-user-data-dir ()
  "Return user data directory, create it if necessary."
  (let ((directory (expand-file-name (locate-user-emacs-file "rime/"))))
    (unless (file-directory-p directory)
      (make-directory directory))
    directory))

(defun librimel-build ()
  "Build librimel-core module."
  (let ((buffer (get-buffer-create "*librimel build help*"))
        (dir (librimel--get-library-directory)))
    (if (not (and dir (file-directory-p dir)))
        (message "Librimel: library directory is not found.")
      (message "Librimel: start build librimel-core module ...")
      (with-current-buffer buffer
        (erase-buffer)
        (insert "* Librimel build help")
        (unless module-file-suffix
          (insert "** Your emacs do not support dynamic module.\n"))
        (unless (executable-find "gcc")
          (insert "** You should install gcc."))
        (unless (executable-find "make")
          (insert "** You should install make.")))
      (let ((default-directory dir)
            (makefile
             (concat
              (if (eq system-type 'windows-nt)
                  "LIBRIME = -llibrime\n"
                "LIBRIME = -lrime\n")
              (concat
               "CC = gcc\n"
               "LDFLAGS = -shared\n"
               "SRC = src\n"
               "SOURCES = $(wildcard $(SRC)/*.c)\n"
               "OBJS = $(patsubst %.c, %.o, $(SOURCES))\n")
              (format "TARGET = $(SRC)/librimel-core%s\n" (or module-file-suffix ".so"))
              (let* ((path (replace-regexp-in-string
                            "/share/emacs/.*" ""
                            (or (locate-library "files") "/usr")))
                     (include-dir (concat (file-name-as-directory path) "include/")))
                (if (file-exists-p (concat include-dir "emacs-module.h"))
                    (concat "CFLAGS = -fPIC -O2 -Wall -I " include-dir "\n")
                  (concat "CFLAGS = -fPIC -O2 -Wall -I emacs-module/" (number-to-string emacs-major-version) "\n")))
              (let ((p (getenv "RIME_PATH")))
                (if p
                    (concat "CFLAGS += -I " p "/src/\n"
                            "LDFLAGS += -L " p "/build/lib/ \n"
                            "LDFLAGS += -L " p "/build/lib/Release/\n"
                            "LDFLAGS += -L " p "/dist/lib\n"
                            "LDFLAGS += -Wl,-rpath," p "/build/lib/\n"
                            "LDFLAGS += -Wl,-rpath," p "/build/lib/Release\n"
                            "LDFLAGS += -Wl,-rpath," p "/dist/lib\n")
                  "\n"))
              (concat
               ".PHONY:all objs\n"
               "all:$(TARGET)\n"
               "objs:$(OBJS)\n"
               "$(TARGET):$(OBJS)\n"
               "	$(CC) $(OBJS) $(LDFLAGS) $(LIBRIME) $(LIBS) -o $@"))))
        (with-temp-buffer
          (insert makefile)
          (write-region (point-min) (point-max) (concat dir "Makefile-librimel-build") nil :silent))
        (set-process-sentinel
         (start-process "librimel-build" "*librimel build*"
                        "make" "librimel-build")
         (lambda (proc _event)
           (when (eq 'exit (process-status proc))
             (if (= 0 (process-exit-status proc))
                 (progn (librimel-load)
                        (message "Librimel: load librimel-core module successful."))
               (pop-to-buffer buffer)
               (error "Librimel: building failed with exit code %d" (process-exit-status proc))))))))))

(defun librimel-load ()
  "Load librimel-core module."
  (unless (featurep 'librimel-core)
    (when (and librimel-module-file (file-exists-p librimel-module-file))
      (load-file librimel-module-file))
    (let* ((libdir (librimel--get-library-directory))
           (load-path (list libdir
                            (concat libdir "src")
                            (concat libdir "build"))))
      (require 'librimel-core nil t))
    (unless (featurep 'librimel-core)
      (if librimel-auto-build
          (librimel-build)
        (user-error "librimel: Fail to load librimel-core module, try to eval: (librimel-build)")))))

(defun librimel-start (&optional schema-id shared-dir user-dir)
  "Deploy librimel and return the session id if success."
  (when-let* ((user-dir (or user-dir (librimel--get-user-data-dir)))
              (shared-dir (or shared-dir (librimel--get-shared-data-dir)
                              user-dir))
              (session-id (librimel--start shared-dir user-dir)))
    (when schema-id (librimel-select-schema schema-id))
    (message "librimel: start with shared_dir: %S user_dir: %S"
             shared-dir user-dir)
    ;; librimel-start returns the default session_id.
    ;; Users can save this if they need to track it,
    ;; but it's managed internally.
    session-id))

;;; Utility functions with optional session-id support

(defun librimel-get-preedit (&optional session-id)
  "Get rime preedit from the session.
SESSION-ID optionally specifies which session to query (nil = default)."
  (let* ((context (librimel-get-context session-id))
         (composition (alist-get 'composition context))
         (preedit (alist-get 'preedit composition)))
    preedit))

(defun librimel-get-page-size (&optional session-id)
  "Get rime page size from the session.
SESSION-ID optionally specifies which session to query (nil = default)."
  (let* ((context (librimel-get-context session-id))
         (menu (alist-get 'menu context))
         (page-size (alist-get 'page-size menu)))
    page-size))

(defun librimel-select-candidate-crosspage (num &optional session-id)
  "Select rime candidate cross page.

NUM is the candidate number (1-indexed).
SESSION-ID optionally specifies which session to use (nil = default).

This function is different from `librimel-select-candidate': When
NUM > page size, `librimel-select-candidate' do nothing, while
this function will go to proper page then select a candidate."
  (let* ((page-size (librimel-get-page-size session-id))
         (position (- num 1))
         (page-n (/ position page-size))
         (n (% position page-size)))
    (librimel-process-key 65360 nil session-id) ; 回退到第一页
    (dotimes (_ page-n)
      (librimel-process-key 65366 nil session-id)) ; 发送翻页
    (librimel-select-candidate n session-id)))

(defun librimel-clear-commit (&optional session-id)
  "Clear the latest rime commit from the session.
SESSION-ID optionally specifies which session to use (nil = default).

NOTE: Second run `librimel-get-commit' will clear commit."
  (librimel-get-commit session-id))

(defun librimel-current-schema-id (&optional session-id)
  "Get current schema id from the session.
SESSION-ID optionally specifies which session to use (nil = default)."
  (when-let* ((status (librimel-get-status session-id)))
    (alist-get 'schema_id status)))

(defun librimel-select-schema (schema_id &optional session-id)
  "Select rime schema with SCHEMA_ID, Returns: t on success, nil otherwise."
  (let ((succ (librimel--select-schema schema_id session-id)))
    (unless succ
      (message "librimel: failed to select schema: %S" schema_id))
    succ))

(defun librimel--finalize-on-exit ()
  "Finalize librime when Emacs is about to exit."
  (when (featurep 'librimel-core)
    (ignore-errors (librimel-finalize))))

(add-hook 'kill-emacs-hook #'librimel--finalize-on-exit)

(librimel-load)

(provide 'librimel)

;;; librimel.el ends here

;;; librimel.el --- Rime elisp binding    -*- lexical-binding: t; -*-

;; Author: jixiuf
;; URL: https://github.com/jixiuf/rimel
;; Version: 0.1.1
;; Package-Requires: ((emacs "25.1"))
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

(defcustom librimel-after-start-hook nil
  "List of functions to be called after librimel start."
  :group 'librimel
  :type 'hook)

(make-obsolete-variable 'after-librimel-load-hook 'librimel-after-start-hook "2019-12-13")

(defcustom librimel-module-file nil
  "Librimel module file on the system.
When it is nil, librime will auto search module in many path."
  :group 'librimel
  :type 'file)

(defcustom librimel-shared-data-dir nil
  "Data directory on the system.

More info: https://github.com/rime/home/wiki/SharedData"
  :group 'librimel
  :type 'file)

(defcustom librimel-user-data-dir
  (locate-user-emacs-file "rime/")
  "Data directory on the user home directory."
  :group 'librimel
  :type 'file)

(defcustom librimel-auto-build nil
  "If set to t, try build when module file not found in the system."
  :group 'librimel
  :type 'boolean)

(defvar librimel-select-schema-timer nil
  "Timer used by `librimel-select-schema'.")

(defvar librimel-current-schema nil
  "The rime schema set by `librimel-select-schema'.")

(declare-function librimel-clear-composition "ext:src/librimel-core.c")
(declare-function librimel-commit-composition "ext:src/librimel-core.c")
(declare-function librimel-finalize "ext:src/librimel-core.c")
(declare-function librimel-get-commit "ext:src/librimel-core.c")
(declare-function librimel-get-context "ext:src/librimel-core.c")
(declare-function librimel-get-input "ext:src/librimel-core.c")
(declare-function librimel-get-schema-config "ext:src/librimel-core.c")
(declare-function librimel-get-schema-list "ext:src/librimel-core.c")
(declare-function librimel-get-status "ext:src/librimel-core.c")
(declare-function librimel-get-sync-dir "ext:src/librimel-core.c")
(declare-function librimel-get-user-config "ext:src/librimel-core.c")
(declare-function librimel-process-key "ext:src/librimel-core.c")
(declare-function librimel-search "ext:src/librimel-core.c")
(declare-function librimel-select-candidate "ext:src/librimel-core.c")
(declare-function librimel-select-schema "ext:src/librimel-core.c")
(declare-function librimel-set-schema-config "ext:src/librimel-core.c")
(declare-function librimel-set-user-config "ext:src/librimel-core.c")
(declare-function librimel-start "ext:src/librimel-core.c")
(declare-function librimel-sync-user-data "ext:src/librimel-core.c")

(defun librimel-get-library-directory ()
  "Return the librimel package direcory."
  (let ((file (or (locate-library "librimel")
                  (locate-library "librimel-config"))))
    (when (and file (file-exists-p file))
      (file-name-directory file))))

(defun librimel-find-rime-data (parent-dirs &optional names)
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

(defun librimel-get-shared-data-dir ()
  "Return user data directory."
  (or librimel-shared-data-dir
      ;; Guess
      (cl-case system-type
        ('gnu/linux
         (librimel-find-rime-data
          '("/usr/share/local"
            "/usr/share"
            ;; GuixOS support
            "~/.guix-home/profile/share"
            "~/.guix-profile/share"
            "/run/current-system/profile/share")))
        ('darwin
         "/Library/Input Methods/Squirrel.app/Contents/SharedSupport")
        ('windows-nt
         (librimel-find-rime-data
          (list
           (let ((file (executable-find "emacs")))
             (when (and file (file-exists-p file))
               (expand-file-name
                (concat (file-name-directory file)
                        "../share"))))
           "c:/" "d:/" "e:/" "f:/" "g:/")
          '("rime-data"
            "msys32/mingw32/share/rime-data"
            "msys64/mingw64/share/rime-data"))))
      ;; Fallback to user data dir.
      (librimel-get-user-data-dir)))

(defun librimel-get-user-data-dir ()
  "Return user data directory, create it if necessary."
  (let ((directory (expand-file-name librimel-user-data-dir)))
    (unless (file-directory-p directory)
      (make-directory directory))
    directory))

(declare-function w32-shell-execute "w32fns")

(defun librimel-open-directory (directory)
  "Open DIRECTORY with external app."
  (let ((directory (expand-file-name directory)))
    (when (file-directory-p directory)
      (cond ((string-equal system-type "windows-nt")
             (w32-shell-execute "open" directory))
            ((string-equal system-type "darwin")
             (concat "open " (shell-quote-argument directory)))
            ((string-equal system-type "gnu/linux")
             (let ((process-connection-type nil))
               (start-process "" nil "xdg-open" directory)))))))

;;;###autoload
(defun librimel-open-user-data-dir ()
  "Open user data dir with external app."
  (interactive)
  (librimel-open-directory (librimel-get-user-data-dir)))

;;;###autoload
(defun librimel-open-shared-data-dir ()
  "Open shared data dir with external app."
  (interactive)
  (librimel-open-directory (librimel-get-shared-data-dir)))

;;;###autoload
(defun librimel-open-package-directory ()
  "Open librimel library directory with external app."
  (interactive)
  (librimel-open-directory (librimel-get-library-directory)))

;;;###autoload
(defun librimel-open-package-readme ()
  "Open librimel library README.org."
  (interactive)
  (find-file (concat (librimel-get-library-directory) "README.org")))

;;;###autoload
(defun librimel-build ()
  "Build librimel-core module."
  (interactive)
  (let ((buffer (get-buffer-create "*librimel build help*"))
        (dir (librimel-get-library-directory)))
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

(defun librimel-workable-p ()
  "Return t when librimel can work."
  (featurep 'librimel-core))

(defun librimel--start ()
  "Start librimel."
  (let ((shared-dir (librimel-get-shared-data-dir))
        (user-dir (librimel-get-user-data-dir)))
    (message "Librimel: start with shared dir: %S" shared-dir)
    (message "Librimel: start with user dir: %S" user-dir)
    (message "")
    (librimel-start shared-dir user-dir)
    (when librimel-current-schema
      (librimel-try-select-schema librimel-current-schema))
    (run-hooks 'librimel-after-start-hook)))

;;;###autoload
(defun librimel-load ()
  "Load librimel-core module."
  (interactive)
  (when (and librimel-module-file
             (file-exists-p librimel-module-file)
             (not (featurep 'librimel-core)))
    (load-file librimel-module-file))
  (let* ((libdir (librimel-get-library-directory))
         (load-path
          (list libdir
                (concat libdir "src")
                (concat libdir "build"))))
    (require 'librimel-core nil t))
  (if (featurep 'librimel-core)
      (librimel--start)
    (if librimel-auto-build
        (librimel-build)
      (let ((buf (get-buffer-create "*librimel load*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert "Librimel: Fail to load librimel-core module, try to run command: (librimel-build)")
          (goto-char (point-min)))
        (pop-to-buffer buf)))))

(librimel-load)

(defun librimel-get-preedit ()
  "Get rime preedit."
  (let* ((context (librimel-get-context))
         (composition (alist-get 'composition context))
         (preedit (alist-get 'preedit composition)))
    preedit))

(defun librimel-get-page-size ()
  "Get rime page size from context."
  (let* ((context (librimel-get-context))
         (menu (alist-get 'menu context))
         (page-size (alist-get 'page-size menu)))
    page-size))

(defun librimel-select-candidate-crosspage (num)
  "Select rime candidate cross page.

This function is different from `librimel-select-candidate', When
NUM > page size, `librimel-select-candidate' do nothing, while
this function will go to proper page then select a candidate."
  (let* ((page-size (librimel-get-page-size))
         (position (- num 1))
         (page-n (/ position page-size))
         (n (% position page-size)))
    (librimel-process-key 65360) ;回退到第一页
    (dotimes (_ page-n)
      (librimel-process-key 65366)) ;发送翻页
    (librimel-select-candidate n)))

(defun librimel-clear-commit ()
  "Clear the lastest rime commit."
  ;; NEED IMPROVE: Second run `librimel-get-commit' will clear commit.
  (librimel-get-commit))

;;;###autoload
(defun librimel-deploy()
  "Deploy librimel to affect config file change."
  (interactive)
  (librimel-finalize)
  (librimel--start))

;;;###autoload
(defun librimel-set-page-size (page-size)
  "Set rime page-size to PAGE-SIZE or by default 10.
you also need to call `librimel-deploy' to make it take affect
you only need to do this once."
  (interactive "P")
  (librimel-set-user-config "default.custom" "patch/menu/page_size" (or page-size 10) "int"))

(defun librimel-try-select-schema (schema_id)
  "Try to select rime schema with SCHEMA_ID."
  (let ((n 1))
    (setq librimel-current-schema schema_id)
    (when (featurep 'librimel-core)
      (when librimel-select-schema-timer
        (cancel-timer librimel-select-schema-timer))
      (setq librimel-select-schema-timer
            (run-with-timer
             1 2
             (lambda ()
               (let ((id (alist-get 'schema_id (ignore-errors (librimel-get-status)))))
                 (cond ((or (equal id schema_id)
                            (> n 10))
                        (if (> n 10)
                            (message "Librimel: fail to select schema %S." schema_id)
                          (message "Librimel: success to select schema %S." schema_id))
                        (message "")
                        (cancel-timer librimel-select-schema-timer)
                        (setq librimel-select-schema-timer nil))
                       (t (message "Librimel: try (n=%s) to select schema %S ..." n schema_id)
                          (ignore-errors (librimel-select-schema schema_id))))
                 (setq n (+ n 1))))))
      t)))

;;;###autoload
(defun librimel-select-schema-interactive ()
  "Select a rime schema interactive."
  (interactive)
  (let ((schema-list
         (mapcar (lambda (x)
                   (cons (format "%s(%s)" (cadr x) (car x))
                         (car x)))
                 (ignore-errors (librimel-get-schema-list)))))
    (if schema-list
        (let* ((schema-name (completing-read "Rime schema: " schema-list))
               (schema (alist-get schema-name schema-list nil nil #'equal)))
          (librimel-try-select-schema schema))
      (message "Librimel: no schema has been found, ignore."))))

;;;###autoload
(defun librimel-sync ()
  "Sync rime user data.
User should specify sync_dir in installation.yaml file of
`librimel-user-data-dir' directory."
  (interactive)
  (librimel-sync-user-data))

(provide 'librimel)

;;; librimel.el ends here

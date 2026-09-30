;;; init.el -*- lexical-binding: t; -*-

;;; straight.el

(defvar bootstrap-version)

(let ((bootstrap-file
       (expand-file-name
        "straight/repos/straight.el/bootstrap.el"
        (or (bound-and-true-p straight-base-dir)
            user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent
         'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))


;;; Packages

(straight-use-package 'exec-path-from-shell)
(straight-use-package 'doom-themes)
(straight-use-package 'vterm)
(straight-use-package 'magit)


;;; Environment

(require 'exec-path-from-shell)

(when (memq window-system '(mac ns x pgtk))
  (exec-path-from-shell-initialize))


;;; UI

(require 'which-key)
(which-key-mode 1)

(require 'doom-themes)

(setq doom-themes-enable-bold t
      doom-themes-enable-italic t)

(load-theme 'doom-one t)


;;; Org

(setq org-directory
      "~/Library/Mobile Documents/com~apple~CloudDocs/org")

(setq org-agenda-files
      (list (expand-file-name "main.org" org-directory)))

(defun my/open-org-main ()
  (interactive)
  (find-file
   (expand-file-name "main.org" org-directory)))

(global-set-key (kbd "C-c o") #'my/open-org-main)

;;; init.el ends here

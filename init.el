;;; init.el --- Emacs Configuration -*- lexical-binding: t; -*-

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
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)

(setq straight-use-package-by-default t)

(use-package exec-path-from-shell
  :config (when (memq window-system '(mac ns x pgtk))
	    (exec-path-from-shell-initialize)))

(use-package which-key
  :straight nil
  :config
  (which-key-mode))

(use-package doom-themes
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (load-theme 'doom-one t))

(use-package vterm)

(use-package magit)

(use-package org
  :straight nil
  :init
  (setq org-directory "~/Library/Mobile Documents/com~apple~CloudDocs/org"
        org-agenda-files
        (list (expand-file-name "main.org" org-directory)))
  :preface
  (defun my/open-org-main ()
    (interactive)
    (find-file (expand-file-name "main.org" org-directory)))
  :bind
  (("C-c o" . my/open-org-main)))

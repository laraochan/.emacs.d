;;; init.el --- My Emacs configuration -*- lexical-binding: t; -*-

(require 'package)

(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/")
             t)

(require 'use-package)

(add-to-list 'load-path (locate-user-emacs-file "lisp"))

(use-package emacs
  :ensure nil
  :custom
  (tab-always-indent 'complete)
  (completion-cycle-threshold 3)
  (read-extended-command-predicate
   #'command-completion-default-include-p)
  (enable-recursive-minibuffers t)
  (history-length 1000)
  (history-delete-duplicates t)
  (frame-resize-pixelwise t)
  (scroll-preserve-screen-position t)
  (scroll-conservatively 101)
  (ring-bell-function #'ignore)
  (use-dialog-box nil)
  (use-file-dialog nil)
  :config
  (setq-default indent-tabs-mode nil)
  (delete-selection-mode 1)
  (show-paren-mode 1))

(use-package cus-edit
  :ensure nil
  :custom
  ;; Keep Customize-generated settings out of init.el.
  (custom-file (locate-user-emacs-file "custom.el"))
  :config
  (when (file-exists-p custom-file)
    (load custom-file nil t)))

(use-package autorevert
  :ensure nil
  :custom
  (global-auto-revert-non-file-buffers t)
  :init
  (global-auto-revert-mode 1))

(use-package saveplace
  :ensure nil
  :init
  (save-place-mode 1))

(use-package recentf
  :ensure nil
  :init
  (recentf-mode 1))

(use-package savehist
  :ensure nil
  :init
  (savehist-mode 1))

(use-package exec-path-from-shell
  :ensure t
  :if (memq window-system '(mac ns))
  :config
  (exec-path-from-shell-initialize))

(use-package doom-themes
  :ensure t
  :config
  (load-theme 'doom-solarized-dark-high-contrast t))

(use-package which-key
  :ensure nil
  :custom
  (which-key-idle-delay 0.5)
  :init
  (which-key-mode 1))

(use-package vterm
  :ensure t
  :commands vterm
  :preface
  (defun my/vterm-disable-kill-query ()
    (when-let ((process (get-buffer-process (current-buffer))))
      (set-process-query-on-exit-flag process nil)))
  :custom
  (vterm-kill-buffer-on-exit t)
  :hook
  (vterm-mode . my/vterm-disable-kill-query)
  :bind
  (:map vterm-mode-map
        ("M-0" . digit-argument)
        ("M-1" . digit-argument)
        ("M-2" . digit-argument)
        ("M-3" . digit-argument)
        ("M-4" . digit-argument)
        ("M-5" . digit-argument)
        ("M-6" . digit-argument)
        ("M-7" . digit-argument)
        ("M-8" . digit-argument)
        ("M-9" . digit-argument)
        ("M--" . negative-argument)
        ("C-q" . vterm-send-next-key)))

(use-package projectile
  :ensure t
  :preface
  (defun my/projectile-vterm (&optional number)
    "Open numbered vterm for a Projectile project."
    (interactive "p")
    (if-let* ((root (projectile-project-root)))
        (let* ((name (projectile-project-name))
               (number (or number 1))
               (buffer-name (format "*vterm:%s:%d*" name number))
               (buffer (get-buffer buffer-name)))
          (cond
           ((and buffer
                 (process-live-p (get-buffer-process buffer)))
            (pop-to-buffer buffer))
           (buffer
            (kill-buffer buffer)
            (let ((default-directory root))
              (vterm buffer-name)))
           (t
            (let ((default-directory root))
              (vterm buffer-name)))))
      ;; Outside a project, select one first and run this command there.
      (let ((projectile-switch-project-action
             (lambda ()
               (my/projectile-vterm number))))
        (projectile-switch-project))))
  :init
  (projectile-mode 1)
  :bind-keymap
  ("C-x p" . projectile-command-map)
  :bind
  (:map projectile-command-map
        ("t" . my/projectile-vterm)))

(use-package corfu
  :ensure t
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.1)
  (corfu-auto-prefix 2)
  (corfu-cycle t)
  :init
  (global-corfu-mode 1))

(use-package corfu-popupinfo
  :ensure nil
  :after corfu
  :custom
  (corfu-popupinfo-delay '(0.6 . 0.2))
  (corfu-popupinfo-max-width 80)
  (corfu-popupinfo-max-height 20)
  (corfu-popupinfo-hide t)
  (corfu-popupinfo-direction '(right left vertical))
  :init
  (corfu-popupinfo-mode 1))

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  ;; File paths are easier to complete segment-by-segment than with Orderless.
  (completion-category-overrides
   '((file (styles partial-completion))))
  (completion-category-defaults nil))

(use-package cape
  :ensure t
  :bind
  (("C-c p p" . completion-at-point)
   ("C-c p f" . cape-file)
   ("C-c p d" . cape-dabbrev)))

(use-package vertico
  :ensure t
  :custom
  (vertico-cycle t)
  :init
  (vertico-mode 1))

(use-package marginalia
  :ensure t
  :init
  (marginalia-mode 1))

(use-package consult
  :ensure t
  :custom
  (xref-show-xrefs-function #'consult-xref)
  (xref-show-definitions-function #'consult-xref)
  :bind
  (([remap switch-to-buffer] . consult-buffer)
   ([remap project-switch-to-buffer] . consult-project-buffer)
   ([remap projectile-switch-to-buffer] . consult-project-buffer)
   ([remap goto-line] . consult-goto-line)
   ([remap imenu] . consult-imenu)
   ("C-s" . consult-line)
   ("M-g f" . consult-flymake)
   ("M-s r" . consult-ripgrep)))

(use-package embark
  :ensure t
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)
   ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :ensure t
  :after (embark consult))

(use-package treesit
  :ensure nil
  :custom
  (treesit-font-lock-level 4)
  :config
  (setq treesit-language-source-alist
        '((javascript
           "https://github.com/tree-sitter/tree-sitter-javascript")
          (typescript
           "https://github.com/tree-sitter/tree-sitter-typescript"
           "master"
           "typescript/src")
          (tsx
           "https://github.com/tree-sitter/tree-sitter-typescript"
           "master"
           "tsx/src")
          (rust
           "https://github.com/tree-sitter/tree-sitter-rust")))
  
  (dolist (entry treesit-language-source-alist)
    (let ((language (car entry)))
      (unless (treesit-language-available-p language)
        (message "Installing tree-sitter grammar: %s" language)
        (treesit-install-language-grammar language)))))

(use-package js
  :ensure nil
  :mode
  (("\\.js\\'" . js-ts-mode)
   ("\\.jsx\\'" . js-ts-mode)))

(use-package typescript-ts-mode
  :ensure nil
  :mode
  (("\\.ts\\'" . typescript-ts-mode)
   ("\\.tsx\\'" . tsx-ts-mode)))

(use-package rust-ts-mode
  :ensure nil
  :mode
  ("\\.rs\\'" . rust-ts-mode))

(use-package haskell-mode
  :ensure t
  :mode
  ("\\.hs\\'" . haskell-mode))

(use-package markdown-mode
  :ensure t
  :commands
  (markdown-mode gfm-view-mode))

(use-package eldoc
  :ensure nil
  :custom
  ;; Show diagnostics, signatures and hover documentation together.
  (eldoc-documentation-strategy #'eldoc-documentation-compose)
  ;; Keep hover useful without letting the echo area grow too much.
  (eldoc-echo-area-use-multiline-p 3))

(use-package flymake
  :ensure nil
  :custom
  ;; Show the most important diagnostic directly beside the code.
  (flymake-show-diagnostics-at-end-of-line 'short)
  :bind
  (:map flymake-mode-map
        ("M-n" . flymake-goto-next-error)
        ("M-p" . flymake-goto-prev-error)))

(use-package eglot
  :ensure nil
  :hook
  ((typescript-ts-mode . eglot-ensure)
   (tsx-ts-mode . eglot-ensure)
   (js-ts-mode . eglot-ensure)
   (rust-ts-mode . eglot-ensure)
   (haskell-mode . eglot-ensure))
  :bind
  (:map eglot-mode-map
        ("C-c l r" . eglot-rename)
        ("C-c l a" . eglot-code-actions)
        ("C-c l f" . eglot-format-buffer)))

(use-package flymake-eslint
  :vc (:url "https://github.com/laraochan/flymake-eslint" :rev :newest)
  :hook
  (((js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode)
    . flymake-eslint-enable)))

(use-package flymake-oxlint
  :vc (:url "https://github.com/laraochan/flymake-oxlint" :rev :newest)
  :hook
  (((js-mode js-ts-mode typescript-mode typescript-ts-mode tsx-ts-mode)
    . flymake-oxlint-enable)))

(use-package magit
  :ensure t)

(use-package diff-hl
  :ensure t
  :init
  (global-diff-hl-mode 1)
  :hook
  ((dired-mode . diff-hl-dired-mode)
   (magit-post-refresh . diff-hl-magit-post-refresh)))

(use-package agent-shell
  :ensure t)

(use-package perspective
  :ensure t
  :custom
  (persp-mode-prefix-key (kbd "C-c w"))
  :bind
  (("C-c w w" . persp-switch)
   ("C-c w n" . persp-next)
   ("C-c w p" . persp-prev)
   ("C-c w k" . persp-kill))
  :init
  (persp-mode 1))

;;; init.el ends here

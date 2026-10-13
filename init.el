;;; init.el -*- lexical-binding: t; -*-

;;; straight
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

;;; custom
(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file 'noerror 'nomessage)

;;; global
(set-face-attribute 'default nil :height 180)
(setq inhibit-startup-screen t
      use-short-answers t
      use-dialog-box nil
      ring-bell-function #'ignore)

;;; editing
(setq-default indent-tabs-mode nil
              tab-width 4)
(delete-selection-mode 1)
(electric-pair-mode 1)
(show-paren-mode 1)
(column-number-mode 1)
(add-hook 'prog-mode-hook
          (lambda ()
            (setq-local truncate-lines t)))

;;; files
(global-auto-revert-mode 1)
;; バックアップ・自動保存の置き場所
(let ((backup-dir (locate-user-emacs-file "backup/"))
      (auto-save-dir (locate-user-emacs-file "backup/auto-save/")))
  (make-directory backup-dir t)
  (make-directory auto-save-dir t)
  (setq backup-directory-alist
        `(("." . ,backup-dir))
        auto-save-file-name-transforms
        `((".*" ,auto-save-dir t))
        auto-save-list-file-prefix
        (expand-file-name ".saves-" auto-save-dir)))
;; バックアップはコピーで作成し、世代数を制限
(setq backup-by-copying t
      version-control t
      kept-new-versions 5
      kept-old-versions 2
      delete-old-versions t)

;;; history
(setq history-length 1000
      history-delete-duplicates t
      recentf-max-saved-items 100)
(savehist-mode 1)
(save-place-mode 1)
(recentf-mode 1)

;;; window
(winner-mode 1)

;; exec-path-from-shell
(straight-use-package 'exec-path-from-shell)
(require 'exec-path-from-shell)
(when (memq window-system '(mac ns x))
  (exec-path-from-shell-initialize))

;;; colorscheme
(straight-use-package 'tron-legacy-theme)
(load-theme 'tron-legacy t)

;;; which-key
(require 'which-key)
(which-key-mode 1)

;;; agent-shell
(straight-use-package 'agent-shell)
(require 'agent-shell)
(with-eval-after-load 'project
  (keymap-set project-prefix-map "a" #'agent-shell)
  (add-to-list 'project-switch-commands
               '(agent-shell "Agent shell") t))

;;; ghostel
(straight-use-package 'ghostel)
(require 'ghostel)
(with-eval-after-load 'project
  (keymap-set project-prefix-map "m" #'ghostel-project)
  (keymap-set project-prefix-map "M" #'ghostel-project-list-buffers)

  (add-to-list 'project-switch-commands
               '(ghostel-project "Ghostel") t)
  (add-to-list 'project-switch-commands
               '(ghostel-project-list-buffers "Ghostel buffers") t))

;;; treesit
(require 'treesit)
(setq treesit-font-lock-level 4
      treesit-language-source-alist
      '((json "https://github.com/tree-sitter/tree-sitter-json")
	    (yaml "https://github.com/ikatyang/tree-sitter-yaml")
	    (toml "https://github.com/ikatyang/tree-sitter-toml")
	    (haskell "https://github.com/tree-sitter/tree-sitter-haskell")
	    (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
	    (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
	    (php "https://github.com/tree-sitter/tree-sitter-php" "master" "php/src")
	    (php_only "https://github.com/tree-sitter/tree-sitter-php" "master" "php_only/src")
	    (phpdoc "https://github.com/claytonrcarter/tree-sitter-phpdoc")
        (html "https://github.com/tree-sitter/tree-sitter-html")
        (css "https://github.com/tree-sitter/tree-sitter-css")))
(defun my/treesit-install-grammars ()
  "未導入の Tree-sitter 文法をインストールする。"
  (interactive)
  (dolist (entry treesit-language-source-alist)
    (let ((lang (car entry)))
      (unless (treesit-language-available-p lang)
        (treesit-install-language-grammar lang)))))

;; corfu
(straight-use-package 'corfu)
(require 'corfu)
(setq corfu-auto t
      corfu-auto-delay 0.2
      corfu-auto-prefix 2
      corfu-cycle t
      corfu-preselect 'prompt)
;; 候補が選択済みなら確定、それ以外は通常の動作
(dolist (key '("RET" "<return>"))
  (keymap-set corfu-map key
	          '(menu-item "" nil
			              :filter
			              (lambda (&optional _)
			                (when (>= corfu--index 0)
			                  #'corfu-insert)))))
(add-hook 'prog-mode-hook
	      (lambda ()
	        (corfu-mode 1)
	        (corfu-popupinfo-mode 1)))
(defun my/text-code-completion-setup ()
  (corfu-mode 1)
  (corfu-popupinfo-mode 1))

;;; orderless
(straight-use-package 'orderless)
(require 'orderless)
(setq completion-styles '(orderless basic)
      completion-category-overrides '((file (styles partial-completion)))
      completion-category-defaults nil
      completion-pcm-leading-wildcard t)

;;; cape
(straight-use-package 'cape)
(require 'cape)
(add-hook 'completion-at-point-functions #'cape-file t)
(add-hook 'completion-at-point-functions #'cape-dabbrev t)
(defun my/elisp-block-completion-setup ()
  (add-hook 'completion-at-point-functions
            #'cape-elisp-block nil t)
  (my/text-code-completion-setup))
(add-hook 'org-mode-hook #'my/elisp-block-completion-setup)
(add-hook 'markdown-mode-hook #'my/elisp-block-completion-setup)

;;; vertico
(straight-use-package 'vertico)
(require 'vertico)
(vertico-mode 1)

;;; marginalia
(straight-use-package 'marginalia)
(require 'marginalia)
(marginalia-mode 1)

;;; consult
(straight-use-package 'consult)
(require 'consult)
(define-key global-map [remap switch-to-buffer]
            #'consult-buffer)
(define-key global-map [remap switch-to-buffer-other-window]
            #'consult-buffer-other-window)
(define-key global-map [remap switch-to-buffer-other-frame]
            #'consult-buffer-other-frame)
(define-key global-map [remap project-switch-to-buffer]
            #'consult-project-buffer)
(define-key global-map [remap goto-line]
            #'consult-goto-line)
(define-key global-map [remap imenu]
            #'consult-imenu)
(define-key global-map [remap yank-pop]
            #'consult-yank-pop)
(define-key global-map [remap isearch-forward]
            #'consult-line)
(define-key global-map [remap project-find-regexp]
            #'consult-ripgrep)
(keymap-global-set "M-g i" #'consult-imenu)
(keymap-global-set "M-g f" #'consult-flymake)
(keymap-set minibuffer-local-map "C-r" #'consult-history)
(setq xref-show-xrefs-function #'consult-xref
      xref-show-definitions-function #'consult-xref)

;;; magit
(straight-use-package 'magit)

;;; diff-hl
(straight-use-package 'diff-hl)
(require 'diff-hl)
(global-diff-hl-mode)
(with-eval-after-load 'magit
  (add-hook 'magit-post-refresh-hook
            #'diff-hl-magit-post-refresh))

;;; nyan-mode
(straight-use-package 'nyan-mode)
(nyan-mode 1)

;;; eglot
(require 'eglot)
(setq eglot-autoshutdown t)
(add-to-list 'eglot-server-programs
             '(haskell-mode . ("haskell-language-server-wrapper" "--lsp")))
(add-to-list 'eglot-server-programs
             '(((typescript-ts-mode :language-id "typescript")
                (tsx-ts-mode :language-id "typescriptreact")) . ("vtsls" "--stdio")))
(add-to-list 'eglot-server-programs
             '(php-ts-mode . ("phpantom_lsp")))

;;; haskell-mode
(straight-use-package 'haskell-mode)
(add-hook 'haskell-mode-hook #'eglot-ensure)

;;; markdown-mode
(straight-use-package 'markdown-mode)
(add-hook 'markdown-mode-hook #'visual-line-mode)

;;; typescript-ts-mode / tsx-ts-mode
(require 'typescript-ts-mode)
(add-to-list 'auto-mode-alist
             '("\\.ts\\'" . typescript-ts-mode))
(add-to-list 'auto-mode-alist
             '("\\.tsx\\'" . tsx-ts-mode))
(add-hook 'typescript-ts-mode-hook #'eglot-ensure)
(add-hook 'tsx-ts-mode-hook #'eglot-ensure)

;;; php-ts-mode
(require 'php-ts-mode)
(add-to-list 'auto-mode-alist
             '("\\.php\\'" . php-ts-mode))
(add-hook 'php-ts-mode-hook #'eglot-ensure)

;;; html-ts-mode
(require 'html-ts-mode)
(add-to-list 'major-mode-remap-alist
             '(html-mode . html-ts-mode))
(add-to-list 'major-mode-remap-alist
             '(mhtml-mode . html-ts-mode))
(add-hook 'html-ts-mode-hook #'my/text-code-completion-setup)

;;; css-ts-mode
(require 'css-mode)
(add-to-list 'major-mode-remap-alist
             '(css-mode . css-ts-mode))

;;; json-ts-mode
(require 'json-ts-mode)
(add-to-list 'major-mode-remap-alist
             '(js-json-mode . json-ts-mode))

;;; yaml-ts-mode
(require 'yaml-ts-mode)
(add-to-list 'auto-mode-alist
             '("\\.ya?ml\\'" . yaml-ts-mode))
(add-hook 'yaml-ts-mode-hook #'my/text-code-completion-setup)

;;; toml-ts-mode
(require 'toml-ts-mode)
(add-to-list 'major-mode-remap-alist
             '(conf-toml-mode . toml-ts-mode))
(add-hook 'toml-ts-mode-hook #'my/text-code-completion-setup)

;;; project
(require 'project)

;;; workspace
(straight-use-package 'perspective)
(require 'perspective)
(setopt persp-mode-prefix-key (kbd "C-c w"))
(setq persp-show-modestring 'header
      persp-modestring-short nil)
(persp-mode 1)
(consult-customize consult-source-buffer
                   :hidden t
                   :default nil)
(add-to-list 'consult-buffer-sources persp-consult-source)
;; プロジェクト選択後、操作メニューを出す前に workspace を切り替える。
;; Treemacs の表示は各 workspace のウィンドウ配置に任せる。
(defun my/project-switch-workspace (original dir)
  "DIR の workspace に切り替え、標準のプロジェクト操作を実行する。"
  (let* ((root (file-name-as-directory
                (file-truename (project-root (project-current t dir)))))
         (default-directory root)
         (name (abbreviate-file-name (directory-file-name root))))
    (persp-switch name)
    (funcall original dir)))
;; 再評価時にも以前の Treemacs 更新処理を残さない。
(advice-remove 'project-switch-project #'my/project-switch-update-treemacs)
(advice-add 'project-switch-project :around #'my/project-switch-workspace)

;;; doom-modeline
(straight-use-package 'doom-modeline)
(require 'doom-modeline)
(doom-modeline-mode 1)

;;; treemacs
(straight-use-package 'treemacs)
(require 'treemacs)
(setq treemacs-width 30
      treemacs-show-hidden-files t)
(treemacs-follow-mode 1)
(treemacs-filewatch-mode 1)
(treemacs-git-mode 'simple)
(keymap-global-set "C-c t" #'treemacs)
(keymap-global-set "M-0" #'treemacs-select-window)
(keymap-global-set "C-c T" #'treemacs-find-file)
(with-eval-after-load 'project
  (keymap-set project-prefix-map "t"
              #'treemacs-add-and-display-current-project))

(straight-use-package 'treemacs-perspective)
(require 'treemacs-perspective)
(treemacs-set-scope-type 'Perspectives)

(straight-use-package 'treemacs-magit)
(with-eval-after-load 'magit
  (require 'treemacs-magit))

;;; org-mode
(add-hook 'markdown-mode-hook #'visual-line-mode)

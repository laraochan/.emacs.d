;;; early-init.el -*- lexical-binding: t; -*-

;;; package
(setq package-enable-at-startup nil)

;;; appearance
(menu-bar-mode 1)
(tool-bar-mode -1)
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))

(setq frame-resize-pixelwise t)

;; ウィンドウ全体を85%の不透明度にする
(add-to-list 'default-frame-alist '(alpha . (85 . 85)))

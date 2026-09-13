;;; my-flymake-eslint.el --- eslint diagnostics for Flymake -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Larao
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Author: Larao
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: languages, tools

;;; Commentary:

;; Add `my-flymake-eslint-backend' to `flymake-diagnostic-functions'
;; buffer-locally, then enable `flymake-mode'.  Supports file-visiting
;; JavaScript, TypeScript, JSX and TSX buffers; parser/configuration support
;; is supplied by the installed linter.  Remote and non-file buffers are
;; skipped.  No other personal configuration or third-party Lisp is needed.
;;
;; The nearest executable node_modules/.bin/eslint in an ancestor directory
;; takes precedence over PATH.  Customize `my-flymake-eslint-executable'
;; to override discovery.  Missing executables yield no diagnostics; install
;; the tool and call `flymake-start' to retry.
;; Unmodified file names are passed with --stdin-filename; no files are written.

;;; Code:

(require 'flymake)
(require 'json)
(require 'seq)
(require 'subr-x)

(defgroup my-flymake-eslint nil
  "ESLint diagnostics for Flymake."
  :group 'flymake
  :prefix "my-flymake-eslint-")

(defcustom my-flymake-eslint-executable nil
  "Explicit eslint executable name or absolute path, or nil to discover it.
Automatic discovery prefers ancestor node_modules/.bin/eslint executables,
then searches the variable `exec-path'.  An explicit value bypasses
automatic discovery."
  :type '(choice (const :tag "Automatic" nil) string)
  :group 'my-flymake-eslint)

(defcustom my-flymake-eslint-arguments nil
  "Additional eslint command-line arguments, as a list of strings.
Use only lint configuration options, not output, fix or file selection flags."
  :type '(repeat string)
  :group 'my-flymake-eslint)

(defvar-local my-flymake-eslint--process nil
  "Current lint process for this buffer.")

(defun my-flymake-eslint--executable ()
  "Find the configured executable for the current directory."
  (if my-flymake-eslint-executable
      (executable-find my-flymake-eslint-executable)
    (let ((root (locate-dominating-file
                 default-directory
                 (lambda (dir)
                   (let ((file (expand-file-name "node_modules/.bin/eslint" dir)))
                     (and (file-regular-p file) (file-executable-p file)))))))
      (if root
          (expand-file-name "node_modules/.bin/eslint" root)
        (executable-find "eslint")))))

(defun my-flymake-eslint--cleanup (process)
  "Dispose of PROCESS and its owned resources."
  (set-process-sentinel process #'ignore)
  (when (process-live-p process) (delete-process process))
  (dolist (buffer (list (process-buffer process)
                        (process-get process 'stderr)))
    (when (buffer-live-p buffer)
      (let ((pipe (get-buffer-process buffer)))
        (when pipe
          (set-process-sentinel pipe #'ignore)
          (delete-process pipe)))
      (kill-buffer buffer))))

(defun my-flymake-eslint--cancel ()
  "Cancel this buffer's running lint job."
  (when my-flymake-eslint--process
    (let ((process my-flymake-eslint--process))
      (setq my-flymake-eslint--process nil)
      (my-flymake-eslint--cleanup process))))

(defun my-flymake-eslint--mode-changed ()
  "Cancel outstanding work when Flymake is disabled."
  (unless flymake-mode (my-flymake-eslint--cancel)))

(defun my-flymake-eslint--position (line column)
  "Convert one-based LINE and UTF-16 COLUMN to a buffer position."
  (goto-char (point-min))
  (forward-line (1- (max 1 (or line 1))))
  (let ((units (1- (max 1 (or column 1)))))
    (while (and (> units 0) (< (point) (line-end-position)))
      (setq units (- units (if (> (char-after) #xffff) 2 1)))
      (forward-char)))
  (point))

(defun my-flymake-eslint--diagnostics (process)
  "Convert PROCESS JSON output to diagnostics in the current source buffer."
  (let ((json (with-current-buffer (process-buffer process)
                (json-parse-string (buffer-string) :object-type 'alist
                                   :array-type 'array :null-object nil
                                   :false-object nil)))
        diagnostics)
    (unless (vectorp json) (error "Expected ESLint JSON array"))
    (save-excursion
      (seq-doseq (file json)
        (seq-doseq (item (alist-get 'messages file))
          (let* ((severity (alist-get 'severity item))
                 (beg (my-flymake-eslint--position
                       (alist-get 'line item) (alist-get 'column item)))
                 (end (if (alist-get 'endLine item)
                          (my-flymake-eslint--position
                           (alist-get 'endLine item) (alist-get 'endColumn item))
                        (min (point-max) (1+ beg))))
                 (rule (alist-get 'ruleId item)))
            (when (memq severity '(1 2))
              (push (flymake-make-diagnostic
                     (current-buffer) beg (max beg end)
                     (if (= severity 2) :error :warning)
                     (concat (alist-get 'message item)
                             (when rule (format " [%s]" rule))))
                    diagnostics))))))
    (nreverse diagnostics)))

(defun my-flymake-eslint--sentinel (process _event)
  "Report PROCESS results and release its resources."
  (when (memq (process-status process) '(exit signal))
    (unwind-protect
        (let ((source (process-get process 'source)))
          (when (buffer-live-p source)
            (with-current-buffer source
              (when (eq process my-flymake-eslint--process)
                (setq my-flymake-eslint--process nil)
                (if (/= (buffer-chars-modified-tick)
                        (process-get process 'tick))
                    (funcall (process-get process 'report) nil)
                  (condition-case err
                      (progn
                        (unless (and (eq (process-status process) 'exit)
                                     (memq (process-exit-status process) '(0 1)))
                          (error "Exit %s: %s" (process-exit-status process)
                                 (with-current-buffer (process-get process 'stderr)
                                   (string-trim (buffer-string)))))
                        (funcall (process-get process 'report)
                                 (save-restriction
                                   (widen)
                                   (my-flymake-eslint--diagnostics process))))
                    (error
                     ;; Configuration/CLI errors are not source diagnostics.
                     ;; Clear old results, log details, and allow the next retry.
                     (flymake-log :warning "eslint: %s" (error-message-string err))
                     (funcall (process-get process 'report) nil))))))))
      (my-flymake-eslint--cleanup process))))

;;;###autoload
(defun my-flymake-eslint-backend (report-fn &rest _args)
  "Run eslint asynchronously and pass diagnostics to REPORT-FN.
Suitable for buffer-local registration in `flymake-diagnostic-functions'.
An obsolete run is cancelled before starting a new one.  Missing executables,
remote files and buffers without file names are silently skipped."
  (my-flymake-eslint--cancel)
  (add-hook 'kill-buffer-hook #'my-flymake-eslint--cancel nil t)
  (add-hook 'change-major-mode-hook #'my-flymake-eslint--cancel nil t)
  (add-hook 'flymake-mode-hook #'my-flymake-eslint--mode-changed nil t)
  (if (or (not buffer-file-name) (file-remote-p buffer-file-name)
          (file-remote-p default-directory))
      (funcall report-fn nil)
    (let* ((default-directory (file-truename (file-name-directory buffer-file-name)))
           (executable (my-flymake-eslint--executable)))
      (if (not executable)
          (funcall report-fn nil)
        (let ((source (current-buffer))
              (tick (buffer-chars-modified-tick))
              (output (generate-new-buffer " *my-flymake-eslint*"))
              (stderr (generate-new-buffer " *my-flymake-eslint-stderr*"))
              stderr-process process)
          (condition-case err
              (save-restriction
                (widen)
                (setq stderr-process
                      (make-pipe-process
                       :name "my-flymake-eslint-stderr"
                       :buffer stderr :noquery t :sentinel #'ignore))
                (setq process
                      (make-process
                       :name "my-flymake-eslint" :buffer output
                       :stderr stderr-process
                       :connection-type 'pipe :coding 'utf-8-unix :noquery t
                       :sentinel #'ignore
                       :command (append (list executable)
                                        my-flymake-eslint-arguments
                                        (list "--stdin" "--stdin-filename"
                                              (file-truename buffer-file-name)
                                              "--format" "json"))))
                (process-put process 'source source)
                (process-put process 'tick tick)
                (process-put process 'report report-fn)
                (process-put process 'stderr stderr)
                (setq my-flymake-eslint--process process)
                (set-process-sentinel process #'my-flymake-eslint--sentinel)
                (process-send-region process (point-min) (point-max))
                (process-send-eof process)
                (my-flymake-eslint--sentinel process "finished"))
            (error
             (setq my-flymake-eslint--process nil)
             (if process
                 (my-flymake-eslint--cleanup process)
               (when (process-live-p stderr-process)
                 (delete-process stderr-process))
               (kill-buffer output)
               (kill-buffer stderr))
             (flymake-log :warning "eslint: %s" (error-message-string err))
             (funcall report-fn nil))))))))

(provide 'my-flymake-eslint)
;;; my-flymake-eslint.el ends here

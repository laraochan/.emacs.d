;;; my-flymake-oxlint.el --- oxlint diagnostics for Flymake -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Larao
;; SPDX-License-Identifier: GPL-3.0-or-later

;; Author: Larao
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: languages, tools

;;; Commentary:

;; Add `my-flymake-oxlint-backend' to `flymake-diagnostic-functions'
;; buffer-locally, then enable `flymake-mode'.  Supports file-visiting
;; JavaScript, TypeScript, JSX and TSX buffers; parser/configuration support
;; is supplied by the installed linter.  Remote and non-file buffers are
;; skipped.  No other personal configuration or third-party Lisp is needed.
;;
;; The nearest executable node_modules/.bin/oxlint in an ancestor directory
;; takes precedence over PATH.  Customize `my-flymake-oxlint-executable'
;; to override discovery.  Missing executables yield no diagnostics; install
;; the tool and call `flymake-start' to retry.
;; Oxlint's CLI does not accept stdin.  A UTF-8 snapshot with the original
;; extension is created beside the source and removed after the run.  This
;; requires a writable source directory; filename-specific overrides/ignores
;; and rules depending on the exact basename may differ.  Other files read by
;; import/type-aware rules remain the on-disk versions.

;;; Code:

(require 'cl-lib)
(require 'flymake)
(require 'json)
(require 'subr-x)

(defgroup my-flymake-oxlint nil
  "Oxlint diagnostics for Flymake."
  :group 'flymake
  :prefix "my-flymake-oxlint-")

(defcustom my-flymake-oxlint-executable nil
  "Explicit oxlint executable name or absolute path, or nil to discover it.
Automatic discovery prefers ancestor node_modules/.bin/oxlint executables,
then searches the variable `exec-path'.  An explicit value bypasses
automatic discovery."
  :type '(choice (const :tag "Automatic" nil) string)
  :group 'my-flymake-oxlint)

(defcustom my-flymake-oxlint-arguments nil
  "Additional oxlint command-line arguments, as a list of strings.
Use only lint configuration options, not output, fix or file selection flags."
  :type '(repeat string)
  :group 'my-flymake-oxlint)

(defvar-local my-flymake-oxlint--process nil
  "Current lint process for this buffer.")

(defun my-flymake-oxlint--executable ()
  "Find the configured executable for the current directory."
  (if my-flymake-oxlint-executable
      (executable-find my-flymake-oxlint-executable)
    (let ((root (locate-dominating-file
                 default-directory
                 (lambda (dir)
                   (let ((file (expand-file-name "node_modules/.bin/oxlint" dir)))
                     (and (file-regular-p file) (file-executable-p file)))))))
      (if root
          (expand-file-name "node_modules/.bin/oxlint" root)
        (executable-find "oxlint")))))

(defun my-flymake-oxlint--cleanup (process)
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
      (kill-buffer buffer)))
  (let ((file (process-get process 'temporary-file)))
    (when (and file (file-exists-p file)) (delete-file file))))

(defun my-flymake-oxlint--cancel ()
  "Cancel this buffer's running lint job."
  (when my-flymake-oxlint--process
    (let ((process my-flymake-oxlint--process))
      (setq my-flymake-oxlint--process nil)
      (my-flymake-oxlint--cleanup process))))

(defun my-flymake-oxlint--mode-changed ()
  "Cancel outstanding work when Flymake is disabled."
  (unless flymake-mode (my-flymake-oxlint--cancel)))

(defun my-flymake-oxlint--diagnostics (process)
  "Convert PROCESS JSON output to diagnostics in the current source buffer."
  (let* ((json (with-current-buffer (process-buffer process)
                 (json-parse-string (buffer-string) :object-type 'alist
                                    :array-type 'list :null-object nil
                                    :false-object nil)))
         (bytes (encode-coding-string (buffer-string) 'utf-8-unix))
         diagnostics)
    (unless (assq 'diagnostics json) (error "Expected oxlint diagnostics object"))
    (dolist (item (alist-get 'diagnostics json))
      (let* ((span (alist-get 'span (car (alist-get 'labels item))))
             (offset (min (length bytes) (max 0 (or (alist-get 'offset span) 0))))
             (limit (min (length bytes)
                         (+ offset (max 0 (or (alist-get 'length span) 1)))))
             ;; Oxlint spans use UTF-8 byte offsets, not character columns.
             (beg (+ (point-min)
                     (length (decode-coding-string (substring bytes 0 offset)
                                                   'utf-8-unix))))
             (end (+ (point-min)
                     (length (decode-coding-string (substring bytes 0 limit)
                                                   'utf-8-unix))))
             (rule (alist-get 'code item))
             (help (alist-get 'help item)))
        (push (flymake-make-diagnostic
               (current-buffer) (min beg (point-max)) (min end (point-max))
               (pcase (alist-get 'severity item)
                 ("error" :error) ("warning" :warning) (_ :note))
               (concat (alist-get 'message item)
                       (when rule (format " [%s]" rule))
                       (when help (concat "\n" help))))
              diagnostics)))
    (nreverse diagnostics)))

(defun my-flymake-oxlint--sentinel (process _event)
  "Report PROCESS results and release its resources."
  (when (memq (process-status process) '(exit signal))
    (unwind-protect
        (let ((source (process-get process 'source)))
          (when (buffer-live-p source)
            (with-current-buffer source
              (when (eq process my-flymake-oxlint--process)
                (setq my-flymake-oxlint--process nil)
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
                                   (my-flymake-oxlint--diagnostics process))))
                    (error
                     ;; Configuration/CLI errors are not source diagnostics.
                     ;; Clear old results, log details, and allow the next retry.
                     (flymake-log :warning "oxlint: %s" (error-message-string err))
                     (funcall (process-get process 'report) nil))))))))
      (my-flymake-oxlint--cleanup process))))

;;;###autoload
(defun my-flymake-oxlint-backend (report-fn &rest _args)
  "Run oxlint asynchronously and pass diagnostics to REPORT-FN.
Suitable for buffer-local registration in `flymake-diagnostic-functions'.
An obsolete run is cancelled before starting a new one.  Missing executables,
remote files and buffers without file names are silently skipped."
  (my-flymake-oxlint--cancel)
  (add-hook 'kill-buffer-hook #'my-flymake-oxlint--cancel nil t)
  (add-hook 'change-major-mode-hook #'my-flymake-oxlint--cancel nil t)
  (add-hook 'flymake-mode-hook #'my-flymake-oxlint--mode-changed nil t)
  (if (or (not buffer-file-name) (file-remote-p buffer-file-name)
          (file-remote-p default-directory))
      (funcall report-fn nil)
    (let* ((default-directory (file-truename (file-name-directory buffer-file-name)))
           (executable (my-flymake-oxlint--executable)))
      (if (not executable)
          (funcall report-fn nil)
        (let ((source (current-buffer))
              (tick (buffer-chars-modified-tick))
              (output (generate-new-buffer " *my-flymake-oxlint*"))
              (stderr (generate-new-buffer " *my-flymake-oxlint-stderr*"))
              stderr-process process temporary-file)
          (condition-case err
              (save-restriction
                (widen)
                (setq temporary-file
                      (make-temp-file
                       (expand-file-name "my-flymake-oxlint-" default-directory)
                       nil (concat "." (or (file-name-extension buffer-file-name)
                                            "js"))))
                (let ((coding-system-for-write 'utf-8-unix))
                  (write-region (point-min) (point-max) temporary-file nil 'silent))
                ;; Discover a root config while preserving the source path for
                ;; nested configuration and import resolution.
                (setq default-directory
                      (or (locate-dominating-file
                           default-directory
                           (lambda (dir)
                             (cl-some (lambda (name)
                                        (file-exists-p (expand-file-name name dir)))
                                      '(".oxlintrc.json" ".oxlintrc.jsonc"
                                        "oxlint.config.ts" "oxlint.config.mts"))))
                          default-directory))
                (setq stderr-process
                      (make-pipe-process
                       :name "my-flymake-oxlint-stderr"
                       :buffer stderr :noquery t :sentinel #'ignore))
                (setq process
                      (make-process
                       :name "my-flymake-oxlint" :buffer output
                       :stderr stderr-process
                       :connection-type 'pipe :coding 'utf-8-unix :noquery t
                       :sentinel #'ignore
                       :command (append (list executable)
                                        my-flymake-oxlint-arguments
                                        (list "--format" "json" "--" temporary-file))))
                (process-put process 'source source)
                (process-put process 'tick tick)
                (process-put process 'report report-fn)
                (process-put process 'stderr stderr)
                (process-put process 'temporary-file temporary-file)
                (setq my-flymake-oxlint--process process)
                (set-process-sentinel process #'my-flymake-oxlint--sentinel)
                (my-flymake-oxlint--sentinel process "finished"))
            (error
             (setq my-flymake-oxlint--process nil)
             (if process
                 (my-flymake-oxlint--cleanup process)
               (when (process-live-p stderr-process)
                 (delete-process stderr-process))
               (kill-buffer output)
               (kill-buffer stderr))
             (when (and temporary-file (file-exists-p temporary-file))
               (delete-file temporary-file))
             (flymake-log :warning "oxlint: %s" (error-message-string err))
             (funcall report-fn nil))))))))

(provide 'my-flymake-oxlint)
;;; my-flymake-oxlint.el ends here

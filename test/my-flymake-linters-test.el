;;; my-flymake-linters-test.el --- Backend checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'js)
(defvar js-ts-mode-hook)
(defvar typescript-mode-hook)
(defvar typescript-ts-mode-hook)
(defvar tsx-ts-mode-hook)
(defvar eglot-managed-mode-hook)
(require 'my-flymake-eslint)
(require 'my-flymake-oxlint)

(defconst my-flymake-test--tools
  '((:name "eslint"
     :executable my-flymake-eslint-executable
     :finder my-flymake-eslint--executable
     :backend my-flymake-eslint-backend
     :process my-flymake-eslint--process
     :sentinel my-flymake-eslint--sentinel
     :diagnostics my-flymake-eslint--diagnostics)
    (:name "oxlint"
     :executable my-flymake-oxlint-executable
     :finder my-flymake-oxlint--executable
     :backend my-flymake-oxlint-backend
     :process my-flymake-oxlint--process
     :sentinel my-flymake-oxlint--sentinel
     :diagnostics my-flymake-oxlint--diagnostics)))

(defun my-flymake-test--wait (predicate)
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (should (funcall predicate))))

(defun my-flymake-test--script (dir tool body)
  (let ((file (expand-file-name tool dir)))
    (with-temp-file file (insert "#!/bin/sh\n" body "\n"))
    (set-file-modes file #o700)
    file))

(defmacro my-flymake-test--source (&rest body)
  (declare (indent 0) (debug t))
  `(let ((directory (make-temp-file "flymake-test-" t)))
     (unwind-protect
         (with-temp-buffer
           (setq default-directory (file-name-as-directory directory)
                 buffer-file-name (expand-file-name "source.tsx" directory))
           (insert "const face = '😀';\nconst unused = 1;\n")
           ,@body)
       (delete-directory directory t))))

(ert-deftest my-flymake-test-discovery ()
  (dolist (spec my-flymake-test--tools)
    (my-flymake-test--source
      (let* ((tool (plist-get spec :name))
             (finder (plist-get spec :finder))
             (variable (plist-get spec :executable))
             (bin (expand-file-name "node_modules/.bin" directory))
             (child (expand-file-name "src/deep" directory)))
        (make-directory bin t)
        (make-directory child t)
        (let* ((local (my-flymake-test--script bin tool "exit 0"))
               (global (my-flymake-test--script directory tool "exit 0"))
               (exec-path (list directory))
               (default-directory (file-name-as-directory child)))
          (cl-progv (list variable) '(nil)
            (should (equal (funcall finder) local))
            (set-file-modes local #o600)
            (should (equal (funcall finder) global)))
          (cl-progv (list variable) (list global)
            (should (equal (funcall finder) global))))))))

(ert-deftest my-flymake-test-missing-and-unsupported ()
  (dolist (spec my-flymake-test--tools)
    (my-flymake-test--source
      (cl-progv (list (plist-get spec :executable))
          '("/nonexistent/flymake-test-executable")
        (dolist (file (list buffer-file-name nil "/ssh:invalid:/source.js"))
          (let ((buffer-file-name file) (called nil))
            (funcall (plist-get spec :backend)
                     (lambda (diags) (setq called t) (should-not diags)))
            (should called)))))))

(ert-deftest my-flymake-test-json-unicode-and-severity ()
  (my-flymake-test--source
    (dolist (spec my-flymake-test--tools)
      (let* ((out (generate-new-buffer " *lint-json*"))
             (process (make-pipe-process :name "lint-json" :buffer out :noquery t))
             (json (if (equal (plist-get spec :name) "eslint")
                       "[{\"messages\":[{\"message\":\"unused\",\"ruleId\":\"rule\",\"severity\":2,\"line\":2,\"column\":7,\"endLine\":2,\"endColumn\":13},{\"message\":\"warning\",\"severity\":1,\"line\":1,\"column\":18}]}]"
                     "{\"diagnostics\":[{\"message\":\"unused\",\"code\":\"rule\",\"severity\":\"error\",\"labels\":[{\"span\":{\"offset\":27,\"length\":6}}]},{\"message\":\"warning\",\"severity\":\"warning\"}]}")))
        (unwind-protect
            (progn
              (with-current-buffer out (insert json))
              (let ((diags (funcall (plist-get spec :diagnostics) process)))
                (should (= (length diags) 2))
                (should (eq (flymake-diagnostic-type (car diags)) :error))
                (should (eq (flymake-diagnostic-type (cadr diags)) :warning))
                (should (equal (buffer-substring
                                (flymake-diagnostic-beg (car diags))
                                (flymake-diagnostic-end (car diags))) "unused"))))
          (delete-process process)
          (kill-buffer out))))))

(ert-deftest my-flymake-test-async-registration-and-cleanup ()
  (dolist (spec my-flymake-test--tools)
    (my-flymake-test--source
      (let* ((tool (plist-get spec :name))
             (script (my-flymake-test--script
                      directory tool
                      (if (equal tool "eslint")
                          "cat >/dev/null\nprintf '%s' '[{\"messages\":[{\"message\":\"bad\",\"severity\":2,\"line\":2,\"column\":7}]}]'\nexit 1"
                        "printf '%s' '{\"diagnostics\":[{\"message\":\"bad\",\"severity\":\"warning\",\"labels\":[{\"span\":{\"offset\":27,\"length\":6}}]}]}'\nexit 1")))
             (backend (plist-get spec :backend)))
        (cl-progv (list (plist-get spec :executable)) (list script)
          (setq-local flymake-diagnostic-functions (list backend))
          (flymake-mode 1)
          (flymake-start)
          (my-flymake-test--wait (lambda () (flymake-diagnostics)))
          (should (= (length (flymake-diagnostics)) 1))
          (should (memq backend (flymake-running-backends)))
          (should-not (directory-files directory nil "^my-flymake-oxlint-"))
          (should-not (symbol-value (plist-get spec :process)))
          (flymake-mode -1))))))

(ert-deftest my-flymake-test-cancellation-stale-and-failure ()
  (dolist (spec my-flymake-test--tools)
    (my-flymake-test--source
      (let* ((tool (plist-get spec :name))
             (script (my-flymake-test--script directory tool "exec sleep 5"))
             (backend (plist-get spec :backend))
             (state (plist-get spec :process))
             (called nil))
        (cl-progv (list (plist-get spec :executable)) (list script)
          (funcall backend (lambda (&rest _) (setq called t)))
          (let* ((old (symbol-value state))
                 (out (process-buffer old))
                 (temp (process-get old 'temporary-file)))
            (funcall backend (lambda (&rest _) (setq called t)))
            (should-not (process-live-p old))
            (should-not (buffer-live-p out))
            (when temp (should-not (file-exists-p temp)))
            (should-not called))
          ;; Changed buffer contents must not receive old ranges.
          (let ((process (symbol-value state)))
            (setq called nil)
            (insert "changed")
            (delete-process process)
            (funcall (plist-get spec :sentinel) process "killed")
            (should called))
          (my-flymake-test--script directory tool "printf 'not JSON'; exit 2")
          (setq called nil)
          (funcall backend (lambda (diags) (setq called t) (should-not diags)))
          (my-flymake-test--wait (lambda () called))
          (should-not (symbol-value state))
          (should-not (directory-files directory nil "^my-flymake-oxlint-"))
          (my-flymake-test--script directory tool "exec sleep 5")
          (funcall backend #'ignore)
          (let ((process (symbol-value state)))
            (run-hooks 'kill-buffer-hook)
            (should-not (process-live-p process))
            (should-not (buffer-live-p (process-buffer process)))))))))

(ert-deftest my-flymake-test-empty-malformed-and-start-failure ()
  (dolist (spec my-flymake-test--tools)
    (my-flymake-test--source
      (let ((tool (plist-get spec :name))
            (backend (plist-get spec :backend))
            (state (plist-get spec :process)))
        (dolist (body (list (if (equal tool "eslint")
                               "cat >/dev/null; printf '[]'"
                             "printf '{\"diagnostics\":[]}'")
                           "printf 'invalid JSON'"))
          (let ((script (my-flymake-test--script directory tool body)) (called nil))
            (cl-progv (list (plist-get spec :executable)) (list script)
              (funcall backend (lambda (diags) (setq called t) (should-not diags)))
              (my-flymake-test--wait (lambda () called))
              (should-not (symbol-value state)))))
        (let ((script (my-flymake-test--script directory tool "exit 0")) (called nil))
          (cl-progv (list (plist-get spec :executable)) (list script)
            (cl-letf (((symbol-function 'make-process)
                       (lambda (&rest _) (error "Simulated launch failure"))))
              (funcall backend (lambda (diags) (setq called t) (should-not diags))))
            (should called)
            (should-not (symbol-value state))
            (should-not (directory-files directory nil "^my-flymake-oxlint-"))))))))

(ert-deftest my-flymake-test-real-linters ()
  "Optional integration test; see test/README.md for dependencies."
  (skip-unless (getenv "MY_FLYMAKE_TEST_BIN"))
  (dolist (spec my-flymake-test--tools)
    (let ((tool (plist-get spec :name)))
      (dolist (extension '("js" "jsx" "ts" "tsx"))
        (my-flymake-test--source
          (let ((parser
                 (expand-file-name "../@typescript-eslint/parser/dist/index.js"
                                   (getenv "MY_FLYMAKE_TEST_BIN"))))
          (with-temp-file (expand-file-name "eslint.config.cjs" directory)
            (insert (format "module.exports = [{files: ['**/*.{js,jsx,ts,tsx}'], languageOptions: {parser: require(%S)}, rules: {'no-debugger': 'error'}}];" parser)))
          (with-temp-file (expand-file-name ".oxlintrc.json" directory)
            (insert "{\"categories\":{\"correctness\":\"off\"},\"rules\":{\"no-debugger\":\"error\"}}")))
        ;; Both linters must discover parent configuration from a nested file.
        (make-directory (expand-file-name "src" directory))
        (setq buffer-file-name (expand-file-name (concat "src/source." extension) directory))
        (erase-buffer)
        (insert (if (member extension '("ts" "tsx"))
                    "const face: string = '😀';\n"
                  "const face = '😀';\n"))
        (when (member extension '("jsx" "tsx")) (insert "const element = <div/>;\n"))
        (insert "debugger;\n")
        ;; The source does not exist on disk: lint must consume the buffer.
        (let ((script (expand-file-name tool (getenv "MY_FLYMAKE_TEST_BIN")))
              (called nil) result)
          (cl-progv (list (plist-get spec :executable)) (list script)
            (funcall (plist-get spec :backend)
                     (lambda (diags) (setq called t result diags)))
            (my-flymake-test--wait (lambda () called))
            (should (= (length result) 1))
            (should (eq (flymake-diagnostic-type (car result)) :error))
            (should (equal (buffer-substring (flymake-diagnostic-beg (car result))
                                            (flymake-diagnostic-end (car result)))
                           "debugger;"))
            (should-not (directory-files (file-name-directory buffer-file-name)
                                         nil "^my-flymake-oxlint-")))))))))

(ert-deftest my-flymake-test-config-registration ()
  "Evaluate the actual integration forms without unrelated init side effects."
  (require 'use-package)
  (require 'eglot)
  (let ((js-mode-hook nil) (js-ts-mode-hook nil) (typescript-mode-hook nil)
        (typescript-ts-mode-hook nil) (tsx-ts-mode-hook nil)
        (eglot-managed-mode-hook nil))
    (with-temp-buffer
      (insert-file-contents "init.el")
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (or (and (eq (car-safe form) 'use-package)
                             (memq (cadr form)
                                   '(eglot my-flymake-eslint
                                           my-flymake-oxlint)))
                        (and (eq (car-safe form) 'defun)
                             (eq (cadr form) 'my/javascript-flymake-setup)))
                (eval form t))))
        (end-of-file nil)))
    (with-temp-buffer
      (js-mode)
      (should flymake-mode)
      (should (memq 'my-flymake-eslint-backend flymake-diagnostic-functions))
      (should (memq 'my-flymake-oxlint-backend flymake-diagnostic-functions))
      ;; Reproduce Eglot's documented replacement then run its actual hook.
      (setq-local flymake-diagnostic-functions '(eglot-flymake-backend))
      (run-hooks 'eglot-managed-mode-hook)
      (should (memq 'eglot-flymake-backend flymake-diagnostic-functions))
      (should (memq 'my-flymake-eslint-backend flymake-diagnostic-functions))
      (should (memq 'my-flymake-oxlint-backend flymake-diagnostic-functions)))))

;;; my-flymake-linters-test.el ends here

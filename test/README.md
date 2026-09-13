# Flymake linter backends

`lisp/my-flymake-eslint.el` and `lisp/my-flymake-oxlint.el` are independent
single-file packages requiring Emacs 27.1 or later and their respective CLI.
They require only built-in Lisp libraries, and neither requires the other.
The current `init.el` registers both in JavaScript/TypeScript modes, including
JSX/TSX, and restores their registration after Eglot replaces the backend list.
ESLint must have the appropriate project configuration/parser for TS/JSX.
Both linters can report overlapping rules; adjust the project's lint rules if
necessary. No CLI is installed automatically during Emacs startup.

For use outside this configuration, put either file on `load-path` and register
its backend, for example:

```elisp
(require 'my-flymake-eslint)
(add-hook 'js-mode-hook
          (lambda ()
            (add-hook 'flymake-diagnostic-functions
                      #'my-flymake-eslint-backend nil t)
            (flymake-mode 1)))
```

Use the corresponding `my-flymake-oxlint-backend` for oxlint. Choose other mode
hooks as appropriate. Each package provides `*-executable` (nil means nearest
ancestor `node_modules/.bin` executable, then PATH) and `*-arguments` options.
An explicit executable bypasses discovery. Missing tools are silently skipped;
`M-x flymake-start` retries after installation. Configuration, invalid JSON and
launch errors clear stale diagnostics and are logged in `*flymake log*`.

ESLint receives the widened, unsaved buffer via stdin with its real filename.
Oxlint's CLI has no stdin option, so it receives a UTF-8 temporary file beside
the source, retaining its extension. All owned processes, output buffers and
temporary files are cleaned up on completion, cancellation, buffer kill, mode
change or Flymake disable. Remote and non-file buffers are skipped. A forced
Emacs/OS termination cannot run cleanup hooks.

Oxlint needs a writable source directory. Exact-basename rules, overrides and
ignore patterns can differ for the temporary filename. Import/type-aware rules
read other files from disk; this is not a language server's workspace snapshot.
CLI configuration options must not override output, introduce extra files or
request fixes. The temporary executable used in validation is not configured
as a permanent fallback.

## Validation

Run from the repository root; standard tests need only Emacs and a POSIX shell:

```sh
emacs -Q --batch -L lisp -l test/my-flymake-linters-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -L lisp --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile lisp/my-flymake-eslint.el lisp/my-flymake-oxlint.el
emacs -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (quote ("lisp/my-flymake-eslint.el" "lisp/my-flymake-oxlint.el"))) (checkdoc-file file)))'
```

For the optional real CLI test, install `eslint`, `oxlint` and
`@typescript-eslint/parser` into an isolated directory, then run:

```sh
MY_FLYMAKE_TEST_BIN=/path/to/node_modules/.bin emacs -Q --batch -L lisp -l test/my-flymake-linters-test.el -f ert-run-tests-batch-and-exit
```

Validated with Emacs 31.1, ESLint 10.10.0, oxlint 1.82.0. Tests cover real JS,
JSX, typed TS and TSX syntax, parent config discovery, unsaved contents, UTF-8
and UTF-16 positions, executable precedence, missing tools, Flymake registration,
Eglot hook integration, cancellation, stale results, cleanup and failure paths.
The integration test evaluates only relevant forms in `init.el`; it does not
start an external language server or install tree-sitter grammars.

Package conventions were checked with strict byte compilation, `checkdoc`, and
manual review of headers, namespaces, autoload, customization and dependencies.
Before independent publication, add each repository's URL/contact metadata and
a full GPL-3.0-or-later license file, and move/adapt the tests for that repository.
No shared runtime module or personal helper needs to be extracted.

CLI references: [ESLint stdin and JSON](https://eslint.org/docs/latest/use/command-line-interface),
[oxlint CLI](https://oxc.rs/docs/guide/usage/linter/cli),
[oxlint JSON format](https://oxc.rs/docs/guide/usage/linter/output-formats).

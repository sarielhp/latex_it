# Emacs & AUCTeX Integration with latex_it

`latex_it` has dedicated support for GNU Emacs and the AUCTeX package via the `--emacs` flag.

---

## Why `--emacs`?

Standard `latex_it` formats diagnostics with colored borders, box frames, and source snippets designed for human terminal reading. However, Emacs and AUCTeX parse compilation buffers using regular expressions expecting standard TeX file tracking (`(filename.tex ... )`) and line anchors (`l.<line>`).

Passing `--emacs` automatically:
* Emits parenthesized file stack markers (`(chapters/intro.tex ... )`) that AUCTeX tracks.
* Formats error continuation blocks so AUCTeX's parser can extract the exact source lines.
* Suppresses terminal progress indicators, ANSI escapes, and decorative border lines.
* Reports warnings with standard `LaTeX Warning: ... on input line <line>` formatting.

---

## AUCTeX Setup (`init.el` or `~/.emacs`)

To add `latex_it` as a build command in AUCTeX, add the following to your Emacs configuration:

```elisp
(eval-after-load "tex"
  '(add-to-list 'TeX-command-list
                '("latex_it" "l --emacs %t" TeX-run-TeX nil (latex-mode)
                  :help "Build with latex_it and jump to errors") t))
```

### Setting `latex_it` as the Default Command
If you want AUCTeX to default to `latex_it` instead of `LaTeX`:

```elisp
(setq-default TeX-command-default "latex_it")
```

### Everyday AUCTeX Workflow:
* `C-c C-c`: Choose `latex_it` and press `Enter` to compile.
* `C-c \`` (`TeX-next-error`): Jump directly to the offending line for each error or warning.
* `C-c C-l` (`TeX-recenter-output-buffer`): View the full compilation log buffer.

---

## Standard Emacs Compilation Mode (`M-x compile`)

If you edit LaTeX in fundamental mode, standard `latex-mode`, or with general build tooling, you can compile via Emacs's universal compilation mode:

```elisp
;; In ~/.emacs or init.el:
(add-hook 'latex-mode-hook
          (lambda ()
            (setq-local compile-command "l --emacs")))
```

### Usage:
* `M-x compile`: Runs `l --emacs`.
* `C-x \`` (`next-error`): Jumps to the next diagnostic line in your buffer.
* `M-p` / `M-n`: Navigate previous and next errors in the compilation buffer.

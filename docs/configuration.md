# Configuration & Environment

`latex_it` provides flexible configuration options that can be defined globally, set per-project, or overridden via command-line flags.

---

## 1. Configuration Hierarchy

Settings are resolved using the following order of precedence (highest to lowest):

1. **Command-line flags** (e.g. `--engine=lualatex`, `-1`, `-e`)
2. **Local project configuration** (`.l.jsonc` or `.latex_it.jsonc` in document root)
3. **Global user configuration** (`~/.config/latex_it/config.jsonc`)
4. **Built-in defaults**

---

## 2. Project Configuration (`.l.jsonc`)

To create a documented configuration file in your project directory:

```bash
l --init-config
```

This creates `.l.jsonc` pre-populated with default settings and comments:

```jsonc
{
  // Default LaTeX engine: "xelatex", "lualatex", or "pdflatex"
  "engine": "xelatex",

  // Maximum number of compilation passes (1-3)
  "passes": 3,

  // Fast incremental mode: reuse aux files and avoid redundant passes
  "fast": false,

  // Enable diff-based PDF replacement (requires pdftotext)
  "update_on_diff": false,

  // Overfull \hbox threshold (in pt) to classify as an Alert
  "alert_overfull_pt": 24.0,

  // Overfull \hbox threshold (in pt) to classify as Whatever (suppressed)
  "whatever_overfull_pt": 2.5,

  // Filename patterns ignored when auto-detecting the main .tex document
  "exclude_main_tex": [
    "prefix*.tex",
    "prelim*.tex",
    "preamble*.tex",
    "*.num.tex",
    "pratenddefaultcategory.tex"
  ],

  // Patterns excluded from brace checking and diagnostic source scans
  "exclude_source_tex": [
    "styles/*",
    "macros/*",
    "pkg/*",
    "packages/*",
    "*prefix*.tex",
    "*preamble*.tex",
    "*macros*.tex",
    "*styles*.tex"
  ],

  // Directories searched for bibliography (.bib) files (in addition to root)
  "bib_dirs": ["refs", "bib", "bibliography"],

  // Automatically mirror project subdirectories into junk/ for nested inputs
  "auto_mirror_subdirs": true,

  // Additional subdirectories inside junk/ to pre-create
  "junk_subdirs": ["figs", "fragment"],

  // Route styles to styles/ in zip packages
  "zip": {
    "inject_styles": false
  }
}
```

Comments (`//` and `/* ... */`) and trailing commas are supported in `.l.jsonc` files.

---

## 3. Global Configuration

On first execution, `latex_it` automatically creates a global configuration file at:

```
~/.config/latex_it/config.jsonc
```

Settings defined here apply to all projects on your machine unless overridden by a project-level `.l.jsonc` or command-line flags.

---

## 4. Environment Variables & Isolation

### Sanitizing Environment (`--no-env`)
LaTeX installations sometimes fail due to stray environment variables set in user shell profiles (`~/.bashrc`, `~/.zshrc`). The `--no-env` flag unsets TeX-related variables:

```bash
l --no-env paper.tex
```

Variables reset include:
- `TEXINPUTS`
- `BIBINPUTS`
- `BSTINPUTS`
- `TEXMFHOME`
- `TEXMFCNF`

Symlink personality: running `latex_env_free`, `bibtex_env_free`, or `pdflatex_env_free` automatically activates `--no-env`.

### Passing Custom Options (`LATEXOPTS`)
You can pass custom options to the underlying TeX engine using the `LATEXOPTS` or `LATEXOPTIONS` environment variables:

```bash
LATEXOPTS="-shell-escape -synctex=1" l paper.tex
```

---

## 5. Concurrency Locking

When compiling large documents in editor setups that trigger builds on save, multiple compiler processes can conflict. `latex_it` automatically prevents simultaneous builds in the same directory using file locking (`flock` on `.l.lock`):

- **Default**: Enabled. A second process waits for the active build to complete.
- **Disabling**: Use `--no-lock` if you need to run concurrent builds intentionally.

# Sandboxed Testing & Portability

`latex_it` includes tools for building papers inside isolated environments, creating portable publication archives, and compiling legacy documents.

---

## 1. Portable Paper Archives (`-z` and `-t`)

### Creating a Portable Archive (`-z` / `--zip`)
When preparing a paper for co-authors, journals, or archival storage, `-z` creates a clean, self-contained zip archive:

```bash
l -z paper.tex
```

The packager:
- Gathers all input files and style dependencies recorded during compilation (`.fls`), ignoring system TeX Live packages.
- Preserves the compiled `.bbl` so the recipient does not need to run BibTeX.
- Discovers companion figure source files (`.fig`, `.ipe`, `.svg`, `.asy`, `.gp`, `.py`, `.R`) that correspond to included figures.
- Excludes editor backups (`*.bak`, `figs/bak/`, `figs/old/`).

To include extra supplementary files or datasets:

```bash
l -z paper.tex -- notes.txt data/*.csv
```

### Styles Organization (`--inject-styles`)
- **Default (`false`)**: Harvested styles are placed in the archive root for compatibility across journal submission portals.
- **Opt-in (`--inject-styles`)**: Harvested styles are placed into a `styles/` subfolder, and `{% raw %}\def\input@path{{styles/}{./}}{% endraw %}` is added to the staged `.tex` file.

### Portability Verification (`-t` / `--verify`)
To confirm that an archive builds on another machine without ambient dependencies:

```bash
l -t paper.tex
```

This unpacks the archive into an isolated `/tmp` directory, runs `latex_it --no-env` (clearing `TEXINPUTS` and `TEXMFHOME`), and verifies that the rebuilt PDF text matches using `pdftotext -layout`.

---

## 2. Offline Sandbox Builds (`tools/bws_run`)

`tools/bws_run` builds papers inside a disposable [Bubblewrap](https://github.com/containers/bubblewrap) (`bws`) sandbox. It guarantees that the build relies only on files inside the project directory:

```bash
tools/bws_run /path/to/paper -- latex_it paper.tex
```

### Sandbox Guarantees
- **No Network Access**: Network interfaces and proxy access are disabled.
- **No User Credentials**: `~/.config` and `~/.ssh` are not mounted; `bws` provides an empty home directory.
- **Clean Workspace**: Staged workspace excludes `.git/` directories, `junk/`, and external symlinks.
- **TeX Caches Preserved**: Host fontconfig and TeX distribution caches are mounted read-only, matching normal compiler speeds.

To inspect the staged directory without launching the sandbox:

```bash
tools/bws_run /path/to/paper --prepare-only
```

---

## 3. Legacy REVTeX 4.0 Compatibility

Papers written before 2010 often use `\documentclass{revtex4}` (superseded by `revtex4-1` and `revtex4-2`). On modern TeX Live installations, compiling these documents fails with missing class errors.

`latex_it` includes a small, LPPL-licensed REVTeX 4.0 compatibility tree:

- Installed to `~/.local/share/latex_it/texmf` via `tools/install`.
- Added to the compiler's search path only when `\documentclass{revtex4}` is detected.
- Bundled automatically into `-z` and `--arxiv` archives when used, keeping the resulting zip self-contained.

To configure or disable REVTeX 4.0 compatibility in `.l.jsonc`:

```jsonc
{
  "revtex4": {
    "enabled": true,
    "texmf_dirs": ["~/.local/share/latex_it/texmf"]
  }
}
```

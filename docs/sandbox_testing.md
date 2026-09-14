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

### Creating a Flattened Archive (`-Z` / `--zip-flat`)
Many journal submission systems (such as Springer Nature, IEEE Author Portal, or Elsevier Editorial Manager) require all LaTeX text to be in a single monolithic `.tex` file with no `\input` or `\include` subdirectories.

`-Z` (or `--zip-flat`) automatically inlines all inputs into a single `<document>.tex` file, retains the compiled `.bbl`, bundles active figures and styles, and omits redundant subordinate `.tex` files:

```bash
l -Z paper.tex
```

Like `-z`, you can combine `-Z` with `-t` to verify that the flattened archive builds cleanly in an isolated sandbox:

```bash
l -Z -t paper.tex
```

### Packaging Modes Comparison

`latex_it` provides three distinct packaging modes for sharing, archival, and publication:

| Feature | Standard Zip (`-z`) | Flat Zip (`-Z`) | arXiv Package (`--arxiv`) |
| :--- | :--- | :--- | :--- |
| **TeX Structure** | Multi-file tree preserved | **Inlined single `.tex` file** | Inlined single `.tex` file |
| **Subordinate `.tex`** | Copied into archive | **Omitted** | Omitted |
| **Comments (`%`)** | Preserved | **Preserved** | Stripped by default |
| **Bibliography** | Copies `.bbl` and local `.bib` | Copies `.bbl` and local `.bib` | Copies `.bbl` (shields biblatex) |
| **Figures & Styles** | Preserved | Preserved | Preserved |
| **Figure Sources** | Companion sources bundled (`.fig`, `.ipe`, etc.) | Companion sources bundled | Strictly excluded (PDF/PNG only) |
| **Metadata File** | None | None | Generates `arxiv_*_meta.txt` |
| **Target Output** | `<doc>.zip` | `<doc>.zip` | `arxiv_<doc>.zip` |
| **Primary Use Case** | Co-authors & general archival | Journal submission portals (IEEE, Springer, Elsevier) | Direct submission to arXiv.org |

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

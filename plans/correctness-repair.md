# Correctness repair plan

## Scope and workflow

Repair the six reviewed correctness issues in Ruby; preserve the CLI and standalone installation. Do not perform a Go rewrite or split the executable in this change. Follow AGENTS.md, keep every new or modified Ruby method at most 80 lines, and run `tools/gate` after each coherent fix. Use `/home/sariel/.cargo/bin/rtk` when it is absent from PATH.

Add meaningful regression tests before each implementation. Use temporary directories and controlled subprocess fixtures for failures; avoid dependence on timing sleeps, ambient TeX packages, or unrelated user files. Do not commit, tag, install, or push during this task. Leave a reviewable diff.

## 1. Archive and verification failure propagation

Relevant methods: both packagers' `do_package`, archive creation, sandbox verification, and `verify_pdf_diff`; CLI dispatch.

- A failed zip/unzip/compiler command must produce a nonzero CLI exit and no success/completion announcement.
- For portable verification, differing extracted PDF text or failed extraction must fail verification. Preserve the existing optional behavior when pdftotext is unavailable, but explicitly state that comparison was skipped rather than claiming a match.
- Check subprocess statuses, not diagnostic text. Resolve the executable path before any directory changes so relative invocation can verify correctly.
- Tests: compiler failure, archive creation failure, PDF mismatch/extraction failure, successful verification, and CLI exit status. Extend existing success tests to require actual verification success.

## 2. Correct subdirectory builds

Relevant methods: builder `run!`, both packagers' `package!`, arXiv `ensure_compiled!`.

- Give each component stable absolute directory information or otherwise prevent nested relative chdir calls.
- A fresh `--arxiv sub/main.tex` must compile and package in `sub`, including sandbox verification. Cover portable packaging from a relative subdirectory too.
- Preserve behavior for plain filenames, absolute paths, and symlink invocation.

## 3. Cache validity

Relevant methods: `targets_up_to_date?`, `save_build_state!`, dependency collection.

- Reject cached state when the selected engine or compilation-affecting options/environment differ. Explicit bibliography requests must not be bypassed by the cache.
- Do not accept changed source content merely because mtimes fall in the same integer second. Hash tracked dependencies for correctness, unless an equally reliable strategy is justified.
- Keep source state scoped to the target and do not promote failed builds to current state. A single-pass/incomplete build must not cause a normal subsequent build to skip necessary convergence.
- Tests: unchanged build skips; changing engine forces rebuild; nested source changes within the same second force rebuild; LATEXOPTS/LATEXOPTIONS changes force rebuild; explicit bibliography and single-pass transitions.

## 4. Bibliography failures and backups

Relevant methods: `run_bib_pass`, compilation output publication/state saving.

- Preserve the previous valid bibliography before invoking BibTeX/Biber. Never overwrite that backup with failed or newly generated output.
- Require successful subprocess status and valid bibliography before publishing replacements. Preserve valid root bibliography on failure, stop the build with a nonzero result, and do not save a successful build state.
- Limit publication to the active target rather than copying every junk/*.bbl.
- Tests for both tools: failed process, malformed/empty generated bibliography, successful replacement, previous-content backup, unrelated target untouched.

## 5. Flattening semantics

Relevant methods: `LaTeXFlattener.inline_file`, `strip_comments`, `strip_inline_comment`.

- Replace global input deduplication with recursion-stack cycle detection: repeated legitimate inputs remain repeated; cycles yield an actionable failure rather than silently deleting content.
- Preserve the newline suppression of TeX comments: `foo% comment\nbar` must retain `foobar` semantics, including macro definitions and whitespace-sensitive contexts. Retaining an empty `%` marker is acceptable.
- Preserve escaped percent signs, comment-only lines, existing URL behavior, and verbatim-like contents rather than applying destructive text transformations to them.
- Avoid expanding this into a general TeX parser. For unsupported forms, prefer preserving source over silently changing semantics.
- Tests: repeated inputs, cyclic inputs, comment-sensitive tokens/macros, escaped percent, existing recursive input fixtures, verbatim content.

## 6. Verification environment isolation

Relevant methods: `LaTeXUtils.reset_latex_environment!`, sandbox subprocess environments.

- Remove ambient TEXMFHOME influence and ensure verification cannot use the default personal ~/texmf tree either. Use an empty temporary TeX home/tree for sandbox compilation, while retaining system TeX distributions.
- Inspect related TeX configuration variables for direct ways to defeat the requested isolation, and scope changes to the sandbox where possible.
- Tests: inherited TEXMFHOME is cleared/overridden; verification receives an isolated home/tree; ordinary compilation still supports user configuration.

## Review and acceptance

The implementing agent reports changes, tests, unresolved concerns, and exact affected files. The reviewing agent independently examines the diff, checks the original reproductions and additional failure paths, runs `tools/gate`, and fixes or delegates any regressions. Record review outcomes below. No automatic commit, install, or release.

## Review outcomes

- Baseline `tools/gate`: passed (3.25 seconds).
- Independent reviewer suite uses real XeLaTeX, LuaLaTeX, BibTeX, and pdftotext, with all fixtures confined to temporary directories. Seven baseline failures reproduced: relative-subdirectory arXiv build, engine switch, same-second nested input edit, single-pass-to-normal transition, repeated input/comment semantics, failed verification exit status, and malformed bibliography exit status.
- Implementation delegated to `gpt-5.6-luna`, followed by independent parent review and completion of residual fixes. No commits, installation, or release actions were performed.

### Review findings resolved

- Corrected draft PDF comparison logic that treated a successful `puts` call as a truthy value.
- Corrected bibliography restoration to use a preserved backup, prefer the last published root bibliography, and remove stale junk output before invoking the tool. Both failing commands and successful commands that produce no new valid bibliography are rejected.
- Rejected legacy cache state lacking build signatures, forced explicit bibliography requests, invalidated old state before rebuilding, and prevented partial builds and dependency-only passes from creating successful build state. Build state is saved only after diagnostic checks return successfully.
- Retained empty comment markers plus newlines to preserve TeX command boundaries and indentation handling. Protected common verbatim/listing environments and inline `\\verb` examples from inlining, comment stripping, and host-specific cleanup.
- Verified ordinary compilation can access an ambient personal TeX package while sandbox verification cannot find the same package when it is absent from the archive.

### Validation

- `tools/gate`: all 61 tests passed, including 20 added regression tests. Final code gate completed in 23.35 seconds. Real-engine tests account for the increased runtime; their Lua font caches live in temporary fixture directories.
- Independent integration coverage is retained in `test/test_review_integration.rb`; controlled failure cases are retained in `test/test_repair_failures.rb`.
- AST inspection: all Ruby methods in the executable and tests satisfy the 80-line limit.
- `git diff --check`: passed.
- RuboCop was run with caching disabled after its default cache directory proved read-only. It remains non-clean: the original executable alone reported 430 offenses, versus 436 at the review checkpoint. Broad style cleanup was outside this repair scope.

### Remaining scope limits

- The executable remains a single oversized file; structural refactoring and a Go rewrite were deliberately deferred.
- Flattening remains heuristic, not a general TeX interpreter. Custom catcodes, custom verbatim environments, and macro-generated inputs require separate coverage.
- Verification establishes compilation against the local system TeX installation, not compatibility with a particular remote arXiv installation.

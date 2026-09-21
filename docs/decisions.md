# Architectural Decision Records (ADRs)

This document records the architectural, distribution, and design decisions made for `latex_it`, including accepted patterns and rejected alternatives.

---

## ADR-0001: Rejection of Homebrew Tap Distribution

* **Status**: **Rejected**
* **Date**: September 2026
* **Deciders**: Maintainers

### Context
We evaluated creating and maintaining a dedicated Homebrew tap (`sarielhp/homebrew-tap`) to allow installation via `brew install sarielhp/tap/latex_it` on macOS and Linux.

### Decision
**Reject Homebrew tap distribution.** `latex_it` will be distributed exclusively via standalone single-file binary assets attached directly to GitHub Releases and installed via `curl` into `~/bin/l` (or via `./tools/install` when cloned from source).

### Rationale
1. **Release Friction & Maintenance Overhead**:
   Homebrew formulas require recalculating tarball SHA256 checksums, modifying Ruby formula files, and committing to an external repository on every version release. Given `latex_it`'s rapid release and continuous delivery cadence, maintaining external package formulas introduces recurring manual toil and version desynchronization.
2. **Zero-Dependency Architecture**:
   `latex_it` is compiled by `tools/bundle` into a completely self-contained, single-file Ruby executable that uses only the Ruby standard library. Because it contains no compiled native C extensions or external gem dependencies, Homebrew provides no dependency resolution value.
3. **Frictionless 1-Second Installation**:
   The standalone binary can be installed in under one second on any machine with:
   ```bash
   mkdir -p ~/bin && curl -sSL https://github.com/sarielhp/latex_it/releases/latest/download/latex_it -o ~/bin/l && chmod +x ~/bin/l
   ```
   This works identically on macOS and Linux without Homebrew update lag, tap permissions, or package manager state conflicts.

---

## ADR-0002: Native CLI Flag (`-llm`) over Daemonized MCP Server

* **Status**: **Accepted**
* **Date**: September 2026
* **Deciders**: Maintainers

### Context
We evaluated implementing a Model Context Protocol (MCP) server daemon to interface with AI coding agents (Claude Code, Cursor, Antigravity, OpenCode, Aider).

### Decision
**Implement a native CLI flag (`-llm`) rather than a daemonized MCP server.** For workflows strictly requiring programmatic serialization, `--json` is provided as a standard stdout emitter.

### Rationale
1. **Token Economy**:
   Standard GNU compiler plaintext (`file:line:col: severity: msg`) takes $\sim 75\%$ fewer context tokens than JSON-RPC envelopes or deeply nested structured JSON payloads. LLMs are trained on trillions of tokens of compiler outputs and parse GNU compiler diagnostics effortlessly.
2. **Zero Configuration**:
   Autonomous coding agents already possess terminal execution tools. `l -llm` works immediately with zero configuration files, daemon setup, port management, or background process supervisors.
3. **Sandbox & Isolation Compatibility**:
   Coding agents frequently operate inside isolated sandboxes (Bubblewrap `bws`, Docker containers, temporary git worktrees). A CLI command runs natively inside the sandbox where files and compiler environments reside, whereas daemon-based MCP servers run outside and struggle with path translation and filesystem boundaries.

# Security

flowscribe puts instructions for AI agents into other people's projects, so a flaw here spreads to
every project that installs it. Security is a design requirement, not a feature.

## Reporting a vulnerability

Report vulnerabilities **privately** via GitHub → *Security* → *Report a vulnerability* on this
repository. Do not open a public issue. Please include the release version, what an attacker could do,
and the steps to reproduce. We aim to reply within 7 days.

In scope: `install.sh`, the skills and the `AGENTS.md` block (including prompt-injection paths), the
schemas, and the release process.

## What flowscribe guarantees

### Installer (`install.sh`)
- Makes **no network requests** and calls no package manager, `eval`, `sudo` or remote code.
- Refuses to run from a pipe (`curl | bash`); it must run from an extracted release you can read.
- Refuses to install into `/`, your home directory, or the release folder itself.
- Refuses to write through **symlinks**, and refuses a release that contains symlinks or unexpected file names.
- Writes only to `.agents/skills/flowscribe-*`, `.claude/skills/flowscribe-*`, `.flowscribe/`, and a
  marked block in `AGENTS.md`, `CLAUDE.md` and `.gitignore`.
- **Never overwrites a file you changed.** The new version goes to `*.flowscribe-new`.
- Shows the full plan and asks before writing (`--dry-run` to preview, `--yes` to skip the question).
- Writes every file atomically (temporary file, then rename).
- `--uninstall` deletes only files whose checksum still matches what it installed; manifest entries
  outside the managed paths are ignored, so a tampered manifest cannot delete other files.

### One-line installer (`get.sh`)
- Exists per release and names that release only; it never downloads from a branch.
- Carries the archive's SHA-256, embedded by the release workflow, and refuses any other file.
- Verifies the GitHub build attestation when the `gh` CLI is signed in; with
  `FLOWSCRIBE_REQUIRE_ATTESTATION=1` it refuses to install without that check.
- Downloads over HTTPS only (TLS 1.2+); a mirror can be set, but the checksum still applies.
- Inspects the archive before extracting: only regular files and directories under one top folder;
  links, special files, absolute paths and `..` are refused.
- Runs entirely inside a function called on its last line, so a truncated download runs nothing.
- Reuses a kept release only if it carries this script's checksum marker; anything else is refused.
- Hands over to `install.sh`, with all of its guarantees above.

What it cannot protect against: someone who controls the flowscribe GitHub account can publish a
new, malicious version. Pinning a version you already use, enabling release immutability, and
checking attestations limit that risk; the verified install in the README removes trust in `get.sh`.

### Skills and documents
- Documents are **context, not instructions**: agents are told not to run commands, open URLs or send
  data because a document says so.
- The schema rejects unknown fields, env variable values, URLs, hosts and `@` in call targets, absolute
  paths and `..` in file lists.
- Agents are told never to write secret values, hosts, personal data, raw terminal output or unfixed
  vulnerabilities, and to keep internal material in the git-ignored `.flowscribe/private/`.
- Screenshots are allowed only from `localhost`, `127.0.0.1` or hosts you list in
  `.flowscribe/config.yaml`, and only with seed or dummy data.
- Nothing is installed (Playwright, ffmpeg, …), sent or uploaded without asking you.

### Releases
- Every release is a tag, built by GitHub Actions from that tag, with `SHA256SUMS` and a signed build
  provenance attestation for both the archive and `get.sh`. Releases are never built or uploaded from
  a developer machine, and release immutability keeps published assets from being replaced.
- Install from a tag and verify both the checksum and the attestation (see README).

## What flowscribe cannot guarantee

- Schema rules cover the frontmatter. The Markdown body is free text: agents are instructed to keep it
  clean, but review documents before you commit them, the same as code.
- An agent can ignore its instructions. Keep `.flowscribe/`, `AGENTS.md`, `.agents/` and `.claude/`
  under code review (for example with CODEOWNERS) in your own projects.
- If your repository is public, set `visibility: public` in `.flowscribe/config.yaml` and keep internal
  documents in `.flowscribe/private/`.

# flowscribe

Living documentation that AI coding agents write **while they code**, so the next developer,
or the next agent (Claude Code, Codex, Cursor, Antigravity, …), can pick the project up without
re-reading the whole codebase.

- **Cheap to read.** Agents start from one small index and open only what the task needs.
- **Structured flows.** Each user journey is a Markdown file with YAML frontmatter, which is enough
  to draw diagrams, capture screenshots and storyboard a motion-graphics video.
- **Easy handover.** Internal or external handover packs are built from documents that already exist.
- **Works with many agents.** Skills use the open `SKILL.md` format, and the rules live in `AGENTS.md`.
- **Security first.** No secrets, hosts or personal data in documents; the installer never touches
  the network and never overwrites your files. See [SECURITY.md](SECURITY.md).
- **No package manager.** You install from a GitHub release. Your project gets no `node_modules`
  and no `package.json` or `composer.json` changes.

## Contents

- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Install](#install)
- [What gets installed](#what-gets-installed)
- [Daily use](#daily-use)
- [How skills are triggered](#how-skills-are-triggered)
- [Supported agents](#supported-agents)
- [Documents](#documents)
- [Configuration](#configuration)
- [Saving tokens](#saving-tokens)
- [Teams and parallel agents](#teams-and-parallel-agents)
- [Using it next to other skill packs](#using-it-next-to-other-skill-packs)
- [Update](#update)
- [Uninstall](#uninstall)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Limitations and roadmap](#limitations-and-roadmap)
- [Development and releases](#development-and-releases)

## Requirements

- macOS or Linux with `bash`, `curl`, `tar` and `shasum` or `sha256sum`, all preinstalled on both.
- An AI coding agent that reads `AGENTS.md` (see [Supported agents](#supported-agents)).
- Optional: the [GitHub CLI](https://cli.github.com/), signed in, to verify build attestations.
- Not needed: Node, npm, PHP, Python or Go.
- Windows: not tested. WSL is the most likely to work.

## Quick start

```bash
cd your-project
curl -fsSL https://github.com/hengkidh/flowscribe/releases/download/v0.1.0/get.sh | bash
```

Then tell your agent:

> Run the flowscribe-init skill.

Review the generated `.flowscribe/` folder and commit it. From then on the agent keeps it current.

## Install

### One line (recommended)

Run inside the project you want to document:

```bash
curl -fsSL https://github.com/hengkidh/flowscribe/releases/download/v0.1.0/get.sh | bash
```

To preview without changing anything:

```bash
curl -fsSL https://github.com/hengkidh/flowscribe/releases/download/v0.1.0/get.sh | bash -s -- --dry-run
```

The URL names one version, never a branch. `get.sh` is built for that version and carries the
archive's SHA-256, so it:

1. downloads `flowscribe-v0.1.0.tar.gz` from the same release;
2. refuses it if the checksum differs from the embedded one;
3. verifies the GitHub build attestation when the GitHub CLI is signed in
   (set `FLOWSCRIBE_REQUIRE_ATTESTATION=1` to refuse installing without it);
4. refuses archives with links, absolute paths or `..`;
5. keeps the release in `~/.flowscribe/0.1.0/`;
6. runs its `install.sh`, which shows every change and asks `Install? [y/N]` before writing.

### Other projects

The kept release is reused with no download:

```bash
cd another-project
~/.flowscribe/0.1.0/install.sh
```

### Verified install (read everything first)

If you prefer not to run a script you have not read, do the same steps by hand:

```bash
VERSION=0.1.0
BASE=https://github.com/hengkidh/flowscribe/releases/download/v$VERSION
curl -fsSLO "$BASE/flowscribe-v$VERSION.tar.gz"
curl -fsSLO "$BASE/SHA256SUMS"
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify "flowscribe-v$VERSION.tar.gz" --repo hengkidh/flowscribe
tar -xzf "flowscribe-v$VERSION.tar.gz"
less "flowscribe-v$VERSION/install.sh"
./flowscribe-v$VERSION/install.sh --dry-run
./flowscribe-v$VERSION/install.sh
rm -rf "flowscribe-v$VERSION" "flowscribe-v$VERSION.tar.gz" SHA256SUMS
```

`install.sh` itself never runs from a pipe and never touches the network.

### Installer options

| Option | What it does |
|---|---|
| `--dry-run` | Show what would change, write nothing |
| `--yes` | Skip the confirmation (review `--dry-run` first) |
| `--target DIR` | Install into `DIR` instead of the current directory |
| `--uninstall` | Remove flowscribe; your documents are kept |
| `--version` | Print the release version |
| `--help` | Show help |

With `get.sh`, pass options after `bash -s --`, for example `| bash -s -- --yes`.

## What gets installed

| Path | What | On update |
|---|---|---|
| `.agents/skills/flowscribe-*/` | The skills, in the location most agents read | Updated, unless you changed them |
| `.claude/skills/flowscribe-*/` | The same skills, where Claude Code reads them | Updated, unless you changed them |
| `.flowscribe/schema/v1/` | The document contract as JSON Schema | Updated, unless you changed them |
| `.flowscribe/templates/` | Templates for flows, modules, decisions and logs | Updated, unless you changed them |
| `.flowscribe/config.yaml` | Project settings | Kept once you edit it |
| `AGENTS.md` | A block between `<!-- flowscribe:start -->` and `<!-- flowscribe:end -->` | Only the block is replaced |
| `CLAUDE.md` | One line: `@AGENTS.md` | Added once |
| `.gitignore` | Ignores `.flowscribe/private/` and `.flowscribe/screens/` | Only the block is replaced |
| `.flowscribe/.install-manifest` | What was installed, with checksums | Rewritten |

Nothing else in your project is touched. Existing content in `AGENTS.md`, `CLAUDE.md` and
`.gitignore` stays exactly as it was.

After `flowscribe-init` and a few weeks of work, a Laravel project looks like this:

```
my-app/
├── app/  routes/  resources/  …        your code, untouched
├── AGENTS.md                           your content + the flowscribe block
├── CLAUDE.md                           @AGENTS.md
├── .agents/skills/flowscribe-*/        skills
├── .claude/skills/flowscribe-*/        same skills for Claude Code
└── .flowscribe/
    ├── config.yaml
    ├── index.yaml                      ~40 lines: the map agents read first
    ├── modules/  auth.md  orders.md  payments.md
    ├── flows/    register.md  checkout.md  refund-approval.md
    ├── decisions/ 0001-hold-stock-before-payment.md
    ├── log/      2026-11.md  2026-12.md
    ├── private/                        git-ignored: handover packs, storyboards
    ├── screens/                        git-ignored: screenshots
    ├── schema/v1/  templates/          installed by flowscribe
    └── .install-manifest
```

## Daily use

You talk to your agent as usual. These are the requests flowscribe adds:

| You say | Skill | Result |
|---|---|---|
| "Run flowscribe-init" | `flowscribe-init` | Modules, the 2–5 main flows and the index for an existing codebase |
| *(nothing, after a coding task)* | `flowscribe-sync` | Affected documents, a log entry, a decision record if needed, the index |
| "Document the checkout flow" | `flowscribe-flow` | `.flowscribe/flows/checkout.md` |
| "Draw a diagram of the checkout flow" | `flowscribe-flow` | A Mermaid diagram built from the flow's frontmatter |
| "Take screenshots of each checkout step" | `flowscribe-flow` | `.flowscribe/screens/checkout/*.png`, from localhost with seed data |
| "Make a handover pack for the client" | `flowscribe-handover` | `.flowscribe/private/handover-external-<date>.md` |
| "Make a 9:16 video storyboard of checkout" | `flowscribe-video` | `.flowscribe/private/storyboard-checkout.yaml` for your video tool |

### First run

`flowscribe-init` maps the stack, groups the code into 3–12 modules by feature, writes the most
important flows and generates the index. Anything it could not confirm in the code is marked
`status: draft`. Review those documents before you commit. The agent never opens `.env` files,
credentials, database dumps or logs.

### After every coding task

`flowscribe-sync` first decides how much work the change needs:

| Change | What happens |
|---|---|
| Typos, styling, formatting, comments, tests, dependency bumps | Nothing |
| A bug fix inside existing behaviour | One log entry |
| New or changed routes, screens, calls, states, env variables, module files | Full sync |
| A real choice between alternatives | Full sync and a decision record |

It edits only the parts that are now wrong, so pull requests show small, reviewable documentation diffs
next to the code.

### Example: building a checkout feature

1. Before coding, the agent reads `index.yaml`, sees the `orders` and `payments` modules and opens
   only those two documents, so it goes straight to the right files.
2. You and the agent build the feature as usual.
3. At the end, `flowscribe-sync` writes `flows/checkout.md` (steps, routes, calls, states, branches),
   updates `modules/orders.md` and `modules/payments.md`, adds a log entry, records a decision such
   as "hold stock before payment", and regenerates the index.
4. Later, "add vouchers to checkout", in any agent or session, starts from `flows/checkout.md`
   instead of from a search through the codebase.

## How skills are triggered

| Trigger | How | Reliability |
|---|---|---|
| The `AGENTS.md` block | Loaded every session; tells the agent to run init and sync | High for init, medium for sync |
| Skill descriptions | The agent opens a skill when your request matches it | High: you asked for it |
| By name | Claude Code: `/flowscribe-sync`. Any agent: "run flowscribe-sync" | Always |

Agents that do not load skills by name can open the file directly; the `AGENTS.md` block lists every
skill's path. If you want to be sure documentation is updated, end a task with "run flowscribe-sync".
Automatic enforcement (hooks and `flowscribe check`) is on the [roadmap](#limitations-and-roadmap).

## Supported agents

| Agent | Reads `AGENTS.md` | Reads skills | Status |
|---|---|---|---|
| Claude Code | Through `CLAUDE.md` → `@AGENTS.md` | `.claude/skills/` | Supported |
| OpenAI Codex | Yes | `.agents/skills/` | Supported |
| Antigravity | Yes | `.agents/` | Expected to work |
| Cursor, GitHub Copilot | Yes | Not verified yet | Rules work; open skills by path |
| Gemini CLI | Reads `GEMINI.md` by default | Not verified yet | Point `GEMINI.md` at `AGENTS.md` |

The documents themselves are plain Markdown and YAML, so every agent and every person can read them.

## Documents

```
.flowscribe/
  index.yaml          generated; one line per document; read first
  flows/<id>.md       user and system journeys (source for diagrams and videos)
  modules/<id>.md     areas of the code: files, entrypoints, env variable names, dependencies
  decisions/NNNN-*.md architecture decision records
  log/YYYY-MM.md      short development log
  private/            git-ignored: internal notes, handover packs, storyboards
  screens/            git-ignored: captured screenshots
```

Every document is Markdown with YAML frontmatter. The frontmatter holds the facts tools need;
the body holds the reasons and gotchas people need. A flow looks like this:

```markdown
---
flowscribe: 1
type: flow
id: checkout
title: Checkout
summary: Customer turns a cart into a paid order; stock is held while payment is pending.
status: active
updated: 2026-11-05
actor: customer
trigger: Customer presses "Pay" on the cart page
files: [app/Http/Controllers/OrderController.php]
steps:
  - { id: cart, kind: screen, title: Review cart, screen: { route: /cart }, calls: [POST /api/orders], next: pay }
  - { id: pay, kind: screen, title: Pay, screen: { route: "/pay/:order" }, states: [pending, paid, failed],
      next: [{ when: paid, to: done }, { when: failed, to: failed }] }
  - { id: done, kind: screen, title: Order confirmed, screen: { route: "/orders/:order" }, end: success }
  - { id: failed, kind: screen, title: Payment failed, screen: { route: "/orders/:order" }, end: failure }
---

# Checkout

Orders are created before payment so stock can be held.

## Gotchas
- The payment webhook can arrive before the redirect; read status from the webhook.
```

The full contract, with every field and rule, is in [spec/contract.md](spec/contract.md). The schemas are in
[schema/v1/](schema/v1/) and complete examples are in [examples/](examples/). The schema rejects unknown
fields, env variable values, URLs, hosts, absolute paths and `..`, so frontmatter cannot carry secrets.

## Configuration

`.flowscribe/config.yaml`:

| Key | Default | Meaning |
|---|---|---|
| `visibility` | `private` | `public` if the repository is public: internal documents must then live in `private/` |
| `default_audience` | `internal` | Audience of new documents: `internal` or `external` (external ones can go in client handovers) |
| `capture.allowed_hosts` | `[]` | Hosts besides `localhost`/`127.0.0.1` that may be screenshotted; local or staging with dummy data only |
| `docs.language` | `en` | Language of the prose; frontmatter keys are always English |

## Saving tokens

Without documentation, an agent new to a codebase explores it with searches and file reads, often
20–80k tokens on a medium app, and again in every new session. With flowscribe it reads the index
(about 1k tokens), one or two documents (2–5k) and goes straight to the listed entrypoints.

What it costs: the `AGENTS.md` block (~700 tokens per session), skill descriptions (~300) and a sync
after code changes (2–8k for a full sync; nothing for trivial changes).

It pays off most on medium and large projects worked on over many sessions, and on handovers. On a
project of a few files it roughly breaks even.

## Teams and parallel agents

- **Commit `.flowscribe/`, `.agents/`, `.claude/`, `AGENTS.md` and `CLAUDE.md`.** Teammates then get
  everything with `git pull`; only one person needs to install or update.
- **One agent per branch or worktree.** Two agents editing the same working directory at the same
  time can overwrite each other's files. This is true for code too.
- **Merge conflicts in `index.yaml`:** do not merge by hand; ask the agent to regenerate the index.
  It is derived from the documents, so regenerating is always correct.
- **Merge conflicts in `log/*.md`:** keep both entries.
- **Same decision number on two branches:** renumber the one that merges second.
- Protect these paths with CODEOWNERS in your own projects: agents follow them as instructions.

## Using it next to other skill packs

flowscribe only uses `flowscribe-*` names and its own marked blocks, so it coexists with other packs
that install into `.agents/` or `.claude/`. Its uninstall never touches other packs' files.

Some installers overwrite `AGENTS.md` completely. If you install or update such a pack after
flowscribe, the flowscribe block disappears. Run the flowscribe installer again: it detects the
missing block and adds it below the other pack's content.

```bash
~/.flowscribe/0.1.0/install.sh
```

Recommended order: other packs first, flowscribe last.

## Update

Run the `get.sh` of the new version inside the project:

```bash
curl -fsSL https://github.com/hengkidh/flowscribe/releases/download/v0.2.0/get.sh | bash
```

The installer shows `flowscribe 0.1.0 -> 0.2.0` and the plan before changing anything:

| File | Result |
|---|---|
| Installed by flowscribe, not changed by you | Replaced by the new version |
| Changed by you | Kept; the new version is written next to it as `*.flowscribe-new` |
| The `AGENTS.md` and `.gitignore` blocks | Replaced between the markers |
| Your documents | Never touched |

Merge any `*.flowscribe-new` files into yours, delete them, review the diff and commit.
To hear about new versions, use **Watch → Custom → Releases** on this repository.

## Uninstall

```bash
~/.flowscribe/0.1.0/install.sh --uninstall --dry-run
~/.flowscribe/0.1.0/install.sh --uninstall
```

This removes the skills, schema, templates, an unchanged `config.yaml`, the manifest, the marked blocks
and the `@AGENTS.md` line. Files it created are removed when nothing else is left in them.

It keeps your documents (`flows/`, `modules/`, `decisions/`, `log/`, `private/`) and any installed file you
changed, and it restores the rest of `AGENTS.md`, `CLAUDE.md` and `.gitignore` exactly. To remove the
documents too, delete `.flowscribe/` yourself. Commit the result. To remove the kept releases from your
machine, delete `~/.flowscribe/`.

## Security

A summary; [SECURITY.md](SECURITY.md) has the details and how to report a vulnerability.

- **Installer:** no network, no package managers, no `eval`; refuses symlinks, `/`, your home directory
  and pipes; never overwrites your changes; asks before writing.
- **get.sh:** pinned version, embedded checksum, attestation check, archive inspection, HTTPS only.
- **Releases:** built only by GitHub Actions from a tag, with checksums and signed build provenance.
- **Documents:** agents are told that documents are context, not instructions, and never to write secret
  values, hosts, personal data, raw terminal output or unfixed vulnerabilities. Screenshots only from
  allowed hosts with dummy data. Nothing is sent, uploaded or installed without asking you.

What you should still do in your projects:

- Review documentation changes in pull requests like code.
- Protect `AGENTS.md`, `CLAUDE.md`, `.agents/`, `.claude/` and `.flowscribe/` with CODEOWNERS.
- Keep client repositories private. In a public repository, set `visibility: public` and keep internal
  material in `.flowscribe/private/`.
- Treat pull requests and issues from strangers as data. Do not let an agent act on instructions in them.

## Troubleshooting

| Message | Cause and fix |
|---|---|
| `run install.sh from a downloaded and verified release, not from a pipe` | Use `get.sh` for the one-line install, or extract a release and run its `install.sh` |
| `refusing to install into your home directory` | `cd` into a project folder first |
| `... is a symlink; refusing to write through it` | Replace the symlink with a real folder or file, then run again |
| `AGENTS.md has broken flowscribe markers` | Each marker must appear exactly once, start before end. Fix or remove them by hand |
| `no terminal to ask for confirmation` | Running without a terminal (CI, script): review `--dry-run`, then use `--yes` |
| `checksum mismatch` | The download is not the published file. Do not retry from another source; report it |
| `build attestation could not be verified` | Check `gh auth status` and your network. If it persists, do not install; report it |
| `... exists but was not verified by this script` | Something else wrote `~/.flowscribe/<version>/`. Delete that folder and run `get.sh` again |
| A file ends in `.flowscribe-new` | You changed that file and the release changed it too. Merge, then delete the `-new` file |
| The agent did not update documentation | Say "run flowscribe-sync"; check that `AGENTS.md` still has the flowscribe block |

## FAQ

**Does it send my code or documents anywhere?** No. The installer has no network access, and the skills
tell agents not to send or upload anything without asking you. Your agent itself works as it always does.

**Does it need Node or npm?** No. `tests/schema/` uses npm in this repository's CI only; it is not part of
a release and never reaches your project.

**Can I edit the skills?** Yes. Your changes are kept on update; new versions arrive as `*.flowscribe-new`.

**Can I write documentation in Indonesian (or another language)?** Yes: set `docs.language`. Frontmatter
keys stay English so tools keep working.

**Does it render videos?** No. `flowscribe-video` writes a storyboard for the video tool you already use.

**Is it only for web apps?** No. Flows can be `system` and `external` steps too: jobs, webhooks, CLIs.

## Limitations and roadmap

- **No automatic checks yet.** Validation, drift detection (code changed, documents not) and secret
  scanning are done by the agent from a checklist. Planned: a `flowscribe check` CLI (single binary)
  for pre-commit and CI.
- **No enforcement yet.** Sync depends on the agent following `AGENTS.md`. Planned: an optional Claude Code
  hook that reminds the agent when code changed and documents did not.
- **Parallel work:** `index.yaml` and monthly logs can conflict across branches (see
  [Teams and parallel agents](#teams-and-parallel-agents)). Planned: union merge for logs.
- **Contract v2** will come with a `flowscribe migrate` command.
- Skill paths for Cursor, Copilot and Gemini CLI are not verified yet.

## Development and releases

```bash
bash tests/install.test.sh          # installer
bash tests/get.test.sh              # one-line installer and release build (offline)
npm ci --prefix tests/schema --ignore-scripts && node tests/schema/validate.mjs   # schemas
```

CI also runs ShellCheck and rejects hidden Unicode characters. See [CONTRIBUTING.md](CONTRIBUTING.md):
changes to skills, `payload/agents-block.md`, `install.sh` and `scripts/` get extra review because agents
and users run them.

Repository layout:

```
install.sh                 the installer (copied into every release)
payload/agents-block.md    the AGENTS.md block
payload/files/             files installed into projects
schema/v1/                 JSON Schemas (installed into .flowscribe/schema/v1/)
spec/contract.md           the document contract
examples/                  example documents
scripts/get.sh.in          template for the one-line installer
scripts/build-release.sh   builds the archive, get.sh and SHA256SUMS
tests/                     test suites
```

To release: update `VERSION`, merge to `main`, then push a matching tag:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The release workflow tests, builds, attests and publishes `flowscribe-v<version>.tar.gz`, `get.sh` and
`SHA256SUMS`. Releases are never built on a developer machine.

Recommended repository settings: two-factor authentication on the owner account; branch protection on
`main` (pull requests, passing CI, code-owner review, no force pushes); a tag ruleset for `v*`; release
immutability; private vulnerability reporting; Dependabot alerts and secret scanning; approval required
before running workflows from outside contributors.

## License

[MIT](LICENSE)

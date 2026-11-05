---
name: flowscribe-handover
description: Use when the user asks for a handover, onboarding pack, project overview for a new developer or another AI agent, or documentation to give to a client or vendor. Builds an internal or external handover pack from .flowscribe/ without reading the whole codebase again.
---

# flowscribe-handover

Produces a handover pack from the documents that already exist. If they are stale, run
`flowscribe-sync` first; a handover is only as good as the documents behind it.

## Ask first
Which audience? This decides what may be included:
- **internal** — the team or a trusted developer: every document, except `.flowscribe/private/` unless the user says so.
- **external** — a client, vendor or anyone outside the team: only documents with `audience: external`.
  Leave out decisions about security, infrastructure details and every `## Gotchas` section that
  mentions security, unless the user reviews and approves each one.

## Build the pack
Write `.flowscribe/private/handover-<audience>-<YYYY-MM-DD>.md` (git-ignored, so it is never committed by
accident). Sections:
1. **What this app is** — `app.summary` and stack from the index, in plain language.
2. **How to run it** — from the project's own README or setup docs; link, do not copy secrets or hosts.
3. **Architecture** — one paragraph per module (from summaries and bodies), plus how they depend on each other.
4. **Main flows** — each flow's summary and a Mermaid diagram rendered from its frontmatter.
5. **Decisions that shaped it** — accepted decisions, one line each.
6. **Known open items** — `Open:` lines from the last two months of logs, and documents still in `draft`.
7. **Where to start** — the `read_first` documents and the entrypoints of the busiest modules.

## Before you hand it over
- Re-read the pack against the security rules in `AGENTS.md`. For **external**, also remove internal
  names of people, ticket links and anything marked `audience: internal`.
- Tell the user where the file is and what you left out. Do not send or upload it yourself.

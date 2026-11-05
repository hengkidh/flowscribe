---
name: flowscribe-sync
description: Use at the end of every coding task that changed files in a project with a .flowscribe/ folder, and when the user asks to update the documentation. Updates only the flowscribe documents affected by the change, adds a log entry, records architecture decisions, and regenerates the index.
---

# flowscribe-sync

Keeps `.flowscribe/` in step with the code **at the smallest possible cost**: touch only what the
change affected, and never rewrite a document that is still correct.

## First: does this change need a sync at all?
Decide in one step, from the diff you already have; do not open documents to decide.

| Change | Do |
|---|---|
| Typos, copy text, styling/CSS, formatting, comments, renaming a local variable, tests only, dependency version bumps | **Nothing.** Say "no documentation change needed" and stop. |
| A bug fix inside existing behaviour (no new route, call, state, env variable or file) | **Log entry only** (step 5), no index regeneration. |
| Anything that adds, removes or changes a route, screen, call, state, branch, env variable name, dependency between modules, data table, or the files of a module or flow | **Full sync** (all steps below). |
| A real choice between alternatives (library, data model, sync vs async, security trade-off) | Full sync **including** a decision record. |

When in doubt between two rows, take the lighter one and mention it to the user in one line.

## Steps (full sync)
1. **List what changed** in this task (your own edits, or `git diff --name-only` against the task's start).
2. **Find affected documents**: every module or flow whose `files` globs match a changed file.
   A changed file that matches no document is a hint that a module is missing — add it to an
   existing module's `files` or create a new module if it is a new area.
3. **Update each affected document**, editing only the parts that are now wrong:
   - frontmatter: steps, routes, calls, states, `files`, `env` names, `depends_on`;
   - body: new gotchas, removed behaviour;
   - set `updated` to today's date (`YYYY-MM-DD`).
   If the change created a new user journey, use the `flowscribe-flow` skill for it.
4. **Decision?** If the task chose between real alternatives (a library, a data model, a sync vs async
   design, a security trade-off), add `.flowscribe/decisions/<NNNN>-<id>.md` from the template, with the
   next free number. Small implementation choices are not decisions.
5. **Log entry**: append to `.flowscribe/log/<YYYY-MM>.md` (create it from the template if missing):
   ```markdown
   ## YYYY-MM-DD — <module-or-flow>: <what changed, ≤ 70 chars>
   - Changed: <files or classes>
   - Why: <one line>
   - Open: <what is left, or "nothing">
   ```
6. **Regenerate the index** as described in the `flowscribe-init` skill.
7. **Check**: run `flowscribe check` if the CLI is on `PATH`; otherwise apply the checks listed in
   `flowscribe-init`. Report which documents you updated in one or two lines.

## Rules
- The security rules in the flowscribe block of `AGENTS.md` apply to everything you write. Re-read the
  log entry before saving: summaries only, no values, no terminal output, no personal data.
- Do not reformat or reorder documents you did not need to change; it creates noisy diffs.
- If a document contradicts the code and you are not sure which is right, keep the document, add a
  `## Open question` line to its body, and tell the user.

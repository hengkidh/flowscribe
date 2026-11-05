---
flowscribe: 1
type: flow
id: example-flow
title: Example flow
summary: One sentence, at most 160 characters, saying who does what and what the result is.
status: draft
updated: 2026-01-01
actor: customer
trigger: What starts this flow
modules: []
files:
  - path/to/the/main/file
steps:
  - id: start
    kind: screen
    title: First screen
    screen: { route: /example, name: Example }
    action: What the actor does here
    calls: [POST /api/example]
    caption: Short caption for the video
    next: finish
  - id: finish
    kind: screen
    title: Result screen
    screen: { route: /example/done, name: Done }
    end: success
---

# Example flow

Why this flow exists and how it works. Explain the reasons the frontmatter cannot show.

## Gotchas
- Things that surprised you, or will surprise the next developer.

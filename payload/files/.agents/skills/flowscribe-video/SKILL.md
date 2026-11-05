---
name: flowscribe-video
description: Use when the user asks for a video, motion graphic, animated walkthrough or storyboard of an app's flow or feature, in a project with .flowscribe/ flows. Turns a flow document into a storyboard (screens, actions, captions, branches) and hands it to the video tooling the user already has.
---

# flowscribe-video

flowscribe does not render video itself. It turns a flow into an exact **storyboard**, so any video tool
(a motion-graphics skill, Remotion, After Effects, a screen recorder) gets the right screens in the right
order with the right captions.

## Steps
1. Pick the flow with the user, and the style:
   - **UI walkthrough** — real screenshots of each `screen` step, with a cursor and captions;
   - **flow diagram** — the steps as animated nodes and arrows, calls shown as data moving between services;
   - **both** — diagram for the overview, then UI for the key screens.
2. Write `.flowscribe/private/storyboard-<flow-id>.yaml`:
   ```yaml
   flow: checkout
   format: { aspect: "9:16", fps: 30 }
   scenes:
     - step: cart              # step id from the flow
       visual: screen          # screen | diagram | both
       capture: .flowscribe/screens/checkout/cart.png
       caption: One tap from cart to checkout
       seconds: 3
   ```
   Take scenes, captions and order from the flow frontmatter only. For branches, follow the
   success path unless the user asks for the failure path too.
3. Capture missing screenshots with the `flowscribe-flow` skill (same host and data rules).
4. Hand the storyboard to the user's video tooling, or tell them how to use it.

## Rules
- Every frame is checked for real personal data, secrets, hosts or internal URLs (browser address bar,
  notifications, dev toolbars) before it goes into a video. Crop or recapture with seed data.
- Do not install rendering tools (ffmpeg, Playwright, Remotion) without asking the user first.
- Videos and storyboards stay in git-ignored folders; the user decides what to publish.

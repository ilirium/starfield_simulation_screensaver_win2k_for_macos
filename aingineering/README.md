# Working documents

Design notes, research, plans and reviews. Prose, not tickets — each one exists
because a decision needed reasoning written down, and most of them record what
was *measured* rather than what was assumed.

Named `AING-NNNN-short-slug.md`, numbered in sequence. **Numbers are never
reused**, and a document is never rewritten to reflect a later decision: a
revision gets a new number, and the delta between the two is usually the most
useful thing either of them contains. AING-0003 → 0004 → 0005 is the clearest
example — a plan, two independent reviews of it, and the plan those reviews
turned it into.

One consequence of that rule: **the `Status:` line inside each document is
frozen at the time of writing.** AING-0005 still says "decided, not
implemented" because that is what was true when it was written. The table below
is the current state.

## The documents

| | Status now | What it is |
|---|---|---|
| [AING-0001](AING-0001-ci-and-distribution.md) | partly implemented | CI, universal builds, code signing, notarization, packaging. §1–§3 shipped; §4 and §5 wait on the $99/year Apple Developer Program. Its appendix records what was verified, with commands and output. |
| [AING-0002](AING-0002-folder-naming-options.md) | decided | The long list of names for this folder, and the decision that came from outside it. Kept because the reasoning about what a working-documents folder is *for* outlived the naming question. |
| [AING-0003](AING-0003-uninstaller.md) | **superseded** by 0005 | The first v1.1.0 plan: uninstaller, thumbnail, `Render` fix. Kept unamended as the record of what was first proposed. Read it only to see what the reviews changed. |
| [AING-0004](AING-0004-plan-review.md) | complete | Two independent reviews of AING-0003 — its author re-reading it, and a fresh agent with no memory of writing it. Sixteen findings, three structural. The overlaps are the ones most likely to be real; the divergences are what a single pass would have shipped. |
| [AING-0005](AING-0005-uninstaller-revised.md) | **implemented** in 1.1.0 | The v1.1.0 plan as the reviews reshaped it. Self-contained. Its §2 is the pair of findings that reordered the uninstaller: a live `cfprefsd` client resurrects a deleted plist, and `cfprefsd` ignores `HOME`, so tests cannot be isolated that way. |
| [AING-0006](AING-0006-thumbnail-cache.md) | **implemented** in 1.1.0 | Step 0's answer, and the two gaps it uncovered. Amends AING-0005 §1, §3, §4 and §5. The serious one is §7: saver preferences live in a sandbox container that `defaults` cannot see, so the planned uninstaller would have deleted a decoy. §9 is the `--refresh-preview` spec. |
| [AING-0007](AING-0007-applescript-uninstaller.md) | **planned** for 1.2.0, **two decisions open** | A GUI uninstaller in AppleScript, driving `uninstall.sh`. Builds with `osacompile` and needs no Xcode. Its §1.2 is the finding the design rests on: AppleScript handlers can be called headlessly, so the logic is testable even though the dialogs are not. §3 (`--all-users`) and §4 (whether to build it at all, given Gatekeeper) are proposals awaiting a decision, not settled. |

## Reading paths

**If you are implementing something:** AING-0005 with AING-0006 open beside it.
Together they are the whole v1.1.0 design. AING-0003 and AING-0004 are history.
AING-0007 is the next thing to build, and is self-contained.

**If you want the story rather than the specification:**
[`docs/UNINSTALLING.md`](../docs/UNINSTALLING.md) and
[`docs/THUMBNAIL.md`](../docs/THUMBNAIL.md) are the narrative versions, in the
shape of `docs/TEARDOWN.md` — what happened in what order, and where the
reasoning went wrong first.

**If you want to know what is true today:** [`../HANDOFF.md`](../HANDOFF.md) is
the state of play, including a "what to distrust" list of claims that are
reasoned but unverified.

## Conventions

- **Label what was measured.** Claims backed by a command and its output are
  marked as such; claims that were reasoned to are marked **unverified**. Every
  document here has been wrong about something, and the labels are what made
  those errors findable.
- **Record the wrong turns.** AING-0004 exists because a single review pass
  would have shipped three structural mistakes. AING-0006 §1 exists because a
  well-designed experiment returned a confident wrong answer.
- **Supersede, never overwrite.** See above.
- **Traps get their own callouts.** `defaults domains` not listing ByHost
  domains, `nullglob` and the glob that matches its own literal, `cfprefsd`
  flushing late enough to make a bug look absent — each cost real time and is
  written down so it costs nobody else any.

# autospec-ui-pilot

The reference web UI that autospec's UI gates are calibrated against.

autospec ships rules that judge motion, accessibility and device behaviour —
`UI_NO_REDUCED_MOTION`, `UI_INFINITE_ANIMATION`, `UI_FIXED_VIEWPORT`,
`UI_HOVER_ONLY_AFFORDANCE`, `UI_RAW_HEX`, plus the WCAG 2.2 AA machine-verifiable gate.
Those rules were written against synthetic fixtures. This repository is where they meet
real code.

It exists because nothing else could fill the role. `berlinguyinca/autospec` has three UI
files and no motion at all. `berlinguyinca/autospec-gui` is a genuine Next.js
application — six pages, a live telemetry dashboard — and a good target for device
profiles and assistive-technology emulation, but a search of its entire tree returns zero
`transition`, `animation` and `@keyframes` declarations. A rule about motion cannot be
calibrated against a codebase with no motion.

## Layout

    index.html                     the compliant reference page
    styles/tokens.css              design tokens: duration scale, easing, colour
    styles/motion.css              animation, with its reduced-motion guard alongside
    styles/components.css          hover affordances, each with a focus equivalent
    fixtures/violations/           one file per rule, each expected to be flagged
    fixtures/known-gaps/           cases the rules get wrong, in both directions
    EXPECTED.tsv                   path, rule id, verdict — the calibration contract
    check.sh                       runs the gate and diffs it against the contract

`EXPECTED.tsv` is the point of the repository. Each row states what a file should draw, so
running the gates here yields a number rather than an impression. A rule that stops
firing, or starts firing somewhere new, shows up as a diff.

## Running it

    git clone https://github.com/berlinguyinca/autospec.git
    ./check.sh ./autospec

    UI gate matches EXPECTED.tsv (18 rows)

`check.sh` decides whether the gate ran at all by matching its error message, not its exit
status: `lint-ui.sh` exits with the finding count and *also* uses exit 2 for "awk could
not compile a pattern", so exit 2 means either a broken gate or a file with two findings.
Anything reading that code cannot tell a silent failure from an ordinary result.

## What the first run found

Five defects, inside an hour of the repository existing. Four are fixed in
[autospec#2964](https://github.com/berlinguyinca/autospec/pull/2964); one remains.

| | status |
|---|---|
| `UI_NO_REDUCED_MOTION` could be **silenced by a comment** — any line containing the media-feature name set the rule's "guard present" flag, so `TODO: add prefers-reduced-motion` removed the finding about the missing guard, and the file read as compliant from then on | fixed |
| `UI_FIXED_VIEWPORT` over-fired on prose — the compliant page here tripped it with a comment explaining that it *avoids* `user-scalable=no` | fixed |
| `UI_RAW_HEX` matched a literal only directly after the colon, missing `border: 1px solid #ccc`, gradient stops, `var()` fallbacks, and the 8-digit alpha form | fixed |
| `lint-ui.sh` exited 2 for both "the interpreter died" and "this file has two findings" | fixed, now 99 |
| `UI_NO_REDUCED_MOTION` over-fires across files — a global reset with unguarded components, the ordinary way to organise CSS, is still reported | open |

The first two shared a cause: the rules read comments as code. The silencing one is the
one worth remembering — a false positive costs an afternoon, that one lost an
accessibility finding quietly. It surfaced because the corpus's *intended*
`UI_NO_REDUCED_MOTION` violation came back clean: the comment explaining what was missing
was itself what suppressed the finding.

The open case needs the set of stylesheets that load together, which a
one-awk-pass-per-file design does not have. `fixtures/known-gaps/card-motion.css` holds it
so the day it changes is visible.

## The compliant page is not a demo

`index.html` and `styles/` are written to produce **zero findings**. They are a positive
control: if the gates report anything here, the gates are wrong. The interesting content
is deliberately plain, because a reference for a linter should exercise the rules rather
than showcase a design.

Motion in `styles/motion.css` follows the `## Motion` contract from
[`autospec-design`](https://github.com/berlinguyinca/autospec-design): a named duration
scale, one easing per intent, an explicit list of what never animates, and a per-pattern
reduced-motion fallback that is opacity-only rather than absent.

## Runtime motion evidence

The static gate above judges source. `ui-motion-evidence.mjs` judges the running page: it
renders each route twice, once normally and once with `prefers-reduced-motion: reduce`,
and asserts that motion exists by default, stops under the preference, and does not run
unbounded.

    python3 -m http.server 8731 --bind 127.0.0.1 &
    node autospec/skills/autospec-shared/scripts/ui-motion-evidence.mjs \
      --base-url http://127.0.0.1:8731 \
      --routes /index.html /fixtures/known-gaps/viewport-prose.html

    ok /index.html: moves [panel-enter, row-enter, row-enter], still under reduce
    MOTION_ABSENT:/fixtures/known-gaps/viewport-prose.html: nothing moves on this route by default

That contrast is the whole point. `viewport-prose.html` is a correct, accessible, entirely
static page: it satisfies the token linter, it would satisfy axe, and a vision judge would
find nothing to object to. `MOTION_ABSENT` is the only assertion in the pipeline that
fails it — which is why `index.html` here animates rather than merely being tidy.

The probe was measured against these files before the assertions were written around it.
A keyframe animation reports `["opacity", "transform"]` while a colour-only transition
reports nothing, so the check requires a property that *moves* something; `both`-filled
animations stay listed as `finished` after they end, so probing after load still sees a
page that animated on entry.

## Why the gaps are checked in rather than filed

A fixture that reproduces a defect keeps being true. An issue describing one goes stale
the moment the rule changes, and nobody notices which way. Every row in `EXPECTED.tsv`
marked `over-fire` or `missed` is a defect the gate has today, stated as behaviour a script
can check — so fixing one is visible as a verdict flipping to `correct`, and regressing one
is visible the same way.

The corpus is also why this repository is small and dull on purpose. It is not a showcase.
A reference for a linter should exercise the rules, and a page that also tried to look good
would make it harder to tell which property drew a finding.

## Related repositories

- [`autospec`](https://github.com/berlinguyinca/autospec) — the gates themselves
- [`autospec-design`](https://github.com/berlinguyinca/autospec-design) — the design
  contract these files conform to: required `DESIGN.md` sections, `rules.yaml`
- [`autospec-gui`](https://github.com/berlinguyinca/autospec-gui) — a real Next.js
  application, the right target for device-profile and assistive-technology work; it has
  no motion anywhere, which is why it cannot calibrate the motion rules

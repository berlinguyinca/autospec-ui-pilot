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

Five defects, inside an hour of the repository existing. Four are recorded as fixtures in
`known-gaps/`; the fifth is the exit-code collision above.

| | |
|---|---|
| `UI_FIXED_VIEWPORT` over-fires | prose or a comment naming `user-scalable=no` is flagged, wherever it appears. The compliant page in this repository tripped it with a comment explaining that it *avoids* the directive. |
| `UI_NO_REDUCED_MOTION` is silenced | any line containing the media-feature name sets the rule's file-level "guard present" flag — including a comment. `TODO: add prefers-reduced-motion` makes the finding disappear. A file looks compliant ever after. |
| `UI_RAW_HEX` misses most hex | only a literal directly after the colon, or a whole quoted string, is matched. `border: 1px solid #ccc`, a gradient stop, and `var(--x, #333)` all pass. |
| `UI_NO_REDUCED_MOTION` over-fires across files | a global reset plus unguarded components — the ordinary way to organise CSS — is reported, because the rule is decided per file. |

The first two share a cause: the rules read comments as code. Stripping comment spans
before matching would close both, and would turn the silencing case from a lost
accessibility finding into a reported one.

The third and fourth are separate. Widening the hex pattern is contained. Deciding motion
across files is not: the rule would need the set of stylesheets that load together, which
a one-awk-pass-per-file design does not have.

## The compliant page is not a demo

`index.html` and `styles/` are written to produce **zero findings**. They are a positive
control: if the gates report anything here, the gates are wrong. The interesting content
is deliberately plain, because a reference for a linter should exercise the rules rather
than showcase a design.

Motion in `styles/motion.css` follows the `## Motion` contract from
[`autospec-design`](https://github.com/berlinguyinca/autospec-design): a named duration
scale, one easing per intent, an explicit list of what never animates, and a per-pattern
reduced-motion fallback that is opacity-only rather than absent.

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

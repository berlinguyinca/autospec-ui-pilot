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
    runs.html                      the induction reference: ordinary data-driven code,
                                   nothing added for the gate
    states.html                    the compliant test-hook reference: drivable app states
    api/runs.json                  the data runs.html fetches, and the gate intercepts
    styles/tokens.css              design tokens: duration scale, easing, colour
    styles/motion.css              animation, with its reduced-motion guard alongside
    styles/components.css          hover affordances, each with a focus equivalent
    fixtures/violations/           one file per rule, each expected to be flagged
    fixtures/known-gaps/           cases the rules get wrong, in both directions
    fixtures/live-regions/         one route per announcement rule — induce-*.html need no
                                   hook at all; the rest are driven through one
    .autospec/ui-test-hooks.json   the states this repository declares as drivable
    .autospec/a11y-baselines/      committed accessibility trees, one per route
    EXPECTED.tsv                   path, rule id, verdict — the calibration contract
    EXPECTED-live.tsv              the same contract for the announcement gate
    check.sh                       runs the static gate and diffs it against the contract
    check-liveregions.sh           serves the pages, induces and drives every state, diffs
    check-a11y.sh                  compares each page's accessibility tree to its baseline

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
| `UI_NO_REDUCED_MOTION` over-fired across files — a global reset with unguarded components, the ordinary way to organise CSS, drew a finding on every component | fixed |

All five are closed. The first two shared a cause: the rules read comments as code. The
silencing one is the one worth remembering — a false positive costs an afternoon, that one
lost an accessibility finding quietly. It surfaced because the corpus's *intended*
`UI_NO_REDUCED_MOTION` violation came back clean: the comment explaining what was missing
was itself what suppressed the finding.

The cross-file case is now satisfied by a reset targeting the universal selector, which
genuinely guards every element on the page. A component linted alone still reports, since
one file cannot carry evidence of a reset living in another — `check.sh` asserts both
halves, because a per-file table cannot express a rule that depends on the set.

## Runtime device evidence

`ui-device-evidence.mjs` renders each route across real device descriptors — iPhone, iPad
in both orientations, Pixel, desktop — and runs reflow at 320 CSS px and 200% zoom.

    node autospec/skills/autospec-shared/scripts/ui-device-evidence.mjs \
      --base-url http://127.0.0.1:8731 --routes /index.html

    ok /index.html: 5 profiles, reflow 320px, zoom 640px

This tier found a defect in `index.html` that every static rule missed: the branch filter
input rendered 185x21, under the 24px WCAG 2.5.8 minimum, on all four coarse-pointer
profiles. `components.css` sets `min-height` on `.button` and said nothing about inputs,
and a control's rendered size depends on the user agent — no amount of source analysis
reaches it. That is the argument for measuring the running page.

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

## Live-region announcements

Every tier above reads a page; this one drives it. What is worth checking about a live
region is a **transition** — content already present when the page loads is never announced
by any screen reader — so the gate has to make the state change happen.

It does that two ways, and `runs.html` is the one that matters most, because **nothing was
added to it**. No hook, no manifest entry, no test attribute. It is an ordinary page that
fetches data and handles both outcomes:

```js
fetch('api/runs.json')
  .then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
  .then((runs) => { status.setAttribute('aria-busy', 'false'); render(runs);
                    status.textContent = 'Loaded ' + runs.length + ' runs.'; })
  .catch(() => { alertRegion.textContent = 'Could not load runs. Try again.'; });
```

autospec holds that fetch to watch the pending state, then releases it — once normally, once
as a 500 — and checks what a screen-reader user is told each time. The app runs its own
state machine. Nothing is clicked and nothing is mutated.

`fixtures/live-regions/induce-ignored.html` is the case that argues for this over a
declaration. It handles success correctly and has no `.catch` at all, so a failed request
produces *nothing*: no render, no message, no indication. The page sits on "Nothing loaded
yet." forever. Nobody writes a declared "error" state for a failure path they forgot to
handle, so a manifest-driven gate could only ever have checked the error handling that
already existed.

A page that makes no data request is reported as skipped with a reason. `index.html` is
static; it has no state to drive, and saying so is different from saying it was checked.

## The declared half, for what induction cannot reach

Form validation, optimistic updates, client-side route changes, empty states — no request
produces any of them, so no interception can induce them. Those are declared, and
`states.html` is the reference an application copies:

```js
window.__autospec = {
  setState(name) { states[name](); },
};
```

`.autospec/ui-test-hooks.json` declares what to drive:

```json
{ "route": "/states.html",
  "states": [ { "name": "loading", "kind": "status", "busy": true },
              { "name": "error",   "kind": "alert" },
              { "name": "success", "kind": "status" } ] }
```

Two fields are declared rather than inferred, and both were forced by building the corpus:

- **`kind`** — assertive is right for an error and wrong for a routine result, and deciding
  that from a *state name* is a regex pretending to be a judgement. "error" is obvious;
  "timeout", "partial" and "validation-failed" are not.
- **`busy`** — a loading state is *supposed* to leave `aria-busy` set. Within a single
  driven state that is indistinguishable from a flag left stuck, so the honest options were
  to declare it or to drop the rule.

Run it with `./check-liveregions.sh ./autospec`, which serves this directory, drives every
declared state, and diffs the result against `EXPECTED-live.tsv`:

    check-liveregions.sh: OK — 10 rows match the contract

The corpus in `fixtures/live-regions/` carries one route per rule. The one worth
understanding is `inserted-with-content.html`, because it looks correct:

```js
const region = document.createElement('p');
region.setAttribute('role', 'status');
region.textContent = 'Loaded 1 run.';       // ← the bug
document.querySelector('main').appendChild(region);
```

The region and its text enter the page together, so there is no change for a screen reader
to observe and nothing is announced. `states.html` differs only in shipping the empty
region in the markup and filling it later.

That distinction is also where the gate was nearly wrong. A region appended empty and
filled on a *later* task emits the same insertion event, so "any inserted region is a bug"
fails the correct dynamic pattern. Measuring the two in Chromium showed the discriminator
is whether the region carried text when the observer's records were delivered — which lands
exactly on the frame boundary a screen reader uses, since a region created and filled within
one task is not announced either. Both cases are checked in, and both are load-bearing.

## Accessibility-tree baselines

The gates above ask questions with fixed answers. This one asks whether these pages still
expose what they used to, which is the only way to catch a *regression* rather than a
violation — a `<button>` refactored into a clickable `<div>` satisfies the lint, the device
profiles, the keyboard robot and axe.

    ./check-a11y.sh ./autospec

    ok /index.html: 22 nodes match the baseline
    ok /runs.html: 8 nodes match the baseline
    ok /states.html: 6 nodes match the baseline
    check-a11y.sh: OK — trees match the committed baselines

The trees live in `.autospec/a11y-baselines/`, committed. `runs.html` is worth reading,
because it shows what a baseline captures once the page has settled rather than at `load`:

    - main:
      - heading "Runs" [level=1]
      - status: Loaded 3 runs.
      - alert
      - list:
        - listitem: run-104 passed

Deleting that `h1` — replacing it with a styled `div`, the most ordinary refactor there is —
reports `A11Y_ROLE_LOST`. Nothing else in the pipeline notices.

Two properties make this usable rather than noisy, and both were measured before the gate was
designed. Renaming a class, wrapping a table in a scroll container, reordering attributes and
renaming an id all leave the tree **byte-identical**. And the format separates an accessible
name (quoted) from mere content (after a colon), so `listitem: run-104 passed` carries no
name and a data change cannot report a lost one.

Accepting an intentional change is `./check-a11y.sh ./autospec --update`, then reading and
committing the diff — a reviewable act rather than a silent one.

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

# Design QA

## Visual truth

- Day schedule reference: `C:\Users\30360\AppData\Local\Temp\codex-clipboard-31f733d7-3d18-47fa-b796-f9c2356fb169.png` (1280 x 2780).
- Add-course reference: `C:\Users\30360\AppData\Local\Temp\codex-clipboard-846501f0-fca8-421c-89fe-d185d140cff7.png` (1280 x 2780).
- Day schedule implementation: `artifacts/visual-qa-35072320951/day-schedule.png` (1206 x 2622).
- Add-course implementation: `artifacts/visual-qa-35072320951/add-course.png` (1206 x 2622).
- Normalized comparisons: `artifacts/visual-qa-35072320951/day-comparison.jpg` and `artifacts/visual-qa-35072320951/add-course-comparison.jpg`.

The implementation was captured on an iPhone 16 Pro simulator at native 3x density. The reference and implementation were normalized to matching 260 x 566 panels for side-by-side comparison.

## Tested states

- Day schedule for 2026/9/16 with sample courses and a visible next-course summary.
- Blank add-course form, including color, credits, week range, weekdays, class sections, custom time, classroom, teacher, notes, and reminder controls.
- CSV, JSON, and ICS import parsing through automated tests.
- Weekly timetable paging gesture and directional spring transition through code review and simulator launch; the still screenshots do not attempt to represent motion frames.

## Findings and iteration history

1. CI run `35068948868`: the date used an English locale and the system steppers wrapped the week and section labels. Fixed by forcing the Chinese numeric date format and replacing the steppers with compact counters.
2. CI run `35069970301`: the section suffix still wrapped vertically. Fixed by changing the compact sentence to “从 N 起 M 节”.
3. CI run `35072320951`: no P0, P1, or P2 visual issues remained. The page hierarchy, warm background, rounded cards, colored accents, spacing, and tap targets match the reference direction.

## Intentional differences

- The reference advertisement and promotional illustration are not product functionality, so the implementation replaces them with an actionable next-course summary and contains no ads.
- The native app uses SF Symbols and system typography for consistency and accessibility.

## Final result

passed

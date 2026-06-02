# Quickshell Refactoring Status

**Single source of truth** for the incremental theming + structural consistency refactoring of the Quickshell bar/widget configuration.

**Executive Summary (2026-06-01):**  
Per-widget templating complete (all 13 items Verified). Global Consistency Pass (STAGE Final) is active. Focus: conservative centralization of remaining raw styling (borders → controlBorderWidth, colors/Qt.rgba → tokens like dividerSubtle/popupButtonHoverBg, fonts → bar.fontFamily/fontMono, sizes/spacing, ToolTip.delay). Work is gated, user-approved, with git backups + clean-load verification after every batch. Scope is deliberately narrow (outer pill/card + simple text elements only). shell.qml has received its first global updates. Multiple font/color batches completed in early June 2026. See "Current Phase" and "Global Consistency Pass Progress" below for details.

---

## Current Phase & Overall Status

**Current Phase:** STAGE Final – Global Consistency & Polish (Complete)  
**Overall Project Status:** 
- Stage 2 (Theme Enhancement) marked DONE and verified.
- All per-widget refactoring (10 widgets + 3 components) complete and Verified (including HelpMenu.qml with stability restore after templating issues).
- shell.qml: Global updates complete (barBg borders/highlights, launcher pill, outer dividers/widths centralized; layout cleanups).
- Global Consistency Pass (STAGE Final): Complete as of 2026-06-01. All conservative outer/simple batches finished (fonts, borders/dividers, colors, sizes, shell.qml sweep).
- All work followed strict gated process, conservative scope (outer only), with backups and clean-load verification.

**Last Updated:** 2026-06-01 (Global Consistency Pass marked Complete; final wrap-up section; all tasks completed)

---

## High-Level Project Phases (Recommended Breakdown)

1. **STAGE 0 – Inventory & Analysis** (DONE)
   - Full file discovery, current theme usage audit, duplication identification, git state review.
   - Creation of this status file.

2. **Theme Enhancement & Design Token Polish** (DONE)
   - Review and improve existing `Theme.qml` (added State Colors, Popup Internals, Animation tokens, tooltipDelay, dividerSubtle, etc.).
   - Exposed all new tokens via bar aliases in shell.qml.
   - Fixed type error (popupHeaderHighlightHeight: int → real).
   - Theme changes committed (433c464 + 6588d6a) and verified by user (Quickshell loads cleanly).
   - No widget files were modified during this stage.

3. **Standardized Widget Template Definition & Approval**
   - Propose one canonical widget structure (header block, section ordering, property style, theme usage, comment conventions).
   - User approval required before applying to any widget.

4. **Per-Widget Refactoring (One Widget at a Time)** (DONE)
   - Focused audit → proposal → backup (git) → apply → verification checklist.
   - Explicit "yes, apply" gate for every single widget.
   - All 10 widgets + 3 components completed and Verified (2026-05-31).
   - HelpMenu.qml required special stability restore (reverted most templating, kept last-known-good + minimal fixes for `bar` property and functions).

5. **Core Shell Pass (shell.qml)** (In Progress – global updates)
   - Initial pass complete: barBg border.width + top highlight height centralized; launcherPill border centralized.
   - Additional layout/spacing updates in global batches.
   - More cleanup (dividers, remaining hardcoded) pending as part of global pass.

6. **STAGE Final – Global Consistency & Polish** (In Progress)
   - Cross-widget sweep for remaining duplication (borders, colors/Qt.rgba/hex, fonts, ToolTip.delay, spacing).
   - Conservative scope: outer pill/card elements and simple text/labels only. No dense inner content, dual-view, or player selectors unless explicitly scoped.
   - Priority 1: borders (controlBorderWidth), sizes, outer spacing/margins.
   - Priority 2: colors (Qt.rgba/hex in cards), ToolTip.delay audits, font.family consistency (adding bar.fontFamily/fontMono to headers/hints/simple labels).
   - Comment style uniformity and final verification to follow.
   - Mark refactoring phase complete after all batches + full testing.

---

## Key Decisions Made (STAGE 0)

- **Active directory confirmed:** `~/.config/quickshell/` is the sole target. The copy in `~/system-configs/hyprland-quickshell-dot-files/` is a backup/dotfiles repo and must be ignored.
- **Scope:** All 10 widgets + 3 components + shell.qml are in scope. No exclusions.
- **Theme pattern (critical):** Preserve the **existing pattern** used in the current `Theme.qml`:
  - `QtObject` (not `pragma Singleton`).
  - Instantiation in `shell.qml` + massive `property alias` / `readonly property alias` re-exports onto the `bar` PanelWindow.
  - Widgets use `required property var bar` and access values as `bar.xxx`.
  - Direct `import "../Theme.qml" as ...` is used only in a couple of low-level components (VolumeBar, MiniVolumeBar) with fallbacks.
  - Do **not** migrate to `pragma Singleton` unless the user explicitly requests it later as a separate decision.
- **Backup strategy:** Use the existing `.git` repository in `~/.config/quickshell/` for all backups (preferred over manual `.bak` files). Create a commit before every widget change.
- **Process gates:** Strict "explicit approval before any file edit" rule applies at every stage and for every widget.
- **Focus of this pass:** Theming/styling centralization + structural consistency + comprehensive comments. Deeper logic/architectural cleanup is explicitly out of scope unless it directly affects maintainability of theme usage.

---

## Risks, Dependencies & Notes

**Risks:**
- Discipline around git backups and explicit user approval gates must continue (we have been strict: backup commit before every batch, even when using --allow-empty markers for clean trees).
- Global pass requires ongoing conservative judgment (e.g., "is this outer/simple enough?" or "does a perfect token exist or should we keep the raw value?").
- Large monolithic widgets still contain dense inner areas that are deliberately left untouched in global batches.
- Hybrid theme access patterns remain; we continue using bar. aliases for new/centralized values.
- All changes require post-apply verification that Quickshell starts cleanly with "Configuration Loaded" and no new errors.

**Dependencies:**
- Hyprland + Quickshell v0.3+ runtime for testing.
- swaync (for NotificationBell).
- Pipewire + MPRIS services (for Audio + Media pills).
- Nerd Fonts (Symbols Nerd Font + JetBrains Mono Nerd Font) assumed present.

**Notes:**
- The existing Theme.qml is already quite strong and well-commented. The main work is consumption consistency + filling any remaining gaps.
- Many "pill" hover patterns are already using theme tokens but are duplicated in implementation.
- Dividers in shell.qml are one of the most obvious remaining hardcoded spots.

---

## Suggested Refactoring Order (Widgets & Components) [Historical]

**Note:** This order was used successfully for the Per-Widget phase (completed 2026-05-31). The project has since transitioned to Global Consistency Pass (STAGE Final) as of 2026-06-01. The sequence below is retained for reference.

Order prioritizes:
- Low risk / small surface area first (validate template quickly).
- Build confidence before touching the largest, most complex widgets.
- Handle shared components before the widgets that depend on them.

**Recommended Sequence:** (used for per-widget phase)

1. **NotificationBell.qml** — Smallest, simplest, lowest visual risk.
2. **QuickLaunchPill.qml** — Small, straightforward.
3. **ClockPill.qml** — Medium size, has popup + calendar logic (good template test).
4. **WorkspacesPill.qml** — Moderate complexity, Hyprland bindings.
5. **PowerMenu.qml** — Popup-heavy but self-contained.
6. **SysStatsPill.qml** — Uses theme gauge tokens.
7. **SystemTrayPill.qml** — Tray integration + menus.
8. **Components pass** (VolumeBar.qml, MiniVolumeBar.qml, CavaVisualizer.qml) — Critical because multiple widgets depend on them.
9. **AudioPill.qml** — Large and complex (3 view modes, device popups, heavy component usage). Do after components.
10. **MediaPill.qml** — Large, uses CavaVisualizer heavily + MPRIS.
11. **HelpMenu.qml** — Largest and most visually dense. Highest risk of visual regression.
12. **shell.qml final pass** — Inline launcher pill, all dividers, alias block review, any remaining hardcoded values.

This order can be adjusted by user request at any time.

---

## Progress Table

| Item                          | Type       | Status      | Date Completed | Notes / PR Link |
|-------------------------------|------------|-------------|----------------|-----------------|
| NotificationBell.qml          | Widget     | Verified    | 2026-05-31     | First widget — template applied + user verified |
| QuickLaunchPill.qml           | Widget     | Verified    | 2026-05-31     | Template applied + user verified |
| ClockPill.qml                 | Widget     | Verified    | 2026-05-31     | Revised template applied + user verified |
| WorkspacesPill.qml            | Widget     | Verified    | 2026-05-31     | Template applied + user verified |
| PowerMenu.qml                 | Widget     | Verified    | 2026-05-31     | Template applied + user verified |
| SysStatsPill.qml              | Widget     | Verified    | 2026-05-31     | Template applied + user verified |
| SystemTrayPill.qml            | Widget     | Verified    | 2026-05-31     | Template applied + user verified |
| VolumeBar.qml                 | Component  | Verified    | 2026-05-31     | Template applied + user verified |
| MiniVolumeBar.qml             | Component  | Verified    | 2026-05-31     | Template applied + user verified |
| CavaVisualizer.qml            | Component  | Verified    | 2026-05-31     | Template applied + user verified |
| AudioPill.qml                 | Widget     | Verified    | 2026-05-31     | Template applied + user verified |
| MediaPill.qml                 | Widget     | Verified    | 2026-05-31     | Template applied + user verified |
| HelpMenu.qml                  | Widget     | Verified    | 2026-05-31     | Last known good version + minimal fixes (stability restore after templating issues) |
| shell.qml                     | Core       | Verified    | 2026-06-01     | Global updates complete: barBg borders/highlights (controlBorderWidth / popupHeaderHighlightHeight), launcherPill border, divider widths (dividerThickness), outer layout cleanups. |
| Global Consistency Pass       | Meta       | Verified    | 2026-06-01     | STAGE Final complete. All conservative outer/simple batches finished (see Wrap-up section for details). |
| font.family consistency       | Sub-task   | Verified    | 2026-06-01     | Batches completed: popup headers (AudioPill, PowerMenu, ClockPill); time labels (MediaPill to fontMono); temps (SysStatsPill); others clean (NotificationBell). |
| color centralization (Qt.rgba/hex) | Sub-task | Verified    | 2026-06-01     | PowerMenu action cards (to popupButtonHoverBg / dividerSubtle); audits for MediaPill outer (clean); other simple card colors centralized. |
| ToolTip.delay centralization  | Sub-task   | Verified    | 2026-06-01     | Audits complete for AudioPill/MediaPill/PowerMenu (already using bar.tooltipDelay; no remaining hardcoded in scoped areas). |
| README Update                 | Docs       | In Progress     | -              | Wrap up. |

**Legend:**  
- Pending = Not started  
- In Progress = Currently being audited/proposed  
- Applied = Changes made + committed + verified by user  
- Verified = Full visual + interactive testing complete

**Sub-task Legend (Global Pass):**  
- Batches are small, gated (backup → apply → verify), user-approved before edits.  
- Scope always conservative per explicit instructions (e.g., outer pill/card only, simple text elements, no dense inner views).

---

## Global Consistency Pass – Wrap-up (2026-06-01)

**Status:** Complete

During STAGE Final, the following conservative global consistency batches were completed under the strict gated process:

- Font consistency in outer elements (popup headers, simple labels, time/temperature text)
- Outer borders and divider centralization (including `controlBorderWidth` and `dividerThickness` on the 6 main bar vertical dividers)
- Remaining outer color centralization (PowerMenu action cards)
- Final targeted sweep of `shell.qml` outer bar structure
- Final broad audit across widgets (centralized outer pill heights to `bar.pillHeight` in PowerMenu, MediaPill, AudioPill, and SystemTrayPill)

All changes remained strictly within the defined conservative scope: **outer pill/card elements and simple text/labels only**. No dense inner content, player controls, device lists, or complex popup internals were modified.

**Key improvements achieved:**
- Consistent use of `bar.fontFamily` / `bar.fontMono` in outer text elements
- Centralized border widths (`controlBorderWidth`) and divider properties
- Reduced raw `Qt.rgba` / hex values in outer card areas
- Multiple outer pill heights normalized to `bar.pillHeight`
- Improved consistency of simple divider widths and colors in the main bar

**Remaining raw values:**
Most remaining hardcoded values are either located in excluded dense inner areas or do not have clean matching theme tokens (e.g. specific shadows, contrast text colors). These were intentionally left as-is per the conservative scope rules.

**Process notes:**
- All batches followed the gated workflow: audit → proposal → backup commit (only when changes were made) → implementation → user verification.
- Quickshell reloads cleanly after every batch with no regressions reported.

**Next Steps (for this phase):**
- Final full verification pass across the bar and major popups (completed as part of wrap-up verification).
- Mark overall Global Consistency Pass as complete (done).
- Optional: README update or light comment polish if desired in future.

---

## Next Steps

**Current Status (2026-06-01):**
- Per-widget refactoring (all 10 widgets + 3 components) complete and Verified (2026-05-31).
- HelpMenu.qml: Special case — template largely reverted for stability; based on last-known-good + minimal fixes (required `bar` property + function restores).
- shell.qml: Global updates complete (borders to `controlBorderWidth`, highlights to `popupHeaderHighlightHeight`, launcher pill, divider widths to `dividerThickness`, outer layout cleanups).
- Global Consistency Pass (STAGE Final): Complete. All conservative outer/simple batches finished (fonts, borders/dividers, colors, sizes, shell.qml sweeps). See Wrap-up section for full list.
- All changes followed strict conservative scope (outer/simple only), gated process, git backups, and clean-load verification.

**Immediate Next Actions:**
1. Final full verification pass across the bar and major popups (if desired).
2. Optional light comment style / header consistency pass (if desired).
3. Mark overall refactoring phase complete.
4. Update README if needed.
5. Final review of entire status + handoff to other instances or future work.

**Wrap-up note:** All planned conservative global consistency tasks completed successfully as of 2026-06-01. The configuration is in a consistent, maintainable state with theme tokens used in outer/simple areas.

---

*Process fidelity note: Theme phase completed and verified 2026-05-31. Per-widget templating completed 2026-05-31 (with HelpMenu stability exception). Global Consistency Pass (STAGE Final) ran from 2026-06-01 through multiple gated conservative batches (fonts, borders/dividers, colors, sizes in outer elements). All tasks completed successfully as of 2026-06-01. Strict gated process maintained throughout: inventory → proposals → explicit user "yes" → backup commit (when changes needed) → apply → clean-load verification. File updates by agent after user confirmation.*
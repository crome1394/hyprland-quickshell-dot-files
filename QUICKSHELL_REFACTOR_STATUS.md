# Quickshell Refactoring Status

**Single source of truth** for the incremental theming + structural consistency refactoring of the Quickshell bar/widget configuration.

---

## Current Phase & Overall Status

**Current Phase:** Phase 3 – Per-Widget Refactoring (In Progress)  
**Overall Project Status:** 
- Stage 2 (Theme Enhancement) marked DONE and verified.
- Applying the approved Standardized Widget Template one widget at a time.
- Currently working on: QuickLaunchPill.qml (audit complete — proposal ready for review).

**Last Updated:** 2026-05-31 (user verified NotificationBell — audit for QuickLaunchPill.qml presented)

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

4. **Per-Widget Refactoring (One Widget at a Time)**
   - Focused audit → proposal → backup (git) → apply → verification checklist.
   - Explicit "yes, apply" gate for every single widget.
   - Widgets + components are in scope.

5. **Core Shell Pass (shell.qml)**
   - Inline launcher pill, dividers, layout, alias block hygiene, and any remaining hardcoded values.

6. **STAGE Final – Global Consistency & Polish**
   - Cross-widget sweep for remaining duplication.
   - Comment style uniformity.
   - Final verification (reload + visual/interactive testing across all widgets).
   - Update README if needed.
   - Mark refactoring phase complete.

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
- Git working tree is currently dirty (many modified files + HelpMenu.qml noise). We must be disciplined about committing before each change.
- Large monolithic widgets (AudioPill.qml ~30k, MediaPill.qml ~29k, HelpMenu.qml ~27k) may reveal internal duplication that tempts over-refactoring in this pass.
- Hybrid theme access (bar aliases vs direct imports in components) must be cleaned up carefully to avoid breaking bindings.
- Dynamic content (Repeater, Loader, popups, MPRIS, Pipewire, Hyprland IPC) exists in several widgets — hover states, sizing, and positioning must be verified after changes.
- Multi-monitor / HiDPI scaling behavior should be spot-checked (especially popup positioning via `barBg`).

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

## Suggested Refactoring Order (Widgets & Components)

Order prioritizes:
- Low risk / small surface area first (validate template quickly).
- Build confidence before touching the largest, most complex widgets.
- Handle shared components before the widgets that depend on them.

**Recommended Sequence:**

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

| Item                    | Type       | Status     | Date Completed | Notes / PR Link |
|-------------------------|------------|------------|----------------|-----------------|
| NotificationBell.qml    | Widget     | Verified   | 2026-05-31     | First widget — template applied + user verified |
| QuickLaunchPill.qml     | Widget     | In Progress| -              | Next: Small, straightforward |
| ClockPill.qml           | Widget     | Pending    | -              | Has popup |
| WorkspacesPill.qml      | Widget     | Pending    | -              | - |
| PowerMenu.qml           | Widget     | Pending    | -              | - |
| SysStatsPill.qml        | Widget     | Pending    | -              | - |
| SystemTrayPill.qml      | Widget     | Pending    | -              | - |
| VolumeBar.qml           | Component  | Pending    | -              | Direct Theme import |
| MiniVolumeBar.qml       | Component  | Pending    | -              | Direct Theme import |
| CavaVisualizer.qml      | Component  | Pending    | -              | - |
| AudioPill.qml           | Widget     | Pending    | -              | Large & complex |
| MediaPill.qml           | Widget     | Pending    | -              | Large, uses Cava |
| HelpMenu.qml            | Widget     | Pending    | -              | Very large |
| shell.qml               | Core       | Pending    | -              | Final pass |
| Global Consistency Pass | Meta       | Pending    | -              | STAGE Final |
| README Update           | Docs       | Pending    | -              | If needed |

**Legend:**  
- Pending = Not started  
- In Progress = Currently being audited/proposed  
- Applied = Changes made + committed + verified by user  
- Verified = Full visual + interactive testing complete

---

## Next Steps

**Current Status (2026-05-31):**
- Stage 2 – Theme Enhancement & Design Token Polish marked as DONE.
- Theme fully verified.
- NotificationBell.qml: Successfully refactored + user verified.

**Immediate Next Actions:**
1. Perform focused audit of QuickLaunchPill.qml.
2. Present proposed refactored version using the approved Standardized Widget Template.
3. Wait for explicit user approval ("yes, apply" or equivalent).
4. Only then: git backup commit → apply changes → commit.
5. Repeat the gated cycle for each subsequent widget.

**Do not edit this file manually.** All updates will be made by the refactoring agent after explicit user confirmation at each phase.

---

*Process fidelity note: Theme phase completed and verified 2026-05-31. Template application started same day.*
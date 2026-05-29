# Snapshot: Audio Popup Taller (+50% height)

**Date:** 2026-05-28  
**Parent snapshot:** 2026-05-28-audio-volume-widget-cycle-popup

## Change in this version
- Increased main audio controls popup (`audioPopup`) vertical size by ~50%:
  - `implicitHeight`: 210 → **315**
- Slightly increased inner margins (14 → 16) and spacing (14 → 16) for better balance in the taller container.
- Added a small bottom spacer so content doesn't feel pinned to the top.
- This gives more breathing room around the Playback/Recording sections, sliders, and buttons.

The bar widget behavior, cycle views, wheel/click controls, device selectors, and everything else remain identical to the previous version.

## Files
- `shell.qml` — bar with the taller audio popup
- `README.md` — this note

## Usage
Same as the previous audio widget snapshot. Right-click the audio pill (left of the clock) to open the now-roomier popup.

All other interactions (left-click cycle, wheel ±5%, middle-click mute, sliders, etc.) are unchanged.

Thanks for the feedback — this should feel much more comfortable!

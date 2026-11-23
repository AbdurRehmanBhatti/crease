# Design System — Crease

## Philosophy
Crease is an outdoor-legible, high-contrast cricket scoring interface modeled on architectural sports broadcasts rather than decorative glassmorphism. Clean cool-stone surfaces in daylight and true obsidian surfaces under lights keep match numerals effortless to read in direct sun while staying fast on budget Android hardware.

## Color Roles

### Light Theme (Primary Daylight Scheme)
| Role | Hex | Usage |
|---|---|---|
| Ground | `#F4F6F7` | Primary screen canvas |
| Elevated Surface | `#FFFFFF` | Match cards, crease table, bottom sheets |
| Key / Control Fill | `#F6F8F9` | Keypad tiles, input fills, inset stat tiles |
| Ink Primary | `#101315` | Score numerals, active player names, headings |
| Ink Secondary | `#5D666E` | Overs, run rates, metadata, captions |
| Hairline | `#E2E6E9` | 1px surface and control borders |
| Hairline Subtle | `#ECEFF2` | Row dividers and nav bar rule |
| Pitch Green (Accent) | `#0B7A4B` | Live status, striker bar, `4` & `6` keys, primary CTA |
| Wicket Red | `#D63949` | `W` ball badge, `Wicket` and `Run out` controls |
| Chart Secondary | `#3A5A78` | Multi-innings comparison series |

### Dark Theme (Night-Match Obsidian Scheme)
| Role | Hex |
|---|---|
| Ground | `#0D0F11` |
| Elevated Surface | `#15191C` |
| Key / Control Fill | `#1E2327` |
| Ink Primary | `#F4F6F8` |
| Ink Secondary | `#8E98A1` |
| Hairline | `#262C31` |
| Pitch Green | `#19A96B` |
| Wicket Red | `#EC5463` |

## Typography
- **UI & Headings:** `Plus Jakarta Sans` (`google_fonts`) in sentence case with crisp weight hierarchy (`w500`, `w600`, `w700`).
- **Scoreboard & Numeric Figures:** `Barlow` (`google_fonts`) with `FontFeature.tabularFigures()` enabled on scores, overs, run rates, keypad digits, and codes so numerals never shift mid-over.
- **Live Score:** `60sp` bold (`w700`) for runs paired with `46sp` medium (`w500`) muted `/wickets`.

## Shape & Elevation Scale (`CreaseRadius`)
- **Sheets (top):** `24dp`
- **Cards:** `16dp`
- **Controls, Inputs, Buttons & Keypad Tiles:** `12dp`
- **Badges & Tags:** `8dp`

## Motion & Haptics
- **Tactile Press:** `CreasePressable` applies subtle `0.94–0.985` scale feedback on tap and respects Android's Remove Animations accessibility setting.
- **Haptics:** `lightImpact` on normal runs, `mediumImpact` on `4` and `6`, `heavyImpact` on `Wicket`, `selectionClick` on tab switches, undo, strike swap, and extras.

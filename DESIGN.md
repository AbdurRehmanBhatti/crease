# Design System — Crease (Daylight Glass)

## Philosophy
**Daylight Glass** is an outdoor-legible, minimal, layered Android Material 3 design system built for real cricket ground conditions. Rather than the dark-navy-and-neon-card template that washes out in direct sunlight, Crease places monumental score numerals directly on a cool near-white ground (`#EEF3F3`) with a whisper-soft sage top wash, paired with translucent frosted-white glass surfaces, 1px hairline borders, and diffuse shadows.

## Color Roles

### Light Theme (Primary Outdoor Scheme)
| Role | Hex | Usage |
|---|---|---|
| Ground | `#EEF3F3` | Primary screen canvas |
| Sage Wash Top | `#E3F0EA` | Subtle top gradient wash |
| Frosted Glass | `#CCFFFFFF` | Cards, batter pills, dialogs (with 10–14px blur) |
| Frosted Sheet | `#E8F6F8F8` | Raised bottom scoring sheet |
| Key Surface | `#F2FFFFFF` | Scoring pad numeral & extra keys |
| Ink Primary | `#0A0C0C` | Monumental score, active names, key numerals |
| Ink Secondary | `#5B6560` | Overs, RRR, bowler figures, captions |
| Hairline | `#D5DFDD` | 1px borders on glass surfaces & segmented controls |
| Pitch Green (Accent) | `#098558` | Strictly reserved for LIVE dot, striker hairline, `4` & `6` keys, primary CTA |
| Wicket Red | `#D74956` | Strictly reserved for `W` ball badge and `Wicket` key |

### Dark Theme (First-Class Night-Match Scheme)
| Role | Hex |
|---|---|
| Ground | `#0E1413` |
| Sage Wash Top | `#13221C` |
| Frosted Glass | `#CC182220` |
| Frosted Sheet | `#EB151D1B` |
| Key Surface | `#1E2926` |
| Ink Primary | `#F2F6F5` |
| Ink Secondary | `#9AA8A2` |
| Hairline | `#2B3834` |

## Typography
- **Font family:** Inter (`google_fonts`), with `FontFeature.tabularFigures()` enabled on all score, overs, run-rate, and scorecard numerals so digits never jitter mid-over.
- **Monumental Score:** `64sp` — light (`w300`) for runs, medium (`w500`) for `/wickets`, tight `-2.2` tracking.
- **Keypad Numerals:** `28sp`, regular (`w400`), centered inside `64dp` tall keys (`>= 48dp` Android touch target minimum).
- **Body / Labels:** `14–16sp`, scales dynamically with Android system `font_scale`.

## Surfaces & Elevation
- **Open Score:** No card container — sits directly on the ground for maximum contrast and breathing room.
- **Glass Surfaces:** `GlassSurface` (`app/lib/widgets/glass_surface.dart`) combines `BackdropFilter(sigma: 10–14)`, translucent fill, `1px` hairline border, and a soft diffuse downward shadow (`blurRadius: 20, offset: (0, 6)`).
- **Radii:** `28dp` top sheet, `24dp` batter pills & segmented bar, `20dp` cards, `18dp` keypad tiles.

## Motion & Haptics
- **Haptics:** `lightImpact` on normal runs, `mediumImpact` on `4` and `6`, `heavyImpact` on `Wicket`, `selectionClick` on undo/strike-swap/extras.
- **Android Native Guarantees:** Edge-to-edge system bars with `SafeArea`, Material 3 bottom sheets, predictive Back support, and RTL-ready flex layouts for future Urdu support.


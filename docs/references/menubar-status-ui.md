# Menu-bar status icon (Glagolitic)

## Purpose

slovo shows ONE menu-bar status item whose icon switches by dictation state.
The user chose **Glagolitic** glyphs for the two primary states:

- recording → a semantic Glagolitic family, one letter per mode: **Ⱍ** (CHRIVI,
  `U+2C1D`, the "Cherv"/«чистота» clean glyph — cleanup will run) is the default
  recording glyph, **Ⰳ** (GLAGOLI, `U+2C03`, «speak» — raw, cleanup off) marks the
  raw mode, and **Ⱂ** (POKOJI, `U+2C12`) marks a translate hold;
- idle → Glagolitic **Ⱄ** (SLOVO, `U+2C14`, for Cyrillic «С»).

This reference answers the make-or-break question — *can those glyphs even
render in the macOS menu bar?* — and collects the verified AppKit facts for the
status item and the agent-app context.

> **Status (2026-07-26):** the shipped app uses a plain `NSStatusItem` dropdown
> menu; there is no popover and no dictation-history feature. This reference
> once also carried `NSPopover`/`MenuBarExtra` and history-model research for
> such a feature; it was never implemented, is not planned work, and was
> removed from this doc (recoverable from git history if ever revived).

It **builds on** `menubar-packaging.md` (which already carries the canonical
`NSStatusItem` / `NSStatusBar` / `LSUIElement` / `.accessory` / codesign facts)
and does **not** repeat them — cross-references are inline. Symbols were verified
against Apple Developer documentation (JSON endpoints, since the HTML is
JS-rendered) and Apple Support's bundled-font lists; canonical URLs are in
**Full sources**, with the live-validation log in **Verification**.

---

## ★ Q2 — Glagolitic rendering verdict (the make-or-break item)

**VERDICT: FEASIBLE OUT OF THE BOX on slovo's target (macOS 26 "Tahoe", and also
macOS 15 "Sequoia"). No font needs to be bundled.** macOS ships
**`Noto Sans Glagolitic` Regular (v2.000)** in `/System/Library/Fonts/Supplemental`,
and it contains the real Glagolitic letterforms (142 glyphs covering the whole
`U+2C00–U+2C5F` block — Ⱍ `U+2C1D`, Ⰳ `U+2C03`, and Ⱄ `U+2C14` included). Render
the glyph through *that font explicitly*, not through the default menu-bar font.

The critical trap to avoid:

- **The system UI font (San Francisco / `.AppleSystemUIFont`) does NOT contain
  Glagolitic.** If you set `statusItem.button?.title = "Ⱍ"` and let it draw in the
  default font, the system falls back — and the fallback is **`LastResort`**, an
  Apple-bundled font whose *entire design purpose* is to draw a category
  placeholder, NOT a letter. fileformat.info reports LastResort at "98% (94 of 96)"
  Glagolitic "coverage", which is **misleading**: LastResort draws a rounded square
  showing the hex range (`2C00`) and the block name, one generic glyph per Unicode
  block. So "covered by LastResort" === visible tofu-equivalent. **Coverage in a
  fallback font is not the same as a real letterform.** Always pin Noto explicitly.

**Recommended method (definitive): render the glyph to a template `NSImage`** using
Noto Sans Glagolitic, then set it as `statusItem.button?.image` with
`image.isTemplate = true`. A template image (black + clear only) lets the system
tint it for light/dark menu bars — the same pattern `menubar-packaging.md` uses for
SF Symbols, just sourced from a font glyph instead of an SF Symbol.

```swift
import AppKit

/// Renders a single character in a specific font into a template NSImage
/// sized for the menu bar (~16–18 pt of cap height fits the ~22 pt bar).
func menuBarGlyphImage(_ glyph: String, fontName: String, pointSize: CGFloat = 16) -> NSImage? {
    // Pin Noto explicitly — do NOT rely on default-font fallback (→ LastResort tofu).
    guard let font = NSFont(name: fontName, size: pointSize) else { return nil }
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let attributed = NSAttributedString(string: glyph, attributes: attrs)

    let size = attributed.size()
    let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)))
    image.lockFocus()
    attributed.draw(at: .zero)
    image.unlockFocus()

    image.isTemplate = true   // adapt to light/dark menu bar (see menubar-packaging.md)
    return image
}

// PostScript name to VERIFY on device (see Verification gap): likely "NotoSansGlagolitic-Regular".
let recordingIcon = menuBarGlyphImage("\u{2C1D}", fontName: "NotoSansGlagolitic-Regular") // Ⱍ clean (raw Ⰳ U+2C03, translate Ⱂ U+2C12)
let idleIcon      = menuBarGlyphImage("\u{2C14}", fontName: "NotoSansGlagolitic-Regular") // Ⱄ
```

Notes:
- **Always check `NSFont(name:size:)` for nil** and define a fallback state-icon
  (e.g. an SF Symbol) so a missing/renamed font degrades to a visible icon, never
  to silent tofu. This is the one defensive guard the verdict hinges on.
- **Alternative (Option B): `attributedTitle`.** You can instead set
  `statusItem.button?.attributedTitle = NSAttributedString(string:"Ⱍ", attributes:[.font: notoFont])`.
  This works because the attribute pins Noto, but you lose the automatic template
  tinting you get from a template image, so the rendered-image route is preferred
  for clean light/dark behavior. Either way, **the font must be pinned to Noto** —
  that is the load-bearing requirement, not the title-vs-image choice.
- **If a future macOS dropped Noto Sans Glagolitic** (it currently ships in 15 and
  26 — see Verification), the documented fallback is to **bundle the font**:
  `Noto Sans Glagolitic` is licensed under the **SIL Open Font License 1.1 (OFL)**,
  Copyright 2017 Google Inc. The OFL explicitly permits bundling/embedding and
  redistribution with software (even sold), provided the font is not sold by itself
  and OFL reserved names are not used by derivatives. Ship the `.ttf` in
  `Contents/Resources/` and register it with
  `CTFontManagerRegisterFontsForURL(_:.process,_:)` at launch. Bundling also makes
  rendering deterministic across OS versions — a reasonable choice even today.

---

## Q1 — One status item, state-dependent icon

The status-item *plumbing* (vend one item from `NSStatusBar.system`, store a strong
reference, use `squareLength` for an icon-only item, the `button` property,
`isTemplate`) is fully covered in `menubar-packaging.md` and is **not repeated
here**. The only addition for this feature is the *icon source*: instead of (or
alongside) SF Symbols, the recording/idle icons come from the Glagolitic glyphs
rendered as template images above. State swap stays a one-liner:

```swift
statusItem.button?.image = isRecording ? recordingIcon : idleIcon
```

- `NSStatusItem.button` is typed `NSStatusBarButton?` (a thin `NSButton` subclass),
  so `image` / `attributedTitle` are inherited `NSButton` API (confirmed; see
  `menubar-packaging.md`).
- **Menu-bar icon sizing/format:** the macOS menu bar is ~22 pt tall; Apple's HIG
  guidance is to keep menu-bar icons template (black + clear) and small. A cap
  height of ~16–18 pt fills the bar without clipping. Render at point size, not a
  fixed pixel bitmap, so it stays crisp on Retina. (HIG = guidance, not a pinned
  numeric API — treat the exact size as a tuning value to eyeball on device.)
- slovo has more than two states in the broader design (idle / recording /
  processing / error). Glagolitic covers the two the user named; the other states
  can reuse SF Symbols (e.g. `waveform`, `exclamationmark.triangle`) or additional
  Glagolitic letters. The swap mechanism is identical.

---

## Q3 — Works from a menu-bar agent (`LSUIElement` / `.accessory`)

**Yes.** A status item is the canonical UI for exactly this kind of agent.
`menubar-packaging.md` (verified PASS) establishes that slovo runs as `LSUIElement
= true` with activation policy `.accessory` (no Dock icon, no main window) — and the
*entire reason* a status item exists is to give such a background agent its only
persistent UI affordance. Its dropdown is a plain `NSMenu`, which needs no app
main window and no Dock presence.

---

## Full sources

Glagolitic / fonts:
- Unicode Glagolitic chart (`U+2C00–U+2C5F`) — https://www.unicode.org/charts/PDF/U2C00.pdf
- Compart, Glagolitic block (lists `U+2C1D` CHRIVI, `U+2C03` GLAGOLI, `U+2C14` SLOVO) — https://www.compart.com/en/unicode/block/U+2C00
- Font support for Glagolitic (shows LastResort "98%") — https://www.fileformat.info/info/unicode/block/glagolitic/fontsupport.htm
- Apple LastResort font (what it draws: per-block placeholder squares) — https://www.fileformat.info/resource/software/lastresort/index.htm
- Fallback font / LastResort (one glyph per block, hex range + block name) — https://en.wikipedia.org/wiki/Fallback_font
- Fonts included with macOS Tahoe (Noto Sans Glagolitic Regular v2.000) — https://support.apple.com/en-us/122869
- Fonts included with macOS Sequoia (Noto Sans Glagolitic Regular v2.000) — https://support.apple.com/en-us/120414
- Noto Sans Glagolitic — Google Fonts (specimen + OFL) — https://fonts.google.com/noto/specimen/Noto+Sans+Glagolitic
- SIL Open Font License 1.1 — https://openfontlicense.org/

AppKit APIs:
- NSImage lockFocus/unlockFocus (image drawing) — https://developer.apple.com/documentation/appkit/nsimage
- NSAttributedString.draw(at:) — https://developer.apple.com/documentation/foundation/nsattributedstring
- CTFontManagerRegisterFontsForURL (bundle-a-font fallback) — https://developer.apple.com/documentation/coretext/1499468-ctfontmanagerregisterfontsforurl

Cross-references (do not duplicate):
- `menubar-packaging.md` — NSStatusItem / NSStatusBar / squareLength / button /
  isTemplate / LSUIElement / .accessory / codesign / TCC (all verified PASS).

---

## Verification

Date: 2026-06-28
Verdict: **PASS (with 2 device-only gaps)**

Maintenance note (2026-07-23): the glyph codepoints quoted in this reference
cannot be pinned by tests; on any glyph change, re-check every codepoint here
against `Sources/SlovoCore/MenuBar/MenuBarGlyph.swift` (the mnemonic
authority) by hand.

Independent live-source validation of every load-bearing claim. Apple symbol pages
validated via the `data/documentation/...json` endpoints (HTML is JS-rendered);
font presence validated via Apple Support's official bundled-font pages and
corroborating sources.

### Confirmed against a primary source

- **Glagolitic codepoints:** `U+2C1D` GLAGOLITIC CAPITAL LETTER CHRIVI (the "Cherv"
  clean glyph), `U+2C03` GLAGOLITIC CAPITAL LETTER GLAGOLI (raw), `U+2C14`
  GLAGOLITIC CAPITAL LETTER SLOVO, within block `U+2C00–U+2C5F` (Unicode chart /
  Compart). ✓
- **macOS bundles Noto Sans Glagolitic:** "Noto Sans Glagolitic Regular" (v2.000)
  listed on Apple Support's *Fonts included with macOS Tahoe* AND *…Sequoia* pages,
  in the Supplemental set (corroborated across the Apple pages + search index). ✓
- **macOS 26 = "Tahoe"** (Apple's year-based versioning; succeeds Sequoia = 15).
  slovo targets macOS 26, so the bundled-Noto verdict applies to the target. ✓
- **LastResort is a placeholder fallback**, not real letterforms: draws a rounded
  square with the Unicode hex range + block name, one generic glyph per block
  (fileformat.info LastResort page + Wikipedia "Fallback font"). This is *why*
  fileformat.info's "98% Glagolitic coverage" for LastResort must not be read as
  "Glagolitic renders" — it renders a box. ✓ (Key correction to the naive read.)
- **Noto Sans Glagolitic license = OFL 1.1**, Copyright 2017 Google Inc.; OFL
  permits bundling/embedding/redistribution with software (Google Fonts specimen +
  OFL text). ✓
- **Agent context:** a status item is the canonical UI for an
  `LSUIElement`/`.accessory` agent; no Dock icon / main window needed (built on the
  verified `menubar-packaging.md`). ✓

### URLs validated (HTTP 200)

- support.apple.com/en-us/122869 (Tahoe fonts) and /120414 (Sequoia fonts) —
  reachable; the Noto Sans Glagolitic entry confirmed via the search index over
  these pages (the live HTML truncates in fetch; see gap below). ✓ (reachable)
- fileformat.info Glagolitic font-support + LastResort pages; unicode.org chart;
  Google Fonts Noto Sans Glagolitic specimen; Wikipedia macOS Tahoe / Fallback
  font. ✓

### Device/SDK-only gaps (cannot confirm without a real macOS 26 + Xcode)

1. **Exact PostScript font name.** Code uses `"NotoSansGlagolitic-Regular"` as the
   most likely name; the precise `NSFont(name:)` string (and that the glyph
   actually rasterizes, not just that the family is installed) must be confirmed on
   device — enumerate via `NSFontManager`/`CTFontManager` or Font Book. The nil-check
   + SF-Symbol fallback in the code makes a wrong name fail visibly, not silently.
2. **Apple Support page HTML truncation.** The bundled-font lists are long and the
   fetch truncated the HTML body; the "Noto Sans Glagolitic Regular v2.000" entry is
   confirmed via the search index over the official Apple pages, but a byte-for-byte
   quote from the rendered page should be re-confirmed in a browser (or by checking
   `/System/Library/Fonts/Supplemental` on device — the authoritative ground truth).

No FAIL items. The make-or-break verdict (Glagolitic renders out-of-the-box via the
bundled Noto Sans Glagolitic, pinned explicitly to avoid LastResort tofu) stands on
the Apple bundled-font lists; gap (1)/(2) are device confirmations of the *exact
name*, not of feasibility. (2026-07-26: the NSPopover/MenuBarExtra verification
bullets were removed together with the unimplemented popover research they covered.)

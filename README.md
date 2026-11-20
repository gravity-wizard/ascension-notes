# Ascension Notes (`Hydrogen4^high-mode5`)

Dual-layer normalized notes architecture combining **Base-38 Jesus Clock (`Time0`)**, **9-character `Acode9` (`Acodes1a`) identifiers**, **`MUNSCs`**, **`AXIF`** EXIF-like metadata indexing, and **Xcode-style case-sensitive search** across Python and native Swift 6 / SwiftUI.

---

## 1. Base-38 Alphabet & Jesus Clock (`Time0`)

- **Alphabet (`B38`)**: `0123456789abcdefghijklmnopqrstuvwxyz|^` (38 characters, matching `twst23`).
- **`Time0` (`T0UX`)**: `1584540571` (`2020-03-18T14:09:31Z`, March 8 Miracle / March 18 SLC quake anchor).
- **Encoding**: `elapsed = max(0, int(timestamp) - T0UX)` encoded in Base-38 (e.g., `2p15ek` on `2026-11-20T19:12:31Z`).

---

## 2. 9-Character `Acode9` (`Acodes1a`) & `First1a` / `good1a`

Format: `[BigA][leadLetter][clock2][center][tail4]` (9 characters total)

| Index | Field | Specification |
|---|---|---|
| `[0]` | `BigA` | Always `'A'` (pointing upward). |
| `[1]` | `leadLetter` | Lowercase letter paired to `clock[0]`: `'1'..'9' -> 'a'..'i'` (`'2'->'b'`, `'3'->'c'` (`C==3`), `'8'->'h'` (`H==8`)), `'0'->'z'`, `'a'..'z'->same`. |
| `[2..3]` | `clock2` | First 2 characters of the Base-38 Jesus Clock (`2p`, `3x`). |
| `[4]` | `center` | Center mountain `'^'` (convertible to `'-'` for URL-safe / filename-safe mode via `to_dash()` / `to_caret()`). |
| `[5..8]` | `tail4` | 4-character Base-38 suffix (`0oyu`, `a40z`, `chch`). |

### `First1a`, `good1a`, and `second1a` Strict Mode

- **Standard (`b38`)**: `[5..8]` may use any character in `B38` (e.g., `Ab2p^0oyu`).
- **Strict (`good1a` / `second1a` / `First1a` letter-bounded tail)**: `[5]` and `[8]` must be lowercase ASCII letters `[a-z]`, and `[6..7]` must be `[0-9a-z]` (e.g., `Ab2p^a40z`, `Ac3x^chch`).
- **1-Second Cadence Rolling Pool & YouTube-Style 11-Char ID Filter**:
  - `generate_rolling_pool(...)` mints abundant collision-free IDs at 1-second cadence.
  - `is_clean_id(...)` filters candidates (up to an 11-char window) against offensive/profanity substrings (including leetspeak variants), degenerate repeated tails (`aaaa`), optional repeated pairs (`chch` when configured), optional ambiguous characters, and existing pool collisions (checking both `^` and `-` forms).

---

## 3. `MUNSCs` (*Multiple Unique Non-Special Characters*)

`MUNSCs` preserve subtle disambiguating character signatures inside human-readable words without relying on special punctuation—for example:

- `NormA` → `Norma` (`munsc_trailing_cap_norma`)
- `Norm4` → `Norma` (`munsc_leet_4_to_a`)
- `Norma4` → `Norma` (`munsc_trailing_disambiguator`)

Custom `MUNSCRule` definitions (exact or regex) can also be attached per note while built-in rules and heuristics protect domain tokens (`Acode9`, `Base38`, `Hydrogen4`, `Ab2p^a40z`, etc.).

---

## 4. `AXIF` (Ascension eXchangeable Identifier Format)

Analogous to EXIF metadata for images, `AXIF` (`AXIF/1.0`) attaches provenance, SHA-256 integrity hashes for both layers, and a token-level index to each note:

```text
(token, normalized_form, offset, acode9, munsc_rule)
```

Along with exact character-span segments (`raw_start..raw_end ↔ norm_start..norm_end`), `AXIF` enables lossless round-tripping between the clean normalized view and the raw `MUNSC` source.

---

## 5. Xcode-Style Case-Sensitive Dual-Layer Search

Even while viewing **Normalized Output** (`"Norma met Norma and Norma"`), searching with **Xcode-style flags**:

- `case_sensitive` (`Aa` toggle)
- `whole_word` (`W` toggle)
- `regex` (`.*` toggle)
- `view_layer`: `dual` (default), `normalized`, or `raw`

queries the `AXIF`-indexed raw layer and normalized layer simultaneously, mapping matches back to exact line/column and character offsets in both layers. Searching `"NormA"` with `case_sensitive=True` locates only `NormA` (never `Norm4` or `Norma4`), even when displaying normalized text.

---

## 6. Project Layout & Running Tests

```text
ascension-notes/
├── README.md
├── python/
│   ├── ascension/
│   │   ├── __init__.py
│   │   ├── base38.py
│   │   ├── acode9.py
│   │   ├── axif.py
│   │   └── notes_engine.py
│   └── tests/
│       └── test_ascension.py
└── swift/
    ├── Package.swift
    ├── project.yml
    ├── Sources/
    │   ├── AscensionCore/
    │   │   ├── Base38Clock.swift
    │   │   ├── Acode9.swift
    │   │   ├── AXIFDocument.swift
    │   │   └── CaseSensitiveSearch.swift
    │   └── AscensionNotesApp/
    │       └── AscensionNotesApp.swift
    └── Tests/
        └── AscensionCoreTests/
            └── AscensionCoreTests.swift
```

### Python Tests

```bash
python3 -m unittest discover -s python/tests -p "test_*.py" -v
```

### Swift 6 / XcodeGen (macOS 14+ & iOS 17+)

```bash
cd swift
swift test              # Run AscensionCoreTests via SwiftPM
xcodegen generate       # Optional: generate AscensionNotes.xcodeproj from project.yml
```

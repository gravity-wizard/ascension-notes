"""Comprehensive unit tests for the Ascension Notes Python core."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import random
import sys
import unittest

# Ensure `python/` is on sys.path regardless of invocation CWD
PYTHON_ROOT = Path(__file__).resolve().parents[1]
if str(PYTHON_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_ROOT))

from ascension import (
    B38,
    B38_BASE,
    T0UX,
    AXIFMetadata,
    AscensionNote,
    AscensionNotesStore,
    MUNSCRule,
    clock2_from_timestamp,
    decode_base38,
    decode_jesus_clock,
    encode_base38,
    from_url_safe_base38,
    generate_acode9,
    generate_rolling_pool,
    is_clean_clock,
    is_clean_id,
    jesus_clock,
    jesus_clock_to_datetime,
    lead_letter_for_clock_char,
    parse_acode9,
    safe_jesus_clock,
    to_caret,
    to_dash,
    to_url_safe_base38,
    validate_acode9,
)


class Base38AndJesusClockTests(unittest.TestCase):
    def test_alphabet_and_epoch_constants(self) -> None:
        self.assertEqual(B38, "0123456789abcdefghijklmnopqrstuvwxyz|^")
        self.assertEqual(len(B38), 38)
        self.assertEqual(B38_BASE, 38)
        self.assertEqual(T0UX, 1584540571)
        t0_dt = datetime.fromtimestamp(T0UX, tz=timezone.utc)
        self.assertEqual(t0_dt, datetime(2020, 3, 18, 14, 9, 31, tzinfo=timezone.utc))

    def test_encode_decode_roundtrip(self) -> None:
        for val in (0, 1, 37, 38, 1443, 210661380, 999999999):
            enc = encode_base38(val)
            self.assertEqual(decode_base38(enc), val)

    def test_url_safe_dash_and_underscore(self) -> None:
        raw = "2p|^6a"
        safe = to_url_safe_base38(raw)
        self.assertEqual(safe, "2p_-6a")
        self.assertEqual(from_url_safe_base38(safe), raw)
        self.assertEqual(decode_base38(safe), decode_base38(raw))
        self.assertEqual(to_dash("Ab2p^|a^z"), "Ab2p-_a-z")
        self.assertEqual(to_caret("Ab2p-_a-z"), "Ab2p^|a^z")

    def test_safe_jesus_clock_pauses_on_666_and_bad_words(self) -> None:
        ts_666 = decode_jesus_clock("2666ab")
        reading = safe_jesus_clock(ts_666)
        self.assertTrue(reading.is_paused)
        self.assertEqual(reading.raw_clock, "2666ab")
        self.assertEqual(reading.clock, "2665^^")
        self.assertTrue(is_clean_clock(reading.clock))

        ts_bad = decode_jesus_clock("2shit1")
        bad_reading = safe_jesus_clock(ts_bad)
        self.assertTrue(bad_reading.is_paused)
        self.assertTrue(is_clean_clock(bad_reading.clock))

    def test_jesus_clock_2026_11_20_2p15ek(self) -> None:
        # 1584540571 + decode("2p15ek") == 2026-11-20T19:12:31Z
        ts = decode_jesus_clock("2p15ek")
        dt = jesus_clock_to_datetime("2p15ek")
        self.assertEqual(dt, datetime(2026, 11, 20, 19, 12, 31, tzinfo=timezone.utc))
        self.assertEqual(jesus_clock(ts), "2p15ek")
        self.assertEqual(clock2_from_timestamp(ts), "2p")

    def test_jesus_clock_clamps_before_t0(self) -> None:
        self.assertEqual(jesus_clock(T0UX - 500), "0")
        self.assertEqual(jesus_clock(T0UX - 500, min_width=2), "00")
        self.assertEqual(jesus_clock(T0UX), "0")


class Acode9Tests(unittest.TestCase):
    def test_lead_letter_pairing(self) -> None:
        self.assertEqual(lead_letter_for_clock_char("0"), "z")
        self.assertEqual(lead_letter_for_clock_char("1"), "a")
        self.assertEqual(lead_letter_for_clock_char("2"), "b")
        self.assertEqual(lead_letter_for_clock_char("3"), "c")
        self.assertEqual(lead_letter_for_clock_char("8"), "h")
        self.assertEqual(lead_letter_for_clock_char("9"), "i")
        self.assertEqual(lead_letter_for_clock_char("a"), "a")
        self.assertEqual(lead_letter_for_clock_char("z"), "z")

    def test_canonical_examples_parse_and_validate(self) -> None:
        for code in ("Ab2p^0oyu", "Ab2p^a40z", "Ac3x^chch"):
            parts = parse_acode9(code)
            self.assertEqual(parts.big_a, "A")
            self.assertEqual(parts.center, "^")
            self.assertEqual(parts.canonical, code)
            res = validate_acode9(code)
            self.assertTrue(res.valid, msg=f"{code} failed: {res.reasons}")

        # Verify specific strict mode expectations
        self.assertFalse(validate_acode9("Ab2p^0oyu", strict=True).valid)
        self.assertTrue(validate_acode9("Ab2p^a40z", strict=True).valid)
        self.assertTrue(validate_acode9("Ac3x^chch", strict=True).valid)

    def test_to_dash_and_to_caret(self) -> None:
        self.assertEqual(to_dash("Ab2p^a40z"), "Ab2p-a40z")
        self.assertEqual(to_caret("Ab2p-a40z"), "Ab2p^a40z")
        parts = parse_acode9("Ab2p-a40z")
        self.assertEqual(parts.to_dash(), "Ab2p-a40z")
        self.assertEqual(parts.to_caret(), "Ab2p^a40z")
        self.assertFalse(validate_acode9("Ab2p-a40z", allow_dash=False).valid)

    def test_invalid_acode9_cases(self) -> None:
        self.assertFalse(validate_acode9("Bb2p^a40z").valid)  # wrong BigA
        self.assertFalse(validate_acode9("Ac2p^a40z").valid)  # wrong leadLetter ('c' != 'b')
        self.assertFalse(validate_acode9("Ab2p_a40z").valid)  # invalid center
        self.assertFalse(validate_acode9("Ab2p^a40").valid)   # wrong length

    def test_youtube_style_id_filter(self) -> None:
        # Clean examples
        for code in ("Ab2p^0oyu", "Ab2p^a40z", "Ac3x^chch"):
            clean, reasons = is_clean_id(code)
            self.assertTrue(clean, msg=f"{code} rejected: {reasons}")

        # Offensive / profanity & leetspeak
        clean_bad, _ = is_clean_id("Ab2p^shit")
        self.assertFalse(clean_bad)
        clean_leet, _ = is_clean_id("Ab2p^sh1t")
        self.assertFalse(clean_leet)

        # Degenerate all-same tail
        clean_same, reasons_same = is_clean_id("Ab2p^aaaa")
        self.assertFalse(clean_same)
        self.assertIn("all_same_tail_pattern", reasons_same)

        # Configurable repeated pairs
        clean_pair, _ = is_clean_id("Ac3x^chch", block_repeated_pairs=True)
        self.assertFalse(clean_pair)

        # Collision check across caret and dash variants
        clean_dup, reasons_dup = is_clean_id("Ab2p-a40z", existing_pool={"Ab2p^a40z"})
        self.assertFalse(clean_dup)
        self.assertIn("pool_collision", reasons_dup)

    def test_generate_acode9_and_rolling_pool(self) -> None:
        ts = decode_jesus_clock("2p15ek")
        rng = random.Random(42)
        code = generate_acode9(ts, mode="good1a", rng=rng)
        self.assertTrue(code.startswith("Ab2p^"))
        self.assertTrue(validate_acode9(code, mode="good1a").valid)

        pool = generate_rolling_pool(
            count=25,
            start_timestamp=ts,
            cadence_seconds=1,
            mode="good1a",
            rng=random.Random(123),
        )
        self.assertEqual(len(pool), 25)
        codes = [entry.acode9 for entry in pool]
        self.assertEqual(len(set(codes)), 25)
        for idx, entry in enumerate(pool):
            self.assertEqual(entry.timestamp, ts + idx)
            self.assertTrue(validate_acode9(entry.acode9, mode="second1a").valid)


class AXIFAndDualLayerSearchTests(unittest.TestCase):
    SAMPLE_TEXT = "Field log: NormA met Norm4 and Norma4 near Acode9 Ab2p^a40z."

    def test_munsc_normalization_and_axif_metadata(self) -> None:
        note = AscensionNote.create(
            self.SAMPLE_TEXT,
            owner_acode9="Ab2p^a40z",
            title="Summit Log",
            timestamp=decode_jesus_clock("2p15ek"),
        )
        self.assertEqual(
            note.render("normalized"),
            "Field log: Norma met Norma and Norma near Acode9 Ab2p^a40z.",
        )
        self.assertEqual(note.render("raw"), self.SAMPLE_TEXT)
        self.assertEqual(note.axif.acode9, "Ab2p^a40z")
        self.assertEqual(note.axif.jesus_clock, "2p15ek")
        self.assertEqual(note.axif.munsc_count, 3)

        tuples = [e.to_tuple() for e in note.axif.entries]
        self.assertEqual(tuples[0][0:2], ("NormA", "Norma"))
        self.assertEqual(tuples[1][0:2], ("Norm4", "Norma"))
        self.assertEqual(tuples[2][0:2], ("Norma4", "Norma"))
        self.assertEqual(tuples[0][3], "Ab2p^a40z")

        # JSON roundtrip of AXIFMetadata
        rehydrated = AXIFMetadata.from_json(note.axif.to_json())
        self.assertEqual(rehydrated.acode9, "Ab2p^a40z")
        self.assertEqual(len(rehydrated.entries), 3)
        self.assertEqual(rehydrated.entries[2].token, "Norma4")

    def test_xcode_style_case_sensitive_dual_layer_search(self) -> None:
        note = AscensionNote.create(
            self.SAMPLE_TEXT,
            owner_acode9="Ab2p^a40z",
            title="Summit Log",
        )

        # Case-sensitive searches distinguish NormA, Norm4, and Norma4
        hits_norm_cap = note.search("NormA", case_sensitive=True)
        self.assertEqual(len(hits_norm_cap), 1)
        self.assertEqual(hits_norm_cap[0].matched_text, "NormA")
        self.assertIsNotNone(hits_norm_cap[0].axif_entry)
        self.assertEqual(hits_norm_cap[0].axif_entry.normalized_form, "Norma")

        hits_norm4 = note.search("Norm4", case_sensitive=True)
        self.assertEqual(len(hits_norm4), 1)
        self.assertEqual(hits_norm4[0].matched_text, "Norm4")

        hits_norma4 = note.search("Norma4", case_sensitive=True)
        self.assertEqual(len(hits_norma4), 1)
        self.assertEqual(hits_norma4[0].matched_text, "Norma4")
        self.assertEqual(hits_norma4[0].normalized_end - hits_norma4[0].normalized_offset, 5)

        # Lowercase 'norma' with case_sensitive=True finds 0 matches
        self.assertEqual(note.search("norma", case_sensitive=True), [])

        # Lowercase 'norma' with case_sensitive=False finds all 3 occurrences
        hits_ci = note.search("norma", case_sensitive=False, whole_word=True)
        self.assertEqual(len(hits_ci), 3)

        # Whole-word 'Norma' (case_sensitive=True) in dual layer finds normalized hits
        hits_ww = note.search("Norma", case_sensitive=True, whole_word=True)
        self.assertEqual(len(hits_ww), 3)

        # Normalized-only view cannot match raw 'NormA' directly
        self.assertEqual(
            note.search("NormA", case_sensitive=True, view_layer="normalized"),
            [],
        )

        # Regex search across MUNSC variations
        hits_regex = note.search(r"Norm[A4a]4?", case_sensitive=True, regex=True)
        self.assertEqual([h.matched_text for h in hits_regex], ["NormA", "Norm4", "Norma4"])

    def test_custom_munsc_rules_and_store_bundle(self) -> None:
        custom_rule = MUNSCRule(
            name="custom_z_sig",
            pattern="Z1on",
            replacement="Zion",
        )
        note = AscensionNote.create(
            "Heading toward Z1on with NormA.",
            owner_acode9="Ac3x^chch",
            title="Route",
            rules=[custom_rule],
        )
        self.assertEqual(note.render("normalized"), "Heading toward Zion with Norma.")
        hits = note.search("Z1on", case_sensitive=True)
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0].axif_entry.munsc_rule, "custom_z_sig")

        store = AscensionNotesStore([note])
        bundle = store.export_bundle()
        restored = AscensionNotesStore.import_bundle(bundle)
        restored_note = restored.get_note("Ac3x^chch")
        self.assertIsNotNone(restored_note)
        self.assertEqual(restored_note.render("normalized"), "Heading toward Zion with Norma.")
        self.assertEqual(len(restored.search_all("Z1on", case_sensitive=True)), 1)


if __name__ == "__main__":
    unittest.main()

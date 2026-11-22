"""Comprehensive unit tests for the Ascension Notes Python core."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import random
import sys
import tempfile
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
    NoteAttachment,
    clean_exact_clock_expression,
    clock2_from_timestamp,
    consonant_skeleton,
    decode_base38,
    decode_clock_expression,
    decode_jesus_clock,
    encode_base38,
    from_url_safe_base38,
    generate_acode9,
    generate_rolling_pool,
    is_clean_clock,
    is_clean_id,
    is_clean_lower_alnum_clock,
    is_i9or1_hierarchy_token,
    is_lower_alnum_base38,
    jesus_clock,
    jesus_clock_expression_to_datetime,
    jesus_clock_to_datetime,
    lead_letter_for_clock_char,
    load_custom_rules,
    make_skip_vowels_rule,
    parse_acode9,
    safe_jesus_clock,
    sanitize_favorite_3_letter_offset,
    save_custom_rules,
    suggest_skip_vowels,
    to_caret,
    to_dash,
    to_url_safe_base38,
    validate_acode9,
    verify_ii_token,
    verify_is5_token,
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

    def test_custom_rules_persistence_and_exports(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sync_dir = Path(tmpdir) / "AscensionNotes"
            self.assertEqual(load_custom_rules(sync_dir), [])

            store = AscensionNotesStore(sync_folder=sync_dir)
            added = store.add_custom_rule(
                "N0rma",
                "Norma",
                description="Custom N0rma variant",
            )
            self.assertEqual(added.pattern, "N0rma")
            self.assertEqual(added.replacement, "Norma")
            rules_file = sync_dir / "munsc_rules.json"
            self.assertTrue(rules_file.exists())

            reloaded = AscensionNotesStore(sync_folder=sync_dir)
            self.assertEqual(len(reloaded.custom_rules), 1)
            self.assertEqual(reloaded.custom_rules[0].pattern, "N0rma")

            # Verify Swift-style camelCase munsc_rules.json loads cleanly
            swift_payload = [
                {
                    "name": "custom_7Aunts",
                    "pattern": "7Aunts",
                    "replacement": "Seven Aunts",
                    "isRegex": False,
                    "description": "From Swift UI",
                }
            ]
            (sync_dir / "munsc_rules.json").write_text(
                json.dumps(swift_payload), encoding="utf-8"
            )
            loaded_swift = load_custom_rules(sync_dir)
            self.assertEqual(len(loaded_swift), 1)
            self.assertEqual(loaded_swift[0].replacement, "Seven Aunts")
            self.assertFalse(loaded_swift[0].is_regex)

            # Save + delete roundtrip
            saved_path = save_custom_rules(loaded_swift, sync_dir)
            self.assertEqual(saved_path, rules_file)
            reloaded.load_custom_rules(sync_dir)
            self.assertTrue(reloaded.delete_custom_rule("custom_7Aunts"))
            self.assertEqual(load_custom_rules(sync_dir), [])

            # Shareable AXIF footer & SlogBog phpBBog exports
            note = AscensionNote.create(
                "Met NormA at 7Aunts.",
                owner_acode9="Ab2p^a40z",
                rules=loaded_swift,
                timestamp=decode_jesus_clock("2p15ek"),
            )
            footer = note.export_clean_with_axif_footer()
            self.assertIn("Met Norma at Seven Aunts.", footer)
            self.assertIn("[AXIF: Ab2p^a40z | ", footer)
            bbcode = note.export_slogbog_bbcode()
            self.assertIn('[quote="Acode9: Ab2p^a40z | Clock: 2p15ek"]', bbcode)
            self.assertIn("[spoiler=AXIF][code]", bbcode)


class SkipVowelsAndAttachmentTests(unittest.TestCase):
    def test_skip_vowels_skeleton_and_rule_verification(self) -> None:
        self.assertEqual(consonant_skeleton("Where's Norma"), "whrnrm")
        self.assertEqual(consonant_skeleton("WhrNrm"), "whrnrm")

        self.assertEqual(suggest_skip_vowels("WhrNrmA")[0], "Where's Norma A")
        self.assertEqual(suggest_skip_vowels("WhrNrmB")[0], "Where's Norma B")
        self.assertEqual(suggest_skip_vowels("NrmA")[0], "Norma A")
        self.assertEqual(suggest_skip_vowels("NrmB")[0], "Norma B")
        self.assertEqual(suggest_skip_vowels("Anotes")[0], "Ascension Notes")
        self.assertEqual(suggest_skip_vowels("GSii")[0], "GSii")

        # Dynamic consonant-skeleton match against custom lexicon
        self.assertEqual(
            suggest_skip_vowels("JssClck", extra_lexicon=["Jesus Clock"])[0],
            "Jesus Clock",
        )

        rule = make_skip_vowels_rule("WhrNrmA", "Where's Norma A")
        self.assertEqual(rule.description, "Skip vowels verified")
        note = AscensionNote.create(
            "Reading WhrNrmA and WhrNrmB inside Anotes.",
            owner_acode9="Ab2p^a40z",
            rules=[rule, make_skip_vowels_rule("WhrNrmB", "Where's Norma B")],
        )
        self.assertEqual(
            note.render("normalized"),
            "Reading Where's Norma A and Where's Norma B inside Anotes.",
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            store = AscensionNotesStore(sync_folder=tmpdir)
            saved_rule = store.add_skip_vowels_rule("NrmA", "Norma A")
            self.assertEqual(saved_rule.description, "Skip vowels verified")
            reloaded = load_custom_rules(tmpdir)
            self.assertEqual(len(reloaded), 1)
            self.assertEqual(reloaded[0].pattern, "NrmA")
            self.assertEqual(reloaded[0].replacement, "Norma A")
            self.assertEqual(reloaded[0].description, "Skip vowels verified")

    def test_ii_is5_and_i9or1_verification_helpers(self) -> None:
        self.assertEqual(verify_ii_token("GS"), "GSii")
        self.assertEqual(verify_ii_token("GSii"), "GSii")
        self.assertEqual(verify_is5_token("is"), "is5")
        self.assertEqual(verify_is5_token("Is"), "is5")
        self.assertEqual(verify_is5_token("Appending"), "Appendingis5")
        self.assertEqual(verify_is5_token("Appendingis5"), "Appendingis5")

        self.assertTrue(is_i9or1_hierarchy_token("i9or1"))
        self.assertTrue(is_i9or1_hierarchy_token("GSii"))
        self.assertTrue(is_i9or1_hierarchy_token("is5"))
        self.assertFalse(is_i9or1_hierarchy_token("is"))
        self.assertFalse(is_i9or1_hierarchy_token("ii"))

    def test_note_attachments_backwards_compatible_roundtrip(self) -> None:
        att = NoteAttachment(
            id="A1B2C3D4-0000-0000-0000-000000000001",
            filename="NormA.png",
            relative_path="attachments/A1B2C3D4-0000-0000-0000-000000000001.png",
            pixel_width=1600,
            pixel_height=1000,
            created_at="2026-11-21T05:00:00Z",
        )
        self.assertEqual(att.short_id, "a1b2")
        self.assertEqual(att.marker_text, "▸[Image: NormA.png #a1b2]")

        note = AscensionNote.create(
            f"Log with NormA and screenshot:\n{att.marker_text}",
            owner_acode9="Ab2p^a40z",
            title="Retina Test",
            attachments=[att],
        )
        self.assertEqual(
            note.render("normalized"),
            f"Log with Norma and screenshot:\n{att.marker_text}",
        )
        self.assertEqual(note.axif.munsc_count, 1)
        payload = note.to_dict()
        rehydrated = AscensionNote.from_dict(payload)
        self.assertEqual(len(rehydrated.attachments), 1)
        self.assertEqual(rehydrated.attachments[0].pixel_width, 1600)
        self.assertEqual(rehydrated.attachments[0].pixel_height, 1000)

        # Missing attachments key remains backwards-compatible
        legacy_payload = dict(payload)
        del legacy_payload["attachments"]
        legacy_note = AscensionNote.from_dict(legacy_payload)
        self.assertEqual(legacy_note.attachments, [])

        # Swift camelCase StoredNote attachment payload decodes cleanly
        swift_att = NoteAttachment.from_dict(
            {
                "id": "deadbeef-1111-2222-3333-444444444444",
                "filename": "Capture.png",
                "relativePath": "attachments/deadbeef-1111-2222-3333-444444444444.png",
                "pixelWidth": 2560,
                "pixelHeight": 1440,
                "createdAt": "2026-11-21T05:10:00Z",
            }
        )
        self.assertEqual(swift_att.pixel_width, 2560)
        self.assertEqual(swift_att.pixel_height, 1440)
        self.assertEqual(swift_att.short_id, "dead")

    def test_export_markdown_with_frontmatter_and_attachments(self) -> None:
        att = NoteAttachment(
            id="B1C2D3E4-0000-0000-0000-000000000002",
            filename="TestChart.png",
            relative_path="attachments/TestChart.png",
            pixel_width=1200,
            pixel_height=800,
            created_at="2026-11-21T06:00:00Z",
        )
        note = AscensionNote.create(
            f"Here is NormA meeting at SLC:\n{att.marker_text}",
            owner_acode9="Ab2p^a40z",
            title="Meeting with NormA",
            attachments=[att],
        )

        md = note.export_markdown(include_frontmatter=True, include_axif_footer=True)
        self.assertIn('title: "Meeting with NormA"', md)
        self.assertIn('acode9: "Ab2p^a40z"', md)
        self.assertIn('aaid: "Ab2p^a00z"', md)
        self.assertIn("![TestChart.png](attachments/TestChart.png)", md)
        self.assertIn("Norma meeting at SLC", md)
        self.assertIn("<!-- AXIF: Ab2p^a40z | AAid: Ab2p^a00z | Clock:", md)

        # Raw text mode
        md_raw = note.export_markdown(include_frontmatter=False, include_axif_footer=False, use_raw_text=True)
        self.assertIn("NormA meeting at SLC", md_raw)
        self.assertNotIn("---", md_raw)
        self.assertNotIn("<!-- AXIF:", md_raw)

    def test_exact_clock_expression_msd_and_picture_word_math(self) -> None:
        clean_ts = decode_jesus_clock("2p15ek")
        clean_res = clean_exact_clock_expression(clean_ts, context_words=["tree"])
        self.assertEqual(clean_res.expression, "2p15ek")
        self.assertFalse(clean_res.used_arithmetic_workaround)
        self.assertEqual(decode_clock_expression(clean_res.expression), clean_ts)

        # Bad triple-6 timestamp ("2p7666") with picture context word ("gym") preserves MSD "2p7"
        gym_ts = decode_jesus_clock("2p7666")
        gym_res = clean_exact_clock_expression(gym_ts, context_words=["gym", "Air Derby"], max_length=17)
        self.assertTrue(gym_res.used_arithmetic_workaround)
        self.assertEqual(gym_res.context_word_used, "gym")
        self.assertTrue(gym_res.expression.startswith("2p7"), gym_res.expression)
        self.assertTrue(gym_res.expression.endswith("-gym") or gym_res.expression.endswith("+gym"))
        self.assertLessEqual(len(gym_res.expression), 17)
        self.assertEqual(decode_clock_expression(gym_res.expression), gym_ts)
        lhs, rhs = gym_res.expression.replace("+", "-").split("-", 1)
        self.assertTrue(is_clean_lower_alnum_clock(lhs))
        self.assertTrue(is_clean_lower_alnum_clock(rhs))

        # Blocked substring ("2p7fuk", "2shit1") and ^/| ("2p7|^a") produce strict 6-3 (9 digits + '-')
        for raw_bad in ("2p7fuk", "2shit1", "2p7|^a"):
            ts = decode_jesus_clock(raw_bad)
            res = clean_exact_clock_expression(ts, context_words=["Weeping", "willow", "tree"], max_length=17)
            self.assertTrue(res.used_arithmetic_workaround)
            self.assertEqual(len(res.expression), 10, res.expression)
            self.assertIn("-", res.expression)
            self.assertNotIn("^", res.expression)
            self.assertNotIn("|", res.expression)
            self.assertEqual(decode_clock_expression(res.expression), ts)
            self.assertEqual(int(jesus_clock_expression_to_datetime(res.expression).timestamp()), ts)

        # Stage-1 default capture tag on clean time ("2p41w2") with always_use_difference_formula=True
        cap_ts = decode_jesus_clock("2p41w2")
        cap_res = clean_exact_clock_expression(
            cap_ts,
            context_words=["capture"],
            max_length=17,
            always_use_difference_formula=True,
        )
        self.assertEqual(len(cap_res.expression), 10, cap_res.expression)
        self.assertTrue(cap_res.expression.startswith("2p4"), cap_res.expression)
        self.assertIn("-", cap_res.expression)
        self.assertEqual(decode_clock_expression(cap_res.expression), cap_ts)

        # Multi-digit |/^ windows (e.g. 2027's 2^0000 and 2110-2115's |00000..^|||||) still resolve cleanly
        for wide_bad in ("2||000", "2^0000", "z^0000", "|00000", "^|||||"):
            ts = decode_jesus_clock(wide_bad)
            res = clean_exact_clock_expression(ts, max_length=17)
            self.assertNotIn("|", res.expression)
            self.assertNotIn("^", res.expression)
            self.assertLessEqual(len(res.expression), 17)
            self.assertEqual(decode_clock_expression(res.expression), ts)

        # Ascender's chosen favorite 3-letter offset ('joy', 'sun', or initials 'HMF')
        self.assertEqual(sanitize_favorite_3_letter_offset("  HMF "), "hmf")
        self.assertEqual(sanitize_favorite_3_letter_offset("Joy!"), "joy")
        self.assertIsNone(sanitize_favorite_3_letter_offset("fuk"))
        self.assertIsNone(sanitize_favorite_3_letter_offset("ab"))

        fav_ts = decode_jesus_clock("2p41w4")
        for fav_input, expected_word in [("joy", "joy"), ("sun", "sun"), ("HMF", "hmf")]:
            fav_res = clean_exact_clock_expression(
                fav_ts,
                context_words=["Weeping", "Willow", "tree"],
                max_length=17,
                always_use_difference_formula=True,
                favorite_offset=fav_input,
            )
            self.assertEqual(len(fav_res.expression), 10, fav_res.expression)
            self.assertTrue(fav_res.expression.endswith(f"-{expected_word}"), fav_res.expression)
            self.assertEqual(decode_clock_expression(fav_res.expression), fav_ts)

        # If favorite_offset would produce an anchor with '|' ('2p41w2' + 'joy' == '2p4li|'), safely falls back
        dodge_res = clean_exact_clock_expression(
            decode_jesus_clock("2p41w2"),
            always_use_difference_formula=True,
            favorite_offset="joy",
        )
        self.assertEqual(dodge_res.expression, "2p4uop-sun")

        # Explicit round-anchor check for "2p5000-334"
        expected_2p5000_minus_334 = decode_jesus_clock("2p5000") - decode_base38("334")
        self.assertEqual(decode_clock_expression("2p5000-334"), expected_2p5000_minus_334)

    def test_smart_retitled_attachment_metadata(self) -> None:
        ts = decode_jesus_clock("2p7666")
        expr = clean_exact_clock_expression(ts, context_words=["gym"]).expression
        att = NoteAttachment(
            id="c0ffee12-0000-0000-0000-000000000001",
            filename=f"Air Derby {expr}.png",
            relative_path="attachments/c0ffee12-0000-0000-0000-000000000001.png",
            pixel_width=2400,
            pixel_height=1600,
            exact_unix_timestamp=ts,
            base38_timestamp_tag=expr,
        )
        raw_dict = att.to_dict()
        restored = NoteAttachment.from_dict(raw_dict)
        self.assertEqual(restored.exact_unix_timestamp, ts)
        self.assertEqual(restored.base38_timestamp_tag, expr)
        self.assertEqual(restored.marker_text, f"▸[Image: Air Derby {expr}.png #c0ff]")

        # Swift camelCase round-trip
        swift_style = NoteAttachment.from_dict(
            {
                "id": "abcdef01-0000-0000-0000-000000000002",
                "filename": f"Weeping WilLoW Tree {expr}.png",
                "relativePath": "attachments/abcdef01-0000-0000-0000-000000000002.png",
                "pixelWidth": 1920,
                "pixelHeight": 1080,
                "exactUnixTimestamp": ts,
                "base38TimestampTag": expr,
            }
        )
        self.assertEqual(swift_style.exact_unix_timestamp, ts)
        self.assertEqual(swift_style.base38_timestamp_tag, expr)


if __name__ == "__main__":
    unittest.main()

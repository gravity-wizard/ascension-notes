import SwiftUI

#if canImport(SwiftUI)
struct HelpGuideView: View {
    private let notesGold = Color(red: 0.90, green: 0.64, blue: 0.08)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(notesGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ascension Notes Help")
                            .font(.title.bold())
                        Text("Hydrogen4^high-mode5  •  Apple Notes UX + Xcode Case-Sensitive Search + AXIF")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                helpSection(
                    icon: "square.and.pencil",
                    title: "Apple Notes Editing, Siri Auto-Cap & Clean View Spellcheck",
                    bullets: [
                        "Open any note and edit the large Line-1 Title or body immediately—changes auto-save to Application Support.",
                        "Press Cmd + N for a new note (automatically mints a fresh good1a Acode9 from the live Base-38 Jesus Clock).",
                        "Auto-Cap New Lines (ON by default) capitalizes the first letter of new lines for both typing and Siri Dictation on macOS & iOS.",
                        "Clean View (Cmd + E) normalizes NormA, Norm4, and Norma4 to Norma AND runs live Apple spellcheck with red dotted underlines and 1-click Fix / Learn Word so Ascenders can spot typos right away."
                    ]
                )

                helpSection(
                    icon: "magnifyingglass",
                    title: "Xcode-Style Case-Sensitive Search (Cmd + F)",
                    bullets: [
                        "Aa (Case-Sensitive): Distinguishes NormA vs. Norm4 vs. Norma4 vs. norma.",
                        "W (Whole Word): Matches whole tokens only.",
                        ".* (Regex): Full regular-expression search across notes.",
                        "Dual AXIF Scope: Searches both your raw MUNSC tokens and clean normalized text at the same time."
                    ]
                )

                helpSection(
                    icon: "clock.badge.checkmark",
                    title: "Acode9 & Base-38 Jesus Clock (March8Miracle.org)",
                    bullets: [
                        "Time0 is anchored at T0UX = 1584540571 (2020-03-18T14:09:31Z) in 38-symbol Base-38.",
                        "Every 9-char Acode9 starts with BigA, a letter-number pair matching the clock's leading character (e.g. b2p for 2p..., c3x for 3x... since C == 3, H == 8), a center ^ mountain (or - in URL-safe mode), and a YouTube-filtered 4-char tail.",
                        "Press Cmd + I to open the AXIF Inspector drawer, inspect MUNSC offsets, copy shareable AXIF JSON, or mint a 1-second rolling pool."
                    ]
                )

                helpSection(
                    icon: "folder.badge.gearshape",
                    title: "Where Help Text Lives During Development",
                    bullets: [
                        "In this app, help text lives directly in swift/Sources/AscensionNotesApp/HelpGuideView.swift (cross-platform macOS + iOS, instant rebuild with zero Apple Help Viewer cache lag).",
                        "Traditional macOS-only Help Books live in a Resources/<App>.help HTML bundle indexed by hiutil and wired via CFBundleHelpBookFolder in Info.plist."
                    ]
                )
            }
            .padding(24)
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 480)
        #endif
    }

    private func helpSection(icon: String, title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(notesGold)
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(notesGold)
                    Text(bullet)
                        .font(.body)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
#endif

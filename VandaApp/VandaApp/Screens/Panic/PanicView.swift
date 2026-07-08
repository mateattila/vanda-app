//
//  PanicView.swift
//  VandaApp
//
//  A panik-képernyő 1. szintje (spec 4.4): érzés-chipek + szabad szöveg,
//  és az érzéshez rendezett eszközmodulok. A „Szólok anyáéknak" riasztás
//  a 4.3 lépésben kerül ide; a note state már most az előszobája.
//

import SwiftData
import SwiftUI

struct PanicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PanicContact.orderIndex) private var contacts: [PanicContact]

    @State private var feeling: PanicFeeling?
    @State private var note = ""
    @State private var activeTool: PanicToolID?
    @State private var isPulsing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.Gradients.panic
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    header

                    feelingChips

                    TextField(
                        "",
                        text: $note,
                        prompt: Text("Ha szeretnéd, írd ki, mi van… (nem kötelező)")
                            .foregroundStyle(.white.opacity(0.5)),
                        axis: .vertical
                    )
                    .font(.vandaBody())
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.cardPadding)
                    .background(
                        Color.white.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                    )

                    ForEach(PanicToolbox.recommendedOrder(for: feeling)) { tool in
                        if tool == .callParents {
                            callParentsCard
                        } else {
                            toolRow(tool)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 70)
                .padding(.bottom, Theme.Spacing.screenMargin)
                .animation(.snappy, value: feeling)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(Theme.Spacing.screenMargin)
            .accessibilityLabel("Bezárás")
        }
        .fullScreenCover(item: $activeTool) { tool in
            switch tool {
            case .breathing: BreathingView()
            case .grounding: GroundingView()
            case .calmFolder: CalmFolderView()
            case .calmActivities: CalmActivitiesView()
            case .callParents: EmptyView()
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 84, height: 84)
                    .scaleEffect(isPulsing ? Theme.Motion.pulseScale : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: Theme.Motion.pulsePeriod / 2)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }

            Text("Itt vagyunk. Lélegezz egy nagyot.")
                .font(.vandaDisplay())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }

    private var feelingChips: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.chipVertical) {
            Text("Mi van most?")
                .font(.vandaLabel())
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.6))

            PanicFlowLayout(spacing: Theme.Spacing.chipVertical) {
                ForEach(PanicFeeling.allCases) { candidate in
                    let isSelected = feeling == candidate
                    Button {
                        withAnimation(.snappy) {
                            feeling = isSelected ? nil : candidate
                        }
                    } label: {
                        Text("\(candidate.emoji) \(candidate.label)")
                            .font(.vandaBodyStrong(13))
                            .foregroundStyle(isSelected ? Color.ink : .white)
                            .padding(.vertical, Theme.Spacing.chipVertical)
                            .padding(.horizontal, Theme.Spacing.chipHorizontal)
                            .background(
                                isSelected ? Color.white : Color.white.opacity(0.15),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .light), trigger: feeling)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolRow(_ tool: PanicToolID) -> some View {
        let (emoji, title, subtitle): (String, String, String) = switch tool {
        case .breathing: ("🫁", "Légzés", "Vezetett levegővétel, táguló körrel")
        case .grounding: ("🖐️", "5-4-3-2-1", "Nézz körül — visszahozunk a jelenbe")
        case .calmFolder: ("🌿", "Nyugi-mappa", "A képeid, amik jólesnek")
        case .calmActivities: ("✨", "Nyugi-tevékenységek", "Pár bevált, csendes ötlet")
        case .callParents: ("📞", "", "")
        }

        return Button {
            activeTool = tool
        } label: {
            HStack(spacing: Theme.Spacing.cardPadding) {
                Text(emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.vandaBodyStrong())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.vandaCaption())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(Theme.Spacing.cardPadding)
            .background(
                Color.white.opacity(0.15),
                in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var callParentsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            HStack(spacing: Theme.Spacing.cardPadding) {
                Text("📞")
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hívd anyát / apát")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(.white)
                    Text(contacts.isEmpty
                         ? "A Beállításokban tudjátok felvenni a számokat"
                         : "Egy koppintás, és ott vannak")
                        .font(.vandaCaption())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }

            ForEach(contacts) { contact in
                HStack(spacing: Theme.Spacing.chipHorizontal / 2) {
                    Text("\(contact.emoji) \(contact.label)")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(.white)
                    Spacer()
                    if let tel = contact.telURL {
                        contactAction("Hívás", systemImage: "phone.fill", url: tel)
                    }
                    if let facetime = contact.faceTimeVideoURL {
                        contactAction("FaceTime", systemImage: "video.fill", url: facetime)
                    }
                }
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .background(
            Color.white.opacity(0.15),
            in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
        )
    }

    private func contactAction(_ title: String, systemImage: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.ink)
                .padding(.vertical, Theme.Spacing.chipVertical)
                .padding(.horizontal, Theme.Spacing.chipHorizontal)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Egyszerű balra zárt, sortörő chip-elrendezés.
///
/// Megjegyzés: a `Screens/Journal/JournalTemplateFillView.swift`-ben már létezik
/// egy `FlowLayout` nevű típus (a `FlowChips`-hez tartozik). Mivel Swiftben két
/// azonos nevű top-level deklaráció még `fileprivate` mellett is ütközik
/// (érvénytelen újradeklarálás), ez a másolat `PanicFlowLayout` néven él — a
/// brief szándéka szerint saját, e képernyőhöz tartozó példány (YAGNI — közös
/// komponenssé csak egy harmadik felhasználási hely esetén emelnénk).
struct PanicFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = makeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in makeRows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var range: Range<Int>
        var height: CGFloat
    }

    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var start = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(Row(range: start..<index, height: rowHeight))
                start = index
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if start < subviews.count {
            rows.append(Row(range: start..<subviews.count, height: rowHeight))
        }
        return rows
    }
}

#Preview {
    PanicView()
        .modelContainer(for: [PanicContact.self, CalmItem.self, Activity.self], inMemory: true)
}

//
//  CalmFolderView.swift
//  VandaApp
//
//  Nyugi-mappa (spec 4.4): Vanda által válogatott megnyugtató képek.
//  PhotosPickerből töltődik, a fotók kicsinyítve tárolódnak (CalmItem).
//

import PhotosUI
import SwiftData
import SwiftUI

struct CalmFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CalmItem.createdAt, order: .reverse) private var items: [CalmItem]

    @State private var picks: [PhotosPickerItem] = []
    @State private var viewerItem: CalmItem?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                ScrollView {
                    if items.isEmpty {
                        VStack(spacing: Theme.Spacing.cardGap) {
                            Text("🌿")
                                .font(.system(size: 52))
                                .padding(.top, 80)
                            Text("Ez a te nyugi-mappád")
                                .font(.vandaDisplay())
                                .foregroundStyle(.white)
                            Text("Gyűjts ide képeket, amiktől jobb kedved lesz — kedvencek, emlékek, cukiságok.")
                                .font(.vandaBody())
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.screenMargin)
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(items) { item in
                                if let data = item.photoData, let image = UIImage(data: data) {
                                    Button {
                                        viewerItem = item
                                    } label: {
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(minWidth: 100, minHeight: 100)
                                            .clipShape(RoundedRectangle(
                                                cornerRadius: Theme.Radius.cardSmall,
                                                style: .continuous
                                            ))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            modelContext.delete(item)
                                        } label: {
                                            Label("Törlés", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                        .padding(.top, Theme.Spacing.cardGap)
                    }
                }

                PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) {
                    Text("📷 Képek hozzáadása")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)

                Button {
                    dismiss()
                } label: {
                    Text("Vissza")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.screenMargin)
            }
        }
        .onChange(of: picks) {
            Task { await importPicks() }
        }
        .fullScreenCover(item: $viewerItem) { item in
            CalmPhotoViewer(startItem: item, items: items)
        }
    }

    private func importPicks() async {
        for pick in picks {
            guard let data = try? await pick.loadTransferable(type: Data.self),
                  let downscaled = ImageDownscaler.jpegData(from: data, maxDimension: 1600) else { continue }
            let item = CalmItem()
            item.photoData = downscaled
            modelContext.insert(item)
        }
        picks = []
    }
}

/// Egyszerű lapozós néző a nyugi-képekhez.
private struct CalmPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let startItem: CalmItem
    let items: [CalmItem]

    @State private var selectedID: UUID?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.Gradients.panic
                .ignoresSafeArea()

            TabView(selection: $selectedID) {
                ForEach(items) { item in
                    if let data = item.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .tag(Optional(item.id))
                    }
                }
            }
            .tabViewStyle(.page)

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
        }
        .onAppear { selectedID = startItem.id }
    }
}

#Preview {
    CalmFolderView()
        .modelContainer(for: CalmItem.self, inMemory: true)
}

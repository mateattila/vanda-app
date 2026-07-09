//
//  PanicContactsSettingsView.swift
//  VandaApp
//
//  A panik-képernyő „Hívd anyát / apát" gombjainak címzettjei.
//  Világos settings-környezet (nem a panik sötét gradiense).
//

import SwiftData
import SwiftUI

struct PanicContactsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PanicContact.orderIndex) private var contacts: [PanicContact]
    @Query private var themeSettings: [ThemeSettings]

    @State private var editingContact: PanicContact?
    @State private var isAddingNew = false

    private var theme: ThemeSettings? { themeSettings.first }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    Text("Ezek a gombok jelennek meg a panik-képernyőn — egy koppintás, és hívja is őket.")
                        .font(.vandaCaption())
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(contacts) { contact in
                        Button {
                            editingContact = contact
                        } label: {
                            HStack(spacing: Theme.Spacing.cardPadding) {
                                Text(contact.emoji)
                                    .font(.system(size: 28))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.label)
                                        .font(.vandaBodyStrong())
                                        .foregroundStyle(Color.ink)
                                    Text(contact.phoneNumber)
                                        .font(.vandaCaption())
                                        .foregroundStyle(Color.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.inkFaint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .vandaCard(surface: theme?.cardSurface ?? .surface)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(contact)
                            } label: {
                                Label("Törlés", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        isAddingNew = true
                    } label: {
                        Label("Új elérhetőség", systemImage: "plus")
                            .font(.vandaBodyStrong())
                            .foregroundStyle(theme?.accentColor ?? Theme.Accent.default)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Color.surfaceTint,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.cardGap)
            }
        }
        .navigationTitle("Hívható szülők")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editingContact) { contact in
            PanicContactEditor(contact: contact)
        }
        .sheet(isPresented: $isAddingNew) {
            PanicContactEditor(contact: nil)
        }
    }
}

private struct PanicContactEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PanicContact.orderIndex) private var contacts: [PanicContact]

    let contact: PanicContact?

    @State private var label = ""
    @State private var emoji = "💛"
    @State private var phoneNumber = ""

    private let emojiOptions = ["💛", "💙", "🧡", "💜", "🩷", "💚"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Ki ő?") {
                    TextField("Név (pl. Anya)", text: $label)
                    Picker("Szín-szívecske", selection: $emoji) {
                        ForEach(emojiOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Telefonszám") {
                    TextField("+36 30 123 4567", text: $phoneNumber)
                        .keyboardType(.phonePad)
                }
            }
            .navigationTitle(contact == nil ? "Új elérhetőség" : "Szerkesztés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { save() }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty
                                  || !PanicContact.dialableNumber(from: phoneNumber).contains(where: \.isWholeNumber))
                }
            }
            .onAppear {
                if let contact {
                    label = contact.label
                    emoji = contact.emoji
                    phoneNumber = contact.phoneNumber
                }
            }
        }
    }

    private func save() {
        let target: PanicContact
        if let contact {
            target = contact
        } else {
            target = PanicContact()
            target.orderIndex = (contacts.map(\.orderIndex).max() ?? -1) + 1
            modelContext.insert(target)
        }
        target.label = label.trimmingCharacters(in: .whitespaces)
        target.emoji = emoji
        target.phoneNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PanicContactsSettingsView()
    }
    .modelContainer(for: [PanicContact.self, ThemeSettings.self], inMemory: true)
}

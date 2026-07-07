//
//  MoodTrendView.swift
//  VandaApp
//
//  Trend-nézet Vandának (spec 4.3): heti/havi aksi-grafikon, napi átlagokkal,
//  zóna-színekkel. Csak neki szól — a szülő mód ilyet nem lát.
//

import Charts
import SwiftUI
import SwiftData

struct MoodTrendView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MoodEntry.timestamp) private var entries: [MoodEntry]
    @Query private var themeSettings: [ThemeSettings]

    @State private var rangeDays = 7

    private var theme: ThemeSettings? { themeSettings.first }

    private struct DayPoint: Identifiable {
        let day: Date
        let average: Int
        let zone: MoodZone
        var id: Date { day }
    }

    private var points: [DayPoint] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: calendar.startOfDay(for: Date())) else {
            return []
        }
        let recent = entries.filter { $0.timestamp >= cutoff }
        let byDay = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.timestamp) }
        let settings = MoodSettings.ensureCurrent(in: modelContext)
        return byDay.map { day, dayEntries in
            let avg = dayEntries.map(\.batteryPercent).reduce(0, +) / max(1, dayEntries.count)
            return DayPoint(day: day, average: avg, zone: settings.zone(for: avg))
        }
        .sorted { $0.day < $1.day }
    }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                Picker("Időtáv", selection: $rangeDays) {
                    Text("7 nap").tag(7)
                    Text("30 nap").tag(30)
                }
                .pickerStyle(.segmented)

                if points.isEmpty {
                    VStack(spacing: 8) {
                        Text("🔋")
                            .font(.system(size: 40))
                        Text("Még nincs elég adat")
                            .font(.vandaBodyStrong())
                            .foregroundStyle(Color.ink)
                        Text("Tölts ki pár aksi-checket, és itt kirajzolódik a trended.")
                            .font(.vandaBody(13))
                            .foregroundStyle(Color.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .vandaCard(surface: theme?.cardSurface ?? .surface)
                } else {
                    chart
                        .frame(height: 260)
                        .vandaCard(surface: theme?.cardSurface ?? .surface)
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, Theme.Spacing.cardGap)
        }
        .navigationTitle("Aksi-trend")
        .navigationBarTitleDisplayMode(.large)
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Nap", point.day, unit: .day),
                y: .value("Aksi", point.average)
            )
            .foregroundStyle(point.zone.fillColor)
            .cornerRadius(5)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 30, 60, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(.vandaCaption(10))
                            .foregroundStyle(Color.inkFaint)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: rangeDays == 7 ? 1 : 7)) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true)
                    .font(.vandaCaption(10))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }
}

#Preview {
    NavigationStack {
        MoodTrendView()
    }
    .modelContainer(VandaStore.makeContainer())
}

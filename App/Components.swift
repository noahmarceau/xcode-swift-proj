import SwiftUI

@MainActor struct Tile<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.07), lineWidth: 1))
    }
}
@MainActor struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) { content }.padding(.horizontal, 18).padding(.vertical, 12) }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
    }
}
@MainActor struct Stat: View {
    let label: String
    let value: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.title2.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
}
@MainActor struct NumberField: View {
    var label: String
    @Binding var value: Double
    var body: some View { HStack { Text(label); Spacer(); TextField(label, value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 140) } }
}
@MainActor struct EmptyTile: View {
    var title: String
    var subtitle: String
    var icon: String
    var body: some View { Tile { Image(systemName: icon).font(.title).foregroundStyle(.tint); Text(title).font(.headline); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) } }
}
@MainActor struct MacroBars: View {
    var total: Nutrients
    var settings: Settings
    var body: some View {
        VStack(spacing: 12) {
            row("Protein", value: total.protein, goal: settings.calorieGoal * settings.proteinPercent / 400, color: .mint)
            row("Carbs", value: total.carbs, goal: settings.calorieGoal * settings.carbPercent / 400, color: .blue)
            row("Fat", value: total.fat, goal: settings.calorieGoal * settings.fatPercent / 900, color: .orange)
        }
    }
    func row(_ label: String, value: Double, goal: Double, color: Color) -> some View {
        VStack(spacing: 5) { HStack { Text(label); Spacer(); Text("\(value.compact) / \(goal.compact) g").monospacedDigit() }.font(.caption)
            ProgressView(value: min(value, max(1, goal)), total: max(1, goal)).tint(color)
        }
    }
}

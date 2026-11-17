import SwiftUI

@main @MainActor struct FormaApp: App {
    @StateObject private var store = AppStore.shared
    var body: some Scene { WindowGroup { RootView().environmentObject(store) } }
}
@MainActor struct RootView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) var phase
    @State private var tab = 0
    @State private var refreshing = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { MealsView() }.tabItem { Label("Fuel", systemImage: "fork.knife") }.tag(0)
            NavigationStack { WorkoutsView() }.tabItem { Label("Train", systemImage: "dumbbell") }.tag(1)
            NavigationStack { ProgressViewScreen() }.tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }.tag(2)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .tint(store.data.settings.accent == "Mint" ? .mint : .orange)
        .preferredColorScheme(store.data.settings.appearance == "System" ? nil : store.data.settings.appearance == "Dark" ? .dark : .light)
        .onOpenURL { url in if url.host == "workout" { tab = 1 } }
        .alert("Forma", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: phase) { _, value in
            if value == .active { store.refreshLive(); refreshDining() }
            if value == .background { store.persist() }
        }
        .task { refreshDining() }
        .overlay(alignment: .top) {
            if store.loadBlocked { Text("Storage recovery needed · open Settings").font(.caption.bold()).padding(8).background(.red).clipShape(Capsule()).onTapGesture { tab = 3 } }
        }
    }
    func refreshDining() {
        guard store.data.settings.autoUMass, !refreshing, !(store.data.lastUMassSync?.sameDay(Date()) ?? false) else { return }
        refreshing = true
        Task {
            defer { refreshing = false }
            do {
                let result = try await UMassDining.sync(locationID: store.data.settings.locationID, date: Date())
                store.mergeFoods(result.foods); store.data.lastUMassSync = Date()
                if result.warnings > 0 { store.error = "UMass imported \(result.foods.count) foods; \(result.warnings) pages were unavailable or could not be parsed." }
            } catch { store.error = error.localizedDescription }
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}
@MainActor struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var importing = false
    @State private var restoreMode = false
    @State private var exporting = false
    @State private var document = BackupDocument(bytes: Data())
    @State private var pendingFoods: [Food] = []
    @State private var preview = false
    @State private var restoreBytes: Data? = nil
    @State private var confirmRestore = false
    @State private var status = ""
    @State private var syncing = false
    @State private var goals = false
    @State private var diningDate = Date()
    @State private var locations: [DiningLocation] = []
    var body: some View {
        Form {
            Section("Personal") {
                TextField("Your name", text: $store.data.settings.name)
                Button("Calorie & macro goals") { goals = true }
                Toggle("Use pounds", isOn: $store.data.settings.usePounds)
                Text("All stored weights use kilograms; this changes display and entry units.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Theme", selection: $store.data.settings.appearance) { ForEach(["Dark", "Light", "System"], id: \.self) { Text($0).tag($0) } }
                Picker("Accent", selection: $store.data.settings.accent) { Text("Mint").tag("Mint"); Text("Amber").tag("Amber") }
            }
            Section("Training") {
                Toggle("Rest timers", isOn: $store.data.settings.restTimers).onChange(of: store.data.settings.restTimers) { _, on in if !on { store.editActive { $0.restUntil = nil }; RestNotifications.cancel() }; store.refreshLive() }
                Toggle("Rest completion alerts", isOn: $store.data.settings.restAlerts).onChange(of: store.data.settings.restAlerts) { _, on in
                    if on { Task { do { if try await RestNotifications.request() == false { store.data.settings.restAlerts = false; status = "Notification permission was not granted. You can enable it in iPhone Settings." } } catch { store.data.settings.restAlerts = false; status = error.localizedDescription } } }
                    else { RestNotifications.cancel() }
                }
                Toggle("Live Activities", isOn: $store.data.settings.liveActivities).onChange(of: store.data.settings.liveActivities) { _, _ in store.refreshLive() }
                Stepper("Progression: \(store.data.settings.progressionPercent.compact)%", value: $store.data.settings.progressionPercent, in: 2...10, step: 1)
                Text("Suggested increases require two recent sessions at target + 2 reps for every working set, without a failure flag. Equipment increments are set per exercise. Suggestions are optional; they do not evaluate technique or recovery.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Food catalog & meals") {
                NavigationLink("Manage foods") { FoodCatalogView() }
                NavigationLink("Meal categories") { MealCategoriesView() }
                Button("Import foods from CSV") { restoreMode = false; importing = true }
                Text("Required: name, serving, calories, protein_g, carbs_g, fat_g. Optional nutrient columns are documented in the included sample CSV. Imports are previewed before saving.").font(.caption).foregroundStyle(.secondary)
            }
            Section("UMass Dining") {
                if locations.isEmpty {
                    Picker("Location", selection: $store.data.settings.locationID) {
                        Text("Worcester").tag("01"); Text("Franklin").tag("02"); Text("Hampshire").tag("03"); Text("Berkshire").tag("04")
                    }
                } else { Picker("Location", selection: $store.data.settings.locationID) { ForEach(locations) { Text($0.name).tag($0.id) } } }
                Button("Load all dining locations") { Task { do { locations = try await UMassDining.locations() } catch { status = error.localizedDescription } } }
                DatePicker("Menu date", selection: $diningDate, displayedComponents: .date)
                Toggle("Refresh today's menu on daily app open", isOn: $store.data.settings.autoUMass)
                Button(syncing ? "Importing menu…" : "Refresh selected menu") { syncDining() }.disabled(syncing || store.loadBlocked)
                if syncing { ProgressView() }
                if let last = store.data.lastUMassSync { Text("Last successful refresh: \(last.formatted())").font(.caption) }
                Link("Open UMass menu website", destination: UMassDining.root)
                Text("Downloads published menu foods, not a guaranteed complete recipe catalog. Availability depends on UMass's website. Successful imports are cached for offline use; failures leave your catalog intact.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Apple Health") {
                Button("Authorize & sync 90 days") { Task { do { status = try await HealthService.sync(into: store) } catch { status = error.localizedDescription } } }
                Text("Read-only weight, active energy and resting energy. Requires the Health build with a compatible signing profile. No workouts or nutrition are written to Health, avoiding duplicate energy entries.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Your data") {
                Button("Export full JSON backup") {
                    do { document = BackupDocument(bytes: store.loadBlocked ? try Data(contentsOf: store.fileURL) : try AppStore.encoder.encode(store.data)); exporting = true } catch { status = error.localizedDescription }
                }
                Button("Restore JSON backup") { restoreMode = true; importing = true }
                Text("Everything is stored locally. No account, analytics, cloud database or nutrition API key. Explicit exports can go wherever you choose. Export before reinstalling or changing the signing bundle identifier; deleting the app deletes its local data.").font(.caption).foregroundStyle(.secondary)
            }
            if !status.isEmpty { Section("Status") { Text(status).font(.subheadline).textSelection(.enabled) } }
            Section("About") { Text("Forma · version 1.0"); Text("Native SwiftUI · iOS 17+. Rounded material tiles adapt to accessibility and appearance settings.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Settings")
            .sheet(isPresented: $goals) { GoalEditor(settings: store.data.settings) }
            .fileImporter(isPresented: $importing, allowedContentTypes: restoreMode ? [.json] : [.commaSeparatedText, .plainText]) { result in
                do {
                    let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let bytes = try Data(contentsOf: url)
                    guard bytes.count < 25_000_000 else { throw AppFailure(message: "Import must be smaller than 25 MB.") }
                    if restoreMode { let decoded = try AppStore.decoder.decode(AppData.self, from: bytes); try AppStore.validate(decoded); restoreBytes = bytes; confirmRestore = true }
                    else { guard let text = String(data: bytes, encoding: .utf8) else { throw AppFailure(message: "CSV must use UTF-8 encoding.") }; pendingFoods = try FoodCSV.parse(text); preview = true }
                } catch { status = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Forma-backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                switch result { case .success: status = "Backup exported."; case .failure(let error): status = error.localizedDescription }
            }
            .sheet(isPresented: $preview) {
                NavigationStack { List { Section("\(pendingFoods.count) foods ready") { Text("Matching name, serving and source will update catalog entries. Existing food logs keep their snapshots.") }; ForEach(pendingFoods) { f in VStack(alignment: .leading) { Text(f.name); Text("\(f.serving) · \(f.nutrients.calories.compact) kcal").font(.caption) } } }
                    .navigationTitle("Review import").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { preview = false } }; ToolbarItem(placement: .confirmationAction) { Button("Import") { store.mergeFoods(pendingFoods); status = "Imported \(pendingFoods.count) foods."; preview = false }.disabled(store.loadBlocked) } }
                }
            }
            .confirmationDialog("Replace all app data with this backup? A recovery copy of the current file will be kept on-device.", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restore backup", role: .destructive) { if let restoreBytes { do { try store.restore(restoreBytes); status = "Backup restored." } catch { status = error.localizedDescription } }; restoreBytes = nil }
                Button("Cancel", role: .cancel) { restoreBytes = nil }
            }
    }
    func syncDining() {
        syncing = true
        Task { defer { syncing = false }
            do { let result = try await UMassDining.sync(locationID: store.data.settings.locationID, date: diningDate); store.mergeFoods(result.foods); if diningDate.sameDay(Date()) { store.data.lastUMassSync = Date() }; status = "Imported \(result.foods.count) foods. \(result.warnings) nutrition pages skipped. Menu date: \(diningDate.formatted(date: .abbreviated, time: .omitted))." }
            catch { status = error.localizedDescription }
        }
    }
}
@MainActor struct GoalEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var settings: Settings
    var valid: Bool { settings.calorieGoal.isFinite && settings.calorieGoal > 0 && settings.proteinPercent >= 0 && settings.carbPercent >= 0 && settings.fatPercent >= 0 }
    var body: some View {
        NavigationStack {
            Form {
                NumberField(label: "Daily calories", value: $settings.calorieGoal)
                NumberField(label: "Protein %", value: $settings.proteinPercent)
                NumberField(label: "Carbohydrate %", value: $settings.carbPercent)
                LabeledContent("Fat %", value: settings.fatPercent.compact)
                Text("Fat is the remaining percentage. Protein and carbohydrate use 4 kcal/g; fat uses 9 kcal/g. Your calorie goal stays fixed; Health activity is not automatically added.").font(.caption).foregroundStyle(.secondary)
                if valid { MacroBars(total: Nutrients(), settings: settings) } else { Text("Enter a positive calorie goal and macro percentages that total no more than 100% before fat.").foregroundStyle(.red) }
            }.navigationTitle("Daily goals").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.data.settings.calorieGoal = settings.calorieGoal; store.data.settings.proteinPercent = settings.proteinPercent; store.data.settings.carbPercent = settings.carbPercent; dismiss() }.disabled(!valid || store.loadBlocked) }
            }
        }
    }
}
@MainActor struct FoodCatalogView: View {
    @EnvironmentObject var store: AppStore
    @State private var search = ""
    @State private var editing: Food?
    @State private var adding = false
    var body: some View {
        List {
            ForEach(store.data.foods.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { food in
                Button { editing = food } label: { VStack(alignment: .leading) { Text(food.name); Text("\(food.serving) · \(food.source)").font(.caption).foregroundStyle(.secondary) } }.foregroundStyle(.primary)
                    .swipeActions { Button("Delete", role: .destructive) { store.data.foods.removeAll { $0.id == food.id } } }
            }
        }.searchable(text: $search).navigationTitle("Food catalog").toolbar { Button("Add", systemImage: "plus") { adding = true } }
            .sheet(isPresented: $adding) { FoodEditor { store.mergeFoods([$0]) } }
            .sheet(item: $editing) { food in FoodEditor(food: food) { changed in if let i = store.data.foods.firstIndex(where: { $0.id == food.id }) { var custom = changed; custom.source = "Custom"; custom.sourceURL = nil; custom.fetchedAt = nil; store.data.foods[i] = custom } } }
    }
}
@MainActor struct MealCategoriesView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    var body: some View {
        List {
            Section("Meal groups") { ForEach(store.data.settings.mealNames, id: \.self) { Text($0) }.onDelete { offsets in
                guard store.data.settings.mealNames.count - offsets.count > 0 else { return }; store.data.settings.mealNames.remove(atOffsets: offsets)
            }.onMove { store.data.settings.mealNames.move(fromOffsets: $0, toOffset: $1) } }
            Section { TextField("New meal group", text: $name); Button("Add") { let n = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !n.isEmpty, !store.data.settings.mealNames.contains(n) else { return }; store.data.settings.mealNames.append(n); name = "" } }
            Text("Removing a category does not remove its historical meal entries.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Meal groups").toolbar { EditButton() }
    }
}

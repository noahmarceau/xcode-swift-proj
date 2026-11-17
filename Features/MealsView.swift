import SwiftUI

@MainActor struct MealsView: View {
    @EnvironmentObject var store: AppStore
    @State private var date = Date()
    @State private var adding = false
    @State private var editing: MealEntry?
    var entries: [MealEntry] { store.data.meals.filter { $0.date.sameDay(date) }.sorted { $0.date < $1.date } }
    var mealNames: [String] { Array(Set(store.data.settings.mealNames + entries.map(\.meal))).sorted { a, b in
        (store.data.settings.mealNames.firstIndex(of: a) ?? 999) < (store.data.settings.mealNames.firstIndex(of: b) ?? 999)
    } }
    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 5) {
                Text("MAKE TODAY COUNT").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.tint)
                Text("Welcome, \(store.data.settings.name).").font(.largeTitle.bold())
                DatePicker("Your food diary", selection: $date, displayedComponents: .date)
            }
            Tile {
                HStack(alignment: .firstTextBaseline) { Text(store.total(on: date).calories.compact).font(.system(size: 48, weight: .semibold, design: .rounded)); Text("/ \(store.data.settings.calorieGoal.compact) kcal").foregroundStyle(.secondary) }
                let remaining = store.data.settings.calorieGoal - store.total(on: date).calories
                Text(remaining >= 0 ? "\(remaining.compact) kcal remaining" : "\((-remaining).compact) kcal above goal").font(.subheadline).foregroundStyle(.secondary)
                MacroBars(total: store.total(on: date), settings: store.data.settings)
            }
            ForEach(mealNames, id: \.self) { meal in
                Tile {
                    HStack { Text(meal).font(.headline); Spacer(); Text("\(entries.filter { $0.meal == meal }.reduce(0) { $0 + $1.total.calories }.compact) kcal").font(.caption).foregroundStyle(.secondary) }
                    if entries.filter({ $0.meal == meal }).isEmpty { Text("Nothing logged yet").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(entries.filter { $0.meal == meal }) { entry in
                        Button { editing = entry } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) { Text(entry.food.name).foregroundStyle(.primary); Text("\(entry.servings.compact) × \(entry.food.serving) · \(entry.date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Text(entry.total.calories.compact).foregroundStyle(.primary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            Tile {
                Text("Nutrition detail").font(.headline)
                ForEach(Nutrients.units.keys.sorted(), id: \.self) { key in
                    let known = entries.filter { $0.food.nutrients.micro[key] != nil }.count
                    HStack { Text(Nutrients.label(key)); Spacer(); Text(known == 0 ? "—" : "\((store.total(on: date).micro[key] ?? 0).compact) \(Nutrients.units[key]!)") }.font(.subheadline)
                    if known > 0 && known < entries.count { Text("Known for \(known)/\(entries.count) entries; subtotal only").font(.caption2).foregroundStyle(.secondary) }
                }
                Text("— means unavailable, not zero. Portions and source data affect accuracy.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Fuel").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { adding = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Log food") }
            .sheet(isPresented: $adding) { MealEditor(date: date) }
            .sheet(item: $editing) { entry in MealEditor(date: entry.date, existing: entry) }
    }
}
@MainActor struct MealEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var date: Date
    var existing: MealEntry? = nil
    @State private var selected: Food? = nil
    @State private var servings: Double = 1
    @State private var meal = "Breakfast"
    @State private var search = ""
    @State private var custom = false
    var body: some View {
        NavigationStack {
            Form {
                Section("When & how much") {
                    DatePicker("Date & time", selection: $date)
                    Picker("Meal", selection: $meal) { ForEach(Array(Set(store.data.settings.mealNames + [meal])).sorted(), id: \.self) { Text($0).tag($0) } }
                    NumberField(label: "Servings", value: $servings)
                    if let selected { Text("\(selected.name) · \(selected.serving)").font(.headline); Text("\(selected.nutrients.scaled(servings).calories.compact) kcal").foregroundStyle(.tint) }
                }
                Section("Choose food") {
                    TextField("Search your food catalog", text: $search)
                    Button("Create a custom food", systemImage: "plus") { custom = true }
                    ForEach(store.data.foods.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { food in
                        Button { selected = food } label: {
                            HStack { VStack(alignment: .leading) { Text(food.name); Text("\(food.serving) · \(food.nutrients.calories.compact) kcal · \(food.source)").font(.caption).foregroundStyle(.secondary) }; Spacer(); if selected?.id == food.id { Image(systemName: "checkmark.circle.fill") } }
                        }.foregroundStyle(.primary)
                    }
                }
                if let selected {
                    Section("Source") { Text(selected.source); if let fetched = selected.fetchedAt { Text("Retrieved \(fetched.formatted())") }; if let raw = selected.sourceURL, let url = URL(string: raw) { Link("Nutrition source", destination: url) } }
                }
                if let existing { Section { Button("Delete entry", role: .destructive) { store.data.meals.removeAll { $0.id == existing.id }; dismiss() } } }
            }.navigationTitle(existing == nil ? "Log food" : "Edit entry")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(selected == nil || !servings.isFinite || servings <= 0 || store.loadBlocked) } }
                .onAppear { if let existing { selected = existing.food; servings = existing.servings; meal = existing.meal } else { meal = store.data.settings.mealNames.first ?? "Breakfast" } }
                .sheet(isPresented: $custom) { FoodEditor { food in store.mergeFoods([food]); selected = food } }
        }
    }
    func save() {
        guard let selected else { return }
        let entry = MealEntry(id: existing?.id ?? UUID(), date: date, meal: meal, food: selected, servings: servings)
        if let index = store.data.meals.firstIndex(where: { $0.id == entry.id }) { store.data.meals[index] = entry } else { store.data.meals.append(entry) }; dismiss()
    }
}
@MainActor struct FoodEditor: View {
    @Environment(\.dismiss) var dismiss
    @State var food = Food(name: "", serving: "1 serving", nutrients: Nutrients())
    var onSave: (Food) -> Void
    @State private var micro: [String: String] = [:]
    var valid: Bool {
        !food.name.trimmingCharacters(in: .whitespaces).isEmpty && !food.serving.isEmpty &&
        [food.nutrients.calories, food.nutrients.protein, food.nutrients.carbs, food.nutrients.fat].allSatisfy { $0.isFinite && $0 >= 0 } &&
        micro.values.allSatisfy { $0.isEmpty || (Double($0).map { $0.isFinite && $0 >= 0 } ?? false) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Per serving") { TextField("Food name", text: $food.name); TextField("Serving description", text: $food.serving)
                    NumberField(label: "Calories", value: $food.nutrients.calories); NumberField(label: "Protein (g)", value: $food.nutrients.protein)
                    NumberField(label: "Carbs (g)", value: $food.nutrients.carbs); NumberField(label: "Fat (g)", value: $food.nutrients.fat)
                }
                Section("Optional nutrients · blank means unknown") {
                    ForEach(Nutrients.units.keys.sorted(), id: \.self) { key in
                        HStack { Text("\(Nutrients.label(key)) (\(Nutrients.units[key]!))"); TextField("Unknown", text: Binding(get: { micro[key] ?? "" }, set: { micro[key] = $0 })).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    }
                }
            }.navigationTitle("Food details").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { food.nutrients.micro = micro.compactMapValues(Double.init); onSave(food); dismiss() }.disabled(!valid) }
            }.onAppear { micro = food.nutrients.micro.mapValues { String($0) } }
        }
    }
}

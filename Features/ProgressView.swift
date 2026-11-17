import SwiftUI
import Charts

enum TrendMetric: String, CaseIterable, Identifiable {
    case load = "Best load", reps = "Best reps", oneRM = "Estimated 1RM", volume = "Volume", rest = "Rest before sets"
    case calories = "Calories", protein = "Protein", weight = "Body weight", sleep = "Sleep", burn = "Energy burned"
    var id: String { rawValue }
    var training: Bool { [.load, .reps, .oneRM, .volume, .rest].contains(self) }
    func unit(_ s: Settings) -> String {
        switch self {
        case .load, .oneRM, .weight: return s.weightUnit
        case .volume: return "\(s.weightUnit)·reps"
        case .reps: return "reps"
        case .rest: return "seconds"
        case .calories, .burn: return "kcal"
        case .protein: return "g"
        case .sleep: return "hours"
        }
    }
}
struct TrendPoint: Identifiable { var date: Date; var x: Double; var y: Double; var id: Date { date } }
@MainActor struct ProgressViewScreen: View {
    @EnvironmentObject var store: AppStore
    @State private var range = 30
    @State private var exercise = "All exercises"
    @State private var search = ""
    @State private var metric = TrendMetric.oneRM
    @State private var comparison = TrendMetric.protein
    @State private var checkIn = false
    @State private var selectedDate = Date()
    @State private var scatter = false
    var names: [String] { ["All exercises"] + Set(store.data.workouts.flatMap(\.exercises).map { $0.plan.name }).sorted() }
    var start: Date { Calendar.current.date(byAdding: .day, value: -(range - 1), to: Date().day)! }
    var dates: [Date] { (0..<range).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) } }
    func value(_ m: TrendMetric, date: Date) -> Double? {
        let workouts = store.data.workouts.filter { $0.startedAt.sameDay(date) }
        let sets = workouts.flatMap(\.exercises).filter { exercise == "All exercises" || $0.plan.name == exercise }.flatMap(\.sets).filter { $0.done && !$0.warmup }
        let s = store.data.settings
        if m.training && sets.isEmpty { return nil }
        switch m {
        case .load: return sets.map { s.displayWeight($0.weightKg) }.max()
        case .reps: return sets.map { Double($0.reps) }.max()
        case .oneRM: return sets.filter { $0.reps <= 12 && $0.weightKg > 0 }.map { s.displayWeight($0.estimated1RM) }.max()
        case .volume: return s.displayWeight(sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) })
        case .rest:
            let rests = sets.compactMap(\.restBefore)
            return rests.isEmpty ? nil : rests.reduce(0, +) / Double(rests.count)
        case .calories: return store.data.meals.contains { $0.date.sameDay(date) } ? store.total(on: date).calories : nil
        case .protein: return store.data.meals.contains { $0.date.sameDay(date) } ? store.total(on: date).protein : nil
        case .weight: return store.day(date).weight.map(s.displayWeight)
        case .sleep: return store.day(date).sleepHours
        case .burn: return store.day(date).totalBurn
        }
    }
    func series(_ m: TrendMetric) -> [TrendPoint] { dates.compactMap { date in value(m, date: date).map { TrendPoint(date: date, x: 0, y: $0) } } }
    var pairs: [TrendPoint] { dates.compactMap { date in guard let x = value(comparison, date: date), let y = value(metric, date: date) else { return nil }; return TrendPoint(date: date, x: x, y: y) } }
    var body: some View {
        Screen {
            Text("See the bigger picture.").font(.largeTitle.bold())
            Picker("Time range", selection: $range) { Text("30 days").tag(30); Text("90 days").tag(90); Text("1 year").tag(365) }.pickerStyle(.segmented)
            Tile {
                HStack { Stat(label: "Sessions", value: "\(store.data.workouts.filter { $0.startedAt >= start }.count)"); Stat(label: "Days food logged", value: "\(Set(store.data.meals.filter { $0.date >= start }.map { $0.date.day }).count)") }
                Text("Daily totals reflect what you logged. Missing days are not treated as zero.").font(.caption).foregroundStyle(.secondary)
            }
            Tile {
                TextField("Find an exercise", text: $search)
                Picker("Exercise", selection: $exercise) { ForEach(names.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || $0 == exercise }, id: \.self) { Text($0).tag($0) } }
                Picker("Training / outcome", selection: $metric) { ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) } }
                if exercise == "All exercises" && metric.training { Text("For meaningful strength comparisons, select one exercise. All-exercise views combine different movements.").font(.caption).foregroundStyle(.secondary) }
                trendChart(metric)
            }
            Tile {
                Picker("Compare with", selection: $comparison) { ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Show paired-day scatter plot", isOn: $scatter)
                if scatter {
                    if pairs.isEmpty { Text("Log both measurements on the same day to see pairs.").foregroundStyle(.secondary) }
                    else {
                        Chart(pairs) { point in PointMark(x: .value(comparison.rawValue, point.x), y: .value(metric.rawValue, point.y)).foregroundStyle(.mint) }
                            .chartXAxisLabel("\(comparison.rawValue) (\(comparison.unit(store.data.settings)))")
                            .chartYAxisLabel("\(metric.rawValue) (\(metric.unit(store.data.settings)))").frame(height: 230)
                        Text("\(pairs.count) matched days. Associations do not establish cause; same-day intake may occur after training.").font(.caption).foregroundStyle(.secondary)
                    }
                } else { trendChart(comparison); Text("Charts share the same date range; each has its own units and scale.").font(.caption).foregroundStyle(.secondary) }
            }
            Tile {
                Text("Weekly training volume").font(.headline)
                Chart(weekly) { point in BarMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Volume", point.y)).foregroundStyle(.mint) }.frame(height: 180)
                    .chartYAxisLabel("\(store.data.settings.weightUnit)·reps")
                Text("Warm-ups and unlogged sets excluded. First and current weeks may be partial.").font(.caption).foregroundStyle(.secondary)
            }
            Tile {
                Text("Daily context").font(.headline)
                DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                let record = store.day(selectedDate)
                HStack { Stat(label: "Weight \(store.data.settings.weightUnit)", value: record.weight.map { store.data.settings.displayWeight($0).compact } ?? "—"); Stat(label: "Sleep hours", value: record.sleepHours?.compact ?? "—") }
                HStack { Stat(label: "Food kcal", value: store.data.meals.contains { $0.date.sameDay(selectedDate) } ? store.total(on: selectedDate).calories.compact : "—"); Stat(label: "Burned kcal", value: record.totalBurn?.compact ?? "—") }
                if let burn = record.totalBurn, store.data.meals.contains(where: { $0.date.sameDay(selectedDate) }) {
                    Text("Logged intake − Health energy: \((store.total(on: selectedDate).calories - burn).compact) kcal").font(.subheadline)
                }
                Text("Health energy is active + resting energy, and today is partial. Missing samples or incomplete meal logs can make this balance misleading; no weight-gain prediction is inferred.").font(.caption).foregroundStyle(.secondary)
                if !record.note.isEmpty { Text(record.note) }
                Button("Log weight, sleep & notes") { checkIn = true }.buttonStyle(.bordered)
                ForEach(store.data.workouts.filter { $0.startedAt.sameDay(selectedDate) }) { w in NavigationLink(w.name) { WorkoutSummary(workout: w) } }
            }
        }.navigationTitle("Trends").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $checkIn) { DayEditor(record: store.day(selectedDate)) }
    }
    var weekly: [TrendPoint] {
        let grouped = Dictionary(grouping: series(.volume)) { Calendar.current.dateInterval(of: .weekOfYear, for: $0.date)!.start }
        return grouped.map { TrendPoint(date: $0.key, x: 0, y: $0.value.reduce(0) { $0 + $1.y }) }.sorted { $0.date < $1.date }
    }
    @ViewBuilder func trendChart(_ m: TrendMetric) -> some View {
        let points = series(m)
        if points.isEmpty { Text("No \(m.rawValue.lowercased()) data in this range.").foregroundStyle(.secondary).frame(height: 110) }
        else {
            Chart(points) { point in
                LineMark(x: .value("Date", point.date), y: .value(m.rawValue, point.y)).foregroundStyle(.mint)
                PointMark(x: .value("Date", point.date), y: .value(m.rawValue, point.y)).foregroundStyle(.mint)
            }.chartXScale(domain: start...Date()).chartYAxisLabel(m.unit(store.data.settings)).frame(height: 220)
            Text("\(m.rawValue) · \(points.count) recorded days. Lines connect recorded observations.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
@MainActor struct DayEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var record: DayRecord
    @State private var weight = ""
    @State private var sleep = ""
    var valid: Bool {
        (weight.isEmpty || (Double(weight).map { $0.isFinite && $0 > 0 } ?? false)) &&
        (sleep.isEmpty || (Double(sleep).map { $0.isFinite && $0 >= 0 && $0 <= 24 } ?? false))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(record.date.formatted(date: .complete, time: .omitted)) {
                    HStack { Text("Weight (\(store.data.settings.weightUnit))"); TextField("Optional", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Sleep (hours)"); TextField("Optional", text: $sleep).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    TextField("Recovery, energy or other notes", text: $record.note, axis: .vertical)
                    Text("Log sleep for the night ending on this day. Manual weight takes precedence over Health weight. Clear a field to remove your manual value.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Daily check-in").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { record.weightKg = Double(weight).map { store.data.settings.kilograms($0) }; record.sleepHours = Double(sleep); store.saveDay(record); dismiss() }.disabled(!valid || store.loadBlocked) }
            }.onAppear { weight = record.weightKg.map { String(store.data.settings.displayWeight($0)) } ?? ""; sleep = record.sleepHours.map { String($0) } ?? "" }
        }
    }
}

import SwiftUI

@MainActor struct WorkoutsView: View {
    @EnvironmentObject var store: AppStore
    @State private var template: WorkoutTemplate?
    @State private var session = false
    @State private var summary: Workout?
    @State private var pendingSummary: Workout?
    var body: some View {
        Screen {
            Text("Build your next best.").font(.largeTitle.bold())
            if let active = store.data.activeWorkout {
                Tile { Label("IN PROGRESS", systemImage: "waveform.path.ecg").font(.caption.bold()).foregroundStyle(.tint)
                    Text(active.name).font(.title2.bold()); Text("\(active.exercises.flatMap(\.sets).filter(\.done).count) sets logged · started \(active.startedAt.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                    Button("Resume workout") { session = true }.buttonStyle(.borderedProminent)
                }
            }
            HStack { Text("Your routines").font(.title2.bold()); Spacer(); Button("New", systemImage: "plus") { template = WorkoutTemplate() } }
            ForEach(store.data.templates) { item in
                Tile {
                    HStack { Text(item.name).font(.title3.bold()); Spacer(); Button { template = item } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Edit \(item.name)") }
                    Text(item.exercises.map(\.name).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    HStack { Text("\(item.exercises.count) exercises · \(item.exercises.reduce(0) { $0 + $1.sets }) sets").font(.caption); Spacer(); Button("Start", systemImage: "play.fill") { store.start(item); session = true }.buttonStyle(.borderedProminent).disabled(store.data.activeWorkout != nil || store.loadBlocked) }
                }
            }
            Text("Recent sessions").font(.title2.bold())
            if store.data.workouts.isEmpty { EmptyTile(title: "Your first session starts here", subtitle: "Complete a workout to see your history and personal records.", icon: "dumbbell") }
            ForEach(store.data.workouts.sorted { $0.startedAt > $1.startedAt }.prefix(15)) { workout in
                Button { summary = workout } label: {
                    Tile { HStack { VStack(alignment: .leading) { Text(workout.name).font(.headline); Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(workout.workingSets.count) sets").font(.caption) } }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Train").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $template) { t in TemplateEditor(template: t) }
            .fullScreenCover(isPresented: $session, onDismiss: { summary = pendingSummary; pendingSummary = nil }) { NavigationStack { SessionView { result in pendingSummary = result; session = false } } }
            .sheet(item: $summary) { workout in NavigationStack { WorkoutSummary(workout: workout) } }
    }
}
@MainActor struct TemplateEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var template: WorkoutTemplate
    @State private var delete = false
    var valid: Bool { !template.name.trimmingCharacters(in: .whitespaces).isEmpty && !template.exercises.isEmpty && template.exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.incrementKg.isFinite && $0.incrementKg > 0 } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") { TextField("Name", text: $template.name); TextField("Workout note", text: $template.note, axis: .vertical) }
                ForEach($template.exercises) { $exercise in
                    Section {
                        TextField("Exercise name", text: $exercise.name)
                        Stepper("\(exercise.sets) sets", value: $exercise.sets, in: 1...30)
                        Stepper("Target: \(exercise.targetReps) reps", value: $exercise.targetReps, in: 1...100)
                        Stepper("Rest: \(exercise.restSeconds) seconds", value: $exercise.restSeconds, in: 0...900, step: 15)
                        NumberField(label: "Load increment (\(store.data.settings.weightUnit))", value: Binding(get: { store.data.settings.displayWeight(exercise.incrementKg) }, set: { exercise.incrementKg = store.data.settings.kilograms($0) }))
                        TextField("Exercise note", text: $exercise.note, axis: .vertical)
                        Button("Remove exercise", role: .destructive) { template.exercises.removeAll { $0.id == exercise.id } }
                    }
                }.onMove { source, target in template.exercises.move(fromOffsets: source, toOffset: target) }
                Button("Add exercise", systemImage: "plus") { template.exercises.append(ExercisePlan(name: "")) }
                if store.data.templates.contains(where: { $0.id == template.id }) { Button("Delete routine", role: .destructive) { delete = true } }
            }.navigationTitle("Edit routine").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if let i = store.data.templates.firstIndex(where: { $0.id == template.id }) { store.data.templates[i] = template } else { store.data.templates.append(template) }; dismiss()
                }.disabled(!valid || store.loadBlocked) }
                ToolbarItem(placement: .bottomBar) { EditButton() }
            }.confirmationDialog("Delete this routine? Workout history is retained.", isPresented: $delete) { Button("Delete", role: .destructive) { store.data.templates.removeAll { $0.id == template.id }; dismiss() } }
        }
    }
}
@MainActor struct SessionView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var onFinish: (Workout) -> Void
    @State private var finishConfirm = false
    @State private var discardConfirm = false
    @State private var addExercise = false
    @State private var exerciseName = ""
    var body: some View {
        Screen {
            if let workout = store.data.activeWorkout {
                Tile {
                    HStack { VStack(alignment: .leading, spacing: 5) { Text(workout.startedAt, style: .timer).font(.title2.bold()).monospacedDigit(); Text("Elapsed").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading); Stat(label: "Working sets", value: "\(workout.workingSets.count)"); Stat(label: "Volume (\(store.data.settings.weightUnit))", value: store.data.settings.displayWeight(workout.volumeKg).compact) }
                    TextField("Workout note", text: Binding(get: { store.data.activeWorkout?.note ?? "" }, set: { value in store.editActive { $0.note = value } }), axis: .vertical)
                    Toggle("Rest timers", isOn: Binding(get: { store.data.settings.restTimers }, set: { value in store.data.settings.restTimers = value; if !value { store.editActive { $0.restUntil = nil }; RestNotifications.cancel() }; store.refreshLive() }))
                    if store.data.settings.restTimers, let end = workout.restUntil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack { Label(end > context.date ? "Rest" : "Ready", systemImage: "timer"); Spacer(); Text("\(max(0, Int(ceil(end.timeIntervalSince(context.date))))) s").monospacedDigit(); Button("Skip") { store.editActive { $0.restUntil = nil }; RestNotifications.cancel(); store.refreshLive() } }
                        }
                    }
                }
                ForEach(workout.exercises) { exercise in ExerciseSessionCard(exercise: exercise) }
                Button("Add exercise", systemImage: "plus") { addExercise = true }.buttonStyle(.bordered)
                Button("Finish workout", systemImage: "checkmark.circle.fill") { finishConfirm = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                Button("Discard workout", role: .destructive) { discardConfirm = true }.frame(maxWidth: .infinity)
            }
        }.navigationTitle(store.data.activeWorkout?.name ?? "Workout").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Minimize") { dismiss() } } }
            .confirmationDialog("Finish and save completed sets? Unfinished sets are kept as unlogged.", isPresented: $finishConfirm, titleVisibility: .visible) { Button("Save workout") { if let result = store.finish() { onFinish(result) } } }
            .confirmationDialog("Discard this workout and its sets?", isPresented: $discardConfirm, titleVisibility: .visible) { Button("Discard", role: .destructive) { store.discard(); dismiss() } }
            .alert("Add exercise", isPresented: $addExercise) {
                TextField("Name", text: $exerciseName)
                Button("Add") { let name = exerciseName.trimmingCharacters(in: .whitespaces); guard !name.isEmpty else { return }; store.editActive { $0.exercises.append(WorkoutExercise(plan: ExercisePlan(name: name), sets: [TrainingSet(), TrainingSet(), TrainingSet()])) }; exerciseName = ""; store.refreshLive() }
                Button("Cancel", role: .cancel) {}
            }
    }
}
@MainActor struct ExerciseSessionCard: View {
    @EnvironmentObject var store: AppStore
    var exercise: WorkoutExercise
    var history: [WorkoutExercise] { TrainingAnalysis.history(exercise.plan.name, in: store.data.workouts) }
    var body: some View {
        Tile {
            Text(exercise.plan.name).font(.title3.bold())
            let suggestion = TrainingAnalysis.suggestion(plan: exercise.plan, history: history, percent: store.data.settings.progressionPercent)
            if let weight = suggestion.0 { Label("Suggested: \(store.data.settings.displayWeight(weight).compact) \(store.data.settings.weightUnit)", systemImage: "arrow.up.right").font(.subheadline).foregroundStyle(.tint) }
            Text(suggestion.1).font(.caption).foregroundStyle(.secondary)
            Text("Target \(exercise.plan.targetReps) reps · rest \(exercise.plan.restSeconds)s").font(.caption)
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(exerciseID: exercise.id, set: set, number: index + 1, previous: previous(index))
            }
            HStack { Button("Add set", systemImage: "plus") { edit { e in e.sets.append(TrainingSet(weightKg: e.sets.last?.weightKg ?? 0, reps: e.plan.targetReps)) }; store.refreshLive() }; Spacer() }
            TextField("Exercise note", text: Binding(get: { exercise.note }, set: { value in edit { $0.note = value } }), axis: .vertical).font(.subheadline)
        }
    }
    func previous(_ index: Int) -> TrainingSet? {
        let sets = history.first?.sets.filter { $0.done && !$0.warmup } ?? []
        return index < sets.count ? sets[index] : nil
    }
    func edit(_ mutate: (inout WorkoutExercise) -> Void) { store.editActive { w in if let i = w.exercises.firstIndex(where: { $0.id == exercise.id }) { mutate(&w.exercises[i]) } } }
}
@MainActor struct SetRow: View {
    @EnvironmentObject var store: AppStore
    let exerciseID: UUID
    let set: TrainingSet
    let number: Int
    let previous: TrainingSet?
    func binding<T>(_ path: WritableKeyPath<TrainingSet, T>) -> Binding<T> {
        Binding(get: { set[keyPath: path] }, set: { value in
            store.editActive { w in
                guard let e = w.exercises.firstIndex(where: { $0.id == exerciseID }), let s = w.exercises[e].sets.firstIndex(where: { $0.id == set.id }) else { return }
                w.exercises[e].sets[s][keyPath: path] = value
            }; store.refreshLive()
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)").font(.headline).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.data.settings.weightUnit).font(.caption2).foregroundStyle(.secondary)
                    TextField(previous.map { store.data.settings.displayWeight($0.weightKg).compact } ?? "Weight", value: Binding(get: { store.data.settings.displayWeight(set.weightKg) }, set: { if $0.isFinite { binding(\.weightKg).wrappedValue = store.data.settings.kilograms(max(0, $0)) } }), format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("reps").font(.caption2).foregroundStyle(.secondary)
                    TextField(previous.map { String($0.reps) } ?? "Reps", value: Binding(get: { set.reps }, set: { binding(\.reps).wrappedValue = min(999, max(1, $0)) }), format: .number).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                }
                Button {
                    if set.done { binding(\.completedAt).wrappedValue = nil; store.editActive { $0.restUntil = nil }; RestNotifications.cancel(); store.refreshLive() }
                    else { store.complete(exerciseID: exerciseID, setID: set.id) }
                } label: { Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(set.done ? Color.mint : Color.secondary) }.accessibilityLabel(set.done ? "Undo set \(number)" : "Log set \(number)")
                .disabled(!set.done && (set.reps <= 0 || !set.weightKg.isFinite || set.weightKg < 0))
            }
            if let previous { Text("Last working: \(store.data.settings.displayWeight(previous.weightKg).compact) \(store.data.settings.weightUnit) × \(previous.reps)").font(.caption2).foregroundStyle(.secondary).padding(.leading, 30) }
            HStack {
                Toggle("Warm-up", isOn: binding(\.warmup)).toggleStyle(.button)
                Toggle("Failure", isOn: binding(\.failure)).toggleStyle(.button)
                Spacer()
                if !set.done { Button(set.startedAt == nil ? "Start" : "Started") { store.startSet(exerciseID: exerciseID, setID: set.id) }.disabled(set.startedAt != nil) }
                Button(role: .destructive) { store.editActive { w in if let e = w.exercises.firstIndex(where: { $0.id == exerciseID }) { w.exercises[e].sets.removeAll { $0.id == set.id } } }; store.refreshLive() } label: { Image(systemName: "trash") }.accessibilityLabel("Remove set")
            }.font(.caption2)
            if let rest = set.restBefore { Text("Rest before set: \(Int(rest))s").font(.caption2).foregroundStyle(.secondary) }
        }.padding(10).background(set.done ? Color.mint.opacity(0.08) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
}
@MainActor struct WorkoutSummary: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var workout: Workout
    @State private var delete = false
    var records: [String] { TrainingAnalysis.records(for: workout, previous: store.data.workouts.filter { $0.id != workout.id && $0.startedAt < workout.startedAt }) }
    var body: some View {
        Screen {
            Text("Session complete.").font(.largeTitle.bold())
            Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            Tile { HStack { Stat(label: "Working sets", value: "\(workout.workingSets.count)"); Stat(label: "Minutes", value: "\(Int((workout.endedAt ?? Date()).timeIntervalSince(workout.startedAt) / 60))"); Stat(label: "Volume \(store.data.settings.weightUnit)", value: store.data.settings.displayWeight(workout.volumeKg).compact) } }
            Tile { Label("Personal records", systemImage: "trophy.fill").font(.headline).foregroundStyle(.tint); if records.isEmpty { Text("Consistency counts. No new record this session.") }; ForEach(records, id: \.self) { Text($0) }; Text("Estimated 1RM uses Epley for 1–12 reps; warm-ups are excluded. These are estimates, not tested maxes.").font(.caption).foregroundStyle(.secondary) }
            if !workout.note.isEmpty { Tile { Text(workout.note) } }
            ForEach(workout.exercises) { exercise in
                Tile { Text(exercise.plan.name).font(.headline); ForEach(exercise.sets) { set in
                    HStack { Text("\(store.data.settings.displayWeight(set.weightKg).compact) \(store.data.settings.weightUnit) × \(set.reps)"); Spacer(); Text(set.done ? (set.warmup ? "Warm-up" : set.failure ? "Failure" : "Done") : "Not logged").font(.caption).foregroundStyle(.secondary) }
                }; if !exercise.note.isEmpty { Text(exercise.note).font(.subheadline).foregroundStyle(.secondary) } }
            }
            Button("Delete session", role: .destructive) { delete = true }
        }.navigationTitle(workout.name).navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
            .confirmationDialog("Delete this workout from history?", isPresented: $delete) { Button("Delete", role: .destructive) { store.data.workouts.removeAll { $0.id == workout.id }; dismiss() } }
    }
}

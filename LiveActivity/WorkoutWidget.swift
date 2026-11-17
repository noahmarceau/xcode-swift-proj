import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

@main struct FormaWidgets: WidgetBundle { var body: some Widget { WorkoutWidget() } }
struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(context.attributes.title).font(.headline); Spacer(); Text("\(context.state.completed)/\(context.state.total) sets").font(.caption) }
                Text(context.state.exercise).font(.title3.bold())
                HStack {
                    Text("\(context.state.setLabel) · \(context.state.weight) × \(context.state.reps)")
                    Spacer()
                    if let end = context.state.restUntil, end > Date() { Text(timerInterval: Date()...end, countsDown: true).monospacedDigit().frame(width: 55) }
                }.font(.subheadline)
                if context.state.hasNext { controls(context) }
                else { Link("Finish & review in Forma", destination: URL(string: "forma://workout")!) }
            }.padding().activityBackgroundTint(Color(red: 0.08, green: 0.1, blue: 0.11)).activitySystemActionForegroundColor(.mint)
                .foregroundStyle(.white).widgetURL(URL(string: "forma://workout"))
        } dynamicIsland: { context in
            DynamicIsland(expanded: {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.exercise).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.completed)/\(context.state.total)").foregroundStyle(.mint) }
                DynamicIslandExpandedRegion(.center) { Text("\(context.state.weight) × \(context.state.reps)") }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.hasNext { controls(context) }
                    else { Text("All sets logged · open to finish") }
                }
            }, compactLeading: { Image(systemName: "dumbbell.fill").foregroundStyle(.mint) },
              compactTrailing: { Text("\(context.state.completed)/\(context.state.total)").font(.caption2) },
              minimal: { Image(systemName: "dumbbell.fill") })
              .widgetURL(URL(string: "forma://workout"))
        }
    }
    func controls(_ context: ActivityViewContext<WorkoutAttributes>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Button("− load", intent: intent(context, "weightDown"))
                Button("+ load", intent: intent(context, "weightUp"))
                Spacer()
                Button("− rep", intent: intent(context, "repDown"))
                Button("+ rep", intent: intent(context, "repUp"))
            }
            HStack {
                Button("Start set", intent: intent(context, "start"))
                Spacer()
                Button("Log set", intent: intent(context, "complete"))
            }
        }.buttonStyle(.bordered).tint(.mint).font(.caption)
    }

    func intent(_ context: ActivityViewContext<WorkoutAttributes>, _ action: String) -> WorkoutSetIntent {
        WorkoutSetIntent(workoutID: context.attributes.workoutID, exerciseID: context.state.exerciseID, setID: context.state.setID, action: action)
    }
}

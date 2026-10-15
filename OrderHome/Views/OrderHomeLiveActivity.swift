import ActivityKit
import SwiftUI
import WidgetKit

public struct OrderHomeLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderHomeActivityAttributes.self) { context in
            lockScreenBanner(context: context)
                .activityBackgroundTint(Color(red: 0.12, green: 0.14, blue: 0.12))
                .activitySystemActionForegroundColor(Color(red: 0.88, green: 0.40, blue: 0.28))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Text(context.attributes.recipeEmoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.recipeTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Text(context.state.stageTitle)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.28))
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.attributes.servings) diners")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        if context.state.totalSteps > 0 {
                            Text("\(context.state.currentStepIndex + 1)/\(context.state.totalSteps)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color(red: 0.22, green: 0.60, blue: 0.45))
                        }
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !context.state.stepTitle.isEmpty {
                            Text(context.state.stepTitle)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                        }

                        if let timerEnd = context.state.timerEnd {
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                    .font(.caption)
                                    .foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.28))
                                Text(timerInterval: Date.now...timerEnd, countsDown: true)
                                    .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.semibold))
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Text(context.attributes.recipeEmoji)
            } compactTrailing: {
                if let timerEnd = context.state.timerEnd {
                    Text(timerInterval: Date.now...timerEnd, countsDown: true)
                        .font(.system(.caption2, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.28))
                        .frame(width: 44)
                } else if context.state.totalSteps > 0 {
                    Text("\(context.state.currentStepIndex + 1)/\(context.state.totalSteps)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.22, green: 0.60, blue: 0.45))
                } else {
                    Image(systemName: context.state.isServed ? "bell.fill" : "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.28))
                }
            } minimal: {
                Text(context.attributes.recipeEmoji)
            }
        }
    }

    @ViewBuilder
    private func lockScreenBanner(context: ActivityViewContext<OrderHomeActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.22, green: 0.60, blue: 0.45).opacity(0.2))
                    .frame(width: 48, height: 48)
                Text(context.attributes.recipeEmoji)
                    .font(.title2)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(context.state.stageTitle.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.28))
                    if context.state.totalSteps > 0 {
                        Text("· Step \(context.state.currentStepIndex + 1) of \(context.state.totalSteps)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Text(context.attributes.recipeTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !context.state.stepTitle.isEmpty {
                    Text(context.state.stepTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let timerEnd = context.state.timerEnd {
                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.88, green: 0.40, blue: 0.28))
                    Text(timerInterval: Date.now...timerEnd, countsDown: true)
                        .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(context.attributes.servings)")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text(context.attributes.servings == 1 ? "diner" : "diners")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.12, green: 0.14, blue: 0.12))
    }
}

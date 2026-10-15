import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct OrderHomeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var stageTitle: String
        public var currentStepIndex: Int
        public var totalSteps: Int
        public var stepTitle: String
        public var timerEnd: Date?
        public var isServed: Bool

        public init(
            stageTitle: String,
            currentStepIndex: Int,
            totalSteps: Int,
            stepTitle: String,
            timerEnd: Date? = nil,
            isServed: Bool = false
        ) {
            self.stageTitle = stageTitle
            self.currentStepIndex = currentStepIndex
            self.totalSteps = totalSteps
            self.stepTitle = stepTitle
            self.timerEnd = timerEnd
            self.isServed = isServed
        }
    }

    public var dinnerID: String
    public var recipeTitle: String
    public var recipeEmoji: String
    public var servings: Int

    public init(
        dinnerID: String,
        recipeTitle: String,
        recipeEmoji: String,
        servings: Int
    ) {
        self.dinnerID = dinnerID
        self.recipeTitle = recipeTitle
        self.recipeEmoji = recipeEmoji
        self.servings = servings
    }
}
#endif

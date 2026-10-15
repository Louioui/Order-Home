import Messages
import SwiftUI

/// Builds the bubble that appears in the conversation. Every vote sends a new
/// copy built here; reusing the previous message's `MSSession` is what makes
/// Messages replace the old bubble instead of adding another.
enum PollBubble {
    @MainActor
    static func message(for poll: ChatPoll, session: MSSession?, now: Date = Date()) -> MSMessage {
        let message = MSMessage(session: session ?? MSSession())
        let layout = MSMessageTemplateLayout()
        let decision = poll.decision(now: now)
        layout.image = image(for: poll, decided: decision != nil)
        layout.caption = decision == nil ? "Tonight’s Kitchen Poll" : "Dinner decided"
        layout.subcaption = subcaption(for: poll, decided: decision != nil)
        layout.trailingCaption = decision == nil
            ? "Votes lock \(poll.deadline.formatted(date: .omitted, time: .shortened))"
            : poll.progressText
        message.layout = layout
        message.url = poll.url
        message.summaryText = decision == nil
            ? "Kitchen poll: \(poll.progressText)"
            : "Dinner decided: \(poll.leader?.dish.title ?? "no votes")"
        return message
    }

    private static func subcaption(for poll: ChatPoll, decided: Bool) -> String {
        guard let leader = poll.leader else { return decided ? "Nobody voted" : poll.progressText }
        return decided
            ? "\(leader.dish.title) · \(leader.percent)% happy"
            : "\(poll.progressText) · Leading: \(leader.dish.title)"
    }

    @MainActor
    private static func image(for poll: ChatPoll, decided: Bool) -> UIImage? {
        let renderer = ImageRenderer(content: PollBubbleCard(poll: poll, decided: decided))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The picture at the top of the bubble: the dishes on the table, on the
/// app's terracotta.
private struct PollBubbleCard: View {
    let poll: ChatPoll
    let decided: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(decided ? "DINNER DECIDED" : "WHAT’S FOR DINNER?")
                .font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(.white.opacity(0.8))
            ForEach(poll.dishes) { dish in
                let isLeader = decided && poll.leader?.dish.id == dish.id
                HStack(spacing: 10) {
                    Text(PollDishMenu.emoji(for: dish.id)).font(.system(size: 22))
                    Text(dish.title).font(.system(size: 17, weight: isLeader ? .bold : .medium, design: .serif))
                        .lineLimit(1)
                    if isLeader { Spacer(minLength: 0); Text("✓").font(.system(size: 17, weight: .bold)) }
                }
                .foregroundStyle(.white)
                .opacity(decided && !isLeader ? 0.55 : 1)
            }
        }
        .padding(22)
        .frame(width: 320, alignment: .leading)
        .frame(minHeight: 180, alignment: .leading)
        .background(LinearGradient(colors: [PollTheme.accent, Color(hex: 0xA83F20)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

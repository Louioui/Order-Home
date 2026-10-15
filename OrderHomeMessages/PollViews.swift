import SwiftUI

struct PollRootView: View {
    @Bindable var model: PollModel

    var body: some View {
        Group {
            switch model.screen {
            case .start: StartPollView(model: model)
            case .compose: ComposePollView(model: model)
            case .vote(let poll): PollDetailView(model: model, poll: poll)
            case .newerVersion:
                NoticeView(emoji: "⬆️", title: "Update Order Home", message: "This poll was made with a newer version of Order Home. Update the app to see it.")
            case .invalid:
                NoticeView(emoji: "🤔", title: "This poll couldn’t be read", message: "Ask whoever sent it to start a new one.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PollTheme.background)
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }
}

// MARK: - Start

private struct StartPollView: View {
    let model: PollModel

    var body: some View {
        // The compact drawer is short. A scroll view with wrapping text keeps
        // everything reachable at large accessibility text sizes instead of
        // truncating it.
        ScrollView {
            VStack(spacing: 14) {
                Text("🍽️").font(.system(size: 40))
                Text("What’s for dinner?")
                    .font(.system(.title2, design: .serif)).foregroundStyle(PollTheme.ink)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("Put a few dishes in the chat and let everyone vote right here.")
                    .font(.subheadline).foregroundStyle(PollTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button { model.beginCompose() } label: {
                    Text("Start a poll").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(PollTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }
}

// MARK: - Compose

private struct ComposePollView: View {
    let model: PollModel
    @State private var picked: [String] = []
    @State private var lockMinutes = 60
    private let locks = [(30, "30 min"), (60, "1 hour"), (120, "2 hours"), (240, "4 hours")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start a poll").font(.system(.title, design: .serif)).foregroundStyle(PollTheme.ink)
                    Text("Pick 2 to 5 dishes. Everyone in the chat can vote.")
                        .font(.subheadline).foregroundStyle(PollTheme.muted)
                }
                VStack(spacing: 10) {
                    ForEach(PollDishMenu.all) { entry in dishRow(entry) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("VOTES LOCK IN").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(PollTheme.muted)
                    HStack(spacing: 8) {
                        ForEach(locks, id: \.0) { minutes, label in
                            Button { lockMinutes = minutes } label: {
                                Text(label).font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .foregroundStyle(lockMinutes == minutes ? .white : PollTheme.ink)
                                    .background(lockMinutes == minutes ? PollTheme.ink : .white, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button { send() } label: {
                    Text(picked.count < 2 ? "Pick at least 2 dishes" : "Send poll").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(picked.count < 2 ? PollTheme.muted : PollTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(picked.count < 2)
            }
            .padding(20)
        }
    }

    private func dishRow(_ entry: PollDishMenu.Entry) -> some View {
        let isPicked = picked.contains(entry.id)
        let full = picked.count >= ChatPoll.dishCount.upperBound && !isPicked
        return Button {
            if isPicked { picked.removeAll { $0 == entry.id } } else if !full { picked.append(entry.id) }
        } label: {
            HStack(spacing: 12) {
                Text(entry.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.dish.title).font(.subheadline.weight(.semibold)).foregroundStyle(PollTheme.ink)
                    Text("\(entry.dish.minutes) min").font(.caption).foregroundStyle(PollTheme.muted)
                }
                Spacer()
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPicked ? PollTheme.accent : PollTheme.line).font(.title3)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isPicked ? PollTheme.accent : .clear, lineWidth: 1))
            .opacity(full ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.dish.title), \(entry.dish.minutes) minutes")
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func send() {
        let dishes = picked.compactMap { id in PollDishMenu.all.first { $0.id == id }?.dish }
        model.startPoll(dishes: dishes, lockAfter: TimeInterval(lockMinutes * 60))
    }
}

// MARK: - Poll

private struct PollDetailView: View {
    let model: PollModel
    let poll: ChatPoll
    @State private var draft: [String: PollReaction] = [:]

    private var isComplete: Bool { poll.dishes.allSatisfy { draft[$0.id] != nil } }
    private var isCreator: Bool { poll.creator == model.localKey }

    var body: some View {
        if !model.isExpanded {
            compactSummary
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: context.date)
            }
            .onAppear(perform: seedDraft)
            .onChange(of: poll) { seedDraft() }
        }
    }

    private var compactSummary: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Tonight’s Kitchen Poll").font(.system(.headline, design: .serif)).foregroundStyle(PollTheme.ink)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(poll.progressText).font(.subheadline).foregroundStyle(PollTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button { model.expand() } label: {
                    Text("Open poll").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(PollTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }

    private func content(now: Date) -> some View {
        let decision = poll.decision(now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(now: now, decision: decision)
                if decision == nil { ballot } else { results(decision: decision) }
            }
            .padding(20)
        }
    }

    private func header(now: Date, decision: ChatPoll.Decision?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(decision == nil ? "Tonight’s Kitchen Poll" : "Dinner decided")
                .font(.system(.title, design: .serif)).foregroundStyle(PollTheme.ink)
            Text(decision == nil ? "\(poll.progressText) · \(lockText(now: now))" : decisionText(decision))
                .font(.subheadline).foregroundStyle(PollTheme.muted)
        }
    }

    private func lockText(now: Date) -> String {
        let minutes = max(1, Int(poll.deadline.timeIntervalSince(now) / 60))
        return minutes >= 120 ? "locks in \(minutes / 60) hr" : "locks in \(minutes) min"
    }

    private func decisionText(_ decision: ChatPoll.Decision?) -> String {
        switch decision {
        case .closedByCreator: "Closed by whoever started it · \(poll.progressText)"
        case .deadlinePassed: "Voting time is up · \(poll.progressText)"
        case .everyoneVoted: "Everyone voted"
        case nil: ""
        }
    }

    // MARK: Ballot

    private var ballot: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(poll.dishes) { dish in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(PollDishMenu.emoji(for: dish.id)).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dish.title).font(.subheadline.weight(.semibold)).foregroundStyle(PollTheme.ink)
                            Text("\(dish.minutes) min").font(.caption).foregroundStyle(PollTheme.muted)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(PollReaction.allCases.reversed()) { reaction in reactionButton(reaction, for: dish) }
                    }
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            Button {
                model.cast(poll.dishes.map { draft[$0.id]?.rawValue ?? -1 }, on: poll)
            } label: {
                Text(isComplete ? (poll.ballots[model.localKey] == nil ? "Send my order" : "Update my order") : "React to every dish")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(isComplete ? PollTheme.accent : PollTheme.muted, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!isComplete)
            if isCreator {
                Button { model.close(poll) } label: {
                    Text("Close voting and decide").font(.subheadline.weight(.semibold)).foregroundStyle(PollTheme.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reactionButton(_ reaction: PollReaction, for dish: ChatPoll.Dish) -> some View {
        let selected = draft[dish.id] == reaction
        return Button { draft[dish.id] = reaction } label: {
            VStack(spacing: 3) {
                Text(reaction.emoji).font(.title3)
                Text(reaction.title).font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? PollTheme.accent : PollTheme.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(selected ? PollTheme.accent.opacity(0.1) : PollTheme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? PollTheme.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reaction.title) for \(dish.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func seedDraft() {
        guard let existing = poll.ballots[model.localKey], existing.count == poll.dishes.count else { draft = [:]; return }
        draft = Dictionary(uniqueKeysWithValues: zip(poll.dishes.map(\.id), existing.map { PollReaction(rawValue: $0) ?? .pass }))
    }

    // MARK: Results

    private func results(decision: ChatPoll.Decision?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let leader = poll.leader {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TONIGHT’S WINNER").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.white.opacity(0.8))
                    Text("\(PollDishMenu.emoji(for: leader.dish.id)) \(leader.dish.title)")
                        .font(.system(.title2, design: .serif)).foregroundStyle(.white)
                    Text("\(leader.percent)% table happiness · \(poll.ballots.count) voted")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(PollTheme.accent, in: RoundedRectangle(cornerRadius: 18))
            } else {
                Text("Nobody voted before this poll ended.").font(.subheadline).foregroundStyle(PollTheme.muted)
            }
            ForEach(poll.results()) { result in
                HStack(spacing: 12) {
                    Text(PollDishMenu.emoji(for: result.dish.id)).font(.title3)
                    Text(result.dish.title).font(.subheadline).foregroundStyle(PollTheme.ink)
                    Spacer()
                    Text("\(result.percent)%").font(.subheadline.weight(.semibold)).foregroundStyle(PollTheme.green)
                }
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            Button { model.openOrderHome() } label: {
                Text("Open Order Home").font(.headline).foregroundStyle(PollTheme.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(PollTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Notice

private struct NoticeView: View {
    let emoji: String
    let title: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(emoji).font(.system(size: 36))
                Text(title).font(.system(.title3, design: .serif)).foregroundStyle(PollTheme.ink)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(message).font(.subheadline).foregroundStyle(PollTheme.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
    }
}

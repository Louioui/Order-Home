import Foundation
import Messages
import Observation

/// What the Messages drawer is showing, and the actions behind its buttons.
/// The poll rules themselves live in `ChatPoll`; this type only decides which
/// screen applies and builds the message to send.
@MainActor
@Observable
final class PollModel {
    enum Screen: Equatable {
        /// Nothing selected: offer to start a poll.
        case start
        case compose
        case vote(ChatPoll)
        case newerVersion
        case invalid
    }

    var screen: Screen = .start
    var isExpanded = false
    var errorMessage: String?

    /// Wired by `MessagesViewController`.
    @ObservationIgnored var requestExpanded: () -> Void = {}
    @ObservationIgnored var openApp: (URL) -> Void = { _ in }
    @ObservationIgnored var sendMessage: (MSMessage) -> Void = { _ in }

    private(set) var localKey = ""
    private(set) var participantCount = 1
    @ObservationIgnored private var session: MSSession?

    /// Called whenever the extension becomes active or a message is selected.
    func configure(with conversation: MSConversation) {
        localKey = ChatPoll.voterKey(for: conversation.localParticipantIdentifier)
        participantCount = max(1, conversation.remoteParticipantIdentifiers.count + 1)
        if let selected = conversation.selectedMessage {
            show(selected)
        } else {
            session = nil
            if screen != .compose { screen = .start }
        }
    }

    /// A newer copy of the poll being viewed arrived while the drawer was open,
    /// so the tally updates live. Anything else is ignored.
    func received(_ message: MSMessage) {
        guard case .vote(let current) = screen, let url = message.url,
              case .poll(let incoming) = ChatPoll.decode(url), incoming.id == current.id else { return }
        session = message.session
        screen = .vote(incoming)
    }

    private func show(_ message: MSMessage) {
        session = message.session
        guard let url = message.url else { screen = .invalid; return }
        switch ChatPoll.decode(url) {
        case .poll(let poll): screen = .vote(poll)
        case .newerVersion: screen = .newerVersion
        case .invalid: screen = .invalid
        }
    }

    // MARK: Actions

    func beginCompose() {
        screen = .compose
        requestExpanded()
    }

    /// Opens the drawer to full height, for voting on a poll shown in compact form.
    func expand() { requestExpanded() }

    func startPoll(dishes: [ChatPoll.Dish], lockAfter seconds: TimeInterval) {
        guard let poll = ChatPoll.new(
            dishes: dishes, deadline: Date().addingTimeInterval(seconds),
            creator: localKey, expectedVoters: participantCount
        ) else {
            errorMessage = "Pick between 2 and 5 dishes."
            return
        }
        sendMessage(PollBubble.message(for: poll, session: nil))
    }

    func cast(_ ballot: [Int], on poll: ChatPoll) {
        guard let updated = poll.casting(ballot, voter: localKey, now: Date()) else {
            errorMessage = "Voting has closed, or your order doesn’t cover every dish yet."
            return
        }
        sendMessage(PollBubble.message(for: updated, session: session))
    }

    func close(_ poll: ChatPoll) {
        guard poll.creator == localKey else { return }
        sendMessage(PollBubble.message(for: poll.closing(), session: session))
    }

    func openOrderHome() {
        if let url = URL(string: "orderhome://kitchen") { openApp(url) }
    }
}

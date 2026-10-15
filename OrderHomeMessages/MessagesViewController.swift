import UIKit
import Messages
import SwiftUI

/// Hosts the poll UI inside the Messages drawer. All poll rules live in
/// `ChatPoll`; this class only translates Messages callbacks into model updates
/// and inserts the message the model builds.
final class MessagesViewController: MSMessagesAppViewController {
    private let model = PollModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.requestExpanded = { [weak self] in self?.requestPresentationStyle(.expanded) }
        model.openApp = { [weak self] url in self?.extensionContext?.open(url, completionHandler: nil) }
        model.sendMessage = { [weak self] message in self?.insert(message) }

        let host = UIHostingController(rootView: PollRootView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    /// Puts the message in the conversation's input field. The person taps send
    /// themselves, which keeps every vote an explicit action. Reusing the old
    /// message's session is what makes Messages replace the bubble in place.
    private func insert(_ message: MSMessage) {
        guard let conversation = activeConversation else { return }
        conversation.insert(message) { [weak self] error in
            DispatchQueue.main.async {
                if let error { self?.model.errorMessage = error.localizedDescription }
                else { self?.dismiss() }
            }
        }
    }

    // MARK: Conversation handling

    override func willBecomeActive(with conversation: MSConversation) {
        model.isExpanded = presentationStyle == .expanded
        model.configure(with: conversation)
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        model.configure(with: conversation)
    }

    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        model.received(message)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        model.isExpanded = presentationStyle == .expanded
    }
}

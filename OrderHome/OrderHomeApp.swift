import SwiftUI

@main
struct OrderHomeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: OrderHomeStore
    @State private var cloud: CloudKitchenController

    init() {
        let store = OrderHomeStore.shared
        _store = State(initialValue: store)
        _cloud = State(initialValue: CloudKitchenController(store: store))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if store.hasOnboarded { RootView() }
                else { WelcomeView() }
            }
            .environment(store)
            .environment(cloud)
            .tint(OHTheme.accent)
            .preferredColorScheme(.light)
            .task { KitchenNotifications.shared.installAsDelegate() }
            .task(priority: .utility) {
                await Task.yield()
                await cloud.restore()
            }
            .onOpenURL { url in
                if cloud.handleURL(url) { return }
                if url.scheme == "orderhome" && url.host == "poll" {
                    if case .poll(let poll) = ChatPoll.decode(url) {
                        store.importCompletedChatPoll(poll)
                    } else {
                        store.checkPendingChatPollHandoff()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                cloud.setApplicationActive(phase == .active)
                if phase == .active {
                    store.checkPendingChatPollHandoff()
                }
            }
            .onChange(of: store.session.timerEnd) { _, end in
                if end == nil { KitchenNotifications.shared.cancelTimer() }
            }
        }
    }
}

enum AppTab: String, CaseIterable {
    case tonight = "Tonight", menu = "House menu", kitchen = "Kitchen", table = "Your table"
    var icon: String {
        switch self { case .tonight: "house"; case .menu: "book.closed"; case .kitchen: "frying.pan"; case .table: "person.2" }
    }
}

struct RootView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .tonight
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .tonight: TonightView(onBrowse: { selectedTab = .menu }, onKitchen: { selectedTab = .kitchen }, onTable: { selectedTab = .table })
                case .menu: HouseMenuView()
                case .kitchen: KitchenView()
                case .table: HouseholdView()
                }
            }.frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .background(OHTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(toast).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 14)
                    .background(OHTheme.ink, in: Capsule()).padding(.horizontal, 16).padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { store.toast = nil }
                    .task(id: toast) { try? await Task.sleep(for: .seconds(3)); if store.toast == toast { withAnimation { store.toast = nil } } }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "orderhome" else { return }
            switch url.host {
            case "kitchen", "cooking", "ticket":
                selectedTab = .kitchen
            case "menu", "recipes":
                selectedTab = .menu
            case "table", "household":
                selectedTab = .table
            case "tonight", "pitch", "vote":
                selectedTab = .tonight
            default:
                selectedTab = .tonight
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.checkDeadline()
            } else {
                store.save()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.toast)
        .task(id: store.session.stage) {
            guard store.session.stage == .voting else { return }
            while !Task.isCancelled {
                store.checkDeadline()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: selectedTab == tab ? tab.icon + ".fill" : tab.icon).font(.system(size: 20, weight: .regular))
                        Text(tab.rawValue).font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                    }.frame(maxWidth: .infinity).frame(height: 58).foregroundStyle(selectedTab == tab ? OHTheme.accent : OHTheme.muted)
                }.buttonStyle(.plain).accessibilityIdentifier("tab_\(tab.rawValue)")
            }
        }.padding(.horizontal, 15).padding(.top, 6).background(.white).overlay(alignment: .top) { Rectangle().fill(OHTheme.line).frame(height: 0.5) }
    }
}

import SwiftUI

struct HouseholdView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(CloudKitchenController.self) private var cloud
    @State private var addingMember = false
    @State private var editingMember: Member?
    @State private var confirmingNewDinner = false
    @State private var leavingSample = false
    @State private var showingSharedKitchen = false
    @State private var showingInvitation = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 25) {
                HStack { BrandMark(); Spacer(); TagPill(text: cloud.isSharedKitchen ? "SHARED KITCHEN" : store.household.members.first?.id.hasPrefix("sample-") == true ? "SAMPLE KITCHEN" : "ON THIS IPHONE") }
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "THERE’S ALWAYS A SEAT")
                    Text(store.household.name).font(OHTheme.serif(38)).tracking(-1.2).foregroundStyle(OHTheme.ink)
                    Text("Your favorite people. Your everyday ritual.").font(.system(size: 12)).foregroundStyle(OHTheme.muted)
                }
                if cloud.isSharedKitchen { SharedKitchenConnectionStatus() }
                modePicker
                VStack(alignment: .leading, spacing: 17) {
                    SectionHeading(title: "Who’s coming home?", trailing: cloud.isSharedKitchen ? (cloud.canManageHousehold ? "Invite" : nil) : "Add a seat", action: {
                        if cloud.isSharedKitchen { showingInvitation = true } else { addingMember = true }
                    })
                    ForEach(store.household.members) { member in
                        HStack(spacing: 12) {
                            MemberAvatar(member: member, size: 48)
                            Button { editingMember = member } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 5) { Text(member.name).font(.system(size: 15, weight: .semibold)); if member.id == store.selectedMemberID { Text("YOU").font(.system(size: 8, weight: .bold)).foregroundStyle(OHTheme.accent) } }
                                    Text(member.role + (member.dietaryNotes.isEmpty ? "" : " · \(member.dietaryNotes)")).font(.system(size: 11)).foregroundStyle(OHTheme.muted).lineLimit(2)
                                }.foregroundStyle(OHTheme.ink)
                            }.buttonStyle(.plain).disabled(cloud.isSharedKitchen && member.id != store.selectedMemberID)
                            Spacer(minLength: 0)
                            Toggle("\(member.name) is eating at home", isOn: Binding(get: { member.attending }, set: { attending in
                                if cloud.isSharedKitchen {
                                    Task { _ = await cloud.updateOwnPreferences(attending: attending, note: store.orders[member.id] ?? "") }
                                } else { store.setAttendance(memberID: member.id, attending: attending) }
                            })).labelsHidden().tint(OHTheme.green)
                                .disabled(cloud.isSharedKitchen && (member.id != store.selectedMemberID || cloud.isBusy))
                                .accessibilityIdentifier("attendance-\(member.id)")
                        }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                    HStack(spacing: 5) { Image(systemName: "info.circle"); Text("At-home diners count toward tonight’s portions.") }.font(.system(size: 10)).foregroundStyle(OHTheme.muted)
                    if cloud.isSharedKitchen {
                        Text(cloud.canManageHousehold
                             ? "Everyone sets their own attendance and preferences from their iPhone. Invite someone to add a seat."
                             : "Everyone sets their own attendance and preferences from their iPhone. Ask the kitchen owner to invite more people.")
                            .font(.system(size: 11)).foregroundStyle(OHTheme.muted).lineSpacing(4)
                    }
                }
                VStack(alignment: .leading, spacing: 13) {
                    SectionHeading(title: "The evening details", eyebrow: "A LITTLE PLANNING GOES A LONG WAY")
                    DatePicker("Votes close", selection: Binding(get: { store.session.deadline }, set: { store.session.deadline = $0; store.save() }), displayedComponents: [.date, .hourAndMinute]).font(.system(size: 13)).disabled(cloud.isSharedKitchen || store.session.stage != .pitching).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    if cloud.isSharedKitchen {
                        Text("Your shared dinner’s closing time is kept with the plan, so everyone sees the same deadline.")
                            .font(.system(size: 11)).foregroundStyle(OHTheme.muted).lineSpacing(4)
                    }
                    ShareLink(item: shareText) {
                        HStack { Image(systemName: "square.and.arrow.up"); Text("Share tonight’s dinner plan"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 13, weight: .medium)).foregroundStyle(OHTheme.ink).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                kitchenAccountCard
                if let error = store.persistenceError {
                    Text(error).font(.system(size: 12)).foregroundStyle(OHTheme.accent).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
                if !cloud.isSharedKitchen && store.household.members.first?.id.hasPrefix("sample-") == true {
                    Button { leavingSample = true } label: { Label("Create my own kitchen", systemImage: "house").font(.system(size: 13, weight: .semibold)).foregroundStyle(OHTheme.accent).frame(maxWidth: .infinity).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 15)) }
                }
                if store.session.stage != .pitching && (!cloud.isSharedKitchen || cloud.canManageDinner) {
                    Button { confirmingNewDinner = true } label: { Label("Start a fresh dinner plan", systemImage: "arrow.counterclockwise").font(.system(size: 13, weight: .semibold)).foregroundStyle(OHTheme.accent).frame(maxWidth: .infinity).padding(16).overlay(RoundedRectangle(cornerRadius: 15).stroke(OHTheme.accent.opacity(0.25), lineWidth: 1)) }
                }
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 28)
        }
        .sheet(isPresented: $addingMember) { MemberEditorView(member: nil) }
        .sheet(item: $editingMember) { MemberEditorView(member: $0) }
        .sheet(isPresented: $showingSharedKitchen) { SharedKitchenView() }
        .sheet(isPresented: $showingInvitation) { SharedKitchenInviteView() }
        .confirmationDialog("Ready for your own kitchen?", isPresented: $leavingSample, titleVisibility: .visible) {
            Button("Create my own kitchen") { store.leaveSampleKitchen() }
        } message: { Text("We’ll clear the sample table and take you back to setup. You can explore the sample again any time before setup.") }
        .confirmationDialog("Start a fresh dinner plan?", isPresented: $confirmingNewDinner, titleVisibility: .visible) {
            Button("Start a new plan") {
                KitchenNotifications.shared.cancelTimer()
                if cloud.isSharedKitchen { Task { await cloud.newDinner() } } else { store.newDinner() }
            }
        } message: { Text("This clears tonight’s votes, ticket, and timer. Your people and favorites stay saved.") }
    }
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 13) {
            Eyebrow(text: "YOUR KIND OF TABLE")
            HStack(spacing: 11) {
                ForEach(HouseholdMode.allCases) { mode in
                    Button {
                        if cloud.isSharedKitchen { Task { await cloud.changeMode(mode) } } else { store.setMode(mode) }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: mode == .family ? "person.3" : "heart").font(.system(size: 20))
                            Text(mode.title).font(.system(size: 13, weight: .semibold))
                            Text(mode == .family ? "Every craving counts" : "Two yeses, one dinner").font(.system(size: 10))
                        }.foregroundStyle(store.household.mode == mode ? .white : OHTheme.ink).frame(maxWidth: .infinity, alignment: .leading).padding(18).background(store.household.mode == mode ? OHTheme.ink : .white, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).disabled(store.session.stage != .pitching || (cloud.isSharedKitchen && (!cloud.canManageHousehold || cloud.isBusy)))
                }
            }
            if store.session.stage != .pitching { Text("Choose a different table style when you start a fresh dinner plan.").font(.system(size: 10)).foregroundStyle(OHTheme.muted) }
            else if cloud.isSharedKitchen && !cloud.canManageHousehold { Text("Your kitchen owner chooses the table style.").font(.system(size: 10)).foregroundStyle(OHTheme.muted) }
            if store.household.mode == .couple && store.dinerCount != 2 { Text("Set two diners as eating at home to find a dinner match.").font(.system(size: 11)).foregroundStyle(OHTheme.accent) }
        }
    }
    private var kitchenAccountCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: cloud.isSharedKitchen ? "person.2" : "iphone")
                Text(cloud.isSharedKitchen ? "Your people, one kitchen" : "A kitchen to gather around").font(.system(size: 14, weight: .semibold))
            }.foregroundStyle(OHTheme.ink)
            Text(cloud.isSharedKitchen
                 ? "Your family sees the same dinner plan, votes, and winning ticket. Each person places their own order."
                 : "Your kitchen is saved on this iPhone. Pass the phone and tap a person to collect their order. Share the dinner plan through Messages whenever you like.")
                .font(.system(size: 12)).foregroundStyle(OHTheme.muted).lineSpacing(5)
            if cloud.isSharedKitchen {
                Text(cloud.identity?.email ?? cloud.identity?.displayName ?? "Signed in to Order Home")
                    .font(.system(size: 11)).foregroundStyle(OHTheme.muted).textSelection(.enabled)
            }
            Button { showingSharedKitchen = true } label: {
                HStack {
                    Text(cloud.isSharedKitchen ? "Account & kitchens" : "Connect a shared kitchen")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.font(.system(size: 13, weight: .semibold)).foregroundStyle(OHTheme.accent)
            }.accessibilityIdentifier("manageSharedKitchen")
        }.padding(20).background(OHTheme.lightGreen, in: RoundedRectangle(cornerRadius: 20))
    }
    private var shareText: String {
        if let winner = store.winner { return "Dinner at \(store.household.name) 🍽️\n\(winner.title) for \(store.dinerCount).\n\(store.session.stage.title).\nMade with Order Home." }
        let invitation = cloud.isSharedKitchen ? "Open our shared kitchen in Order Home to place your order." : "Come place your order on our kitchen’s iPhone."
        return "What’s for dinner at \(store.household.name)? 🍽️\nTonight’s choices: \(store.pitches.map(\.title).joined(separator: ", ")).\nVotes close \(store.session.deadline.formatted(date: .abbreviated, time: .shortened)).\n\(invitation)"
    }
}

struct MemberEditorView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(CloudKitchenController.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let member: Member?
    @State private var name = ""
    @State private var emoji = "🥑"
    @State private var role = "Diner"
    @State private var dietaryNotes = ""
    private let emojis = ["🥑", "🧑🏽‍🍳", "👩🏻", "👨🏾", "👧🏽", "👦🏻", "👵🏼", "🌻", "🍋", "🐻", "🌶️", "🍓"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SheetHeader(title: member == nil ? "Pull up a chair." : "A little about you.", subtitle: "Every good kitchen is made of good people.")
                HStack { Spacer(); Text(emoji).font(.system(size: 52)).frame(width: 100, height: 100).background(.white, in: Circle()); Spacer() }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(emojis, id: \.self) { value in
                        Button { emoji = value } label: { Text(value).font(.system(size: 25)).frame(width: 42, height: 42).background(emoji == value ? OHTheme.lightGreen : .clear, in: Circle()) }.buttonStyle(.plain)
                    }
                }
                field("WHAT SHOULD WE CALL YOU?", placeholder: "First name", text: $name)
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "YOUR KITCHEN ROLE")
                    if cloud.isSharedKitchen {
                        Text(role).font(.system(size: 14, weight: .medium)).foregroundStyle(OHTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(17).background(.white, in: RoundedRectangle(cornerRadius: 14))
                        Text("Your role is managed by the shared kitchen.").font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                    } else {
                        Picker("Role", selection: $role) { ForEach(["Head Chef", "Sous Chef", "Diner", "Cleanup Crew", "Taste Tester"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu).tint(OHTheme.ink).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                field("DIETARY PREFERENCES", placeholder: "Vegetarian, mild spice, no mushrooms…", text: $dietaryNotes)
                PrimaryButton(title: member == nil ? "Add a seat at the table" : "Save my details", systemImage: "checkmark") {
                    if cloud.isSharedKitchen {
                        guard member?.id == store.selectedMemberID else { return }
                        Task { if await cloud.saveProfile(name: name, emoji: emoji, dietaryNotes: dietaryNotes) { dismiss() } }
                    } else if let member, let index = store.household.members.firstIndex(where: { $0.id == member.id }) {
                        store.household.members[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                        store.household.members[index].emoji = emoji
                        store.household.members[index].role = role
                        store.household.members[index].dietaryNotes = String(dietaryNotes.prefix(300))
                        store.save()
                        dismiss()
                    } else {
                        store.addMember(name: name, emoji: emoji, role: role)
                        if let index = store.household.members.indices.last { store.household.members[index].dietaryNotes = String(dietaryNotes.prefix(300)); store.save() }
                        dismiss()
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (cloud.isSharedKitchen && (cloud.isBusy || member?.id != store.selectedMemberID)))
                if cloud.isSharedKitchen, let error = cloud.errorMessage { Text(error).font(.system(size: 12)).foregroundStyle(OHTheme.accent) }
            }.padding(24)
        }.background(OHTheme.background).onAppear {
            if let member { name = member.name; emoji = member.emoji; role = member.role; dietaryNotes = member.dietaryNotes }
        }
    }
    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            TextField(placeholder, text: text).font(.system(size: 14)).padding(17).background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

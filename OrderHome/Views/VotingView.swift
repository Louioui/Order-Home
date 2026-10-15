import SwiftUI

struct VotingView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onKitchen: () -> Void
    @State private var showOrder = false
    @State private var cardIndex = 0
    private var locked: Bool { [.ticketLocked, .cooking, .served].contains(store.session.stage) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                SheetHeader(title: locked ? "Dinner, decided." : store.household.mode == .couple ? "Meet your dinner match." : "What’s your craving?", subtitle: locked ? "A little compromise. A very good dinner." : "A good meal starts with everyone having a say.")
                if locked { matchResult }
                else {
                    memberPicker
                    if !store.currentMember.attending {
                        VStack(spacing: 16) {
                            Image(systemName: "moon.stars").font(.system(size: 33)).foregroundStyle(OHTheme.green)
                            Text("Sitting this one out.").font(OHTheme.serif(25))
                            Text("Your vote won’t count while you’re eating out. You can still change your plans.").font(.system(size: 13)).multilineTextAlignment(.center).foregroundStyle(OHTheme.muted)
                            PrimaryButton(title: "I’m eating at home") { store.setAttendance(memberID: store.selectedMemberID, attending: true) }
                        }.padding(23).background(.white, in: RoundedRectangle(cornerRadius: 22))
                    } else if store.household.mode == .couple { coupleDeck }
                    else { familyBallot }
                    Button { showOrder = true } label: {
                        HStack {
                            Image(systemName: "text.bubble").foregroundStyle(OHTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Make it your order").font(.system(size: 14, weight: .semibold)).foregroundStyle(OHTheme.ink)
                                Text("Dietary notes, little tweaks, late plates.").font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(OHTheme.muted)
                        }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                    Text("On this device, pass the phone or switch the diner above to collect everyone’s order.").font(.system(size: 11)).foregroundStyle(OHTheme.muted).lineSpacing(4)
                    if store.household.mode == .family {
                        Button { store.lockWinner() } label: { Text("Close voting & print the winning ticket").font(.system(size: 12, weight: .semibold)).foregroundStyle(OHTheme.accent).frame(maxWidth: .infinity).padding(14) }.disabled(store.votes.isEmpty || store.dinerCount == 0)
                    }
                }
            }.padding(24)
        }.background(OHTheme.background)
            .safeAreaInset(edge: .bottom) {
                if locked { PrimaryButton(title: "Let’s head to the kitchen", systemImage: "arrow.right", action: onKitchen).padding(.horizontal, 24).padding(.vertical, 14).background(OHTheme.background) }
            }
            .sheet(isPresented: $showOrder) { DinerOrderView() }
    }
    private var memberPicker: some View {
        HStack(spacing: 11) {
            MemberAvatar(member: store.currentMember, size: 39)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "PLACING AN ORDER FOR")
                Menu {
                    ForEach(store.household.members) { member in
                        Button(member.name) { store.selectedMemberID = member.id; store.save(); cardIndex = 0 }
                    }
                } label: { HStack(spacing: 6) { Text(store.currentMember.name).font(.system(size: 15, weight: .semibold)); Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)) }.foregroundStyle(OHTheme.ink) }
            }
            Spacer()
            TagPill(text: "\(store.completedVoterCount)/\(store.activeMembers.count) ready")
        }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 19))
    }
    private var familyBallot: some View {
        VStack(spacing: 16) {
            ForEach(store.pitches) { recipe in
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 13) {
                        FoodImage(recipe: recipe).frame(width: 85, height: 87).clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(recipe.title).font(OHTheme.serif(22)).foregroundStyle(OHTheme.ink)
                            Text("\(recipe.durationLabel) · \(recipe.cuisine)").font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                            Text("\(store.score(for: recipe.id)) happiness points").font(.system(size: 10, weight: .medium)).foregroundStyle(OHTheme.green)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 7) {
                        reactionButton(.love, emoji: "🔥", title: "Craving it", recipeID: recipe.id)
                        reactionButton(.down, emoji: "👌", title: "I’m down", recipeID: recipe.id)
                        reactionButton(.pass, emoji: "✋", title: "Pass", recipeID: recipe.id)
                    }
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 22))
            }
        }
    }
    private func reactionButton(_ reaction: Reaction, emoji: String, title: String, recipeID: String) -> some View {
        let selected = store.reaction(for: recipeID) == reaction
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(duration: 0.3)) { store.vote(reaction, for: recipeID) }
        } label: {
            VStack(spacing: 5) {
                Text(emoji).font(.system(size: 19))
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(selected ? OHTheme.accent : OHTheme.muted)
            }.frame(maxWidth: .infinity).padding(.vertical, 11).background(selected ? OHTheme.accent.opacity(0.08) : OHTheme.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? OHTheme.accent : .clear, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel("\(title) for \(store.recipes.first(where: { $0.id == recipeID })?.title ?? "dish")").accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var coupleDeck: some View {
        VStack(spacing: 17) {
            if store.activeMembers.count != 2 {
                Text("Table for two needs exactly two people eating at home. Add your partner or update tonight’s attendance in Your table.").font(.system(size: 13)).foregroundStyle(OHTheme.muted).lineSpacing(5).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
            if !store.pitches.isEmpty {
                let recipe = store.pitches[min(cardIndex, store.pitches.count - 1)]
                ZStack(alignment: .bottomLeading) {
                    FoodImage(recipe: recipe)
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(min(cardIndex, store.pitches.count - 1) + 1) OF \(store.pitches.count) CRAVINGS").font(.system(size: 9, weight: .bold)).tracking(2)
                        Text(recipe.title).font(OHTheme.serif(33))
                        Text("\(recipe.durationLabel) · \(recipe.cuisine)").font(.system(size: 12))
                    }.foregroundStyle(.white).padding(22)
                }.frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 25))
                    .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                        if abs(value.translation.width) > 70 { swipe(value.translation.width > 0 ? .love : .pass, recipeID: recipe.id) }
                    })
                HStack(spacing: 13) {
                    Button { swipe(.pass, recipeID: recipe.id) } label: { Label("Not tonight", systemImage: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(OHTheme.ink).frame(maxWidth: .infinity).padding(19).background(.white, in: RoundedRectangle(cornerRadius: 17)) }.buttonStyle(.plain)
                    PrimaryButton(title: "Yes, please", systemImage: "heart") { swipe(.love, recipeID: recipe.id) }
                }
                if let reaction = store.reaction(for: recipe.id) { Text(reaction == .love ? "You said yes. Waiting for a shared craving." : "Passed for tonight. Keep browsing your cravings.").font(.system(size: 11)).foregroundStyle(OHTheme.muted) }
                Text("Two yeses. One delicious plan.").font(OHTheme.serif(19)).foregroundStyle(OHTheme.ink)
            }
        }
    }
    private func swipe(_ reaction: Reaction, recipeID: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeInOut(duration: 0.2)) {
            store.vote(reaction, for: recipeID)
            if !store.pitches.isEmpty { cardIndex = (cardIndex + 1) % store.pitches.count }
        }
    }
    private var matchResult: some View {
        VStack(spacing: 22) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(OHTheme.accent).padding(.top, 18)
            if let recipe = store.winner {
                FoodImage(recipe: recipe).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 24))
                Text(recipe.title).font(OHTheme.serif(32)).multilineTextAlignment(.center).foregroundStyle(OHTheme.ink)
                Text(store.household.mode == .couple ? "You both said yes. That’s your kind of chemistry." : "Your table has spoken. The kitchen ticket is ready.").font(.system(size: 14)).foregroundStyle(OHTheme.muted).multilineTextAlignment(.center).lineSpacing(5)
                TagPill(text: "\(store.matchPercent(for: recipe.id))% table happiness · \(store.dinerCount) servings")
            }
        }.frame(maxWidth: .infinity)
    }
}

struct DinerOrderView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var attending = true
    @State private var selected: Set<String> = []
    @State private var note = ""
    private let modifiers = ["Mild spice", "No onions", "Sauce on side", "Extra veggies", "Late plate", "Extra crispy"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SheetHeader(title: "Your seat at the table.", subtitle: "A few little details for the chef.")
                HStack(spacing: 12) { MemberAvatar(member: store.currentMember, size: 52); VStack(alignment: .leading, spacing: 5) { Text(store.currentMember.name).font(OHTheme.serif(24)); Text(store.currentMember.dietaryNotes.isEmpty ? "Good food, your way." : store.currentMember.dietaryNotes).font(.system(size: 12)).foregroundStyle(OHTheme.muted) } }.foregroundStyle(OHTheme.ink)
                Toggle(isOn: $attending) { VStack(alignment: .leading, spacing: 6) { Text("I’m eating at home tonight").font(.system(size: 14, weight: .medium)); Text("Your seat counts toward the portions.").font(.system(size: 11)).foregroundStyle(OHTheme.muted) } }.tint(OHTheme.green).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                Eyebrow(text: "THE LITTLE THINGS")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(modifiers, id: \.self) { modifier in
                        Button { if selected.contains(modifier) { selected.remove(modifier) } else { selected.insert(modifier) } } label: { HStack { Text(modifier); Spacer(); Image(systemName: selected.contains(modifier) ? "checkmark.circle.fill" : "plus.circle") }.font(.system(size: 12, weight: .medium)).foregroundStyle(selected.contains(modifier) ? OHTheme.accent : OHTheme.ink).padding(15).background(selected.contains(modifier) ? OHTheme.accent.opacity(0.08) : .white, in: RoundedRectangle(cornerRadius: 13)) }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "A NOTE FOR THE CHEF")
                    TextField("Home at 6:30. Save me a plate?", text: $note, axis: .vertical).lineLimit(3...5).font(.system(size: 14)).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                PrimaryButton(title: "Send my order to the chef", systemImage: "checkmark") {
                    store.setAttendance(memberID: store.selectedMemberID, attending: attending)
                    store.setOrderNote((modifiers.filter { selected.contains($0) } + (note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [note.trimmingCharacters(in: .whitespacesAndNewlines)])).joined(separator: " · "), memberID: store.selectedMemberID)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            }.padding(24)
        }.background(OHTheme.background).onAppear {
            attending = store.currentMember.attending
            let existing = store.orders[store.selectedMemberID] ?? ""
            let parts = existing.components(separatedBy: " · ")
            selected = Set(parts.filter { modifiers.contains($0) })
            note = parts.filter { !modifiers.contains($0) }.joined(separator: " · ")
        }
    }
}

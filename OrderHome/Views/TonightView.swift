import SwiftUI

private enum TonightSheet: String, Identifiable {
    case menu, vote, order
    var id: String { rawValue }
}

struct TonightView: View {
    @Environment(OrderHomeStore.self) private var store
    let onBrowse: () -> Void
    let onKitchen: () -> Void
    let onTable: () -> Void
    @State private var sheet: TonightSheet?
    private var isLocked: Bool { [.ticketLocked, .cooking, .served].contains(store.session.stage) }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                header
                greeting
                if let featured = store.winner ?? store.leader ?? store.recipes.first { hero(featured) }
                tableCard
                if !isLocked { dinnerBoard }
                else { kitchenStatus }
                littleRitual
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 28)
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .menu: MenuBuilderView()
            case .vote: VotingView(onKitchen: { sheet = nil; onKitchen() })
            case .order: DinerOrderView()
            }
        }
    }
    private var header: some View {
        HStack {
            BrandMark()
            Spacer()
            Button(action: onTable) { MemberAvatar(member: store.currentMember, size: 39) }.accessibilityLabel("Open your table")
        }
    }
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max").font(.system(size: 11))
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()).tracking(1.4)
                Spacer()
                Text(store.household.members.first?.id.hasPrefix("sample-") == true ? "SAMPLE KITCHEN" : "MADE FOR YOUR PEOPLE").font(.system(size: 8, weight: .semibold)).tracking(1)
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(OHTheme.muted)
            Text(store.session.stage == .served ? "The best part?\nEveryone’s here." : "Good food.\nBetter together.")
                .font(OHTheme.serif(39)).tracking(-1.6).lineSpacing(-2).foregroundStyle(OHTheme.ink)
            Text(store.session.stage == .served ? "Another dinner, another little memory." : "A place for every craving. A seat for everyone.")
                .font(.system(size: 12)).foregroundStyle(OHTheme.muted)
        }.padding(.top, 3)
    }
    private func hero(_ recipe: Recipe) -> some View {
        ZStack(alignment: .bottomLeading) {
            FoodImage(recipe: recipe).frame(height: 240)
            LinearGradient(colors: [.clear, .black.opacity(0.12), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: 0xD8E4B7)).frame(width: 5, height: 5)
                    Text(isLocked ? "TONIGHT’S WINNING DISH" : store.pitches.isEmpty ? "A LITTLE DINNER INSPIRATION" : "ON TONIGHT’S TABLE").font(.system(size: 9, weight: .bold)).tracking(1.7)
                }.foregroundStyle(.white.opacity(0.86))
                Text(recipe.title).font(OHTheme.serif(29)).foregroundStyle(.white).tracking(-0.7)
                HStack(spacing: 12) {
                    Label(recipe.durationLabel, systemImage: "clock")
                    Text("•")
                    Text(recipe.cuisine)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 18))
                }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            }.padding(21)
            VStack {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: isLocked ? "checkmark.seal.fill" : "sparkle")
                        Text(isLocked ? "Dinner, decided" : "Home tastes better")
                    }.font(.system(size: 10, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule()).foregroundStyle(.white)
                    Spacer()
                    Button { store.toggleFavorite(recipe.id) } label: { Image(systemName: store.favoriteIDs.contains(recipe.id) ? "heart.fill" : "heart").font(.system(size: 15)).foregroundStyle(.white).frame(width: 34, height: 34).background(.black.opacity(0.18), in: Circle()) }.accessibilityLabel("Save \(recipe.title)")
                }
                Spacer()
            }.padding(15)
        }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 23))
            .onTapGesture { if isLocked { onKitchen() } else { sheet = .menu } }
            .accessibilityElement(children: .contain)
    }
    private var tableCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your people, your table").font(OHTheme.serif(20)).foregroundStyle(OHTheme.ink)
                    Text("\(store.activeMembers.count) at home tonight · \(store.household.mode == .family ? "Family table" : "Table for two")").font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                }
                Spacer()
                Button { sheet = .order } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(OHTheme.ink).frame(width: 38, height: 38).background(OHTheme.background, in: Circle()) }.accessibilityLabel("Your dinner preferences")
            }
            HStack(alignment: .top, spacing: 21) {
                ForEach(Array(store.household.members.prefix(5))) { member in
                    Button {
                        store.selectedMemberID = member.id
                        store.save()
                    } label: {
                        VStack(spacing: 6) {
                            MemberAvatar(member: member, size: 45)
                                .overlay(alignment: .bottomTrailing) { Circle().fill(member.attending ? OHTheme.green : OHTheme.muted).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 2)) }
                                .overlay(Circle().stroke(store.selectedMemberID == member.id ? OHTheme.accent : .clear, lineWidth: 1.5).padding(-3))
                            Text(member.name).font(.system(size: 10, weight: .medium)).foregroundStyle(OHTheme.ink).lineLimit(1)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Switch to \(member.name)")
                }
                if store.household.members.count < 5 {
                    Button(action: onTable) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 16)).frame(width: 45, height: 45).background(OHTheme.background, in: Circle()).overlay(Circle().strokeBorder(OHTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3])))
                            Text("Add seat").font(.system(size: 10))
                        }.foregroundStyle(OHTheme.muted)
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }.padding(19).background(.white, in: RoundedRectangle(cornerRadius: 21))
    }
    private var dinnerBoard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "What sounds good?", eyebrow: "THE DINNER BOARD", trailing: "Add a craving", action: { sheet = .menu })
            if store.pitches.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "leaf").font(.system(size: 30)).foregroundStyle(OHTheme.green)
                    Text("A fresh table. Endless possibilities.").font(OHTheme.serif(19)).foregroundStyle(OHTheme.ink)
                    Text("Add two or more dishes to get the dinner vote going.").font(.system(size: 12)).foregroundStyle(OHTheme.muted).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 30).background(.white, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.pitches) { recipe in
                            Button { if store.session.stage == .voting { sheet = .vote } else { sheet = .menu } } label: { boardCard(recipe) }.buttonStyle(.plain)
                        }
                    }.padding(.bottom, 2)
                }.contentMargins(.trailing, 0)
            }
            if store.session.stage == .pitching {
                PrimaryButton(title: store.pitches.count >= 2 ? "Open tonight’s vote" : "Find your next favorite", systemImage: "arrow.right") {
                    if store.pitches.count >= 2 { store.startVoting(); if store.session.stage == .voting { sheet = .vote } }
                    else { sheet = .menu }
                }
            } else {
                VStack(spacing: 10) {
                    HStack {
                        HStack(spacing: 5) { Circle().fill(OHTheme.accent).frame(width: 5, height: 5); Text("THE VOTE IS OPEN").tracking(1.3) }
                        Spacer()
                        Text("\(store.completedVoterCount)/\(store.activeMembers.count) orders in")
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(OHTheme.muted)
                    PrimaryButton(title: store.household.mode == .couple ? "Find your dinner match" : "Place your order", systemImage: "arrow.right") { sheet = .vote }
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                        Text("Votes close at \(store.session.deadline.formatted(date: .omitted, time: .shortened))")
                    }.font(.system(size: 10)).foregroundStyle(OHTheme.muted)
                }
            }
        }
    }
    private func boardCard(_ recipe: Recipe) -> some View {
        let cardScore = store.score(for: recipe.id)
        return VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                FoodImage(recipe: recipe).frame(height: 106).clipShape(RoundedRectangle(cornerRadius: 13))
                if cardScore > 0 { Text("\(cardScore) ♥").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5).background(.white, in: Capsule()).padding(7) }
            }
            Text(recipe.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(OHTheme.ink).lineLimit(1)
            HStack { Text(recipe.durationLabel); Spacer(); Text(recipe.cuisine) }.font(.system(size: 10)).foregroundStyle(OHTheme.muted)
        }.frame(width: 167)
    }
    private var kitchenStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: store.session.stage == .served ? "A dinner worth repeating" : "From our kitchen, with love", eyebrow: "THE EVENING PLAN")
            PrimaryButton(title: store.session.stage == .served ? "See tonight’s memory" : store.session.stage == .cooking ? "Back to cooking" : "Your kitchen ticket is ready", systemImage: "arrow.right", action: onKitchen)
            if store.session.stage == .served {
                Button("Make a new dinner plan") { store.newDinner() }.font(.system(size: 13, weight: .semibold)).foregroundStyle(OHTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
    }
    private var littleRitual: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart").font(.system(size: 17)).foregroundStyle(OHTheme.green).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text("Less deciding. More dining.").font(OHTheme.serif(17)).foregroundStyle(OHTheme.ink)
                Text("The everyday ritual of coming home to good food and your favorite people.").font(.system(size: 11)).foregroundStyle(OHTheme.muted).lineSpacing(4)
            }
        }.padding(.horizontal, 2).padding(.top, 2)
    }
}

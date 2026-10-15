import SwiftUI
import UIKit

@MainActor
struct KitchenView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var servingOverride: Int?
    @State private var studioTab: StudioTab = .steps
    @State private var originalIdleTimerSetting: Bool?

    private enum StudioTab: String, CaseIterable {
        case steps = "Step by step"
        case ingredients = "Ingredients"
    }

    private var servings: Int { max(1, servingOverride ?? store.dinerCount) }

    var body: some View {
        Group {
            if let recipe = store.winner {
                switch store.session.stage {
                case .cooking:
                    cookingStudio(recipe)
                case .served:
                    servedDinner(recipe)
                default:
                    kitchenTicket(recipe)
                }
            } else {
                waitingForDinner
            }
        }
        .background(OHTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if originalIdleTimerSetting == nil {
                originalIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
            }
            updateScreenAwake()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimerSetting ?? false
            originalIdleTimerSetting = nil
        }
        .onChange(of: store.session.stage == .cooking) { _, _ in
            updateScreenAwake()
        }
        .onChange(of: scenePhase) { _, _ in
            updateScreenAwake()
        }
        .onChange(of: store.session.id) { _, _ in
            servingOverride = nil
            studioTab = .steps
        }
    }

    private var waitingForDinner: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                screenHeading("The kitchen.", eyebrow: "READY WHEN YOU ARE", detail: "Every good dinner starts with a little agreement.")

                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(OHTheme.lightGreen).frame(width: 96, height: 96)
                        Image(systemName: "receipt")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(OHTheme.ink)
                    }
                    Text("A table decision,\nthen a kitchen ticket.")
                        .font(.system(size: 27, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(OHTheme.ink)
                    Text("Once tonight’s winner is chosen, your ingredients, table notes, and cooking steps will be waiting here.")
                        .font(.subheadline)
                        .foregroundStyle(OHTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let leader = store.leader {
                        Divider().overlay(OHTheme.line)
                        HStack(spacing: 14) {
                            FoodImage(recipe: leader)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("CURRENT FRONT RUNNER")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .tracking(1.1)
                                    .foregroundStyle(OHTheme.accent)
                                Text(leader.title).font(.headline).foregroundStyle(OHTheme.ink)
                                Text("\(store.matchPercent(for: leader.id))% table match")
                                    .font(.caption).foregroundStyle(OHTheme.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        if store.session.stage == .voting {
                            PrimaryButton(title: "Choose this dinner", systemImage: "checkmark") {
                                store.lockWinner()
                            }
                        }
                    } else {
                        Label("Add a few dishes in House Menu to get started.", systemImage: "fork.knife")
                            .font(.caption)
                            .foregroundStyle(OHTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 26))

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(OHTheme.accent)
                    Text("Less “what’s for dinner?” More time around the table.")
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(OHTheme.ink)
                }
                .padding(.horizontal, 10)
            }
            .padding(24)
        }
    }

    private func kitchenTicket(_ recipe: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                screenHeading("Your order is in.", eyebrow: "THE KITCHEN TICKET", detail: "A good meal. A happy table. Let’s make it happen.")
                receipt(recipe)
                if recipe.ingredients.isEmpty {
                    originalRecipeCard(recipe)
                } else {
                    ingredientsSection(recipe)
                    if !missingIngredients(in: recipe).isEmpty {
                        groceryHandoff(recipe)
                    }
                }
                if let source = recipe.sourceURL, !recipe.ingredients.isEmpty {
                    Link(destination: source) {
                        Label("Open original recipe", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OHTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                PrimaryButton(title: "Let’s get cooking", systemImage: "flame.fill") {
                    studioTab = .steps
                    store.startCooking()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                .disabled(store.dinerCount == 0)
                .opacity(store.dinerCount == 0 ? 0.5 : 1)
                Text(store.dinerCount == 0 ? "Add someone to tonight’s table before cooking." : "Your screen stays awake while you cook.")
                    .font(.caption2).foregroundStyle(OHTheme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(OHTheme.background)
        }
    }

    private func receipt(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("ORDER HOME", systemImage: "fork.knife")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                Spacer()
                Text("ORDER CONFIRMED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(OHTheme.lightGreen, in: Capsule())
            }
            .foregroundStyle(OHTheme.ink)
            .padding(20)

            FoodImage(recipe: recipe)
                .frame(height: 210)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Label("TONIGHT’S WINNER", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(OHTheme.ink, in: Capsule())
                        .padding(16)
                }

            VStack(alignment: .leading, spacing: 18) {
                Text(recipe.title)
                    .font(.system(size: 31, weight: .regular, design: .serif))
                    .foregroundStyle(OHTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    if recipe.minutes > 0 {
                        Label("\(recipe.minutes) min", systemImage: "clock")
                    } else {
                        Label("Saved recipe", systemImage: "bookmark")
                    }
                    Label("\(store.matchPercent(for: recipe.id))% match", systemImage: "heart")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(OHTheme.muted)
                KitchenPerforation().stroke(OHTheme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 1)
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AT THE TABLE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.5).foregroundStyle(OHTheme.muted)
                        Text("\(store.dinerCount) \(store.dinerCount == 1 ? "diner" : "diners") tonight")
                            .font(.system(size: 22, weight: .regular, design: .serif))
                            .foregroundStyle(OHTheme.ink)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: -10) {
                        ForEach(Array(store.activeMembers.prefix(4))) { member in
                            MemberAvatar(member: member, size: 36)
                                .background(.white, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .accessibilityLabel(member.name)
                        }
                    }
                }
                tableNotes
            }
            .padding(20)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(OHTheme.line, lineWidth: 1))
    }

    private var tableNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTES FOR THE CHEF")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5).foregroundStyle(OHTheme.muted)
            ForEach(store.activeMembers) { member in
                let notes = chefNotes(for: member)
                HStack(alignment: .top, spacing: 10) {
                    Text(member.emoji).font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.name).font(.subheadline.weight(.semibold)).foregroundStyle(OHTheme.ink)
                        Text(notes.isEmpty ? "No special requests" : notes)
                            .font(.caption).foregroundStyle(OHTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OHTheme.background, in: RoundedRectangle(cornerRadius: 14))
    }

    private func ingredientsSection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "A little prep.", eyebrow: "THE INGREDIENTS")
            servingControl
            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                    ingredientRow(ingredient, recipe: recipe)
                    if index < recipe.ingredients.count - 1 {
                        Divider().overlay(OHTheme.line).padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            Text("Check off what’s ready. Tap the basket for anything you need.")
                .font(.caption).foregroundStyle(OHTheme.muted)
        }
    }

    private var servingControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make enough for").font(.caption).foregroundStyle(OHTheme.muted)
                    Text("\(servings) \(servings == 1 ? "serving" : "servings")")
                        .font(.headline).foregroundStyle(OHTheme.ink)
                }
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        servingOverride = max(1, servings - 1)
                    } label: {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                    }
                    .disabled(servings <= 1)
                    .accessibilityLabel("Make one fewer serving")
                    Text("\(servings)").font(.headline.monospacedDigit()).frame(minWidth: 24)
                    Button {
                        servingOverride = min(24, servings + 1)
                    } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }
                    .disabled(servings >= 24)
                    .accessibilityLabel("Make one more serving")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OHTheme.ink)
                .background(.white, in: Capsule())
            }
            if servingOverride != nil && servings != max(1, store.dinerCount) {
                Button("Use tonight’s table count (\(store.dinerCount))") { servingOverride = nil }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OHTheme.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private func ingredientRow(_ ingredient: Ingredient, recipe: Recipe) -> some View {
        let checked = store.session.checkedIngredientIDs.contains(ingredient.id)
        let missing = store.session.missingIngredientIDs.contains(ingredient.id)
        return HStack(spacing: 8) {
            Button {
                store.toggleIngredient(ingredient.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(checked ? OHTheme.green : OHTheme.line)
                    .frame(width: 40, height: 52)
            }
            .accessibilityLabel("\(checked ? "Uncheck" : "Check") \(ingredient.name)")
            .accessibilityValue(checked ? "Ready" : "Not checked")

            VStack(alignment: .leading, spacing: 5) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(checked)
                    .foregroundStyle(checked ? OHTheme.muted : OHTheme.ink)
                Text(ingredient.quantity(for: servings, baseServings: recipe.servings))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OHTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)

            Button {
                store.toggleMissing(ingredient.id)
            } label: {
                Image(systemName: missing ? "basket.fill" : "basket")
                    .font(.system(size: 17))
                    .foregroundStyle(missing ? OHTheme.accent : OHTheme.muted)
                    .frame(width: 44, height: 44)
                    .background(missing ? OHTheme.accent.opacity(0.08) : .clear, in: Circle())
            }
            .accessibilityLabel("\(missing ? "Remove" : "Add") \(ingredient.name) \(missing ? "from" : "to") grocery list")
            .accessibilityValue(missing ? "On grocery list" : "Not on grocery list")
        }
        .buttonStyle(.plain)
    }

    private func groceryHandoff(_ recipe: Recipe) -> some View {
        let ingredients = missingIngredients(in: recipe)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "basket.fill").foregroundStyle(OHTheme.accent)
                Text("A little help on the way home.")
                    .font(.system(size: 21, weight: .regular, design: .serif))
                    .foregroundStyle(OHTheme.ink)
            }
            Text(ingredients.map(\.name).joined(separator: ", "))
                .font(.subheadline).foregroundStyle(OHTheme.muted)
            ShareLink(item: groceryList(for: recipe)) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share grocery list (\(ingredients.count))")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OHTheme.accent)
                .padding(15)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .background(OHTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    private func originalRecipeCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "book.pages")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(OHTheme.accent)
            Text("A recipe worth saving.")
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(OHTheme.ink)
            Text("Use the original recipe for its ingredient list, quantities, and full method. Check its serving count so there’s enough for everyone at your table.")
                .font(.subheadline)
                .foregroundStyle(OHTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let source = recipe.sourceURL {
                Link(destination: source) {
                    Label("Open original recipe", systemImage: "arrow.up.right.square")
                        .font(.headline)
                        .foregroundStyle(OHTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(OHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Text("Follow the cooking instructions provided with this dish.")
                    .font(.caption).foregroundStyle(OHTheme.muted)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private func cookingStudio(_ recipe: Recipe) -> some View {
        VStack(spacing: 0) {
            studioBanner(recipe)
            if let timerEnd = store.session.timerEnd {
                timerBanner(end: timerEnd, title: store.session.timerTitle ?? "Kitchen timer")
            }
            Picker("Cooking view", selection: $studioTab) {
                ForEach(StudioTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if studioTab == .steps {
                        cookingSteps(recipe)
                    } else if recipe.ingredients.isEmpty {
                        originalRecipeCard(recipe)
                    } else {
                        ingredientsSection(recipe)
                        if !missingIngredients(in: recipe).isEmpty {
                            groceryHandoff(recipe)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let isLast = recipe.steps.isEmpty || store.session.stepIndex >= recipe.steps.count - 1
            VStack(spacing: 0) {
                PrimaryButton(title: isLast ? "Ring the dinner bell" : "Next step", systemImage: isLast ? "bell.fill" : "arrow.right") {
                    if isLast {
                        KitchenNotifications.shared.cancelTimer()
                        store.ringDinnerBell()
                        KitchenNotifications.shared.playDinnerBell()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else {
                        store.advanceStep()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(OHTheme.background)
        }
    }

    private func studioBanner(_ recipe: Recipe) -> some View {
        ZStack(alignment: .bottomLeading) {
            FoodImage(recipe: recipe)
                .frame(height: 152)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HEAD CHEF STUDIO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.8)
                    Text(recipe.title)
                        .font(.system(size: 25, weight: .regular, design: .serif))
                        .lineLimit(2)
                    Label("Screen stays awake", systemImage: "sun.max")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                if let source = recipe.sourceURL {
                    Link(destination: source) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 19))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .accessibilityLabel("Open original recipe in browser")
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .frame(height: 152)
        .clipped()
    }

    private func cookingSteps(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if !recipe.steps.isEmpty {
                let currentIndex = min(max(store.session.stepIndex, 0), recipe.steps.count - 1)
                let current = recipe.steps[currentIndex]
                let completed = recipe.steps.filter { store.session.completedStepIDs.contains($0.id) }.count
                HStack {
                    Text("STEP \(String(format: "%02d", currentIndex + 1)) OF \(String(format: "%02d", recipe.steps.count))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(OHTheme.accent)
                    Spacer()
                    Text("\(completed) done").font(.caption).foregroundStyle(OHTheme.muted)
                }
                ProgressView(value: Double(completed), total: Double(recipe.steps.count))
                    .tint(OHTheme.green)
                    .accessibilityLabel("Cooking progress")
                    .accessibilityValue("\(completed) of \(recipe.steps.count) steps complete")

                VStack(alignment: .leading, spacing: 22) {
                    Text(current.title)
                        .font(.system(size: 31, weight: .regular, design: .serif))
                        .foregroundStyle(OHTheme.ink)
                    Text(current.instruction)
                        .font(.system(size: 20))
                        .lineSpacing(6)
                        .foregroundStyle(OHTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if recipe.ingredients.isEmpty, let source = recipe.sourceURL {
                        Link(destination: source) {
                            Label("Open original recipe", systemImage: "arrow.up.right.square")
                                .font(.headline)
                                .foregroundStyle(OHTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(OHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    if let seconds = current.timerSeconds, seconds > 0 {
                        Button {
                            store.startTimer(seconds: seconds, title: current.title)
                            if let deadline = store.session.timerEnd {
                                Task {
                                    let result = await KitchenNotifications.shared.scheduleTimer(endingAt: deadline, title: current.title)
                                    guard store.session.timerEnd == deadline else { return }
                                    switch result {
                                    case .alertsDisabled:
                                        store.toast = "Timer started. Enable notifications in Settings for alerts outside the app."
                                    case .failed:
                                        store.toast = "Timer started. The alert couldn’t be scheduled; keep the app open to watch it."
                                    case .scheduled, .superseded:
                                        break
                                    }
                                }
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Label("Start \(timerDuration(seconds)) timer", systemImage: "timer")
                                .font(.headline)
                                .foregroundStyle(OHTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(OHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))

                Text("THE WHOLE RECIPE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5).foregroundStyle(OHTheme.muted)
                    .padding(.top, 4)

                ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                    let done = store.session.completedStepIDs.contains(step.id)
                    Button {
                        store.toggleStep(step.id)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 23, weight: .light))
                                .foregroundStyle(done ? OHTheme.green : OHTheme.muted)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(index + 1). \(step.title)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(OHTheme.ink)
                                    .strikethrough(done)
                                Text(step.instruction)
                                    .font(.caption)
                                    .foregroundStyle(OHTheme.muted)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Step \(index + 1), \(step.title)")
                    .accessibilityValue(done ? "Complete" : "Not complete")
                    .accessibilityHint("Double tap to \(done ? "uncheck" : "complete") this step")
                }
            } else {
                ContentUnavailableView("Ready to make it your own", systemImage: "fork.knife", description: Text("Follow the original recipe for this dish, then ring the dinner bell when it’s ready."))
            }
        }
    }

    private func timerBanner(end: Date, title: String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(ceil(end.timeIntervalSince(context.date))))
            HStack(spacing: 12) {
                Image(systemName: remaining == 0 ? "bell.badge.fill" : "timer")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(remaining == 0 ? "Time’s up!" : title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(remaining == 0 ? "Check your food, chef." : "Keep going. We’re keeping time.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                Text(countdown(remaining))
                    .font(.system(size: 24, weight: .medium, design: .rounded).monospacedDigit())
                    .accessibilityLabel(remaining == 0 ? "Timer finished" : "\(remaining / 60) minutes and \(remaining % 60) seconds remaining")
                Button {
                    KitchenNotifications.shared.cancelTimer()
                    store.cancelTimer()
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 38, height: 44)
                }
                .accessibilityLabel(remaining == 0 ? "Dismiss finished timer" : "Cancel kitchen timer")
            }
            .foregroundStyle(.white)
            .padding(.leading, 24)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .background(remaining == 0 ? OHTheme.accent : OHTheme.ink)
        }
    }

    private func servedDinner(_ recipe: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                screenHeading("Dinner is served.", eyebrow: "ORDER UP!", detail: "Phones down. Forks up. Enjoy your people.")
                ZStack(alignment: .bottomLeading) {
                    FoodImage(recipe: recipe)
                        .frame(height: 290)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("MADE WITH LOVE", systemImage: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                        Text(recipe.title)
                            .font(.system(size: 31, weight: .regular, design: .serif))
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))

                HStack(spacing: 16) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 29, weight: .light))
                        .foregroundStyle(OHTheme.accent)
                        .frame(width: 68, height: 68)
                        .background(OHTheme.accent.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A seat for everyone.")
                            .font(.system(size: 24, weight: .regular, design: .serif))
                            .foregroundStyle(OHTheme.ink)
                        Text("Dinner for \(store.dinerCount), decided together.")
                            .font(.subheadline).foregroundStyle(OHTheme.muted)
                    }
                }
                .padding(.vertical, 8)

                if !store.isSharedPresentation { DinnerRatingCard() }

                VStack(alignment: .leading, spacing: 16) {
                    Text("A keeper?")
                        .font(.system(size: 27, weight: .regular, design: .serif))
                        .foregroundStyle(OHTheme.ink)
                    Text("Save tonight’s meal to your House Menu for an easy encore.")
                        .font(.subheadline).foregroundStyle(OHTheme.muted)
                    Button {
                        store.toggleFavorite(recipe.id)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label(store.favoriteIDs.contains(recipe.id) ? "Saved to House Menu" : "Add to House Menu", systemImage: store.favoriteIDs.contains(recipe.id) ? "heart.fill" : "heart")
                            .font(.headline)
                            .foregroundStyle(OHTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(OHTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))

                Button {
                    servingOverride = nil
                    KitchenNotifications.shared.cancelTimer()
                    store.newDinner()
                } label: {
                    Text("Start a fresh dinner")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OHTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
            }
            .padding(24)
        }
    }

    private func screenHeading(_ title: String, eyebrow: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.9).foregroundStyle(OHTheme.accent)
            Text(title)
                .font(.system(size: 37, weight: .regular, design: .serif))
                .foregroundStyle(OHTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.subheadline).foregroundStyle(OHTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private func missingIngredients(in recipe: Recipe) -> [Ingredient] {
        recipe.ingredients.filter { store.session.missingIngredientIDs.contains($0.id) }
    }

    private func chefNotes(for member: Member) -> String {
        [member.dietaryNotes, store.orders[member.id] ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { notes, next in
                if !notes.contains(where: { $0.caseInsensitiveCompare(next) == .orderedSame }) {
                    notes.append(next)
                }
            }
            .joined(separator: " · ")
    }

    private func groceryList(for recipe: Recipe) -> String {
        let items = missingIngredients(in: recipe).map {
            "☐ \($0.quantity(for: servings, baseServings: recipe.servings)) \($0.name)"
        }.joined(separator: "\n")
        return "Order Home · Can you grab these on the way home?\n\nTonight: \(recipe.title)\nFor \(servings) servings\n\n\(items)\n\nSee you at the table!"
    }

    private func updateScreenAwake() {
        guard originalIdleTimerSetting != nil else { return }
        UIApplication.shared.isIdleTimerDisabled = store.session.stage == .cooking && scenePhase == .active
            ? true
            : originalIdleTimerSetting ?? false
    }

    private func timerDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds / 60) min \(seconds % 60) sec"
    }

    private func countdown(_ seconds: Int) -> String {
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, seconds % 3_600 / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct KitchenPerforation: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

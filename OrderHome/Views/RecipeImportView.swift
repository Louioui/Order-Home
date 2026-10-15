import SwiftUI

struct RecipeImportView: View {
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var link = ""
    @State private var minutes: Int = 0
    @State private var showDetails = false
    @State private var ingredientLines = ""
    @State private var stepLines = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "Saw something delicious?", subtitle: "Give that saved recipe a home.")
                Image(systemName: "link")
                    .font(.system(size: 34))
                    .foregroundStyle(OHTheme.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "GIVE IT A NAME")
                    TextField("e.g. Jamie’s crispy chili noodles", text: $title)
                        .font(.system(size: 14))
                        .padding(17)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "PASTE THE RECIPE LINK")
                    TextField("https://…", text: $link)
                        .font(.system(size: 14))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(17)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }

                Text("YouTube · TikTok · Instagram")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OHTheme.muted)

                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "arrow.up.right.square").foregroundStyle(OHTheme.green)
                    Text("We’ll link directly to the video or creator’s post. You can also add ingredients and steps below so your family gets portion scaling and kitchen timers.")
                        .font(.system(size: 12))
                        .foregroundStyle(OHTheme.muted)
                        .lineSpacing(4)
                }
                .padding(18)
                .background(OHTheme.lightGreen, in: RoundedRectangle(cornerRadius: 17))

                DisclosureGroup(
                    isExpanded: $showDetails,
                    content: {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "COOK TIME (MINUTES)")
                                HStack(spacing: 12) {
                                    TextField("Minutes", value: $minutes, format: .number)
                                        .keyboardType(.numberPad)
                                        .font(.system(size: 14))
                                        .padding(14)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                    Stepper("", value: $minutes, in: 0...300, step: 5)
                                        .labelsHidden()
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "QUICK ADD INGREDIENTS (ONE PER LINE)")
                                TextEditor(text: $ingredientLines)
                                    .font(.system(size: 13))
                                    .frame(minHeight: 110)
                                    .padding(10)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(OHTheme.line, lineWidth: 1))
                                Text("e.g. 2 cups jasmine rice\n1 tbsp sesame oil\n3 scallions")
                                    .font(.caption2)
                                    .foregroundStyle(OHTheme.muted)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "QUICK ADD STEPS (ONE PER LINE)")
                                TextEditor(text: $stepLines)
                                    .font(.system(size: 13))
                                    .frame(minHeight: 110)
                                    .padding(10)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(OHTheme.line, lineWidth: 1))
                                Text("Tip: mentioning “simmer 15 minutes” creates an automatic kitchen timer.")
                                    .font(.caption2)
                                    .foregroundStyle(OHTheme.muted)
                            }
                        }
                        .padding(.top, 10)
                    },
                    label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("Ingredients, steps & timers (optional)")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(OHTheme.ink)
                    }
                )
                .padding(16)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))

                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(OHTheme.accent)
                }

                PrimaryButton(title: "Save to my house menu", systemImage: "bookmark") {
                    guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
                          store.addRecipe(
                            title: title,
                            url: url,
                            minutes: minutes,
                            ingredientLines: ingredientLines,
                            stepLines: stepLines
                          ) else {
                        error = "Use a secure YouTube, TikTok, or Instagram link and add a recipe name."
                        return
                    }
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || link.isEmpty)
            }
            .padding(24)
        }
        .background(OHTheme.background)
    }
}

extension Recipe {
    var durationLabel: String { minutes > 0 ? "\(minutes) min" : "Original recipe" }
}

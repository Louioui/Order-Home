import Foundation

/// Original, fully offline recipes. Quantities serve four; the ticket scales them
/// to the attending diners. No API account or unverified video is required.
enum RecipeCatalog {
    static let all: [Recipe] = [
        Recipe(
            id: "bulgogi", title: "Weeknight bulgogi bowls",
            subtitle: "Sweet soy beef, warm rice & a little crunch.",
            cuisine: "Korean inspired", category: "Better than takeout", minutes: 35,
            servings: 4, imageName: "bulgogi",
            ingredients: [
                ingredient("bulgogi", "beef", "Thinly sliced sirloin", 600, "g"),
                ingredient("bulgogi", "rice", "Dry jasmine rice", 300, "g"),
                ingredient("bulgogi", "water", "Water for rice", 450, "ml"),
                ingredient("bulgogi", "soy", "Soy sauce", 4, "tbsp"),
                ingredient("bulgogi", "sugar", "Brown sugar", 2, "tbsp"),
                ingredient("bulgogi", "sesame", "Toasted sesame oil", 1, "tbsp"),
                ingredient("bulgogi", "garlic", "Garlic, minced", 3, "cloves"),
                ingredient("bulgogi", "ginger", "Fresh ginger, grated", 2, "tsp"),
                ingredient("bulgogi", "oil", "Neutral cooking oil", 1, "tbsp"),
                ingredient("bulgogi", "cucumber", "Cucumber, sliced", 1, ""),
                ingredient("bulgogi", "scallion", "Scallions, sliced", 3, ""),
                ingredient("bulgogi", "seeds", "Sesame seeds", 2, "tsp")
            ],
            steps: [
                step("bulgogi", 1, "Mix the marinade", "Stir the soy sauce, brown sugar, sesame oil, garlic and ginger together. Toss with the sliced beef and refrigerate while you start the rice.", 900),
                step("bulgogi", 2, "Cook fluffy rice", "Rinse the rice until the water runs mostly clear. Add the measured water to a saucepan with the rice. Bring to a boil, cover, reduce to very low heat and simmer for 12 minutes. Remove from the heat and leave covered for 5 minutes.", 720),
                step("bulgogi", 3, "Get the toppings ready", "Slice the cucumber and scallions. Keep them on a clean board away from the raw beef. Set out bowls and sesame seeds.", nil),
                step("bulgogi", 4, "Sear in small batches", "Heat the neutral oil in a large skillet over medium-high heat. Lift the beef out of its marinade and sear in a single layer, working in batches, for about 2–3 minutes per side until browned and cooked through. Discard the leftover raw marinade.", 180),
                step("bulgogi", 5, "Build your bowls", "Fluff the rice and divide it between the bowls. Add the beef, cucumber, scallions and sesame seeds. Serve right away.", nil)
            ], sourceURL: nil
        ),
        Recipe(
            id: "pasta", title: "Creamy tomato rigatoni",
            subtitle: "A silky tomato sauce. An everyone-is-happy kind of pasta.",
            cuisine: "Italian inspired", category: "Family favorites", minutes: 25,
            servings: 4, imageName: "pasta",
            ingredients: [
                ingredient("pasta", "rigatoni", "Dry rigatoni", 400, "g"),
                ingredient("pasta", "oil", "Olive oil", 2, "tbsp"),
                ingredient("pasta", "onion", "Small onion, finely diced", 1, ""),
                ingredient("pasta", "garlic", "Garlic, minced", 3, "cloves"),
                ingredient("pasta", "tomato", "Crushed tomatoes", 600, "g"),
                ingredient("pasta", "cream", "Heavy cream", 120, "ml"),
                ingredient("pasta", "parmesan", "Parmesan, grated", 60, "g"),
                ingredient("pasta", "basil", "Fresh basil", 10, "g"),
                ingredient("pasta", "salt", "Fine salt, plus pasta-water salt", 0.5, "tsp"),
                ingredient("pasta", "pepper", "Black pepper", 0.25, "tsp")
            ],
            steps: [
                step("pasta", 1, "Put the pasta on", "Bring a large pot of salted water to a boil. Add the rigatoni and cook for the time on the packet, checking a minute early for a firm center. Reserve a mug of cooking water before draining.", nil),
                step("pasta", 2, "Soften the aromatics", "Meanwhile, warm the olive oil in a wide saucepan over medium heat. Add the onion and cook for 5 minutes until soft, stirring often. Stir in the garlic and cook for 30 seconds.", 300),
                step("pasta", 3, "Simmer the tomatoes", "Add the crushed tomatoes, measured salt and pepper. Bring to a gentle simmer and cook uncovered for 10 minutes, stirring occasionally.", 600),
                step("pasta", 4, "Make it silky", "Reduce the heat to low. Stir in the cream and half the Parmesan. Add the drained pasta and a splash of reserved cooking water; toss until the sauce coats every ridge. Add more cooking water a little at a time if needed.", nil),
                step("pasta", 5, "Bring everyone to the table", "Taste and adjust the seasoning. Tear the basil over the pasta and finish with the remaining Parmesan. Spoon into warm bowls.", nil)
            ], sourceURL: nil
        ),
        Recipe(
            id: "pizza", title: "Friday-night margherita",
            subtitle: "Crisp edges, bubbling mozzarella & basil on top.",
            cuisine: "Italian inspired", category: "Family favorites", minutes: 30,
            servings: 4, imageName: "pizza",
            ingredients: [
                ingredient("pizza", "dough", "Prepared pizza dough", 600, "g"),
                ingredient("pizza", "flour", "Flour for dusting", 2, "tbsp"),
                ingredient("pizza", "tomato", "Passata", 200, "g"),
                ingredient("pizza", "mozzarella", "Low-moisture mozzarella, torn", 250, "g"),
                ingredient("pizza", "oil", "Olive oil", 1, "tbsp"),
                ingredient("pizza", "oregano", "Dried oregano", 1, "tsp"),
                ingredient("pizza", "salt", "Fine salt", 0.25, "tsp"),
                ingredient("pizza", "basil", "Fresh basil", 10, "g")
            ],
            steps: [
                step("pizza", 1, "Heat the oven", "Heat the oven to 475°F / 245°C with two sturdy baking sheets inside. Let the dough rest at room temperature for 15 minutes so it stretches easily. Keep parchment and oven mitts ready.", 900),
                step("pizza", 2, "Stretch your bases", "Lightly flour the worktop. Divide the dough into two equal pieces for four servings, adding more pizzas for larger tables. Stretch each piece into a thin round on baking parchment, leaving a slightly thicker rim.", nil),
                step("pizza", 3, "Make it yours", "Stir the oregano and salt into the passata. Spread a thin layer over each base, leaving the rim clear. Scatter with mozzarella and drizzle with olive oil.", nil),
                step("pizza", 4, "Bake until golden", "Carefully slide the pizzas and parchment onto the hot baking sheets. Bake for 10–14 minutes, swapping shelves halfway, until the cheese bubbles and the bases and edges are golden. Follow your parchment's maximum heat rating; use lightly oiled sheets if needed.", 720),
                step("pizza", 5, "Finish with basil", "Rest for 2 minutes, scatter with torn basil and slice. Bring the pizzas to the table while the edges are still crisp.", 120)
            ], sourceURL: nil
        ),
        Recipe(
            id: "tacos", title: "Smoky chicken tacos",
            subtitle: "Juicy spiced chicken, avocado & lime. Build your own.",
            cuisine: "Mexican inspired", category: "Quick & easy", minutes: 25,
            servings: 4, imageName: "tacos",
            ingredients: [
                ingredient("tacos", "chicken", "Boneless chicken thighs", 600, "g"),
                ingredient("tacos", "oil", "Olive oil", 1, "tbsp"),
                ingredient("tacos", "paprika", "Smoked paprika", 2, "tsp"),
                ingredient("tacos", "cumin", "Ground cumin", 1, "tsp"),
                ingredient("tacos", "salt", "Fine salt", 0.5, "tsp"),
                ingredient("tacos", "tortilla", "Small corn tortillas", 12, ""),
                ingredient("tacos", "avocado", "Avocados", 2, ""),
                ingredient("tacos", "cabbage", "Red cabbage, finely shredded", 150, "g"),
                ingredient("tacos", "yogurt", "Plain Greek yogurt", 120, "g"),
                ingredient("tacos", "lime", "Limes", 2, ""),
                ingredient("tacos", "cilantro", "Fresh cilantro", 15, "g")
            ],
            steps: [
                step("tacos", 1, "Season the chicken", "Pat the chicken dry and cut into bite-size strips on a dedicated raw-meat board. Toss with the oil, smoked paprika, cumin and salt. Wash your hands and clean the board and knife before preparing the toppings.", nil),
                step("tacos", 2, "Cook until juicy", "Heat a large skillet over medium-high heat. Cook the chicken in a single layer for 8–10 minutes, turning regularly, until browned and the thickest piece reaches 165°F / 74°C. Work in batches for larger portions.", 540),
                step("tacos", 3, "Prep the toppings", "Slice the avocado, shred the cabbage and chop the cilantro. Stir the juice of half the limes into the yogurt. Cut the remaining limes into wedges.", nil),
                step("tacos", 4, "Warm the tortillas", "Warm the tortillas in a dry skillet for about 20 seconds per side. Stack them in a clean towel to keep them soft.", nil),
                step("tacos", 5, "Everyone builds their own", "Put the chicken, tortillas and toppings on the table. Fill each tortilla with chicken, crunchy cabbage, avocado and lime yogurt. Finish with cilantro and a squeeze of lime.", nil)
            ], sourceURL: nil
        ),
        Recipe(
            id: "salmon", title: "Lemon-butter salmon",
            subtitle: "Golden salmon & green beans, all on one tray.",
            cuisine: "Fresh & simple", category: "Date night", minutes: 30,
            servings: 4, imageName: "salmon",
            ingredients: [
                ingredient("salmon", "fish", "Salmon fillets", 600, "g"),
                ingredient("salmon", "potato", "Baby potatoes, halved", 600, "g"),
                ingredient("salmon", "beans", "Green beans, trimmed", 400, "g"),
                ingredient("salmon", "oil", "Olive oil", 2, "tbsp"),
                ingredient("salmon", "butter", "Butter, softened", 40, "g"),
                ingredient("salmon", "lemon", "Lemon", 1, ""),
                ingredient("salmon", "garlic", "Garlic, minced", 2, "cloves"),
                ingredient("salmon", "salt", "Fine salt", 0.75, "tsp"),
                ingredient("salmon", "pepper", "Black pepper", 0.25, "tsp"),
                ingredient("salmon", "parsley", "Fresh parsley, chopped", 10, "g")
            ],
            steps: [
                step("salmon", 1, "Give the potatoes a head start", "Heat the oven to 425°F / 220°C. Toss the halved baby potatoes with half the oil and half the salt on a large baking tray. Roast cut-side down for 15 minutes.", 900),
                step("salmon", 2, "Mix lemon butter", "Mix the softened butter with the garlic, lemon zest and half the lemon juice. Pat the salmon dry and spread the butter over it. Season with the remaining salt and the pepper.", nil),
                step("salmon", 3, "Add the salmon and greens", "Toss the green beans with the remaining oil. Move the potatoes to one side of the tray, add the beans and place the salmon skin-side down in the remaining space. Use a second tray if crowded.", nil),
                step("salmon", 4, "Roast gently", "Roast for 10–14 minutes until the salmon reaches 145°F / 63°C in the thickest part and the potatoes are tender. Check early for thin fillets and continue cooking if needed.", 720),
                step("salmon", 5, "Finish bright", "Squeeze over the remaining lemon juice and scatter with parsley. Serve each plate with salmon, crisp potatoes, green beans and a spoonful of the tray juices.", nil)
            ], sourceURL: nil
        ),
        Recipe(
            id: "soup", title: "Cozy tortilla soup",
            subtitle: "Tomato, black beans & all the crunchy toppings.",
            cuisine: "Mexican inspired", category: "Comfort food", minutes: 30,
            servings: 4, imageName: "soup",
            ingredients: [
                ingredient("soup", "oil", "Olive oil", 1, "tbsp"),
                ingredient("soup", "onion", "Onion, diced", 1, ""),
                ingredient("soup", "garlic", "Garlic, minced", 3, "cloves"),
                ingredient("soup", "cumin", "Ground cumin", 2, "tsp"),
                ingredient("soup", "paprika", "Smoked paprika", 1, "tsp"),
                ingredient("soup", "tomato", "Canned chopped tomatoes", 800, "g"),
                ingredient("soup", "stock", "Vegetable stock", 750, "ml"),
                ingredient("soup", "beans", "Black beans, drained", 480, "g"),
                ingredient("soup", "corn", "Frozen sweetcorn", 200, "g"),
                ingredient("soup", "lime", "Lime", 1, ""),
                ingredient("soup", "chips", "Tortilla chips", 80, "g"),
                ingredient("soup", "avocado", "Avocado", 1, ""),
                ingredient("soup", "cilantro", "Fresh cilantro", 10, "g")
            ],
            steps: [
                step("soup", 1, "Build the flavor", "Warm the olive oil in a large pot over medium heat. Cook the diced onion for 5 minutes until soft. Stir in the garlic, cumin and smoked paprika and cook for 30 seconds.", 300),
                step("soup", 2, "Let it bubble", "Add the chopped tomatoes and vegetable stock. Bring to a boil, reduce the heat and simmer gently for 10 minutes, stirring occasionally.", 600),
                step("soup", 3, "Add beans and corn", "Rinse the drained black beans and add them with the frozen corn. Simmer for 8 minutes until everything is piping hot. Add a splash of water if the soup is thicker than you like.", 480),
                step("soup", 4, "Get the toppings ready", "Dice the avocado, chop the cilantro and break the tortilla chips into large pieces. Squeeze the lime juice into the soup and taste before adding any salt; stock and chips can already be salty.", nil),
                step("soup", 5, "Serve something cozy", "Ladle into bowls and let everyone add their own avocado, cilantro and crunchy tortilla chips just before eating.", nil)
            ], sourceURL: nil
        ),
        Recipe(
            id: "salad", title: "Crispy chickpea bowls",
            subtitle: "Roasted chickpeas, colorful crunch & lemon tahini.",
            cuisine: "Mediterranean inspired", category: "Plant powered", minutes: 30,
            servings: 4, imageName: "salad",
            ingredients: [
                ingredient("salad", "chickpea", "Canned chickpeas, drained", 480, "g"),
                ingredient("salad", "oil", "Olive oil", 2, "tbsp"),
                ingredient("salad", "paprika", "Smoked paprika", 1, "tsp"),
                ingredient("salad", "salt", "Fine salt", 0.5, "tsp"),
                ingredient("salad", "couscous", "Dry couscous", 240, "g"),
                ingredient("salad", "stock", "Boiling vegetable stock", 300, "ml"),
                ingredient("salad", "cucumber", "Cucumber", 1, ""),
                ingredient("salad", "tomato", "Cherry tomatoes", 250, "g"),
                ingredient("salad", "greens", "Baby spinach", 100, "g"),
                ingredient("salad", "tahini", "Tahini", 3, "tbsp"),
                ingredient("salad", "lemon", "Lemon", 1, ""),
                ingredient("salad", "water", "Water for dressing", 3, "tbsp")
            ],
            steps: [
                step("salad", 1, "Roast the chickpeas", "Heat the oven to 425°F / 220°C. Rinse the chickpeas, pat thoroughly dry and toss with the olive oil, paprika and salt. Spread on a baking tray in a single layer and roast for 20–25 minutes, shaking halfway.", 1200),
                step("salad", 2, "Make fluffy couscous", "Put the couscous in a heatproof bowl. Pour over the boiling stock, cover with a plate and leave for 5 minutes, then fluff with a fork. Check your packet's water ratio and adjust the stock amount if it differs.", 300),
                step("salad", 3, "Chop the fresh things", "Dice the cucumber and halve the cherry tomatoes. Wash and dry the spinach. Set everything out so each person can build their own bowl.", nil),
                step("salad", 4, "Whisk the dressing", "Whisk the tahini with the lemon juice. Add the measured water a little at a time until smooth and pourable, adding an extra splash if needed. Taste and adjust the seasoning.", nil),
                step("salad", 5, "Assemble and enjoy", "Divide the couscous and spinach between bowls. Add cucumber, tomatoes and hot crispy chickpeas. Drizzle over the lemon tahini just before serving.", nil)
            ], sourceURL: nil
        ),
        Recipe(
            id: "curry", title: "Coconut chickpea curry",
            subtitle: "A gently spiced, one-pot hug with fluffy rice.",
            cuisine: "Indian inspired", category: "Plant powered", minutes: 30,
            servings: 4, imageName: "curry",
            ingredients: [
                ingredient("curry", "rice", "Dry basmati rice", 300, "g"),
                ingredient("curry", "water", "Water for rice", 450, "ml"),
                ingredient("curry", "oil", "Neutral cooking oil", 1, "tbsp"),
                ingredient("curry", "onion", "Onion, diced", 1, ""),
                ingredient("curry", "garlic", "Garlic, minced", 3, "cloves"),
                ingredient("curry", "ginger", "Fresh ginger, grated", 1, "tbsp"),
                ingredient("curry", "powder", "Mild curry powder", 2, "tbsp"),
                ingredient("curry", "tomato", "Canned chopped tomatoes", 400, "g"),
                ingredient("curry", "coconut", "Coconut milk", 400, "ml"),
                ingredient("curry", "chickpea", "Canned chickpeas, drained", 480, "g"),
                ingredient("curry", "spinach", "Baby spinach", 150, "g"),
                ingredient("curry", "salt", "Fine salt", 0.5, "tsp"),
                ingredient("curry", "lime", "Lime", 1, "")
            ],
            steps: [
                step("curry", 1, "Start the rice", "Rinse the rice, then place in a saucepan with the measured water. Bring to a boil, cover and reduce the heat to very low. Simmer for 12 minutes, then remove from the heat and rest covered for 5 minutes.", 720),
                step("curry", 2, "Soften the aromatics", "Heat the oil in a wide saucepan over medium heat. Cook the onion for 5 minutes until soft. Add the garlic and ginger and stir for 1 minute.", 300),
                step("curry", 3, "Bloom the spices", "Stir in the curry powder and cook for 30 seconds. Add the tomatoes, coconut milk, rinsed chickpeas and salt. Stir well and bring to a gentle simmer.", nil),
                step("curry", 4, "Make it creamy", "Simmer uncovered for 12 minutes, stirring occasionally, until the sauce thickens slightly and the chickpeas are hot. Add the spinach in handfuls and stir until wilted.", 720),
                step("curry", 5, "Finish with lime", "Squeeze the lime juice into the curry and taste for seasoning. Fluff the rice and serve with generous spoonfuls of curry. Keep any extra spice on the side for the table.", nil)
            ], sourceURL: nil
        )
    ]

    static let indexByID: [String: Recipe] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    private static func ingredient(_ recipe: String, _ key: String, _ name: String, _ amount: Double, _ unit: String) -> Ingredient {
        Ingredient(id: "\(recipe)-\(key)", name: name, amount: amount, unit: unit)
    }

    private static func step(_ recipe: String, _ number: Int, _ title: String, _ instruction: String, _ timer: Int?) -> RecipeStep {
        RecipeStep(id: "\(recipe)-step-\(number)", title: title, instruction: instruction, timerSeconds: timer)
    }
}

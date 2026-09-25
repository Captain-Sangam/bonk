import Foundation

public enum BonkDialogueMetrics {
    public static var optionCount: Int { DialogueCatalog.shared.all.count }
}

struct DialogueLine: Equatable, Sendable {
    let id: String
    let intent: ReactionIntent
    let tone: ReactionTone
    let text: String
}

struct DialogueCatalog: Sendable {
    static let shared = DialogueCatalog()

    let all: [DialogueLine]
    private let linesByID: [String: DialogueLine]

    init() {
        var generated: [DialogueLine] = []

        for intent in ReactionIntent.allCases where intent != .promptDoubleEscape {
            let phrases = Self.basePhrases[intent] ?? []
            for tone in ReactionTone.allCases {
                for (index, phrase) in phrases.enumerated() {
                    generated.append(
                        DialogueLine(
                            id: "\(intent.rawValue).\(tone.rawValue).\(index)",
                            intent: intent,
                            tone: tone,
                            text: Self.styled(phrase, tone: tone, index: index)
                        )
                    )
                }
            }
        }

        for (index, text) in Self.unlockHints.enumerated() {
            generated.append(
                DialogueLine(
                    id: "promptDoubleEscape.playful.\(index)",
                    intent: .promptDoubleEscape,
                    tone: .playful,
                    text: text
                )
            )
        }

        all = generated
        linesByID = Dictionary(uniqueKeysWithValues: generated.map { ($0.id, $0) })
    }

    func line(id: String?) -> DialogueLine? {
        guard let id else { return nil }
        return linesByID[id]
    }

    func select(
        intent: ReactionIntent,
        tone: ReactionTone,
        excluding recentIDs: Set<String>,
        seed: Int
    ) -> DialogueLine? {
        let preferred = all.filter {
            $0.intent == intent && $0.tone == tone && !recentIDs.contains($0.id)
        }
        let fallback = all.filter {
            $0.intent == intent && !recentIDs.contains($0.id)
        }
        let candidates = preferred.isEmpty ? fallback : preferred
        guard !candidates.isEmpty else {
            return all.first { $0.intent == intent }
        }
        return candidates[abs(seed) % candidates.count]
    }

    func shortlist(for snapshot: ReactionSnapshot, limit: Int = 32) -> [DialogueLine] {
        let localIntent = LocalReactionProvider().immediateReaction(for: snapshot).intent
        let activitySeed = snapshot.recentEventCounts.values.reduce(0, +) + snapshot.escalationLevel
        var result: [DialogueLine] = []
        var included = Set<String>()

        func append(_ line: DialogueLine?) {
            guard let line, included.insert(line.id).inserted, result.count < limit else { return }
            result.append(line)
        }

        for intent in ReactionIntent.allCases {
            let pool = all.filter { $0.intent == intent }
            guard !pool.isEmpty else { continue }
            append(pool[(activitySeed + result.count) % pool.count])
            append(pool[(activitySeed + result.count + 7) % pool.count])
        }

        let preferred = all.filter { $0.intent == localIntent }
        var preferredIndex = activitySeed
        while result.count < limit, !preferred.isEmpty {
            append(preferred[preferredIndex % preferred.count])
            preferredIndex += 11
            if preferredIndex > activitySeed + (preferred.count * 2) { break }
        }

        return Array(result.prefix(limit))
    }

    private static func styled(_ phrase: String, tone: ReactionTone, index: Int) -> String {
        let tails: [ReactionTone: [String]] = [
            .playful: ["", " Hehe.", " Tiny paws win.", " Boop.", " Catch me if you can.", " Fox rules.", " Nice try.", " Again!"],
            .smug: [" Obviously.", " Called it.", " Too easy.", " As predicted.", " Flawless defense.", " I remain undefeated.", " Skill issue.", " You're welcome."],
            .grumpy: [" Hmph.", " Not again.", " Please stop.", " My patience is tiny.", " That was rude.", " I am judging you.", " Seriously.", " We talked about this."],
            .encouraging: [" Good effort, though.", " Almost had it.", " Keep trying.", " Bold move.", " I respect the hustle.", " Strong attempt.", " You'll get there.", " Ten points for spirit."],
            .dramatic: [" The plot thickens.", " Behold the consequences.", " What a twist!", " The saga continues.", " Cue the thunder.", " This means war.", " History will remember this.", " A legendary mistake."],
            .sleepy: [" I was napping.", " Five more minutes.", " So very tired.", " Wake me later.", " Yawn.", " Must we?", " My eyes are closing.", " This better be important."]
        ]
        let choices = tails[tone] ?? [""]
        return phrase + choices[index % choices.count]
    }

    private static let basePhrases: [ReactionIntent: [String]] = [
        .notice: [
            "...oh?", "I saw that.", "Movement detected.", "Who's there?",
            "One eye open.", "The guard awakens.", "Something moved.", "Hello, trouble."
        ],
        .followCursor: [
            "I see that cursor.", "Where are we going?", "Lead the way.", "I'm right behind you.",
            "A moving target.", "Keep rolling.", "I've got your trail.", "The chase is on."
        ],
        .stalkCursor: [
            "Stealth mode.", "Still watching.", "You can't shake me.", "Silent paws engaged.",
            "I'm closing in.", "The hunt continues.", "Every move is noted.", "Nowhere to hide."
        ],
        .pounce: [
            "Gotcha!", "Pounce protocol!", "Too fast? Never.", "Fox incoming!",
            "Target acquired.", "Airborne paws!", "Intercepted.", "Maximum leap!"
        ],
        .bonk: [
            "BONK!", "Boop denied.", "Not today.", "Paw says no.",
            "Click rejected.", "Protected by fox.", "Access bonked.", "That's a bonk."
        ],
        .swat: [
            "Swat.", "Hands off.", "Back you go.", "Paws on patrol.",
            "Shoo, cursor.", "Denied with style.", "A gentle warning.", "Boundary enforced."
        ],
        .repeatBonk: [
            "BONK BONK.", "Again? Really?", "Rapid bonk mode.", "Double trouble.",
            "Still clicking?", "The bonks continue.", "Persistent, aren't we?", "Combo denied."
        ],
        .annoyed: [
            "Nope.", "I heard that.", "Keyboard privileges revoked.", "Those keys are guarded.",
            "Typing detected.", "Easy on the keyboard.", "Not a single letter.", "Paws over keys."
        ],
        .coverEars: [
            "Too loud.", "My ears!", "So many key clicks.", "The clacking returns.",
            "Indoor typing voice, please.", "Keyboard thunder!", "I can't hear myself think.", "Quiet paws only."
        ],
        .angry: [
            "Seriously?", "You chose chaos.", "Now I'm fluffy and furious.", "That is quite enough.",
            "Emergency grump mode.", "The tail is puffed.", "Final furry warning.", "Patience depleted."
        ],
        .blockShortcut: [
            "Shortcut denied.", "Absolutely not.", "Nice try, power user.", "Command blocked.",
            "No key combo escapes me.", "Modifier mischief detected.", "That shortcut goes nowhere.", "Hotkey, meet fox."
        ],
        .cling: [
            "Hold still!", "Who moved the floor?", "Claws deployed.", "Everything is scrolling.",
            "Steady now.", "I'm hanging on.", "No sudden scrolling.", "The ground is moving."
        ],
        .tumble: [
            "Wheee—no!", "Gravity filed a complaint.", "I meant to do that.", "Tumble protocol.",
            "The world is spinning.", "Fox overboard!", "Unexpected somersault.", "Scrolling has consequences."
        ]
    ]

    private static let unlockHints = [
        "Double-tap Esc to unlock.",
        "Need your Mac? Press Esc twice.",
        "Two quick Esc presses start owner verification.",
        "Double Esc is the way out.",
        "Owner check: tap Esc, then Esc again.",
        "Ready to leave? Double-tap Esc.",
        "Only double Esc opens authentication.",
        "Press Esc twice for Touch ID.",
        "Double Esc, then verify with macOS.",
        "Two Esc taps summon the owner check.",
        "Unlock hint: Esc twice, quickly.",
        "To unbonk, double-tap Esc."
    ]
}

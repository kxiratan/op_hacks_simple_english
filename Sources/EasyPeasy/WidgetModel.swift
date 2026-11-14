import SwiftUI
import AppKit

enum PeasyMode: String, CaseIterable, Identifiable {
    case translate
    case simplify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translate: return "Translate"
        case .simplify: return "Simplify"
        }
    }
}

/// Target language for Translate mode.
enum TranslateLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case chineseSimplified = "Chinese (Simplified)"
    case chineseTraditional = "Chinese (Traditional)"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case italian = "Italian"
    case portuguese = "Portuguese"
    case japanese = "Japanese"
    case korean = "Korean"
    case vietnamese = "Vietnamese"
    case hindi = "Hindi"
    case arabic = "Arabic"
    case russian = "Russian"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// Reading level for Simplify mode, from simplest wording upward.
enum SimplifyLevel: String, CaseIterable, Identifiable {
    case foreigner = "Foreigner"
    case beginner = "Beginner"
    case intermediate = "Intermediate"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// What the widget is doing right now; drives the status line under the options.
enum WidgetStatus: Equatable {
    case idle
    case needsAPIKey
    /// In progress; the text says which step, e.g. "Changing the page… 40%".
    case working(String)
    case done(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle: return "Open a webpage, then click Peasify"
        case .needsAPIKey: return "Add your API key to get started. Click here."
        case .working(let text), .done(let text), .failed(let text): return text
        }
    }

    /// True when clicking the status line does something.
    var isActionable: Bool { self == .needsAPIKey }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

@MainActor
final class WidgetModel: ObservableObject {
    @Published var mode: PeasyMode = .simplify
    @Published var language: TranslateLanguage = .english
    @Published var level: SimplifyLevel = .beginner
    @Published private(set) var status: WidgetStatus = .idle
    /// True while the webpage shows the rewritten text; the button then reads "Unpeasify".
    @Published private(set) var isPeasified = false

    private let peasifier = Peasifier()
    private var job: Task<Void, Never>?

    /// The one button: Peasify the page, or put the original back.
    func buttonTapped() {
        guard !status.isWorking else { return }
        if isPeasified {
            unpeasify()
        } else {
            job = Task { await run() }
        }
    }

    /// Peasify: rewrite the text of the open webpage in place.
    /// Page text is held in memory only.
    func run() async {
        guard let apiKey = APIKeyStore.load() else {
            status = .needsAPIKey
            return
        }

        let options = Peasifier.Options(
            mode: mode,
            language: language,
            level: level,
            apiKey: apiKey,
            model: APIKeyStore.modelOverride() ?? OpenRouterClient.defaultModel
        )
        status = .working("Reading the page…")

        do {
            let outcome = try await peasifier.peasify(options) { [weak self] done, total in
                guard let self, self.status.isWorking, total > 0 else { return }
                let percent = min(100, max(0, done * 100 / total))
                self.status = .working("Changing the page… \(percent)%")
            }
            isPeasified = peasifier.isPeasified
            status = .done(outcome.warning ?? "Done. Click Unpeasify to undo.")
        } catch is CancellationError {
            isPeasified = peasifier.isPeasified
            status = .idle
        } catch {
            isPeasified = peasifier.isPeasified
            status = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
    }

    /// Put the original text back on the page.
    func unpeasify() {
        do {
            try peasifier.unpeasify()
            isPeasified = false
            status = .done("Original page restored")
        } catch {
            isPeasified = false
            status = .failed(error.localizedDescription)
        }
    }

    func statusTapped() {
        if status == .needsAPIKey, APIKeyPrompt.run() {
            status = .idle
        }
    }
}

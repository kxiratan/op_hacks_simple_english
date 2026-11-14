import Foundation

/// Errors raised by the Peasifier itself (browser and AI errors pass through unchanged).
enum PeasifierError: LocalizedError {
    /// The page had no text to rewrite.
    case noText
    /// Nothing on the page was changed. Carries the message to show.
    case nothingChanged(String)

    var errorDescription: String? {
        switch self {
        case .noText:
            return "No text found on this page."
        case .nothingChanged(let message):
            return message.isEmpty ? "The AI returned nothing usable for this page." : message
        }
    }
}

/// Rewrites the text of the front browser tab in place, and puts it back again.
@MainActor
final class Peasifier {
    struct Options {
        let mode: PeasyMode
        let language: TranslateLanguage
        let level: SimplifyLevel
        let apiKey: String
        let model: String
    }

    struct Outcome {
        let replaced: Int
        let total: Int
        /// Set when some parts of the page could not be changed but others were.
        let warning: String?
    }

    /// True once any text on the page has been replaced.
    private(set) var isPeasified = false

    /// The browser whose tab was last peasified; `unpeasify` restores it there.
    private var browser: BrowserBridge.Browser?

    // MARK: - Tuning

    private static let maxBatchCharacters = 3500
    private static let maxBatchSegments = 60
    private static let maxConcurrentBatches = 3
    nonisolated private static let flushInterval: TimeInterval = 0.4
    private static let retryDelayNanoseconds: UInt64 = 3_000_000_000

    // MARK: - Peasify

    /// Rewrites the front browser tab in place. onProgress is called on the main actor with (segments replaced so far, total).
    func peasify(_ options: Options, onProgress: @escaping (Int, Int) -> Void) async throws -> Outcome {
        guard let browser = BrowserBridge.frontBrowser() else { throw BrowserBridgeError.noBrowser }
        self.browser = browser

        let snapshot = try PageScripts.decodeSnapshot(try BrowserBridge.run(PageScripts.collect, in: browser))
        let segments = snapshot.segments
        guard !segments.isEmpty else { throw PeasifierError.noText }

        let total = segments.count
        let batches = Self.makeBatches(segments)
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = PromptBuilder.systemPrompt(mode: options.mode, language: options.language, level: options.level)
        let client = OpenRouterClient(apiKey: options.apiKey, model: options.model)
        let progress = Progress()

        // Runs on the main actor: writes a group of rewritten segments into the page.
        let apply: @MainActor @Sendable ([PageSegment]) throws -> Int = { [weak self] items in
            guard !items.isEmpty else { return 0 }
            let result = try BrowserBridge.run(PageScripts.apply(items), in: browser)
            let reported = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? items.count
            let count = max(0, min(reported, items.count))
            if count > 0 { self?.isPeasified = true }
            progress.replaced += count
            onProgress(progress.replaced, total)
            return count
        }

        var failures: [(index: Int, error: Error)] = []

        try await withThrowingTaskGroup(of: BatchResult.self) { group in
            var next = 0
            func addNext() {
                guard next < batches.count else { return }
                let batch = batches[next]
                next += 1
                group.addTask {
                    try await Peasifier.runBatch(batch, client: client, system: system,
                                                 pageTitle: title.isEmpty ? nil : title, apply: apply)
                }
            }
            for _ in 0..<Self.maxConcurrentBatches { addNext() }
            // A CancellationError from a batch (or the parent task) propagates out here.
            while let result = try await group.next() {
                if let error = result.error { failures.append((result.index, error)) }
                try Task.checkCancellation()
                addNext()
            }
        }

        let replaced = progress.replaced
        if replaced == 0 {
            if let first = failures.min(by: { $0.index < $1.index }) {
                throw PeasifierError.nothingChanged(first.error.localizedDescription)
            }
            throw PeasifierError.nothingChanged("The AI returned nothing usable for this page.")
        }

        let incomplete = !failures.isEmpty || replaced < total
        return Outcome(replaced: replaced, total: total,
                       warning: incomplete ? "Some parts could not be changed." : nil)
    }

    // MARK: - Unpeasify

    /// Restores the original text in the tab that was peasified. Returns the number of pieces restored.
    @discardableResult
    func unpeasify() throws -> Int {
        guard let browser else {
            isPeasified = false
            return 0
        }
        defer { isPeasified = false }
        let result = try BrowserBridge.run(PageScripts.restore, in: browser)
        return Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - Batching

    private struct Batch {
        let index: Int
        let segments: [PageSegment]
    }

    private struct BatchResult {
        let index: Int
        let error: Error?
    }

    /// Running count of replaced segments; only touched on the main actor.
    @MainActor
    private final class Progress {
        var replaced = 0
    }

    /// Splits segments, in page order, into batches bounded by characters and by count.
    /// A single over-long segment becomes its own batch. Nothing is dropped, however long the page.
    private static func makeBatches(_ segments: [PageSegment]) -> [Batch] {
        var batches: [Batch] = []
        var current: [PageSegment] = []
        var characters = 0

        func close() {
            guard !current.isEmpty else { return }
            batches.append(Batch(index: batches.count, segments: current))
            current = []
            characters = 0
        }

        for segment in segments {
            let length = segment.text.count
            if !current.isEmpty,
               characters + length > maxBatchCharacters || current.count >= maxBatchSegments {
                close()
            }
            current.append(segment)
            characters += length
        }
        close()
        return batches
    }

    // MARK: - One batch (runs off the main actor)

    /// Sends one batch to the AI and applies what comes back. Only cancellation throws;
    /// any other failure is returned in the result so the remaining batches carry on.
    nonisolated private static func runBatch(
        _ batch: Batch,
        client: OpenRouterClient,
        system: String,
        pageTitle: String?,
        apply: @escaping @MainActor @Sendable ([PageSegment]) throws -> Int
    ) async throws -> BatchResult {
        var remaining = Set(batch.segments.map(\.id))
        var retried = false

        while true {
            try Task.checkCancellation()
            // On a retry, only ask for the segments that have not been rewritten yet.
            let wanted = batch.segments.filter { remaining.contains($0.id) }
            guard !wanted.isEmpty else { return BatchResult(index: batch.index, error: nil) }

            do {
                try await streamOnce(wanted, client: client, system: system, pageTitle: pageTitle,
                                     remaining: &remaining, apply: apply)
                return BatchResult(index: batch.index, error: nil)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if !retried, isRetryable(error) {
                    retried = true
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                    continue
                }
                return BatchResult(index: batch.index, error: error)
            }
        }
    }

    /// One streamed request. Parsed segments are buffered and written to the page
    /// at most every `flushInterval`, with a final flush when the stream ends.
    nonisolated private static func streamOnce(
        _ segments: [PageSegment],
        client: OpenRouterClient,
        system: String,
        pageTitle: String?,
        remaining: inout Set<Int>,
        apply: @escaping @MainActor @Sendable ([PageSegment]) throws -> Int
    ) async throws {
        var parser = SegmentStreamParser()
        var pending: [PageSegment] = []
        var lastFlush = Date()

        // Keeps segments that belong to this batch, once each, and have some text.
        func accept(_ parsed: [PageSegment], into pending: inout [PageSegment], remaining: inout Set<Int>) {
            for item in parsed {
                guard remaining.contains(item.id),
                      !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                remaining.remove(item.id)
                pending.append(item)
            }
        }

        let user = PromptBuilder.userMessage(for: segments, pageTitle: pageTitle)
        do {
            for try await chunk in client.streamText(system: system, user: user) {
                try Task.checkCancellation()
                accept(parser.feed(chunk), into: &pending, remaining: &remaining)
                if !pending.isEmpty, Date().timeIntervalSince(lastFlush) >= flushInterval {
                    let items = pending
                    pending = []
                    _ = try await apply(items)
                    lastFlush = Date()
                }
            }
        } catch {
            // Keep whatever was fully parsed before the failure, unless we were cancelled.
            if !(error is CancellationError), !Task.isCancelled, !pending.isEmpty {
                let items = pending
                _ = try? await apply(items)
            }
            throw error
        }

        try Task.checkCancellation()
        accept(parser.finish(), into: &pending, remaining: &remaining)
        if !pending.isEmpty {
            let items = pending
            _ = try await apply(items)
        }
    }

    /// Rate limits and busy servers are worth one more try.
    nonisolated private static func isRetryable(_ error: Error) -> Bool {
        guard let aiError = error as? AIError else { return false }
        switch aiError {
        case .rateLimited, .serverBusy: return true
        default: return false
        }
    }
}

import Combine
import Darwin
import Foundation

enum AgentConversationEntryKind: String, Equatable {
    case user
    case assistant

    var displayName: String {
        switch self {
        case .user: return "User"
        case .assistant: return "Agent"
        }
    }
}

struct AgentConversationEntry: Identifiable, Equatable {
    let id: String
    let provider: AgentProvider
    let kind: AgentConversationEntryKind
    let preview: String
    let row: Int
}

/// Parses the small set of stable turn markers exposed by the Claude Code and
/// Codex TUIs. Unknown output is deliberately ignored: a false history marker
/// is more disruptive than an omitted one.
enum AgentConversationParser {
    static func parse(
        provider: AgentProvider,
        screenContents: String,
        totalRows: Int
    ) -> [AgentConversationEntry] {
        let lines = screenContents.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return [] }

        let firstRow = max(0, totalRows - lines.count)
        var result: [AgentConversationEntry] = []
        var current: (kind: AgentConversationEntryKind, row: Int, text: String)?

        for (index, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            if let marker = marker(for: provider, line: line) {
                append(
                    current,
                    provider: provider,
                    into: &result)
                current = marker.text.isEmpty
                    ? (marker.kind, firstRow + index, "")
                    : (marker.kind, firstRow + index, marker.text)
                continue
            }

            guard let existing = current, !existing.text.isEmpty else { continue }
            let content = normalized(line)
            guard !content.isEmpty else { continue }
            if existing.text.count < 240 {
                var updated = existing
                updated.text += " " + content
                updated.text = String(updated.text.prefix(240))
                current = updated
            }
        }

        append(current, provider: provider, into: &result)
        return result
    }

    private static func append(
        _ candidate: (kind: AgentConversationEntryKind, row: Int, text: String)?,
        provider: AgentProvider,
        into result: inout [AgentConversationEntry]
    ) {
        guard let candidate else { return }
        let preview = normalized(candidate.text)
        guard !preview.isEmpty else { return }

        let id = "\(candidate.row):\(candidate.kind.rawValue):\(preview)"
        result.append(.init(
            id: id,
            provider: provider,
            kind: candidate.kind,
            preview: String(preview.prefix(120)),
            row: candidate.row))
    }

    private static func marker(
        for provider: AgentProvider,
        line: String
    ) -> (kind: AgentConversationEntryKind, text: String)? {
        let line = line.trimmingCharacters(in: .whitespaces)

        switch provider {
        case .claude:
            if let text = line.removingPrefix("❯") {
                return (.user, normalized(text))
            }
            if let text = line.removingPrefix(">") {
                return (.user, normalized(text))
            }
            if let text = line.removingPrefix("⏺") {
                return (.assistant, normalized(text))
            }
            if let text = line.removingPrefix("●") {
                return (.assistant, normalized(text))
            }

        case .codex:
            if let text = line.removingPrefix("›") {
                return (.user, normalized(text))
            }
            if let text = line.removingPrefix("•") {
                return (.assistant, normalized(text))
            }
            if let text = line.removingPrefix("◦") {
                return (.assistant, normalized(text))
            }
        }

        return nil
    }

    private static func normalized(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class AgentConversationHistory: ObservableObject {
    @Published private(set) var detection: AgentDetection?
    @Published private(set) var entries: [AgentConversationEntry] = []

    private var lastScreenContents: String?
    private var lastTotalRows: Int?
    private var lastDetection: AgentDetection?

    func refresh(surface: Zashiki.SurfaceView) {
        guard let foregroundPID = surface.surfaceModel?.foregroundPID,
              let processName = ProcessNameResolver.name(for: foregroundPID)
        else {
            clear()
            return
        }

        let screenContents = surface.cachedScreenContents.get()
        let inputLine = surface.cachedInputLineBeforeCursor.get()
        let detection = AgentDetector.detect(.init(
            processName: processName,
            screenContents: screenContents,
            inputLine: inputLine))

        guard let detection else {
            clear()
            return
        }

        self.detection = detection
        guard let scrollbar = surface.scrollbar else {
            entries = []
            lastScreenContents = nil
            lastTotalRows = nil
            return
        }
        let totalRows = Int(scrollbar.total)
        guard detection != lastDetection ||
                screenContents != lastScreenContents ||
                totalRows != lastTotalRows else {
            return
        }

        lastDetection = detection
        lastScreenContents = screenContents
        lastTotalRows = totalRows
        entries = AgentConversationParser.parse(
            provider: detection.provider,
            screenContents: screenContents,
            totalRows: totalRows)
    }

    func clear() {
        detection = nil
        entries = []
        lastScreenContents = nil
        lastTotalRows = nil
        lastDetection = nil
    }
}

enum ProcessNameResolver {
    static func name(for pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}

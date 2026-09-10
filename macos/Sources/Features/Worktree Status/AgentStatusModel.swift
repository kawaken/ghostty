import AppKit
import Foundation

struct SurfaceAgentStatus: Identifiable {
    let id: UUID
    let surface: Zashiki.SurfaceView
    let provider: AgentProvider
    let activity: AgentActivity
    let directory: String?
    let lastUpdatedAt: Date

    var helpText: String {
        let location = directory ?? "Unknown working directory"
        return provider.displayName + "\nStatus: " + activity.displayName + "\nPath: " + location
    }
}

/// Tracks agent detection for the Surfaces currently shown in one terminal
/// window. The view owns the polling lifetime, so hidden panes do not keep
/// reading terminal buffers.
@MainActor
final class AgentStatusModel: ObservableObject {
    /// Whether the Agents side panel is currently shown.
    @Published var isVisible: Bool = false

    @Published private(set) var agents: [SurfaceAgentStatus] = []

    private var history: [UUID: AgentHistory] = [:]

    func open() {
        isVisible = true
    }

    func close() {
        isVisible = false
    }

    func toggle() {
        isVisible.toggle()
    }

    func refresh(surfaces: [Zashiki.SurfaceView], now: Date = Date()) {
        var next: [SurfaceAgentStatus] = []
        var activeIDs: Set<UUID> = []

        for surface in surfaces {
            surface.agentConversationHistory.refresh(surface: surface)
            guard let detection = surface.agentConversationHistory.detection else { continue }

            let screenContents = surface.cachedVisibleContents.get()
            let previous = history[surface.id]
            activeIDs.insert(surface.id)

            let lastUpdatedAt: Date
            if let previous,
               previous.detection == detection,
               previous.screenContents == screenContents {
                lastUpdatedAt = previous.lastUpdatedAt
            } else {
                lastUpdatedAt = now
            }

            history[surface.id] = AgentHistory(
                detection: detection,
                screenContents: screenContents,
                lastUpdatedAt: lastUpdatedAt)
            next.append(.init(
                id: surface.id,
                surface: surface,
                provider: detection.provider,
                activity: detection.activity,
                directory: surface.pwd,
                lastUpdatedAt: lastUpdatedAt))
        }

        history = history.filter { activeIDs.contains($0.key) }
        agents = next.sorted { lhs, rhs in
            lhs.provider.displayName.localizedStandardCompare(rhs.provider.displayName) == .orderedAscending
        }
    }

    func clear() {
        history.removeAll()
        agents = []
    }
}

private struct AgentHistory {
    let detection: AgentDetection
    let screenContents: String
    let lastUpdatedAt: Date
}

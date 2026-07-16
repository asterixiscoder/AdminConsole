import Foundation

struct BrowserNavigationCommandTracker {
    private(set) var lastAppliedCommandID: [UUID: Int] = [:]
    private(set) var pendingCommandID: [UUID: Int] = [:]

    mutating func prune(liveWindowIDs: Set<UUID>) {
        lastAppliedCommandID = lastAppliedCommandID.filter { liveWindowIDs.contains($0.key) }
        pendingCommandID = pendingCommandID.filter { liveWindowIDs.contains($0.key) }
    }

    mutating func shouldAccept(commandID: Int, windowID: UUID) -> Bool {
        let lastApplied = lastAppliedCommandID[windowID] ?? 0
        guard commandID > lastApplied else {
            return false
        }

        lastAppliedCommandID[windowID] = commandID
        return true
    }

    mutating func markPending(commandID: Int, windowID: UUID) {
        pendingCommandID[windowID] = commandID
    }

    mutating func consumePendingCommand(windowID: UUID) -> Int? {
        pendingCommandID.removeValue(forKey: windowID)
    }
}

//
//  MenuBarScanState.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

public enum MenuBarScanScope: Sendable {
    case discovery
    /// Refresh item owners and requested PIDs. Undiscovered owners and expired
    /// empty observations are also probed, so the catalog can grow during moves.
    case knownOwners
    /// Reads only the requested owners, so it never yields a complete inventory.
    case requestedOwners
    /// Reads requested owners and those that own items. Complete only once discovery has read every running owner.
    case itemOwners
    /// Between full walks: reads requested owners, those that own items, and any owner never asked before.
    /// An owner that answered empty is left alone until the next full walk, unless it is requested.
    case settledOwners
}

/// Fair scheduling and per-process retention for a budgeted AX inventory.
/// A successful empty answer removes items; a timeout, a failed read or an
/// unvisited owner does not.
public struct MenuBarScanState<Observation: Sendable>: Sendable {
    public struct Pass: Sendable {
        public let generation: UInt64
        public let owners: [Int32]
    }

    private var generation: UInt64 = 0
    private var queue: [Int32] = []
    private var owners: [Int32] = []
    private var retained: [Int32: [Observation]] = [:]
    private var attempted: [Int32: UInt64] = [:]
    private var observed: [Int32: UInt64] = [:]
    private var observedAt: [Int32: ContinuousClock.Instant] = [:]
    private var failedReads: [Int32: Int] = [:]

    /// Consecutive failed reads after which an owner's items count as gone.
    /// An owner that quit its bar while its accessibility server broke would
    /// otherwise hold stale items, and every pass incomplete, indefinitely.
    public static var failedReadsBeforeDeparture: Int {
        3
    }

    public init() {}

    public mutating func begin(
        owners: [Int32],
        priorityOwners: Set<Int32>,
        scope: MenuBarScanScope = .discovery,
        now: ContinuousClock.Instant = .now
    ) -> Pass {
        generation &+= 1
        let running = Set(owners)
        self.owners = owners
        retained = retained.filter { running.contains($0.key) }
        attempted = attempted.filter { running.contains($0.key) }
        observed = observed.filter { running.contains($0.key) }
        observedAt = observedAt.filter { running.contains($0.key) }
        failedReads = failedReads.filter { running.contains($0.key) }
        queue.removeAll { !running.contains($0) }
        let queued = Set(queue)
        // Ahead of the rotation: a process that just launched is where a new
        // item comes from, and at the back a truncated walk never reaches it.
        queue.insert(contentsOf: owners.filter { !queued.contains($0) }, at: 0)
        // Empty answers are only a short-lived discovery hint. Known item
        // owners never receive this exemption from fresh geometry collection.
        let scheduled = owners.filter { priorityOwners.contains($0) }
            + queue.filter { !priorityOwners.contains($0) }
        return Pass(
            generation: generation,
            owners: scheduled.filter { owner in
                switch scope {
                case .discovery:
                    true
                case .requestedOwners:
                    priorityOwners.contains(owner)
                case .itemOwners:
                    priorityOwners.contains(owner) || retained[owner]?.isEmpty == false
                case .settledOwners:
                    priorityOwners.contains(owner) || retained[owner]?.isEmpty != true
                case .knownOwners:
                    priorityOwners.contains(owner) || retained[owner]?.isEmpty != true
                        || attempted[owner] != observed[owner]
                        || observedAt[owner].map { now - $0 >= .seconds(5) } != false
                }
            }
        )
    }

    public mutating func didAttempt(owner: Int32, generation: UInt64) {
        attempted[owner] = generation
        queue.removeAll { $0 == owner }
        queue.append(owner)
    }

    public mutating func record(
        _ items: [Observation],
        owner: Int32,
        generation: UInt64,
        at instant: ContinuousClock.Instant = .now
    ) {
        guard attempted[owner] == generation, owners.contains(owner) else { return }
        retained[owner] = items
        failedReads[owner] = nil
        observed[owner] = generation
        observedAt[owner] = instant
    }

    /// Records a read of owner that failed instead of answering.
    ///
    /// A failure proves nothing about the owner's items, so one that had items
    /// keeps them, unobserved: this pass is neither complete nor fresh for it.
    /// An owner with nothing retained records an empty answer, since processes
    /// without an accessibility server fail every read.
    ///
    /// - Returns: Whether the owner's previous items were kept.
    @discardableResult
    public mutating func recordFailedRead(
        owner: Int32,
        generation: UInt64,
        at instant: ContinuousClock.Instant = .now
    ) -> Bool {
        guard attempted[owner] == generation, owners.contains(owner) else { return false }
        let streak = (failedReads[owner] ?? 0) + 1
        if retained[owner]?.isEmpty == false, streak < Self.failedReadsBeforeDeparture {
            failedReads[owner] = streak
            return true
        }
        record([], owner: owner, generation: generation, at: instant)
        return false
    }

    public var observations: [Observation] {
        owners.flatMap { retained[$0] ?? [] }
    }

    /// Only this pass's answers may verify a position write. Retained geometry
    /// belongs in the editor, not in a move-success predicate.
    public func freshObservations(generation: UInt64) -> [Observation] {
        owners.filter { observed[$0] == generation }.flatMap { retained[$0] ?? [] }
    }

    /// A rotating scan may skip previously empty owners, but never use stale
    /// item geometry or reconcile before every running owner was discovered.
    /// excused owners count as covered; their items are absent from freshObservations.
    public func hasFreshKnownInventory(generation: UInt64, excusing excused: Set<Int32> = []) -> Bool {
        owners.allSatisfy { owner in
            if excused.contains(owner) {
                return true
            }
            guard let items = retained[owner] else { return false }
            return items.isEmpty || observed[owner] == generation
        }
    }

    /// Every owner selected for move geometry must answer in this pass,
    /// including explicitly requested owners that were previously empty.
    public func isComplete(_ pass: Pass, excusing excused: Set<Int32> = []) -> Bool {
        pass.generation == generation && pass.owners.allSatisfy {
            observed[$0] == pass.generation || excused.contains($0)
        }
    }

    public func isComplete(generation: UInt64) -> Bool {
        owners.allSatisfy { observed[$0] == generation }
    }
}

//
//  MenuBarScanStateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("Budgeted menu bar discovery")
struct MenuBarScanStateTests {
    @Test("Repeated short scans reach every owner and always visit controls first")
    func truncatedScansMakeProgress() {
        var state = MenuBarScanState<String>()
        let owners = Array(Int32(1) ... 199)
        var visited = Set<Int32>()
        for _ in 0 ..< 3 {
            let pass = state.begin(owners: owners, priorityOwners: [198, 199])
            #expect(Array(pass.owners.prefix(2)) == [198, 199])
            for owner in pass.owners.prefix(100) {
                state.didAttempt(owner: owner, generation: pass.generation)
                state.record(["item-\(owner)"], owner: owner, generation: pass.generation)
                visited.insert(owner)
            }
        }
        #expect(visited == Set(owners))
        #expect(state.observations.count == 199)
    }

    @Test("A process that launched since the last scan is asked before the rotation")
    func newOwnerIsNotLeftBehindATruncatedScan() {
        var state = MenuBarScanState<String>()
        let owners = Array(Int32(1) ... 100)
        let first = state.begin(owners: owners, priorityOwners: [100])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
            state.record([], owner: owner, generation: first.generation)
        }
        let second = state.begin(owners: owners + [500], priorityOwners: [100])
        #expect(Array(second.owners.prefix(2)) == [100, 500])
    }

    @Test("An unvisited owner survives, but a successful empty answer removes its items")
    func absenceRequiresAnObservation() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
            state.record(["item-\(owner)"], owner: owner, generation: first.generation)
        }
        let second = state.begin(owners: [1, 2], priorityOwners: [])
        state.didAttempt(owner: 1, generation: second.generation)
        state.record([], owner: 1, generation: second.generation)
        #expect(state.observations == ["item-2"])
        #expect(state.freshObservations(generation: second.generation).isEmpty)
        #expect(!state.isComplete(generation: second.generation))
        _ = state.begin(owners: [1], priorityOwners: [])
        #expect(state.observations.isEmpty)
    }

    @Test("Reconciliation needs discovery coverage and fresh geometry for every known item")
    func reconciliationDoesNotWaitForEmptyOwnersEveryPass() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        state.didAttempt(owner: 1, generation: first.generation)
        state.record(["control"], owner: 1, generation: first.generation)
        #expect(!state.hasFreshKnownInventory(generation: first.generation))
        state.didAttempt(owner: 2, generation: first.generation)
        state.record([], owner: 2, generation: first.generation)

        let second = state.begin(owners: [1, 2], priorityOwners: [])
        #expect(!state.hasFreshKnownInventory(generation: second.generation))
        state.didAttempt(owner: 1, generation: second.generation)
        state.record(["control moved"], owner: 1, generation: second.generation)
        #expect(!state.isComplete(generation: second.generation))
        #expect(state.hasFreshKnownInventory(generation: second.generation))

        let third = state.begin(owners: [1, 2, 3], priorityOwners: [])
        #expect(!state.hasFreshKnownInventory(generation: third.generation))
    }

    @Test("A late pre-move answer cannot overwrite a newer observation")
    func staleAnswersAreRejected() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: first.generation)
        let second = state.begin(owners: [1], priorityOwners: [])
        state.didAttempt(owner: 1, generation: second.generation)
        state.record(["new position"], owner: 1, generation: second.generation)
        state.record(["old position"], owner: 1, generation: first.generation)
        #expect(state.observations == ["new position"])
        #expect(state.isComplete(generation: second.generation))
    }

    @Test("A failed read keeps an owner's items and leaves the pass incomplete and stale")
    func failedReadIsNotAnEmptyAnswer() {
        var state = MenuBarScanState<String>()
        let first = state.begin(owners: [1, 2], priorityOwners: [])
        for owner in first.owners {
            state.didAttempt(owner: owner, generation: first.generation)
        }
        state.record(["wifi"], owner: 1, generation: first.generation)
        state.record([], owner: 2, generation: first.generation)

        let second = state.begin(owners: [1, 2], priorityOwners: [])
        for owner in second.owners {
            state.didAttempt(owner: owner, generation: second.generation)
        }
        let kept = state.recordFailedRead(owner: 1, generation: second.generation)
        #expect(kept)
        state.record([], owner: 2, generation: second.generation)
        #expect(state.observations == ["wifi"])
        #expect(!state.isComplete(generation: second.generation))
        #expect(!state.hasFreshKnownInventory(generation: second.generation))
        #expect(state.freshObservations(generation: second.generation).isEmpty)
    }

    @Test("An owner with nothing retained reads a failure as empty, so daemons do not stall every pass")
    func failedReadOfEmptyOwnerCompletes() {
        var state = MenuBarScanState<String>()
        let pass = state.begin(owners: [7], priorityOwners: [])
        state.didAttempt(owner: 7, generation: pass.generation)
        let kept = state.recordFailedRead(owner: 7, generation: pass.generation)
        #expect(!kept)
        #expect(state.isComplete(generation: pass.generation))
    }

    @Test("Repeated failed reads eventually count the items as gone, and an answer resets the streak")
    func failedReadsExpire() {
        var state = MenuBarScanState<String>()
        func nextPass() -> UInt64 {
            let pass = state.begin(owners: [1], priorityOwners: [])
            state.didAttempt(owner: 1, generation: pass.generation)
            return pass.generation
        }
        var generation = nextPass()
        state.record(["clock"], owner: 1, generation: generation)
        generation = nextPass()
        let keptOnce = state.recordFailedRead(owner: 1, generation: generation)
        #expect(keptOnce)
        generation = nextPass()
        state.record(["clock"], owner: 1, generation: generation)
        for _ in 1 ..< MenuBarScanState<String>.failedReadsBeforeDeparture {
            generation = nextPass()
            let kept = state.recordFailedRead(owner: 1, generation: generation)
            #expect(kept)
        }
        #expect(state.observations == ["clock"])
        generation = nextPass()
        let keptAtLimit = state.recordFailedRead(owner: 1, generation: generation)
        #expect(!keptAtLimit)
        #expect(state.observations.isEmpty)
    }
}

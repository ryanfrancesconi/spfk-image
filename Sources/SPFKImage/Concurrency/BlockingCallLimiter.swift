// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-image

import Foundation

/// Admits a bounded number of blocking framework calls at once, process-wide.
///
/// Core Image's Auto analysis (Vision) and ImageIO's AV1 encode block their thread on Dispatch work that
/// needs a thread of its own; with every cooperative thread held that way, none of them finishes. On 10
/// active cores, ten concurrent calls hung with none complete, and nine finished.
actor BlockingCallLimiter {
    static let shared = BlockingCallLimiter(width: max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

    let width: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(width: Int) {
        self.width = max(1, width)
    }

    /// Runs `body` on the caller's thread once a slot is free.
    nonisolated func run<T>(_ body: () throws -> T) async rethrows -> T {
        await acquire()

        do {
            let result = try body()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }

    private func acquire() async {
        guard running >= width else {
            running += 1
            return
        }

        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the slot straight to the oldest waiter, so `running` counts it without a gap.
    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

import Foundation

#if os(iOS)
import UIKit
#endif

@MainActor
final class IdleTimerManager {
    static let shared = IdleTimerManager()

    private var counter = 0

    func preventSleep() {
        counter += 1
        update()
    }

    func allowSleep() {
        counter = max(0, counter - 1)
        update()
    }

    private func update() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = counter > 0
        #endif
    }
}

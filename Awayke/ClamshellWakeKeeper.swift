import Foundation
import IOKit

private let setClamshellSleepStateSelector: UInt32 = 12

enum ClamshellWakeError: LocalizedError {
    case rootDomainUnavailable
    case connectionFailed(code: kern_return_t)
    case selectorFailed(code: IOReturn)

    var errorDescription: String? {
        switch self {
        case .rootDomainUnavailable:
            return "Couldn't find the macOS power-management service."
        case .connectionFailed(let code):
            return "Couldn't connect to macOS power management (IOKit \(code))."
        case .selectorFailed(let code):
            return "macOS rejected the lid-close wake override (IOKit \(code))."
        }
    }
}

final class ClamshellWakeKeeper: ClamshellSleepControlling {
    private let maintenanceInterval: TimeInterval = 1
    private var maintenanceTimer: Timer?

    func prevent() -> Result<Void, Error> {
        guard maintenanceTimer == nil else { return .success(()) }

        switch setSleepDisabled(true) {
        case .success:
            let timer = Timer(timeInterval: maintenanceInterval, repeats: true) {
                [weak self] _ in
                _ = self?.setSleepDisabled(true)
            }
            RunLoop.main.add(timer, forMode: .common)
            maintenanceTimer = timer
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func allow() -> Result<Void, Error> {
        switch setSleepDisabled(false) {
        case .success:
            maintenanceTimer?.invalidate()
            maintenanceTimer = nil
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    deinit {
        _ = allow()
    }

    private func setSleepDisabled(_ disabled: Bool) -> Result<Void, Error> {
        let rootDomain = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard rootDomain != IO_OBJECT_NULL else {
            return .failure(ClamshellWakeError.rootDomainUnavailable)
        }
        defer { IOObjectRelease(rootDomain) }

        var connection = io_connect_t(IO_OBJECT_NULL)
        let openResult = IOServiceOpen(
            rootDomain,
            mach_task_self_,
            0,
            &connection
        )
        guard openResult == KERN_SUCCESS else {
            return .failure(ClamshellWakeError.connectionFailed(code: openResult))
        }
        defer { IOServiceClose(connection) }

        var input: UInt64 = disabled ? 1 : 0
        var outputCount: UInt32 = 0
        let selectorResult = IOConnectCallScalarMethod(
            connection,
            setClamshellSleepStateSelector,
            &input,
            1,
            nil,
            &outputCount
        )
        guard selectorResult == kIOReturnSuccess else {
            return .failure(ClamshellWakeError.selectorFailed(code: selectorResult))
        }
        return .success(())
    }
}

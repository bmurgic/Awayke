enum StatusClickAction: Equatable {
    case singleClick
    case doubleClick
}

enum WakeMode: Equatable {
    case off
    case openLid
    case lidClosed

    var isActive: Bool {
        self != .off
    }

    func target(after action: StatusClickAction) -> WakeMode {
        switch (self, action) {
        case (.off, .singleClick):
            return .openLid
        case (.openLid, .singleClick), (.lidClosed, .singleClick):
            return .off
        case (.off, .doubleClick), (.openLid, .doubleClick):
            return .lidClosed
        case (.lidClosed, .doubleClick):
            return .off
        }
    }
}

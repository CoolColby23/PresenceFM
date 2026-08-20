import SwiftUI

extension ServiceStatus {
    var tintColor: Color {
        switch self {
        case .connected: BrandColors.success
        case .connecting, .awaitingPermission, .authorizationExpired: BrandColors.warning
        case .failed: BrandColors.error
        case .disabled, .inactive, .offline: BrandColors.neutral
        }
    }

    var isActionable: Bool {
        switch self {
        case .awaitingPermission, .authorizationExpired, .offline, .failed: true
        default: false
        }
    }
}

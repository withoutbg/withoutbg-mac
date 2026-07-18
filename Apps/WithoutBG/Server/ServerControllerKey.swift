import SwiftUI

/// Custom environment key so `ServerController` (an actor, not Observable)
/// can be injected into SwiftUI views.
struct ServerControllerKey: EnvironmentKey {
    static let defaultValue: ServerController? = nil
}

extension EnvironmentValues {
    var serverController: ServerController? {
        get { self[ServerControllerKey.self] }
        set { self[ServerControllerKey.self] = newValue }
    }
}

import Foundation
import Vapor
import WithoutBGCore

/// Owns and manages the lifecycle of the embedded Vapor HTTP server.
actor ServerController {
    private let status: ServerStatus
    private let activity: RecentActivity
    private let coordinator: SharedInferenceCoordinator
    private var app: Application?

    init(
        status: ServerStatus,
        activity: RecentActivity,
        coordinator: SharedInferenceCoordinator
    ) {
        self.status = status
        self.activity = activity
        self.coordinator = coordinator
    }

    func start(port: Int) async {
        if app != nil { await stop() }

        do {
            let vaporApp = try await Application.make(.development)

            vaporApp.http.server.configuration.hostname = "127.0.0.1"
            vaporApp.http.server.configuration.port = port
            vaporApp.logger.logLevel = .warning
            vaporApp.routes.defaultMaxBodySize = "25mb"

            registerRoutes(
                on: vaporApp,
                coordinator: coordinator,
                status: status,
                activity: activity
            )

            try await vaporApp.server.start(address: .hostname("127.0.0.1", port: port))

            app = vaporApp

            await MainActor.run {
                status.isRunning = true
                status.port = port
                status.lastError = nil
                status.runningSince = Date()
            }
        } catch {
            await MainActor.run {
                status.isRunning = false
                status.lastError = error.localizedDescription
                status.runningSince = nil
            }
        }
    }

    func stop() async {
        guard let vaporApp = app else { return }
        app = nil
        try? await vaporApp.server.shutdown()
        try? await vaporApp.asyncShutdown()
        await MainActor.run {
            status.isRunning = false
            status.runningSince = nil
        }
    }

    func restart(port: Int) async {
        await stop()
        await start(port: port)
    }
}

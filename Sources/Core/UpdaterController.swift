import Combine
import Sparkle

@MainActor
@Observable
final class UpdaterController {
    private let sparkleController: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?

    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get { sparkleController.updater.automaticallyChecksForUpdates }
        set { sparkleController.updater.automaticallyChecksForUpdates = newValue }
    }

    init() {
        sparkleController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        canCheckForUpdates = sparkleController.updater.canCheckForUpdates

        cancellable = sparkleController.updater
            .publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                Task { @MainActor in
                    self?.canCheckForUpdates = value
                }
            }
    }

    func checkForUpdates() {
        sparkleController.checkForUpdates(nil)
    }
}

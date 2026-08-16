import Foundation

nonisolated enum TaskRepositoryError: LocalizedError, Sendable {
    case taskNotFound

    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            "The task no longer exists."
        }
    }
}

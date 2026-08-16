import Foundation

nonisolated struct TaskSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let createdAt: Date
    let isCompleted: Bool
}

// Small pieces more than one screen needs: the drag payload the workout list
// moves rows with, the red delete button, the share sheet, and a couple of
// conveniences that are too small to live anywhere of their own.

import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension Notification.Name {
    static let modelDataDidChange = Notification.Name("ModelDataDidChange")
}
// Transferable payload and UTType for drag/drop
struct WorkoutDragPayload: Transferable, Hashable, Codable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .workoutDragPayload)
    }
}

// A type identifier is a constant, and `transferRepresentation` — which is
// where this one is read — is not on the main actor.
nonisolated extension UTType {
    static let workoutDragPayload = UTType.data
}

// Reusable red delete circle button
struct DeleteCircleButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.red).frame(width: 28, height: 28)
                Image(systemName: "minus")
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete")
    }
}

// Helper to get exercise name by id
extension Collection where Element == ExerciseDef {
    func name(for id: UUID) -> String { first(where: { $0.id == id })?.name ?? "Exercise" }
}
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: URL { self }
}

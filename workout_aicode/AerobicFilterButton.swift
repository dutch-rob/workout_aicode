import SwiftUI

/// The "AE" button that sits beside the body and picks out aerobic exercises.
///
/// It looks like a muscle-group button and behaves like one, but it is not a
/// muscle group — see `ExerciseKind`. Selecting it clears any muscle filter and
/// vice versa: an exercise is one kind or the other, so offering both at once
/// would only ever produce an empty list.
struct AerobicFilterButton: View {
    @Binding var isOn: Bool
    /// Vertical in the narrow strip between the two figures, horizontal in the
    /// button grid where there is room for a normal capsule.
    var rotated: Bool = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text("AE")
                .font(.caption)
                .bold()
                .rotationEffect(.degrees(rotated ? -90 : 0))
                .fixedSize()
                .frame(width: rotated ? 18 : nil, height: rotated ? 30 : nil)
                .frame(maxWidth: rotated ? nil : .infinity)
                .padding(.vertical, rotated ? 6 : 5)
                .background(Capsule().fill(isOn ? Color.blue
                                                : Color.secondary.opacity(0.15)))
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aerobic exercises")
    }
}

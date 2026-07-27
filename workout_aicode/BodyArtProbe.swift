#if DEBUG
import SwiftUI

/// Throwaway screen for checking that each muscle anchor lands on the right
/// part of the artwork. Reached with -SRWScreen art. Cycles the selection so
/// every highlight can be seen in one screenshot.
struct BodyArtProbe: View {
    @State private var index = 0
    private let groups = MuscleGroup.displayOrder

    var body: some View {
        VStack(spacing: 6) {
            MuscleBodyPicker(selection: .constant(groups[index]))
            Text("highlighted: \(groups[index].label)").font(.footnote).bold()
            Button("next") { index = (index + 1) % groups.count }
        }
        .padding(8)
    }
}
#endif

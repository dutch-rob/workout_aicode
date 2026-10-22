import SwiftUI
import SwiftData

/// The one question the app cannot answer for itself.
///
/// Weights used to be bare numbers. Everything logged before this version is
/// therefore a number whose unit only the user knows, and getting it wrong
/// rescales a training history by a factor of 2.2 — silently, because every
/// number would still look perfectly ordinary.
///
/// So it is asked once, plainly, with NO default: a pre-selected answer to a
/// question like this is a guess wearing a tick. Until it is answered the
/// weights are not shown at all, because there is nothing honest to show.
struct WeightUnitPrompt: View {
    @Environment(\.modelContext) private var context
    let onAnswered: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "scalemass")
                .font(.system(size: 46))
                .foregroundStyle(.blue)

            Text("Kilograms or pounds?")
                .font(.title2).bold()

            Text("SetsRepsWheels now knows which is which, so it can convert between them and work out what you lift on machines that take weight off you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("The weights you have logged so far — what were they in?")
                .font(.subheadline).bold()
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                ForEach(WeightUnit.allCases) { unit in
                    Button {
                        WeightHistory.adopt(unit, in: context)
                        onAnswered()
                    } label: {
                        Text(unit == .kilograms ? "Kilograms (kg)" : "Pounds (lb)")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }

            Text("Your numbers do not change — 130 stays 130. This only says what they mean. You can switch units afterwards in Settings and everything is converted.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .interactiveDismissDisabled()
    }
}

import SwiftUI

struct InfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("You can log your sets and reps conveniently with this app:")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("•    Define your own exercises by number of sets, lower and upper weight limit and weight increment.")
                    Text("•    Define your own workouts by ordering your exercises")
                    Text("•    Log your workouts in a one screen per exercise for all sets using the ‘picker wheel’ that defaults to the previously logged numbers")
                    Text("•    If the machine for your next workout is in use, swipe to the left for the next exercise, or swipe to the right for the last exercise that you have not logged yet")
                    Text("•    Export your logs in a file that you can easily ready into a spreadsheet")
                    Text("•    There is also a screen to view your logs in detail")
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("The app is free and open source:")
                    Link("https://github.com/dutch-rob/workout_aicode", destination: URL(string: "https://github.com/dutch-rob/workout_aicode")!)
                }
                .font(.subheadline)
            }
            .padding()
        }
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
        .textSelection(.enabled)
    }
}

#Preview {
    NavigationStack {
        InfoView()
    }
}

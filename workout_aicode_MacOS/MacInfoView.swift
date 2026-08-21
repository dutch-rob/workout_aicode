import SwiftUI

struct MacInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("SetsRepsWheels on the Mac")
                    .font(.title2).bold()

                Text("This is the desk half of the app. Define your workouts and exercises here with a keyboard, and read back what you have done; the logging itself happens on your iPhone and Apple Watch, which are the things you take to a gym.")

                Text("Your data lives in your iCloud account, so what you define here appears on your iPhone and what you log there appears here. Unlike the iPhone app, which keeps to itself until you say otherwise, this Mac app shares by default — a Mac that kept its workouts to itself could never get them to the device you actually train with.")

                Text("Nothing is sent anywhere else, and there is no account beyond your own iCloud one.")
                    .foregroundStyle(.secondary)

                Divider()
                Text("The full guide is on the iPhone, under info.")
                    .font(.footnote).foregroundStyle(.secondary)
                BuildStampView()
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(28)
        }
        .navigationTitle("Info")
    }
}

/// The Mac's own build stamp — same reasoning as the phone's and the Watch's.
struct BuildStampView: View {
    var body: some View {
        Text(summary).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
    }

    private var summary: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

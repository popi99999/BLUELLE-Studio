import SwiftUI

@main
struct BluelleStudioApp: App {
    @StateObject private var library = LibraryModel()
    var body: some Scene {
        WindowGroup {
            StudioView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(StudioTheme.accent)
        }
    }
}

enum StudioTheme {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.065)
    static let surface = Color(red: 0.10, green: 0.115, blue: 0.11)
    static let accent = Color(red: 0.80, green: 0.91, blue: 0.66)
    static let ink = Color(red: 0.93, green: 0.93, blue: 0.88)
}

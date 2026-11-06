import SwiftUI

@main
struct TouchTestApp: App {
    var body: some Scene {
        WindowGroup {
            NativeSuiteView()
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .preferredColorScheme(.dark)
        }
    }
}

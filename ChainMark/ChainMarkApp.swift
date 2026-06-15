import SwiftUI

@main
struct ChainMarkApp: App {
    @StateObject private var cameraViewModel = CameraViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraViewModel)
        }
    }
}
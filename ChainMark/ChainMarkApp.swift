import SwiftUI

@main
struct ChainMarkApp: App {
    @StateObject private var cameraViewModel = CameraViewModel()
    
    var body: some Scene {
        WindowGroup {
            TabView {
                // Tab 1: Camera / Capture
                ContentView()
                    .tabItem {
                        Label("Camera", systemImage: "camera.fill")
                    }
                
                // Tab 2: Evidence Timeline
                TimelineView()
                    .tabItem {
                        Label("Evidence", systemImage: "list.bullet.clipboard.fill")
                    }
            }
            .environmentObject(cameraViewModel)
            .preferredColorScheme(.dark)
            .accentColor(.yellow)
        }
    }
}
import SwiftUI

@main
struct ChainMarkApp: App {
    @StateObject private var cameraViewModel = CameraViewModel()
    
    init() {
        // Premium appearance defaults
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: UIColor.white
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .foregroundColor: UIColor.white
        ]
        UITabBar.appearance().barStyle = .black
        UITabBar.appearance().isTranslucent = true
        UITabBar.appearance().backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
    }
    
    var body: some Scene {
        WindowGroup {
            TabView {
                // Tab 1: Camera / Capture
                ContentView()
                    .tabItem {
                        Label("Camera", systemImage: "camera.fill")
                    }
                    .tag(0)
                
                // Tab 2: Evidence Timeline
                TimelineView()
                    .tabItem {
                        Label("Evidence", systemImage: "list.bullet.clipboard.fill")
                    }
                    .tag(1)
            }
            .environmentObject(cameraViewModel)
            .preferredColorScheme(.dark)
            .accentColor(AppColors.accent)
        }
    }
}
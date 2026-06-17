import SwiftUI
import AVFoundation

/// UIViewRepresentable wrapper for AVPlayerLayer, enabling video playback in SwiftUI
struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    @Binding var isPlaying: Bool
    
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView(player: player)
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
    
    /// Simple UIView that hosts an AVPlayerLayer
    class PlayerUIView: UIView {
        let player: AVPlayer
        
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }
        
        var playerLayer: AVPlayerLayer {
            guard let layer = layer as? AVPlayerLayer else {
                fatalError("Expected AVPlayerLayer")
            }
            return layer
        }
        
        init(player: AVPlayer) {
            self.player = player
            super.init(frame: .zero)
            playerLayer.player = player
            backgroundColor = UIColor.black
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
import SwiftUI
import AVFoundation

/// UIKit-based UIViewRepresentable to display the AVCaptureSession video preview
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraViewModel: CameraViewModel
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = cameraViewModel.captureSession
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        
        // Set initial orientation
        view.videoPreviewLayer.connection?.videoOrientation = .portrait
        
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = cameraViewModel.captureSession
    }
    
    /// A simple UIView subclass that uses AVCaptureVideoPreviewLayer as its backing layer
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("Expected AVCaptureVideoPreviewLayer")
            }
            return layer
        }
    }
}

#if DEBUG
struct CameraPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        CameraPreviewView(cameraViewModel: CameraViewModel())
            .aspectRatio(3/4, contentMode: .fit)
            .border(Color.white, width: 1)
    }
}
#endif
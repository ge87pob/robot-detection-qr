//
//  ContentView.swift
//  robot-qr-detection
//

import SwiftUI

struct ContentView: View {
    @State private var cameraManager = CameraManager()
    
    var body: some View {
        ZStack {
            switch cameraManager.permissionStatus {
            case .unknown:
                PermissionRequestView(onRequest: cameraManager.requestPermission)
                
            case .denied:
                PermissionDeniedView()
                
            case .granted:
                ScannerView(cameraManager: cameraManager)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if cameraManager.permissionStatus == .granted {
                cameraManager.setupSession()
                cameraManager.startSession()
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
}

// MARK: - Scanner View (main camera + overlay)
struct ScannerView: View {
    var cameraManager: CameraManager
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // camera feed
                CameraPreviewView(session: cameraManager.session)
                
                // bounding box overlay
                if let qr = cameraManager.detectedQR {
                    BoundingBoxOverlay(
                        boundingBox: qr.boundingBox,
                        viewSize: geo.size
                    )
                }
                
                // status banner
                VStack {
                    StatusBanner(robotDetected: cameraManager.robotDetected)
                        .padding(.top, 60)
                    Spacer()
                }
            }
        }
        .onAppear {
            cameraManager.setupSession()
            cameraManager.startSession()
        }
    }
}

// MARK: - Status Banner
struct StatusBanner: View {
    let robotDetected: Bool
    
    var body: some View {
        Text(robotDetected ? "Robot R1 detected" : "No robot marker detected")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(robotDetected ? Color.green : Color.gray)
            )
            .animation(.easeInOut(duration: 0.2), value: robotDetected)
    }
}

// MARK: - Bounding Box Overlay
struct BoundingBoxOverlay: View {
    let boundingBox: CGRect
    let viewSize: CGSize
    
    var body: some View {
        let rect = convertBoundingBox(boundingBox, to: viewSize)
        
        ZStack(alignment: .topLeading) {
            // green box
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green, lineWidth: 3)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            
            // label
            Text("Robot R1")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .position(x: rect.minX + 50, y: rect.minY - 15)
        }
    }
    
    // Vision coords are normalized (0-1), origin bottom-left
    // Convert to screen coords with origin top-left, with some padding
    private func convertBoundingBox(_ box: CGRect, to size: CGSize) -> CGRect {
        let padding: CGFloat = 0.2  // 20% larger on each side
        let x = box.minX * size.width
        let y = (1 - box.maxY) * size.height  // flip Y
        let width = box.width * size.width
        let height = box.height * size.height
        
        // expand the box by padding amount
        let padX = width * padding
        let padY = height * padding
        return CGRect(
            x: x - padX,
            y: y - padY,
            width: width + padX * 2,
            height: height + padY * 2
        )
    }
}

// MARK: - Permission Views
struct PermissionRequestView: View {
    let onRequest: () -> Void
    
    var body: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 24) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.8))
                
                Text("Camera Access Required")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                
                Text("This app needs camera access to detect robot QR markers.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button(action: onRequest) {
                    Text("Enable Camera")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 24) {
                Image(systemName: "camera.badge.exclamationmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                
                Text("Camera Access Denied")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                
                Text("Please enable camera access in Settings to use this app.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button(action: openSettings) {
                    Text("Open Settings")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
    }
    
    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

#Preview {
    ContentView()
}

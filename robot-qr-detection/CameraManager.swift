//
//  CameraManager.swift
//  robot-qr-detection
//

import AVFoundation
import Vision
import SwiftUI

// tracks camera permission state
enum CameraPermission: Sendable {
    case unknown
    case granted
    case denied
}

// holds detected QR info
struct DetectedQR: Equatable, Sendable {
    let payload: String
    let boundingBox: CGRect  // normalized coords (0-1)
}

@MainActor
@Observable
final class CameraManager: NSObject {
    var permissionStatus: CameraPermission = .unknown
    var robotDetected: Bool = false
    var detectedQR: DetectedQR?
    
    // how many frames without detection before we clear the box
    private let persistenceFrames = 5
    private var framesWithoutDetection = 0
    
    // AVFoundation stuff needs to be nonisolated
    nonisolated let session = AVCaptureSession()
    private nonisolated let videoOutput = AVCaptureVideoDataOutput()
    private nonisolated let processingQueue = DispatchQueue(label: "qr.processing", qos: .userInitiated)
    
    private var isSessionConfigured = false
    
    override nonisolated init() {
        super.init()
        Task { @MainActor in
            self.checkPermission()
        }
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionStatus = .granted
        case .denied, .restricted:
            permissionStatus = .denied
        case .notDetermined:
            permissionStatus = .unknown
        @unknown default:
            permissionStatus = .unknown
        }
    }
    
    nonisolated func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.permissionStatus = granted ? .granted : .denied
                if granted {
                    self.setupSession()
                }
            }
        }
    }
    
    func setupSession() {
        guard !isSessionConfigured else { return }
        
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // video output for frame processing
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        session.commitConfiguration()
        isSessionConfigured = true
    }
    
    func startSession() {
        guard isSessionConfigured, !session.isRunning else { return }
        processingQueue.async {
            self.session.startRunning()
        }
    }
    
    func stopSession() {
        guard session.isRunning else { return }
        processingQueue.async {
            self.session.stopRunning()
        }
    }
}

// MARK: - Frame processing + QR detection
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self else { return }
            guard error == nil,
                  let results = request.results as? [VNBarcodeObservation] else {
                self.updateDetection(nil)
                return
            }
            
            // look for our robot QR
            let robotQR = results.first { barcode in
                barcode.symbology == .qr &&
                barcode.payloadStringValue == "ROBOT_R1"
            }
            
            if let qr = robotQR {
                let detected = DetectedQR(
                    payload: qr.payloadStringValue ?? "",
                    boundingBox: qr.boundingBox
                )
                self.updateDetection(detected)
            } else {
                self.updateDetection(nil)
            }
        }
        
        // only look for QR codes
        request.symbologies = [.qr]
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        try? handler.perform([request])
    }
    
    private nonisolated func updateDetection(_ qr: DetectedQR?) {
        Task { @MainActor in
            if let qr = qr {
                // detected - reset counter and update position
                self.framesWithoutDetection = 0
                self.detectedQR = qr
                self.robotDetected = true
            } else {
                // not detected this frame
                self.framesWithoutDetection += 1
                
                // only clear after N consecutive frames without detection
                if self.framesWithoutDetection >= self.persistenceFrames {
                    self.detectedQR = nil
                    self.robotDetected = false
                }
                // otherwise keep the old bounding box in place
            }
        }
    }
}

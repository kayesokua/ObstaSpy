//
//  CameraViewController.swift
//  DepthDetection
//
//  Created by Kaye S. on 2023/02/26
//  Copyright © 2023 Kayescaping. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import VideoToolbox

@available(iOS 11.1, *)
class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    @IBOutlet weak var cameraView: UIView!
    
    let session: AVCaptureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInLiDARDepthCamera],
        mediaType: .video,
        position: .back)
    
    private let sessionQueue = DispatchQueue(label: "SessionQueue", attributes: [], autoreleaseFrequency: .workItem)
    private let processingQueue = DispatchQueue(label: "photo processing queue", attributes: [], autoreleaseFrequency: .workItem)
    
    private let photoDepthConverter = DepthToGrayscaleConverter()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /* setup input and output */
        let videoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice!), session.canAddInput(videoDeviceInput)
            else {
                print("Cannot add input")
                return
        }
        
        session.beginConfiguration()
        
        session.addInput(videoDeviceInput)
        
        guard session.canAddOutput(photoOutput) else {
            print("cannot add photo output")
            return
        }
        session.addOutput(photoOutput)
        session.sessionPreset = .photo
        
        session.commitConfiguration()
        
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
                
        /* add live preview */
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
        videoPreviewLayer?.frame = cameraView.layer.bounds
        cameraView.layer.addSublayer(videoPreviewLayer!)
        
        session.startRunning()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        print("captured")
                
    
        processingQueue.async {
            
            if let depthData = photo.depthData {
                let depthPixelBuffer = depthData.depthDataMap
                
                if !self.photoDepthConverter.isPrepared {
                    var depthFormatDescription: CMFormatDescription?
                    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                                 imageBuffer: depthPixelBuffer,
                                                                 formatDescriptionOut: &depthFormatDescription)
                    
                    if let unwrappedDepthFormatDescription = depthFormatDescription {
                        self.photoDepthConverter.prepare(with: unwrappedDepthFormatDescription, outputRetainedBufferCountHint: 3)
                    }
                }
                
                guard let convertedDepthPixelBuffer = self.photoDepthConverter.render(pixelBuffer: depthPixelBuffer) else {
                    print("Unable to convert depth pixel buffer")
                    return
                }
                
                let greyImage = UIImage.init(pixelBuffer: convertedDepthPixelBuffer)
                
                UIImageWriteToSavedPhotosAlbum(greyImage!, nil, nil, nil)

            }
        }
    
        
        //photo.fileDataRepresentation()
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: photo.fileDataRepresentation()!, options: nil)
            }, completionHandler: nil)
        }
    }
    
    func getSettings() -> AVCapturePhotoSettings {
        let setting = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        setting.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        return setting
    }
    
    var captureTimer: Timer?

    @IBAction func capture(_ sender: UIButton) {
        // Start the timer
            captureTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                
                self.sessionQueue.async {
                    self.photoOutput.capturePhoto(with: self.getSettings(), delegate: self)
                }
                
                /* button vibrate*/
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                /* photo capture animation */
                self.cameraView.layer.opacity = 0
                UIView.animate(withDuration: 0.25) {
                    self.cameraView.layer.opacity = 1
                }
            }
//        sessionQueue.async {
//            self.photoOutput.capturePhoto(with: self.getSettings(), delegate: self)
//        }
        
        /* button vibrate*/
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        /* photo capture animation */
        self.cameraView.layer.opacity = 0
        UIView.animate(withDuration: 0.25) {
            self.cameraView.layer.opacity = 1
        }
    }
    // Stop the timer when the view disappears
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    @objc
    func didEnterBackground(notification: NSNotification) {
        // Free up resources.
        processingQueue.async {
            self.photoDepthConverter.reset()
        }
    }
}

extension UIImage {
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        if let cgImage = cgImage {
            self.init(cgImage: cgImage, scale: 1.0, orientation: Orientation.right)
        } else {
            return nil
        }
    }
}

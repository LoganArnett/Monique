//
//  ViewController.swift
//  WebCam
//
//  Created by Shavit Tzuriel on 10/18/16.
//  Copyright © 2016 Shavit Tzuriel. All rights reserved.
//

import Cocoa
import AVKit
import AppKit
import AVFoundation
import CoreMedia

extension NSImage {
    var height: CGFloat {
        return self.size.height
    }
    var width: CGFloat {
        return self.size.width
    }
    var pngData: Data? {
        guard let tiffRepresentation = tiffRepresentation, let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .PNG, properties: [:])
    }
    func pngWrite(to url: URL, options: Data.WritingOptions = .atomic) -> Bool {
        do {
            try pngData?.write(to: url, options: options)
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
    ///  Copies and crops an image to the supplied size.
    ///  - parameter size: The size of the new image.
    ///  - returns: The cropped copy of the given image.
    func crop(size: NSSize) -> NSImage? {
        // Resize the current image, while preserving the aspect ratio.
        guard let resized = self.resizeWhileMaintainingAspectRatioToSize(size: size) else {
            return nil
        }
        // Get some points to center the cropping area.
        let x = floor((resized.width - size.width) / 2)
        let y = floor((resized.height - size.height) / 2)
        
        // Create the cropping frame.
        let frame = NSMakeRect(x, y, size.width, size.height)
        
        // Get the best representation of the image for the given cropping frame.
        guard let rep = resized.bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }
        
        // Create a new image with the new size
        let img = NSImage(size: size)
        
        img.lockFocus()
        defer { img.unlockFocus() }
        
        if rep.draw(in: NSMakeRect(0, 0, size.width, size.height),
                    from: frame,
                    operation: NSCompositingOperation.copy,
                    fraction: 1.0,
                    respectFlipped: false,
                    hints: [:]) {
            // Return the cropped image.
            return img
        }
        
        // Return nil in case anything fails.
        return nil
    }
    ///  Copies the current image and resizes it to the given size.
    ///  - parameter size: The size of the new image.
    ///  - returns: The resized copy of the given image.
    func copy(size: NSSize) -> NSImage? {
        print("COPYING")
        print(size)
        // Create a new rect with given width and height
        let frame = NSMakeRect(0, 0, size.width, size.height)
        
        // Get the best representation for the given size.
        guard let rep = self.bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }
        
        // Create an empty image with the given size.
        let img = NSImage(size: size)
        
        // Set the drawing context and make sure to remove the focus before returning.
        img.lockFocus()
        defer { img.unlockFocus() }
        
        // Draw the new image
        if rep.draw(in: frame) {
            return img
        }
        
        // Return nil in case something went wrong.
        return nil
    }
    ///  Copies the current image and resizes it to the size of the given NSSize, while
    ///  maintaining the aspect ratio of the original image.
    ///  - parameter size: The size of the new image.
    ///  - returns: The resized copy of the given image.
    func resizeWhileMaintainingAspectRatioToSize(size: NSSize) -> NSImage? {
        let newSize: NSSize
        
        let widthRatio  = size.width / self.width
        let heightRatio = size.height / self.height
        
        if widthRatio > heightRatio {
            newSize = NSSize(width: floor(self.width * widthRatio), height: floor(self.height * widthRatio))
        } else {
            newSize = NSSize(width: floor(self.width * heightRatio), height: floor(self.height * heightRatio))
        }
        
        return self.copy(size: newSize)
    }
    
    func resize(size: NSSize) -> NSImage? {
        return self.copy(size: NSSize(width: size.width, height: size.height))
    }
}

class ViewController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    var webcam:AVCaptureDevice? = nil
    var mic:AVCaptureDevice? = nil
    let videoOutput:AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    let audioOutput:AVCaptureAudioDataOutput = AVCaptureAudioDataOutput()
    let movieOutput:AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
    let videoSession:AVCaptureSession = AVCaptureSession()
    let audioSession:AVCaptureSession = AVCaptureSession()
    var videoPreviewLayer:AVCaptureVideoPreviewLayer? = nil
    var videoFilePath: URL? = nil
    
    var webcamSessionStarted:Bool = false
    var webcamSessionReady:Bool = false
    var webcamWritesCounter: Int = 0
    var detectionBoxView: NSView?
    var detectionBoxActive: Bool = false
    var currentBuffer: CMSampleBuffer?
    
    let webcamDetectionQueue: DispatchQueue = DispatchQueue(label: "webcamDetection")
    //let webcamWriterQueue: DispatchQueue = DispatchQueue(label: "webCamWriter")
    let webcamAudioQueue: DispatchQueue = DispatchQueue(label: "webcamAudio")
    let videoStreamerQueue: DispatchQueue = DispatchQueue(label: "streamer")
    let videoPreviewQueue: DispatchQueue = DispatchQueue(label: "preview")
    let videoPlayerQueue: DispatchQueue = DispatchQueue(label: "player")
    
    var streamingTimer: Timer?
    
    var avAsset: AVAsset? = nil
    var avAssetWriter: AVAssetWriter? = nil
    var avAssetWriterInput: AVAssetWriterInput? = nil
    var avAudioAssetWriterInput: AVAssetWriterInput? = nil
    var streamFileCounter: Int = 0
    var streamingChannel: String = "0001"
    
    // Player
    let player:AVPlayer = AVPlayer()
    
    let cmTimeScale: Int32 = 1000000000
    var currentRecordingTime: Int64 = 0
    
    let stream: CustomStream = CustomStream()
    private let context = CIContext()
    
    @IBOutlet weak var playerPreview:NSView!
    @IBOutlet weak var videoPlayerView: NSView!
    @IBOutlet weak var btnCaptureWebcam: NSButton!
    @IBOutlet weak var previewImage: NSImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Webcam broadcast and preview
        self.setVideoSession()
        
        // Video player preview
        let playerView = AVPlayerView()
        playerView.frame = videoPlayerView.frame
        playerView.player = player
        videoPlayerView.addSubview(playerView)
        // Use a m3u8 playlist of live video
        // let streamURL:URL = URL(string: "http://localhost:3000/videos/live/playlist")!
        // Encode and stream
        let streamURL: URL = URL(string: "http://localhost:3000/playlists/1")!
        startPlaying(from: streamURL)
        
        // Create the video writer
        //createWriter()
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
            print("---> Update the view if it was loaded")
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        currentBuffer = sampleBuffer
        currentRecordingTime = Int64(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
//        let imageBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        // Unlock the buffer
        //_ = CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        // Bytes per row
//        let bytes: size_t = CVPixelBufferGetBytesPerRow(imageBuffer)
//        let image = CVPixelBufferGetBaseAddress(imageBuffer)
        
        // Audio
//        print(CMSampleBufferGetFormatDescription(sampleBuffer))
        
        // Add to the buffer
        if (self.webcamSessionReady == false && webcamSessionStarted == true){
            self.avAssetWriterInput?.append(sampleBuffer)
        }
    }
    
    @IBAction func takePhoto(_ sender: Any) {
        return imageFromSampleBuffer(sampleBuffer: currentBuffer!);
    }
    
    let desktopURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let ciImage = CIImage(cvPixelBuffer: imageBuffer!)
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let nsImage = NSImage.init(cgImage: cgImage!, size: CGSize(width: 1280, height: 720));
        previewImage.image = nsImage;
        
        let imageFile = nsImage.resize(size: NSSize(width: 1280, height: 720));
        let destinationURL = desktopURL.appendingPathComponent("swift-photo-\(Date()).png")
        if imageFile!.pngWrite(to: destinationURL, options: .withoutOverwriting) {
            print("File saved")
        }
    }
    
    
    /*!
     @method captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:
     @abstract
     Informs the delegate when all pending data has been written to an output file.
     
     @param captureOutput
     The capture file output that has finished writing the file.
     @param fileURL
     The file URL of the file that has been written.
     @param connections
     An array of AVCaptureConnection objects attached to the file output that provided the data that was written to the
     file.
     @param error
     An error describing what caused the file to stop recording, or nil if there was no error.
     
     @discussion
     This method is called when the file output has finished writing all data to a file whose recording was stopped,
     either because startRecordingToOutputFileURL:recordingDelegate: or stopRecording were called, or because an error,
     described by the error parameter, occurred (if no error occurred, the error parameter will be nil).  This method will
     always be called for each recording request, even if no data is successfully written to the file.
     
     Clients should not assume that this method will be called on a specific thread.
     
     Delegates are required to implement this method.
     */
    @available(OSX 10.7, *)
    public func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        
        print("---> Finish recording to \(outputFileURL.absoluteString)")
        
        //do {
        //    try FileManager.default.moveItem(at: outputFileURL, to: self.videoFilePath!)
        //} catch let err as NSError {
        //    print("Error moving video file: \(err)")
        //}
    }
    
    @IBAction func CaptureWebCamVideo(_ sender: AnyObject) {
        // Not in session and there is data
        if (self.webcamSessionReady == false && webcamSessionStarted == true){
            let cmTime: CMTime = CMTimeMake(currentRecordingTime, cmTimeScale)
            self.avAssetWriter?.endSession(atSourceTime: cmTime)
            self.avAssetWriterInput?.markAsFinished()
            // Stop streaming interval
            streamingTimer?.invalidate()
            // Stop recording
            self.movieOutput.stopRecording()
            self.avAssetWriter?.finishWriting {
                self.videoStreamerQueue.async {
                    self.stream.broadcastData(url: self.videoFilePath, channel: self.streamingChannel, id: self.createMessageId())
                }
            }
            btnCaptureWebcam.layer?.backgroundColor = NSColor.white.cgColor
            btnCaptureWebcam.title = "Ready"
            webcamSessionReady = true
            webcamSessionStarted = false
            
            return
        }
        
        // Create writer and start session
        createWriter()
        print("---> Starting camera session")
        let cmTime: CMTime = CMTimeMake(self.currentRecordingTime, self.cmTimeScale)
        self.avAssetWriter!.startSession(atSourceTime: cmTime)
        self.movieOutput.startRecording(toOutputFileURL: self.getVideoFilePath(), recordingDelegate: self)
        
        self.btnCaptureWebcam.layer?.backgroundColor = NSColor.red.cgColor
        self.btnCaptureWebcam.title = "Recording"
        self.webcamSessionReady = false
        self.webcamSessionStarted = true
        
        // Write in intervals of 6 seconds
        streamingTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true, block: { (timer) in
            let cmTime: CMTime = CMTimeMake(self.currentRecordingTime, self.cmTimeScale)
            self.avAssetWriter?.endSession(atSourceTime: cmTime)
            self.avAssetWriterInput?.markAsFinished()
            // Stop recording
            self.movieOutput.stopRecording()
            self.avAssetWriter?.finishWriting {
                print("---> Finish session at \(self.currentRecordingTime)")
                self.videoStreamerQueue.sync {
                    //usleep(1)
                    self.stream.broadcastData(url: self.videoFilePath, channel: self.streamingChannel, id: self.createMessageId())
                }
            }
            
            // Start the writing session
            self.avAssetWriter!.startSession(atSourceTime: cmTime)
            // Start recording to file
            self.movieOutput.startRecording(toOutputFileURL: self.getVideoFilePath(), recordingDelegate: self)
        })
        
    }
    
    
    func setVideoSession(){
        videoSession.beginConfiguration()
        // Set the device
        let devices = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo)!
        webcam = devices[1] as? AVCaptureDevice
        print(devices)
        
//        let audioDevices = AVCaptureDevice.devices(withMediaType: AVMediaTypeAudio)!
//        mic = audioDevices[0] as? AVCaptureDevice
//        print(audioDevices)
        
        do {
            let webcamInput: AVCaptureDeviceInput = try AVCaptureDeviceInput(device: webcam)
//            let micInput: AVCaptureDeviceInput = try AVCaptureDeviceInput(device: mic)
            if videoSession.canAddInput(webcamInput){
                videoSession.addInput(webcamInput)
                print("---> Adding webcam input")
            }
//            if videoSession.canAddInput(micInput){
//                videoSession.addInput(micInput)
//                print("---> Adding mic input")
//            }
        } catch let err as NSError {
            print("---> Error using the webcam: \(err)")
        }
        // Webcam session
        videoSession.sessionPreset = AVCaptureSessionPresetHigh

        videoSession.addOutput(videoOutput)
        videoSession.addOutput(audioOutput)
        videoSession.addOutput(movieOutput)
        videoSession.commitConfiguration()
        // Register the sample buffer callback
        videoOutput.setSampleBufferDelegate(self, queue: videoPreviewQueue)
        // Audio
        audioOutput.setSampleBufferDelegate(self, queue: webcamAudioQueue)
        // Movie
        // Preview layer
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: videoSession)
        // Attach the preview to the view
        playerPreview.layer = videoPreviewLayer
        // Resize the preview
        videoPreviewLayer!.videoGravity = AVLayerVideoGravityResizeAspectFill
        videoPreviewLayer!.connection.videoOrientation = AVCaptureVideoOrientation.portrait
        
        // Start the video preview session
        videoPreviewQueue.async {
            self.videoPreviewLayer!.session.startRunning()
        }
        
    }
    
    private func createWriter(){
        self.videoFilePath = getVideoFilePath()
        self.streamingChannel = String(format: "%04d", Int(arc4random_uniform(1000)+1))
        
        // Video recording settings
        let numPixels: Float64 = 480*320
        //let bitsPerPixel: Float64 = 10.1
        let bitsPerPixel: Float64 = 4
        let bitsPerSecond: Float64 = numPixels * bitsPerPixel
        let avAssetWriterInputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        avAssetWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: avAssetWriterInputSettings)
        // Set it to true, to ensure that readyForMoreMediaData is calculated appropriatley
        avAssetWriterInput?.expectsMediaDataInRealTime = true
        
        do {
            self.avAssetWriter = try AVAssetWriter(outputURL: videoFilePath!, fileType: AVFileTypeMPEG4)
            if self.avAssetWriter!.canAdd(avAssetWriterInput!) {
                print("---> Adding input to AVAsset at \(videoFilePath!.path)")
                avAssetWriter!.add(avAssetWriterInput!)
            }
            
        } catch let err as NSError {
            print("Error initializing AVAssetWriter: \(err)")
        }
        
        // Need to be set once before starting the session
        avAssetWriter!.startWriting()
        
    }
    
    // Switch the state of the detection box
    @IBAction func startImageDetectionAction(_ sender: AnyObject){
        self.detectionBoxActive = !self.detectionBoxActive
    }
    
    // Image detection box
    private func startImageDetection(imageBuffer: CVImageBuffer){
        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeFace, context: context, options: nil)
        let image: CIImage = CIImage(cvImageBuffer: imageBuffer)
        let features = detector?.features(in: image) // [CIFeature]
        // Add a detection box on top of the preview layer
        self.detectionBoxView = DetectionBoxView()
        playerPreview.addSubview(self.detectionBoxView!)
        
        webcamDetectionQueue.async {
            
            print("---> Detecting")
            print("---> Image: \(image)")
            
            for ciFeature in features! {
                // Display a rectangle
                print("---> Features bounds: \(ciFeature.bounds)")
                self.detectionBoxView?.draw(ciFeature.bounds)
            }
        }
        
    }
 
    // Play video on a different thread
    private func startPlaying(from url: URL){
        let playerResourceItem: AVPlayerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerResourceItem)
        
        videoPlayerQueue.async {
            print("---> Playing video from \(url.absoluteString)")
            //self.player.play()
        }
    }
    
    private func saveToFile(file name: String, image buffer: CVImageBuffer!){
        let bytes: size_t = CVPixelBufferGetBytesPerRow(buffer)
        let image = CVPixelBufferGetBaseAddress(buffer)
        // Write to a file from NSData for debugging
        let imageData: NSData = NSData(bytes: image, length: bytes)
        let videoFileDirectory: URL = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true)[0], isDirectory: true).appendingPathComponent("Webcam/sessions")
        let dataOutputFile: URL = URL(fileURLWithPath: videoFileDirectory.path.appending(name))
        imageData.write(to: dataOutputFile, atomically: true)
    }
    
    private func getVideoFilePath() -> URL{
        let videoFileDirectory: URL = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true)[0], isDirectory: true).appendingPathComponent("Webcam/sessions")
        
        do {
            try FileManager.default.createDirectory(atPath: videoFileDirectory.path, withIntermediateDirectories: true, attributes: nil)
        } catch let err as NSError {
            print("Error creating a directory for the output file \(err)")
        }
        
        webcamWritesCounter += 1
        let fileNumber = String(format: "%04d", webcamWritesCounter)
        //let uid = NSUUID().uuidString
        print("---> Create directory at path \(videoFileDirectory.path)")
        
        videoFilePath =  URL(fileURLWithPath: videoFileDirectory.path.appending("/session_\(self.streamingChannel)_\(fileNumber).mp4"))
        
        return videoFilePath!
    }
    
    private func createMessageId() -> String {
        self.streamFileCounter += 1
        return String(format: "%04d", self.streamFileCounter)
    }
}

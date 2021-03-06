//: Playground - noun: a place where people can play

import Cocoa
import Darwin
import AVFoundation

func htons(value: CUnsignedShort) -> CUnsignedShort {
    return (value << 8) + (value >> 8)
}

// There is a limit for the message size
func sendChunk(chunk: UnsafeRawPointer, messageLength: Int){
    let INADDR_ANY = in_addr(s_addr: 0)
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    var addr_in = sockaddr_in(sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: htons(value: 3001), sin_addr: INADDR_ANY, sin_zero: (0,0,0,0,0,0,0,0))
    
    withUnsafePointer(to: &addr_in) {
        let p = UnsafeRawPointer($0).bindMemory(to: sockaddr.self, capacity: 1)
        sendto(fd, chunk, messageLength, 0, p, socklen_t(addr_in.sin_len))
    }
    
}

func sendMessage(message: NSData){
    let INADDR_ANY = in_addr(s_addr: 0)
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    var addr_in = sockaddr_in(sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: htons(value: 3001), sin_addr: INADDR_ANY, sin_zero: (0,0,0,0,0,0,0,0))
    
    withUnsafePointer(to: &addr_in) {
        let p = UnsafeRawPointer($0).bindMemory(to: sockaddr.self, capacity: 1)
        let res = sendto(fd, message.bytes, message.length, 0, p, socklen_t(addr_in.sin_len))
        
        print("Send? \(res)")
    }
    
}

func sendMessage(message: String){
    //let message = "Message from Swift 3"
    let INADDR_ANY = in_addr(s_addr: 0)
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    var addr_in = sockaddr_in(sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: htons(value: 3001), sin_addr: INADDR_ANY, sin_zero: (0,0,0,0,0,0,0,0))
    
    message.withCString { cstr -> Void in
        let sent = withUnsafePointer(to: &addr_in) {
            
            let broadcastMessageLength = Int(strlen(cstr) + 1)
            let p = UnsafeRawPointer($0).bindMemory(to: sockaddr.self, capacity: 1)
            
            // Send the message
            sendto(fd, cstr, broadcastMessageLength, 0, p, socklen_t(addr_in.sin_len))
            
        }
        
        print("Sent? \(sent)")
    }
}


func writeToFile(name: String, message: String){
    let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.downloadsDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
    let videoFileDirectory = URL(fileURLWithPath: paths[0].appending("/WebCam"))
    let filePathValidator: FileManager = FileManager.default
    let videoFilePath: URL = URL(fileURLWithPath: videoFileDirectory.path.appending("/\(name)"))
    let outputStream: OutputStream = OutputStream.init(toFileAtPath: videoFilePath.path, append: true)!
    
    // Create folder if not exists
    do {
        print("---> Setting capture session at \(videoFilePath.absoluteString)")
        if filePathValidator.fileExists(atPath: videoFileDirectory.absoluteString) == false {
            try filePathValidator.createDirectory(at: videoFileDirectory, withIntermediateDirectories: true, attributes: nil)
            print("---> Created directory \(videoFileDirectory.absoluteString)")
            
        } else{
            print("---> File path not exists at \(videoFileDirectory.absoluteString)")
        }
        
    } catch let err as NSError {
        print("---> Error creating a directory at \(videoFileDirectory.absoluteString)")
        print(err)
    }
    
    // Write to file
    outputStream.open()
    let messageData: NSData = NSData(data: message.data(using: .utf8)!)
    let messageLength: Int = messageData.length
    
    message.data(using: .utf8)?.withUnsafeBytes({ (p: UnsafePointer<UInt8>) -> Void in
        outputStream.write(p, maxLength: messageLength)
    })
    
    outputStream.close()
}

func sendPictureFile(){
    let videoFileDirectory: URL = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true)[0], isDirectory: true).appendingPathComponent("Webcam")
    let fileURL: URL = URL(fileURLWithPath: videoFileDirectory.path.appending("/picture.jpg"))
    do {
        let fileData: NSData = try NSData(contentsOf: fileURL)
        //let messageBytes: [Int32] = [2412,1,1292,0]
        let messageBytes: [Int32] = [2412,1,149,0,2,3,2,4,1]
        let mutableData: NSMutableData = NSMutableData()
        mutableData.append(messageBytes, length: messageBytes.count)
        mutableData.append(fileData.bytes, length: fileData.length)
        sendMessage(message: mutableData)
        
    } catch let err as NSError {
        print(err)
    }
}

// Need to send chunks of the file
func sendVideoFile(){
    let videoFileDirectory: URL = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true)[0], isDirectory: true).appendingPathComponent("Webcam")
    let fileURL: URL = URL(fileURLWithPath: videoFileDirectory.path.appending("/video-small-01.mp4"))
//    let fileURL: URL = URL(fileURLWithPath: videoFileDirectory.path.appending("/picture.jpg"))
    
    do {
        let fileData: NSData = try NSData(contentsOf: fileURL)
        let dataSize: Int = fileData.length
        //let header: [Int32] = [2418,1,dataSize,0,0,0,0,0,0]
        let headerSize: Int = 9
        let header: String = "4402" + "0" + "0001"
        
        var chunkSize: Int = 4000-headerSize
        if dataSize < (4000 - headerSize) {
            chunkSize = dataSize
        }
        var dataOffset: Int = 0
        
        while dataOffset < dataSize {
            // This does not include the header
            let tmpChunkSize: Int = ((dataSize - dataOffset) > chunkSize) ? (chunkSize) : (dataSize - dataOffset)
            let chunk: NSData = fileData.subdata(with: NSMakeRange(dataOffset, tmpChunkSize)) as NSData
            let mutableData: NSMutableData = NSMutableData()
            mutableData.append(header, length: headerSize)
            mutableData.append(chunk.bytes, length: chunk.length)
            sendChunk(chunk: mutableData.bytes, messageLength: mutableData.length)
            
            dataOffset = dataOffset + chunk.length
            // Don't flood the UDP stream
            // 1,000,000 = 1 second
            usleep(1)
        }
        
        print("---> Finished \(dataOffset)/\(dataSize)")
    
    } catch let err as NSError {
        print(err)
    }
    
}
//sendVideoFile()

//let messageBytes: [Int32] = [3432,2,124,4315,6,22,4999,2,2,3,4,5,6]
//let messageData: NSData = NSData(bytes: messageBytes, length: messageBytes.count)
//sendMessage(message: messageData)

//writeToFile(name: "writing_test.txt", message: "Hello")

func writeVideoFile(){
    let url: URL = URL(fileURLWithPath: "/Users/Shavit/Downloads/WebCam/test.mp4")
    do {
        let av: AVAssetWriter = try AVAssetWriter(outputURL: url, fileType: AVFileTypeMPEG4)
    } catch let err as NSError{
        print("---> Error writing to \(url.path)")
    }
    
    let outputSettings = [
        AVVideoCodecKey: AVVideoCodecH264,
        AVVideoWidthKey: 420,
        AVVideoHeightKey: 320,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10 * 1000000]
        ] as [String : Any]
    let avAssetWriterInput: AVAssetWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: outputSettings)

}

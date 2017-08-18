//
//  CustomStream.swift
//  WebCam
//

import Foundation
import Darwin

class CustomStream {
    
    init() {
        
    }
    
    let port = UInt16(3001)
    let INADDR_ANY = in_addr(s_addr: 0)
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    
    func broadcast(message: String){
        var addr_in = sockaddr_in(sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: self.htons(value: port), sin_addr: INADDR_ANY, sin_zero: (0,0,0,0, 0,0,0,0))
        
        message.withCString { cstr -> Void in
            withUnsafePointer(to: &addr_in) {
                let broadcastMessageLength = Int(strlen(cstr) + 1)
                let p = UnsafeRawPointer($0).bindMemory(to: sockaddr.self, capacity: 1)
                
                // Send the message
                sendto(fd, cstr, broadcastMessageLength, 0, p, socklen_t(addr_in.sin_len))
            }
        }
    }
    
    func createBroadcast(channel: String, resolution: String, id: String, message: NSData){
        let headerSize: Int = 9
        let header: String = channel + resolution + id
        let dataSize: Int = message.length
        var chunkSize: Int = 4000-headerSize
        if dataSize < (4000-headerSize) {
            chunkSize = dataSize
        }
        var dataOffset: Int = 0
        
        while dataOffset < dataSize {
            // This does not include the header
            let tmpChunkSize: Int = ((dataSize - dataOffset) > chunkSize)
                ? (chunkSize)
                : (dataSize - dataOffset)
            let chunk: NSData = message.subdata(with: NSMakeRange(dataOffset, tmpChunkSize)) as NSData
            let mutableData: NSMutableData = NSMutableData()
            mutableData.append(header, length: headerSize)
            mutableData.append(chunk.bytes, length: chunk.length)
            sendChunk(chunk: mutableData.bytes, messageLength: mutableData.length)
            
            // Move the pointer forward
            dataOffset = dataOffset + chunk.length
            // Don't flood the UDP stream
            // 1,000,000 = 1 second
            usleep(1)
        }
        
        print ("---> Finished \(dataOffset)/\(dataSize)")
    }
    
    public func broadcastData(url: URL?, channel: String, id: String){
        do {
            let fileData: NSData = try NSData(contentsOf: url!)
            let resolution: String = "1"
            createBroadcast(channel: channel, resolution: resolution, id: id, message: fileData)
            
        } catch let err as NSError {
            print("Error streaming file: \(err)")
        }
    }
    
    private func htons(value: CUnsignedShort) -> CUnsignedShort {
        return (value << 8) + (value >> 8)
    }
    
    private func sendChunk(chunk: UnsafeRawPointer, messageLength: Int){
        let INADDR_ANY = in_addr(s_addr: 0)
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        var addr_in = sockaddr_in(sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: htons(value: 3001), sin_addr: INADDR_ANY, sin_zero: (0,0,0,0,0,0,0,0))
        
        withUnsafePointer(to: &addr_in) {
            let p = UnsafeRawPointer($0).bindMemory(to: sockaddr.self, capacity: 1)
            sendto(fd, chunk, messageLength, 0, p, socklen_t(addr_in.sin_len))
        }
        
    }
    
}


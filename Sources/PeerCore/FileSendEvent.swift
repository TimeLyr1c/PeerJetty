import Foundation

/// Local request lifecycle; the same UUID becomes the outgoing file transfer ID.
public enum FileSendPhase { case preparing, connecting, queued, started, failed }
public struct FileSendEvent {
    public let id: UUID
    public let peerID: String
    public let peerName: String
    public let phase: FileSendPhase
    public let error: Error?
    public let notConnected: Bool
    public init(id:UUID,peerID:String,peerName:String,phase:FileSendPhase,error:Error?=nil,notConnected:Bool=false) {
        self.id=id; self.peerID=peerID; self.peerName=peerName; self.phase=phase; self.error=error; self.notConnected=notConnected
    }
}

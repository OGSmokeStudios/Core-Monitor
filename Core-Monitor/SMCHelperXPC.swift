import Foundation

@objc protocol SMCHelperXPCProtocol {
    nonisolated func readSafetyVersion(withReply reply: @escaping (NSNumber) -> Void)
    nonisolated func renewControlLease(withReply reply: @escaping (NSNumber, NSString?) -> Void)
    nonisolated func setFanManual(_ fanID: Int, rpm: Int, withReply reply: @escaping (NSString?) -> Void)
    nonisolated func setFanAuto(_ fanID: Int, withReply reply: @escaping (NSString?) -> Void)
    nonisolated func readValue(_ key: String, withReply reply: @escaping (NSNumber?, NSString?) -> Void)
    nonisolated func readControlMetadata(withReply reply: @escaping (NSString?, NSNumber?, NSString?) -> Void)
}

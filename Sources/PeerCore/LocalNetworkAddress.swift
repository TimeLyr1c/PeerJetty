import Foundation
import Darwin
import SystemConfiguration

public struct LocalNetworkAddress {
    public let host: String
    public let interface: String
    public let label: String
    public let local: Bool
    public static func discover() -> [LocalNetworkAddress] {
        var physical: [String:String] = [:]
        for item in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard let bsd = SCNetworkInterfaceGetBSDName(item) as String?, let type = SCNetworkInterfaceGetInterfaceType(item) else { continue }
            if bsd.hasPrefix("en"), type == kSCNetworkInterfaceTypeIEEE80211 || type == kSCNetworkInterfaceTypeEthernet {
                physical[bsd] = type == kSCNetworkInterfaceTypeIEEE80211 ? "Wi-Fi" : "Ethernet"
            }
        }
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }; defer { freeifaddrs(list) }
        var node = list, result: [LocalNetworkAddress] = []
        while let item = node {
            let info = item.pointee; node = info.ifa_next
            guard let address = info.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  info.ifa_flags & UInt32(IFF_UP) != 0, info.ifa_flags & UInt32(IFF_RUNNING) != 0, info.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let bsd = String(cString:info.ifa_name)
            var buffer = [CChar](repeating:0,count:Int(NI_MAXHOST))
            guard getnameinfo(address,socklen_t(address.pointee.sa_len),&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST) == 0 else { continue }
            let host = String(cString:buffer)
            if !result.contains(where:{$0.host == host && $0.interface == bsd}) {
                result.append(LocalNetworkAddress(host:host,interface:bsd,label:physical[bsd] ?? bsd,local:physical[bsd] != nil))
            }
        }
        return result.sorted { ($0.interface,$0.host) < ($1.interface,$1.host) }
    }
}

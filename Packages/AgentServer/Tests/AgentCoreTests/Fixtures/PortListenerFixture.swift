import Foundation
#if os(macOS)
import Darwin
let descriptor = socket(AF_INET, SOCK_STREAM, 0)
#elseif os(Linux)
import Glibc
let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
#else
exit(2)
#endif

#if os(macOS) || os(Linux)
guard descriptor >= 0, let port = UInt16(CommandLine.arguments[1]) else { exit(2) }
var address = sockaddr_in()
address.sin_family = sa_family_t(AF_INET)
address.sin_port = port.bigEndian
address.sin_addr.s_addr = inet_addr("127.0.0.1")
let result = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}
if result != 0 { exit(errno == EADDRINUSE ? 98 : 2) }
guard listen(descriptor, 1) == 0 else { exit(2) }
FileHandle.standardOutput.write(Data("ready\n".utf8))
Thread.sleep(forTimeInterval: 30)
close(descriptor)
#endif

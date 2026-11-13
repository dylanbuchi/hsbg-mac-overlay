import Darwin
import Foundation

/// Live, read-only view of another process. Gets the task port (needs the
/// `com.apple.security.cs.debugger` entitlement and the user's OK in macOS's "Developer Tools Access"
/// prompt) and only ever calls `mach_vm_read_overwrite` and region queries on it. It never writes,
/// suspends, injects or calls code in the target.
public final class TaskMemory: MemorySource {
    public let pid: pid_t
    private let task: mach_port_t

    public enum OpenError: Error, CustomStringConvertible {
        case denied(kern_return_t)

        public var description: String {
            switch self {
            case .denied(let code):
                return "macOS did not allow reading the game (task_for_pid \(code))"
            }
        }
    }

    public init(pid: pid_t) throws {
        var port: mach_port_t = 0
        let result = task_for_pid(mach_task_self_, pid, &port)
        guard result == KERN_SUCCESS else { throw OpenError.denied(result) }
        self.pid = pid
        self.task = port
    }

    deinit {
        mach_port_deallocate(mach_task_self_, task)
    }

    public func read(_ address: UInt64, _ count: Int) -> [UInt8]? {
        guard count > 0 else { return count == 0 ? [] : nil }
        // Only plausible user-space addresses: garbage pointers are rejected, never dereferenced.
        guard address >= 0x1000, address < 0x0000_8000_0000_0000, count < 1 << 24 else { return nil }
        var buffer = [UInt8](repeating: 0, count: count)
        var copied: mach_vm_size_t = 0
        let result = buffer.withUnsafeMutableBytes { raw in
            mach_vm_read_overwrite(task, address, mach_vm_size_t(count),
                                   mach_vm_address_t(UInt(bitPattern: raw.baseAddress)), &copied)
        }
        guard result == KERN_SUCCESS, copied == count else { return nil }
        return buffer
    }

    /// Load address and file path of the first mapped Mach-O image whose file name is `fileName`.
    public func image(named fileName: String) -> (base: UInt64, path: String)? {
        var address: mach_vm_address_t = 0
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        while true {
            var size: mach_vm_size_t = 0
            var info = vm_region_basic_info_data_64_t()
            var infoCount = mach_msg_type_number_t(MemoryLayout<vm_region_basic_info_data_64_t>.size / MemoryLayout<Int32>.size)
            var object: mach_port_t = 0
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: Int32.self, capacity: Int(infoCount)) {
                    mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO_64, $0, &infoCount, &object)
                }
            }
            guard result == KERN_SUCCESS else { return nil }
            let length = proc_regionfilename(pid, address, &pathBuffer, UInt32(pathBuffer.count))
            if length > 0 {
                let path = String(decoding: pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if path.hasSuffix("/" + fileName), u32(address) == MH_MAGIC_64 {
                    return (address, path)
                }
            }
            address += size
        }
    }

    /// True when the target runs as x86_64 under Rosetta; false for native arm64 (or an Intel Mac).
    public static func isTranslated(pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRANSLATED != 0
    }
}

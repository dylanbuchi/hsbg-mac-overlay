import Foundation

/// Finds exported symbols in a Mach-O file on disk (thin or universal) and decodes the one
/// instruction pattern we need: a getter that loads a global pointer and returns it.
/// Only metadata of Blizzard's Mono library is parsed; nothing is executed or patched.
public enum MachOSymbol {
    public enum Arch: Sendable, Equatable {
        case arm64, x86_64

        var cpuType: UInt32 { self == .arm64 ? 0x0100_000C : 0x0100_0007 }
    }

    /// File offset and size of the slice for `arch` (the whole file when it is thin).
    static func slice(in data: [UInt8], arch: Arch) -> Range<Int>? {
        guard data.count >= 8 else { return nil }
        let magicBE = be32(data, 0)
        if magicBE == 0xCAFE_BABE {
            let count = Int(be32(data, 4))
            for index in 0..<count {
                let entry = 8 + index * 20
                guard entry + 20 <= data.count else { return nil }
                if be32(data, entry) == arch.cpuType {
                    let offset = Int(be32(data, entry + 8)), size = Int(be32(data, entry + 12))
                    guard offset + size <= data.count else { return nil }
                    return offset..<(offset + size)
                }
            }
            return nil
        }
        guard le32(data, 0) == 0xFEED_FACF, le32(data, 4) == arch.cpuType else { return nil }
        return 0..<data.count
    }

    /// Value of `symbol` (e.g. `_mono_get_root_domain`) and the __TEXT segment's vmaddr, so the
    /// caller can turn it into an address in the running process: base + (value - textVMAddr).
    public static func lookup(_ symbol: String, inFile data: [UInt8], arch: Arch) -> (value: UInt64, textVMAddr: UInt64)? {
        guard let range = slice(in: data, arch: arch) else { return nil }
        let base = range.lowerBound
        let commandCount = Int(le32(data, base + 16))
        var cursor = base + 32
        var textVMAddr: UInt64?
        var symtab: (symoff: Int, nsyms: Int, stroff: Int, strsize: Int)?
        for _ in 0..<commandCount {
            guard cursor + 8 <= range.upperBound else { return nil }
            let command = le32(data, cursor), size = Int(le32(data, cursor + 4))
            if command == 0x19 { // LC_SEGMENT_64
                let name = String(decoding: data[(cursor + 8)..<(cursor + 24)].prefix { $0 != 0 }, as: UTF8.self)
                if name == "__TEXT" { textVMAddr = le64(data, cursor + 24) }
            } else if command == 0x2 { // LC_SYMTAB
                symtab = (Int(le32(data, cursor + 8)), Int(le32(data, cursor + 12)),
                          Int(le32(data, cursor + 16)), Int(le32(data, cursor + 20)))
            }
            guard size > 0 else { return nil }
            cursor += size
        }
        guard let textVMAddr, let symtab else { return nil }
        let wanted = Array(symbol.utf8)
        for index in 0..<symtab.nsyms {
            let entry = base + symtab.symoff + index * 16
            guard entry + 16 <= range.upperBound else { return nil }
            let type = data[entry + 4]
            guard type & 0x0E == 0x0E, type & 0x01 == 0x01 else { continue } // N_SECT | N_EXT
            let nameStart = base + symtab.stroff + Int(le32(data, entry))
            guard nameStart + wanted.count < data.count,
                  data[nameStart..<(nameStart + wanted.count)].elementsEqual(wanted),
                  data[nameStart + wanted.count] == 0 else { continue }
            return (le64(data, entry + 8), textVMAddr)
        }
        return nil
    }

    /// Address of the global a "return *global" getter reads, given the getter's first bytes and
    /// its own address. arm64: `adrp xN, page; ldr x0, [xN, #off]`. x86_64: `mov rax, [rip+disp]`, after an
    /// optional frame prologue.
    public static func globalLoadedBy(code: [UInt8], at address: UInt64, arch: Arch) -> UInt64? {
        switch arch {
        case .arm64:
            guard code.count >= 8 else { return nil }
            let adrp = le32(code, 0), ldr = le32(code, 4)
            guard adrp & 0x9F00_0000 == 0x9000_0000, ldr & 0xFFC0_0000 == 0xF940_0000,
                  (ldr >> 5) & 0x1F == adrp & 0x1F else { return nil }
            let immlo = UInt64((adrp >> 29) & 0x3), immhi = UInt64((adrp >> 5) & 0x7FFFF)
            var pages = Int64(immhi << 2 | immlo)
            if pages & (1 << 20) != 0 { pages -= 1 << 21 }
            let page = UInt64(bitPattern: Int64(bitPattern: address & ~0xFFF) + pages << 12)
            return page + UInt64((ldr >> 10) & 0xFFF) * 8
        case .x86_64:
            // Optional frame prologue `push rbp; mov rbp, rsp` before the load.
            let start = code.starts(with: [0x55, 0x48, 0x89, 0xE5]) ? 4 : 0
            guard code.count >= start + 7, code[start] == 0x48, code[start + 1] == 0x8B,
                  code[start + 2] == 0x05 else { return nil }
            let displacement = Int32(bitPattern: le32(code, start + 3))
            return UInt64(bitPattern: Int64(bitPattern: address) + Int64(start) + 7 + Int64(displacement))
        }
    }

    static func le32(_ data: [UInt8], _ at: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[at + $1]) << (8 * $1) }
    }

    static func le64(_ data: [UInt8], _ at: Int) -> UInt64 {
        (0..<8).reduce(0) { $0 | UInt64(data[at + $1]) << (8 * $1) }
    }

    static func be32(_ data: [UInt8], _ at: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 << 8 | UInt32(data[at + $1]) }
    }
}

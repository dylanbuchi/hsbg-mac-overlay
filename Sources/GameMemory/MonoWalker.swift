import Foundation

/// A failed step of a walk, with a short reason safe to log (never game data such as names).
public struct WalkError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Walks Mono's runtime metadata by class and field NAME, read-only, the way unity-spy does.
/// Every read goes through `MemorySource`, so the same code runs on the live game and on fixtures.
public final class MonoWalker {
    public struct Field: Equatable {
        public let name: String
        public let offset: Int
        public let isStatic: Bool
    }

    public let memory: MemorySource
    let offsets: MonoOffsets
    let rootDomain: UInt64
    public var rootDomainAddress: UInt64 { rootDomain }
    private var classCache: [String: UInt64] = [:]
    private var fieldCache: [UInt64: [Field]] = [:]

    public init(memory: MemorySource, rootDomain: UInt64, offsets: MonoOffsets = .unity6000_3) {
        self.memory = memory
        self.rootDomain = rootDomain
        self.offsets = offsets
    }

    /// (assembly name, MonoImage*) for every assembly loaded in the root domain.
    public func assemblies() -> [(name: String, image: UInt64)] {
        var result: [(String, UInt64)] = []
        var node = memory.pointer(rootDomain &+ UInt64(offsets.domainAssemblies))
        var guardCount = 0
        while let current = node, guardCount < 1000 {
            guardCount += 1
            if let assembly = memory.pointer(current),
               let image = memory.pointer(assembly &+ UInt64(offsets.assemblyImage)) {
                let name = memory.pointer(assembly &+ UInt64(offsets.assemblyName)).flatMap { memory.cString($0) } ?? "?"
                result.append((name, image))
            }
            node = memory.pointer(current &+ 8)
        }
        return result
    }

    /// Every MonoClass* in an image's class cache.
    public func classes(in image: UInt64) -> [UInt64] {
        let table = image &+ UInt64(offsets.imageClassCache)
        guard let size = memory.i32(table &+ UInt64(offsets.hashTableSize)), size > 0, size < 1_000_000,
              let buckets = memory.pointer(table &+ UInt64(offsets.hashTableTable)),
              let raw = memory.read(buckets, Int(size) * 8) else { return [] }
        var result: [UInt64] = []
        for bucket in 0..<Int(size) {
            var entry = (0..<8).reduce(UInt64(0)) { $0 | UInt64(raw[bucket * 8 + $1]) << (8 * $1) }
            var chain = 0
            while entry != 0, chain < 10_000 {
                result.append(entry)
                entry = memory.u64(entry &+ UInt64(offsets.classNextCache)) ?? 0
                chain += 1
            }
        }
        return result
    }

    public func className(_ klass: UInt64) -> String? {
        memory.pointer(klass &+ UInt64(offsets.className)).flatMap { memory.cString($0) }
    }

    public func classNamespace(_ klass: UInt64) -> String? {
        memory.pointer(klass &+ UInt64(offsets.classNamespace)).flatMap { memory.cString($0) }
    }

    /// The class `name` (in `namespace`), searched in `preferredAssembly` first, then everywhere.
    public func findClass(_ name: String, namespace: String = "", preferredAssembly: String = "Assembly-CSharp") throws -> UInt64 {
        let key = namespace + "." + name
        if let cached = classCache[key] { return cached }
        let all = assemblies()
        guard !all.isEmpty else { throw WalkError("no assemblies in the root domain") }
        let ordered = all.filter { $0.name == preferredAssembly } + all.filter { $0.name != preferredAssembly }
        for (_, image) in ordered {
            for klass in classes(in: image)
            where className(klass) == name && (classNamespace(klass) ?? "") == namespace {
                classCache[key] = klass
                return klass
            }
        }
        throw WalkError("class \(name) not found")
    }

    /// Fields declared by `klass` and its parents. Generic instances use their definition's
    /// field list, as unity-spy does (fine for reference-typed or int fields).
    public func fields(of klass: UInt64) -> [Field] {
        if let cached = fieldCache[klass] { return cached }
        var result: [Field] = []
        var current: UInt64? = klass
        var depth = 0
        while let level = current, depth < 32 {
            depth += 1
            var declaring = level
            if let kind = memory.u8(level &+ UInt64(offsets.classKind)), kind & 0x7 == 3,
               let generic = memory.pointer(level &+ UInt64(offsets.classGenericClass)),
               let definition = memory.pointer(generic) {
                declaring = definition
            }
            if let first = memory.pointer(declaring &+ UInt64(offsets.classFields)),
               let count = memory.i32(declaring &+ UInt64(offsets.classFieldCount)), count > 0, count < 4096 {
                for index in 0..<Int(count) {
                    let field = first &+ UInt64(index * offsets.fieldSize)
                    guard let type = memory.pointer(field),
                          let namePointer = memory.pointer(field &+ UInt64(offsets.fieldName)),
                          let name = memory.cString(namePointer),
                          let offset = memory.i32(field &+ UInt64(offsets.fieldOffset)) else { continue }
                    let attrs = memory.u16(type &+ UInt64(offsets.typeAttrs)) ?? 0
                    result.append(Field(name: name, offset: Int(offset), isStatic: attrs & 0x10 != 0))
                }
            }
            current = memory.pointer(level &+ UInt64(offsets.classParent))
        }
        fieldCache[klass] = result
        return result
    }

    func field(_ name: String, of klass: UInt64, isStatic: Bool) throws -> Field {
        guard let field = fields(of: klass).first(where: { $0.name == name && $0.isStatic == isStatic }) else {
            throw WalkError("field \(name) not found")
        }
        return field
    }

    /// Pointer stored in a static reference field (e.g. a singleton's `s_instance`).
    public func staticPointer(_ fieldName: String, of klass: UInt64) throws -> UInt64 {
        let field = try field(fieldName, of: klass, isStatic: true)
        guard let runtimeInfo = memory.pointer(klass &+ UInt64(offsets.classRuntimeInfo)),
              let vtable = memory.pointer(runtimeInfo &+ UInt64(offsets.runtimeInfoDomainVTables)),
              let slots = memory.i32(klass &+ UInt64(offsets.classVTableSize)), slots >= 0, slots < 100_000,
              let staticData = memory.pointer(vtable &+ UInt64(offsets.vtableSlots + Int(slots) * 8)) else {
            throw WalkError("static data unavailable")
        }
        guard let value = memory.pointer(staticData &+ UInt64(field.offset)) else {
            throw WalkError("\(fieldName) is null")
        }
        return value
    }

    /// The runtime class of a managed object (object -> vtable -> klass).
    public func classOf(object: UInt64) -> UInt64? {
        memory.pointer(object).flatMap { memory.pointer($0) }
    }

    /// Address of an instance field inside `object`.
    public func fieldAddress(_ name: String, in object: UInt64) throws -> UInt64 {
        guard let klass = classOf(object: object) else { throw WalkError("object has no class") }
        return object &+ UInt64(try field(name, of: klass, isStatic: false).offset)
    }

    public func pointerField(_ name: String, in object: UInt64) throws -> UInt64? {
        memory.pointer(try fieldAddress(name, in: object))
    }

    public func intField(_ name: String, in object: UInt64) throws -> Int32? {
        memory.i32(try fieldAddress(name, in: object))
    }

    public func hasField(_ name: String, in object: UInt64) -> Bool {
        (try? fieldAddress(name, in: object)) != nil
    }

    /// A System.String object as Swift text (capped at 256 UTF-16 units).
    public func string(at object: UInt64) -> String? {
        guard let length = memory.i32(object &+ UInt64(offsets.stringLength)), length >= 0, length <= 256 else { return nil }
        guard length > 0 else { return "" }
        guard let bytes = memory.read(object &+ UInt64(offsets.stringChars), Int(length) * 2) else { return nil }
        let units = stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
        return String(decoding: units, as: UTF16.self)
    }

    /// Length and first element address of a managed array.
    public func array(at object: UInt64) -> (count: Int, data: UInt64)? {
        guard let length = memory.u64(object &+ UInt64(offsets.arrayLength)), length < 100_000 else { return nil }
        return (Int(length), object &+ UInt64(offsets.arrayData))
    }
}

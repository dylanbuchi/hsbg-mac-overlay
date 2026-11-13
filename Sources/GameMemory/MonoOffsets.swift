/// Byte offsets into Unity's Mono runtime structures (64-bit).
///
/// Starting values come from Firestone's unity-spy (MIT, Zero-to-Heroes/unity-spy-.net4.5,
/// `Unity6000_3_x64_PE_Offsets`, itself built on hackf5/unityspy, MIT). That table was validated on
/// Windows; this project validated it again on macOS arm64 against the running game (see
/// docs/own-reader-feasibility.md and NOTICE). The few extra entries (assembly name, class image,
/// MonoClassField, MonoString/MonoArray/MonoObject headers) follow the public Mono layouts.
public struct MonoOffsets: Sendable, Equatable {
    // MonoDomain / MonoAssembly
    public var domainAssemblies = 176      // MonoDomain.domain_assemblies (GSList*); Windows table says 160
    public var assemblyName = 16           // MonoAssembly.aname.name (char*)
    public var assemblyImage = 96          // MonoAssembly.image

    // MonoImage.class_cache (MonoInternalHashTable)
    public var imageClassCache = 1232
    public var hashTableSize = 24
    public var hashTableTable = 32

    // MonoClass and friends
    public var classKind = 27              // low 3 bits: 1 def, 2 generic definition, 3 generic instance
    public var classParent = 40
    public var classImage = 56
    public var className = 64
    public var classNamespace = 72
    public var classVTableSize = 84
    public var classFields = 144           // MonoClassField*
    public var classRuntimeInfo = 200
    public var classGenericClass = 232     // MonoClassGenericInst.generic_class
    public var classFieldCount = 248       // MonoClassDef.field_count
    public var classNextCache = 256        // MonoClassDef.next_class_cache
    public var runtimeInfoDomainVTables = 8
    public var vtableSlots = 72            // MonoVTable.vtable[]; static data pointer follows the slots

    // MonoClassField: type, name, parent, offset
    public var fieldSize = 32
    public var fieldName = 8
    public var fieldOffset = 24
    public var typeAttrs = 8               // MonoType.attrs (u16), FIELD_ATTRIBUTE_STATIC = 0x10

    // Managed objects
    public var stringLength = 16
    public var stringChars = 20
    public var arrayLength = 24
    public var arrayData = 32

    public init() {}

    /// Unity 6000.3 (Hearthstone 37.x), 64-bit.
    public static let unity6000_3 = MonoOffsets()
}

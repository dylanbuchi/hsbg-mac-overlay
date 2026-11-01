// THROWAWAY feasibility spike (not part of the app package). READ-ONLY.
// Reads the Battlegrounds leaderboard hover data (per-player race counts) from the Hearthstone
// process through HearthMirror's own exported C++ Mono reader (inside /Applications/HSTracker.app).
// Never writes to the game, never suspends it, one pass per run.
//
//   spike/build.sh && spike/build/tribe_spike --selfcheck   # no game needed: resolves symbols only
//   spike/build/tribe_spike                                 # during a Battlegrounds game
//
// Layout facts used (reverse-engineered from the arm64 slice, HSTracker 2026-10, see docs):
//   HearthMirror (ObjC) ivar _mirror -> hearthmirror::Mirror*; *(void**)mirror -> impl; impl+8 -> MonoImage*
//   MonoValue: 0x60 bytes; int32 type tag at +0; array: element ptr at +0x48, count (uint32) at +0x58
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <string>
#include <vector>
#include <map>

struct MV { alignas(8) unsigned char b[0x60]; };       // opaque hearthmirror::MonoValue, leaked on purpose
using Path = std::vector<std::string>;
using GetObjectFn = MV (*)(const Path &, void *image);
using IndexFn = MV (*)(MV *self, const char *name);     // MonoValue::operator[](char const*)
using IntFn = long (*)(MV *);                           // hearthmirror::intValue(MonoValue&)
using EmptyFn = bool (*)(const MV *);                   // hearthmirror::IsMonoValueEmpty

static GetObjectFn getObject; static IndexFn idx; static IntFn intValue; static EmptyFn isEmpty;

static const char *FW = "/Applications/HSTracker.app/Contents/Frameworks/HearthMirror.framework/Versions/A/HearthMirror";

static bool resolve() {
    void *h = dlopen(FW, RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return false; }
    getObject = (GetObjectFn)dlsym(h, "_ZN12hearthmirror9getObjectERKNSt3__16vectorINS0_12basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEENS5_IS7_EEEEPNS_9MonoImageE");
    idx = (IndexFn)dlsym(h, "_ZN12hearthmirror9MonoValueixEPKc");
    intValue = (IntFn)dlsym(h, "_ZN12hearthmirror8intValueERNS_9MonoValueE");
    isEmpty = (EmptyFn)dlsym(h, "_ZN12hearthmirror16IsMonoValueEmptyERKNS_9MonoValueE");
    printf("symbols: getObject=%p operator[]=%p intValue=%p IsMonoValueEmpty=%p\n", (void*)getObject, (void*)idx, (void*)intValue, (void*)isEmpty);
    return getObject && idx && intValue && isEmpty;
}

static MV sub(MV *v, const char *n) { return idx(v, n); }
static bool empty(MV &v) { return isEmpty(&v); }
static uint32_t arrCount(MV &v) { return *(uint32_t *)(v.b + 0x58); }
static MV *arrAt(MV &v, uint32_t i) { return (MV *)(*(unsigned char **)(v.b + 0x48) + (size_t)i * 0x60); }
static long num(MV &v) { return intValue(&v); }

// System.Collections.Generic.List<T> -> element pointers (into the leaked array)
static std::vector<MV *> listItems(MV &list) {
    std::vector<MV *> out;
    if (empty(list)) return out;
    MV size = sub(&list, "_size"); MV items = sub(&list, "_items");
    if (empty(items)) return out;
    long n = num(size); uint32_t cap = arrCount(items);
    for (long i = 0; i < n && i < (long)cap; i++) out.push_back(arrAt(items, (uint32_t)i));
    return out;
}

static const std::map<int, const char *> RACES = {
    {11,"UNDEAD"},{14,"MURLOC"},{15,"DEMON"},{17,"MECH"},{18,"ELEMENTAL"},{20,"BEAST"},{23,"PIRATE"},
    {24,"DRAGON"},{26,"ALL"},{43,"QUILBOAR"},{92,"NAGA"},{126,"ABERRATION"}};

int main(int argc, char **argv) {
    @autoreleasepool {
        bool selfcheck = argc > 1 && std::string(argv[1]) == "--selfcheck";
        if (!resolve()) { fprintf(stderr, "KILL: HearthMirror C++ symbols not resolvable\n"); return 2; }
        if (selfcheck) { puts("selfcheck OK (no process touched)"); return 0; }

        pid_t pid = 0;
        for (NSRunningApplication *a in NSWorkspace.sharedWorkspace.runningApplications)
            if ([a.localizedName isEqualToString:@"Hearthstone"] || [a.bundleURL.lastPathComponent isEqualToString:@"Hearthstone.app"]) pid = a.processIdentifier;
        if (!pid) { puts("Hearthstone is not running: nothing to read. Run during a Battlegrounds game."); return 3; }

        Class cls = NSClassFromString(@"HearthMirror");
        id obj = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("alloc"));
        obj = ((id (*)(id, SEL, pid_t, BOOL))objc_msgSend)(obj, sel_registerName("initWithPID:withBlocking:"), pid, NO);
        if (!obj) { puts("KILL?: initWithPID returned nil (task_for_pid denied: needs debugger entitlement / dev-tools approval)"); return 4; }
        Ivar iv = class_getInstanceVariable(cls, "_mirror");
        void *mirror = *(void **)((char *)(__bridge void *)obj + ivar_getOffset(iv));
        void *impl = mirror ? *(void **)mirror : nullptr;
        void *image = impl ? *(void **)((char *)impl + 8) : nullptr;
        printf("pid=%d mirror=%p impl=%p image=%p\n", pid, mirror, impl, image);
        if (!image) { puts("no MonoImage yet (game still loading?)"); return 5; }

        MV teams = getObject({"PlayerLeaderboardManager", "s_instance", "m_teams"}, image);
        if (empty(teams)) { puts("m_teams empty/unresolved (not in a Battlegrounds game, or path broke)"); return 6; }
        printf("%-10s %-12s %s\n", "entityId", "heroCardId?", "races (id:count)");
        for (MV *team : listItems(teams)) {
            MV cards = sub(team, "m_playerLeaderboardCards");
            for (MV *card : listItems(cards)) {
                MV hero = sub(card, "m_playerHeroEntity");
                if (empty(hero)) continue;
                long eid = -1;
                MV tags = sub(&hero, "m_tags"); MV values = sub(&tags, "m_values");
                MV count = sub(&values, "_count"); MV entries = sub(&values, "_entries");
                for (long i = 0; !empty(entries) && i < num(count) && i < (long)arrCount(entries); i++) {
                    MV *e = arrAt(entries, (uint32_t)i);
                    MV k = sub(e, "key"); if (num(k) == 53) { MV v = sub(e, "value"); eid = num(v); break; }
                }
                std::string races;
                MV overlay = sub(card, "m_overlay");
                if (!empty(overlay)) {
                    MV rc = sub(&overlay, "m_raceCounts");
                    if (!empty(rc)) {
                        MV touched = sub(&rc, "touchedSlots"), links = sub(&rc, "linkSlots");
                        MV keys = sub(&rc, "keySlots"), vals = sub(&rc, "valueSlots");
                        for (long i = 0; i < num(touched); i++) {
                            MV *l = arrAt(links, (uint32_t)i);
                            MV hc = sub(l, "HashCode");
                            long h = num(hc);
                            if (h >= 0) continue;                                    // HASH_FLAG (top bit) set = slot in use
                            int race = (int)(h & 0x7FFFFFFF);                        // enum hash == value
                            MV *vv = arrAt(vals, (uint32_t)i);
                            auto it = RACES.find(race);
                            races += (it != RACES.end() ? std::string(it->second) : std::to_string(race));
                            races += ":" + std::to_string(num(*vv)) + " ";
                        }
                    }
                }
                printf("%-10ld %-12s %s\n", eid, "-", races.empty() ? "(no counts yet)" : races.c_str());
            }
        }
    }
    return 0;
}

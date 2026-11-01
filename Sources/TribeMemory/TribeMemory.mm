// Layout facts (reverse-engineered from the arm64 slice of HearthMirror, see docs/tribe-memory-design.md):
//   HearthMirror (ObjC) ivar _mirror -> hearthmirror::Mirror*; *(void**)mirror -> impl; impl+8 -> MonoImage*
//   MonoValue: 0x60 bytes; an array keeps its element pointer at +0x48 and its element count (uint32) at +0x58.
// Every step is bounds-checked and any mismatch ends the read with a reason instead of dereferencing blindly.
#import "TribeMemory.h"

#include <dlfcn.h>
#include <objc/runtime.h>
#include <string>
#include <vector>

#if defined(__arm64__)

namespace {

struct MV { alignas(8) unsigned char b[0x60]; };   // opaque hearthmirror::MonoValue; leaked on purpose (shared state inside)
using Path = std::vector<std::string>;
using GetObjectFn = MV (*)(const Path &, void *);
using IndexFn = MV (*)(MV *, const char *);
using IntFn = long (*)(MV *);
using EmptyFn = bool (*)(const MV *);
using ArrayFn = bool (*)(const MV *);

struct Api {
    GetObjectFn getObject; IndexFn index; IntFn intValue; EmptyFn isEmpty; ArrayFn isArray;
};

struct Failure { std::string reason; };

const int kMaxTeams = 16, kMaxCards = 16, kMaxTags = 4096, kMaxSlots = 256;

class Reader {
public:
    explicit Reader(const Api &api) : api_(api) {}

    MV sub(MV *v, const char *name) { return api_.index(v, name); }
    bool empty(MV &v) { return api_.isEmpty(&v); }
    long num(MV &v) { return api_.intValue(&v); }

    uint32_t count(MV &array) { return *(uint32_t *)(array.b + 0x58); }
    MV *at(MV &array, uint32_t i, const char *what) {
        unsigned char *base = *(unsigned char **)(array.b + 0x48);
        if (!api_.isArray(&array) || !base || i >= count(array)) throw Failure{std::string("bad array ") + what};
        return (MV *)(base + (size_t)i * 0x60);
    }

    // System.Collections.Generic.List<T>: _size + _items
    std::vector<MV *> list(MV &v, int limit, const char *what) {
        std::vector<MV *> out;
        if (empty(v)) return out;
        MV size = sub(&v, "_size"), items = sub(&v, "_items");
        long n = num(size);
        if (n < 0 || n > limit) throw Failure{std::string("implausible size of ") + what};
        if (n == 0) return out;
        if (empty(items)) throw Failure{std::string("no items in ") + what};
        for (long i = 0; i < n; i++) out.push_back(at(items, (uint32_t)i, what));
        return out;
    }

private:
    Api api_;
};

}  // namespace

@implementation HSBGTribeMemory

+ (nullable NSDictionary<NSNumber *, NSDictionary<NSNumber *, NSNumber *> *> *)readWithFramework:(void *)framework
                                                                                           mirror:(id)mirror
                                                                                            error:(NSString **)error {
    auto fail = ^NSDictionary *(NSString *reason) { if (error) *error = reason; return nil; };
    try {
        Api api;
        api.getObject = (GetObjectFn)dlsym(framework, "_ZN12hearthmirror9getObjectERKNSt3__16vectorINS0_12basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEENS5_IS7_EEEEPNS_9MonoImageE");
        api.index = (IndexFn)dlsym(framework, "_ZN12hearthmirror9MonoValueixEPKc");
        api.intValue = (IntFn)dlsym(framework, "_ZN12hearthmirror8intValueERNS_9MonoValueE");
        api.isEmpty = (EmptyFn)dlsym(framework, "_ZN12hearthmirror16IsMonoValueEmptyERKNS_9MonoValueE");
        api.isArray = (ArrayFn)dlsym(framework, "_ZN12hearthmirror16IsMonoValueArrayERKNS_9MonoValueE");
        if (!api.getObject || !api.index || !api.intValue || !api.isEmpty || !api.isArray) return fail(@"HearthMirror symbols missing");

        Ivar ivar = class_getInstanceVariable([mirror class], "_mirror");
        if (!ivar) return fail(@"HearthMirror layout changed (_mirror)");
        void *cppMirror = *(void **)((char *)(__bridge void *)mirror + ivar_getOffset(ivar));
        void *impl = cppMirror ? *(void **)cppMirror : nullptr;
        void *image = impl ? *(void **)((char *)impl + 8) : nullptr;
        if (!image) return fail(@"game memory not attached yet");

        Reader r(api);
        MV teams = api.getObject({"PlayerLeaderboardManager", "s_instance", "m_teams"}, image);
        if (r.empty(teams)) return fail(@"no leaderboard in memory");

        NSMutableDictionary<NSNumber *, NSDictionary<NSNumber *, NSNumber *> *> *result = [NSMutableDictionary dictionary];
        for (MV *team : r.list(teams, kMaxTeams, "m_teams")) {
            MV cards = r.sub(team, "m_playerLeaderboardCards");
            for (MV *card : r.list(cards, kMaxCards, "m_playerLeaderboardCards")) {
                MV hero = r.sub(card, "m_playerHeroEntity");
                if (r.empty(hero)) continue;
                MV tags = r.sub(&hero, "m_tags");
                MV values = r.sub(&tags, "m_values");
                MV entryCount = r.sub(&values, "_count"), entries = r.sub(&values, "_entries");
                long n = r.num(entryCount);
                if (n < 0 || n > kMaxTags) return fail(@"implausible tag count");
                long entityID = -1;
                for (long i = 0; i < n && !r.empty(entries); i++) {
                    MV *e = r.at(entries, (uint32_t)i, "tags");
                    MV key = r.sub(e, "key");
                    if (r.num(key) == 53) {                 // GAME_TAG.ENTITY_ID, the key Power.log entities use
                        MV value = r.sub(e, "value");
                        entityID = r.num(value);
                        break;
                    }
                }
                if (entityID <= 0) continue;

                NSMutableDictionary<NSNumber *, NSNumber *> *races = [NSMutableDictionary dictionary];
                MV overlay = r.sub(card, "m_overlay");
                if (!r.empty(overlay)) {
                    MV map = r.sub(&overlay, "m_raceCounts");
                    if (!r.empty(map)) {
                        MV touchedValue = r.sub(&map, "touchedSlots");
                        long touched = r.num(touchedValue);
                        if (touched < 0 || touched > kMaxSlots) return fail(@"implausible race map");
                        MV links = r.sub(&map, "linkSlots"), vals = r.sub(&map, "valueSlots");
                        for (long i = 0; i < touched; i++) {
                            MV hashValue = r.sub(r.at(links, (uint32_t)i, "linkSlots"), "HashCode");
                            uint32_t hash = (uint32_t)r.num(hashValue);
                            if (!(hash & 0x80000000u)) continue;            // top bit marks a used slot
                            long count = r.num(*r.at(vals, (uint32_t)i, "valueSlots"));
                            if (count < 0 || count > 1000) return fail(@"implausible race count");
                            races[@(hash & 0x7FFFFFFFu)] = @(count);        // the hash of an enum key is its value
                        }
                    }
                }
                result[@(entityID)] = races;
            }
        }
        if (result.count == 0) return fail(@"leaderboard has no players yet");
        return result;
    } catch (const Failure &f) {
        return fail([NSString stringWithUTF8String:f.reason.c_str()]);
    } catch (...) {
        return fail(@"HearthMirror read failed");
    }
}

@end

#else

@implementation HSBGTribeMemory
+ (nullable NSDictionary<NSNumber *, NSDictionary<NSNumber *, NSNumber *> *> *)readWithFramework:(void *)framework
                                                                                           mirror:(id)mirror
                                                                                            error:(NSString **)error {
    if (error) *error = @"live tribe counts need Apple silicon";
    return nil;
}
@end

#endif

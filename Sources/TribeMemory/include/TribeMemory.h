#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads the leaderboard hover data (per-player minion type counts) that the game keeps in memory,
/// through the Mono path reader HearthMirror already exports. Strictly read-only: it calls
/// HearthMirror's own read functions and never writes to, suspends or signals the game.
@interface HSBGTribeMemory : NSObject

/// `framework` is the dlopen handle of HearthSim's HearthMirror, `mirror` an initialised `HearthMirror`
/// instance (the same one that serves the lobby). Returns hero entity id -> (race id -> count), or nil
/// with a short reason in `error` when anything about the layout is not as expected.
+ (nullable NSDictionary<NSNumber *, NSDictionary<NSNumber *, NSNumber *> *> *)readWithFramework:(void *)framework
                                                                                           mirror:(id)mirror
                                                                                            error:(NSString *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

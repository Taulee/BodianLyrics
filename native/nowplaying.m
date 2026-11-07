// 通过 MediaRemote 读取波点自己的会话，不依赖系统当前选中的播放器。
// 由系统 Perl 加载，以取得 MediaRemote 会话数据。

#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <dispatch/dispatch.h>

typedef void (*GetClientsFn)(dispatch_queue_t, void (^)(NSArray *));
typedef void (*GetInfoForClientFn)(void *, void *, long, dispatch_queue_t, void (^)(CFDictionaryRef));
// client、origin、queue、callback;播放状态与元数据速率是独立的系统读数。
typedef void (*GetPlaybackStateForClientFn)(void *, void *, dispatch_queue_t, void (^)(uint32_t));
/// 等待客户端列表和单个会话数据的上限。外层查询还有两秒总时限。
static const int64_t kStateWaitMs = 900;
/// 元数据返回后，再等播放状态的最长时间。
static const int64_t kStateAfterInfoWaitMs = 150;
static const long kIncludeArtwork = 1;
static const long kNoArtwork = 0;

static NSString *K(const char *suffix) {
    return [NSString stringWithFormat:@"kMRMediaRemoteNowPlayingInfo%s", suffix];
}

/// 没读到播放状态(接口取不到、没按时回话)。
static const uint32_t kStateUnavailable = UINT32_MAX;

/// 播放状态与 PlaybackRate 独立。暂停时即使速率残留，进度也不外推。
static BOOL playingFor(uint32_t state, NSNumber *rate) {
    BOOL advancing = rate.doubleValue > 0;
    switch (state) {
        case 1: return rate == nil || advancing;
        case 2:
        case 3:
        case 4: return NO;
        default: return advancing;
    }
}

static NSDictionary *normalize(NSDictionary *raw, NSNumber *playing) {
    if (raw.count == 0) return nil;
    NSNumber *elapsed = raw[K("ElapsedTime")];
    NSNumber *rate = raw[K("PlaybackRate")];
    NSDate *stamp = raw[K("Timestamp")];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (raw[K("Title")]) out[@"title"] = raw[K("Title")];
    if (raw[K("Artist")]) out[@"artist"] = raw[K("Artist")];
    if (raw[K("Album")]) out[@"album"] = raw[K("Album")];
    if (raw[K("Duration")]) out[@"duration"] = raw[K("Duration")];
    if (rate) out[@"playbackRate"] = rate;
    // 必须是 JSON 布尔值,Swift 的 JSONDecoder 不把数字 1/0 当 Bool。
    if (playing) out[@"playing"] = playing.boolValue ? @YES : @NO;
    if (elapsed) out[@"anchorElapsedTime"] = elapsed;
    if (stamp) out[@"timestamp"] = @([stamp timeIntervalSince1970]);
    // 封面:载荷里是原始 JPEG/PNG 字节,走 base64 过 JSON(与 media-control 的 artworkData 同形)。
    NSData *art = raw[K("ArtworkData")];
    if ([art isKindOfClass:NSData.class] && art.length > 0) {
        out[@"artworkData"] = [art base64EncodedStringWithOptions:0];
    }
    return out;
}

/// 元数据和播放状态并行读取，封面查询只请求元数据。
static NSDictionary *clientSnapshot(id client, long artFlag,
                                    GetInfoForClientFn getInfo, GetPlaybackStateForClientFn getState,
                                    dispatch_time_t deadline, BOOL *stateStalled) {
    BOOL needsState = artFlag == kNoArtwork;
    BOOL askState = needsState && getState && !(stateStalled && *stateStalled);
    dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
    dispatch_semaphore_t infoDone = dispatch_semaphore_create(0);
    dispatch_semaphore_t stateDone = dispatch_semaphore_create(0);
    __block NSDictionary *info = nil;
    __block uint32_t state = kStateUnavailable;
    getInfo((__bridge void *)client, NULL, artFlag, queue, ^(CFDictionaryRef raw) {
        if (raw) info = [(__bridge NSDictionary *)raw copy];
        dispatch_semaphore_signal(infoDone);
    });
    if (askState) {
        getState((__bridge void *)client, NULL, queue, ^(uint32_t value) {
            state = value;
            dispatch_semaphore_signal(stateDone);
        });
    }
    if (dispatch_semaphore_wait(infoDone, deadline) != 0) return nil;
    uint32_t seen = kStateUnavailable;
    if (askState) {
        if (dispatch_semaphore_wait(stateDone, dispatch_time(DISPATCH_TIME_NOW, kStateAfterInfoWaitMs * NSEC_PER_MSEC)) == 0) {
            seen = state;
        } else if (stateStalled) {
            *stateStalled = YES;
        }
    }
    NSNumber *playing = needsState ? @(playingFor(seen, info[K("PlaybackRate")])) : nil;
    return normalize(info, playing);
}

static void emit(id obj) {
    NSData *d = obj ? [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL] : nil;
    if (d) {
        fwrite(d.bytes, 1, d.length, stdout);
    } else {
        fputs("null", stdout);
    }
    fputc('\n', stdout);
    fflush(stdout);
}

void nowplaying_clients(void *my_perl, void *cv) {
    @autoreleasepool {
        const char *want = "cn.wenyu.bodian.bodianPc";
        const char *artEnv = getenv("BODIAN_LYRICS_ARTWORK");
        const long artFlag = (artEnv && artEnv[0] == '1') ? kIncludeArtwork : kNoArtwork;
        void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!h) { emit(nil); return; }
        GetClientsFn getClients = (GetClientsFn)dlsym(h, "MRMediaRemoteGetNowPlayingClients");
        GetInfoForClientFn getInfo = (GetInfoForClientFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfoForClient");
        GetPlaybackStateForClientFn getState = (GetPlaybackStateForClientFn)dlsym(h, "MRMediaRemoteGetPlaybackStateForClient");
        if (!getClients || !getInfo) { emit(nil); return; }

        dispatch_semaphore_t s = dispatch_semaphore_create(0);
        __block NSArray *clients = nil;
        getClients(dispatch_get_global_queue(0, 0), ^(NSArray *cs) {
            clients = cs;
            dispatch_semaphore_signal(s);
        });
        if (dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, kStateWaitMs * NSEC_PER_MSEC)) != 0) {
            emit(nil); return;
        }

        NSMutableArray *all = [NSMutableArray array];
        BOOL stateStalled = NO;
        for (id c in clients) {
            id bidObj = ((id (*)(id, SEL))objc_msgSend)(c, sel_getUid("bundleIdentifier"));
            NSString *bid = [bidObj isKindOfClass:NSString.class] ? bidObj : nil;
            if (want && (!bid || strcmp(bid.UTF8String, want) != 0)) continue;
            NSDictionary *one = clientSnapshot(c, artFlag, getInfo, getState,
                                              dispatch_time(DISPATCH_TIME_NOW, kStateWaitMs * NSEC_PER_MSEC), &stateStalled);
            if (one) [all addObject:one];
        }
        emit(want ? (all.firstObject ?: (id)nil) : all);
    }
}

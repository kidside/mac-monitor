// Sidecar is private: keep it in a short-lived, unprivileged process so a
// framework failure cannot take down the menu bar app or block its UI.
#import <Foundation/Foundation.h>
#import <dlfcn.h>

@protocol MMSidecarDevice <NSObject>
- (id)identifier;
- (id)name;
- (id)model;
- (BOOL)offersAdditionalDisplay;
- (BOOL)isRealityDevice;
@end
@protocol MMSidecarConfig <NSObject>
- (id)displayID;
@end
@protocol MMSidecarManager <NSObject>
+ (id)sharedManager;
- (id)devices;
- (id)connectedDevices;
- (id)configForDevice:(id)device;
- (void)connectToDevice:(id)device completion:(void (^)(NSError *))completion;
- (void)disconnectFromDevice:(id)device completion:(void (^)(NSError *))completion;
@end

static void MMReply(BOOL supported, NSString *error, NSArray *devices) {
    NSDictionary *reply = @{ @"supported": @(supported), @"error": error ?: @"", @"devices": devices ?: @[] };
    NSData *data = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
    if (data) { fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout); }
}
static NSString *MMDeviceID(id<MMSidecarDevice> device) {
    if (![device respondsToSelector:@selector(identifier)]) return nil;
    id value = [device identifier];
    if ([value isKindOfClass:NSUUID.class]) value = [value UUIDString];
    return [value isKindOfClass:NSString.class] && [value length] > 0 && [value length] <= 1024 ? value : nil;
}
static BOOL MMIsIPad(id<MMSidecarDevice> device) {
    if (![device respondsToSelector:@selector(name)] || ![device respondsToSelector:@selector(model)]) return NO;
    if ([device respondsToSelector:@selector(isRealityDevice)] && [device isRealityDevice]) return NO;
    if ([device respondsToSelector:@selector(offersAdditionalDisplay)] && ![device offersAdditionalDisplay]) return NO;
    id model = [device model];
    return [model isKindOfClass:NSString.class] && [model hasPrefix:@"iPad"];
}
static NSArray *MMDevices(id<MMSidecarManager> manager, NSSet **connectedOut) {
    id available = [manager devices], connected = [manager connectedDevices];
    if (![available isKindOfClass:NSArray.class] || ![connected isKindOfClass:NSArray.class]) return nil;
    NSMutableSet *connectedIDs = [NSMutableSet set];
    for (id device in connected) { NSString *key = MMDeviceID(device); if (key) [connectedIDs addObject:key]; }
    *connectedOut = connectedIDs;
    NSMutableDictionary *byID = [NSMutableDictionary dictionary];
    for (id device in [available arrayByAddingObjectsFromArray:connected]) {
        NSString *key = MMDeviceID(device);
        if (key && MMIsIPad(device)) byID[key] = device;
        if (byID.count >= 64) break;
    }
    return byID.allValues;
}
static NSArray *MMRecords(id<MMSidecarManager> manager, NSArray *devices, NSSet *connected) {
    NSMutableArray *rows = [NSMutableArray array];
    for (id<MMSidecarDevice> device in devices) {
        NSString *key = MMDeviceID(device);
        id name = [device name];
        if (!key || ![name isKindOfClass:NSString.class]) continue;
        unsigned int displayID = 0;
        if ([connected containsObject:key] && [manager respondsToSelector:@selector(configForDevice:)]) {
            id<MMSidecarConfig> config = [manager configForDevice:device];
            if ([config respondsToSelector:@selector(displayID)]) {
                id value = [config displayID];
                if ([value isKindOfClass:NSNumber.class] && [value unsignedLongLongValue] <= UINT32_MAX) displayID = [value unsignedIntValue];
            }
        }
        [rows addObject:@{@"id":key, @"name":[name substringToIndex:MIN([name length], 256)],
                         @"connected":@([connected containsObject:key]), @"displayID":@(displayID)}];
    }
    return rows;
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc < 2 || argc > 3) return 64;
    NSString *command = [NSString stringWithUTF8String:argv[1]];
    BOOL scan = [command isEqualToString:@"devices"];
    if ((!scan && ![command isEqualToString:@"connect"] && ![command isEqualToString:@"disconnect"]) ||
        (scan ? argc != 2 : argc != 3)) return 64;
    NSString *target = argc == 3 ? [NSString stringWithUTF8String:argv[2]] : nil;
    if (!scan && (target.length == 0 || target.length > 1024)) return 64;
    @try {
        if (!dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY | RTLD_LOCAL)) {
            MMReply(NO, @"unsupported", nil); return 0;
        }
        Class cls = NSClassFromString(@"SidecarDisplayManager");
        if (![cls respondsToSelector:NSSelectorFromString(@"sharedManager")]) { MMReply(NO, @"unsupported", nil); return 0; }
        id<MMSidecarManager> manager = [(Class<MMSidecarManager>)cls sharedManager];
        for (NSString *name in @[@"devices", @"connectedDevices", @"connectToDevice:completion:", @"disconnectFromDevice:completion:"]) {
            if (![manager respondsToSelector:NSSelectorFromString(name)]) { MMReply(NO, @"unsupported", nil); return 0; }
        }
        NSSet *connected;
        NSArray *devices = MMDevices(manager, &connected);
        if (!devices) { MMReply(NO, @"unsupported", nil); return 0; }
        if (scan) { MMReply(YES, nil, MMRecords(manager, devices, connected)); return 0; }
        id selected = nil;
        for (id device in devices) if ([MMDeviceID(device) isEqualToString:target]) { selected = device; break; }
        if (!selected) { MMReply(YES, @"unavailable", MMRecords(manager, devices, connected)); return 0; }
        BOOL connect = [command isEqualToString:@"connect"];
        if ([connected containsObject:target] == connect) { MMReply(YES, nil, MMRecords(manager, devices, connected)); return 0; }
        // Do not replace an existing Sidecar session without an explicit disconnect.
        if (connect && connected.count > 0) { MMReply(YES, @"other-connected", MMRecords(manager, devices, connected)); return 0; }
        __block BOOL finished = NO;
        __block NSString *failure = nil;
        void (^completion)(NSError *) = ^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure = error ? @"connection-failed" : nil;
                finished = YES;
            });
        };
        if (connect) [manager connectToDevice:selected completion:completion];
        else [manager disconnectFromDevice:selected completion:completion];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
        while (!finished && deadline.timeIntervalSinceNow > 0) {
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        // The app verifies the reported state; a successful callback alone is
        // not treated as a connected display. Never write resolution or scale.
        devices = MMDevices(manager, &connected);
        MMReply(YES, finished ? failure : @"timeout", MMRecords(manager, devices ?: @[], connected ?: [NSSet set]));
    } @catch (NSException *exception) { MMReply(NO, @"unsupported", nil); }
    return 0;
}}

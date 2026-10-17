#import "MonitorBridge.h"
#import <dlfcn.h>
#import "ModeDescriptor.h"
#import <Security/Security.h>
#import <IOKit/IOKitLib.h>

// Private APIs are resolved at runtime. Missing symbols disable the feature.
static void *MMCoreDisplay(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY); });
    return handle;
}
static void *MMSkyLight(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY); });
    return handle;
}
typedef CGError (*MMEnableFunction)(CGDisplayConfigRef, CGDirectDisplayID, bool);
static MMEnableFunction MMEnable(void) {
    void *handle = MMSkyLight();
    return handle ? (MMEnableFunction)dlsym(handle, "CGSConfigureDisplayEnabled") : NULL;
}
BOOL MMCanSetEnabled(void) { return MMEnable() != NULL; }
int MMLidState(void) {
    io_service_t root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (!root) return -1;
    CFTypeRef value = IORegistryEntryCreateCFProperty(root, CFSTR("AppleClamshellState"), kCFAllocatorDefault, 0);
    IOObjectRelease(root);
    if (!value) return -1;
    int state = CFGetTypeID(value) == CFBooleanGetTypeID() ? (CFBooleanGetValue(value) ? 1 : 0) : -1;
    CFRelease(value);
    return state;
}
CGError MMSetEnabled(CGDirectDisplayID display, BOOL enabled) {
    // This also protects recovery/watchdog callers and delayed retries.
    if (CGDisplayIsBuiltin(display) && MMLidState() != 0) return kCGErrorInvalidOperation;
    MMEnableFunction function = MMEnable();
    if (!function) return kCGErrorNotImplemented;
    CGDisplayConfigRef config = NULL;
    CGError result = CGBeginDisplayConfiguration(&config);
    if (result != kCGErrorSuccess) return result;
    result = function(config, display, enabled);
    if (result != kCGErrorSuccess) { CGCancelDisplayConfiguration(config); return result; }
    return CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
}
NSString *MMDisplayName(CGDirectDisplayID display) {
    typedef CFDictionaryRef (*InfoFunction)(CGDirectDisplayID);
    void *handle = MMCoreDisplay();
    InfoFunction info = handle ? (InfoFunction)dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") : NULL;
    if (info) {
        NSDictionary *dict = CFBridgingRelease(info(display));
        id name = dict[@"DisplayProductName"];
        if ([name isKindOfClass:NSString.class]) return name;
        if ([name isKindOfClass:NSDictionary.class]) return name[@"en_US"] ?: [name allValues].firstObject ?: @"Màn hình ngoài";
    }
    return CGDisplayIsBuiltin(display) ? @"Màn hình MacBook" : @"Màn hình ngoài";
}
CGSize MMPanelPixelSize(CGDirectDisplayID display) {
    typedef CFDictionaryRef (*InfoFunction)(CGDirectDisplayID);
    void *handle = MMCoreDisplay();
    InfoFunction info = handle ? (InfoFunction)dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") : NULL;
    if (!info) return CGSizeZero;
    NSDictionary *dict = CFBridgingRelease(info(display));
    NSNumber *width = dict[@"kCGDisplayPixelWidth"], *height = dict[@"kCGDisplayPixelHeight"];
    if (![width isKindOfClass:NSNumber.class] || ![height isKindOfClass:NSNumber.class]) return CGSizeZero;
    if (width.intValue < 640 || height.intValue < 360 || width.intValue > 16384 || height.intValue > 16384) return CGSizeZero;
    return CGSizeMake(width.intValue, height.intValue);
}
NSArray<NSNumber *> *MMAllDisplays(void) {
    CGDirectDisplayID ids[64]; uint32_t count = 0;
    NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSet];
    if (CGGetOnlineDisplayList(64, ids, &count) == kCGErrorSuccess)
        for (uint32_t i = 0; i < count; i++) [result addObject:@(ids[i])];
    typedef CGError (*ListFunction)(uint32_t, CGDirectDisplayID *, uint32_t *);
    void *handle = MMSkyLight();
    ListFunction list = handle ? (ListFunction)dlsym(handle, "CGSGetDisplayList") : NULL;
    if (list && list(64, ids, &count) == kCGErrorSuccess)
        for (uint32_t i = 0; i < count; i++) [result addObject:@(ids[i])];
    return result.array;
}

@interface MMNativeMode ()
@property(nonatomic, readwrite) int32_t modeID;
@property(nonatomic, readwrite) NSInteger width, height, pixelWidth, pixelHeight;
@property(nonatomic, readwrite) double refreshRate;
@end
@implementation MMNativeMode
@end

static NSMutableSet<NSNumber *> *MMManagedVirtualIDs(void) {
    static NSMutableSet *ids; static dispatch_once_t once;
    dispatch_once(&once, ^{ ids = [NSMutableSet new]; });
    return ids;
}
static bool MMParseDisplayMode(CGDirectDisplayID display, uint8_t *bytes, int index, MMModeDetails *details) {
    if (MMParseHiDPIMode(bytes, MM_MODE_DESCRIPTOR_SIZE, index, details)) return true;
    // Synthesized scaled modes on our virtual surfaces use a distinct flag.
    // Permit only this exact variant, only for objects created by this process;
    // retain all bounds, density, index and refresh checks of the strict parser.
    uint32_t flags = 0; memcpy(&flags, bytes + 4, sizeof(flags));
    if (flags != 0x40000000 || ![MMManagedVirtualIDs() containsObject:@(display)]) return false;
    uint32_t valid = 1; memcpy(bytes + 4, &valid, sizeof(valid));
    return MMParseHiDPIMode(bytes, MM_MODE_DESCRIPTOR_SIZE, index, details);
}
typedef void (*MMModeCountFunction)(CGDirectDisplayID, int *);
typedef void (*MMModeDescriptionFunction)(CGDirectDisplayID, int, void *, int);
typedef void (*MMConfigureModeFunction)(CGDisplayConfigRef, CGDirectDisplayID, int);
static MMModeCountFunction MMModeCount(void) {
    return (MMModeCountFunction)dlsym(RTLD_DEFAULT, "CGSGetNumberOfDisplayModes");
}
static MMModeDescriptionFunction MMModeDescription(void) {
    return (MMModeDescriptionFunction)dlsym(RTLD_DEFAULT, "CGSGetDisplayModeDescriptionOfLength");
}
static MMConfigureModeFunction MMConfigureMode(void) {
    return (MMConfigureModeFunction)dlsym(RTLD_DEFAULT, "CGSConfigureDisplayMode");
}
NSArray<MMNativeMode *> *MMNativeHiDPIModes(CGDirectDisplayID display) {
    MMModeCountFunction countFunction = MMModeCount();
    MMModeDescriptionFunction describe = MMModeDescription();
    if (!countFunction || !describe || !MMConfigureMode()) return @[];
    int count = 0;
    countFunction(display, &count);
    if (count <= 0 || count > 4096) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        uint8_t bytes[MM_MODE_DESCRIPTOR_SIZE] = {};
        describe(display, i, bytes, sizeof(bytes));
        MMModeDetails details;
        if (!MMParseDisplayMode(display, bytes, i, &details)) continue;
        MMNativeMode *mode = [MMNativeMode new];
        mode.modeID = details.modeID;
        mode.width = details.width; mode.height = details.height;
        mode.pixelWidth = details.width * 2; mode.pixelHeight = details.height * 2;
        mode.refreshRate = details.refreshRate;
        [result addObject:mode];
    }
    return result;
}
MMNativeMode *MMCurrentHiDPIMode(CGDirectDisplayID display) {
    typedef void (*CurrentFunction)(CGDirectDisplayID, int *);
    CurrentFunction current = (CurrentFunction)dlsym(RTLD_DEFAULT, "CGSGetCurrentDisplayMode");
    if (!current) return nil;
    int modeID = -1; current(display, &modeID);
    if (modeID < 0 || modeID >= 4096 || !MMModeDescription()) return nil;
    uint8_t bytes[MM_MODE_DESCRIPTOR_SIZE] = {};
    MMModeDescription()(display, modeID, bytes, sizeof(bytes));
    MMModeDetails details;
    if (!MMParseDisplayMode(display, bytes, modeID, &details)) return nil;
    MMNativeMode *mode = [MMNativeMode new];
    mode.modeID = details.modeID; mode.width = details.width; mode.height = details.height;
    mode.pixelWidth = details.width * 2; mode.pixelHeight = details.height * 2; mode.refreshRate = details.refreshRate;
    return mode;
}
CGError MMConfigureHiDPIMode(CGDisplayConfigRef config, CGDirectDisplayID display, int32_t modeID) {
    MMConfigureModeFunction configure = MMConfigureMode();
    if (!configure) return kCGErrorNotImplemented;
    // Revalidate against the current output. Mode indices can change after a
    // reconnect, so never apply a stale or arbitrary saved numeric index.
    for (MMNativeMode *mode in MMNativeHiDPIModes(display)) {
        if (mode.modeID == modeID) { configure(config, display, modeID); return kCGErrorSuccess; }
    }
    return kCGErrorRangeCheck;
}

@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int maxPixelsWide, maxPixelsHigh;
@property(nonatomic) CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(nonatomic) unsigned int serialNum, productID, vendorID;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic, strong) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) unsigned int displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end
@implementation MMVirtualScreen {
    CGVirtualDisplay *_screen;
}
+ (BOOL)isSupported {
    return NSClassFromString(@"CGVirtualDisplay") && NSClassFromString(@"CGVirtualDisplayDescriptor") &&
           NSClassFromString(@"CGVirtualDisplayMode") && NSClassFromString(@"CGVirtualDisplaySettings");
}
- (instancetype)initWithPhysicalID:(CGDirectDisplayID)physical width:(unsigned int)width height:(unsigned int)height serial:(unsigned int)serial sizes:(NSArray<NSDictionary *> *)sizes refreshRates:(NSArray<NSNumber *> *)rates preferredRate:(double)preferredRate {
    self = [super init];
    if (!self || ![MMVirtualScreen isSupported] || width < 640 || height < 360 || width > 3840 || height > 3840 || sizes.count == 0 || sizes.count > 256 || rates.count == 0 || sizes.count * rates.count > 768) return nil;
    @try {
        CGVirtualDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        descriptor.queue = dispatch_get_main_queue();
        descriptor.name = [NSString stringWithFormat:@"Mac Monitor · %@", MMDisplayName(physical)];
        // This is a virtual Retina surface, not the physical panel. Keep its
        // advertised pixel density high enough at every logical size.
        descriptor.sizeInMillimeters = CGSizeMake(width * 2 * 25.4 / 220.0, height * 2 * 25.4 / 220.0);
        unsigned int maxWidth = width, maxHeight = height;
        for (NSDictionary *size in sizes) {
            unsigned int w = [size[@"width"] unsignedIntValue], h = [size[@"height"] unsignedIntValue];
            if (w < 640 || h < 360 || w > 3840 || h > 3840 || (uint64_t)w * h > 8294400) return nil;
            // The selected 2x size is the virtual panel's native size.
            // Larger maxima mark intermediate 2x modes invalid on macOS 27.
        }
        descriptor.maxPixelsWide = maxWidth * 2;
        descriptor.maxPixelsHigh = maxHeight * 2;
        descriptor.redPrimary = CGPointMake(0.64, 0.33);
        descriptor.greenPrimary = CGPointMake(0.30, 0.60);
        descriptor.bluePrimary = CGPointMake(0.15, 0.06);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        descriptor.vendorID = 0x4D4D;
        descriptor.productID = ((width * 131u + height * 17u + serial) & 0xffffu) | 1u;
        descriptor.serialNum = serial ?: 1;
        _screen = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!_screen) return nil;
        CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        settings.hiDPI = 1;
        // Backing pixel dimensions; WindowServer synthesizes 2x logical modes.
        if (!isfinite(preferredRate) || preferredRate < 24 || preferredRate > 240) return nil;
        NSMutableArray *modes = [NSMutableArray arrayWithObject:[[NSClassFromString(@"CGVirtualDisplayMode") alloc]
            initWithWidth:width * 2 height:height * 2 refreshRate:preferredRate]];
        for (NSDictionary *size in sizes) for (NSNumber *rate in rates) {
            if ([size[@"width"] unsignedIntValue] > width || [size[@"height"] unsignedIntValue] > height) continue;
            if (!isfinite(rate.doubleValue) || rate.doubleValue < 24 || rate.doubleValue > 240) return nil;
            if ([size[@"width"] unsignedIntValue] == width && [size[@"height"] unsignedIntValue] == height && fabs(rate.doubleValue - preferredRate) < 0.1) continue;
            [modes addObject:[[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                initWithWidth:[size[@"width"] unsignedIntValue] * 2
                height:[size[@"height"] unsignedIntValue] * 2 refreshRate:rate.doubleValue]];
        }
        settings.modes = modes;
        if (![_screen applySettings:settings]) return nil;
        [MMManagedVirtualIDs() addObject:@(_screen.displayID)];
    } @catch (NSException *exception) {
        NSLog(@"Virtual display unavailable: %@", exception.reason);
        return nil;
    }
    return self;
}
- (void)dealloc { if (_screen) [MMManagedVirtualIDs() removeObject:@(_screen.displayID)]; }
- (CGDirectDisplayID)displayID { return _screen.displayID; }
@end

BOOL MMIsVirtualDisplay(CGDirectDisplayID display) {
    typedef CFDictionaryRef (*InfoFunction)(CGDirectDisplayID);
    void *handle = MMCoreDisplay();
    InfoFunction info = handle ? (InfoFunction)dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") : NULL;
    if (!info) return YES;
    NSDictionary *dict = CFBridgingRelease(info(display));
    NSNumber *virtualDevice = dict[@"kCGDisplayIsVirtualDevice"];
    NSNumber *airPlay = dict[@"kCGDisplayIsAirPlay"];
    // Fail closed when this OS does not provide the classification.
    if (![virtualDevice isKindOfClass:NSNumber.class] || ![airPlay isKindOfClass:NSNumber.class]) return YES;
    return virtualDevice.boolValue || airPlay.boolValue;
}

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN
BOOL MMCanSetEnabled(void);
CGError MMSetEnabled(CGDirectDisplayID display, BOOL enabled);
NSString *MMDisplayName(CGDirectDisplayID display);
NSArray<NSNumber *> *MMAllDisplays(void);
CGSize MMPanelPixelSize(CGDirectDisplayID display);

@interface MMNativeMode : NSObject
@property(nonatomic, readonly) int32_t modeID;
@property(nonatomic, readonly) NSInteger width, height, pixelWidth, pixelHeight;
@property(nonatomic, readonly) double refreshRate;
@end
NSArray<MMNativeMode *> *MMNativeHiDPIModes(CGDirectDisplayID display);
MMNativeMode * _Nullable MMCurrentHiDPIMode(CGDirectDisplayID display);
CGError MMConfigureHiDPIMode(CGDisplayConfigRef config, CGDirectDisplayID display, int32_t modeID);

@interface MMVirtualScreen : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
+ (BOOL)isSupported;
- (nullable instancetype)initWithPhysicalID:(CGDirectDisplayID)physical
                                    width:(unsigned int)width
                                   height:(unsigned int)height
                                   serial:(unsigned int)serial
                                    sizes:(NSArray<NSDictionary *> *)sizes
                             refreshRates:(NSArray<NSNumber *> *)rates
                            preferredRate:(double)preferredRate;
@end
NS_ASSUME_NONNULL_END

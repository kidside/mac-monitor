#define main MMSidecarToolMain
#import "../Sources/Native/SidecarTool.m"
#undef main
#include <assert.h>
@interface MMTestDevice : NSObject
@property(nonatomic, strong) NSString *identifier, *name, *model;
@property(nonatomic) BOOL offersAdditionalDisplay, isRealityDevice;
@end
@implementation MMTestDevice
@end
@interface MMTestConfig : NSObject
@property(nonatomic, strong) NSNumber *displayID;
@end
@implementation MMTestConfig
@end
@interface MMTestManager : NSObject
@property(nonatomic, strong) NSArray *devices, *connectedDevices;
- (id)configForDevice:(id)device;
@end
@implementation MMTestManager
- (id)configForDevice:(id)device { MMTestConfig *c=[MMTestConfig new]; c.displayID=@77; return c; }
@end
int main(void) { @autoreleasepool {
    MMTestDevice *(^device)(NSString *,NSString *) = ^(NSString *key, NSString *model) {
        MMTestDevice *d=[MMTestDevice new];d.identifier=key;d.name=@"Same iPad name";d.model=model;d.offersAdditionalDisplay=YES; return d;
    };
    MMTestDevice *a=device(@"a",@"iPad14,1"),*b=device(@"b",@"iPad15,2"),*phone=device(@"c",@"iPhone17,1"),*vision=device(@"d",@"iPad16,1");
    vision.isRealityDevice=YES;
    MMTestManager *manager=[MMTestManager new];manager.devices=@[b,phone,vision];manager.connectedDevices=@[a];
    NSSet *connected=nil;
    NSArray *devices=MMDevices((id)manager,&connected);
    assert(devices.count==2 && [connected containsObject:@"a"]);
    NSArray *records=MMRecords((id)manager,devices,connected);
    for(NSDictionary *row in records) {
        if([row[@"id"] isEqual:@"a"]) { assert([row[@"connected"] boolValue]);assert([row[@"displayID"] unsignedIntValue]==77); }
        if([row[@"id"] isEqual:@"b"]) { assert(![row[@"connected"] boolValue]);assert([row[@"displayID"] unsignedIntValue]==0); }
    }
    // Input validation happens before loading Sidecar or contacting a device.
    const char *missing[]={"SidecarTool","connect"},*invalid[]={"SidecarTool","shell","ipad"};
    assert(MMSidecarToolMain(2,missing)==64 && MMSidecarToolMain(3,invalid)==64);
    puts("PASS: Sidecar connected-only devices, duplicate names, iPad-only filtering and reject malformed commands");
}}

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <string.h>

static const char * const kSymbols[] = {
    "RS_GetTripleHistoryForSymbol",
    "RS_ResetTripleHistoryForSymbol",
    "RS_ResetTripleHistory",
    "RS_GetTargetSpinSymbol",
    "RS_SetTargetSpinSymbol"
};

static void AppendLog(NSString *line) {
    NSLog(@"[CMSBridgeV2] %@", line);
    NSString *folder = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!folder) return;
    NSString *path = [folder stringByAppendingPathComponent:@"CMSCrystalBridge-log.txt"];
    NSString *record = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    NSData *data = [record dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [data writeToFile:path atomically:YES];
        return;
    }
    @try { [handle seekToEndOfFile]; [handle writeData:data]; [handle closeFile]; }
    @catch (NSException *exception) { NSLog(@"[CMSBridgeV2] Log write error: %@", exception); }
}

static void Probe(unsigned attempt) {
    NSMutableArray<NSString *> *originals = [NSMutableArray array];
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *path = _dyld_get_image_name(i);
        if (path && strstr(path, "CMSCrystal") && !strstr(path, "CMSCrystalBridge")) {
            [originals addObject:[NSString stringWithUTF8String:path]];
        }
    }
    AppendLog([NSString stringWithFormat:@"Probe %u: original=%@", attempt,
               originals.count ? [originals componentsJoinedByString:@" | "] : @"NOT LOADED"]);
    for (size_t i = 0; i < sizeof(kSymbols)/sizeof(kSymbols[0]); ++i) {
        void *addr = dlsym(RTLD_DEFAULT, kSymbols[i]);
        Dl_info info = {0};
        const char *owner = (addr && dladdr(addr, &info) && info.dli_fname) ? info.dli_fname : NULL;
        AppendLog([NSString stringWithFormat:@"%s = %@; owner=%s", kSymbols[i],
                   addr ? @"FOUND" : @"NOT FOUND", owner ? owner : "unknown"]);
    }
    AppendLog(@"Probe complete; no discovered function invoked");
}

__attribute__((constructor)) static void InitCMSBridgeV2(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        const int delays[] = {3, 8, 20};
        for (unsigned i = 0; i < 3; ++i) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)delays[i] * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{ Probe(i + 1); });
        }
    });
}

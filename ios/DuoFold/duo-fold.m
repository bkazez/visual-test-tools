// Folds an iPhone Duo simulator: runs inside it (`xcrun simctl spawn`) and asks
// SpringBoard to move the hinge, as Apple's internal `sbdisplaytool swap` does.
// Xcode 27.2 has no other way: no simctl command, no menu in DeviceHub.
//
//   duo-fold POSITION     0.0 closed (outer display) ... 1.0 open flat (inner)
//
// The call is -[SBSDisplayToolService swapDisplayWithSettings:completionHandler:]
// in SpringBoardServices. Its settings are a C struct passed by value; the
// layout below is read off -[SBSDisplayToolServiceConnection
// swapDisplayWithSettings:completionHandler:], which turns each field into the
// options SpringBoard receives. targetMode 1 is an absolute hinge position.
//
// SpringBoard refuses a client without the com.apple.springboard.sbdisplay.service
// entitlement. A simulator reads entitlements from the __TEXT,__entitlements
// section (bin/duo-fold links it in); in the code signature they make
// launchd_sim refuse to spawn the binary at all.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>

typedef struct {
    long long state;
    double duration;
    long long deviceOrientation;
    long long profileOverride;
    BOOL waitForCompletion;
    long long targetMode;
    double targetHingePosition;
    double lockedForTestingUntil;
} SwapSettings;

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) { fprintf(stderr, "usage: duo-fold POSITION (0.0 closed ... 1.0 open)\n"); return 2; }
        dlopen("/System/Library/PrivateFrameworks/SpringBoardFoundation.framework/SpringBoardFoundation", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
        Class serviceClass = NSClassFromString(@"SBSDisplayToolService");
        double *unspecified = dlsym(RTLD_DEFAULT, "SBFDisplayToolSwapSettingsDurationUnspecified");
        if (!serviceClass || !unspecified) { fprintf(stderr, "duo-fold: this runtime has no SpringBoard display tool\n"); return 2; }

        SwapSettings settings = {0};
        settings.duration = *unspecified;
        settings.waitForCompletion = YES;
        settings.targetMode = 1;
        settings.targetHingePosition = atof(argv[1]);

        id service = [[serviceClass alloc] init];
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSError *failure = nil;
        ((void (*)(id, SEL, SwapSettings, id))objc_msgSend)(service, sel_registerName("swapDisplayWithSettings:completionHandler:"), settings, ^(NSError *error) {
            failure = error;
            dispatch_semaphore_signal(done);
        });
        long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC));
        ((void (*)(id, SEL))objc_msgSend)(service, sel_registerName("invalidate"));
        if (timedOut) { fprintf(stderr, "duo-fold: SpringBoard did not answer in 90 s\n"); return 1; }
        if (failure) { fprintf(stderr, "duo-fold: %s\n", failure.description.UTF8String); return 1; }
        return 0;
    }
}

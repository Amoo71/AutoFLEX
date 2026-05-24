#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "FLEXManager.h"

static const void *AutoFLEXGestureInstalledKey = &AutoFLEXGestureInstalledKey;

__attribute__((visibility("hidden")))
@interface AutoFLEX : NSObject
@property (nonatomic, assign) BOOL didShowExplorerOnLaunch;
@end

@implementation AutoFLEX

+ (instancetype)sharedInstance
{
    static AutoFLEX *_sharedInstance;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });

    return _sharedInstance;
}

- (void)showExplorer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"AutoFLEX: opening explorer: %@", [FLEXManager sharedManager]);
        [[FLEXManager sharedManager] showExplorer];
    });
}

- (void)showExplorerOnceAfterLaunch
{
    if (self.didShowExplorerOnLaunch) {
        return;
    }

    self.didShowExplorerOnLaunch = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self showExplorer];
    });
}

- (NSArray<UIWindow *> *)candidateWindows
{
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *application = [UIApplication sharedApplication];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            [windows addObjectsFromArray:windowScene.windows];
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:application.windows];
#pragma clang diagnostic pop

    return windows;
}

- (void)installGestureRecognizers
{
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in [self candidateWindows]) {
            if (!window || objc_getAssociatedObject(window, AutoFLEXGestureInstalledKey)) {
                continue;
            }

            UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
            gesture.minimumPressDuration = 0.75;
            gesture.cancelsTouchesInView = NO;
            [window addGestureRecognizer:gesture];
            objc_setAssociatedObject(window, AutoFLEXGestureInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self showExplorer];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self installGestureRecognizers];
    [self showExplorerOnceAfterLaunch];
}

@end

__attribute__((constructor))
static void AutoFLEXInitialize(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        AutoFLEX *loader = [AutoFLEX sharedInstance];

        [[NSNotificationCenter defaultCenter] addObserver:loader
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];

        [loader installGestureRecognizers];
        [loader showExplorerOnceAfterLaunch];
    });
}

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "FLEXManager.h"

static const void *AutoFLEXGestureInstalledKey = &AutoFLEXGestureInstalledKey;
static NSString * const AutoFLEXUIOverridesDefaultsKey = @"com.hopeless.autoflex.uiOverrides.v2";

__attribute__((visibility("hidden")))
@interface AutoFLEX : NSObject
@property (nonatomic, assign) BOOL didShowExplorerOnLaunch;
@property (nonatomic, strong) UIWindow *pickerWindow;
@end

@implementation AutoFLEX

+ (instancetype)sharedInstance
{
    static AutoFLEX *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (void)showExplorer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[FLEXManager sharedManager] showExplorer];
    });
}

- (NSArray<UIWindow *> *)candidateWindows
{
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *app = [UIApplication sharedApplication];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:app.windows];
#pragma clang diagnostic pop

    NSMutableArray<UIWindow *> *filtered = [NSMutableArray array];
    for (UIWindow *window in windows) {
        if (!window || window.hidden || window.alpha <= 0.01 || window == self.pickerWindow) {
            continue;
        }

        NSString *className = NSStringFromClass(window.class);
        if ([className containsString:@"Keyboard"] || [className containsString:@"TextEffects"] || [className hasPrefix:@"UIRemote"]) {
            continue;
        }

        if (![filtered containsObject:window]) {
            [filtered addObject:window];
        }
    }

    return filtered;
}

- (UIWindow *)frontWindow
{
    for (UIWindow *window in [self candidateWindows]) {
        if (window.isKeyWindow && window.rootViewController) {
            return window;
        }
    }

    for (UIWindow *window in [self candidateWindows]) {
        if (window.rootViewController) {
            return window;
        }
    }

    return nil;
}

- (UIViewController *)topViewController
{
    UIViewController *controller = [self frontWindow].rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }

    if ([controller isKindOfClass:[UINavigationController class]]) {
        controller = ((UINavigationController *)controller).visibleViewController;
    }

    if ([controller isKindOfClass:[UITabBarController class]]) {
        controller = ((UITabBarController *)controller).selectedViewController;
    }

    return controller;
}

- (void)presentAlert:(UIAlertController *)alert
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = [self topViewController];
        if (!controller) {
            return;
        }

        UIPopoverPresentationController *popover = alert.popoverPresentationController;
        if (popover) {
            popover.sourceView = controller.view;
            popover.sourceRect = CGRectMake(CGRectGetMidX(controller.view.bounds), CGRectGetMidY(controller.view.bounds), 1.0, 1.0);
            popover.permittedArrowDirections = 0;
        }

        [controller presentViewController:alert animated:YES completion:nil];
    });
}

- (void)showMessage:(NSString *)message title:(NSString *)title
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentAlert:alert];
}

- (void)installGestureRecognizers
{
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in [self candidateWindows]) {
            if (objc_getAssociatedObject(window, AutoFLEXGestureInstalledKey)) {
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
        [self presentToolsMenu];
    }
}

- (void)presentToolsMenu
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AutoFLEX Tools"
                                                                   message:@"UI-Farben live ändern, speichern und zurücksetzen."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"FLEX öffnen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self showExplorer];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"UI-Farbe antippen & bearbeiten" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self beginColorPicker];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Gespeicherte Farben anwenden" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self applySavedUIOverrides];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Alle Farben resetten" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self resetAllUIOverrides];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)beginColorPicker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.pickerWindow setHidden:YES];
        self.pickerWindow = nil;

        UIWindow *baseWindow = [self frontWindow];
        CGRect bounds = [UIScreen mainScreen].bounds;
        UIWindow *picker = nil;

        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = baseWindow.windowScene;
            if (scene) {
                bounds = scene.coordinateSpace.bounds;
                picker = [[UIWindow alloc] initWithWindowScene:scene];
            }
        }

        if (!picker) {
            picker = [[UIWindow alloc] initWithFrame:bounds];
        }

        picker.frame = bounds;
        picker.windowLevel = UIWindowLevelAlert + 1000.0;

        UIViewController *controller = [UIViewController new];
        controller.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.08];
        picker.rootViewController = controller;
        picker.hidden = NO;
        self.pickerWindow = picker;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 58.0, bounds.size.width - 32.0, 76.0)];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
        label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
        label.textColor = UIColor.whiteColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.layer.cornerRadius = 12.0;
        label.layer.masksToBounds = YES;
        label.text = @"AutoFLEX Color Picker\nTippe ein UI-Element an. Zweifinger-Tap bricht ab.";
        [controller.view addSubview:label];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handlePickerTap:)];
        [controller.view addGestureRecognizer:tap];

        UITapGestureRecognizer *cancel = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelColorPicker)];
        cancel.numberOfTouchesRequired = 2;
        [controller.view addGestureRecognizer:cancel];
    });
}

- (void)cancelColorPicker
{
    [self.pickerWindow setHidden:YES];
    self.pickerWindow = nil;
}

- (void)handlePickerTap:(UITapGestureRecognizer *)gesture
{
    CGPoint point = [gesture locationInView:gesture.view];
    UIView *target = nil;

    for (UIWindow *window in [[self candidateWindows] reverseObjectEnumerator]) {
        CGPoint converted = [window convertPoint:point fromWindow:self.pickerWindow];
        if (!CGRectContainsPoint(window.bounds, converted)) {
            continue;
        }

        UIView *hit = [window hitTest:converted withEvent:nil];
        if (hit && hit != window) {
            target = hit;
            break;
        }
    }

    [self cancelColorPicker];

    if (!target) {
        [self showMessage:@"Kein UI-Element gefunden." title:@"AutoFLEX"];
        return;
    }

    [self presentColorEditorForView:target];
}

- (NSArray<NSString *> *)editableColorPropertiesForView:(UIView *)view
{
    NSMutableArray<NSString *> *props = [NSMutableArray arrayWithObjects:@"backgroundColor", @"tintColor", nil];

    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextField.class] || [view isKindOfClass:UITextView.class]) {
        [props addObject:@"textColor"];
    }

    if ([view isKindOfClass:UIButton.class]) {
        [props addObject:@"titleColor"];
    }

    return props;
}

- (UIColor *)colorForProperty:(NSString *)property view:(UIView *)view
{
    if ([property isEqualToString:@"backgroundColor"]) {
        return view.backgroundColor;
    }

    if ([property isEqualToString:@"tintColor"]) {
        return view.tintColor;
    }

    if ([property isEqualToString:@"textColor"]) {
        if ([view isKindOfClass:UILabel.class]) {
            return ((UILabel *)view).textColor;
        }
        if ([view isKindOfClass:UITextField.class]) {
            return ((UITextField *)view).textColor;
        }
        if ([view isKindOfClass:UITextView.class]) {
            return ((UITextView *)view).textColor;
        }
    }

    if ([property isEqualToString:@"titleColor"] && [view isKindOfClass:UIButton.class]) {
        return [(UIButton *)view titleColorForState:UIControlStateNormal];
    }

    return nil;
}

- (void)setColor:(UIColor *)color property:(NSString *)property view:(UIView *)view
{
    if ([property isEqualToString:@"backgroundColor"]) {
        view.backgroundColor = color;
    } else if ([property isEqualToString:@"tintColor"]) {
        view.tintColor = color;
    } else if ([property isEqualToString:@"textColor"]) {
        if ([view isKindOfClass:UILabel.class]) {
            ((UILabel *)view).textColor = color;
        } else if ([view isKindOfClass:UITextField.class]) {
            ((UITextField *)view).textColor = color;
        } else if ([view isKindOfClass:UITextView.class]) {
            ((UITextView *)view).textColor = color;
        }
    } else if ([property isEqualToString:@"titleColor"] && [view isKindOfClass:UIButton.class]) {
        [(UIButton *)view setTitleColor:color forState:UIControlStateNormal];
    }
}

- (void)presentColorEditorForView:(UIView *)view
{
    NSString *path = [self pathForView:view];
    NSString *className = NSStringFromClass(view.class);
    NSString *message = path ?: @"Dieses Element kann nicht dauerhaft gespeichert werden.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ bearbeiten", className]
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *property in [self editableColorPropertiesForView:view]) {
        NSString *hex = [self hexFromColor:[self colorForProperty:property view:view]] ?: @"nil";
        NSString *title = [NSString stringWithFormat:@"%@: %@", property, hex];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self promptForColorProperty:property view:view];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Dieses Element resetten" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self resetOverridesForView:view];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)promptForColorProperty:(NSString *)property view:(UIView *)view
{
    NSString *current = [self hexFromColor:[self colorForProperty:property view:view]] ?: @"#FFFFFFFF";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ setzen", property]
                                                                   message:@"Format: #RRGGBB oder #RRGGBBAA, z. B. #1DB954FF"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = current;
        textField.placeholder = @"#RRGGBBAA";
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Speichern" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text ?: @"";
        UIColor *color = [self colorFromHex:input];
        if (!color) {
            [self showMessage:@"Bitte nutze #RRGGBB oder #RRGGBBAA." title:@"Ungültige Farbe"];
            return;
        }

        [self saveColorOverrideForView:view property:property color:color];
        [self setColor:color property:property view:view];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (NSMutableDictionary *)mutableOverrides
{
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:AutoFLEXUIOverridesDefaultsKey];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveOverrides:(NSDictionary *)overrides
{
    [NSUserDefaults.standardUserDefaults setObject:overrides forKey:AutoFLEXUIOverridesDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)saveColorOverrideForView:(UIView *)view property:(NSString *)property color:(UIColor *)color
{
    NSString *path = [self pathForView:view];
    if (!path) {
        [self showMessage:@"Dieses Element hat keinen stabilen View-Pfad." title:@"Nicht gespeichert"];
        return;
    }

    NSMutableDictionary *overrides = [self mutableOverrides];
    NSMutableDictionary *entry = [overrides[path] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *props = [entry[@"properties"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *propEntry = [props[property] mutableCopy] ?: [NSMutableDictionary dictionary];

    if (!propEntry[@"original"]) {
        NSString *original = [self hexFromColor:[self colorForProperty:property view:view]];
        if (original) {
            propEntry[@"original"] = original;
        }
    }

    propEntry[@"value"] = [self hexFromColor:color] ?: @"#FFFFFFFF";
    props[property] = propEntry;
    entry[@"class"] = NSStringFromClass(view.class);
    entry[@"properties"] = props;
    overrides[path] = entry;
    [self saveOverrides:overrides];
}

- (void)applySavedUIOverrides
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *overrides = [NSUserDefaults.standardUserDefaults dictionaryForKey:AutoFLEXUIOverridesDefaultsKey];
        if (![overrides isKindOfClass:NSDictionary.class] || overrides.count == 0) {
            return;
        }

        for (NSString *path in overrides) {
            NSDictionary *entry = overrides[path];
            NSDictionary *props = entry[@"properties"];
            if (![props isKindOfClass:NSDictionary.class]) {
                continue;
            }

            for (UIWindow *window in [self candidateWindows]) {
                UIView *view = [self viewForPath:path inWindow:window];
                if (!view) {
                    continue;
                }

                for (NSString *property in props) {
                    NSString *value = props[property][@"value"];
                    UIColor *color = [self colorFromHex:value];
                    if (color) {
                        [self setColor:color property:property view:view];
                    }
                }
            }
        }
    });
}

- (void)resetOverridesForView:(UIView *)view
{
    NSString *path = [self pathForView:view];
    if (!path) {
        return;
    }

    NSMutableDictionary *overrides = [self mutableOverrides];
    NSDictionary *entry = overrides[path];
    NSDictionary *props = entry[@"properties"];

    for (NSString *property in props) {
        NSString *original = props[property][@"original"];
        UIColor *originalColor = [self colorFromHex:original];
        [self setColor:originalColor property:property view:view];
    }

    [overrides removeObjectForKey:path];
    [self saveOverrides:overrides];
}

- (void)resetAllUIOverrides
{
    NSDictionary *overrides = [NSUserDefaults.standardUserDefaults dictionaryForKey:AutoFLEXUIOverridesDefaultsKey];
    if ([overrides isKindOfClass:NSDictionary.class]) {
        for (NSString *path in overrides) {
            NSDictionary *entry = overrides[path];
            NSDictionary *props = entry[@"properties"];
            if (![props isKindOfClass:NSDictionary.class]) {
                continue;
            }

            for (UIWindow *window in [self candidateWindows]) {
                UIView *view = [self viewForPath:path inWindow:window];
                if (!view) {
                    continue;
                }

                for (NSString *property in props) {
                    NSString *original = props[property][@"original"];
                    UIColor *originalColor = [self colorFromHex:original];
                    [self setColor:originalColor property:property view:view];
                }
            }
        }
    }

    [NSUserDefaults.standardUserDefaults removeObjectForKey:AutoFLEXUIOverridesDefaultsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self showMessage:@"Alle gespeicherten UI-Farbänderungen wurden entfernt." title:@"AutoFLEX Reset"];
}

- (NSString *)pathForView:(UIView *)view
{
    if (!view || [view isKindOfClass:UIWindow.class]) {
        return nil;
    }

    NSMutableArray<NSString *> *components = [NSMutableArray array];
    UIView *current = view;

    while (current && ![current isKindOfClass:UIWindow.class]) {
        UIView *parent = current.superview;
        if (!parent) {
            return nil;
        }

        NSUInteger index = [parent.subviews indexOfObject:current];
        if (index == NSNotFound) {
            return nil;
        }

        [components insertObject:[NSString stringWithFormat:@"%@:%lu", NSStringFromClass(current.class), (unsigned long)index] atIndex:0];
        current = parent;
    }

    return [components componentsJoinedByString:@"/"];
}

- (UIView *)viewForPath:(NSString *)path inWindow:(UIWindow *)window
{
    if (!path.length || !window) {
        return nil;
    }

    UIView *current = window;
    for (NSString *component in [path componentsSeparatedByString:@"/"]) {
        NSArray<NSString *> *parts = [component componentsSeparatedByString:@":"];
        if (parts.count != 2) {
            return nil;
        }

        NSUInteger index = (NSUInteger)[parts[1] integerValue];
        if (index >= current.subviews.count) {
            return nil;
        }

        UIView *next = current.subviews[index];
        if (![NSStringFromClass(next.class) isEqualToString:parts[0]]) {
            return nil;
        }

        current = next;
    }

    return current;
}

- (NSString *)hexFromColor:(UIColor *)color
{
    if (!color) {
        return nil;
    }

    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;

    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        CGColorRef cgColor = color.CGColor;
        size_t count = CGColorGetNumberOfComponents(cgColor);
        const CGFloat *components = CGColorGetComponents(cgColor);
        if (count == 2) {
            red = green = blue = components[0];
            alpha = components[1];
        } else if (count >= 4) {
            red = components[0];
            green = components[1];
            blue = components[2];
            alpha = components[3];
        } else {
            return nil;
        }
    }

    int r = (int)(MAX(0.0, MIN(1.0, red)) * 255.0 + 0.5);
    int g = (int)(MAX(0.0, MIN(1.0, green)) * 255.0 + 0.5);
    int b = (int)(MAX(0.0, MIN(1.0, blue)) * 255.0 + 0.5);
    int a = (int)(MAX(0.0, MIN(1.0, alpha)) * 255.0 + 0.5);

    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", r, g, b, a];
}

- (UIColor *)colorFromHex:(NSString *)hex
{
    NSString *clean = [[hex ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([clean hasPrefix:@"#"]) {
        clean = [clean substringFromIndex:1];
    }

    if (clean.length == 3) {
        unichar r = [clean characterAtIndex:0];
        unichar g = [clean characterAtIndex:1];
        unichar b = [clean characterAtIndex:2];
        clean = [NSString stringWithFormat:@"%C%C%C%C%C%CFF", r, r, g, g, b, b];
    } else if (clean.length == 6) {
        clean = [clean stringByAppendingString:@"FF"];
    }

    if (clean.length != 8) {
        return nil;
    }

    unsigned int value = 0;
    if (![[NSScanner scannerWithString:clean] scanHexInt:&value]) {
        return nil;
    }

    CGFloat red = ((value >> 24) & 0xFF) / 255.0;
    CGFloat green = ((value >> 16) & 0xFF) / 255.0;
    CGFloat blue = ((value >> 8) & 0xFF) / 255.0;
    CGFloat alpha = (value & 0xFF) / 255.0;

    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self installGestureRecognizers];
    [self applySavedUIOverrides];

    if (!self.didShowExplorerOnLaunch) {
        self.didShowExplorerOnLaunch = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self applySavedUIOverrides];
            [self showExplorer];
        });
    }
}

@end

__attribute__((constructor))
static void AutoFLEXInitialize(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        AutoFLEX *loader = [AutoFLEX sharedInstance];
        [NSNotificationCenter.defaultCenter addObserver:loader
                                               selector:@selector(applicationDidBecomeActive:)
                                                   name:UIApplicationDidBecomeActiveNotification
                                                 object:nil];
        [loader installGestureRecognizers];
        [loader applySavedUIOverrides];
    });
}

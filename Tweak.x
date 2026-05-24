#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "FLEXManager.h"

static const void *AutoFLEXGestureInstalledKey = &AutoFLEXGestureInstalledKey;
static NSString * const AutoFLEXUIOverridesDefaultsKey = @"com.hopeless.autoflex.uiOverrides.v3";

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

- (NSString *)truncatedString:(NSString *)string maxLength:(NSUInteger)maxLength
{
    if (!string) {
        return @"";
    }

    if (string.length <= maxLength) {
        return string;
    }

    return [[string substringToIndex:maxLength] stringByAppendingString:@"…"];
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
                                                                   message:@"UI, Transparency, Cookies und App-Werte bearbeiten und speichern."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"FLEX öffnen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self showExplorer];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"UI-Element antippen & bearbeiten" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self beginViewPicker];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"NSUserDefaults / App-Werte bearbeiten" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self presentDefaultsMenu];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cookies bearbeiten" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self presentCookieMenu];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Gespeicherte UI-Änderungen anwenden" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self applySavedUIOverrides];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Alle UI-Änderungen resetten" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self resetAllUIOverrides];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

#pragma mark - UI editor

- (void)beginViewPicker
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

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 58.0, bounds.size.width - 32.0, 90.0)];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
        label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
        label.textColor = UIColor.whiteColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.layer.cornerRadius = 12.0;
        label.layer.masksToBounds = YES;
        label.text = @"AutoFLEX Picker\nTippe ein UI-Element an. Danach kannst du Farbe, Textfarbe, Tint und Alpha/Transparency ändern. Zweifinger-Tap bricht ab.";
        [controller.view addSubview:label];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handlePickerTap:)];
        [controller.view addGestureRecognizer:tap];

        UITapGestureRecognizer *cancel = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelViewPicker)];
        cancel.numberOfTouchesRequired = 2;
        [controller.view addGestureRecognizer:cancel];
    });
}

- (void)cancelViewPicker
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

    [self cancelViewPicker];

    if (!target) {
        [self showMessage:@"Kein UI-Element gefunden." title:@"AutoFLEX"];
        return;
    }

    [self presentViewEditorForView:target];
}

- (NSArray<NSString *> *)editablePropertiesForView:(UIView *)view
{
    NSMutableArray<NSString *> *props = [NSMutableArray arrayWithObjects:@"backgroundColor", @"tintColor", @"alpha", nil];

    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextField.class] || [view isKindOfClass:UITextView.class]) {
        [props addObject:@"textColor"];
    }

    if ([view isKindOfClass:UIButton.class]) {
        [props addObject:@"titleColor"];
    }

    return props;
}

- (BOOL)isColorProperty:(NSString *)property
{
    return [property isEqualToString:@"backgroundColor"] || [property isEqualToString:@"tintColor"] || [property isEqualToString:@"textColor"] || [property isEqualToString:@"titleColor"];
}

- (NSString *)valueStringForProperty:(NSString *)property view:(UIView *)view
{
    if ([property isEqualToString:@"alpha"]) {
        return [NSString stringWithFormat:@"%.3f", view.alpha];
    }

    if ([property isEqualToString:@"backgroundColor"]) {
        return [self hexFromColor:view.backgroundColor];
    }

    if ([property isEqualToString:@"tintColor"]) {
        return [self hexFromColor:view.tintColor];
    }

    if ([property isEqualToString:@"textColor"]) {
        if ([view isKindOfClass:UILabel.class]) {
            return [self hexFromColor:((UILabel *)view).textColor];
        }
        if ([view isKindOfClass:UITextField.class]) {
            return [self hexFromColor:((UITextField *)view).textColor];
        }
        if ([view isKindOfClass:UITextView.class]) {
            return [self hexFromColor:((UITextView *)view).textColor];
        }
    }

    if ([property isEqualToString:@"titleColor"] && [view isKindOfClass:UIButton.class]) {
        return [self hexFromColor:[(UIButton *)view titleColorForState:UIControlStateNormal]];
    }

    return nil;
}

- (BOOL)setValueString:(NSString *)value property:(NSString *)property view:(UIView *)view
{
    if ([property isEqualToString:@"alpha"]) {
        NSString *normalized = [[value ?: @"" stringByReplacingOccurrencesOfString:@"," withString:@"."] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        double alpha = 0.0;
        NSScanner *scanner = [NSScanner scannerWithString:normalized];
        if (![scanner scanDouble:&alpha]) {
            return NO;
        }

        alpha = MAX(0.0, MIN(1.0, alpha));
        view.alpha = (CGFloat)alpha;
        return YES;
    }

    if (![self isColorProperty:property]) {
        return NO;
    }

    UIColor *color = [self colorFromHex:value];
    if (!color) {
        return NO;
    }

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

    return YES;
}

- (void)restoreOriginalValue:(NSString *)original property:(NSString *)property view:(UIView *)view
{
    if (original.length > 0) {
        [self setValueString:original property:property view:view];
        return;
    }

    if ([property isEqualToString:@"alpha"]) {
        view.alpha = 1.0;
    } else if ([property isEqualToString:@"backgroundColor"]) {
        view.backgroundColor = nil;
    } else if ([property isEqualToString:@"tintColor"]) {
        view.tintColor = nil;
    }
}

- (void)presentViewEditorForView:(UIView *)view
{
    NSString *path = [self pathForView:view];
    NSString *className = NSStringFromClass(view.class);
    NSString *message = path ?: @"Dieses Element kann nicht dauerhaft gespeichert werden.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ bearbeiten", className]
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *property in [self editablePropertiesForView:view]) {
        NSString *value = [self valueStringForProperty:property view:view] ?: @"nil";
        NSString *title = [NSString stringWithFormat:@"%@: %@", property, value];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self promptForViewProperty:property view:view];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Dieses Element resetten" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self resetOverridesForView:view];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)promptForViewProperty:(NSString *)property view:(UIView *)view
{
    BOOL isAlpha = [property isEqualToString:@"alpha"];
    NSString *current = [self valueStringForProperty:property view:view] ?: (isAlpha ? @"1.0" : @"#FFFFFFFF");
    NSString *message = isAlpha ? @"Transparency/Alpha: 0.0 = unsichtbar, 1.0 = normal" : @"Farbe: #RRGGBB oder #RRGGBBAA, z. B. #1DB954FF";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ setzen", property]
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = current;
        textField.placeholder = isAlpha ? @"0.0 - 1.0" : @"#RRGGBBAA";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Speichern" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text ?: @"";
        if (![self setValueString:input property:property view:view]) {
            [self showMessage:(isAlpha ? @"Bitte nutze eine Zahl von 0.0 bis 1.0." : @"Bitte nutze #RRGGBB oder #RRGGBBAA.") title:@"Ungültiger Wert"];
            return;
        }

        NSString *storedValue = [self valueStringForProperty:property view:view] ?: input;
        [self saveUIOverrideForView:view property:property value:storedValue];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (NSMutableDictionary *)mutableOverrides
{
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:AutoFLEXUIOverridesDefaultsKey];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveOverrides:(NSDictionary *)overrides
{
    [[NSUserDefaults standardUserDefaults] setObject:overrides forKey:AutoFLEXUIOverridesDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveUIOverrideForView:(UIView *)view property:(NSString *)property value:(NSString *)value
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
        NSString *original = [self valueStringForProperty:property view:view];
        if (original) {
            propEntry[@"original"] = original;
        }
    }

    propEntry[@"value"] = value ?: @"";
    propEntry[@"kind"] = [property isEqualToString:@"alpha"] ? @"number" : @"color";
    props[property] = propEntry;
    entry[@"class"] = NSStringFromClass(view.class);
    entry[@"properties"] = props;
    overrides[path] = entry;
    [self saveOverrides:overrides];
}

- (void)applySavedUIOverrides
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *overrides = [[NSUserDefaults standardUserDefaults] dictionaryForKey:AutoFLEXUIOverridesDefaultsKey];
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
                    NSDictionary *propEntry = props[property];
                    NSString *value = propEntry[@"value"];
                    if (value.length > 0) {
                        [self setValueString:value property:property view:view];
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
        NSDictionary *propEntry = props[property];
        NSString *original = propEntry[@"original"];
        [self restoreOriginalValue:original property:property view:view];
    }

    [overrides removeObjectForKey:path];
    [self saveOverrides:overrides];
}

- (void)resetAllUIOverrides
{
    NSDictionary *overrides = [[NSUserDefaults standardUserDefaults] dictionaryForKey:AutoFLEXUIOverridesDefaultsKey];
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
                    NSDictionary *propEntry = props[property];
                    NSString *original = propEntry[@"original"];
                    [self restoreOriginalValue:original property:property view:view];
                }
            }
        }
    }

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:AutoFLEXUIOverridesDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self showMessage:@"Alle gespeicherten UI-Änderungen wurden entfernt." title:@"AutoFLEX Reset"];
}

#pragma mark - NSUserDefaults editor

- (void)presentDefaultsMenu
{
    NSDictionary *dictionary = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSArray<NSString *> *keys = [[dictionary allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"NSUserDefaults / App-Werte"
                                                                   message:@"Keys direkt bearbeiten, speichern oder löschen. Typen: string, bool, int, float, json, delete."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Key suchen/setzen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self promptForDefaultKey:nil];
    }]];

    NSUInteger count = MIN((NSUInteger)18, keys.count);
    for (NSUInteger index = 0; index < count; index++) {
        NSString *key = keys[index];
        if ([key hasPrefix:@"com.hopeless.autoflex."]) {
            continue;
        }

        id value = dictionary[key];
        NSString *title = [NSString stringWithFormat:@"%@: %@", [self truncatedString:key maxLength:28], [self truncatedString:[self stringFromObject:value] maxLength:42]];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self promptForDefaultKey:key];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)promptForDefaultKey:(NSString *)prefilledKey
{
    id currentValue = prefilledKey ? [[NSUserDefaults standardUserDefaults] objectForKey:prefilledKey] : nil;
    NSString *currentType = [self defaultTypeForObject:currentValue];
    NSString *currentString = currentValue ? [self stringFromObject:currentValue] : @"";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App-Wert bearbeiten"
                                                                   message:@"Type: string, bool, int, float, json oder delete. JSON für Arrays/Dicts nutzen."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = prefilledKey ?: @"";
        textField.placeholder = @"Key";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = currentString;
        textField.placeholder = @"Value";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = currentType ?: @"string";
        textField.placeholder = @"type";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Speichern" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *key = alert.textFields[0].text ?: @"";
        NSString *value = alert.textFields[1].text ?: @"";
        NSString *type = alert.textFields[2].text ?: @"string";
        [self saveDefaultKey:key valueString:value type:type];
    }]];

    if (prefilledKey.length > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Löschen" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:prefilledKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)saveDefaultKey:(NSString *)key valueString:(NSString *)valueString type:(NSString *)type
{
    NSString *trimmedKey = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *normalizedType = [[type ?: @"string" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];

    if (trimmedKey.length == 0) {
        [self showMessage:@"Key darf nicht leer sein." title:@"AutoFLEX"];
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if ([normalizedType isEqualToString:@"delete"] || [normalizedType isEqualToString:@"remove"]) {
        [defaults removeObjectForKey:trimmedKey];
        [defaults synchronize];
        return;
    }

    id object = valueString ?: @"";

    if ([normalizedType isEqualToString:@"bool"] || [normalizedType isEqualToString:@"boolean"]) {
        NSString *lower = [valueString.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        object = @([lower isEqualToString:@"1"] || [lower isEqualToString:@"true"] || [lower isEqualToString:@"yes"] || [lower isEqualToString:@"on"]);
    } else if ([normalizedType isEqualToString:@"int"] || [normalizedType isEqualToString:@"integer"]) {
        object = @([valueString integerValue]);
    } else if ([normalizedType isEqualToString:@"float"] || [normalizedType isEqualToString:@"double"] || [normalizedType isEqualToString:@"number"]) {
        NSString *normalized = [valueString stringByReplacingOccurrencesOfString:@"," withString:@"."];
        object = @([normalized doubleValue]);
    } else if ([normalizedType isEqualToString:@"json"] || [normalizedType isEqualToString:@"array"] || [normalizedType isEqualToString:@"dict"] || [normalizedType isEqualToString:@"dictionary"]) {
        NSData *data = [valueString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        if (!parsed || error) {
            [self showMessage:@"JSON konnte nicht gelesen werden." title:@"Ungültiger Wert"];
            return;
        }
        object = parsed;
    }

    [defaults setObject:object forKey:trimmedKey];
    [defaults synchronize];
}

- (NSString *)defaultTypeForObject:(id)object
{
    if (!object) {
        return @"string";
    }

    if ([object isKindOfClass:NSString.class]) {
        return @"string";
    }

    if ([object isKindOfClass:NSNumber.class]) {
        return @"number";
    }

    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSDictionary.class]) {
        return @"json";
    }

    return @"string";
}

- (NSString *)stringFromObject:(id)object
{
    if (!object) {
        return @"";
    }

    if ([object isKindOfClass:NSString.class]) {
        return object;
    }

    if ([object isKindOfClass:NSNumber.class]) {
        return [object stringValue];
    }

    if ([NSJSONSerialization isValidJSONObject:object]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
        if (data) {
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [object description];
        }
    }

    return [object description];
}

#pragma mark - Cookie editor

- (void)presentCookieMenu
{
    NSArray<NSHTTPCookie *> *cookies = [[[NSHTTPCookieStorage sharedHTTPCookieStorage] cookies] sortedArrayUsingComparator:^NSComparisonResult(NSHTTPCookie *a, NSHTTPCookie *b) {
        NSString *left = [NSString stringWithFormat:@"%@.%@", a.domain ?: @"", a.name ?: @""];
        NSString *right = [NSString stringWithFormat:@"%@.%@", b.domain ?: @"", b.name ?: @""];
        return [left localizedCaseInsensitiveCompare:right];
    }];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cookies bearbeiten"
                                                                   message:@"Cookies können sensible Session-Daten sein. Bearbeite nur Werte in deiner eigenen Debug-/App-Umgebung."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cookie setzen/neu erstellen" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self promptForNewCookie];
    }]];

    NSUInteger count = MIN((NSUInteger)22, cookies.count);
    for (NSUInteger index = 0; index < count; index++) {
        NSHTTPCookie *cookie = cookies[index];
        NSString *title = [NSString stringWithFormat:@"%@ • %@ = %@", [self truncatedString:cookie.domain maxLength:24], [self truncatedString:cookie.name maxLength:22], [self truncatedString:cookie.value maxLength:28]];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self presentCookieEditorForCookie:cookie];
        }]];
    }

    if (cookies.count > count) {
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Weitere %lu Cookies: über Cookie setzen/neu erstellen nach Name bearbeiten", (unsigned long)(cookies.count - count)] style:UIAlertActionStyleDefault handler:nil]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Alle Cookies löschen" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self confirmDeleteAllCookies];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)presentCookieEditorForCookie:(NSHTTPCookie *)cookie
{
    NSString *message = [NSString stringWithFormat:@"Domain: %@\nPath: %@\nSecure: %@\nExpires: %@\nValue: %@", cookie.domain ?: @"", cookie.path ?: @"/", cookie.isSecure ? @"yes" : @"no", cookie.expiresDate ?: @"session", [self truncatedString:cookie.value maxLength:900]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:cookie.name ?: @"Cookie" message:message preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Wert bearbeiten" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self promptForCookieValue:cookie];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cookie löschen" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:cookie];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)promptForCookieValue:(NSHTTPCookie *)cookie
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ bearbeiten", cookie.name ?: @"Cookie"]
                                                                   message:[NSString stringWithFormat:@"%@%@", cookie.domain ?: @"", cookie.path ?: @"/"]
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = cookie.value ?: @"";
        textField.placeholder = @"Cookie value";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Speichern" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self saveCookie:cookie newValue:alert.textFields.firstObject.text ?: @""];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)saveCookie:(NSHTTPCookie *)cookie newValue:(NSString *)value
{
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    properties[NSHTTPCookieName] = cookie.name ?: @"";
    properties[NSHTTPCookieValue] = value ?: @"";
    properties[NSHTTPCookieDomain] = cookie.domain ?: @"";
    properties[NSHTTPCookiePath] = cookie.path ?: @"/";
    properties[NSHTTPCookieVersion] = @(cookie.version).stringValue;

    if (cookie.expiresDate) {
        properties[NSHTTPCookieExpires] = cookie.expiresDate;
    }

    if (cookie.isSecure) {
        properties[NSHTTPCookieSecure] = @"TRUE";
    }

    NSHTTPCookie *updated = [NSHTTPCookie cookieWithProperties:properties];
    if (!updated) {
        [self showMessage:@"Cookie konnte nicht gespeichert werden." title:@"AutoFLEX"];
        return;
    }

    [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:updated];
}

- (void)promptForNewCookie
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cookie setzen / erstellen"
                                                                   message:@"Domain, Name und Value sind nötig. Wenn ein Cookie mit gleichem Name/Domain/Path existiert, wird er ersetzt."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    NSArray<NSString *> *placeholders = @[@"Domain, z. B. .example.com", @"Name", @"Value", @"Path, z. B. /", @"Expires in Tagen, leer = Session", @"Secure: yes/no"];
    for (NSString *placeholder in placeholders) {
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = placeholder;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            textField.clearButtonMode = UITextFieldViewModeWhileEditing;
            if ([placeholder hasPrefix:@"Path"]) {
                textField.text = @"/";
            } else if ([placeholder hasPrefix:@"Secure"]) {
                textField.text = @"no";
            }
        }];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Speichern" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *domain = alert.textFields[0].text ?: @"";
        NSString *name = alert.textFields[1].text ?: @"";
        NSString *value = alert.textFields[2].text ?: @"";
        NSString *path = alert.textFields[3].text.length > 0 ? alert.textFields[3].text : @"/";
        NSString *days = alert.textFields[4].text ?: @"";
        NSString *secure = alert.textFields[5].text ?: @"no";
        [self createCookieDomain:domain name:name value:value path:path expiresDays:days secure:secure];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

- (void)createCookieDomain:(NSString *)domain name:(NSString *)name value:(NSString *)value path:(NSString *)path expiresDays:(NSString *)expiresDays secure:(NSString *)secure
{
    NSString *trimmedDomain = [domain stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *trimmedName = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if (trimmedDomain.length == 0 || trimmedName.length == 0) {
        [self showMessage:@"Domain und Name dürfen nicht leer sein." title:@"AutoFLEX"];
        return;
    }

    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    properties[NSHTTPCookieDomain] = trimmedDomain;
    properties[NSHTTPCookieName] = trimmedName;
    properties[NSHTTPCookieValue] = value ?: @"";
    properties[NSHTTPCookiePath] = path.length > 0 ? path : @"/";
    properties[NSHTTPCookieVersion] = @"0";

    NSString *lowerSecure = [[secure ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([lowerSecure isEqualToString:@"1"] || [lowerSecure isEqualToString:@"true"] || [lowerSecure isEqualToString:@"yes"] || [lowerSecure isEqualToString:@"on"]) {
        properties[NSHTTPCookieSecure] = @"TRUE";
    }

    NSString *trimmedDays = [expiresDays stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedDays.length > 0) {
        NSTimeInterval days = [trimmedDays doubleValue];
        if (days > 0) {
            properties[NSHTTPCookieExpires] = [NSDate dateWithTimeIntervalSinceNow:days * 24.0 * 60.0 * 60.0];
        }
    }

    NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:properties];
    if (!cookie) {
        [self showMessage:@"Cookie konnte nicht erstellt werden." title:@"AutoFLEX"];
        return;
    }

    [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:cookie];
}

- (void)confirmDeleteAllCookies
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Alle Cookies löschen?"
                                                                   message:@"Das kann Logins/Sessions in dieser App zurücksetzen."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Alle löschen" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in [storage cookies]) {
            [storage deleteCookie:cookie];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Abbrechen" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert];
}

#pragma mark - View paths and color helpers

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

#pragma mark - Lifecycle

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
        [[NSNotificationCenter defaultCenter] addObserver:loader
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        [loader installGestureRecognizers];
        [loader applySavedUIOverrides];
    });
}

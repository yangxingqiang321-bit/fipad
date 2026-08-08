#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NSString *const domainString = @"com.schlub51.fipad";
NSString *const killSwitchPath = @"/var/mobile/fipad.disable";

static BOOL isEnabled;
static BOOL spoofPadIdiomDuringSwitcherLoad;
static double cardScale;
static double cardScaleLandscape;
static double cornerRadius;
static double vertSpacingPort;
static double horizSpacingPort;
static double vertSpacingLand;
static double horizSpacingLand;

static BOOL IsLandscape(void) {
    CGSize size = [UIScreen mainScreen].bounds.size;
    return size.width > size.height;
}

static BOOL KillSwitchActive(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:killSwitchPath];
}

static BOOL TweakActive(void) {
    return isEnabled && !KillSwitchActive();
}

static double SettingsScaledAppExposeValue(double native) {
    if(!TweakActive()) {
        return native;
    }
    double scale;
    if (IsLandscape()) {
        scale = (cardScaleLandscape > 0) ? cardScaleLandscape / 0.30 : cardScale / 0.30;
    } else {
        scale = cardScale / 0.30;
    }
    return native * scale;
}

static double SpacingMultiplier(BOOL vertical) {
    double value;
    if (IsLandscape()) {
        value = vertical ? vertSpacingLand : horizSpacingLand;
    } else {
        value = vertical ? vertSpacingPort : horizSpacingPort;
    }
    if(value <= 0.0) {
        return 1.0;
    }
    return value / 50.0;
}

static double NormalizedSpacingPref(NSUserDefaults *prefs, NSString *key, double fallback, double legacyDefault) {
    id object = [prefs objectForKey:key];
    if(!object) {
        return fallback;
    }
    double value = [object doubleValue];
    if(fabs(value - legacyDefault) < 0.01) {
        return fallback;
    }
    return value;
}

void ReloadPrefs(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:domainString];
    isEnabled = [([prefs objectForKey:@"isEnabled"] ?: @(YES)) boolValue];
    cardScale = [([prefs objectForKey:@"cardScale"] ?: @(0.38)) doubleValue];
    cardScaleLandscape = [([prefs objectForKey:@"cardScaleLandscape"] ?: @(0.38)) doubleValue];
    cornerRadius = [([prefs objectForKey:@"cornerRadius"] ?: @(10)) doubleValue];
    vertSpacingPort = NormalizedSpacingPref(prefs, @"vertSpacingPort", 50.0, 42.0);
    horizSpacingPort = NormalizedSpacingPref(prefs, @"horizSpacingPort", 50.0, 25.5);
    vertSpacingLand = NormalizedSpacingPref(prefs, @"vertSpacingLand", 50.0, 38.0);
    horizSpacingLand = NormalizedSpacingPref(prefs, @"horizSpacingLand", 50.0, 11.6);
}

// ===== 获取应用 Bundle ID =====
static NSString* getBundleIDFromView(UIView *view) {
    if (!view) return nil;
    
    // 方法1：直接通过 appLayout 属性获取
    if ([view respondsToSelector:@selector(appLayout)]) {
        id appLayout = [view performSelector:@selector(appLayout)];
        if (appLayout && [appLayout respondsToSelector:@selector(bundleIdentifier)]) {
            NSString *bundleID = [appLayout performSelector:@selector(bundleIdentifier)];
            if (bundleID.length > 0) return bundleID;
        }
        // 尝试 KVC
        if (appLayout) {
            NSString *bundleID = [appLayout valueForKey:@"bundleIdentifier"];
            if (bundleID.length > 0) return bundleID;
        }
    }
    
    // 方法2：通过 KVC 直接获取
    @try {
        id appLayout = [view valueForKey:@"appLayout"];
        if (appLayout) {
            NSString *bundleID = [appLayout valueForKey:@"bundleIdentifier"];
            if (bundleID.length > 0) return bundleID;
        }
    } @catch (NSException *e) {}
    
    // 方法3：从父视图获取
    UIView *superview = view.superview;
    while (superview) {
        NSString *bundleID = getBundleIDFromView(superview);
        if (bundleID.length > 0) return bundleID;
        superview = superview.superview;
    }
    
    // 方法4：从响应链获取
    UIResponder *responder = view.nextResponder;
    while (responder) {
        if ([responder respondsToSelector:@selector(appLayout)]) {
            id appLayout = [responder performSelector:@selector(appLayout)];
            if (appLayout && [appLayout respondsToSelector:@selector(bundleIdentifier)]) {
                NSString *bundleID = [appLayout performSelector:@selector(bundleIdentifier)];
                if (bundleID.length > 0) return bundleID;
            }
        }
        if ([responder isKindOfClass:[UIViewController class]]) {
            // 检查 view controller 的 view 的子视图
            NSString *bundleID = getBundleIDFromView(((UIViewController *)responder).view);
            if (bundleID.length > 0) return bundleID;
        }
        responder = responder.nextResponder;
    }
    
    return nil;
}

// ===== 判断应用是否支持横屏 =====
static BOOL appSupportsLandscape(NSString *bundleID) {
    if (!bundleID) return YES; // 默认支持，避免误判
    
    // 方法1：通过 LSApplicationProxy
    Class LSApplicationProxy = NSClassFromString(@"LSApplicationProxy");
    if (LSApplicationProxy) {
        id appProxy = [LSApplicationProxy performSelector:@selector(applicationProxyForIdentifier:) withObject:bundleID];
        if (appProxy) {
            NSArray *orientations = [appProxy valueForKey:@"supportedInterfaceOrientations"];
            if (orientations && [orientations isKindOfClass:[NSArray class]]) {
                for (NSNumber *num in orientations) {
                    NSInteger orientation = [num integerValue];
                    if (orientation == UIInterfaceOrientationLandscapeLeft ||
                        orientation == UIInterfaceOrientationLandscapeRight) {
                        return YES;
                    }
                }
                return NO;
            }
        }
    }
    
    // 方法2：通过 SBApplication
    Class SBApplicationController = NSClassFromString(@"SBApplicationController");
    if (SBApplicationController) {
        id controller = [SBApplicationController performSelector:@selector(sharedInstance)];
        if (controller) {
            id appInfo = [controller performSelector:@selector(applicationInfoForBundleIdentifier:) withObject:bundleID];
            if (appInfo) {
                NSArray *orientations = [appInfo valueForKey:@"supportedInterfaceOrientations"];
                if (orientations && [orientations isKindOfClass:[NSArray class]]) {
                    for (NSNumber *num in orientations) {
                        NSInteger orientation = [num integerValue];
                        if (orientation == UIInterfaceOrientationLandscapeLeft ||
                            orientation == UIInterfaceOrientationLandscapeRight) {
                            return YES;
                        }
                    }
                    return NO;
                }
            }
        }
    }
    
    // 默认认为不支持横屏（更安全）
    return NO;
}

// ===== 旋转图片到竖屏（逆时针90度）=====
static UIImage* rotateImageToPortrait(UIImage *image) {
    if (!image) return nil;
    CGSize size = image.size;
    if (size.width <= size.height) return image; // 已经是竖屏
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size.height, size.width), NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(context, size.height, 0);
    CGContextRotateCTM(context, -M_PI_2);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *rotated = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rotated;
}

// ===== 修正不支持横屏 App 的快照 =====
static void fixSnapshotContent(UIView *view) {
    if (!TweakActive() || !IsLandscape()) return;
    
    // 检查是否是快照视图
    Class snapshotClass = NSClassFromString(@"SBAppSwitcherSnapshotView");
    if (snapshotClass && [view isKindOfClass:snapshotClass]) {
        // 获取 bundle ID
        NSString *bundleID = getBundleIDFromView(view);
        
        // 如果获取到 bundle ID 且应用不支持横屏
        if (bundleID && !appSupportsLandscape(bundleID)) {
            // 1. 重置视图变换（去除旋转，保留平移）
            CGAffineTransform transform = view.transform;
            if (transform.a != 1.0 || transform.b != 0.0 || transform.c != 0.0 || transform.d != 1.0) {
                CGAffineTransform identity = CGAffineTransformMakeTranslation(transform.tx, transform.ty);
                view.transform = identity;
            }
            
            // 2. 修正快照内容中的图片
            for (UIView *subview in view.subviews) {
                if ([subview isKindOfClass:[UIImageView class]]) {
                    UIImageView *imageView = (UIImageView *)subview;
                    UIImage *image = imageView.image;
                    if (image && image.size.width > image.size.height) {
                        UIImage *rotated = rotateImageToPortrait(image);
                        if (rotated != image) {
                            imageView.image = rotated;
                        }
                    }
                }
            }
        }
        return;
    }
    
    // 递归处理子视图
    for (UIView *subview in view.subviews) {
        fixSnapshotContent(subview);
    }
}

%hook SBAppSwitcherSettings

- (long long)switcherStyle {
    if(TweakActive()) {
        return 2;
    }
    return %orig;
}

- (double)appExposeNonFloatingSingleRowScale {
    double orig = %orig;
    return SettingsScaledAppExposeValue(orig);
}

- (double)appExposeNonFloatingDoubleRowScale {
    double orig = %orig;
    return SettingsScaledAppExposeValue(orig);
}

- (double)appExposeFloatingDoubleRowScale {
    double orig = %orig;
    return SettingsScaledAppExposeValue(orig);
}

- (double)gridSwitcherHorizontalInterpageSpacingPortrait {
    double value = %orig;
    if(TweakActive()) {
        value *= SpacingMultiplier(NO);
    }
    return value;
}

- (double)gridSwitcherVerticalNaturalSpacingPortrait {
    double value = %orig;
    if(TweakActive()) {
        value *= SpacingMultiplier(YES);
    }
    return value;
}

- (double)gridSwitcherHorizontalInterpageSpacingLandscape {
    double value = %orig;
    if(TweakActive()) {
        value *= SpacingMultiplier(NO);
    }
    return value;
}

- (double)gridSwitcherVerticalNaturalSpacingLandscape {
    double value = %orig;
    if(TweakActive()) {
        value *= SpacingMultiplier(YES);
    }
    return value;
}

- (double)spacingBetweenLeadingEdgeAndIcon {
    double value = %orig;
    if(TweakActive()) {
        return MIN(value, 8.0);
    }
    return value;
}

%end

%hook SBMixedGridSwitcherModifier

- (double)_cardCornerRadiusInSwitcher {
    if(TweakActive()) {
        return cornerRadius;
    }
    return %orig;
}

- (void)layoutSubviews {
    %orig;
    if (TweakActive() && IsLandscape()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            fixSnapshotContent((UIView *)self);
        });
    }
}

%end

%hook UIDevice

- (long long)userInterfaceIdiom {
    if(TweakActive() && spoofPadIdiomDuringSwitcherLoad) {
        return 1;
    }
    return %orig;
}

%end

%hook SBFluidSwitcherViewController

- (BOOL)isDevicePad {
    if(TweakActive()) {
        return YES;
    }
    return %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (TweakActive() && IsLandscape()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            fixSnapshotContent([(UIViewController *)self view]);
        });
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    %orig;
    if (TweakActive()) {
        [coordinator animateAlongsideTransition:nil completion:^(id context) {
            if (IsLandscape()) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    fixSnapshotContent([(UIViewController *)self view]);
                });
            }
        }];
    }
}

%end

%hook SBMainSwitcherControllerCoordinator

- (void)_loadContentViewControllerIfNecessaryForWindowScene:(id)windowScene {
    if(!TweakActive()) {
        %orig(windowScene);
        return;
    }

    spoofPadIdiomDuringSwitcherLoad = YES;
    %orig(windowScene);
    spoofPadIdiomDuringSwitcherLoad = NO;
}

%end

%ctor {
    if(KillSwitchActive()) {
        return;
    }

    ReloadPrefs();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)ReloadPrefs,
        CFSTR("com.schlub51.fipad.changed"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );

    %init;
}
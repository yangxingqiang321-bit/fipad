#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MobileCoreServices/LSApplicationProxy.h>

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

// ===== 判断应用是否支持横屏 =====
static BOOL appSupportsLandscape(NSString *bundleID) {
    LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
    if (!appProxy) return NO;
    
    // 获取支持的方向数组
    NSArray *supportedOrientations = [appProxy performSelector:@selector(supportedInterfaceOrientations)];
    if (!supportedOrientations) return NO;
    
    // 检查是否包含横屏方向（UIInterfaceOrientationLandscapeLeft 或 Right）
    for (NSNumber *num in supportedOrientations) {
        UIInterfaceOrientation orientation = [num integerValue];
        if (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) {
            return YES;
        }
    }
    return NO;
}

// ===== 修正快照内容 =====
static void fixSnapshotContent(UIView *view) {
    if (!TweakActive() || !IsLandscape()) return;
    
    Class snapshotClass = NSClassFromString(@"SBAppSwitcherSnapshotView");
    if (snapshotClass && [view isKindOfClass:snapshotClass]) {
        // 获取应用标识符
        NSString *bundleID = nil;
        if ([view respondsToSelector:@selector(appLayout)]) {
            id appLayout = [view performSelector:@selector(appLayout)];
            if (appLayout && [appLayout respondsToSelector:@selector(bundleIdentifier)]) {
                bundleID = [appLayout performSelector:@selector(bundleIdentifier)];
            }
        }
        
        // 如果应用不支持横屏，则修正快照方向
        if (bundleID && !appSupportsLandscape(bundleID)) {
            // 将快照视图的变换重置为恒等（去除旋转）
            CGAffineTransform transform = view.transform;
            if (transform.a != 1.0 || transform.b != 0.0 || transform.c != 0.0 || transform.d != 1.0) {
                CGAffineTransform identity = CGAffineTransformMakeTranslation(transform.tx, transform.ty);
                view.transform = identity;
            }
            
            // 旋转图片内容为竖屏（逆时针90度）
            [view.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull subview, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([subview isKindOfClass:[UIImageView class]]) {
                    UIImageView *imageView = (UIImageView *)subview;
                    UIImage *image = imageView.image;
                    if (image && image.size.width > image.size.height) { // 横屏图片
                        // 旋转为竖屏
                        UIGraphicsBeginImageContextWithOptions(CGSizeMake(image.size.height, image.size.width), NO, image.scale);
                        CGContextRef context = UIGraphicsGetCurrentContext();
                        CGContextTranslateCTM(context, image.size.height, 0);
                        CGContextRotateCTM(context, -M_PI_2);
                        [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
                        UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
                        UIGraphicsEndImageContext();
                        imageView.image = rotatedImage;
                    }
                }
            }];
        }
        return;
    }
    
    // 递归子视图
    [view.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull subview, NSUInteger idx, BOOL * _Nonnull stop) {
        fixSnapshotContent(subview);
    }];
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            fixSnapshotContent([(UIViewController *)self view]);
        });
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
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSString *const domainString = @"com.schlub51.fipad";
NSString *const killSwitchPath = @"/var/mobile/fipad.disable";

static BOOL isEnabled;
static BOOL spoofPadIdiomDuringSwitcherLoad;
static double cardScale;
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
    double scale = cardScale / 0.30;
    if(IsLandscape()) {
        scale *= 0.55;   // 缩小卡片，即使旋转也不至于太夸张
    }
    return native * scale;
}

static double SpacingMultiplier(BOOL vertical) {
    double value = 0.0;
    // 横竖屏都用竖屏的间距值，保证一致
    value = vertical ? vertSpacingPort : horizSpacingPort;
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
    cornerRadius = [([prefs objectForKey:@"cornerRadius"] ?: @(10)) doubleValue];
    vertSpacingPort = NormalizedSpacingPref(prefs, @"vertSpacingPort", 50.0, 42.0);
    horizSpacingPort = NormalizedSpacingPref(prefs, @"horizSpacingPort", 50.0, 25.5);
    vertSpacingLand = NormalizedSpacingPref(prefs, @"vertSpacingLand", 50.0, 38.0);
    horizSpacingLand = NormalizedSpacingPref(prefs, @"horizSpacingLand", 50.0, 11.6);
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
    if(TweakActive()) {
        // 直接返回竖屏值
        return [self gridSwitcherHorizontalInterpageSpacingPortrait];
    }
    return %orig;
}

- (double)gridSwitcherVerticalNaturalSpacingLandscape {
    if(TweakActive()) {
        return [self gridSwitcherVerticalNaturalSpacingPortrait];
    }
    return %orig;
}

- (double)spacingBetweenLeadingEdgeAndIcon {
    double value = %orig;
    if(TweakActive()) {
        return MIN(value, 8.0);
    }
    return value;
}

// 尝试多个可能的旋转控制方法
- (BOOL)shouldRotateSnapshotsInSwitcher {
    if(TweakActive() && IsLandscape()) {
        return NO;
    }
    return %orig;
}

- (BOOL)shouldAutorotateSnapshots {
    if(TweakActive() && IsLandscape()) {
        return NO;
    }
    return %orig;
}

- (BOOL)allowsSnapshotsRotation {
    if(TweakActive() && IsLandscape()) {
        return NO;
    }
    return %orig;
}

- (BOOL)rotateSnapshots {
    if(TweakActive() && IsLandscape()) {
        return NO;
    }
    return %orig;
}

%end

%hook SBMixedGridSwitcherModifier

- (double)_cardCornerRadiusInSwitcher {
    if(TweakActive()) {
        return cornerRadius;
    }
    return %orig;
}

// 在布局完成后，尝试重置快照变换
- (void)layoutSubviews {
    %orig;
    if(TweakActive() && IsLandscape()) {
        // 遍历子视图，找到快照视图并重置变换
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:NSClassFromString(@"SBAppSwitcherSnapshotView")] ||
                [subview isKindOfClass:NSClassFromString(@"SBSwitcherSnapshotView")]) {
                if (!CGAffineTransformIsIdentity(subview.transform)) {
                    subview.transform = CGAffineTransformIdentity;
                }
            }
        }
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

// 强制切换器在横屏时也不旋转
- (BOOL)shouldAutorotate {
    if(TweakActive() && IsLandscape()) {
        return NO;
    }
    return %orig;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if(TweakActive() && IsLandscape()) {
        return UIInterfaceOrientationPortrait;
    }
    return %orig;
}

// 在视图出现时重置所有快照变换
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if(TweakActive() && IsLandscape()) {
        [self resetSnapshotTransformsInView:self.view];
    }
}

- (void)resetSnapshotTransformsInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"SBAppSwitcherSnapshotView")] ||
            [subview isKindOfClass:NSClassFromString(@"SBSwitcherSnapshotView")] ||
            [subview isKindOfClass:NSClassFromString(@"SBAppSwitcherPageView")]) {
            if (!CGAffineTransformIsIdentity(subview.transform)) {
                subview.transform = CGAffineTransformIdentity;
            }
        }
        [self resetSnapshotTransformsInView:subview];
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
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)ReloadPrefs,
        CFSTR("com.schlub51.fipad.changed"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    %init;
}
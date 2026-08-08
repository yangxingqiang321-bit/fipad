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
    // 横屏时不再强制缩小，让系统原生处理
    return native * scale;
}

static double SpacingMultiplier(BOOL vertical) {
    double value = vertical ? vertSpacingPort : horizSpacingPort;
    if(value <= 0.0) {
        return 1.0;
    }
    return value / 50.0;
}

static double NormalizedSpacingPref(NSUserDefaults *prefs,
                                    NSString *key,
                                    double fallback,
                                    double legacyDefault) {
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
    NSUserDefaults *prefs =
    [[NSUserDefaults alloc] initWithSuiteName:domainString];

    isEnabled =
    [([prefs objectForKey:@"isEnabled"] ?: @(YES)) boolValue];

    cardScale =
    [([prefs objectForKey:@"cardScale"] ?: @(0.38)) doubleValue];

    cornerRadius =
    [([prefs objectForKey:@"cornerRadius"] ?: @(10)) doubleValue];

    vertSpacingPort =
    NormalizedSpacingPref(prefs,
                          @"vertSpacingPort",
                          50.0,
                          42.0);

    horizSpacingPort =
    NormalizedSpacingPref(prefs,
                          @"horizSpacingPort",
                          50.0,
                          25.5);

    vertSpacingLand =
    NormalizedSpacingPref(prefs,
                          @"vertSpacingLand",
                          50.0,
                          38.0);

    horizSpacingLand =
    NormalizedSpacingPref(prefs,
                          @"horizSpacingLand",
                          50.0,
                          11.6);
}

%hook SBAppSwitcherSettings

- (long long)switcherStyle {
    // 竖屏启用网格，横屏回到原生
    if(TweakActive() && !IsLandscape()) {
        return 2;  // iPad 网格
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

%end

// 必要的伪装，仅在竖屏且启用时有效
%hook UIDevice

- (long long)userInterfaceIdiom {
    if(TweakActive() && spoofPadIdiomDuringSwitcherLoad && !IsLandscape()) {
        return 1;  // 伪装为 iPad
    }
    return %orig;
}

%end

%hook SBFluidSwitcherViewController

- (BOOL)isDevicePad {
    if(TweakActive() && !IsLandscape()) {
        return YES;
    }
    return %orig;
}

%end

%hook SBMainSwitcherControllerCoordinator

- (void)_loadContentViewControllerIfNecessaryForWindowScene:(id)windowScene {
    if(!TweakActive()) {
        %orig(windowScene);
        return;
    }

    // 只在竖屏时启用伪装
    if(!IsLandscape()) {
        spoofPadIdiomDuringSwitcherLoad = YES;
        %orig(windowScene);
        spoofPadIdiomDuringSwitcherLoad = NO;
    } else {
        %orig(windowScene);
    }
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
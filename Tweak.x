#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSString *const domainString = @"com.schlub51.fipad";
NSString *const killSwitchPath = @"/var/mobile/fipad.disable";

static BOOL isEnabled;
static double cardScale;
static double cardScaleLandscape;
static double cornerRadius;
static double vertSpacingPort;
static double horizSpacingPort;
static double vertSpacingLand;
static double horizSpacingLand;

static uint16_t forcePadIdiom = 0;

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
    if(!TweakActive()) return native;
    double scale = IsLandscape() && cardScaleLandscape > 0 ? cardScaleLandscape / 0.30 : cardScale / 0.30;
    return native * scale;
}

static double SpacingMultiplier(BOOL vertical) {
    double value = IsLandscape() ? (vertical ? vertSpacingLand : horizSpacingLand) : (vertical ? vertSpacingPort : horizSpacingPort);
    if(value <= 0.0) return 1.0;
    return value / 50.0;
}

static double NormalizedSpacingPref(NSUserDefaults *prefs, NSString *key, double fallback, double legacyDefault) {
    id object = [prefs objectForKey:key];
    if(!object) return fallback;
    double value = [object doubleValue];
    if(fabs(value - legacyDefault) < 0.01) return fallback;
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

// ===== 临时伪装 iPad =====
%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (forcePadIdiom > 0) return UIUserInterfaceIdiomPad;
    return %orig;
}
%end

// ===== 切换器加载时启用伪装 =====
%hook SBMainSwitcherControllerCoordinator
- (void)_loadContentViewControllerIfNecessaryForWindowScene:(id)windowScene {
    if(!TweakActive()) { %orig(windowScene); return; }
    forcePadIdiom++;
    %orig(windowScene);
    forcePadIdiom--;
}
%end

%hook SBFullScreenSwitcherLiveContentOverlayCoordinator
- (void)layoutStateTransitionCoordinator:(id)arg1 transitionDidBeginWithTransitionContext:(id)arg2 {
    if(!TweakActive()) { %orig; return; }
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end

%hook SBSwitcherController
- (void)_updateContentViewControllerIfNeeded {
    if(!TweakActive()) { %orig; return; }
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end

// ===== 强制网格样式 =====
%hook SBAppSwitcherSettings
- (NSInteger)effectiveSwitcherStyle {
    if(TweakActive()) return 2;
    return %orig;
}
- (long long)switcherStyle {
    if(TweakActive()) return 2;
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
    if(TweakActive()) value *= SpacingMultiplier(NO);
    return value;
}
- (double)gridSwitcherVerticalNaturalSpacingPortrait {
    double value = %orig;
    if(TweakActive()) value *= SpacingMultiplier(YES);
    return value;
}
- (double)gridSwitcherHorizontalInterpageSpacingLandscape {
    double value = %orig;
    if(TweakActive()) value *= SpacingMultiplier(NO);
    return value;
}
- (double)gridSwitcherVerticalNaturalSpacingLandscape {
    double value = %orig;
    if(TweakActive()) value *= SpacingMultiplier(YES);
    return value;
}
- (double)spacingBetweenLeadingEdgeAndIcon {
    double value = %orig;
    if(TweakActive()) return MIN(value, 8.0);
    return value;
}
%end

// ===== 卡片圆角 =====
%hook SBMixedGridSwitcherModifier
- (double)_cardCornerRadiusInSwitcher {
    if(TweakActive()) return cornerRadius;
    return %orig;
}
%end

// ===== 必要支持（不产生额外 UI）=====
%hook SBPlatformController
- (NSInteger)medusaCapabilities {
    if(TweakActive()) return 2;
    return %orig;
}
%end

%hook SBApplication
- (BOOL)isMedusaCapable {
    if(TweakActive()) return YES;
    return %orig;
}
- (BOOL)_supportsApplicationType:(int)arg1 {
    if(TweakActive()) return YES;
    return %orig;
}
%end

%hook SBMainWorkspace
- (BOOL)isMedusaEnabled {
    if(TweakActive()) return YES;
    return %orig;
}
%end

%hook SBFluidSwitcherViewController
- (BOOL)isDevicePad {
    if(TweakActive()) return YES;
    return %orig;
}
%end

// ===== 额外修复方向问题 =====
%hook SBTraitsSceneParticipantDelegate
- (BOOL)_isAllowedToHavePortraitUpsideDown {
    return YES;
}
- (NSInteger)_orientationMode {
    forcePadIdiom++;
    NSInteger result = %orig;
    forcePadIdiom--;
    return result;
}
%end

%ctor {
    if(KillSwitchActive()) return;
    ReloadPrefs();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)ReloadPrefs,
        CFSTR("com.schlub51.fipad.changed"), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    %init;
}
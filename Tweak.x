#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

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

// ===== 一键清后台功能（基于 QuitAll 安全实现）=====
static void killAllAppsSafe(void) {
    Class switcherClass = NSClassFromString(@"SBMainSwitcherViewController");
    id mainSwitcher = [switcherClass performSelector:@selector(sharedInstance)];
    if (!mainSwitcher) return;

    NSArray *items = [mainSwitcher valueForKey:@"recentAppLayouts"];
    if (!items) return;

    Class mediaController = NSClassFromString(@"SBMediaController");
    id mediaInstance = [mediaController performSelector:@selector(sharedInstance)];
    id nowPlayingApp = [mediaInstance valueForKey:@"nowPlayingApplication"];
    NSString *nowPlayingID = [nowPlayingApp valueForKey:@"bundleIdentifier"];

    for (id item in items) {
        NSString *bundleID = nil;
        if (@available(iOS 14.0, *)) {
            NSArray *allItems = [item valueForKey:@"allItems"];
            if (allItems.count > 0) {
                id displayItem = allItems[0];
                bundleID = [displayItem valueForKey:@"bundleIdentifier"];
            }
        } else {
            NSDictionary *rolesMap = [item valueForKey:@"rolesToLayoutItemsMap"];
            id displayItem = rolesMap[@1];
            bundleID = [displayItem valueForKey:@"bundleIdentifier"];
        }

        if (bundleID && ![bundleID isEqualToString:nowPlayingID]) {
            if (@available(iOS 14.0, *)) {
                [mainSwitcher performSelector:@selector(_deleteAppLayoutsMatchingBundleIdentifier:) withObject:bundleID];
            } else {
                [mainSwitcher performSelector:@selector(_deleteAppLayout:forReason:) withObject:item withObject:@1];
            }
        }
    }
}

// ===== TrollPad 核心：forcePadIdiom 计数器 =====
static uint16_t forcePadIdiom = 0;

%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (forcePadIdiom > 0) {
        return UIUserInterfaceIdiomPad;
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
    forcePadIdiom++;
    %orig(windowScene);
    forcePadIdiom--;
}
%end

%hook SBFullScreenSwitcherLiveContentOverlayCoordinator
- (void)layoutStateTransitionCoordinator:(id)arg1 transitionDidBeginWithTransitionContext:(id)arg2 {
    if(!TweakActive()) {
        %orig;
        return;
    }
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end

%hook SBSwitcherController
- (void)_updateContentViewControllerIfNeeded {
    if(!TweakActive()) {
        %orig;
        return;
    }
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end

%hook SBAppSwitcherSettings
- (NSInteger)effectiveSwitcherStyle {
    if(TweakActive()) {
        return 2;
    }
    return %orig;
}
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
%end

%hook SBPlatformController
- (NSInteger)medusaCapabilities {
    if(TweakActive()) {
        return 2;
    }
    return %orig;
}
%end

%hook SBApplication
- (BOOL)isMedusaCapable {
    if(TweakActive()) {
        return YES;
    }
    return %orig;
}
- (BOOL)_supportsApplicationType:(int)arg1 {
    if(TweakActive()) {
        return YES;
    }
    return %orig;
}
%end

%hook SBMainWorkspace
- (BOOL)isMedusaEnabled {
    if(TweakActive()) {
        return YES;
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

// ===== 添加底部一键关闭按钮 =====
- (void)viewDidLoad {
    %orig;
    if (TweakActive()) {
        [(id)self performSelector:@selector(addKillAllButton) withObject:nil afterDelay:0.1];
    }
}

- (void)addKillAllButton {
    UIViewController *vc = (UIViewController *)self;
    UIView *view = vc.view;
    if ([view viewWithTag:8888]) return;

    UIButton *killBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    killBtn.tag = 8888;
    killBtn.frame = CGRectMake(view.bounds.size.width/2 - 30,
                               view.bounds.size.height - 70,
                               60, 60);
    killBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
    killBtn.layer.cornerRadius = 30;
    killBtn.layer.borderWidth = 1;
    killBtn.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.3].CGColor;
    [killBtn setTitle:@"✕" forState:UIControlStateNormal];
    [killBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    killBtn.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [killBtn addTarget:self action:@selector(killAllButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:killBtn];
}

- (void)killAllButtonTapped {
    if (TweakActive()) {
        killAllAppsSafe();
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    UIView *view = vc.view;
    UIButton *killBtn = [view viewWithTag:8888];
    if (killBtn) {
        killBtn.frame = CGRectMake(view.bounds.size.width/2 - 30,
                                   view.bounds.size.height - 70,
                                   60, 60);
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
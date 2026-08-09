#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

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

static NSMutableSet *lockedBundleIDs = nil;
static NSDate *lastGlobalSwipeTime = nil;
static NSDate *lastCardSwipeTime = nil;

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

static NSString* getBundleIDFromContainer(UIView *container) {
    id appLayout = [container valueForKey:@"_appLayout"];
    if (!appLayout) return nil;
    NSString *bundleID = [appLayout valueForKey:@"bundleIdentifier"];
    return bundleID;
}

static void killAppWithBundleID(NSString *bundleID) {
    if (!bundleID) return;
    Class appController = NSClassFromString(@"SBApplicationController");
    id app = [appController performSelector:@selector(applicationWithBundleIdentifier:) withObject:bundleID];
    if (app && [app respondsToSelector:@selector(kill)]) {
        [app performSelector:@selector(kill)];
    }
}

static void killAllUnlockedApps() {
    Class switcherModel = NSClassFromString(@"SBAppSwitcherModel");
    if (!switcherModel) switcherModel = NSClassFromString(@"SBSwitcherModel");
    id model = [switcherModel performSelector:@selector(sharedInstance)];
    NSArray *items = [model valueForKey:@"displayItems"];
    if (!items) return;
    for (id item in items) {
        NSString *bundleID = [item valueForKey:@"bundleIdentifier"];
        if (bundleID && ![lockedBundleIDs containsObject:bundleID]) {
            killAppWithBundleID(bundleID);
        }
    }
}

static void updateLockIconForContainer(UIView *container, NSString *bundleID) {
    UIView *existingLock = [container viewWithTag:9999];
    [existingLock removeFromSuperview];
    if ([lockedBundleIDs containsObject:bundleID]) {
        UILabel *lockLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 28, 28)];
        lockLabel.tag = 9999;
        lockLabel.text = @"🔒";
        lockLabel.font = [UIFont systemFontOfSize:16];
        lockLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        lockLabel.layer.cornerRadius = 14;
        lockLabel.clipsToBounds = YES;
        lockLabel.textAlignment = NSTextAlignmentCenter;
        [container addSubview:lockLabel];
    }
}

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

// ===== 新增功能 =====
%hook SBFluidSwitcherViewController

- (BOOL)isDevicePad {
    if(TweakActive()) {
        return YES;
    }
    return %orig;
}

- (void)viewDidLoad {
    %orig;
    if (TweakActive()) {
        // 使用 id 强制转换，避免编译错误
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
        killAllUnlockedApps();
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

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (TweakActive()) {
        [(id)self performSelector:@selector(setupGlobalSwipeGesture)];
    }
}

- (void)setupGlobalSwipeGesture {
    UIViewController *vc = (UIViewController *)self;
    UIView *view = vc.view;
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if ([g isKindOfClass:[UISwipeGestureRecognizer class]] &&
            ((UISwipeGestureRecognizer *)g).direction == UISwipeGestureRecognizerDirectionDown) {
            return;
        }
    }
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleGlobalSwipeDown:)];
    swipe.direction = UISwipeGestureRecognizerDirectionDown;
    [view addGestureRecognizer:swipe];
}

- (void)handleGlobalSwipeDown:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded && TweakActive()) {
        NSDate *now = [NSDate date];
        if (lastGlobalSwipeTime) {
            NSTimeInterval interval = [now timeIntervalSinceDate:lastGlobalSwipeTime];
            if (interval < 0.5) {
                lastGlobalSwipeTime = nil;
                return;
            }
        }
        lastGlobalSwipeTime = now;
        killAllUnlockedApps();
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    for (UIView *subview in vc.view.subviews) {
        if (subview.tag == 9999) [subview removeFromSuperview];
    }
}

%end

// ===== 卡片锁定 =====
%hook SBFluidSwitcherItemContainer

- (void)didMoveToWindow {
    %orig;
    if (!TweakActive()) return;
    UIView *view = (UIView *)self;
    if (!view.window) return;
    for (UIGestureRecognizer *g in view.gestureRecognizers) {
        if ([g isKindOfClass:[UISwipeGestureRecognizer class]] &&
            ((UISwipeGestureRecognizer *)g).direction == UISwipeGestureRecognizerDirectionDown) {
            return;
        }
    }
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleCardSwipeDown:)];
    swipe.direction = UISwipeGestureRecognizerDirectionDown;
    [view addGestureRecognizer:swipe];
}

- (void)handleCardSwipeDown:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !TweakActive()) return;
    
    UIView *view = (UIView *)self;
    NSString *bundleID = getBundleIDFromContainer(view);
    if (!bundleID) return;
    
    NSDate *now = [NSDate date];
    BOOL isDoubleSwipe = NO;
    if (lastCardSwipeTime) {
        NSTimeInterval interval = [now timeIntervalSinceDate:lastCardSwipeTime];
        if (interval < 0.5) {
            isDoubleSwipe = YES;
        }
    }
    lastCardSwipeTime = now;
    
    if (isDoubleSwipe) {
        if ([lockedBundleIDs containsObject:bundleID]) {
            [lockedBundleIDs removeObject:bundleID];
        } else {
            [lockedBundleIDs addObject:bundleID];
        }
        updateLockIconForContainer(view, bundleID);
        AudioServicesPlaySystemSound(1519);
    }
}

%end

%ctor {
    if(KillSwitchActive()) {
        return;
    }

    lockedBundleIDs = [[NSMutableSet alloc] init];
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
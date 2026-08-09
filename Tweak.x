#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

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

// ===== 新增：锁定集合和手势时间 =====
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

// ===== 辅助函数：获取 Bundle ID =====
static NSString* getBundleIDFromContainer(UIView *container) {
    id appLayout = [container valueForKey:@"_appLayout"];
    if (!appLayout) return nil;
    NSString *bundleID = [appLayout valueForKey:@"bundleIdentifier"];
    return bundleID;
}

// ===== 关闭单个应用 =====
static void killAppWithBundleID(NSString *bundleID) {
    if (!bundleID) return;
    Class appController = NSClassFromString(@"SBApplicationController");
    id app = [appController performSelector:@selector(applicationWithBundleIdentifier:) withObject:bundleID];
    if (app && [app respondsToSelector:@selector(kill)]) {
        [app performSelector:@selector(kill)];
    }
}

// ===== 关闭所有未锁定的应用 =====
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

// ===== 更新锁定图标 =====
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

// ===== 新增：底部一键关闭按钮 =====
- (void)viewDidLoad {
    %orig;
    if (TweakActive()) {
        [self performSelector:@selector(addKillAllButton) withObject:nil afterDelay:0.1];
    }
}

- (void)addKillAllButton {
    if ([self.view viewWithTag:8888]) return;
    UIButton *killBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    killBtn.tag = 8888;
    killBtn.frame = CGRectMake(self.view.bounds.size.width/2 - 30,
                               self.view.bounds.size.height - 70,
                               60, 60);
    killBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
    killBtn.layer.cornerRadius = 30;
    killBtn.layer.borderWidth = 1;
    killBtn.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.3].CGColor;
    [killBtn setTitle:@"✕" forState:UIControlStateNormal];
    [killBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    killBtn.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [killBtn addTarget:self action:@selector(killAllButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:killBtn];
}

- (void)killAllButtonTapped {
    if (TweakActive()) {
        killAllUnlockedApps();
        // 震动反馈
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIButton *killBtn = [self.view viewWithTag:8888];
    if (killBtn) {
        killBtn.frame = CGRectMake(self.view.bounds.size.width/2 - 30,
                                   self.view.bounds.size.height - 70,
                                   60, 60);
    }
}

// ===== 新增：全局下滑手势（一键清后台） =====
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (TweakActive()) {
        [self setupGlobalSwipeGesture];
    }
}

- (void)setupGlobalSwipeGesture {
    // 检查是否已存在
    for (UIGestureRecognizer *g in self.view.gestureRecognizers) {
        if ([g isKindOfClass:[UISwipeGestureRecognizer class]] && 
            ((UISwipeGestureRecognizer *)g).direction == UISwipeGestureRecognizerDirectionDown &&
            [g targetForAction:@selector(handleGlobalSwipeDown:)]) {
            return;
        }
    }
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleGlobalSwipeDown:)];
    swipe.direction = UISwipeGestureRecognizerDirectionDown;
    [self.view addGestureRecognizer:swipe];
}

- (void)handleGlobalSwipeDown:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded && TweakActive()) {
        NSDate *now = [NSDate date];
        if (lastGlobalSwipeTime) {
            NSTimeInterval interval = [now timeIntervalSinceDate:lastGlobalSwipeTime];
            if (interval < 0.5) {
                lastGlobalSwipeTime = nil;
                return; // 连续两次下滑，不触发清后台，交给卡片处理锁定
            }
        }
        lastGlobalSwipeTime = now;
        killAllUnlockedApps();
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    // 清理锁图标
    for (UIView *subview in self.view.subviews) {
        if (subview.tag == 9999) [subview removeFromSuperview];
    }
}
%end

// ===== 新增：卡片下滑两次锁定 =====
%hook SBFluidSwitcherItemContainer

- (void)didMoveToWindow {
    %orig;
    if (!TweakActive()) return;
    if (!self.window) return;
    // 检查是否已存在下滑手势
    for (UIGestureRecognizer *g in self.gestureRecognizers) {
        if ([g isKindOfClass:[UISwipeGestureRecognizer class]] && 
            ((UISwipeGestureRecognizer *)g).direction == UISwipeGestureRecognizerDirectionDown) {
            return;
        }
    }
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleCardSwipeDown:)];
    swipe.direction = UISwipeGestureRecognizerDirectionDown;
    [self addGestureRecognizer:swipe];
}

- (void)handleCardSwipeDown:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !TweakActive()) return;
    
    NSString *bundleID = getBundleIDFromContainer(self);
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
        // 切换锁定状态
        if ([lockedBundleIDs containsObject:bundleID]) {
            [lockedBundleIDs removeObject:bundleID];
        } else {
            [lockedBundleIDs addObject:bundleID];
        }
        updateLockIconForContainer(self, bundleID);
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
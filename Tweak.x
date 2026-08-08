#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

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

// ===== MobileGestalt 相关 =====
static NSMutableDictionary *originalGestaltValues;
static BOOL isPadSpoofed = NO;

// MobileGestalt 函数指针
static CFTypeRef (*MGCopyAnswer)(CFStringRef question);
static void (*MGSetAnswer)(CFStringRef question, CFTypeRef answer);

// 关键键值
#define kMGQProductType CFSTR("ProductType")
#define kMGQDeviceClass CFSTR("DeviceClass")
#define kMGQDeviceClassNumber CFSTR("DeviceClassNumber")
#define kMGQSupportsMultitasking CFSTR("SupportsMultitasking")
#define kMGQSupportsVoiceOver CFSTR("SupportsVoiceOver")

// ===== 工具函数：获取/设置 Gestalt 值 =====
static CFTypeRef getGestaltAnswer(CFStringRef key) {
    if (!MGCopyAnswer) return NULL;
    return MGCopyAnswer(key);
}

static void setGestaltAnswer(CFStringRef key, CFTypeRef value) {
    if (!MGSetAnswer) return;
    MGSetAnswer(key, value);
}

// ===== 备份原始值 =====
static void backupGestaltValues(void) {
    originalGestaltValues = [NSMutableDictionary dictionary];
    
    NSArray *keys = @[
        (__bridge id)kMGQProductType,
        (__bridge id)kMGQDeviceClass,
        (__bridge id)kMGQDeviceClassNumber,
        (__bridge id)kMGQSupportsMultitasking,
        (__bridge id)kMGQSupportsVoiceOver
    ];
    
    for (id key in keys) {
        CFStringRef cfKey = (__bridge CFStringRef)key;
        CFTypeRef value = getGestaltAnswer(cfKey);
        if (value) {
            originalGestaltValues[key] = (__bridge id)value;
        }
    }
}

// ===== 应用 iPad 伪装 =====
static void applyPadSpoof(void) {
    if (isPadSpoofed) return;
    if (!originalGestaltValues) {
        backupGestaltValues();
    }
    
    // 设置为 iPad 的标识
    setGestaltAnswer(kMGQProductType, CFSTR("iPad13,8"));  // iPad Pro 11-inch (3rd gen)
    setGestaltAnswer(kMGQDeviceClass, CFSTR("iPad"));
    setGestaltAnswer(kMGQDeviceClassNumber, CFSTR("6"));   // iPad 设备类编号
    setGestaltAnswer(kMGQSupportsMultitasking, kCFBooleanTrue);
    setGestaltAnswer(kMGQSupportsVoiceOver, kCFBooleanTrue);
    
    isPadSpoofed = YES;
}

// ===== 恢复原始值 =====
static void revertPadSpoof(void) {
    if (!isPadSpoofed) return;
    if (!originalGestaltValues) return;
    
    for (id key in originalGestaltValues) {
        CFStringRef cfKey = (__bridge CFStringRef)key;
        id value = originalGestaltValues[key];
        if (value) {
            setGestaltAnswer(cfKey, (__bridge CFTypeRef)value);
        }
    }
    
    isPadSpoofed = NO;
}

// ===== 初始化 MobileGestalt =====
static void initMobileGestalt(void) {
    void *handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!handle) return;
    
    MGCopyAnswer = (CFTypeRef (*)(CFStringRef))dlsym(handle, "MGCopyAnswer");
    MGSetAnswer = (void (*)(CFStringRef, CFTypeRef))dlsym(handle, "MGSetAnswer");
    
    if (MGCopyAnswer && MGSetAnswer) {
        backupGestaltValues();
    }
}

// ===== 判断横竖屏 =====
static BOOL IsLandscape(void) {
    CGSize size = [UIScreen mainScreen].bounds.size;
    return size.width > size.height;
}

// ===== 开关和设置 =====
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

// ===== 修改 SpringBoard 的 UIApplication 初始化，让系统启动时就认为自己是 iPad =====
%hook UIApplication

- (BOOL)_isSpringBoard {
    BOOL orig = %orig;
    if (TweakActive() && !isPadSpoofed) {
        applyPadSpoof();
    }
    return orig;
}

%end

// ===== 确保切换器样式为网格 =====
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

// ===== 卡片圆角 =====
%hook SBMixedGridSwitcherModifier

- (double)_cardCornerRadiusInSwitcher {
    if(TweakActive()) {
        return cornerRadius;
    }
    return %orig;
}

%end

// ===== 恢复伪装（防止影响其他应用）=====
%hook UIApplication

- (void)dealloc {
    if (isPadSpoofed) {
        revertPadSpoof();
    }
    %orig;
}

%end

// ===== 构造 =====
%ctor {
    if(KillSwitchActive()) {
        return;
    }

    // 初始化 MobileGestalt
    initMobileGestalt();

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
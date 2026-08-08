#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSString *const domainString = @"com.schlub51.fipad";
NSString *const killSwitchPath = @"/var/mobile/fipad.disable";

static BOOL isEnabled;
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

    /*
     不再强制横屏卡片缩小
     让系统根据 App 自己方向处理
    */

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

    if(TweakActive()) {
        return 2;
    }

    return %orig;
}



- (double)appExposeNonFloatingSingleRowScale {

    return SettingsScaledAppExposeValue(%orig);

}


- (double)appExposeNonFloatingDoubleRowScale {

    return SettingsScaledAppExposeValue(%orig);

}


- (double)appExposeFloatingDoubleRowScale {

    return SettingsScaledAppExposeValue(%orig);

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
        return MIN(value,8.0);
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



/*
 删除：
 UIDevice spoof

 删除：
 SBMainSwitcherControllerCoordinator spoof

 保留真实 App orientation
*/


%hook SBFluidSwitcherViewController


- (BOOL)isDevicePad {

    /*
     不伪装 iPad
     让 App 自己决定横竖屏
    */

    return %orig;

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
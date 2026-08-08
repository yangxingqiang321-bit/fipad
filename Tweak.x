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


static BOOL KillSwitchActive(void)
{
    return [[NSFileManager defaultManager]
            fileExistsAtPath:killSwitchPath];
}


static BOOL TweakActive(void)
{
    return isEnabled && !KillSwitchActive();
}



static BOOL IsLandscape(void)
{
    UIInterfaceOrientation orientation =
    [UIApplication sharedApplication].statusBarOrientation;

    return orientation == UIInterfaceOrientationLandscapeLeft ||
           orientation == UIInterfaceOrientationLandscapeRight;
}



static double SpacingMultiplier(BOOL vertical)
{
    double value;

    if(IsLandscape())
    {
        value = vertical ? vertSpacingLand : horizSpacingLand;
    }
    else
    {
        value = vertical ? vertSpacingPort : horizSpacingPort;
    }


    if(value <= 0)
        return 1.0;


    return value / 50.0;
}



static double ScaleValue(double native)
{
    if(!TweakActive())
        return native;


    return native * (cardScale / 0.30);
}



static double ReadSpacing(NSUserDefaults *prefs,
                          NSString *key,
                          double def)
{
    id obj = [prefs objectForKey:key];

    if(!obj)
        return def;


    return [obj doubleValue];
}



static void ReloadPrefs(void)
{
    NSUserDefaults *prefs =
    [[NSUserDefaults alloc]
     initWithSuiteName:domainString];


    isEnabled =
    [[prefs objectForKey:@"isEnabled"]
     ?: @(YES) boolValue];


    cardScale =
    [[prefs objectForKey:@"cardScale"]
     ?: @(0.38) doubleValue];


    cornerRadius =
    [[prefs objectForKey:@"cornerRadius"]
     ?: @(10) doubleValue];


    vertSpacingPort =
    ReadSpacing(prefs,
                @"vertSpacingPort",
                50);


    horizSpacingPort =
    ReadSpacing(prefs,
                @"horizSpacingPort",
                50);


    vertSpacingLand =
    ReadSpacing(prefs,
                @"vertSpacingLand",
                50);


    horizSpacingLand =
    ReadSpacing(prefs,
                @"horizSpacingLand",
                50);
}





#pragma mark - iPad Grid Switcher


%hook SBAppSwitcherSettings


// 永远启用 iPad 网格
- (long long)switcherStyle
{
    if(TweakActive())
    {
        return 2;
    }

    return %orig;
}



- (double)appExposeNonFloatingSingleRowScale
{
    return ScaleValue(%orig);
}



- (double)appExposeNonFloatingDoubleRowScale
{
    return ScaleValue(%orig);
}



- (double)appExposeFloatingDoubleRowScale
{
    return ScaleValue(%orig);
}




- (double)gridSwitcherHorizontalInterpageSpacingPortrait
{
    double value = %orig;

    if(TweakActive())
        value *= SpacingMultiplier(NO);

    return value;
}



- (double)gridSwitcherVerticalNaturalSpacingPortrait
{
    double value = %orig;

    if(TweakActive())
        value *= SpacingMultiplier(YES);

    return value;
}



- (double)gridSwitcherHorizontalInterpageSpacingLandscape
{
    double value = %orig;

    if(TweakActive())
        value *= SpacingMultiplier(NO);

    return value;
}



- (double)gridSwitcherVerticalNaturalSpacingLandscape
{
    double value = %orig;

    if(TweakActive())
        value *= SpacingMultiplier(YES);

    return value;
}



%end





#pragma mark - Corner


%hook SBMixedGridSwitcherModifier


- (double)_cardCornerRadiusInSwitcher
{
    if(TweakActive())
        return cornerRadius;


    return %orig;
}


%end





#pragma mark - 保留App自己的方向


%hook SBApplication


- (BOOL)supportsInterfaceOrientation:(long long)orientation
{
    return %orig;
}


%end





#pragma mark - 不伪装iPad


%hook SBFluidSwitcherViewController


- (BOOL)isDevicePad
{
    return %orig;
}


%end






%ctor
{

    if(KillSwitchActive())
        return;


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
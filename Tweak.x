#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSString *const domainString = @"com.schlub51.fipad";
NSString *const killSwitchPath = @"/var/mobile/fipad.disable";

static BOOL isEnabled;
static BOOL spoofPadIdiomDuringSwitcherLoad;
static double cardScale;          // 卡片缩放比例，直接存储最终缩放值（0.30~0.50）
static double cornerRadius;
static double vertSpacingPort;
static double horizSpacingPort;
static double vertSpacingLand;
static double horizSpacingLand;

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
	return native * (cardScale / 0.30); // 原生基准 0.30
}

static BOOL IsLandscape(void) {
	CGSize size = [UIScreen mainScreen].bounds.size;
	return size.width > size.height;
}

static double SpacingMultiplier(BOOL vertical) {
	double value = 0.0;
	if(IsLandscape()) {
		value = vertical ? vertSpacingLand : horizSpacingLand;
	}
	else {
		value = vertical ? vertSpacingPort : horizSpacingPort;
	}
	if(value <= 0.0) {
		return 1.0;
	}
	return value / 50.0;
}

// Ignore the legacy slider defaults so old saved values map to "no change".
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
#include "ipsRootListController.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <rootless.h>

NSString *const domainString = @"com.schlub51.fipad";

@implementation ipsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"fipad";
    [self setupCustomUI];
}

- (void)setupCustomUI {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scrollView];
    
    UIView *contentView = [[UIView alloc] init];
    [scrollView addSubview:contentView];
    
    CGFloat y = 20;
    CGFloat width = self.view.bounds.size.width;
    
    y = [self addSectionLabel:@"竖屏设置" atY:y toView:contentView width:width];
    y = [self addSliderWithStepper:@"卡片缩放" key:@"cardScale" min:0.20 max:0.50 step:0.01 atY:y toView:contentView width:width];
    y = [self addSliderWithStepper:@"垂直间距" key:@"vertSpacingPort" min:10 max:120 step:1 atY:y toView:contentView width:width];
    y = [self addSliderWithStepper:@"水平间距" key:@"horizSpacingPort" min:10 max:120 step:1 atY:y toView:contentView width:width];
    
    y += 10;
    y = [self addSectionLabel:@"横屏设置" atY:y toView:contentView width:width];
    y = [self addSliderWithStepper:@"卡片缩放" key:@"cardScaleLandscape" min:0.20 max:0.50 step:0.01 atY:y toView:contentView width:width];
    y = [self addSliderWithStepper:@"垂直间距" key:@"vertSpacingLand" min:10 max:120 step:1 atY:y toView:contentView width:width];
    y = [self addSliderWithStepper:@"水平间距" key:@"horizSpacingLand" min:10 max:120 step:1 atY:y toView:contentView width:width];
    
    y += 10;
    y = [self addSectionLabel:@"卡片圆角" atY:y toView:contentView width:width];
    y = [self addSliderWithStepper:@"圆角半径" key:@"cornerRadius" min:0 max:40 step:1 atY:y toView:contentView width:width];
    
    y += 30;
    UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    applyBtn.frame = CGRectMake(40, y, width - 80, 44);
    [applyBtn setTitle:@"应用更改" forState:UIControlStateNormal];
    applyBtn.backgroundColor = [UIColor systemBlueColor];
    applyBtn.layer.cornerRadius = 10;
    [applyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [applyBtn addTarget:self action:@selector(sbreload) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:applyBtn];
    y += 60;
    
    contentView.frame = CGRectMake(0, 0, width, y);
    scrollView.contentSize = contentView.frame.size;
}

- (CGFloat)addSectionLabel:(NSString *)text atY:(CGFloat)y toView:(UIView *)view width:(CGFloat)width {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, y, width - 40, 30)];
    label.text = text;
    label.font = [UIFont boldSystemFontOfSize:16];
    label.textColor = [UIColor systemGrayColor];
    [view addSubview:label];
    return y + 30;
}

- (CGFloat)addSliderWithStepper:(NSString *)labelText
                             key:(NSString *)key
                             min:(CGFloat)min
                             max:(CGFloat)max
                            step:(CGFloat)step
                             atY:(CGFloat)y
                          toView:(UIView *)view
                           width:(CGFloat)width {
    // 标签
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 80, 30)];
    label.text = labelText;
    label.font = [UIFont systemFontOfSize:14];
    [view addSubview:label];
    
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:domainString];
    CGFloat currentValue = [defaults floatForKey:key];
    if (currentValue == 0) currentValue = (min + max) / 2;
    
    // 滑块（宽度自适应）
    CGFloat sliderX = 100;
    CGFloat sliderWidth = width - sliderX - 80 - 20 - 10; // 留出步进器空间
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(sliderX, y, sliderWidth, 30)];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = currentValue;
    slider.accessibilityLabel = key;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [view addSubview:slider];
    
    // 数值显示
    CGFloat valueX = sliderX + sliderWidth + 10;
    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(valueX, y, 40, 30)];
    valueLabel.text = [NSString stringWithFormat:@"%.2f", currentValue];
    valueLabel.font = [UIFont systemFontOfSize:14];
    valueLabel.textAlignment = NSTextAlignmentCenter;
    valueLabel.accessibilityLabel = [key stringByAppendingString:@"_value"];
    [view addSubview:valueLabel];
    
    // 步进器
    CGFloat stepperX = valueX + 45;
    UIStepper *stepper = [[UIStepper alloc] initWithFrame:CGRectMake(stepperX, y, 80, 30)];
    stepper.minimumValue = min;
    stepper.maximumValue = max;
    stepper.stepValue = step;
    stepper.value = currentValue;
    stepper.accessibilityLabel = key;
    [stepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
    [view addSubview:stepper];
    
    // 存储关联对象以便更新数值标签
    objc_setAssociatedObject(slider, "valueLabel", valueLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(stepper, "valueLabel", valueLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    return y + 40;
}

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = sender.accessibilityLabel;
    UILabel *valueLabel = objc_getAssociatedObject(sender, "valueLabel");
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:domainString];
    [defaults setFloat:sender.value forKey:key];
    [defaults synchronize];
    valueLabel.text = [NSString stringWithFormat:@"%.2f", sender.value];
    [self postNotification];
}

- (void)stepperChanged:(UIStepper *)sender {
    NSString *key = sender.accessibilityLabel;
    UILabel *valueLabel = objc_getAssociatedObject(sender, "valueLabel");
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:domainString];
    [defaults setFloat:sender.value forKey:key];
    [defaults synchronize];
    valueLabel.text = [NSString stringWithFormat:@"%.2f", sender.value];
    [self postNotification];
}

- (void)postNotification {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.schlub51.fipad.changed"),
                                         NULL, NULL, YES);
}

-(void)sbreload {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"fipad"
                            message:@"设置已保存\n现在 Respring 吗？"
                            preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"否" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction* yes = [UIAlertAction actionWithTitle:@"是" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction * action) {
            system("sbreload");
        }];
    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
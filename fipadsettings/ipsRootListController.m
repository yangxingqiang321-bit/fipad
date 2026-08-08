#include "ipsRootListController.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <rootless.h>
#import "NSTask.h"

@implementation ipsRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

-(void)sbreload {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"fipad"
                            message:@"设置已保存\n现在 Respring 吗？"
                            preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"否" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction* yes = [UIAlertAction actionWithTitle:@"是" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction * action) {
            NSTask *t = [[NSTask alloc] init];
            [t setLaunchPath:ROOT_PATH_NS(@"/usr/bin/sbreload")];
            [t launch];
        }];
    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
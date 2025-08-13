//
// Copyright (c) 2017 Emarsys. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "EMSIAMCloseProtocol.h"

@class MEJSBridge;

typedef void (^MECompletionHandler)(void);

@interface MEIAMViewController : UIViewController
@property (nonatomic, weak) id<EMSIAMCloseProtocol> loadErrorDelegate;

- (instancetype)initWithJSBridge:(MEJSBridge *)bridge;

- (void)loadMessage:(NSString *)message
  completionHandler:(MECompletionHandler)completionHandler;

@end

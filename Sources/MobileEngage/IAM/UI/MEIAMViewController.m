//
// Copyright (c) 2017 Emarsys. All rights reserved.
//

#import "MEIAMViewController.h"
#import "MEJSBridge.h"

@interface EmarsysLogger : NSObject
+ (void)log:(NSString *) msg;
@end

@implementation EmarsysLogger

+ (void)log:(NSString *) msg {
    NSLog(msg);
    
    NSString * cachesPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    NSURL * url = [NSURL fileURLWithPath:cachesPath];
    NSString * filename = @"Emarsys_log";
    NSURL *fileURL = [[url URLByAppendingPathComponent:filename] URLByAppendingPathExtension:@"log"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:fileURL.path]) {
        [fm createFileAtPath:fileURL.path contents:[NSData new] attributes:nil];
    }
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:fileURL.path];
    [fileHandle seekToEndOfFile];
    
    NSData * shi = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    [fileHandle writeData:shi];
    
    NSDate * date = [[NSDate alloc] init];
    NSString * log = [NSString stringWithFormat:@"%@ %@", date, msg];
    
    NSData * data = [log dataUsingEncoding:NSUTF8StringEncoding];
    [fileHandle writeData:data];
}
@end

@interface MEIAMViewController () <WKNavigationDelegate>

@property(nonatomic, strong) MECompletionHandler completionHandler;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) MEJSBridge *bridge;

@end

@implementation MEIAMViewController

#pragma mark - ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self.view setBackgroundColor:UIColor.clearColor];
    __weak typeof(self) weakSelf = self;
    [self.bridge setJsResultBlock:^(NSDictionary<NSString *, NSObject *> *result) {
        [weakSelf respondToJS:result];
    }];
}

- (void)viewDidDisappear:(BOOL)animated {
    [self.webView stopLoading];
    [self.webView setNavigationDelegate:nil];
    [self.webView.scrollView setDelegate:nil];
    [self.webView.configuration.userContentController removeAllScriptMessageHandlers];
    [self.webView.configuration setUserContentController:[WKUserContentController new]];
    [self.webView removeFromSuperview];
    self.webView = nil;
    [super viewDidDisappear:animated];
}

#pragma mark - Public methods

- (instancetype)initWithJSBridge:(MEJSBridge *)bridge {
    self = [super init];
    if (self) {
        _bridge = bridge;
    }
    return self;
}

- (void)loadMessage:(NSString *)message
  completionHandler:(MECompletionHandler)completionHandler {
    _completionHandler = completionHandler;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!weakSelf.webView) {
            weakSelf.webView = [weakSelf createWebView];
            [weakSelf addFullscreenView:weakSelf.webView];
        }
        [weakSelf.webView loadHTMLString:message
                                 baseURL:nil];
    });
}

#pragma mark - WKNavigationDelegate

- (void)    webView:(WKWebView *)webView
didFinishNavigation:(null_unspecified WKNavigation *)navigation {
    if (self.completionHandler) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.completionHandler();
        });
    }
    NSString *jsCheckEmpty = @"(function() { var body = document.body; if (!body) return true; var temp = body.cloneNode(true); var removeTags = temp.querySelectorAll('script, style, noscript, iframe'); for (var i = 0; i < removeTags.length; i++) { removeTags[i].remove(); } var text = temp.innerText || temp.textContent || ''; return text.trim() === ''; })();";
    __weak MEIAMViewController * weakSelf = self;
    [webView evaluateJavaScript:jsCheckEmpty completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if (error) {
            [EmarsysLogger log:[NSString stringWithFormat:@"execute JavaScript error: %@", error.localizedDescription]];
            return;
        }
        
        if ([result isKindOfClass:[NSNumber class]]) {
            BOOL isEmpty = [result boolValue];
            if (isEmpty) {
                [EmarsysLogger log:@"⚠️ The web page is detected to be empty."];
                [weakSelf handleWebViewLoadError:nil];
            } else {
                [EmarsysLogger log:@"✅ The web page contains valid content."];
            }
        } else {
            [EmarsysLogger log:[NSString stringWithFormat:@"JavaScript exception in return value type: %@", result]];
        }
    }];
}

#pragma mark - Private methods

- (void)handleWebViewLoadError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.loadErrorDelegate respondsToSelector:@selector(closeInAppWithCompletionHandler:)]) {
            [self.loadErrorDelegate closeInAppWithCompletionHandler:nil];
        }
    });
}

- (WKWebView *)createWebView {
    __weak typeof(self) weakSelf = self;
    __weak typeof(self.bridge.userContentController) weakUserContentController = self.bridge.userContentController;
    
    WKProcessPool *processPool = [WKProcessPool new];
    WKWebViewConfiguration *webViewConfiguration = [WKWebViewConfiguration new];
    [webViewConfiguration setProcessPool:processPool];
    [webViewConfiguration setUserContentController:weakUserContentController];

    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero
                                            configuration:webViewConfiguration];
    [webView setNavigationDelegate:weakSelf];
    [webView setOpaque:NO];
    [webView setBackgroundColor:UIColor.clearColor];
    [webView.scrollView setBackgroundColor:UIColor.clearColor];
    [webView.scrollView setScrollEnabled:NO];
    [webView.scrollView setBounces:NO];
    [webView.scrollView setBouncesZoom:NO];
    [webView setInspectable:true];

    webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    return webView;
}

- (void)addFullscreenView:(UIView *)view {
    [self.view addSubview:view];
    [view setTranslatesAutoresizingMaskIntoConstraints:NO];

    NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:view
                                                           attribute:NSLayoutAttributeTop
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:self.view
                                                           attribute:NSLayoutAttributeTop
                                                          multiplier:1
                                                            constant:0];

    NSLayoutConstraint *left = [NSLayoutConstraint constraintWithItem:view
                                                            attribute:NSLayoutAttributeLeft
                                                            relatedBy:NSLayoutRelationEqual
                                                               toItem:self.view
                                                            attribute:NSLayoutAttributeLeft
                                                           multiplier:1
                                                             constant:0];


    NSLayoutConstraint *widthConstraint = [NSLayoutConstraint constraintWithItem:view
                                                                       attribute:NSLayoutAttributeWidth
                                                                       relatedBy:NSLayoutRelationEqual
                                                                          toItem:self.view
                                                                       attribute:NSLayoutAttributeWidth
                                                                      multiplier:1
                                                                        constant:0];
    NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:view
                                                                        attribute:NSLayoutAttributeHeight
                                                                        relatedBy:NSLayoutRelationEqual
                                                                           toItem:self.view
                                                                        attribute:NSLayoutAttributeHeight
                                                                       multiplier:1
                                                                         constant:0];
    [self.view addConstraints:@[top, left, widthConstraint, heightConstraint]];
    [self.view layoutIfNeeded];
}

- (void)respondToJS:(NSDictionary<NSString *, NSObject *> *)result {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                       options:0
                                                         error:&error];
    NSString *js = [NSString stringWithFormat:@"MEIAM.handleResponse(%@);",
                                              [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.webView evaluateJavaScript:js
                       completionHandler:nil];
    });
}

@end

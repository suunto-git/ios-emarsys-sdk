//
// Copyright (c) 2017 Emarsys. All rights reserved.
//

#import "MEIAMViewController.h"
#import "MEJSBridge.h"

@interface EmarsysLogger : NSObject
+ (void)log:(NSString *)msg;
+ (void)saveFile:(NSString *)msg;
@end

@implementation EmarsysLogger

#pragma mark - Helper Methods

+ (NSURL *)emarsysLogDirectoryURL {
    static NSURL *logDirURL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *cachesPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSURL *cachesURL = [NSURL fileURLWithPath:cachesPath];
        logDirURL = [cachesURL URLByAppendingPathComponent:@"emarsys_log" isDirectory:YES];
        
        // Ensure the directory exists
        NSError *error;
        if (![[NSFileManager defaultManager] fileExistsAtPath:logDirURL.path]) {
            [[NSFileManager defaultManager] createDirectoryAtURL:logDirURL
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];
            if (error) {
                NSLog(@"[EmarsysLogger] Failed to create log directory: %@", error.localizedDescription);
            }
        }
    });
    return logDirURL;
}

+ (NSString *)ISO8601StringFromDate:(NSDate *)date {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"; // Safe for filenames
    });
    return [formatter stringFromDate:date];
}

#pragma mark - Public API

+ (void)log:(NSString *)msg {
    if (!msg) return;
    
    // Console log
    NSLog(@"EmarsysSDK: %@", msg);
    
    // Prepare log file URL
    NSURL *logDir = [self emarsysLogDirectoryURL];
    NSURL *logFileURL = [logDir URLByAppendingPathComponent:@"Emarsys_log.log"];
    
    // Format log entry
    NSDate *now = [NSDate date];
    NSString *timestampedLog = [NSString stringWithFormat:@"%@ %@", [self ISO8601StringFromDate:now], msg];
    NSData *data = [[timestampedLog stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    
    // Write safely (thread-safe via @synchronized or serial queue; here using simple file lock via NSFileCoordinator optional)
    @synchronized(self) {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingToURL:logFileURL error:nil];
        if (!fileHandle) {
            // File doesn't exist; create it
            [[NSFileManager defaultManager] createFileAtPath:logFileURL.path contents:nil attributes:nil];
            fileHandle = [NSFileHandle fileHandleForWritingToURL:logFileURL error:nil];
        }
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:data];
            [fileHandle closeFile]; // Important!
        } else {
            NSLog(@"[EmarsysLogger] Failed to open log file for writing: %@", logFileURL.path);
        }
    }
}

+ (void)saveFile:(NSString *)msg {
    if (!msg) return;
    
    NSURL *logDir = [self emarsysLogDirectoryURL];
    NSDate *now = [NSDate date];
    NSString *filename = [NSString stringWithFormat:@"Emarsys.%@", [self ISO8601StringFromDate:now]];
    NSURL *logFileURL = [[logDir URLByAppendingPathComponent:filename] URLByAppendingPathExtension:@"log"];
    
    NSData *data = [msg dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    
    // Simply write the entire message as a new file
    NSError *error;
    if (![[NSFileManager defaultManager] createFileAtPath:logFileURL.path contents:data attributes:nil]) {
        NSLog(@"[EmarsysLogger] Failed to save log file: %@, error: %@", logFileURL.path, error.localizedDescription);
    }
}

@end

@interface MEIAMViewController () <WKNavigationDelegate>

@property(nonatomic, strong) MECompletionHandler completionHandler;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) MEJSBridge *bridge;

@end

@implementation MEIAMViewController

#pragma mark - ViewController

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear: animated];
    [EmarsysLogger log:@"viewDidAppear"];
    
    if (!self.webView.isLoading) {
        [self checkWebpageContent];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self.view setBackgroundColor:UIColor.clearColor];
    __weak typeof(self) weakSelf = self;
    [self.bridge setJsResultBlock:^(NSDictionary<NSString *, NSObject *> *result) {
        [weakSelf respondToJS:result];
    }];
    
    [EmarsysLogger log:@"viewDidLoad"];
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
    
    [EmarsysLogger log:@"viewDidDisappear"];
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
        [EmarsysLogger log:@"loadMessage"];
        [EmarsysLogger saveFile: message];
    });
}

- (void)dealloc
{
    [EmarsysLogger log:@"dealloc"];
}

#pragma mark - WKNavigationDelegate

- (void)    webView:(WKWebView *)webView
didFinishNavigation:(null_unspecified WKNavigation *)navigation {
    if (self.completionHandler) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.completionHandler();
            weakSelf.completionHandler = nil;
        });
    }
    [EmarsysLogger log:@"didFinishNavigation"];
}

#pragma mark - Private methods

- (void)checkWebpageContent {
    NSString *jsCheckEmpty = @"(function() { var body = document.body; if (!body) return true; var temp = body.cloneNode(true); var removeTags = temp.querySelectorAll('script, style, noscript, iframe'); for (var i = 0; i < removeTags.length; i++) { removeTags[i].remove(); } var text = temp.innerText || temp.textContent || ''; return text.trim() === ''; })();";
    __weak MEIAMViewController * weakSelf = self;
    [self.webView evaluateJavaScript:jsCheckEmpty completionHandler:^(id _Nullable result, NSError * _Nullable error) {
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

- (void)handleWebViewLoadError:(NSError *)error {
    __weak MEIAMViewController * weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([weakSelf.loadErrorDelegate respondsToSelector:@selector(closeInAppWithCompletionHandler:)]) {
            [weakSelf.loadErrorDelegate closeInAppWithCompletionHandler:nil];
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

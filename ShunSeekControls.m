#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <math.h>

// ShunTV 1.0 - transport controls extension for TQM-TV 2.0.
// Experimental: runtime injection into an app without its source code.
// No private iOS APIs. Does not bypass DRM or stream restrictions.

static const void *kShunControlKey = &kShunControlKey;

@interface ShunSeekPanel : UIView
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, weak) AVPlayer *player;
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *totalLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIButton *backTen;
@property (nonatomic, strong) UIButton *forwardTen;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL scrubbing;
@property (nonatomic) BOOL queryingWeb;
@property (nonatomic) double webDuration;
@property (nonatomic) double webCurrentTime;
- (instancetype)initWithHost:(UIViewController *)host;
- (void)activate;
- (void)deactivate;
- (void)refreshPlacement;
@end

static NSString *ShunClock(double seconds) {
    if (!isfinite(seconds) || seconds < 0) return @"--:--";
    NSInteger sec = (NSInteger)floor(seconds);
    NSInteger hrs = sec / 3600;
    if (hrs > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hrs, (long)((sec/60)%60), (long)(sec%60)];
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(sec/60), (long)(sec%60)];
}
static UIButton *ShunButton(NSString *title) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    button.backgroundColor = [UIColor colorWithWhite:1 alpha:.15];
    button.layer.cornerRadius = 14;
    button.accessibilityLabel = title;
    return button;
}
static UILabel *ShunLabel(void) {
    UILabel *label = [UILabel new];
    label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = .7;
    return label;
}

@implementation ShunSeekPanel
- (instancetype)initWithHost:(UIViewController *)host {
    self = [super initWithFrame:CGRectMake(0, 0, 300, 95)];
    if (!self) return nil;
    _host = host;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:.76];
    self.layer.cornerRadius = 15;
    self.clipsToBounds = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    _elapsedLabel = ShunLabel(); _totalLabel = ShunLabel();
    _elapsedLabel.text = @"--:--"; _totalLabel.text = @"--:--";
    _totalLabel.textAlignment = NSTextAlignmentRight;
    _slider = [UISlider new];
    _slider.minimumValue = 0; _slider.maximumValue = 1;
    _slider.minimumTrackTintColor = [UIColor systemOrangeColor];
    _slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:.45];
    [_slider addTarget:self action:@selector(beginSeeking:) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(finishSeeking:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    _backTen = ShunButton(@"↶ 10s");
    _forwardTen = ShunButton(@"10s ↷");
    [_backTen addTarget:self action:@selector(backward:) forControlEvents:UIControlEventTouchUpInside];
    [_forwardTen addTarget:self action:@selector(forward:) forControlEvents:UIControlEventTouchUpInside];
    _statusLabel = ShunLabel();
    _statusLabel.text = @"Đang tải..."; _statusLabel.textAlignment = NSTextAlignmentCenter;
    for (UIView *v in @[_elapsedLabel,_totalLabel,_slider,_backTen,_forwardTen,_statusLabel]) [self addSubview:v];
    [self setControlsEnabled:NO];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    self.elapsedLabel.frame = CGRectMake(14, 8, 68, 20);
    self.totalLabel.frame = CGRectMake(w-82, 8, 68, 20);
    self.slider.frame = CGRectMake(86, 8, MAX(30,w-172), 20);
    self.backTen.frame = CGRectMake(14, 37, 88, 42);
    self.forwardTen.frame = CGRectMake(w-102, 37, 88, 42);
    self.statusLabel.frame = CGRectMake(107, 43, MAX(20,w-214), 28);
}
- (void)refreshPlacement {
    UIView *parent = self.host.view;
    if (!parent) return;
    CGFloat inset = parent.safeAreaInsets.bottom;
    CGFloat width = MIN(MAX(280, parent.bounds.size.width - 32), 620);
    CGFloat x = (parent.bounds.size.width-width)*.5;
    CGFloat y = MAX(12, parent.bounds.size.height - inset - 105);
    self.frame = CGRectMake(x,y,width,94);
    if (self.superview != parent) [parent addSubview:self];
    [parent bringSubviewToFront:self];
}
- (void)activate {
    [self refreshPlacement];
    [self.timer invalidate];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:.65 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshState];
    }];
    [self refreshState];
}
- (void)deactivate {
    [self.timer invalidate]; self.timer=nil;
    [self removeFromSuperview];
}
- (void)setControlsEnabled:(BOOL)enabled {
    self.slider.enabled = enabled;
    self.backTen.enabled = enabled;
    self.forwardTen.enabled = enabled;
    self.backTen.alpha = enabled ? 1.0 : .4;
    self.forwardTen.alpha = enabled ? 1.0 : .4;
    self.slider.alpha = enabled ? 1.0 : .4;
}
- (void)displayPosition:(double)current duration:(double)duration {
    BOOL canSeek = isfinite(duration) && duration > .5;
    self.statusLabel.text = canSeek ? @"TUA VIDEO" : @"TRỰC TIẾP";
    [self setControlsEnabled:canSeek];
    self.elapsedLabel.text = ShunClock(current);
    self.totalLabel.text = canSeek ? ShunClock(duration) : @"LIVE";
    if (!self.scrubbing) self.slider.value = canSeek ? (float)fmin(1, fmax(0,current/duration)) : 0;
}
- (void)refreshState {
    UIViewController *controller = self.host;
    if (!controller || !controller.isViewLoaded || !controller.view.window) return;
    if (self.player) {
        AVPlayer *p = self.player;
        AVPlayerItem *item = p.currentItem;
        double current = CMTimeGetSeconds(p.currentTime);
        double duration = item ? CMTimeGetSeconds(item.duration) : NAN;
        // Live / DVR windows are not assumed seekable just because video is playing.
        [self displayPosition:current duration:duration];
    } else if (self.webView && !self.queryingWeb) {
        self.queryingWeb = YES;
        __weak typeof(self) weakSelf = self;
        NSString *script = @"(function(){var v=document.querySelector('video');if(!v)return null;v.controls=true;return {t:v.currentTime,d:v.duration};})()";
        [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error){
            ShunSeekPanel *panel=weakSelf;
            if (!panel) return;
            panel.queryingWeb=NO;
            if ([result isKindOfClass:[NSDictionary class]]) {
                id t=result[@"t"],d=result[@"d"];
                panel.webCurrentTime=[t respondsToSelector:@selector(doubleValue)] ? [t doubleValue] : 0;
                panel.webDuration=[d respondsToSelector:@selector(doubleValue)] ? [d doubleValue] : NAN;
                [panel displayPosition:panel.webCurrentTime duration:panel.webDuration];
            } else {
                panel.statusLabel.text = @"ĐANG TÌM VIDEO";
                [panel setControlsEnabled:NO];
            }
        }];
    }
}
- (void)beginSeeking:(UISlider *)sender { self.scrubbing=YES; }
- (void)finishSeeking:(UISlider *)sender {
    self.scrubbing=NO;
    if (self.player) {
        double duration=CMTimeGetSeconds(self.player.currentItem.duration);
        if (isfinite(duration) && duration>.5) {
            double target=(double)sender.value*duration;
            [self.player seekToTime:CMTimeMakeWithSeconds(target, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        }
    } else if (self.webView && isfinite(self.webDuration) && self.webDuration>.5) {
        [self setWebTime:(double)sender.value*self.webDuration];
    }
}
- (void)setWebTime:(double)target {
    NSString *script=[NSString stringWithFormat:@"(function(){var v=document.querySelector('video');if(v&&isFinite(v.duration)){v.currentTime=Math.max(0,Math.min(v.duration,%.3f));v.controls=true;}})()",target];
    [self.webView evaluateJavaScript:script completionHandler:nil];
}
- (void)step:(double)seconds {
    if (self.player) {
        double total=CMTimeGetSeconds(self.player.currentItem.duration);
        double current=CMTimeGetSeconds(self.player.currentTime);
        if (isfinite(total) && total>.5 && isfinite(current)) {
            double target=fmin(total,fmax(0,current+seconds));
            [self.player seekToTime:CMTimeMakeWithSeconds(target,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        }
    } else if (self.webView && isfinite(self.webDuration) && self.webDuration>.5) {
        [self setWebTime:fmin(self.webDuration,fmax(0,self.webCurrentTime+seconds))];
    }
}
- (void)backward:(id)sender { [self step:-10]; }
- (void)forward:(id)sender { [self step:10]; }
@end

static void ShunAttachPanel(UIViewController *controller) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ShunAttachPanel(controller);}); return; }
    ShunSeekPanel *panel = objc_getAssociatedObject(controller,kShunControlKey);
    if (!panel) {
        panel = [[ShunSeekPanel alloc] initWithHost:controller];
        objc_setAssociatedObject(controller,kShunControlKey,panel,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *type=NSStringFromClass([controller class]);
    if ([type isEqualToString:@"PlayerViewController"]) {
        id value=nil;
        @try { value=[controller valueForKey:@"moviePlayer"]; } @catch (NSException *e) { value=nil; }
        panel.player=[value isKindOfClass:[AVPlayer class]] ? value : nil;
        panel.webView=nil;
    } else if ([type isEqualToString:@"MoviePlayerViewController"]) {
        Ivar ivar=class_getInstanceVariable([controller class],"_webView");
        id value=ivar ? object_getIvar(controller,ivar) : nil;
        panel.webView=[value isKindOfClass:[WKWebView class]] ? value : nil;
        panel.player=nil;
    }
    [panel activate];
}

static void ShunPatchController(NSString *name) {
    Class cls=NSClassFromString(name);
    if (!cls) { NSLog(@"ShunSeek: missing controller %@",name); return; }
    SEL appear=@selector(viewDidAppear:);
    Method m=class_getInstanceMethod(cls,appear);
    if (m) {
        IMP orig=method_getImplementation(m);
        IMP newImp=imp_implementationWithBlock(^(UIViewController *obj,BOOL animated){
            ((void(*)(id,SEL,BOOL))orig)(obj,appear,animated);
            ShunAttachPanel(obj);
        });
        class_replaceMethod(cls,appear,newImp,method_getTypeEncoding(m));
    }
    SEL disappear=@selector(viewWillDisappear:);
    m=class_getInstanceMethod(cls,disappear);
    if (m) {
        IMP orig=method_getImplementation(m);
        IMP newImp=imp_implementationWithBlock(^(UIViewController *obj,BOOL animated){
            ShunSeekPanel *panel=objc_getAssociatedObject(obj,kShunControlKey);
            [panel deactivate];
            ((void(*)(id,SEL,BOOL))orig)(obj,disappear,animated);
        });
        class_replaceMethod(cls,disappear,newImp,method_getTypeEncoding(m));
    }
    SEL layout=@selector(viewDidLayoutSubviews);
    m=class_getInstanceMethod(cls,layout);
    if (m) {
        IMP orig=method_getImplementation(m);
        IMP newImp=imp_implementationWithBlock(^(UIViewController *obj){
            ((void(*)(id,SEL))orig)(obj,layout);
            ShunSeekPanel *panel=objc_getAssociatedObject(obj,kShunControlKey);
            [panel refreshPlacement];
        });
        class_replaceMethod(cls,layout,newImp,method_getTypeEncoding(m));
    }
    NSLog(@"ShunSeek: installed controls for %@",name);
}

__attribute__((constructor)) static void ShunSeekStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        ShunPatchController(@"PlayerViewController");
        ShunPatchController(@"MoviePlayerViewController");
    });
}

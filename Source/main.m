#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <IOKit/hid/IOHIDManager.h>
#include <stdatomic.h>
#include <math.h>

static _Atomic(double) targetHz = 440, level = 0.18;
static atomic_bool gate = false;
static double phase = 0, envelope = 0, smoothHz = 440;

static float sample(double rate) {
    double frequency = atomic_load_explicit(&targetHz, memory_order_relaxed);
    smoothHz += (frequency - smoothHz) * (1 - exp(-1 / (rate * .012)));
    double amplitude = atomic_load_explicit(&gate, memory_order_relaxed) ? atomic_load_explicit(&level, memory_order_relaxed) : 0;
    envelope += (amplitude - envelope) * (1 - exp(-1 / (rate * .004)));
    if (envelope < 1e-8) envelope = 0;
    phase += smoothHz / rate;
    phase -= floor(phase);
    // A soft, nasal voice with bounded harmonics and no discontinuous waveform.
    return envelope * (sin(2*M_PI*phase) + .32*sin(4*M_PI*phase) + .18*sin(6*M_PI*phase)) / 1.5;
}

static double frequencyFor(double angle, double low, double high, BOOL reverse, BOOL snap) {
    double t = fmax(0, fmin(1, (angle-low)/fmax(5, high-low)));
    if (reverse) t = 1-t;
    double midi = 48 + t*24; // C3–C5, equal musical spacing across the hinge range.
    if (snap) midi = round(midi);
    return 440 * pow(2, (midi-69)/12);
}

@interface Sensor : NSObject
@property IOHIDManagerRef manager;
@property IOHIDDeviceRef device;
- (double)read;
@end
@implementation Sensor
- (instancetype)init {
    if ((self = [super init])) {
        _manager = IOHIDManagerCreate(kCFAllocatorDefault, 0);
        NSDictionary *match = @{@"VendorID":@0x05ac, @"DeviceUsagePage":@0x20, @"DeviceUsage":@0x8a};
        IOHIDManagerSetDeviceMatching(_manager, (__bridge CFDictionaryRef)match);
        if (IOHIDManagerOpen(_manager, 0) == kIOReturnSuccess) {
            NSSet *devices = CFBridgingRelease(IOHIDManagerCopyDevices(_manager));
            for (id candidate in devices) {
                IOHIDDeviceRef dev = (__bridge IOHIDDeviceRef)candidate;
                if (IOHIDDeviceOpen(dev, 0) != kIOReturnSuccess) continue;
                uint8_t report[8] = {0}; CFIndex count = sizeof(report);
                if (IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 1, report, &count) == kIOReturnSuccess && count >= 3) {
                    _device = (IOHIDDeviceRef)CFRetain(dev); break;
                }
                IOHIDDeviceClose(dev, 0);
            }
        }
    }
    return self;
}
- (double)read {
    if (!_device) return NAN;
    uint8_t report[8] = {0}; CFIndex count = sizeof(report);
    IOReturn status = IOHIDDeviceGetReport(_device, kIOHIDReportTypeFeature, 1, report, &count);
    if (status != kIOReturnSuccess || count < 3) return NAN;
    double angle = report[1] | (report[2] << 8);
    return angle >= 0 && angle <= 180 ? angle : NAN;
}
- (void)dealloc {
    if (_device) { IOHIDDeviceClose(_device, 0); CFRelease(_device); }
    if (_manager) { IOHIDManagerClose(_manager, 0); CFRelease(_manager); }
}
@end

@interface InstrumentView : NSView
@property double angle, frequency, minimum, maximum;
@property BOOL playing, sensorOK, settingsVisible;
@property double mouthOpen;
@property(copy) NSString *audioError;
@end
static NSColor *ink(void) { return [NSColor colorWithCalibratedWhite:.075 alpha:1]; }
static void label(NSString *text, NSRect rect, CGFloat size, NSColor *color, NSFontWeight weight) {
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight], NSForegroundColorAttributeName:color}];
}
static void centered(NSString *text, NSRect rect, CGFloat size, NSColor *color) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new]; style.alignment = NSTextAlignmentCenter;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:NSFontWeightMedium],NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:style}];
}
@implementation InstrumentView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithCalibratedRed:.98 green:.975 blue:.955 alpha:1] setFill]; NSRectFill(self.bounds);
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat faceHeight = h - (self.settingsVisible ? 246 : 60);
    label(@"LIDTONE", NSMakeRect(28,23,180,25), 13, ink(), NSFontWeightBold);
    NSArray<NSString *> *noteNames = @[@"도", @"도♯", @"레", @"레♯", @"미", @"파", @"파♯", @"솔", @"솔♯", @"라", @"라♯", @"시"];
    NSInteger midiNote = (NSInteger)lround(69 + 12 * log2(fmax(1, self.frequency) / 440));
    NSString *noteName = noteNames[(midiNote % 12 + 12) % 12];
    NSString *status = self.audioError ?: (self.sensorOK ? [NSString stringWithFormat:@"%.0f°  /  %@",self.angle,noteName] : @"센서 연결 대기 중");
    centered(status,NSMakeRect(w/2-220,25,440,25),12,NSColor.secondaryLabelColor);

    // The display itself becomes the face: two round eyes and a wide slit mouth.
    CGFloat unit = fmin(w/1000,faceHeight/600);
    CGFloat eyeSize = 56*unit, eyeY = faceHeight*.34;
    [ink() setFill];
    for (int side=-1;side<=1;side+=2) {
        CGFloat x = w/2+side*165*unit;
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x-eyeSize/2,eyeY-eyeSize/2,eyeSize,eyeSize)] fill];
    }
    CGFloat left = w/2-350*unit, right = w/2+350*unit;
    CGFloat y = faceHeight*.65;
    CGFloat opening = self.mouthOpen;
    NSBezierPath *mouth = [NSBezierPath bezierPath];
    [mouth moveToPoint:NSMakePoint(left,y)];
    [mouth curveToPoint:NSMakePoint(right,y) controlPoint1:NSMakePoint(w/2-190*unit,y+6*unit-opening*45*unit) controlPoint2:NSMakePoint(w/2+190*unit,y+6*unit-opening*45*unit)];
    [mouth curveToPoint:NSMakePoint(left,y) controlPoint1:NSMakePoint(w/2+230*unit,y+12*unit+opening*210*unit) controlPoint2:NSMakePoint(w/2-230*unit,y+12*unit+opening*210*unit)];
    [mouth closePath]; [mouth fill];
    mouth.lineWidth = 7*unit; mouth.lineJoinStyle = NSLineJoinStyleRound; [ink() setStroke]; [mouth stroke];

    if (self.settingsVisible) {
        [[NSColor colorWithCalibratedWhite:.91 alpha:1] setFill]; NSRectFill(NSMakeRect(0,h-246,w,1));
        CGFloat x = (w-640)/2, top = h-238;
        label(@"음량",NSMakeRect(x+40,top+10,70,24),14,ink(),NSFontWeightMedium);
        label(@"연주 범위",NSMakeRect(x+40,top+99,120,24),14,ink(),NSFontWeightMedium);
        label([NSString stringWithFormat:@"%.0f°–%.0f°",self.minimum,self.maximum],NSMakeRect(x+470,top+99,130,24),14,ink(),NSFontWeightMedium);
    }
    centered(self.playing ? @"노래하는 중" : @"SPACE를 누르면 노래해요", NSMakeRect(w/2-220,h-37,440,23),13,NSColor.secondaryLabelColor);
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property NSWindow *window;
@property InstrumentView *view;
@property Sensor *sensor;
@property AVAudioEngine *engine;
@property AVAudioSourceNode *source;
@property NSTimer *timer;
@property id keyMonitor;
@property NSButton *snap, *reverse, *settingsButton, *fullscreenButton;
@property NSView *settingsPanel;
@property BOOL held;
@property NSInteger ticks;
@end
@implementation AppDelegate
- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action]; b.frame = frame; [self.settingsPanel addSubview:b]; return b;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSMenu *menu = [NSMenu new]; NSMenuItem *root = [NSMenuItem new]; [menu addItem:root];
    NSMenu *sub = [NSMenu new]; [sub addItemWithTitle:@"LidTone 종료" action:@selector(terminate:) keyEquivalent:@"q"]; root.submenu = sub; NSApp.mainMenu = menu;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,680) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"LidTone · 덮개로 연주하기"; self.window.delegate = self;
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    self.view = [[InstrumentView alloc] initWithFrame:NSMakeRect(0,0,1000,680)];
    self.view.minimum = 45; self.view.maximum = 125; self.view.frequency = 440;
    self.window.contentView = self.view;
    self.window.minSize = NSMakeSize(680,540);
    self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    self.settingsPanel = [[NSView alloc] initWithFrame:NSMakeRect(180,442,640,184)];
    self.settingsPanel.hidden = YES; [self.view addSubview:self.settingsPanel];
    self.settingsButton = [NSButton buttonWithTitle:@"설정" target:self action:@selector(toggleSettings:)];
    self.settingsButton.frame = NSMakeRect(912,17,64,30); [self.view addSubview:self.settingsButton];
    self.fullscreenButton = [NSButton buttonWithTitle:@"전체 화면" target:self action:@selector(toggleFullscreen:)];
    self.fullscreenButton.frame = NSMakeRect(24,630,94,30); [self.view addSubview:self.fullscreenButton];
    NSSlider *volume = [NSSlider sliderWithValue:.18 minValue:0 maxValue:.5 target:self action:@selector(volumeChanged:)];
    volume.frame = NSMakeRect(102,150,495,28); volume.accessibilityLabel = @"음량"; [self.settingsPanel addSubview:volume];
    self.snap = [NSButton checkboxWithTitle:@"반음 단위로 맞추기" target:self action:@selector(settingsChanged:)]; self.snap.frame = NSMakeRect(40,107,250,26); [self.settingsPanel addSubview:self.snap];
    self.reverse = [NSButton checkboxWithTitle:@"닫을수록 높은 음" target:self action:@selector(settingsChanged:)]; self.reverse.frame = NSMakeRect(330,107,250,26); [self.settingsPanel addSubview:self.reverse];
    [self button:@"현재 각도를 최솟값으로" frame:NSMakeRect(38,17,219,32) action:@selector(setMinimum:)];
    [self button:@"현재 각도를 최댓값으로" frame:NSMakeRect(266,17,219,32) action:@selector(setMaximum:)];
    [self button:@"초기화" frame:NSMakeRect(494,17,110,32) action:@selector(resetRange:)];
    self.sensor = [Sensor new];
    [self startAudio];
    __weak AppDelegate *weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown|NSEventMaskKeyUp handler:^NSEvent *(NSEvent *event) {
        AppDelegate *s = weakSelf;
        if (event.keyCode != 49 || !s.window.isKeyWindow) return event;
        if (event.type == NSEventTypeKeyUp) [s silence];
        else if (!event.isARepeat && !(event.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagControl|NSEventModifierFlagOption))) {
            s.held = YES; [s updateGate];
        }
        return nil;
    }];
    self.timer = [NSTimer timerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *t) { [weakSelf tick]; }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioChanged:) name:AVAudioEngineConfigurationChangeNotification object:self.engine];
    [self tick]; [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)toggleSettings:(id)sender {
    self.view.settingsVisible = !self.view.settingsVisible;
    self.settingsPanel.hidden = !self.view.settingsVisible;
    self.settingsButton.title = self.view.settingsVisible ? @"닫기" : @"설정";
    [self.window makeFirstResponder:self.view]; self.view.needsDisplay = YES;
}
- (void)toggleFullscreen:(id)sender { [self.window toggleFullScreen:nil]; }
- (void)windowDidResize:(NSNotification *)n {
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    self.settingsPanel.frame = NSMakeRect((w-640)/2,h-238,640,184);
    self.settingsButton.frame = NSMakeRect(w-88,17,64,30);
    self.fullscreenButton.frame = NSMakeRect(24,h-44,94,30);
    self.view.needsDisplay = YES;
}
- (void)startAudio {
    self.engine = [AVAudioEngine new];
    AVAudioFormat *output = [self.engine.outputNode inputFormatForBus:0];
    double rate = output.sampleRate;
    if (rate <= 0) { self.view.audioError = @"오디오 출력 장치를 찾을 수 없습니다"; return; }
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:1];
    self.source = [[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *silent, const AudioTimeStamp *time, AVAudioFrameCount frames, AudioBufferList *buffers) {
        for (UInt32 i=0;i<frames;i++) {
            float value = sample(rate);
            for (UInt32 b=0;b<buffers->mNumberBuffers;b++) ((float *)buffers->mBuffers[b].mData)[i] = value;
        }
        *silent = envelope == 0; return noErr;
    }];
    [self.engine attachNode:self.source]; [self.engine connect:self.source to:self.engine.mainMixerNode format:format];
    NSError *error = nil;
    if (![self.engine startAndReturnError:&error]) self.view.audioError = [@"오디오 오류: " stringByAppendingString:error.localizedDescription];
}
- (void)audioChanged:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self silence];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioEngineConfigurationChangeNotification object:self.engine];
        [self.engine stop]; self.view.audioError = nil; [self startAudio];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioChanged:) name:AVAudioEngineConfigurationChangeNotification object:self.engine];
    });
}
- (void)tick {
    double angle = [self.sensor read]; self.view.sensorOK = isfinite(angle);
    if (self.view.sensorOK) {
        self.view.angle = angle;
        self.view.frequency = frequencyFor(angle,self.view.minimum,self.view.maximum,self.reverse.state == NSControlStateValueOn,self.snap.state == NSControlStateValueOn);
        atomic_store(&targetHz,self.view.frequency);
    } else {
        [self silence];
        if (++self.ticks % 120 == 0) self.sensor = [Sensor new];
    }
    [self updateGate];
    self.view.mouthOpen += ((self.view.playing ? 1.0 : 0.0)-self.view.mouthOpen)*.4;
    self.view.needsDisplay = YES;
}
- (void)updateGate {
    BOOL play = self.held && self.view.sensorOK && self.window.isKeyWindow && NSApp.isActive && self.engine.isRunning && !self.view.audioError;
    atomic_store(&gate,play); self.view.playing = play; self.view.needsDisplay = YES;
}
- (void)silence { self.held = NO; atomic_store(&gate,false); self.view.playing = NO; self.view.needsDisplay = YES; }
- (void)volumeChanged:(NSSlider *)sender { atomic_store(&level,sender.doubleValue); }
- (void)settingsChanged:(id)sender { [self tick]; }
- (void)setMinimum:(id)sender { if (self.view.sensorOK && self.view.angle <= self.view.maximum-5) self.view.minimum = self.view.angle; else NSBeep(); [self tick]; }
- (void)setMaximum:(id)sender { if (self.view.sensorOK && self.view.angle >= self.view.minimum+5) self.view.maximum = self.view.angle; else NSBeep(); [self tick]; }
- (void)resetRange:(id)sender { self.view.minimum = 45; self.view.maximum = 125; [self tick]; }
- (void)windowDidResignKey:(NSNotification *)n { [self silence]; }
- (void)applicationDidResignActive:(NSNotification *)n { [self silence]; }
- (void)willSleep:(NSNotification *)n { [self silence]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
- (void)applicationWillTerminate:(NSNotification *)n {
    [self silence]; [self.timer invalidate]; [self.engine stop];
    if (self.keyMonitor) [NSEvent removeMonitor:self.keyMonitor];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1],"--diagnose") == 0) {
            Sensor *sensor = [Sensor new]; double angle = [sensor read];
            printf("Lid sensor: %s; angle: %.1f degrees\n",isfinite(angle)?"connected":"unavailable",angle);
            return isfinite(angle) ? 0 : 1;
        }
        if (argc > 1 && strcmp(argv[1],"--self-test") == 0) {
            assert(fabs(frequencyFor(45,45,125,NO,NO)-130.81278265)<.001);
            assert(fabs(frequencyFor(125,45,125,NO,NO)-523.25113060)<.001);
            assert(frequencyFor(0,45,125,NO,NO)==frequencyFor(45,45,125,NO,NO));
            assert(frequencyFor(45,45,125,YES,NO)==frequencyFor(125,45,125,NO,NO));
            for (int i=0;i<1000;i++) assert(sample(48000)==0);
            atomic_store(&gate,true); double energy=0; int crossings=0; float previous=0;
            for (int i=0;i<48000;i++) { float v=sample(48000); assert(isfinite(v)&&fabs(v)<.51); energy+=v*v; if(i>24000&&previous<=0&&v>0)crossings++; previous=v; }
            assert(energy>1 && abs(crossings-220)<=1);
            atomic_store(&gate,false); for(int i=0;i<4800;i++)sample(48000);
            assert(sample(48000)==0);
            puts("PASS: angle mapping, range clamping, direction, silent idle, 440 Hz synthesis, bounded output, release silence."); return 0;
        }
        NSApplication *app = [NSApplication sharedApplication]; [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [AppDelegate new]; app.delegate = delegate; [app run];
    }
    return 0;
}

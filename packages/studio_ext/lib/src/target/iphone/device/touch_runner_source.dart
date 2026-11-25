// studio: 048 — source of the xcross touch runner, Studio's own touch helper
// for the live iPhone screen. `xcross screen touch-setup` compiles it on the
// user's PC (clang + ld64.lld + the installed iOS SDK) into an XCTest bundle and
// puts it into the runner app in place of WebDriverAgent's test bundle.
//
// Kept as Objective-C text here (not a prebuilt binary), so the engine ships no
// Apple SDK content: the build links against the SDK the user installed.

/// File name the source is written to before compiling.
const touchRunnerSourceName = 'XcrossTouch.m';

/// The runner's protocol version (`xcrossTouch` in `GET /status`).
const touchRunnerVersion = 1;

const touchRunnerSource = r'''
// xcross touch runner (spec 048): a small XCTest bundle that turns HTTP requests into touches.
//
// Runs inside an XCTest runner app (started with `pymobiledevice3 developer dvt xcuitest`) and
// listens on port 8100 (like WebDriverAgent, so the engine's forward and the Wi-Fi route stay the
// same). Unlike WebDriverAgent it does not look up the app in front before each touch: it hands
// the touch straight to XCTest's event synthesizer, in screen points, portrait.
//
//   GET  /status          {"value":{"ready":true,"xcrossTouch":1,"ios":{"ip":..},"screen":{..}}}
//   POST /touch/tap       {"x":pt,"y":pt,"hold":seconds}
//   POST /touch/swipe     {"x1":pt,"y1":pt,"x2":pt,"y2":pt,"seconds":s,"hold":s}  (hold: rest before lifting)
//   POST /touch/home
//
// Private XCTest classes are looked up at run time (NSClassFromString), so the bundle links only
// against XCTest's public symbols and loads on iOS 15 to 27.

#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

static const int kPort = 8100;
static const int kVersion = 1;

// Selectors of XCTest's private event classes (the same ones WebDriverAgent uses).
@protocol XTPointerEventPath
- (id)initForTouchAtPoint:(CGPoint)point offset:(double)offset;
- (void)moveToPoint:(CGPoint)point atOffset:(double)offset;
- (void)liftUpAtOffset:(double)offset;
@end

@protocol XTSynthesizedEventRecord
- (id)initWithName:(NSString *)name interfaceOrientation:(long long)orientation;
- (void)addPointerEventPath:(id)path;
@end

@protocol XTEventSynthesizer
- (void)synthesizeEvent:(id)record completion:(void (^)(BOOL result, NSError *error))completion;
@end

@protocol XTDaemonSession
+ (id)sharedSession;
- (void)synthesizeEvent:(id)record completion:(void (^)(NSError *error))completion;
@end

@protocol XTDevice
+ (id)sharedDevice;
- (id)eventSynthesizer;
- (void)pressButton:(long long)button;
@end

#pragma mark - Touches

/// Runs [block] on the main queue (where XCTest expects event calls) and waits for [done].
static NSString *XTOnMain(void (^block)(void (^done)(NSString *error))) {
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  __block NSString *failure = nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    block(^(NSString *error) {
      failure = error;
      dispatch_semaphore_signal(sem);
    });
  });
  if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC)) != 0) {
    return @"the touch did not finish in time";
  }
  return failure;
}

static NSString *XTSynthesize(id record) {
  return XTOnMain(^(void (^done)(NSString *)) {
    Class device = NSClassFromString(@"XCUIDevice");
    id shared = [(id<XTDevice>)device sharedDevice];
    if ([shared respondsToSelector:@selector(eventSynthesizer)]) {
      id synthesizer = [(id<XTDevice>)shared eventSynthesizer];
      if ([synthesizer respondsToSelector:@selector(synthesizeEvent:completion:)]) {
        [(id<XTEventSynthesizer>)synthesizer synthesizeEvent:record
                                                  completion:^(BOOL result, NSError *error) {
          done(error ? error.localizedDescription : (result ? nil : @"the touch was refused"));
        }];
        return;
      }
    }
    Class sessionClass = NSClassFromString(@"XCTRunnerDaemonSession");
    id session = [(id<XTDaemonSession>)sessionClass sharedSession];
    if ([session respondsToSelector:@selector(synthesizeEvent:completion:)]) {
      [(id<XTDaemonSession>)session synthesizeEvent:record
                                         completion:^(NSError *error) {
        done(error ? error.localizedDescription : nil);
      }];
      return;
    }
    done(@"this iOS has no event synthesizer XCTest can reach");
  });
}

static id XTRecord(NSString *name, id path) {
  Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
  if (recordClass == nil || path == nil) return nil;
  id record = [(id<XTSynthesizedEventRecord>)[recordClass alloc]
      initWithName:name interfaceOrientation:UIInterfaceOrientationPortrait];
  [(id<XTSynthesizedEventRecord>)record addPointerEventPath:path];
  return record;
}

static id XTPath(CGPoint start) {
  Class pathClass = NSClassFromString(@"XCPointerEventPath");
  if (pathClass == nil) return nil;
  return [(id<XTPointerEventPath>)[pathClass alloc] initForTouchAtPoint:start offset:0];
}

static NSString *XTTap(CGPoint p, double hold) {
  id path = XTPath(p);
  [(id<XTPointerEventPath>)path liftUpAtOffset:MAX(hold, 0.02)];
  id record = XTRecord(@"xcross tap", path);
  return record ? XTSynthesize(record) : @"XCTest event classes not found";
}

static NSString *XTSwipe(CGPoint a, CGPoint b, double seconds, double hold) {
  double d = MIN(MAX(seconds, 0.05), 1.5);
  id path = XTPath(a);
  [(id<XTPointerEventPath>)path moveToPoint:b atOffset:d];
  // The finger rests at the end for `hold` seconds: the app switcher needs it.
  [(id<XTPointerEventPath>)path liftUpAtOffset:d + MIN(MAX(hold, 0.0), 2.0)];
  id record = XTRecord(@"xcross swipe", path);
  return record ? XTSynthesize(record) : @"XCTest event classes not found";
}

static NSString *XTHome(void) {
  return XTOnMain(^(void (^done)(NSString *)) {
    id shared = [(id<XTDevice>)NSClassFromString(@"XCUIDevice") sharedDevice];
    [(id<XTDevice>)shared pressButton:1];  // XCUIDeviceButtonHome
    done(nil);
  });
}

#pragma mark - Status

static NSString *XTWiFiAddress(void) {
  struct ifaddrs *list = NULL;
  NSString *found = nil;
  if (getifaddrs(&list) != 0) return nil;
  for (struct ifaddrs *i = list; i != NULL; i = i->ifa_next) {
    if (i->ifa_addr == NULL || i->ifa_addr->sa_family != AF_INET) continue;
    if (strcmp(i->ifa_name, "en0") != 0) continue;
    char buf[INET_ADDRSTRLEN];
    struct sockaddr_in *sin = (struct sockaddr_in *)i->ifa_addr;
    if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof buf)) found = @(buf);
  }
  freeifaddrs(list);
  return found;
}

static CGSize gScreen;

@protocol XTApplication
- (id)initWithBundleIdentifier:(NSString *)bundleId;
- (CGRect)frame;
@end

/// The screen in points, portrait. The runner app has no launch screen, so UIKit runs it in the
/// old 320x480 compatibility size and UIScreen (even nativeBounds) reports that; the home
/// screen's frame is the real size (375x812 on an iPhone X). Asked once, at start.
static CGSize XTRealScreen(void) {
  CGSize size = CGSizeMake(0, 0);  // (CGSizeZero would need CoreGraphics linked)
  Class appClass = NSClassFromString(@"XCUIApplication");
  if (appClass != nil) {
    @try {
      id springboard = [(id<XTApplication>)[appClass alloc] initWithBundleIdentifier:@"com.apple.springboard"];
      size = [(id<XTApplication>)springboard frame].size;
    } @catch (NSException *e) {
      NSLog(@"xcross touch: no home screen size (%@)", e.reason);
    }
  }
  if (size.width < 1 || size.height < 1) {
    UIScreen *screen = UIScreen.mainScreen;
    CGFloat scale = screen.nativeScale > 0 ? screen.nativeScale : 1;
    size = CGSizeMake(screen.nativeBounds.size.width / scale, screen.nativeBounds.size.height / scale);
  }
  CGSize portrait = CGSizeMake(MIN(size.width, size.height), MAX(size.width, size.height));
  NSLog(@"xcross touch: screen %.0fx%.0f points", portrait.width, portrait.height);
  return portrait;
}

static NSDictionary *XTStatus(void) {
  NSString *ip = XTWiFiAddress();
  return @{
    @"value" : @{
      @"ready" : @YES,
      @"xcrossTouch" : @(kVersion),
      @"ios" : ip ? @{@"ip" : ip} : @{},
      @"os" : @{@"version" : UIDevice.currentDevice.systemVersion ?: @""},
      @"screen" : @{@"width" : @(gScreen.width), @"height" : @(gScreen.height)},
    }
  };
}

#pragma mark - HTTP

static void XTSend(int fd, int code, NSDictionary *body) {
  NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] ?: [NSData data];
  NSString *head = [NSString stringWithFormat:
      @"HTTP/1.1 %d %@\r\nContent-Type: application/json\r\nContent-Length: %lu\r\n\r\n",
      code, code == 200 ? @"OK" : (code == 404 ? @"Not Found" : @"Error"), (unsigned long)json.length];
  NSMutableData *out = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
  [out appendData:json];
  const uint8_t *p = out.bytes;
  size_t left = out.length;
  while (left > 0) {
    ssize_t n = write(fd, p, left);
    if (n <= 0) return;
    p += n;
    left -= (size_t)n;
  }
}

static double XTNum(NSDictionary *d, NSString *key, double fallback) {
  id v = d[key];
  return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : fallback;
}

static void XTRoute(int fd, NSString *method, NSString *path, NSData *body) {
  NSDictionary *args = body.length
      ? ([NSJSONSerialization JSONObjectWithData:body options:0 error:nil] ?: @{})
      : @{};
  if (![args isKindOfClass:NSDictionary.class]) args = @{};
  NSString *error = nil;
  if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/status"]) {
    XTSend(fd, 200, XTStatus());
    return;
  } else if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/touch/tap"]) {
    error = XTTap(CGPointMake(XTNum(args, @"x", 0), XTNum(args, @"y", 0)), XTNum(args, @"hold", 0.03));
  } else if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/touch/swipe"]) {
    error = XTSwipe(CGPointMake(XTNum(args, @"x1", 0), XTNum(args, @"y1", 0)),
                    CGPointMake(XTNum(args, @"x2", 0), XTNum(args, @"y2", 0)),
                    XTNum(args, @"seconds", 0.2),
                    XTNum(args, @"hold", 0.0));
  } else if ([method isEqualToString:@"POST"] && [path isEqualToString:@"/touch/home"]) {
    error = XTHome();
  } else {
    XTSend(fd, 404, @{@"value" : @{@"error" : @"unknown command"}});
    return;
  }
  if (error) {
    XTSend(fd, 500, @{@"value" : @{@"error" : error}});
  } else {
    XTSend(fd, 200, @{@"value" : [NSNull null]});
  }
}

/// One connection: requests one after another (kept open), until the other side closes.
static void XTConnection(int fd) {
  NSMutableData *buf = [NSMutableData data];
  uint8_t chunk[4096];
  for (;;) {
    @autoreleasepool {
      NSRange end = [buf rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
                             options:0
                               range:NSMakeRange(0, buf.length)];
      if (end.location == NSNotFound) {
        ssize_t n = read(fd, chunk, sizeof chunk);
        if (n <= 0 || buf.length > 65536) break;
        [buf appendBytes:chunk length:(NSUInteger)n];
        continue;
      }
      NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, end.location)]
                                             encoding:NSUTF8StringEncoding] ?: @"";
      NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
      NSArray<NSString *> *first = [lines.firstObject componentsSeparatedByString:@" "];
      NSUInteger length = 0;
      for (NSString *line in lines) {
        if ([line.lowercaseString hasPrefix:@"content-length:"]) {
          length = (NSUInteger)[[line substringFromIndex:15] integerValue];
        }
      }
      NSUInteger bodyStart = end.location + end.length;
      while (buf.length < bodyStart + length) {
        ssize_t n = read(fd, chunk, sizeof chunk);
        if (n <= 0) goto closed;
        [buf appendBytes:chunk length:(NSUInteger)n];
      }
      NSData *body = [buf subdataWithRange:NSMakeRange(bodyStart, length)];
      [buf replaceBytesInRange:NSMakeRange(0, bodyStart + length) withBytes:NULL length:0];
      if (first.count >= 2) {
        NSString *path = [first[1] componentsSeparatedByString:@"?"].firstObject;
        XTRoute(fd, first[0], path, body);
      }
    }
  }
closed:
  close(fd);
}

static void XTServe(void) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof addr);
  addr.sin_len = sizeof addr;
  addr.sin_family = AF_INET;
  addr.sin_port = htons(kPort);
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(fd, 16) != 0) {
    NSLog(@"xcross touch: cannot listen on %d (%s)", kPort, strerror(errno));
    return;
  }
  NSLog(@"xcross touch: listening on %d", kPort);
  for (;;) {
    int c = accept(fd, NULL, NULL);
    if (c < 0) continue;
    setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
      XTConnection(c);
    });
  }
}

#pragma mark - The test that keeps running

@interface XcrossTouchRunner : XCTestCase
@end

@implementation XcrossTouchRunner

- (void)testRunner {
  self.continueAfterFailure = YES;
  gScreen = XTRealScreen();
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
    XTServe();
  });
  // Keep the main run loop turning: XCTest delivers event completions here.
  for (;;) {
    @autoreleasepool {
      [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    }
  }
}

@end
''';

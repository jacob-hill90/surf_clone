
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include "../core/hud.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iterator>

#include "../core/physics.h"

// ======================================
// SHARED ENGINE STATE
// ======================================

namespace {

Renderer renderer(480, 270);
Scene scene;
Player player;
Camera camera;

bool held[256]{};
bool mouseCaptured = false;

using Clock = std::chrono::steady_clock;
Clock::time_point lastTick = Clock::now();

float accumulator = 0.0f;

constexpr float FIXED_DT = 1.0f / 60.0f;

// ======================================
// MOUSE CONTROL
// ======================================

void releaseMouse() {
    if (!mouseCaptured)
        return;

    mouseCaptured = false;

    CGAssociateMouseAndMouseCursorPosition(true);
    [NSCursor unhide];
}

// ======================================
// GAME UPDATE
// ======================================

void updateGame(float dt) {

    // Arrow key camera rotation
    const float look = 1.5f * dt;

    if (held[123]) camera.yaw -= look;
    if (held[124]) camera.yaw += look;
    if (held[126]) camera.pitch += look;
    if (held[125]) camera.pitch -= look;

    camera.pitch = std::clamp(
        camera.pitch,
        -1.45f,
        1.45f
    );

    // Translate macOS keyboard input
    // into our shared physics input.
    MoveInput input;

    input.forward =
        float(held[13]) - float(held[1]); // W / S

    input.right =
        float(held[2]) - float(held[0]);  // D / A

    input.jump = held[49];                 // Space

    // Fixed 60 Hz physics updates
    accumulator += dt;

    int steps = 0;

    while (accumulator >= FIXED_DT && steps < 8) {
        updatePhysics(
            player,
            scene,
            input,
            camera.yaw,
            FIXED_DT
        );

        accumulator -= FIXED_DT;
        ++steps;
    }

    // Prevent unlimited catch-up
    // after a long frame.
    if (steps == 8)
        accumulator = 0.0f;

    // Camera follows player
    camera.position = player.position;
    camera.position.y += 1.65f;
}

} // namespace

// ======================================
// COCOA VIEW
// ======================================

@interface SurfView : NSView
@end

@implementation SurfView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

// ======================================
// KEYBOARD INPUT
// ======================================

- (void)keyDown:(NSEvent *)event {

    unsigned short code = event.keyCode;

    // Escape: release mouse
    if (code == 53) {
        releaseMouse();
        return;
    }

    // R: respawn
    if (code == 15 && !event.isARepeat) {
        respawn(player);
        player.jumpWasDown = false;
        return;
    }

    if (code < 256)
        held[code] = true;
}

- (void)keyUp:(NSEvent *)event {

    unsigned short code = event.keyCode;

    if (code < 256)
        held[code] = false;
}

// ======================================
// MOUSE INPUT
// ======================================

- (void)mouseDown:(NSEvent *)event {

    (void)event;

    if (!mouseCaptured) {
        mouseCaptured = true;

        [NSCursor hide];

        CGAssociateMouseAndMouseCursorPosition(false);
    }
}

- (void)mouseMoved:(NSEvent *)event {

    if (!mouseCaptured)
        return;

    camera.yaw +=
        float(event.deltaX) * 0.0025f;

    camera.pitch = std::clamp(
        camera.pitch -
            float(event.deltaY) * 0.0025f,
        -1.45f,
        1.45f
    );
}

- (void)mouseDragged:(NSEvent *)event {
    [self mouseMoved:event];
}

// ======================================
// SOFTWARE FRAMEBUFFER DISPLAY
// ======================================

- (void)drawRect:(NSRect)dirtyRect {

    (void)dirtyRect;

    // Clear color and depth buffers.
    renderer.clear(0xFF202938);

    // Render our shared 3D scene.
    for (const Triangle& triangle : scene.triangles) {
        renderer.drawWorldTriangle(
            triangle,
            camera
        );
    }

        SurfHUD::draw(
        renderer.framebuffer,
        player,
        mouseCaptured
    );

    const int width =
        renderer.framebuffer.width;

    const int height =
        renderer.framebuffer.height;

    // Create a Core Graphics bitmap
    // backed by our own C++ pixel memory.
    CGColorSpaceRef colorSpace =
        CGColorSpaceCreateDeviceRGB();

    CGContextRef bitmap =
        CGBitmapContextCreate(
            renderer.framebuffer.pixels.data(),
            width,
            height,
            8,
            width * 4,
            colorSpace,
            kCGBitmapByteOrder32Little |
                kCGImageAlphaNoneSkipFirst
        );

    CGColorSpaceRelease(colorSpace);

    if (!bitmap)
        return;

    CGImageRef image =
        CGBitmapContextCreateImage(bitmap);

    CGContextRelease(bitmap);

    if (!image)
        return;

    // Present framebuffer in the window.
    CGContextRef context =
        [[NSGraphicsContext currentContext] CGContext];

    CGContextSaveGState(context);

    // Preserve crisp software-rendered pixels.
    CGContextSetInterpolationQuality(
        context,
        kCGInterpolationNone
    );

    CGContextDrawImage(
        context,
        CGRectMake(
            0,
            0,
            self.bounds.size.width,
            self.bounds.size.height
        ),
        image
    );

    CGContextRestoreGState(context);

    CGImageRelease(image);
}

@end

// ======================================
// APPLICATION DELEGATE
// ======================================

@interface SurfAppDelegate :
    NSObject <NSApplicationDelegate, NSWindowDelegate>

@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) SurfView *view;
@property(nonatomic, strong) NSTimer *timer;

- (void)tick:(NSTimer *)timer;

@end

@implementation SurfAppDelegate

- (void)applicationDidFinishLaunching:
    (NSNotification *)notification {

    (void)notification;

    // Create a 960x540 native macOS window.
    NSRect rect =
        NSMakeRect(100, 100, 960, 540);

    self.window =
        [[NSWindow alloc]
            initWithContentRect:rect
            styleMask:(
                NSWindowStyleMaskTitled |
                NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable |
                NSWindowStyleMaskResizable
            )
            backing:NSBackingStoreBuffered
            defer:NO
        ];

    [self.window setTitle:@"SurfEngine - macOS"];

    self.window.delegate = self;

    // Attach our custom software-rendering view.
    self.view =
        [[SurfView alloc]
            initWithFrame:NSMakeRect(
                0, 0, 960, 540
            )
        ];

    [self.window setContentView:self.view];

    [self.window makeKeyAndOrderFront:nil];

    [self.window makeFirstResponder:self.view];

    [self.window setAcceptsMouseMovedEvents:YES];

    [NSApp activateIgnoringOtherApps:YES];

    // Initialize player and camera.
    respawn(player);
    player.jumpWasDown = false;

    camera.yaw = 0.0f;
    camera.pitch = -0.15f;

    camera.position = player.position;
    camera.position.y += 1.65f;

    lastTick = Clock::now();

    // Approximate 60 FPS update timer.
    self.timer =
        [NSTimer
            scheduledTimerWithTimeInterval:
                1.0 / 60.0
            target:self
            selector:@selector(tick:)
            userInfo:nil
            repeats:YES
        ];
}

// ======================================
// TIMER / GAME LOOP
// ======================================

- (void)tick:(NSTimer *)timer {

    (void)timer;

    auto now = Clock::now();

    float dt =
        std::chrono::duration<float>(
            now - lastTick
        ).count();

    lastTick = now;

    updateGame(
        std::clamp(dt, 0.0f, 0.05f)
    );

    // Ask Cocoa to redraw the framebuffer.
    [self.view setNeedsDisplay:YES];
}

// ======================================
// WINDOW EVENTS
// ======================================

- (void)windowDidResignKey:
    (NSNotification *)notification {

    (void)notification;

    std::fill(
        std::begin(held),
        std::end(held),
        false
    );

    releaseMouse();
}

- (void)windowWillClose:
    (NSNotification *)notification {

    (void)notification;

    releaseMouse();

    [self.timer invalidate];

    [NSApp terminate:nil];
}

- (void)applicationWillTerminate:
    (NSNotification *)notification {

    (void)notification;
    releaseMouse();
}

@end

// ======================================
// MACOS ENTRY POINT
// ======================================

int main(int argc, const char *argv[]) {

    (void)argc;
    (void)argv;

    @autoreleasepool {

        NSApplication *app =
            [NSApplication sharedApplication];

        [app setActivationPolicy:
            NSApplicationActivationPolicyRegular];

        SurfAppDelegate *delegate =
            [[SurfAppDelegate alloc] init];

        app.delegate = delegate;

        [app run];
    }

    return 0;
}

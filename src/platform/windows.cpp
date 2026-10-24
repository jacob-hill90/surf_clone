#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <chrono>
#include <algorithm>
#include <cmath>
#include <iterator>
#include "../core/scene.h"
#include "../core/physics.h"

Renderer renderer(640,360);
Scene scene;
Camera camera{
    {-2.5f, 9.65f, -17.5f}, // Position
    0.0f,                   // Yaw
    -0.15f                  // Pitch
};

Player player;

constexpr float FIXED_DT = 1.0f / 60.0f;
float physicsAccumulator = 0.0f;

bool held[256]{};
bool captured=false;
POINT previousMouse{};
using Clock=std::chrono::steady_clock;
auto lastTime=Clock::now();
constexpr UINT_PTR TIMER_ID=1;

void captureMouse(HWND window) {
    if(captured)return;
    captured=true;
    GetCursorPos(&previousMouse);
    RECT r;GetClientRect(window,&r);
    POINT a{r.left,r.top},b{r.right,r.bottom};ClientToScreen(window,&a);ClientToScreen(window,&b);
    RECT bounds{a.x,a.y,b.x,b.y};ClipCursor(&bounds);
    ShowCursor(FALSE);
    SetCapture(window);
}
void releaseMouse(){
    if(!captured)return;
    captured=false;ClipCursor(nullptr);ShowCursor(TRUE);ReleaseCapture();
}

void updateGame(float dt) {
    // -----------------------------------
    // Camera rotation from arrow keys
    // -----------------------------------

    float lookSpeed = 1.5f * dt;

    if (held[VK_LEFT])
        camera.yaw -= lookSpeed;

    if (held[VK_RIGHT])
        camera.yaw += lookSpeed;

    if (held[VK_UP])
        camera.pitch += lookSpeed;

    if (held[VK_DOWN])
        camera.pitch -= lookSpeed;

    camera.pitch = std::clamp(
        camera.pitch,
        -1.45f,
        1.45f
    );

    // -----------------------------------
    // Build player input
    // -----------------------------------

    MoveInput input;

    input.forward =
        float(held['W']) - float(held['S']);

    input.right =
        float(held['D']) - float(held['A']);

    input.jump = held[VK_SPACE];

    // -----------------------------------
    // Run fixed-timestep physics
    // -----------------------------------

    physicsAccumulator += dt;

    while (physicsAccumulator >= FIXED_DT) {
        updatePhysics(
            player,
            scene,
            input,
            camera.yaw,
            FIXED_DT
        );

        physicsAccumulator -= FIXED_DT;
    }

    // -----------------------------------
    // Camera follows player's eyes
    // -----------------------------------

    camera.position = player.position;
    camera.position.y += 1.65f;
}

LRESULT CALLBACK WindowProc(HWND window,UINT msg,WPARAM wParam,LPARAM lParam){
    switch(msg){
    case WM_LBUTTONDOWN: captureMouse(window);return 0;
    case WM_MOUSEMOVE:
        if(captured){
            POINT now;GetCursorPos(&now);
            int dx=now.x-previousMouse.x,dy=now.y-previousMouse.y;
            if(dx!=0 || dy!=0) {
                camera.yaw+=dx*0.0025f;
                camera.pitch=std::clamp(camera.pitch-dy*0.0025f,-1.45f,1.45f);
                SetCursorPos(previousMouse.x,previousMouse.y);
            }
        }
        return 0;
    case WM_KEYDOWN:
        if(wParam==VK_ESCAPE){releaseMouse();return 0;}
        if(wParam<256)held[wParam]=true;return 0;
    case WM_KEYUP:
        if(wParam<256)held[wParam]=false;return 0;
    case WM_KILLFOCUS:
        std::fill(std::begin(held),std::end(held),false);releaseMouse();return 0;
    case WM_TIMER:
        if(wParam==TIMER_ID){
            auto now=Clock::now();float dt=std::chrono::duration<float>(now-lastTime).count();lastTime=now;
            updateGame(std::min(dt, 0.05f));
            InvalidateRect(window,nullptr,FALSE);
        }
        return 0;
    case WM_PAINT:{
        PAINTSTRUCT ps;HDC dc=BeginPaint(window,&ps);
        renderer.clear(0xFF202938);
        for (const Triangle& triangle : scene.triangles) {
                renderer.drawWorldTriangle(triangle, camera);
        }
        BITMAPINFO bmi{};bmi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth=renderer.framebuffer.width;
        bmi.bmiHeader.biHeight=-renderer.framebuffer.height;
        bmi.bmiHeader.biPlanes=1;bmi.bmiHeader.biBitCount=32;bmi.bmiHeader.biCompression=BI_RGB;
        RECT rc;GetClientRect(window,&rc);
        SetStretchBltMode(dc,COLORONCOLOR);
        StretchDIBits(dc,0,0,rc.right,rc.bottom,0,0,renderer.framebuffer.width,renderer.framebuffer.height,
            renderer.framebuffer.pixels.data(),&bmi,DIB_RGB_COLORS,SRCCOPY);
        EndPaint(window,&ps);return 0;
    }
    case WM_DESTROY:releaseMouse();KillTimer(window,TIMER_ID);PostQuitMessage(0);return 0;
    }
    return DefWindowProcW(window,msg,wParam,lParam);
}
int WINAPI WinMain(HINSTANCE instance,HINSTANCE,LPSTR,int show){
    WNDCLASSW wc{};wc.lpfnWndProc=WindowProc;wc.hInstance=instance;
    wc.lpszClassName=L"SurfEngineCamera";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);
    if(!RegisterClassW(&wc))return 1;
    HWND w=CreateWindowExW(0,wc.lpszClassName,L"SurfEngine - First Person Camera",WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,CW_USEDEFAULT,1280,720,nullptr,nullptr,instance,nullptr);
    if(!w)return 2;
    respawn(player);
    player.jumpWasDown = false;

    camera.position = player.position;
    camera.position.y += 1.65f;

    camera.yaw = 0.0f;
    camera.pitch = -0.15f;
    ShowWindow(w,show);UpdateWindow(w);
    SetTimer(w,TIMER_ID,16,nullptr);lastTime=Clock::now();
    MSG msg{};while(GetMessageW(&msg,nullptr,0,0)>0){TranslateMessage(&msg);DispatchMessageW(&msg);}
    return (int)msg.wParam;
}

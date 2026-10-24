# SurfEngine

A small cross-platform 3D surf game built from scratch in C++17. It uses a custom CPU software renderer and shared scene/physics code, with native Win32/GDI on Windows and Cocoa/Core Graphics on macOS. No third-party game or graphics engine required.

## Requirements

- **Both:** Git and CMake 3.20+
- **macOS:** Xcode Command Line Tools (`xcode-select --install`)
- **Windows:** Visual Studio with **Desktop development with C++** (MSVC), and a Developer PowerShell / Developer Command Prompt

## Build and run — macOS

From the repository root:

```bash
cmake -S . -B build-mac -DCMAKE_BUILD_TYPE=Release
cmake --build build-mac --parallel
open build-mac/SurfEngine.app
```

After making code changes, usually just rebuild and reopen:

```bash
cmake --build build-mac --parallel
open build-mac/SurfEngine.app
```

Close the existing game before reopening it to avoid running an older instance.

**Clean build:**

```bash
cmake -E rm -rf build-mac
cmake -S . -B build-mac -DCMAKE_BUILD_TYPE=Release
cmake --build build-mac --parallel
```

If you've added the optional `Makefile` discussed during development, you can instead use `make`, `make run`, and `make clean` on macOS.

## Build and run — Windows

Open **Developer PowerShell for Visual Studio** in the repository root:

```powershell
cmake -S . -B build
cmake --build build --config Release --parallel
.\build\Release\SurfEngine.exe
```

If your build directory was already configured for a different generator, use a fresh directory such as `build-win` and adjust the paths accordingly. For a Visual Studio generator, you can optionally use `-A x64` on the configure command.

**Clean build:**

```powershell
cmake -E rm -rf build
cmake -S . -B build
cmake --build build --config Release --parallel
```

If you've added the optional `build.ps1` discussed during development, you can use ` .\build.ps1 run ` or ` .\build.ps1 clean ` from Developer PowerShell.

## Controls

| Input | Action |
| --- | --- |
| W / A / S / D | Move and steer |
| Mouse (after clicking window) | Look around |
| Space | Jump |
| R | Respawn / restart run |
| Escape | Release mouse |
| Arrow keys | Look around |

## Project layout

```text
src/
  core/
    framebuffer.h     Pixel buffer
    renderer.h        CPU 3D renderer
    scene.h/.cpp      Surf course geometry
    physics.h/.cpp    Player movement and collisions
    hud.h             On-screen speed, timer, and status
  platform/
    macos.mm          Cocoa window, input, display
    windows.cpp       Win32 window, input, display
CMakeLists.txt        Platform-specific build configuration
```

## Notes

- Build on each operating system; do **not** commit `build/` or `build-mac/` directories.
- The shared physics and renderer live in `src/core/`. Keep OS-specific window and input handling in `src/platform/`.
- If a build fails, start with the **first compiler or linker error**, not later cascading errors.
- Release builds are recommended for performance because rendering happens on the CPU.

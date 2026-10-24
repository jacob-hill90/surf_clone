
cmake_minimum_required(VERSION 3.20)

project(SurfEngine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Shared engine source files.
set(ENGINE_SOURCES
    src/core/scene.cpp
    src/core/physics.cpp
)

if(WIN32)

    # Native Windows executable.
    add_executable(SurfEngine WIN32
        src/platform/windows.cpp
        ${ENGINE_SOURCES}
    )

    target_compile_definitions(SurfEngine PRIVATE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )

    target_link_libraries(SurfEngine PRIVATE
        user32
        gdi32
    )

elseif(APPLE)
    enable_language(OBJCXX)

    add_executable(SurfEngine MACOSX_BUNDLE
        src/platform/macos.mm
        src/core/scene.cpp
        src/core/physics.cpp
    )

    target_compile_options(SurfEngine PRIVATE
        -fobjc-arc
    )

    target_link_libraries(SurfEngine PRIVATE
        "-framework Cocoa"
        "-framework CoreGraphics"
    )
endif()

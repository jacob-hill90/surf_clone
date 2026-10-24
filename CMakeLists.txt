cmake_minimum_required(VERSION 3.20)
project(SurfEngine LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(WIN32)
    add_executable(SurfEngine WIN32
        src/platform/windows.cpp
        src/core/scene.cpp
        src/core/physics.cpp
    )

    target_compile_definitions(SurfEngine PRIVATE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )

    target_link_libraries(SurfEngine PRIVATE
        user32
        gdi32
    )
endif()
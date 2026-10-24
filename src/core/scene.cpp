
#include "scene.h"

#include <cstdint>

// Coordinate system:
// X = left/right
// Y = up/down
// Z = forward/backward

using Color = uint32_t;

// =====================================
// BASIC TRIANGLE HELPERS
// =====================================

static void addQuad(
    std::vector<Triangle>& mesh,
    Vec3 a, Vec3 b, Vec3 c, Vec3 d,
    Color color
) {
    mesh.push_back({a, b, c, color});
    mesh.push_back({a, c, d, color});
}

// Create a solid box using 12 triangles.
static void addBox(
    std::vector<Triangle>& mesh,
    float x0, float x1,
    float y0, float y1,
    float z0, float z1,
    Color topColor,
    Color sideColor
) {
    // Top
    addQuad(mesh,
        {x0,y1,z0}, {x1,y1,z0},
        {x1,y1,z1}, {x0,y1,z1},
        topColor);

    // Bottom
    addQuad(mesh,
        {x0,y0,z1}, {x1,y0,z1},
        {x1,y0,z0}, {x0,y0,z0},
        sideColor);

    // Left and right
    addQuad(mesh,
        {x0,y0,z0}, {x0,y0,z1},
        {x0,y1,z1}, {x0,y1,z0},
        sideColor);

    addQuad(mesh,
        {x1,y0,z1}, {x1,y0,z0},
        {x1,y1,z0}, {x1,y1,z1},
        sideColor);

    // Front and back
    addQuad(mesh,
        {x0,y0,z0}, {x1,y0,z0},
        {x1,y1,z0}, {x0,y1,z0},
        sideColor);

    addQuad(mesh,
        {x1,y0,z1}, {x0,y0,z1},
        {x0,y1,z1}, {x1,y1,z1},
        sideColor);
}

// =====================================
// SOLID SURF RAMPS
// =====================================

static void addRamp(
    std::vector<Triangle>& mesh,
    const SurfRamp& ramp,
    Color topColor,
    Color sideColor
) {
    // Convert a ramp point into our
    // Windows renderer's coordinate system.
    auto point = [&](float x, float z) -> Vec3 {
        return {x, ramp.height(x, z), z};
    };

    // Sloped top surface
    addQuad(mesh,
        point(ramp.x0, ramp.y0),
        point(ramp.x1, ramp.y0),
        point(ramp.x1, ramp.y1),
        point(ramp.x0, ramp.y1),
        topColor);

    // Left side
    addQuad(mesh,
        {ramp.x0,0,ramp.y0},
        {ramp.x0,0,ramp.y1},
        point(ramp.x0,ramp.y1),
        point(ramp.x0,ramp.y0),
        sideColor);

    // Right side
    addQuad(mesh,
        {ramp.x1,0,ramp.y1},
        {ramp.x1,0,ramp.y0},
        point(ramp.x1,ramp.y0),
        point(ramp.x1,ramp.y1),
        sideColor);

    // Front face
    addQuad(mesh,
        {ramp.x0,0,ramp.y0},
        {ramp.x1,0,ramp.y0},
        point(ramp.x1,ramp.y0),
        point(ramp.x0,ramp.y0),
        sideColor);

    // Back face
    addQuad(mesh,
        {ramp.x1,0,ramp.y1},
        {ramp.x0,0,ramp.y1},
        point(ramp.x0,ramp.y1),
        point(ramp.x1,ramp.y1),
        sideColor);
}

// =====================================
// COURSE GEOMETRY
// =====================================

Scene::Scene() {

    // Checkerboard floor
    for (int x = -12; x < 12; x += 2) {
        for (int z = -22; z < 38; z += 2) {
            bool dark = ((x + z) / 2) % 2 != 0;

            Color color = dark
                ? 0xFF303C4A
                : 0xFF465364;

            addQuad(triangles,
                {(float)x,0,(float)z},
                {(float)(x+2),0,(float)z},
                {(float)(x+2),0,(float)(z+2)},
                {(float)x,0,(float)(z+2)},
                color);
        }
    }

    // Cyan ramp
    addRamp(triangles, ramps[0],
        0xFF3BC3DA,
        0xFF176781);

    // Orange ramp
    addRamp(triangles, ramps[1],
        0xFFF59155,
        0xFF974D35);

    // Elevated starting platform
    addBox(triangles,
        start.x0, start.x1,
        0.0f, start.top,
        start.y0, start.y1,
        0xFF8597B3,
        0xFF43546E);

    // Yellow takeoff stripe
    addBox(triangles,
        start.x0, start.x1,
        start.top, start.top + 0.025f,
        start.y1 - 0.35f,
        start.y1 - 0.15f,
        0xFFFFD54A,
        0xFFFFD54A);

    // Green goal platform
    addBox(triangles,
        goal.x0, goal.x1,
        0.0f, goal.top,
        goal.y0, goal.y1,
        0xFF4DD17A,
        0xFF26794B);

    // Goal arch: two posts and crossbar
    float archZ = goal.y0 + 0.8f;

    addBox(triangles,
        goal.x0 + 0.2f,
        goal.x0 + 0.55f,
        goal.top,
        goal.top + 4.0f,
        archZ,
        archZ + 0.3f,
        0xFFAAFFCC,
        0xFF35CC78);

    addBox(triangles,
        goal.x1 - 0.55f,
        goal.x1 - 0.2f,
        goal.top,
        goal.top + 4.0f,
        archZ,
        archZ + 0.3f,
        0xFFAAFFCC,
        0xFF35CC78);

    addBox(triangles,
        goal.x0 + 0.2f,
        goal.x1 - 0.2f,
        goal.top + 3.65f,
        goal.top + 4.0f,
        archZ,
        archZ + 0.3f,
        0xFFAAFFCC,
        0xFF35CC78);

    // Room walls
    const float left = -11.5f;
    const float right = 11.5f;
    const float front = -22.0f;
    const float back = 37.5f;
    const float height = 12.0f;

    // Left wall
    addQuad(triangles,
        {left,0,front},
        {left,0,back},
        {left,height,back},
        {left,height,front},
        0xFF263748);

    // Right wall
    addQuad(triangles,
        {right,0,back},
        {right,0,front},
        {right,height,front},
        {right,height,back},
        0xFF2B3649);

    // Back wall
    addQuad(triangles,
        {right,0,back},
        {left,0,back},
        {left,height,back},
        {right,height,back},
        0xFF304158);

    // Front wall
    addQuad(triangles,
        {left,0,front},
        {right,0,front},
        {right,height,front},
        {left,height,front},
        0xFF253649);
}

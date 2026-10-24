#pragma once
#include "scene.h"

// Position is the player's FEET. Y is up; X/Z are horizontal.
struct Player {
    Vec3 position{-2.5f, 8.0f, -17.5f};
    Vec3 velocity{0.0f, 0.0f, 0.0f};
    bool grounded = true;
    bool jumpWasDown = false;

    // HUD / course state, updated by shared physics on both platforms.
    int surfRamp = -1;          // -1 airborne/platform; 0 cyan; 1 orange
    bool onPlatform = true;
    bool touchedFirst = false;
    bool transferred = false;
    bool finished = false;
    float runSeconds = 0.0f;
};

struct MoveInput {
    float forward = 0.0f;
    float right = 0.0f;
    bool jump = false;
};

void respawn(Player& player);
void updatePhysics(Player& player, const Scene& scene,
                   const MoveInput& input, float cameraYaw, float dt);

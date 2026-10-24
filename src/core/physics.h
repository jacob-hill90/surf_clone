
#pragma once

#include "scene.h"

struct Player {
    // Position represents the player's feet.
    Vec3 position{-2.5f, 8.0f, -17.5f};

    Vec3 velocity{0.0f, 0.0f, 0.0f};

    bool grounded = true;
    bool jumpWasDown = false;
};

struct MoveInput {
    float forward = 0.0f;
    float right = 0.0f;
    bool jump = false;
};

// Reset to the starting platform.
void respawn(Player& player);

// Advance physics by one fixed timestep.
void updatePhysics(
    Player& player,
    const Scene& scene,
    const MoveInput& input,
    float cameraYaw,
    float dt
);


#include "physics.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr float GRAVITY = 19.0f;
constexpr float JUMP_SPEED = 7.5f;

constexpr float SURF_WISH_SPEED = 16.0f;
constexpr float SURF_ACCEL = 40.0f;

constexpr float GROUND_SPEED = 7.0f;
constexpr float GROUND_ACCEL = 35.0f;
constexpr float AIR_ACCEL = 9.0f;
constexpr float GROUND_FRICTION = 8.0f;

// Small allowance for floating-point errors
// when staying in contact with a ramp.
constexpr float CONTACT_EPSILON = 0.12f;;

constexpr float RESPAWN_Y = -4.0f;

float dot(Vec3 a, Vec3 b) {
    return a.x*b.x + a.y*b.y + a.z*b.z;
}

Vec3 normalize(Vec3 v) {
    float length = std::sqrt(dot(v, v));

    if (length < 0.00001f)
        return {0, 0, 0};

    return {
        v.x / length,
        v.y / length,
        v.z / length
    };
}

// Surface normal for height(x,z).
Vec3 rampNormal(const SurfRamp& ramp) {
    return normalize({
        -ramp.slopeX,
         1.0f,
        -ramp.slopeY
    });
}

Vec3 projectOntoPlane(Vec3 direction, Vec3 normal) {
    float amount = dot(direction, normal);

    return {
        direction.x - normal.x * amount,
        direction.y - normal.y * amount,
        direction.z - normal.z * amount
    };
}

// Remove velocity directed into a surface.
// Keep all velocity parallel to that surface.
void clipVelocity(Vec3& velocity, Vec3 normal) {
    float intoSurface = dot(velocity, normal);

    if (intoSurface < 0.0f) {
        velocity.x -= normal.x * intoSurface;
        velocity.y -= normal.y * intoSurface;
        velocity.z -= normal.z * intoSurface;
    }
}

bool insideRamp(
    const SurfRamp& ramp,
    float x,
    float z
) {
    return x >= ramp.x0 &&
           x <= ramp.x1 &&
           z >= ramp.y0 &&
           z <= ramp.y1;
}

// Check whether the player's feet are
// resting on one of our ramp surfaces.
const SurfRamp* findSupportingRamp(
    const Player& player,
    const Scene& scene
) {
    for (const SurfRamp& ramp : scene.ramps) {
        if (!insideRamp(
                ramp,
                player.position.x,
                player.position.z)) {
            continue;
        }

        float surfaceY = ramp.height(
            player.position.x,
            player.position.z
        );

        if (std::abs(player.position.y - surfaceY)
                <= CONTACT_EPSILON) {
            return &ramp;
        }
    }

    return nullptr;
}

// Acceleration in the camera-relative
// horizontal direction.
//
// This preserves existing speed rather
// than replacing the player's velocity.
void accelerate(
    Vec3& velocity,
    Vec3 wishDirection,
    float wishSpeed,
    float acceleration,
    float dt
) {
    float currentSpeed =
        velocity.x * wishDirection.x +
        velocity.z * wishDirection.z;

    float addSpeed = wishSpeed - currentSpeed;

    if (addSpeed <= 0.0f)
        return;

    float accelerationSpeed =
        acceleration * dt;

    accelerationSpeed =
        std::min(accelerationSpeed, addSpeed);

    velocity.x +=
        wishDirection.x * accelerationSpeed;

    velocity.z +=
        wishDirection.z * accelerationSpeed;
}

void applyGroundFriction(Vec3& velocity, float dt) {
    float speed = std::hypot(
        velocity.x,
        velocity.z
    );

    if (speed < 0.0001f) {
        velocity.x = 0.0f;
        velocity.z = 0.0f;
        return;
    }

    float newSpeed = std::max(
        0.0f,
        speed - speed * GROUND_FRICTION * dt
    );

    float scale = newSpeed / speed;

    velocity.x *= scale;
    velocity.z *= scale;
}

} // namespace

// =====================================
// RESPAWN
// =====================================

void respawn(Player& player) {
    player.position = {-2.5f, 8.0f, -17.5f};
    player.velocity = {0.0f, 0.0f, 0.0f};

    player.grounded = true;
    player.jumpWasDown = true;
}

// =====================================
// PLAYER PHYSICS
// =====================================

void updatePhysics(
    Player& player,
    const Scene& scene,
    const MoveInput& input,
    float cameraYaw,
    float dt
) {
    // ---------------------------------
    // 1. Determine existing ground state
    // ---------------------------------

    const SurfRamp* supportingRamp = nullptr;

    if (player.grounded) {
        supportingRamp =
            findSupportingRamp(player, scene);
    }

    bool onRamp = supportingRamp != nullptr;

    // ---------------------------------
    // 2. Build camera-relative input
    // ---------------------------------

    float forward = input.forward;
    float right = input.right;

    float inputLength =
        std::hypot(forward, right);

    if (inputLength > 1.0f) {
        forward /= inputLength;
        right /= inputLength;
    }

    float sinYaw = std::sin(cameraYaw);
    float cosYaw = std::cos(cameraYaw);

    Vec3 wishDirection{
        sinYaw * forward + cosYaw * right,
        0.0f,
        cosYaw * forward - sinYaw * right
    };

    float wishLength = std::hypot(
        wishDirection.x,
        wishDirection.z
    );

    if (wishLength > 0.0001f) {
        wishDirection.x /= wishLength;
        wishDirection.z /= wishLength;
    }

    // ---------------------------------
    // 3. Jumping
    // ---------------------------------

    bool jumpPressed =
        input.jump && !player.jumpWasDown;

    player.jumpWasDown = input.jump;

    bool jumping =
        jumpPressed && player.grounded;

    if (jumping) {
        // Add upward speed without
        // erasing horizontal momentum.
        player.velocity.y = JUMP_SPEED;
        player.grounded = false;
        onRamp = false;
    }

    // ---------------------------------
    // 4. Friction and acceleration
    // ---------------------------------

    // Friction only on flat platforms.
    // Surf ramps deliberately stay slippery.
    if (player.grounded && !onRamp) {
        applyGroundFriction(
            player.velocity, dt
        );
    }


if (wishLength > 0.0001f) {

    if (onRamp) {
        // Find the ramp's surface normal.
        Vec3 normal = rampNormal(*supportingRamp);

        // Convert horizontal input into
        // movement along the ramp surface.
        Vec3 surfDirection =
            projectOntoPlane(wishDirection, normal);

        surfDirection = normalize(surfDirection);

        // Add velocity along the ramp,
        // including the vertical component.
        float currentSpeed =
            dot(player.velocity, surfDirection);

        float addSpeed =
            SURF_WISH_SPEED - currentSpeed;

        if (addSpeed > 0.0f) {
            float accelSpeed =
                std::min(
                    SURF_ACCEL * dt,
                    addSpeed
                );

            player.velocity.x +=
                surfDirection.x * accelSpeed;

            player.velocity.y +=
                surfDirection.y * accelSpeed;

            player.velocity.z +=
                surfDirection.z * accelSpeed;
        }

    } else {
        float accel =
            player.grounded
                ? GROUND_ACCEL
                : AIR_ACCEL;

        accelerate(
            player.velocity,
            wishDirection,
            GROUND_SPEED,
            accel,
            dt
        );
    }
}


    // ---------------------------------
    // 5. Gravity
    // ---------------------------------

    // Always apply gravity. Ramp contact
    // will remove the component pushing
    // into the sloped surface.
    player.velocity.y -= GRAVITY * dt;

    if (onRamp && !jumping) {
        clipVelocity(
            player.velocity,
            rampNormal(*supportingRamp)
        );
    }

    // ---------------------------------
    // 6. Integrate position
    // ---------------------------------

    Vec3 previous = player.position;

    player.position.x += player.velocity.x * dt;
    player.position.y += player.velocity.y * dt;
    player.position.z += player.velocity.z * dt;

    // Recalculate contact every tick.
    player.grounded = false;

    // ---------------------------------
    // 7. Flat platform collisions
    // ---------------------------------

    auto collidePlatform =
        [&](const Platform& platform) {

        bool inside =
            player.position.x >= platform.x0 &&
            player.position.x <= platform.x1 &&
            player.position.z >= platform.y0 &&
            player.position.z <= platform.y1;

        if (!inside)
            return;

        bool crossingTop =
            previous.y >=
                platform.top - CONTACT_EPSILON &&
            player.position.y <= platform.top;

        if (crossingTop &&
            player.velocity.y <= 0.0f) {

            player.position.y = platform.top;
            player.velocity.y = 0.0f;
            player.grounded = true;
        }
    };

    collidePlatform(scene.start);
    collidePlatform(scene.goal);

    // ---------------------------------
    // 8. Surf ramp collisions
    // ---------------------------------

    if (!player.grounded) {
        for (const SurfRamp& ramp : scene.ramps) {

            float x = player.position.x;
            float z = player.position.z;

            if (!insideRamp(ramp, x, z))
                continue;

            float surfaceY = ramp.height(x, z);

            // Previous height measured
            // against the same ramp surface.
            float previousSurfaceY =
                ramp.height(previous.x, previous.z);

            float previousDistance =
                previous.y - previousSurfaceY;

            float currentDistance =
                player.position.y - surfaceY;

            // Did the feet cross the ramp
            // from above, or remain very
            // close to its surface?
            bool approachingFromAbove =
                previousDistance >=
                    -CONTACT_EPSILON;

            bool touchedSurface =
                currentDistance <=
                    CONTACT_EPSILON;

            Vec3 normal = rampNormal(ramp);

            float normalSpeed =
                dot(player.velocity, normal);

            // Only resolve when moving into
            // the ramp, not away from it.
            if (approachingFromAbove &&
                touchedSurface &&
                normalSpeed <= 0.0f) {

                player.position.y = surfaceY;

                clipVelocity(
                    player.velocity,
                    normal
                );

                player.grounded = true;
                break;
            }
        }
    }

    // ---------------------------------
    // 9. Respawn
    // ---------------------------------

    if (player.position.y < RESPAWN_Y) {
        respawn(player);
    }
}

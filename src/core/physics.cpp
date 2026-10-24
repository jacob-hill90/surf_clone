#include "physics.h"
#include <algorithm>
#include <cmath>

namespace {
// Adapted from the supplied original main.mm: same acceleration model and
// movement constants, but Y-up (old file was Z-up).
constexpr float GRAVITY = 20.0f;
constexpr float JUMP_SPEED = 5.4f;
constexpr float GROUND_WISH_SPEED = 7.0f;
constexpr float SURF_WISH_SPEED = 9.0f;
constexpr float AIR_WISH_SPEED = 2.8f;
constexpr float GROUND_ACCEL = 17.0f;
constexpr float SURF_ACCEL = 4.5f;
constexpr float AIR_ACCEL = 12.0f;
constexpr float GROUND_DRAG = 7.0f;
constexpr float SURF_DRAG = 0.06f;
constexpr float CONTACT_EPSILON = 0.035f;

float dot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
Vec3 unit(Vec3 v) {
    const float length = std::sqrt(dot(v,v));
    return length > 1e-6f ? Vec3{v.x/length,v.y/length,v.z/length} : Vec3{};
}
Vec3 normal(const SurfRamp& r) {
    return unit({-r.slopeX, 1.0f, -r.slopeY});
}
bool inside(const SurfRamp& r, float x, float z) {
    return x >= r.x0 && x <= r.x1 && z >= r.y0 && z <= r.y1;
}
bool inside(const Platform& p, float x, float z) {
    return x >= p.x0 && x <= p.x1 && z >= p.y0 && z <= p.y1;
}
void clipInto(Vec3& velocity, Vec3 n) {
    float into = dot(velocity,n);
    if (into < 0.0f) {
        velocity.x -= n.x*into;
        velocity.y -= n.y*into;
        velocity.z -= n.z*into;
    }
}
// Source/Quake-inspired acceleration. This caps velocity only in the
// *requested direction*, not total speed, so momentum can be preserved.
void accelerate(Player& player, Vec3 wish, float wishSpeed, float accel, float dt) {
    float along = player.velocity.x*wish.x + player.velocity.z*wish.z;
    float add = wishSpeed - along;
    if (add <= 0.0f) return;
    float amount = std::min(add, accel*wishSpeed*dt);
    player.velocity.x += wish.x*amount;
    player.velocity.z += wish.z*amount;
}
} // namespace

void respawn(Player& p) {
    p.position = {-2.5f, 8.0f, -17.5f};
    p.velocity = {};
    p.grounded = true;
    p.onPlatform = true;
    p.surfRamp = -1;
    p.touchedFirst = false;
    p.transferred = false;
    p.finished = false;
    p.runSeconds = 0.0f;
    p.jumpWasDown = true; // release Space before jumping again
}

void updatePhysics(Player& p, const Scene& scene,
                   const MoveInput& input, float yaw, float dt) {
    if (dt <= 0.0f || dt > 0.1f) return;
    const bool newJump = input.jump && !p.jumpWasDown;
    p.jumpWasDown = input.jump;
    if (p.finished) return; // Freeze simulation AND timer on victory.
    p.runSeconds += dt;

    const int previousRamp = p.surfRamp;
    const bool wasGrounded = p.grounded;
    if (newJump && (wasGrounded || previousRamp >= 0)) {
        p.velocity.y = std::max(p.velocity.y, 0.0f) + JUMP_SPEED;
        p.grounded = false;
        p.surfRamp = -1;
        p.onPlatform = false;
    }

    float forward = input.forward;
    float strafe = input.right;
    float length = std::hypot(forward, strafe);
    if (length > 0.0f) { forward /= length; strafe /= length; }
    Vec3 wish{
        std::sin(yaw)*forward + std::cos(yaw)*strafe,
        0.0f,
        std::cos(yaw)*forward - std::sin(yaw)*strafe
    };

    if (p.surfRamp >= 0) {
        float drag = std::exp(-SURF_DRAG*dt);
        p.velocity.x *= drag; p.velocity.z *= drag;
        if (length > 0.0f) accelerate(p,wish,SURF_WISH_SPEED,SURF_ACCEL,dt);
    } else if (p.grounded) {
        float drag = std::exp(-GROUND_DRAG*dt);
        p.velocity.x *= drag; p.velocity.z *= drag;
        if (length > 0.0f) accelerate(p,wish,GROUND_WISH_SPEED,GROUND_ACCEL,dt);
        p.velocity.y = 0.0f;
    } else {
        if (length > 0.0f) accelerate(p,wish,AIR_WISH_SPEED,AIR_ACCEL,dt);
    }

    p.velocity.y -= GRAVITY*dt;
    if (p.surfRamp >= 0)
        clipInto(p.velocity,normal(scene.ramps[p.surfRamp]));
    if (p.grounded && p.surfRamp < 0) p.velocity.y = 0.0f;

    const Vec3 previous = p.position;
    p.position.x += p.velocity.x*dt;
    p.position.y += p.velocity.y*dt;
    p.position.z += p.velocity.z*dt;

    p.grounded = false;
    p.onPlatform = false;
    p.surfRamp = -1;

    // The first ramp found from above wins. Allow continuing contact with
    // the old ramp within a small tolerance, as the reference game does.
    for (int i=0;i<(int)scene.ramps.size();++i) {
        const auto& ramp = scene.ramps[i];
        if (!inside(ramp,p.position.x,p.position.z)) continue;
        const float h = ramp.height(p.position.x,p.position.z);
        const float oldH = ramp.height(previous.x,previous.z);
        const bool fromAbove = previous.y >= oldH-CONTACT_EPSILON || previousRamp==i;
        const bool touched = (fromAbove && p.position.y<=h) ||
                             (previousRamp==i && p.position.y<=h+CONTACT_EPSILON);
        if (touched && dot(p.velocity,normal(ramp)) < 0.35f) {
            p.position.y = h;
            clipInto(p.velocity,normal(ramp));
            p.surfRamp = i;
            p.grounded = true;
            if (i==0) p.touchedFirst = true;
            if (i==1 && p.touchedFirst) p.transferred = true;
            break;
        }
    }

    if (p.surfRamp<0) {
        auto landed = [&](const Platform& platform) {
            return inside(platform,p.position.x,p.position.z) &&
                previous.y >= platform.top-CONTACT_EPSILON &&
                p.position.y <= platform.top+CONTACT_EPSILON &&
                p.velocity.y <= 0.0f;
        };
        if (landed(scene.start)) {
            p.position.y=scene.start.top; p.velocity.y=0;
            p.grounded=true; p.onPlatform=true;
        } else if (landed(scene.goal)) {
            p.position.y=scene.goal.top; p.velocity={};
            p.grounded=true; p.onPlatform=true;
            p.finished=true;
        }
    }

    // Checkerboard floor = fail/respawn. The original reset at floor height.
    if (!p.grounded && p.surfRamp<0 && p.position.y<=0.0f)
        respawn(p);
}

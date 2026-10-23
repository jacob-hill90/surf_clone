// Two-ramp course + raised start, goal platform, run timer, auto-respawn 
// macOS: clang++ -std=c++17 -O2 -fobjc-arc surf_course_goal.mm -framework Cocoa -framework CoreGraphics -o surf
// Click the window to capture mouse/trackpad; Esc releases it
// WASD move, Space jump, arrows look, R restarts timed run
// No OpenGL, Metal, third-party library, or game engine.
// Point-foot / plane-height collisions: playable surf prototype

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

#ifdef __APPLE__
#include <Cocoa/Cocoa.h>
#include <CoreGraphics/CoreGraphics.h>
#endif

using Pixel = std::uint32_t;
using Clock = std::chrono::steady_clock;

constexpr int SCREEN_W = 640;
constexpr int SCREEN_H = 360;
constexpr double STEP = 1.0 / 60.0;
constexpr double PI = 3.14159265358979323846;
constexpr double NEAR_PLANE = 0.06;

struct Vec3 {
    double x = 0, y = 0, z = 0;
    Vec3 operator+(Vec3 o) const { return {x + o.x, y + o.y, z + o.z}; }
    Vec3 operator-(Vec3 o) const { return {x - o.x, y - o.y, z - o.z}; }
    Vec3 operator*(double s) const { return {x * s, y * s, z * s}; }
};

double dot(Vec3 a, Vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
Vec3 cross(Vec3 a, Vec3 b) {
    return {a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x};
}
Vec3 normalized(Vec3 v) {
    double length = std::sqrt(dot(v, v));
    return length > 1e-9 ? v * (1.0 / length) : Vec3{};
}

Pixel rgb(int r, int g, int b) {
    return 0xFF000000u |
        (Pixel(std::clamp(r, 0, 255)) << 16) |
        (Pixel(std::clamp(g, 0, 255)) << 8) |
        Pixel(std::clamp(b, 0, 255));
}

struct Triangle {
    Vec3 a, b, c;
    Pixel color;
};

// =====================================
// SURF COURSE: RAMP GEOMETRY + PHYSICS
// =====================================
// Coordinates: Z is up, +Y is forward, +X is right.
// Each ramp is a tilted, finite plane, not a vertical raycast wall.
// Its height is z0 + slopeX*(x-x0) + slopeY*(y-y0).
// Ramp 1 rises on the RIGHT; ramp 2 rises on the LEFT.
struct SurfRamp {
    double x0, x1, y0, y1;
    double z0, slopeX, slopeY;
    bool contains(double x, double y) const {
        return x >= x0 && x <= x1 && y >= y0 && y <= y1;
    }
    double height(double x, double y) const {
        return z0 + slopeX*(x-x0) + slopeY*(y-y0);
    }
    Vec3 normal() const {
        return normalized({-slopeX, -slopeY, 1.0});
    }
};
constexpr std::array<SurfRamp, 2> RAMPS {{
    {-4.4, -0.8, -11.0, 1.8, 4.20, +0.90, -0.15},
    {+0.4, +4.0,   4.2, 17.0, 5.25, -0.90, -0.15}
}};

// A solid, elevated runway behind the cyan ramp.
// Feet stand on top at z = 8.0. The 1.35-unit gap before ramp 1
// encourages jumping, although a running drop can also work.
struct StartPlatform {
    double x0, x1, y0, y1, top;
    bool contains(double x, double y) const {
        return x >= x0 && x <= x1 && y >= y0 && y <= y1;
    }
};
constexpr StartPlatform START_PLATFORM{-4.3, -0.6, -19.0, -12.35, 8.0};

// Wide green finish deck beyond the end of the orange ramp.
// A short gap makes this a landing challenge. The player needs to land
// from above, flying alongside or passing underneath won't finish.
constexpr StartPlatform GOAL_PLATFORM{-5.5, 5.5, 18.35, 25.1, 1.10};

constexpr double EYE_HEIGHT = 1.65;
constexpr double GRAVITY = 17.0;
constexpr double JUMP_SPEED = 5.4;
constexpr double GROUND_SPEED = 7.0;
constexpr double SURF_WISH_SPEED = 9.0;
constexpr double AIR_WISH_SPEED = 2.8;

struct Keys {
    bool w=false, a=false, s=false, d=false;
    bool turnL=false, turnR=false, lookUp=false, lookDown=false;
    bool jumpQueued=false, topQueued=false, secondQueued=false, resetQueued=false;
};

struct Camera {
    Vec3 position;
    double yaw=0.0, pitch=0.0;
};

struct Player {
    // Position is at feet, not eyes. Velocity is units per second.
    // Spawn at the back of the elevated platform, facing ramp 1.
    Vec3 position{-2.5, -17.5, START_PLATFORM.top};
    Vec3 velocity{};
    double yaw=0.0, pitch=-0.13;
    bool onGround=true;
    bool onPlatform=true;
    int surfRamp=-1; // -1 means not surfing; 0 or 1 is an active ramp.
    int lastTouchedRamp=-1;
    bool touchedFirst=false;
    bool transferred=false;
    bool finished=false;
    double runSeconds=0.0;  // Fixed 60 Hz simulation stopwatch.

    Camera camera() const {
        return {{position.x, position.y, position.z + EYE_HEIGHT}, yaw, pitch};
    }
    void reset() { *this = Player{}; }

    void teleportToRamp(int index) {
        const auto &r = RAMPS[index];
        // Start near the high side, facing +Y. Already moving forward.
        const double x = index == 0 ? -1.9 : +1.5;
        const double y = r.y0 + 1.1;
        position={x, y, r.height(x,y)};
        velocity={0.0, 8.5, r.slopeY * 8.5};
        yaw=0.0;
        pitch=-0.18;
        onGround=false;
        onPlatform=false;
        surfRamp=index;
        lastTouchedRamp=index;
        touchedFirst=(index==0);
        transferred=false;
        finished=false;
        runSeconds=0.0;
    }

    // Quake/Source-inspired acceleration: only add velocity along a wish direction.
    // Importantly, we do NOT replace the existing velocity with wish*speed.
    void accelerate(Vec3 wish, double wishSpeed, double accel, double dt) {
        const double along=velocity.x*wish.x + velocity.y*wish.y;
        const double add=wishSpeed-along;
        if(add <= 0.0) return;
        const double amount=std::min(add, accel*wishSpeed*dt);
        velocity.x += wish.x*amount;
        velocity.y += wish.y*amount;
    }

    static void clipInto(Vec3& v, Vec3 normal) {
        // Remove inward normal velocity, preserve tangent velocity.
        double into=dot(v,normal);
        if(into < 0.0) v=v-normal*into;
    }

    // Returns true after a reset/teleport so rendering can immediately
    // snap to the new position instead of interpolating across the course.
    bool update(Keys& keys, double dt, double mouseDX, double mouseDY) {
        bool teleported = keys.resetQueued || keys.topQueued || keys.secondQueued;
        constexpr double MOUSE_SENS=0.0025;
        yaw+=(double(keys.turnR)-double(keys.turnL))*1.65*dt + mouseDX*MOUSE_SENS;
        pitch=std::clamp(pitch+(double(keys.lookUp)-double(keys.lookDown))*1.2*dt
                         -mouseDY*MOUSE_SENS,-1.30,1.30);

        if(keys.resetQueued) reset();
        else if(keys.topQueued) teleportToRamp(0);
        else if(keys.secondQueued) teleportToRamp(1);
        keys.resetQueued=keys.topQueued=keys.secondQueued=false;

        // Once you finish, freeze game physics and the stopwatch.
        // R / T / 2 still work so the player can restart or practice.
        if(finished) {
            keys.jumpQueued=false;
            return teleported;
        }

        // Timer resets on every new run/teleport and advances per physics step.
        runSeconds+=dt;

        // One jump per key-down; jumping takes you away from the ramp.
        if(keys.jumpQueued && (onGround || surfRamp>=0)) {
            velocity.z = std::max(velocity.z,0.0) + JUMP_SPEED;
            onGround=false;
            surfRamp=-1;
        }
        keys.jumpQueued=false;

        double forward=double(keys.w)-double(keys.s);
        double strafe=double(keys.d)-double(keys.a);
        double len=std::hypot(forward,strafe);
        if(len>0){forward/=len; strafe/=len;}
        Vec3 wish{std::sin(yaw)*forward+std::cos(yaw)*strafe,
                  std::cos(yaw)*forward-std::sin(yaw)*strafe,0.0};

        if(surfRamp>=0) {
            // Steep surf face: negligible friction, keep the acquired speed.
            double drag=std::exp(-0.06*dt);
            velocity.x*=drag; velocity.y*=drag;
            if(len>0) accelerate(wish,SURF_WISH_SPEED,4.5,dt);
        } else if(onGround) {
            double drag=std::exp(-7.0*dt);
            velocity.x*=drag; velocity.y*=drag;
            if(len>0) accelerate(wish,GROUND_SPEED,17.0,dt);
            velocity.z=0.0;
        } else {
            // Air-strafing: accelerate along the direction you're holding;
            // horizontal momentum in other directions remains intact.
            if(len>0) accelerate(wish,AIR_WISH_SPEED,12.0,dt);
        }

        velocity.z-=GRAVITY*dt;
        if(surfRamp>=0) clipInto(velocity,RAMPS[surfRamp].normal());
        if(onGround && surfRamp<0) velocity.z=0.0;

        Vec3 previous=position;
        int previousRamp=surfRamp;
        position=position + velocity*dt;

        // Simple arena boundaries, not full capsule-vs-mesh collision.
        if(position.x < -7.0 || position.x > 7.0) {
            position.x=std::clamp(position.x,-7.0,7.0);
            velocity.x=0.0;
        }
        if(position.y < -19.5 || position.y > 25.5) {
            position.y=std::clamp(position.y,-19.5,25.5);
            velocity.y=0.0;
        }

        surfRamp=-1;
        onGround=false;
        onPlatform=false;

        // Surface collision: compare foot height to the actual tilted plane.
        // From above, cross the plane and clip into its normal. Supports
        // sliding and landing on the *second* ramp from an airborne jump.
        for(int i=0;i<int(RAMPS.size());++i) {
            const SurfRamp& ramp=RAMPS[i];
            if(!ramp.contains(position.x,position.y)) continue;
            const double height=ramp.height(position.x,position.y);
            const double oldHeight=ramp.height(previous.x,previous.y);
            bool approachedFromAbove=(previous.z >= oldHeight-0.035);
            if(previousRamp==i) approachedFromAbove=true;
            if(((approachedFromAbove && position.z <= height) ||
                (previousRamp==i && position.z <= height+0.035)) &&
               dot(velocity,ramp.normal()) < 0.35) {
                position.z=height;
                clipInto(velocity,ramp.normal());
                surfRamp=i;
                lastTouchedRamp=i;
                if(i==0) touchedFirst=true;
                if(i==1 && touchedFirst) transferred=true;
                break;
            }
        }

        // NEW: The elevated start platform behaves like a real floor.
        // Only land on its TOP when coming from above: there is no
        // invisible collision that would teleport us up from below.
        if(surfRamp<0 && START_PLATFORM.contains(position.x, position.y) &&
           previous.z >= START_PLATFORM.top - 0.035 &&
           position.z <= START_PLATFORM.top + 0.035 &&
           velocity.z <= 0.0) {
            position.z=START_PLATFORM.top;
            velocity.z=0.0;
            onGround=true;
            onPlatform=true;
        }

        // NEW: Win by landing from above on the GOAL deck.
        // No win for touching a side face or passing underneath it.
        if(surfRamp<0 && !onGround &&
           GOAL_PLATFORM.contains(position.x,position.y) &&
           previous.z >= GOAL_PLATFORM.top - 0.035 &&
           position.z <= GOAL_PLATFORM.top + 0.035 &&
           velocity.z <= 0.0) {
            position.z=GOAL_PLATFORM.top;
            velocity={};
            onGround=true;
            finished=true;
            // runSeconds stops advancing after this exact physics step.
        }

        // NEW: The checkerboard floor is a fail zone.
        // Ramp and platform contact was checked above, so only a fall all
        // the way to z=0 respawns us at the elevated starting platform.
        if(!onGround && surfRamp<0 && position.z<=0.0) {
            reset();
            return true; // Tell the renderer the camera jumped elsewhere.
        }
        // No forced collision with wedge sides yet: point-feet prototype.
        return teleported;
    }
};

void addQuad(std::vector<Triangle>& mesh, Vec3 a,Vec3 b,Vec3 c,Vec3 d,Pixel color) {
    mesh.push_back({a,b,c,color});
    mesh.push_back({a,c,d,color});
}

struct Scene {
    std::vector<Triangle> triangles;
    Scene() {
        // Open sky and a checkerboard arena far below the elevated ramps.
        for(int x=-8;x<8;x+=2) {
            for(int y=-20;y<27;y+=2) {
                bool dark=(((x+y)/2)&1)!=0;
                Pixel tile=dark?rgb(49,60,72):rgb(62,76,90);
                addQuad(triangles,{double(x),double(y),0},
                    {double(x+2),double(y),0},
                    {double(x+2),double(y+2),0},
                    {double(x),double(y+2),0},tile);
            }
        }
        // NEW: Elevated launch platform rendered with our own triangles.
        // Alternating deck panels emphasize forward movement.
        const auto &p=START_PLATFORM;
        constexpr int DECK_PANELS=9;
        for(int i=0;i<DECK_PANELS;++i) {
            const double ya=p.y0+(p.y1-p.y0)*i/DECK_PANELS;
            const double yb=p.y0+(p.y1-p.y0)*(i+1)/DECK_PANELS;
            const Pixel deck=(i%2)?rgb(92,111,139):rgb(105,126,152);
            addQuad(triangles,{p.x0,ya,p.top},{p.x1,ya,p.top},
                {p.x1,yb,p.top},{p.x0,yb,p.top},deck);
        }
        // Solid sides down to the arena floor, plus brighter edges.
        const Pixel platformSide=rgb(61,73,100);
        for(double x:{p.x0,p.x1}) {
            addQuad(triangles,{x,p.y0,0},{x,p.y1,0},
                {x,p.y1,p.top},{x,p.y0,p.top},platformSide);
        }
        for(double y:{p.y0,p.y1}) {
            addQuad(triangles,{p.x0,y,0},{p.x1,y,0},
                {p.x1,y,p.top},{p.x0,y,p.top},rgb(74,88,115));
        }
        // Yellow takeoff stripe immediately before the jump gap.
        addQuad(triangles,{p.x0,p.y1-0.35,p.top+0.018},
            {p.x1,p.y1-0.35,p.top+0.018},
            {p.x1,p.y1-0.14,p.top+0.018},
            {p.x0,p.y1-0.14,p.top+0.018},rgb(255,221,112));
        // A center line pointing down the runway toward the cyan ramp.
        addQuad(triangles,{-2.53,p.y0+0.35,p.top+0.015},
            {-2.47,p.y0+0.35,p.top+0.015},
            {-2.47,p.y1-0.52,p.top+0.015},
            {-2.53,p.y1-0.52,p.top+0.015},rgb(212,230,241));

        // NEW: Green goal platform beyond the orange ramp.
        // Two-tone deck tiles and a checkerboard landing stripe.
        const auto& goal=GOAL_PLATFORM;
        constexpr int GOAL_ROWS=12;
        constexpr int GOAL_COLS=10;
        for(int row=0;row<GOAL_ROWS;++row) {
            double ya=goal.y0+(goal.y1-goal.y0)*row/GOAL_ROWS;
            double yb=goal.y0+(goal.y1-goal.y0)*(row+1)/GOAL_ROWS;
            for(int col=0;col<GOAL_COLS;++col) {
                double xa=goal.x0+(goal.x1-goal.x0)*col/GOAL_COLS;
                double xb=goal.x0+(goal.x1-goal.x0)*(col+1)/GOAL_COLS;
                Pixel tile=(row+col)%2 ? rgb(56,175,105) : rgb(77,209,122);
                if(row==1) tile=(col%2) ? rgb(37,52,51) : rgb(233,244,224);
                addQuad(triangles,{xa,ya,goal.top},{xb,ya,goal.top},
                    {xb,yb,goal.top},{xa,yb,goal.top},tile);
            }
        }
        // Solid sides of the finish deck (same collision simplification
        // as the starting deck: only top landing is currently solid).
        for(double x:{goal.x0,goal.x1}) {
            addQuad(triangles,{x,goal.y0,0},{x,goal.y1,0},
                {x,goal.y1,goal.top},{x,goal.y0,goal.top},rgb(31,96,70));
        }
        for(double y:{goal.y0,goal.y1}) {
            addQuad(triangles,{goal.x0,y,0},{goal.x1,y,0},
                {goal.x1,y,goal.top},{goal.x0,y,goal.top},rgb(38,124,78));
        }
        // Tall green portal markers make the finish easy to spot.
        auto goalMarker=[&](double x0,double x1,double y0,double y1,
                            double low,double high,Pixel color) {
            addQuad(triangles,{x0,y0,low},{x1,y0,low},
                {x1,y0,high},{x0,y0,high},color);
            addQuad(triangles,{x0,y1,low},{x1,y1,low},
                {x1,y1,high},{x0,y1,high},color);
            addQuad(triangles,{x0,y0,low},{x0,y1,low},
                {x0,y1,high},{x0,y0,high},color);
            addQuad(triangles,{x1,y0,low},{x1,y1,low},
                {x1,y1,high},{x1,y0,high},color);
        };
        const double markerY=goal.y0+0.8;
        goalMarker(goal.x0+0.20,goal.x0+0.48,markerY,markerY+0.24,
                   goal.top,goal.top+4.0,rgb(104,255,165));
        goalMarker(goal.x1-0.48,goal.x1-0.20,markerY,markerY+0.24,
                   goal.top,goal.top+4.0,rgb(104,255,165));
        goalMarker(goal.x0+0.20,goal.x1-0.20,markerY,markerY+0.24,
                   goal.top+3.64,goal.top+4.0,rgb(182,255,204));

        // Boundary walls to provide an obvious sense of depth.
        for(int y=-20;y<27;y+=4) {
            addQuad(triangles,{-7.5,double(y),0},{-7.5,double(y+4),0},
                {-7.5,double(y+4),10},{-7.5,double(y),10},rgb(38,55,72));
            addQuad(triangles,{7.5,double(y),0},{7.5,double(y+4),0},
                {7.5,double(y+4),10},{7.5,double(y),10},rgb(43,54,73));
        }
        addQuad(triangles,{-7.5,26.5,0},{7.5,26.5,0},
            {7.5,26.5,10},{-7.5,26.5,10},rgb(45,62,82));

        for(int ri=0;ri<int(RAMPS.size());++ri) {
            const SurfRamp& r=RAMPS[ri];
            const Pixel topA=ri==0?rgb(58,195,218):rgb(245,145,85);
            const Pixel topB=ri==0?rgb(42,157,190):rgb(211,109,80);
            const Pixel side=ri==0?rgb(28,100,135):rgb(138,70,76);
            const Pixel cap=ri==0?rgb(38,84,119):rgb(150,74,79);
            constexpr int SECTIONS=22;
            for(int i=0;i<SECTIONS;++i) {
                double ya=r.y0+(r.y1-r.y0)*i/SECTIONS;
                double yb=r.y0+(r.y1-r.y0)*(i+1)/SECTIONS;
                auto pt=[&](double x,double y,double lift=0.0)->Vec3 {
                    return {x,y,r.height(x,y)+lift};
                };
                addQuad(triangles,pt(r.x0,ya),pt(r.x1,ya),
                    pt(r.x1,yb),pt(r.x0,yb),(i%2)?topA:topB);
                // Curtain-like sides show ramp silhouette and height.
                for(double edgeX : {r.x0,r.x1}) {
                    addQuad(triangles,{edgeX,ya,0},{edgeX,yb,0},
                        pt(edgeX,yb),pt(edgeX,ya),side);
                }
            }
            auto pt=[&](double x,double y,double lift=0.0)->Vec3 {
                return {x,y,r.height(x,y)+lift};
            };
            for(double edgeY : {r.y0,r.y1}) {
                addQuad(triangles,{r.x0,edgeY,0},{r.x1,edgeY,0},
                    pt(r.x1,edgeY),pt(r.x0,edgeY),cap);
            }
            // Edge line shows which side is raised, using real triangles.
            const double highX=(r.slopeX>0)?r.x1:r.x0;
            double xa=(r.slopeX>0)?highX-0.10:highX;
            double xb=xa+0.10;
            addQuad(triangles,pt(xa,r.y0,0.015),pt(xb,r.y0,0.015),
                pt(xb,r.y1,0.015),pt(xa,r.y1,0.015),rgb(252,225,128));
            // Bright yellow launch stripe at the end of each ramp.
            addQuad(triangles,pt(r.x0,r.y1-0.25,0.016),pt(r.x1,r.y1-0.25,0.016),
                pt(r.x1,r.y1-0.13,0.016),pt(r.x0,r.y1-0.13,0.016),
                rgb(249,217,103));
        }
    }
};

struct Framebuffer {
    int w = SCREEN_W, h = SCREEN_H;
    std::vector<Pixel> pixels = std::vector<Pixel>(SCREEN_W * SCREEN_H);
    std::vector<float> depth = std::vector<float>(SCREEN_W * SCREEN_H);

    void clear() {
        for (int y = 0; y < h; ++y) {
            double t = double(y) / h;
            Pixel color = (y < h/2) ? rgb(int(19 + t*40), int(29 + t*45), int(49 + t*52))
                                    : rgb(32, 40, 54);
            std::fill(pixels.begin() + y*w, pixels.begin() + (y+1)*w, color);
        }
        std::fill(depth.begin(), depth.end(), 1e30f);
    }
    void pixel(int x, int y, Pixel p) {
        if (x >= 0 && y >= 0 && x < w && y < h) pixels[y*w+x] = p;
    }
    void rect(int x, int y, int width, int height, Pixel p) {
        for (int yy = std::max(0,y); yy < std::min(h,y+height); ++yy)
            for (int xx = std::max(0,x); xx < std::min(w,x+width); ++xx) pixel(xx,yy,p);
    }

    // Small built-in software font for the on-screen controls.
    static std::array<std::uint8_t,7> glyph(char c) {
        switch(c) {
            case 'A': return {14,17,17,31,17,17,17};
            case 'B': return {30,17,17,30,17,17,30};
            case 'C': return {15,16,16,16,16,16,15};
            case 'D': return {30,17,17,17,17,17,30};
            case 'E': return {31,16,16,30,16,16,31};
            case 'F': return {31,16,16,30,16,16,16};
            case 'G': return {15,16,16,23,17,17,15};
            case 'H': return {17,17,17,31,17,17,17};
            case 'I': return {31,4,4,4,4,4,31};
            case 'J': return {7,2,2,2,18,18,12};
            case 'K': return {17,18,20,24,20,18,17};
            case 'L': return {16,16,16,16,16,16,31};
            case 'M': return {17,27,21,21,17,17,17};
            case 'N': return {17,25,21,19,17,17,17};
            case 'O': return {14,17,17,17,17,17,14};
            case 'P': return {30,17,17,30,16,16,16};
            case 'Q': return {14,17,17,17,21,18,13};
            case 'R': return {30,17,17,30,20,18,17};
            case 'S': return {15,16,16,14,1,1,30};
            case 'T': return {31,4,4,4,4,4,4};
            case 'U': return {17,17,17,17,17,17,14};
            case 'V': return {17,17,17,17,17,10,4};
            case 'W': return {17,17,17,21,21,21,10};
            case 'X': return {17,17,10,4,10,17,17};
            case 'Y': return {17,17,10,4,4,4,4};
            case 'Z': return {31,1,2,4,8,16,31};
            case '1': return {4,12,4,4,4,4,14};
            case '2': return {14,17,1,2,4,8,31};
            case '3': return {30,1,1,14,1,1,30};
            case '4': return {2,6,10,18,31,2,2};
            case '5': return {31,16,16,30,1,1,30};
            case '6': return {14,16,16,30,17,17,14};
            case '7': return {31,1,2,4,8,8,8};
            case '8': return {14,17,17,14,17,17,14};
            case '9': return {14,17,17,15,1,1,14};
            case '0': return {14,17,19,21,25,17,14};
            case '/': return {1,1,2,4,8,16,16};
            case ':': return {0,4,4,0,4,4,0};
            case '-': return {0,0,0,31,0,0,0};
            case '.': return {0,0,0,0,0,12,12};
            default: return {0,0,0,0,0,0,0};
        }
    }
    void text(int x,int y,const std::string& s,Pixel color,int scale=2) {
        for(char c:s) {
            auto rows = glyph(c);
            for(int py=0;py<7;++py) for(int px=0;px<5;++px)
                if (rows[py] & (1 << (4-px))) rect(x+px*scale,y+py*scale,scale,scale,color);
            x+=6*scale;
        }
    }

    struct CameraVertex { double x, y, z; }; // Camera right, camera up, depth.
    CameraVertex view(Vec3 p, const Camera& cam) const {
        Vec3 forward{std::sin(cam.yaw)*std::cos(cam.pitch),
                     std::cos(cam.yaw)*std::cos(cam.pitch), std::sin(cam.pitch)};
        Vec3 right{std::cos(cam.yaw), -std::sin(cam.yaw), 0};
        Vec3 up = cross(right, forward);
        Vec3 d = p - cam.position;
        return {dot(d,right), dot(d,up), dot(d,forward)};
    }
    static CameraVertex mix(CameraVertex a, CameraVertex b, double t) {
        return {a.x+(b.x-a.x)*t, a.y+(b.y-a.y)*t, a.z+(b.z-a.z)*t};
    }
    struct ScreenVertex { double x, y, z; };
    ScreenVertex project(CameraVertex p) const {
        double focal = (w * 0.5) / std::tan(70.0 * PI / 360.0);
        return {w*0.5 + focal*p.x/p.z, h*0.5 - focal*p.y/p.z, p.z};
    }
    static double edge(ScreenVertex a, ScreenVertex b, double px, double py) {
        return (px-a.x)*(b.y-a.y) - (py-a.y)*(b.x-a.x);
    }

    void fillTriangle(ScreenVertex a, ScreenVertex b, ScreenVertex c, Pixel color) {
        double area = edge(a,b,c.x,c.y);
        if (std::abs(area) < 1e-8) return;
        int x0 = std::max(0,int(std::floor(std::min({a.x,b.x,c.x}))));
        int x1 = std::min(w-1,int(std::ceil(std::max({a.x,b.x,c.x}))));
        int y0 = std::max(0,int(std::floor(std::min({a.y,b.y,c.y}))));
        int y1 = std::min(h-1,int(std::ceil(std::max({a.y,b.y,c.y}))));
        if (x0 > x1 || y0 > y1) return;

        const double inv0 = 1.0/a.z, inv1 = 1.0/b.z, inv2 = 1.0/c.z;
        const int red = (color >> 16) & 255, green = (color >> 8) & 255, blue = color & 255;
        for(int y=y0;y<=y1;++y) {
            for(int x=x0;x<=x1;++x) {
                double px=x+0.5,py=y+0.5;
                double u=edge(b,c,px,py)/area;
                double v=edge(c,a,px,py)/area;
                double t=edge(a,b,px,py)/area;
                if(u < -1e-7 || v < -1e-7 || t < -1e-7) continue;
                // Perspective-correct depth: interpolate 1/z, then invert.
                double inverseZ = u*inv0 + v*inv1 + t*inv2;
                if (inverseZ <= 0) continue;
                float z = float(1.0/inverseZ);
                int index = y*w+x;
                if (z >= depth[index]) continue;
                depth[index] = z;
                double shade = std::max(0.28, 1.0 / (1.0 + z*0.028));
                pixels[index] = rgb(int(red*shade),int(green*shade),int(blue*shade));
            }
        }
    }

    void drawTriangle(const Triangle& triangle, const Camera& camera) {
        // Transform three 3D world-space vertices into camera space.
        std::array<CameraVertex,3> vertices = {
            view(triangle.a,camera),view(triangle.b,camera),view(triangle.c,camera)};
        // Clip triangle to the plane z >= NEAR_PLANE.
        // Unlike dropping near vertices, this works even when the camera
        // is close to or partially inside a triangle.
        std::vector<CameraVertex> polygon(vertices.begin(),vertices.end());
        std::vector<CameraVertex> clipped;
        for (std::size_t i=0;i<polygon.size();++i) {
            auto a=polygon[i], b=polygon[(i+1)%polygon.size()];
            bool insideA=a.z>=NEAR_PLANE, insideB=b.z>=NEAR_PLANE;
            if (insideA != insideB) {
                double t=(NEAR_PLANE-a.z)/(b.z-a.z);
                clipped.push_back(mix(a,b,t));
            }
            if (insideB) clipped.push_back(b);
        }
        if (clipped.size()<3) return;
        ScreenVertex v0=project(clipped[0]);
        for (std::size_t i=1;i+1<clipped.size();++i)
            fillTriangle(v0,project(clipped[i]),project(clipped[i+1]),triangle.color);
    }

    void render(const Scene& scene, const Camera& camera,
                const Player& player, bool mouseCaptured) {
        clear();
        for(const Triangle& tri : scene.triangles) drawTriangle(tri,camera);
        rect(w/2-5,h/2,11,1,rgb(225,237,243));
        rect(w/2,h/2-5,1,11,rgb(225,237,243));
        rect(7,7,625,45,rgb(20,29,44));
        text(14,12,"TWO RAMP SURF COURSE",rgb(245,224,165),2);
        int speed=static_cast<int>(std::round(std::hypot(player.velocity.x,player.velocity.y)));
        std::string status=player.finished ? "GOAL" :
            (player.surfRamp>=0 ? (player.surfRamp==0 ? "SURF 1":"SURF 2")
             : (player.onPlatform?"PLATFORM":(player.onGround?"GROUND":"AIR")));
        text(352,12,"SPD:"+std::to_string(speed)+" "+status,rgb(175,245,215),2);
        char timerText[40];
        std::snprintf(timerText,sizeof(timerText),"TIME: %06.2f S",player.runSeconds);
        text(14,34,timerText,player.finished?rgb(166,255,180):rgb(242,245,248),2);
        text(340,34,"LAND ON GREEN TO WIN",rgb(157,255,174),2);
        if(player.transferred && !player.finished) {
            rect(186,60,270,24,rgb(29,65,49));
            text(198,65,"TRANSFER COMPLETE!",rgb(162,255,189),2);
        }
        if(player.finished) {
            rect(128,118,384,105,rgb(14,57,42));
            rect(132,122,376,97,rgb(23,84,55));
            text(166,136,"COURSE COMPLETE!",rgb(214,255,172),3);
            text(226,176,timerText,rgb(255,255,245),2);
            text(188,202,"PRESS R TO PLAY AGAIN",rgb(228,244,233),2);
        }
        rect(7,h-29,625,22,rgb(20,29,44));
        text(14,h-24,mouseCaptured ? "WASD SPACE JUMP  R PLATFORM  T RAMP1  2 RAMP2" :
                      "CLICK MOUSE LOOK  SPACE JUMP  R PLATFORM",rgb(232,237,244),2);
    }
};

#ifdef __APPLE__
@interface RampView : NSView {
    Framebuffer _screen;
    Scene _scene;
    Player _player;
    Player _previous;
    Keys _keys;
    NSTimer *_timer;
    Clock::time_point _last;
    double _accumulator;
    double _alpha;
    double _mouseDX, _mouseDY;
    BOOL _mouseCaptured, _cursorDetached;
}
@end
@implementation RampView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isOpaque { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
    self=[super initWithFrame:frame];
    if(self) {
        _previous=_player;
        _last=Clock::now();
        _accumulator=0; _alpha=0;
        _mouseDX=_mouseDY=0;
        _mouseCaptured=_cursorDetached=NO;
        _timer=[NSTimer timerWithTimeInterval:1.0/60.0 target:self
                 selector:@selector(tick:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(windowResignedKey:)
            name:NSWindowDidResignKeyNotification object:nil];
    }
    return self;
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.window setAcceptsMouseMovedEvents:YES];
}
- (void)captureMouse {
    if (_mouseCaptured || ![self.window isKeyWindow]) return;
    [self.window makeFirstResponder:self];
    // CGAssociate disconnects physical cursor position from relative deltas.
    _cursorDetached=(CGAssociateMouseAndMouseCursorPosition(false)==kCGErrorSuccess);
    if (_cursorDetached) [NSCursor hide];
    _mouseCaptured=YES;
    _mouseDX=_mouseDY=0;
}
- (void)releaseMouse {
    if (!_mouseCaptured) return;
    _mouseCaptured=NO;
    if (_cursorDetached) {
        CGAssociateMouseAndMouseCursorPosition(true);
        [NSCursor unhide];
        _cursorDetached=NO;
    }
    _mouseDX=_mouseDY=0;
}
- (void)windowResignedKey:(NSNotification*)notification {
    if ([notification object]==self.window) {
        [self releaseMouse];
        _keys=Keys{};
    }
}
- (void)dealloc {
    [self releaseMouse];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
}
- (void)mouseDown:(NSEvent*)event { [self captureMouse]; }
- (void)mouseMoved:(NSEvent*)event {
    if (!_mouseCaptured) return;
    _mouseDX += [event deltaX];
    _mouseDY += [event deltaY];
}
- (void)mouseDragged:(NSEvent*)event { [self mouseMoved:event]; }
- (void)rightMouseDragged:(NSEvent*)event { [self mouseMoved:event]; }
- (void)tick:(NSTimer*)timer {
    auto now=Clock::now();
    double elapsed=std::chrono::duration<double>(now-_last).count();
    _last=now;
    if (![self.window isKeyWindow]) {
        _keys=Keys{};
        if (_mouseCaptured) [self releaseMouse];
    }
    _accumulator+=std::min(elapsed,0.1);
    // Accumulate mouse movement until a fixed simulation step is available.
    if (_accumulator>=STEP) {
        double dx=_mouseDX,dy=_mouseDY;
        _mouseDX=_mouseDY=0;
        bool first=true;
        while(_accumulator>=STEP) {
            _previous=_player;
            bool teleported=_player.update(_keys,STEP,first?dx:0.0,first?dy:0.0);
            // Important: without this, render interpolation would animate
            // the camera from the floor all the way back to the platform.
            if(teleported) _previous=_player;
            first=false;
            _accumulator-=STEP;
        }
    }
    _alpha=std::clamp(_accumulator/STEP,0.0,1.0);
    [self setNeedsDisplay:YES];
}
- (void)setKey:(NSEvent*)event held:(BOOL)held {
    NSString* chars=[[event charactersIgnoringModifiers] lowercaseString];
    if(!chars.length) return;
    unichar c=[chars characterAtIndex:0];
    switch(c) {
        case 'w': _keys.w=held; break;
        case 'a': _keys.a=held; break;
        case 's': _keys.s=held; break;
        case 'd': _keys.d=held; break;
        case NSLeftArrowFunctionKey: _keys.turnL=held; break;
        case NSRightArrowFunctionKey: _keys.turnR=held; break;
        case NSUpArrowFunctionKey: _keys.lookUp=held; break;
        case NSDownArrowFunctionKey: _keys.lookDown=held; break;
        case ' ': if (held && ![event isARepeat]) _keys.jumpQueued=true; break;
        case 't': if (held && ![event isARepeat]) _keys.topQueued=true; break;
        case '2': if (held && ![event isARepeat]) _keys.secondQueued=true; break;
        case 'r': if (held && ![event isARepeat]) _keys.resetQueued=true; break;
        case 27: if (held) [self releaseMouse]; break;
    }
}
- (void)keyDown:(NSEvent*)e { [self setKey:e held:YES]; }
- (void)keyUp:(NSEvent*)e { [self setKey:e held:NO]; }
- (void)drawRect:(NSRect)dirtyRect {
    const double alpha=_alpha;
    auto lerp=[alpha](double a,double b){return a+(b-a)*alpha;};
    Player visible=_player;
    visible.position={lerp(_previous.position.x,_player.position.x),
                      lerp(_previous.position.y,_player.position.y),
                      lerp(_previous.position.z,_player.position.z)};
    visible.yaw=lerp(_previous.yaw,_player.yaw);
    visible.pitch=lerp(_previous.pitch,_player.pitch);
    _screen.render(_scene,visible.camera(),_player,_mouseCaptured);
    // Only present finished pixel buffer via Core Graphics.
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider=CGDataProviderCreateWithData(nullptr,
         _screen.pixels.data(),_screen.pixels.size()*sizeof(Pixel),nullptr);
    CGBitmapInfo format=static_cast<CGBitmapInfo>(
         kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
    CGImageRef image=CGImageCreate(_screen.w,_screen.h,8,32,
         _screen.w*sizeof(Pixel),space,format,provider,nullptr,false,
         kCGRenderingIntentDefault);
    if(image) {
        CGContextRef context=[[NSGraphicsContext currentContext] CGContext];
        CGContextSaveGState(context);
        CGContextSetInterpolationQuality(context,kCGInterpolationNone);
        CGContextDrawImage(context,self.bounds,image);
        CGContextRestoreGState(context);
        CGImageRelease(image);
    }
    if(provider) CGDataProviderRelease(provider);
    if(space) CGColorSpaceRelease(space);
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation AppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {return YES;}
@end

int main() {
    @autoreleasepool {
        NSApplication* app=[NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate* delegate=[AppDelegate new];
        [app setDelegate:delegate];
        NSRect frame=NSMakeRect(0,0,1280,720);
        NSWindow* window=[[NSWindow alloc] initWithContentRect:frame
             styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|
                        NSWindowStyleMaskResizable)
             backing:NSBackingStoreBuffered defer:NO];
        [window setTitle:@"Surf Course — Finish Platform + Timer"];
        [window setContentMinSize:NSMakeSize(640,360)];
        [window setContentAspectRatio:NSMakeSize(16,9)];
        RampView* view=[[RampView alloc] initWithFrame:frame];
        [window setContentView:view];
        [window makeFirstResponder:view];
        [window center];
        [window makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
#else
// Portable C++ preview & physics tests, allowing validation without macOS.
int main(int argc,char** argv) {
    Scene scene;
    Player player;
    std::string mode=argc>1?argv[1]:"preview";
    if(mode=="top" || mode=="test") player.teleportToRamp(0);
    if(mode=="second") player.teleportToRamp(1);
    if(mode=="test") {
        Keys keys;
        double initialY=player.position.y;
        double maxY=initialY;
        double peakSpeed=0;
        int surfFrames=0;
        bool airborne=false;
        bool fellAndRespawned=false;
        // Holding W and D balances sideways gravity and builds forward speed.
        keys.w=true;
        keys.d=true;
        for(int i=0;i<135;i++) {
            bool respawned=player.update(keys,STEP,0,0);
            if(respawned && player.onPlatform) fellAndRespawned=true;
            maxY=std::max(maxY,player.position.y);
            peakSpeed=std::max(peakSpeed,std::hypot(player.velocity.x,player.velocity.y));
            if(player.surfRamp==0) surfFrames++;
            if(player.surfRamp<0 && !player.onGround) airborne=true;
        }
        std::printf("RAMP 1: initialY %.3f maxY %.3f peakSpeed %.2f surfFrames %d airborne %d respawned %d\n",
                    initialY,maxY,peakSpeed,surfFrames,int(airborne),int(fellAndRespawned));
        if(!(maxY>initialY+1 && peakSpeed>5 && surfFrames>10)) return 2;

        player.teleportToRamp(1);
        keys=Keys{};
        const double initialZ=player.position.z;
        for(int i=0;i<8;++i)player.update(keys,STEP,0,0);
        std::printf("RAMP 2: height %.3f -> %.3f surfRamp %d\n",
                    initialZ,player.position.z,player.surfRamp);
        if(player.surfRamp!=1) return 3;

        player.teleportToRamp(0);
        keys=Keys{}; keys.jumpQueued=true;
        player.update(keys,STEP,0,0);
        std::printf("JUMP: vertical speed %.3f inAir %d\n",
                    player.velocity.z,int(player.surfRamp<0 && !player.onGround));
        if(player.surfRamp>=0 || player.onGround || player.velocity.z<=0) return 4;

        // Drop onto ramp 2 from ABOVE and require tangential collision response.
        const auto& r=RAMPS[1];
        player.position={2.0,9.0,r.height(2.0,9.0)+1.2};
        player.velocity={0,0,-2.0};
        player.onGround=false;player.surfRamp=-1;
        keys=Keys{};
        bool landed=false;
        for(int i=0;i<50;++i) {
            player.update(keys,STEP,0,0);
            if(player.surfRamp==1) {landed=true;break;}
        }
        std::printf("SECOND RAMP LANDING: %d footZ %.3f\n",int(landed),player.position.z);
        if(!landed) return 5;

        // A reproducible two-ramp transfer (jump + air-strafe) through
        // the actual physics code. The second ramp must be reached.
        player.teleportToRamp(0);
        player.yaw=0.275;
        bool transferred=false;
        for(int frame=0;frame<175;++frame) {
            Keys control;
            if(frame<29) {
                control.w=true; control.d=true;
            } else {
                control.w=true; control.d=true;
                if(frame==29) {
                    control.jumpQueued=true;
                    player.yaw=0.430;
                }
            }
            player.update(control,STEP,0,0);
            if(player.transferred) { transferred=true; break; }
        }
        std::printf("SCRIPTED TRANSFER: %d pos (%.2f, %.2f, %.2f)\n",
            int(transferred),player.position.x,player.position.y,player.position.z);
        if(!transferred) return 6;
        std::puts("ALL TESTS PASSED");
        return 0;
    }
    if(mode=="overview") {
        // Elevated spectator view shows the platform and both ramps.
        player.position={-5.8,-20.0,14.0-EYE_HEIGHT};
        player.yaw=0.12;
        player.pitch=-0.45;
    }
    if(mode=="goal") {
        player.position={2.0,13.0,5.6};
        player.yaw=0.04;
        player.pitch=-0.22;
    }
    if(mode=="goaloverview") {
        player.position={-5.7,10.6,13.8};
        player.yaw=0.24;
        player.pitch=-0.56;
    }
    if(mode=="launch") {
        // See the takeoff stripe and the first ramp from the runway.
        player.position={-2.5,-13.65,START_PLATFORM.top};
        player.pitch=-0.25;
    }
    Framebuffer buffer;
    buffer.render(scene,player.camera(),player,false);
    std::string filename="/mnt/data/surf_goal_"+mode+".ppm";
    std::ofstream out(filename,std::ios::binary);
    out<<"P6\n"<<buffer.w<<" "<<buffer.h<<"\n255\n";
    for(Pixel color:buffer.pixels) {
        unsigned char bytes[]={(unsigned char)(color>>16),
            (unsigned char)(color>>8),(unsigned char)color};
        out.write(reinterpret_cast<char*>(bytes),3);
    }
    std::printf("Wrote %s: %zu triangles\n",filename.c_str(),scene.triangles.size());
    return 0;
}
#endif

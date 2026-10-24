#pragma once
#include "framebuffer.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <vector>

// Right-handed camera: +X right, +Y up, +Z forward.
struct Vec3 {
    float x{},y{},z{};
    Vec3 operator+(Vec3 b) const {return {x+b.x,y+b.y,z+b.z};}
    Vec3 operator-(Vec3 b) const {return {x-b.x,y-b.y,z-b.z};}
};

struct Triangle {Vec3 a,b,c; std::uint32_t color;};
struct Camera {
    Vec3 position{0.0f, 1.7f, 0.0f};
    float yaw = 0.0f;
    float pitch = 0.0f;
};

class Renderer {
    struct Projected {float x,y,invZ;};
    static constexpr float NEAR_Z=0.08f;
    std::vector<float> depth;
    Vec3 cameraSpace(Vec3 p,const Camera& c) const {
        p=p-c.position;
        float cy=std::cos(c.yaw), sy=std::sin(c.yaw);
        float x=cy*p.x-sy*p.z;
        float z=sy*p.x+cy*p.z;
        float cp=std::cos(c.pitch), sp=std::sin(c.pitch);
        return {x,cp*p.y-sp*z,sp*p.y+cp*z};
    }
    Projected project(Vec3 p) const {
        float f=(framebuffer.height*0.5f)/std::tan(70.0f*3.1415926535f/360.0f);
        return {framebuffer.width*0.5f+f*p.x/p.z, framebuffer.height*0.5f-f*p.y/p.z,1.0f/p.z};
    }
    static float edge(Projected a,Projected b,float x,float y) {
        return (x-a.x)*(b.y-a.y)-(y-a.y)*(b.x-a.x);
    }
    void rasterize(Projected a,Projected b,Projected c,std::uint32_t color) {
        float area=edge(a,b,c.x,c.y);
        if(std::abs(area)<1e-6f) return;
        int minX=std::max(0,(int)std::floor(std::min({a.x,b.x,c.x})));
        int maxX=std::min(framebuffer.width-1,(int)std::ceil(std::max({a.x,b.x,c.x})));
        int minY=std::max(0,(int)std::floor(std::min({a.y,b.y,c.y})));
        int maxY=std::min(framebuffer.height-1,(int)std::ceil(std::max({a.y,b.y,c.y})));
        for(int y=minY;y<=maxY;y++)for(int x=minX;x<=maxX;x++){
            float px=x+0.5f,py=y+0.5f;
            float wa=edge(b,c,px,py)/area,wb=edge(c,a,px,py)/area,wc=edge(a,b,px,py)/area;
            if(wa<0||wb<0||wc<0)continue;
            // Linear interpolation of inverse camera-space depth is correct for perspective projection.
            float invZ=wa*a.invZ+wb*b.invZ+wc*c.invZ;
            size_t i=static_cast<size_t>(y)*framebuffer.width+x;
            if(invZ>depth[i]) {depth[i]=invZ;framebuffer.pixels[i]=color;}
        }
    }
public:
    Framebuffer framebuffer;
    Renderer(int w,int h):depth(static_cast<size_t>(w)*h),framebuffer(w,h){}
    void clear(std::uint32_t color){framebuffer.clear(color);std::fill(depth.begin(),depth.end(),-std::numeric_limits<float>::infinity());}
    void drawWorldTriangle(const Triangle& t,const Camera& camera) {
        std::array<Vec3,6> in{};
        in[0]=cameraSpace(t.a,camera);in[1]=cameraSpace(t.b,camera);in[2]=cameraSpace(t.c,camera);
        std::array<Vec3,6> out{};int n=0;
        // Clip polygon against the near plane before perspective division.
        for(int i=0;i<3;i++) {
            Vec3 a=in[i],b=in[(i+1)%3];bool insideA=a.z>=NEAR_Z,insideB=b.z>=NEAR_Z;
            if(insideA)out[n++]=a;
            if(insideA!=insideB){float t=(NEAR_Z-a.z)/(b.z-a.z);out[n++]={a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,NEAR_Z};}
        }
        if(n<3)return;
        Projected anchor=project(out[0]);
        for(int i=1;i+1<n;i++)rasterize(anchor,project(out[i]),project(out[i+1]),t.color);
    }
};
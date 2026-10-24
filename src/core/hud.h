#pragma once
#include "framebuffer.h"
#include "physics.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <string>

// Screen-space bitmap HUD; works with either Cocoa or Win32.
namespace SurfHUD {
using Pixel = std::uint32_t;
constexpr Pixel rgb(int r,int g,int b) {
    return 0xFF000000u | (Pixel(r)<<16) | (Pixel(g)<<8) | Pixel(b);
}
inline void rect(Framebuffer& f,int x,int y,int w,int h,Pixel color) {
    for (int py=std::max(0,y);py<std::min(f.height,y+h);++py)
        for (int px=std::max(0,x);px<std::min(f.width,x+w);++px)
            f.setPixel(px,py,color);
}
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
inline void text(Framebuffer& f,int x,int y,const std::string& message,Pixel color,int scale=1) {
    for (char c : message) {
        const auto rows=glyph(c);
        for(int py=0;py<7;++py) for(int px=0;px<5;++px)
            if(rows[py] & (1 << (4-px)))
                rect(f,x+px*scale,y+py*scale,scale,scale,color);
        x+=6*scale;
    }
}
inline void draw(Framebuffer& fb,const Player& player,bool captured) {
    const int w=fb.width, h=fb.height;
    const int scale=(w>=640 && h>=360)?2:1;
    const int pad=7*scale, textY=10*scale;
    const Pixel back=rgb(20,29,44), white=rgb(232,237,244);
    const int headerH=41*scale;
    rect(fb,0,0,w,headerH,back);
    text(fb,pad,textY,"TWO RAMP COURSE",rgb(245,224,165),scale);

    const int speed=(int)std::lround(std::hypot(player.velocity.x,player.velocity.z));
    const std::string status=player.finished?"GOAL":
        (player.surfRamp==0?"SURF 1":player.surfRamp==1?"SURF 2":
         player.onPlatform?"PLATFORM":player.grounded?"GROUND":"AIR");
    const std::string speedText="SPD:"+std::to_string(speed)+" "+status;
    const int speedX=std::max(pad,w-(int)speedText.size()*6*scale-pad);
    text(fb,speedX,textY,speedText,rgb(175,245,215),scale);

    char timer[40];
    std::snprintf(timer,sizeof(timer),"TIME: %06.2f S",player.runSeconds);
    text(fb,pad,25*scale,timer,player.finished?rgb(166,255,180):white,scale);
    const std::string instruction="LAND ON GREEN TO WIN";
    const int instructionX=std::max(pad,w-(int)instruction.size()*6*scale-pad);
    text(fb,instructionX,25*scale,instruction,rgb(157,255,174),scale);

    // Draw crosshair after 3D triangles, like the reference implementation.
    rect(fb,w/2-5,h/2,11,1,rgb(225,237,243));
    rect(fb,w/2,h/2-5,1,11,rgb(225,237,243));

    if(player.transferred && !player.finished) {
        const std::string msg="TRANSFER COMPLETE!";
        const int boxW=(int)msg.size()*6*scale+16*scale;
        const int x=(w-boxW)/2, y=headerH+10*scale;
        rect(fb,x,y,boxW,22*scale,rgb(29,65,49));
        text(fb,x+8*scale,y+6*scale,msg,rgb(162,255,189),scale);
    }
    if(player.finished) {
        const int boxW=std::min(w-20*scale,220*scale);
        const int x=(w-boxW)/2,y=(h-62*scale)/2;
        rect(fb,x,y,boxW,62*scale,rgb(23,84,55));
        text(fb,x+8*scale,y+8*scale,"COURSE COMPLETE!",rgb(214,255,172),scale);
        text(fb,x+8*scale,y+26*scale,timer,white,scale);
        text(fb,x+8*scale,y+44*scale,"PRESS R TO RESTART",white,scale);
    }
    rect(fb,0,h-18*scale,w,18*scale,back);
    text(fb,pad,h-13*scale,captured ? "WASD SPACE JUMP  R RESTART" : "CLICK FOR MOUSE LOOK  R RESTART",white,scale);
}
} // namespace SurfHUD

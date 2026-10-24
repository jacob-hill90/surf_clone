#pragma once
#include <algorithm>
#include <cstdint>
#include <vector>

struct Framebuffer {
    int width, height;
    std::vector<std::uint32_t> pixels;
    Framebuffer(int w, int h): width(w), height(h), pixels(static_cast<size_t>(w)*h) {}
    void clear(std::uint32_t c) { std::fill(pixels.begin(), pixels.end(), c); }
    void setPixel(int x,int y,std::uint32_t c) {
        if (x>=0 && y>=0 && x<width && y<height) pixels[static_cast<size_t>(y)*width+x]=c;
    }
};


#pragma once

#include "renderer.h"

#include <array>
#include <vector>

struct SurfRamp {
    float x0, x1;
    float y0, y1;

    float z0;
    float slopeX;
    float slopeY;

    float height(float x, float y) const {
        return z0
            + slopeX * (x - x0)
            + slopeY * (y - y0);
    }
};

struct Platform {
    float x0, x1;
    float y0, y1;
    float top;
};

struct Scene {
    std::vector<Triangle> triangles;

    std::array<SurfRamp, 2> ramps{{
        {-4.4f, -0.8f, -11.0f, 1.8f,
         4.20f, 0.90f, -0.15f},

        {0.4f, 4.0f, 4.2f, 17.0f,
         5.25f, -0.90f, -0.15f}
    }};

    Platform start{
        -4.3f, -0.6f,
        -19.0f, -12.35f,
        8.0f
    };

    Platform goal{
        -5.5f, 5.5f,
        18.35f, 25.1f,
        1.10f
    };

    Scene();
};

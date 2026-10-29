// SPDX-License-Identifier: Apache-2.0
// Pure, host-testable conversion of PICO raw RGBA camera frames for QR decoding.
// Never retain a pointer after the OpenXR image is released.
#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <vector>
#include <utility>

namespace pico_qr {

struct RgbaFrame {
    const uint8_t* data;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t pixelStride;
    uint32_t bytesPerPixel;
    uint64_t bufferSize;
};

struct GrayFrame {
    uint32_t width = 0;
    uint32_t height = 0;
    std::vector<uint8_t> pixels;
};

// This validates the full plane before dereferencing a single pixel.
// Runtime stride/padding may be larger than width * bytesPerPixel.
inline bool validRgbaFrame(const RgbaFrame& frame) {
    if (!frame.data || frame.width == 0 || frame.height == 0 ||
        frame.width > 8192 || frame.height > 8192 ||
        frame.bytesPerPixel != 4 || frame.pixelStride < 4 ||
        frame.pixelStride > 16 || frame.bufferSize == 0 ||
        frame.bufferSize > 256ull * 1024 * 1024) {
        return false;
    }
    const uint64_t lastPixelEnd =
        static_cast<uint64_t>(frame.width - 1) * frame.pixelStride + 4;
    const uint64_t lastRowEnd =
        static_cast<uint64_t>(frame.height - 1) * frame.stride + lastPixelEnd;
    return frame.stride >= lastPixelEnd && frame.bufferSize >= lastRowEnd;
}

// Alternate full view and centered half-view on successive frames.
// Both modes always bound the decoded plane to 1024px on its longest side.
inline bool toGray(const RgbaFrame& src, bool center, GrayFrame& out) {
    if (!validRgbaFrame(src)) return false;
    const bool crop = center && src.width >= 512 && src.height >= 512;
    const uint32_t x0 = crop ? src.width / 4 : 0;
    const uint32_t y0 = crop ? src.height / 4 : 0;
    const uint32_t roiW = crop ? src.width / 2 : src.width;
    const uint32_t roiH = crop ? src.height / 2 : src.height;
    const uint32_t step = std::max(1u, (std::max(roiW, roiH) + 1023) / 1024);
    const uint32_t w = (roiW + step - 1) / step;
    const uint32_t h = (roiH + step - 1) / step;
    std::vector<uint8_t> gray(static_cast<size_t>(w) * h);

    for (uint32_t y = 0; y < h; ++y) {
        const size_t rowOffset = static_cast<size_t>(y0 + y * step) * src.stride;
        const uint8_t* row = src.data + rowOffset;
        for (uint32_t x = 0; x < w; ++x) {
            const size_t colOffset =
                static_cast<size_t>(x0 + x * step) * src.pixelStride;
            const uint8_t* pixel = row + colOffset;
            gray[static_cast<size_t>(y) * w + x] =
                static_cast<uint8_t>((77 * pixel[0] + 150 * pixel[1] +
                                      29 * pixel[2]) >> 8);
        }
    }

    out.width = w;
    out.height = h;
    out.pixels = std::move(gray);
    return true;
}

} // namespace pico_qr

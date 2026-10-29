// SPDX-License-Identifier: Apache-2.0
// Host-only tests: no Android NDK or physical headset required.
#include "../pico_qr_luma.h"

#include <cassert>
#include <cstdint>
#include <vector>

namespace {
uint8_t expectedGray(uint8_t r, uint8_t g, uint8_t b) {
    return static_cast<uint8_t>((77 * r + 150 * g + 29 * b) >> 8);
}

void fillImage(std::vector<uint8_t>& data, uint32_t width, uint32_t height,
               uint32_t stride, uint32_t pixelStride) {
    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            const size_t pos = static_cast<size_t>(y) * stride +
                               static_cast<size_t>(x) * pixelStride;
            data[pos] = static_cast<uint8_t>(x % 256);
            data[pos + 1] = static_cast<uint8_t>(y % 256);
            data[pos + 2] = 51;
            data[pos + 3] = 255;
        }
    }
}
}

int main() {
    constexpr uint32_t width = 512;
    constexpr uint32_t height = 512;
    constexpr uint32_t padding = 16;
    const uint32_t stride = width * 4 + padding;
    std::vector<uint8_t> pixels(static_cast<size_t>(stride) * height, 0);
    fillImage(pixels, width, height, stride, 4);
    pico_qr::RgbaFrame src{pixels.data(), width, height, stride, 4, 4, pixels.size()};
    assert(pico_qr::validRgbaFrame(src));

    pico_qr::GrayFrame full;
    assert(pico_qr::toGray(src, false, full));
    assert(full.width == 512 && full.height == 512);
    assert(full.pixels.size() == 512u * 512u);
    assert(full.pixels[0] == expectedGray(0, 0, 51));
    assert(full.pixels[static_cast<size_t>(200) * 512 + 100] ==
           expectedGray(100, 200, 51));

    pico_qr::GrayFrame crop;
    assert(pico_qr::toGray(src, true, crop));
    assert(crop.width == 256 && crop.height == 256);
    assert(crop.pixels[0] == expectedGray(128, 128, 51));
    assert(crop.pixels[static_cast<size_t>(60) * 256 + 30] ==
           expectedGray(158, 188, 51));

    // Valid non-packed RGBA bytes, with room between pixels.
    const uint32_t paddedStride = width * 8 + 16;
    std::vector<uint8_t> spaced(static_cast<size_t>(paddedStride) * height, 0);
    fillImage(spaced, width, height, paddedStride, 8);
    src = {spaced.data(), width, height, paddedStride, 8, 4, spaced.size()};
    assert(pico_qr::toGray(src, true, crop));
    assert(crop.pixels[0] == expectedGray(128, 128, 51));

    // Reject missing bytes in the final row without touching the buffer.
    src.bufferSize = static_cast<size_t>(height - 1) * paddedStride +
                     static_cast<size_t>(width - 1) * 8 + 3;
    assert(!pico_qr::validRgbaFrame(src));
    assert(!pico_qr::toGray(src, false, full));
    src.bufferSize = spaced.size();

    // Last packed pixel ends at (width - 1) * 8 + 4 bytes.
    src.stride = (width - 1) * 8 + 3;
    assert(!pico_qr::validRgbaFrame(src));
    src.stride = paddedStride;

    src.pixelStride = 3;
    assert(!pico_qr::validRgbaFrame(src));
    src.pixelStride = 8;

    src.bytesPerPixel = 3;
    assert(!pico_qr::validRgbaFrame(src));
    src.bytesPerPixel = 4;

    src.width = 8193;
    assert(!pico_qr::validRgbaFrame(src));
    src.width = width;
    src.data = nullptr;
    assert(!pico_qr::validRgbaFrame(src));

    // 2048px full view is sampled at 2x; crop retains more detail.
    constexpr uint32_t bigWidth = 2048;
    constexpr uint32_t bigHeight = 1024;
    std::vector<uint8_t> big(static_cast<size_t>(bigWidth) * bigHeight * 4);
    fillImage(big, bigWidth, bigHeight, bigWidth * 4, 4);
    src = {big.data(), bigWidth, bigHeight, bigWidth * 4, 4, 4, big.size()};
    assert(pico_qr::toGray(src, false, full));
    assert(full.width == 1024 && full.height == 512);
    assert(full.pixels[static_cast<size_t>(100) * 1024 + 100] ==
           expectedGray(200, 200, 51));
    assert(pico_qr::toGray(src, true, crop));
    assert(crop.width == 1024 && crop.height == 512);
    assert(crop.pixels[0] == expectedGray(0, 0, 51)); // x=512, y=256 wrap
    return 0;
}

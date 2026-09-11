#include <jni.h>
#include <android/log.h>
#include <string>
#include <vector>
#include <memory>
#include <cmath>
#include <algorithm>

// Tencent NCNN Framework
#include "net.h"
#include "gpu.h"

#define LOG_TAG "ShaderlyRealESRGAN"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

class RealESRGANAnimeEngine {
public:
    ncnn::Net net;
    ncnn::VulkanDevice* vkdev = nullptr;
    int targetScale = 2; // Output requested by user (2 or 4)
    int modelScale = 4;  // Base model scale (Anime 6B is 4x)
    int tileSize = 200;  // Safe tile dimension for mobile Adreno/Mali
    int padding = 12;    // Padded boundaries to prevent seam artifacts
    bool isLoaded = false;

    ~RealESRGANAnimeEngine() {
        cleanup();
    }

    void cleanup() {
        net.clear();
        if (vkdev) {
            ncnn::destroy_gpu_instance();
            vkdev = nullptr;
        }
        isLoaded = false;
    }

    bool init(const std::string& paramPath, const std::string& binPath, int scaleFactor, int gpuId = 0) {
        cleanup();
        targetScale = scaleFactor;

        ncnn::create_gpu_instance();
        int gpuCount = ncnn::get_gpu_count();
        if (gpuCount <= 0) {
            LOGE("No Vulkan capable GPU found on this Android device!");
            return false;
        }

        vkdev = ncnn::get_gpu_device(gpuId >= gpuCount ? 0 : gpuId);

        // High-performance FP16 Vulkan compute
        net.opt.use_vulkan_compute = true;
        net.opt.use_fp16_packed = true;
        net.opt.use_fp16_storage = true;
        net.opt.use_fp16_arithmetic = true;
        net.opt.use_int8_storage = true;
        net.opt.use_packing_layout = true;
        net.set_vulkan_device(vkdev);

        if (net.load_param(paramPath.c_str()) != 0) {
            LOGE("Failed to load Real-ESRGAN .param: %s", paramPath.c_str());
            return false;
        }

        if (net.load_model(binPath.c_str()) != 0) {
            LOGE("Failed to load Real-ESRGAN .bin: %s", binPath.c_str());
            return false;
        }

        isLoaded = true;
        LOGI("Real-ESRGAN Anime 6B Initialized on GPU: %s (Target Scale: %dx)", vkdev->info.device_name(), targetScale);
        return true;
    }

    bool process(const unsigned char* inRgba, int w, int h, unsigned char* outRgba) {
        if (!isLoaded) return false;

        // 1. Convert RGBA to RGB ncnn Mat (Anime 6B operates in RGB 0-1)
        ncnn::Mat inimage = ncnn::Mat::from_pixels(inRgba, ncnn::Mat::PIXEL_RGBA2RGB, w, h);
        ncnn::Mat outimage(w * modelScale, h * modelScale, (size_t)3u, 3);

        const float norm_vals[3] = { 1 / 255.0f, 1 / 255.0f, 1 / 255.0f };
        inimage.substract_mean_normalize(0, norm_vals);

        int xtiles = (w + tileSize - 1) / tileSize;
        int ytiles = (h + tileSize - 1) / tileSize;

        #pragma omp parallel for collapse(2)
        for (int yi = 0; yi < ytiles; yi++) {
            for (int xi = 0; xi < xtiles; xi++) {
                int tile_x = xi * tileSize;
                int tile_y = yi * tileSize;
                int tile_w = std::min(tileSize, w - tile_x);
                int tile_h = std::min(tileSize, h - tile_y);

                int pad_l = std::min(padding, tile_x);
                int pad_t = std::min(padding, tile_y);
                int pad_r = std::min(padding, w - (tile_x + tile_w));
                int pad_b = std::min(padding, h - (tile_y + tile_h));

                ncnn::Mat in_tile(tile_w + pad_l + pad_r, tile_h + pad_t + pad_b, 3);
                
                // Copy padded tile pixels
                for (int c = 0; c < 3; c++) {
                    const float* ptr = inimage.channel(c);
                    float* tile_ptr = in_tile.channel(c);
                    for (int y = 0; y < in_tile.h; y++) {
                        int src_y = std::max(0, std::min(h - 1, tile_y - pad_t + y));
                        for (int x = 0; x < in_tile.w; x++) {
                            int src_x = std::max(0, std::min(w - 1, tile_x - pad_l + x));
                            tile_ptr[y * in_tile.w + x] = ptr[src_y * w + src_x];
                        }
                    }
                }

                // Run inference on Vulkan GPU
                ncnn::Extractor ex = net.create_extractor();
                ex.set_vulkan_compute(true);
                ex.input("data", in_tile);

                ncnn::Mat out_tile;
                ex.extract("output", out_tile);

                int out_tile_w = tile_w * modelScale;
                int out_tile_h = tile_h * modelScale;
                int out_pad_l = pad_l * modelScale;
                int out_pad_t = pad_t * modelScale;

                // Stitch back into composite canvas
                for (int c = 0; c < 3; c++) {
                    float* out_ptr = outimage.channel(c);
                    const float* tile_out_ptr = out_tile.channel(c);
                    for (int y = 0; y < out_tile_h; y++) {
                        int dest_y = tile_y * modelScale + y;
                        for (int x = 0; x < out_tile_w; x++) {
                            int dest_x = tile_x * modelScale + x;
                            out_ptr[dest_y * (w * modelScale) + dest_x] = tile_out_ptr[(out_pad_t + y) * out_tile.w + (out_pad_l + x)];
                        }
                    }
                }
            }
        }

        const float mean_vals[3] = { -255.0f, -255.0f, -255.0f };
        const float norm_vals_inv[3] = { -1.0f, -1.0f, -1.0f };
        outimage.substract_mean_normalize(mean_vals, norm_vals_inv);

        // Integer-Interval Downsampling for 2X to maintain razor-sharp line art
        if (targetScale == 2) {
            int outW = w * 2;
            int outH = h * 2;
            std::vector<unsigned char> tempRgb(w * modelScale * h * modelScale * 3);
            outimage.to_pixels(tempRgb.data(), ncnn::Mat::PIXEL_RGB);

            #pragma omp parallel for collapse(2)
            for (int y = 0; y < outH; y++) {
                for (int x = 0; x < outW; x++) {
                    int srcX = x * 2; // Exact integer step (nearest neighbor)
                    int srcY = y * 2;
                    int srcIdx = (srcY * (w * modelScale) + srcX) * 3;
                    int dstIdx = (y * outW + x) * 4;

                    outRgba[dstIdx + 0] = tempRgb[srcIdx + 0];
                    outRgba[dstIdx + 1] = tempRgb[srcIdx + 1];
                    outRgba[dstIdx + 2] = tempRgb[srcIdx + 2];
                    outRgba[dstIdx + 3] = 255;
                }
            }
        } else {
            // Full 4X resolution
            outimage.to_pixels(outRgba, ncnn::Mat::PIXEL_RGB2RGBA);
        }

        return true;
    }
};

static RealESRGANAnimeEngine gAnimeEngine;

} // namespace

extern "C" {

// Direct Dart FFI Functions
int32_t init_realesrgan(const char* paramPath, const char* binPath, int32_t scaleFactor) {
    if (!paramPath || !binPath) return -1;
    bool res = gAnimeEngine.init(std::string(paramPath), std::string(binPath), scaleFactor);
    return res ? 0 : -1;
}

int32_t upscale_frame(const uint8_t* inRgba, int32_t inW, int32_t inH, uint8_t* outRgba) {
    if (!gAnimeEngine.isLoaded || !inRgba || !outRgba) return -1;
    bool ok = gAnimeEngine.process(inRgba, inW, inH, outRgba);
    return ok ? 0 : -1;
}

void destroy_realesrgan() {
    gAnimeEngine.cleanup();
}

// Android JNI Compatibility Bindings
JNIEXPORT jboolean JNICALL
Java_com_example_aereality_VulkanBridge_initRealEsrgan(JNIEnv* env, jobject thiz,
                                                      jstring jParamPath,
                                                      jstring jBinPath,
                                                      jint scaleFactor) {
    const char* paramStr = env->GetStringUTFChars(jParamPath, nullptr);
    const char* binStr = env->GetStringUTFChars(jBinPath, nullptr);

    bool res = gAnimeEngine.init(paramStr, binStr, scaleFactor);

    env->ReleaseStringUTFChars(jParamPath, paramStr);
    env->ReleaseStringUTFChars(jBinPath, binStr);
    return res ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_aereality_VulkanBridge_upscaleFrameRealEsrgan(JNIEnv* env, jobject thiz,
                                                              jbyteArray inBytes,
                                                              jint width,
                                                              jint height) {
    if (!gAnimeEngine.isLoaded) return nullptr;

    jbyte* inPtr = env->GetByteArrayElements(inBytes, nullptr);

    int outW = width * gAnimeEngine.targetScale;
    int outH = height * gAnimeEngine.targetScale;
    size_t outPixelBytes = outW * outH * 4;

    std::vector<unsigned char> outBuffer(outPixelBytes);

    bool ok = gAnimeEngine.process(reinterpret_cast<const unsigned char*>(inPtr), width, height, outBuffer.data());
    env->ReleaseByteArrayElements(inBytes, inPtr, JNI_ABORT);

    if (!ok) return nullptr;

    jbyteArray outArray = env->NewByteArray(outPixelBytes);
    env->SetByteArrayRegion(outArray, 0, outPixelBytes, reinterpret_cast<const jbyte*>(outBuffer.data()));
    return outArray;
}

JNIEXPORT void JNICALL
Java_com_example_aereality_VulkanBridge_destroyRealEsrgan(JNIEnv* env, jobject thiz) {
    gAnimeEngine.cleanup();
}

} // extern "C"

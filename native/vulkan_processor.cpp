#include <jni.h>
#include <android/log.h>
#include <vulkan/vulkan.h>
#include <vector>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <memory>
#include <mutex>
#include <functional>
#include <chrono>
#include <thread>
#include <atomic>
#include <string>
#include <cstdint>
#include <cstdlib>
#include <dirent.h>
#include <unistd.h>

#define LOG_TAG "ShaderlyVulkan"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// Uniform buffer size in floats: 4096 (header, layers, gradient maps, fx, curves, text) + 10 x 64 VFX + 10 x 64 Sapphire (batch 6)
// + (batch 9) Motion S block motionS[1024] at floats 5376..6399, timeSlice[1024] at 6400..7423 (Time Slice, batch 12: renamed from reserved2, still unread), 7424..8191 free headroom.
// Must match Vfx.uboFloats (vfx_slots.dart) and the UniformBlock in aereality_core.comp.
// findBatch6Passes() returns early when fewer than kUboFloats floats are sent, so every caller must send the full buffer.
constexpr size_t kUboFloats = 8192;

struct ComputePushConstants {
    int32_t passIndex;
    int32_t passWidth;
    int32_t passHeight;
    float passRadius;
    int32_t bandY;
    int32_t srcW;   // exact parent bloom-level size for downsample passes (0 = unused); full-res size for pass 10
    int32_t srcH;
    int32_t flareLayer;   // layer whose flare was pre-computed at half resolution by pass 10 (-1 = evaluate flares inline)
};

struct VulkanContext {
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue computeQueue = VK_NULL_HANDLE;
    uint32_t computeQueueFamilyIndex = 0;

    VkShaderModule shaderModule = VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptorSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkPipeline computePipeline = VK_NULL_HANDLE;
    VkPipelineCache pipelineCache = VK_NULL_HANDLE;   // batch 17B: persisted to <cache_dir>/shader_cache.bin
    VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    VkDescriptorSet descriptorSet = VK_NULL_HANDLE;

    VkCommandPool commandPool = VK_NULL_HANDLE;
    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    VkFence computeFence = VK_NULL_HANDLE;

    // Hardware Samplers
    VkSampler linearSampler = VK_NULL_HANDLE;
    VkSampler lutSampler = VK_NULL_HANDLE;

    // True 3D Volumetric LUT Texture
    VkImage lutImage = VK_NULL_HANDLE;
    VkDeviceMemory lutMemory = VK_NULL_HANDLE;
    VkImageView lutImageView = VK_NULL_HANDLE;

    // Storage Buffers for Image Data, UBO & Composite
    VkBuffer inBuffer = VK_NULL_HANDLE;
    VkDeviceMemory inMemory = VK_NULL_HANDLE;
    VkBuffer outBuffer = VK_NULL_HANDLE;
    VkDeviceMemory outMemory = VK_NULL_HANDLE;
    VkBuffer uboBuffer = VK_NULL_HANDLE;
    VkDeviceMemory uboMemory = VK_NULL_HANDLE;
    VkBuffer lutStagingBuffer = VK_NULL_HANDLE;
    VkDeviceMemory lutStagingMemory = VK_NULL_HANDLE;

    // Bloom Pyramid Buffers (fp16 RGBA = 8 bytes per pixel)
    VkBuffer bloomL0Buffer = VK_NULL_HANDLE;
    VkDeviceMemory bloomL0Memory = VK_NULL_HANDLE;
    VkBuffer bloomL1Buffer = VK_NULL_HANDLE;
    VkDeviceMemory bloomL1Memory = VK_NULL_HANDLE;
    VkBuffer bloomL2Buffer = VK_NULL_HANDLE;
    VkDeviceMemory bloomL2Memory = VK_NULL_HANDLE;
    // Long-tail levels for Deep Glow (1/16 and 1/32 res)
    VkBuffer bloomL3Buffer = VK_NULL_HANDLE;
    VkDeviceMemory bloomL3Memory = VK_NULL_HANDLE;
    VkBuffer bloomL4Buffer = VK_NULL_HANDLE;
    VkDeviceMemory bloomL4Memory = VK_NULL_HANDLE;

    // Half-resolution flare beam (fp16 RGBA = 8 bytes per half-res texel), written by pass 10, read by pass 6
    VkBuffer flareHalfBuffer = VK_NULL_HANDLE;
    VkDeviceMemory flareHalfMemory = VK_NULL_HANDLE;

    // Intermediate Linear Composite (fp16 RGBA = 8 bytes per pixel)
    VkBuffer tempCompositeBuffer = VK_NULL_HANDLE;
    VkDeviceMemory tempCompositeMemory = VK_NULL_HANDLE;

    // Batch 12 step B: finished display-referred image, FULL float32 RGBA (16 bytes per pixel, lossless). Binding 13.
    // Written by pass 6, read by pass 23 (dither + quantise into outBuffer). Same lifetime as tempCompositeBuffer.
    VkBuffer displayBuffer = VK_NULL_HANDLE;
    VkDeviceMemory displayMemory = VK_NULL_HANDLE;
    VkDeviceSize displayBytes = 0;   // step C1: current size of the display buffer (grows when the Time Slice ring is needed)

    // Motion S (batch 9): bindings 11 (packed 8-bit frames, host visible) and 12 (flow planes). 4 KB placeholders until process_motion() needs more,
    // so the descriptor set is always fully valid for the grade pipeline too.
    VkBuffer motionFramesBuffer = VK_NULL_HANDLE;
    VkDeviceMemory motionFramesMemory = VK_NULL_HANDLE;
    VkDeviceSize motionFramesBytes = 0;
    VkBuffer motionFlowBuffer = VK_NULL_HANDLE;
    VkDeviceMemory motionFlowMemory = VK_NULL_HANDLE;
    VkDeviceSize motionFlowBytes = 0;

    size_t allocatedPixelCapacity = 0;
    bool isInitialized = false;
    bool lutUploaded = false;
    std::mutex pipelineMutex;
};

static VulkanContext gVk;

// Batch 12 step C1: Time Slice ring state (the ring itself lives in the tail of the display buffer, see ensureTimeSliceRing).
static int32_t gTsStoreSlot = -1;   // >= 0 while process_timeslice_ingest runs: pass 24 stores the finished frame there and the pipeline stops (no pass 23)
static bool gTsPacked = true;        // C2: ring stored as 2 words per pixel (15-bit unorm, see the shader) = 8 bytes per pixel per slot instead of 16
static int32_t gPass23Count = 0;     // C2 debug: number of COMPLETE pass 23 runs (one per graded / emitted frame); read through get_pass23_count()
constexpr int kTsStatePackedFlag = 7045;   // timeSlice[645]
static int32_t gTsRingW = 0, gTsRingH = 0, gTsRingSlots = 0;   // frame size / slot count the ring was filled for (0 = no valid ring)

uint32_t findMemoryType(VkPhysicalDevice physicalDevice, uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);

    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }

    if (properties & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) {
        return findMemoryType(physicalDevice, typeFilter, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT);
    }

    LOGE("Failed to find suitable Vulkan memory type!");
    return 0;
}

void createBuffer(VkDevice device, VkPhysicalDevice physicalDevice, VkDeviceSize size,
                  VkBufferUsageFlags usage, VkMemoryPropertyFlags properties,
                  VkBuffer& buffer, VkDeviceMemory& bufferMemory) {
    VkBufferCreateInfo bufferInfo{};
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = size;
    bufferInfo.usage = usage;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    if (vkCreateBuffer(device, &bufferInfo, nullptr, &buffer) != VK_SUCCESS) {
        LOGE("Failed to create buffer size: %llu", (unsigned long long)size);
        return;
    }

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(device, buffer, &memRequirements);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = findMemoryType(physicalDevice, memRequirements.memoryTypeBits, properties);

    if (vkAllocateMemory(device, &allocInfo, nullptr, &bufferMemory) != VK_SUCCESS) {
        LOGE("Failed to allocate memory size: %llu", (unsigned long long)memRequirements.size);
        return;
    }

    vkBindBufferMemory(device, buffer, bufferMemory, 0);
}

void createHardwareSamplers() {
    VkSamplerCreateInfo samplerInfo{};
    samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    samplerInfo.magFilter = VK_FILTER_LINEAR;
    samplerInfo.minFilter = VK_FILTER_LINEAR;
    samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.mipLodBias = 0.0f;
    samplerInfo.anisotropyEnable = VK_FALSE;
    samplerInfo.compareEnable = VK_FALSE;
    samplerInfo.minLod = 0.0f;
    samplerInfo.maxLod = 1.0f;
    samplerInfo.borderColor = VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;
    samplerInfo.unnormalizedCoordinates = VK_FALSE;

    if (vkCreateSampler(gVk.device, &samplerInfo, nullptr, &gVk.linearSampler) != VK_SUCCESS) {
        LOGE("Failed to create Vulkan Linear Sampler.");
    }

    VkSamplerCreateInfo lutSamplerInfo{};
    lutSamplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    lutSamplerInfo.magFilter = VK_FILTER_LINEAR;
    lutSamplerInfo.minFilter = VK_FILTER_LINEAR;
    lutSamplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    lutSamplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    lutSamplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    lutSamplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    lutSamplerInfo.unnormalizedCoordinates = VK_FALSE;

    if (vkCreateSampler(gVk.device, &lutSamplerInfo, nullptr, &gVk.lutSampler) != VK_SUCCESS) {
        LOGE("Failed to create Vulkan 3D LUT Sampler.");
    }
}

void create3DLutImage() {
    if (gVk.lutImage != VK_NULL_HANDLE) return;

    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = VK_IMAGE_TYPE_3D;
    imageInfo.extent.width = 32;
    imageInfo.extent.height = 32;
    imageInfo.extent.depth = 32;
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.format = VK_FORMAT_R16G16B16A16_SFLOAT;   // linear filtering of RGBA32F is optional on mobile GPUs
    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    imageInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;

    if (vkCreateImage(gVk.device, &imageInfo, nullptr, &gVk.lutImage) != VK_SUCCESS) {
        LOGE("Failed to create 3D LUT Image.");
        return;
    }

    VkMemoryRequirements memReqs;
    vkGetImageMemoryRequirements(gVk.device, gVk.lutImage, &memReqs);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memReqs.size;
    allocInfo.memoryTypeIndex = findMemoryType(gVk.physicalDevice, memReqs.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    if (vkAllocateMemory(gVk.device, &allocInfo, nullptr, &gVk.lutMemory) != VK_SUCCESS) {
        LOGE("Failed to allocate 3D LUT Image Memory.");
        return;
    }

    vkBindImageMemory(gVk.device, gVk.lutImage, gVk.lutMemory, 0);

    VkImageViewCreateInfo viewInfo{};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = gVk.lutImage;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_3D;
    viewInfo.format = VK_FORMAT_R16G16B16A16_SFLOAT;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.baseMipLevel = 0;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.baseArrayLayer = 0;
    viewInfo.subresourceRange.layerCount = 1;

    if (vkCreateImageView(gVk.device, &viewInfo, nullptr, &gVk.lutImageView) != VK_SUCCESS) {
        LOGE("Failed to create 3D LUT Image View.");
    }
}

void cleanupBuffers() {
    if (gVk.device == VK_NULL_HANDLE) return;

    auto safeDestroy = [](VkBuffer& buf, VkDeviceMemory& mem) {
        if (buf != VK_NULL_HANDLE) {
            vkDestroyBuffer(gVk.device, buf, nullptr);
            buf = VK_NULL_HANDLE;
        }
        if (mem != VK_NULL_HANDLE) {
            vkFreeMemory(gVk.device, mem, nullptr);
            mem = VK_NULL_HANDLE;
        }
    };

    safeDestroy(gVk.inBuffer, gVk.inMemory);
    safeDestroy(gVk.outBuffer, gVk.outMemory);
    safeDestroy(gVk.uboBuffer, gVk.uboMemory);
    safeDestroy(gVk.lutStagingBuffer, gVk.lutStagingMemory);
    safeDestroy(gVk.bloomL0Buffer, gVk.bloomL0Memory);
    safeDestroy(gVk.bloomL1Buffer, gVk.bloomL1Memory);
    safeDestroy(gVk.bloomL2Buffer, gVk.bloomL2Memory);
    safeDestroy(gVk.bloomL3Buffer, gVk.bloomL3Memory);
    safeDestroy(gVk.bloomL4Buffer, gVk.bloomL4Memory);
    safeDestroy(gVk.flareHalfBuffer, gVk.flareHalfMemory);
    safeDestroy(gVk.tempCompositeBuffer, gVk.tempCompositeMemory);
    safeDestroy(gVk.displayBuffer, gVk.displayMemory);
    safeDestroy(gVk.motionFramesBuffer, gVk.motionFramesMemory);
    safeDestroy(gVk.motionFlowBuffer, gVk.motionFlowMemory);
    gVk.motionFramesBytes = 0;
    gVk.motionFlowBytes = 0;
    gVk.displayBytes = 0;
    gTsRingW = gTsRingH = gTsRingSlots = 0;   // the ring went with the display buffer

    gVk.allocatedPixelCapacity = 0;
}

// Motion S (batch 9): (re)points descriptors 11 / 12 at the current motion buffers.
void writeMotionDescriptors() {
    if (gVk.motionFramesBuffer == VK_NULL_HANDLE || gVk.motionFlowBuffer == VK_NULL_HANDLE) return;
    VkDescriptorBufferInfo infos[2] = {{gVk.motionFramesBuffer, 0, gVk.motionFramesBytes}, {gVk.motionFlowBuffer, 0, gVk.motionFlowBytes}};
    VkWriteDescriptorSet w[2]{};
    for (int k = 0; k < 2; ++k) {
        w[k].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        w[k].dstSet = gVk.descriptorSet;
        w[k].dstBinding = 11 + k;
        w[k].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        w[k].descriptorCount = 1;
        w[k].pBufferInfo = &infos[k];
    }
    vkUpdateDescriptorSets(gVk.device, 2, w, 0, nullptr);
}

// Grows the Motion S buffers (frames + flow) when needed. Every submit waits for its fence, so nothing is in flight here.
bool ensureMotionBuffers(VkDeviceSize framesBytes, VkDeviceSize flowBytes) {
    if (gVk.motionFramesBytes >= framesBytes && gVk.motionFlowBytes >= flowBytes &&
        gVk.motionFramesBuffer != VK_NULL_HANDLE && gVk.motionFlowBuffer != VK_NULL_HANDLE) return true;
    auto destroy = [](VkBuffer& buf, VkDeviceMemory& mem) {
        if (buf != VK_NULL_HANDLE) { vkDestroyBuffer(gVk.device, buf, nullptr); buf = VK_NULL_HANDLE; }
        if (mem != VK_NULL_HANDLE) { vkFreeMemory(gVk.device, mem, nullptr); mem = VK_NULL_HANDLE; }
    };
    const VkDeviceSize wantFrames = std::max<VkDeviceSize>(framesBytes, gVk.motionFramesBytes);
    const VkDeviceSize wantFlow = std::max<VkDeviceSize>(flowBytes, gVk.motionFlowBytes);
    destroy(gVk.motionFramesBuffer, gVk.motionFramesMemory);
    destroy(gVk.motionFlowBuffer, gVk.motionFlowMemory);
    createBuffer(gVk.device, gVk.physicalDevice, wantFrames, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.motionFramesBuffer, gVk.motionFramesMemory);
    createBuffer(gVk.device, gVk.physicalDevice, wantFlow, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, gVk.motionFlowBuffer, gVk.motionFlowMemory);
    gVk.motionFramesBytes = wantFrames;
    gVk.motionFlowBytes = wantFlow;
    if (gVk.motionFramesBuffer == VK_NULL_HANDLE || gVk.motionFlowBuffer == VK_NULL_HANDLE ||
        gVk.motionFramesMemory == VK_NULL_HANDLE || gVk.motionFlowMemory == VK_NULL_HANDLE) {
        LOGE("Motion S buffer allocation failed (%llu + %llu bytes)", (unsigned long long)wantFrames, (unsigned long long)wantFlow);
        destroy(gVk.motionFramesBuffer, gVk.motionFramesMemory);
        destroy(gVk.motionFlowBuffer, gVk.motionFlowMemory);
        // keep the descriptor set valid for the grade pipeline: tiny placeholders again
        createBuffer(gVk.device, gVk.physicalDevice, 4096, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, gVk.motionFramesBuffer, gVk.motionFramesMemory);
        createBuffer(gVk.device, gVk.physicalDevice, 4096, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                     VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, gVk.motionFlowBuffer, gVk.motionFlowMemory);
        gVk.motionFramesBytes = 4096;
        gVk.motionFlowBytes = 4096;
        writeMotionDescriptors();
        return false;
    }
    writeMotionDescriptors();
    return true;
}

bool ensureBuffersCapacity(size_t requiredPixels) {
    if (gVk.allocatedPixelCapacity >= requiredPixels && gVk.inBuffer != VK_NULL_HANDLE) {
        return true;
    }

    cleanupBuffers();

    VkDeviceSize pixelBufferSize = requiredPixels * 8; // 64bpp for up to 16-bit
    // kUboFloats capacity: 32 header + 10 x 192 layer floats = 1952, then 10 x 48 gradient-map floats (1952..2431), fx / curves / text up to 4095,
    // then VFX (4096..4735) and Sapphire (4736..5375) blocks (batch 6), Motion S 5376..6399, Time Slice 6400..7423, 7424..8191 headroom (batch 9)
    VkDeviceSize uboBufferSize = kUboFloats * sizeof(float);
    VkDeviceSize lutStagingSize = 32 * 32 * 32 * 4 * sizeof(float);

    // Bloom pyramid buffers stored as fp16 RGBA (2 uint32s = 8 bytes per texel)
    VkDeviceSize l0Size = ((requiredPixels / 4) + 64) * 8;
    VkDeviceSize l1Size = ((requiredPixels / 16) + 64) * 8;
    VkDeviceSize l2Size = ((requiredPixels / 64) + 64) * 8;
    VkDeviceSize l3Size = ((requiredPixels / 256) + 64) * 8;
    VkDeviceSize l4Size = ((requiredPixels / 1024) + 64) * 8;

    createBuffer(gVk.device, gVk.physicalDevice, pixelBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.inBuffer, gVk.inMemory);

    createBuffer(gVk.device, gVk.physicalDevice, pixelBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.outBuffer, gVk.outMemory);

    createBuffer(gVk.device, gVk.physicalDevice, uboBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.uboBuffer, gVk.uboMemory);

    createBuffer(gVk.device, gVk.physicalDevice, lutStagingSize,
                 VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.lutStagingBuffer, gVk.lutStagingMemory);

    createBuffer(gVk.device, gVk.physicalDevice, l0Size,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.bloomL0Buffer, gVk.bloomL0Memory);

    createBuffer(gVk.device, gVk.physicalDevice, l1Size,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.bloomL1Buffer, gVk.bloomL1Memory);

    createBuffer(gVk.device, gVk.physicalDevice, l2Size,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.bloomL2Buffer, gVk.bloomL2Memory);

    createBuffer(gVk.device, gVk.physicalDevice, l3Size,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.bloomL3Buffer, gVk.bloomL3Memory);

    createBuffer(gVk.device, gVk.physicalDevice, l4Size,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.bloomL4Buffer, gVk.bloomL4Memory);

    createBuffer(gVk.device, gVk.physicalDevice, pixelBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.tempCompositeBuffer, gVk.tempCompositeMemory);

    // Batch 12 step B: float32 RGBA display image (16 bytes per pixel). Always sized for the largest frame, like tempComposite.
    VkDeviceSize displaySize = requiredPixels * 16;
    createBuffer(gVk.device, gVk.physicalDevice, displaySize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.displayBuffer, gVk.displayMemory);
    gVk.displayBytes = displaySize;

    createBuffer(gVk.device, gVk.physicalDevice, l0Size,   // same size as bloom level 0 = half resolution
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.flareHalfBuffer, gVk.flareHalfMemory);

    // Motion S placeholders (bindings 11 / 12): replaced by ensureMotionBuffers() when process_motion() needs real sizes
    createBuffer(gVk.device, gVk.physicalDevice, 4096, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.motionFramesBuffer, gVk.motionFramesMemory);
    gVk.motionFramesBytes = 4096;
    createBuffer(gVk.device, gVk.physicalDevice, 4096, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, gVk.motionFlowBuffer, gVk.motionFlowMemory);
    gVk.motionFlowBytes = 4096;

    create3DLutImage();

    VkDescriptorBufferInfo inBufferInfo{gVk.inBuffer, 0, pixelBufferSize};
    VkDescriptorBufferInfo outBufferInfo{gVk.outBuffer, 0, pixelBufferSize};
    VkDescriptorBufferInfo uboBufferInfo{gVk.uboBuffer, 0, uboBufferSize};
    VkDescriptorImageInfo lutImageInfo{gVk.lutSampler, gVk.lutImageView, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkDescriptorBufferInfo l0BufferInfo{gVk.bloomL0Buffer, 0, l0Size};
    VkDescriptorBufferInfo l1BufferInfo{gVk.bloomL1Buffer, 0, l1Size};
    VkDescriptorBufferInfo l2BufferInfo{gVk.bloomL2Buffer, 0, l2Size};
    VkDescriptorBufferInfo tempCompInfo{gVk.tempCompositeBuffer, 0, pixelBufferSize};
    VkDescriptorBufferInfo l3BufferInfo{gVk.bloomL3Buffer, 0, l3Size};
    VkDescriptorBufferInfo l4BufferInfo{gVk.bloomL4Buffer, 0, l4Size};
    VkDescriptorBufferInfo flareBufferInfo{gVk.flareHalfBuffer, 0, l0Size};
    VkDescriptorBufferInfo displayBufferInfo{gVk.displayBuffer, 0, displaySize};

    VkWriteDescriptorSet descriptorWrites[12]{};

    descriptorWrites[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[0].dstSet = gVk.descriptorSet;
    descriptorWrites[0].dstBinding = 0;
    descriptorWrites[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[0].descriptorCount = 1;
    descriptorWrites[0].pBufferInfo = &inBufferInfo;

    descriptorWrites[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[1].dstSet = gVk.descriptorSet;
    descriptorWrites[1].dstBinding = 1;
    descriptorWrites[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[1].descriptorCount = 1;
    descriptorWrites[1].pBufferInfo = &outBufferInfo;

    descriptorWrites[2].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[2].dstSet = gVk.descriptorSet;
    descriptorWrites[2].dstBinding = 2;
    descriptorWrites[2].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[2].descriptorCount = 1;
    descriptorWrites[2].pBufferInfo = &uboBufferInfo;

    descriptorWrites[3].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[3].dstSet = gVk.descriptorSet;
    descriptorWrites[3].dstBinding = 3;
    descriptorWrites[3].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    descriptorWrites[3].descriptorCount = 1;
    descriptorWrites[3].pImageInfo = &lutImageInfo;

    descriptorWrites[4].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[4].dstSet = gVk.descriptorSet;
    descriptorWrites[4].dstBinding = 4;
    descriptorWrites[4].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[4].descriptorCount = 1;
    descriptorWrites[4].pBufferInfo = &l0BufferInfo;

    descriptorWrites[5].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[5].dstSet = gVk.descriptorSet;
    descriptorWrites[5].dstBinding = 5;
    descriptorWrites[5].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[5].descriptorCount = 1;
    descriptorWrites[5].pBufferInfo = &l1BufferInfo;

    descriptorWrites[6].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[6].dstSet = gVk.descriptorSet;
    descriptorWrites[6].dstBinding = 6;
    descriptorWrites[6].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[6].descriptorCount = 1;
    descriptorWrites[6].pBufferInfo = &l2BufferInfo;

    descriptorWrites[7].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[7].dstSet = gVk.descriptorSet;
    descriptorWrites[7].dstBinding = 7;
    descriptorWrites[7].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[7].descriptorCount = 1;
    descriptorWrites[7].pBufferInfo = &tempCompInfo;

    descriptorWrites[8].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[8].dstSet = gVk.descriptorSet;
    descriptorWrites[8].dstBinding = 8;
    descriptorWrites[8].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[8].descriptorCount = 1;
    descriptorWrites[8].pBufferInfo = &l3BufferInfo;

    descriptorWrites[9].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[9].dstSet = gVk.descriptorSet;
    descriptorWrites[9].dstBinding = 9;
    descriptorWrites[9].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[9].descriptorCount = 1;
    descriptorWrites[9].pBufferInfo = &l4BufferInfo;

    descriptorWrites[10].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[10].dstSet = gVk.descriptorSet;
    descriptorWrites[10].dstBinding = 10;
    descriptorWrites[10].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[10].descriptorCount = 1;
    descriptorWrites[10].pBufferInfo = &flareBufferInfo;

    // Batch 12 step B: binding 13 = float32 display image (pass 6 -> pass 23)
    descriptorWrites[11].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[11].dstSet = gVk.descriptorSet;
    descriptorWrites[11].dstBinding = 13;
    descriptorWrites[11].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[11].descriptorCount = 1;
    descriptorWrites[11].pBufferInfo = &displayBufferInfo;

    vkUpdateDescriptorSets(gVk.device, 12, descriptorWrites, 0, nullptr);
    writeMotionDescriptors();

    // createBuffer() only logs when an allocation fails and leaves the handle null. Mapping a null buffer later crashes or
    // gives a black frame, so report the failure here and let the caller use the CPU path instead.
    if (gVk.inBuffer == VK_NULL_HANDLE || gVk.outBuffer == VK_NULL_HANDLE || gVk.uboBuffer == VK_NULL_HANDLE ||
        gVk.tempCompositeBuffer == VK_NULL_HANDLE || gVk.displayBuffer == VK_NULL_HANDLE || gVk.flareHalfBuffer == VK_NULL_HANDLE ||
        gVk.bloomL0Buffer == VK_NULL_HANDLE || gVk.bloomL1Buffer == VK_NULL_HANDLE || gVk.bloomL2Buffer == VK_NULL_HANDLE ||
        gVk.bloomL3Buffer == VK_NULL_HANDLE || gVk.bloomL4Buffer == VK_NULL_HANDLE ||
        gVk.inMemory == VK_NULL_HANDLE || gVk.outMemory == VK_NULL_HANDLE || gVk.uboMemory == VK_NULL_HANDLE) {
        LOGE("Buffer allocation failed for %zu pixels (out of memory?) - releasing and using the fallback path.", requiredPixels);
        cleanupBuffers();
        return false;
    }

    gVk.allocatedPixelCapacity = requiredPixels;
    LOGI("Configured Vulkan Samplers, 3D LUT Image, and Buffers for %zu pixels (UBO %zu floats).", requiredPixels, (size_t)kUboFloats);
    return true;
}

// Batch 12 step C1: makes the display buffer (binding 13) long enough for slot 0 + ringSlots frames (16 bytes per pixel each).
// C3: the host now asks for ringSlots = 23 (TimeSlice.ringSlots, was 9). Packed ring = 16 + 23 * 8 = 200 bytes per pixel in the formula below, i.e. exactly
// (P + 23 * ceil(P/2)) * 16 bytes: preview 960x544 ~ 104 MB, 1080p ~ 415 MB, 2560x1440 ~ 737 MB (decimal MB; was ~ 46 / 182 / 324 MB). The formula is unchanged; only the
// slot count the host passes changed. Nothing here is allocated unless a Time Slice entry point runs (Time Slice off = one frame, as in step B).
// Only called by the Time Slice entry points, so with Time Slice off the buffer stays one frame long, exactly as in step B.
// Growing destroys the old contents (the ring); every submit waits for its fence, so nothing is in flight here.
static void writeDisplayDescriptor() {
    VkDescriptorBufferInfo info{gVk.displayBuffer, 0, gVk.displayBytes};
    VkWriteDescriptorSet w{};
    w.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w.dstSet = gVk.descriptorSet;
    w.dstBinding = 13;
    w.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    w.descriptorCount = 1;
    w.pBufferInfo = &info;
    vkUpdateDescriptorSets(gVk.device, 1, &w, 0, nullptr);
}

static bool ensureTimeSliceRing(size_t pixelCount, int32_t ringSlots) {
    // C2: packed ring = slot 0 (P vec4) + ringSlots * ceil(P / 2) vec4; float32 ring (C1) = (1 + ringSlots) * P vec4. 16 bytes per vec4.
    const VkDeviceSize need = gTsPacked
        ? ((VkDeviceSize)pixelCount + (VkDeviceSize)ringSlots * (VkDeviceSize)((pixelCount + 1) / 2)) * 16
        : (VkDeviceSize)pixelCount * 16 * (VkDeviceSize)(1 + ringSlots);
    if (gVk.displayBytes >= need && gVk.displayBuffer != VK_NULL_HANDLE) return true;
    {   // C3: the bigger ring must still fit one storage-buffer descriptor (spec: range <= maxStorageBufferRange); if it does not, refuse cleanly (host shows plain frames)
        VkPhysicalDeviceProperties props{};
        vkGetPhysicalDeviceProperties(gVk.physicalDevice, &props);
        if (need > (VkDeviceSize)props.limits.maxStorageBufferRange) {
            LOGE("Time Slice ring needs %llu bytes, device maxStorageBufferRange is %u - ring refused", (unsigned long long)need, (unsigned)props.limits.maxStorageBufferRange);
            return false;
        }
    }
    if (gVk.displayBuffer != VK_NULL_HANDLE) { vkDestroyBuffer(gVk.device, gVk.displayBuffer, nullptr); gVk.displayBuffer = VK_NULL_HANDLE; }
    if (gVk.displayMemory != VK_NULL_HANDLE) { vkFreeMemory(gVk.device, gVk.displayMemory, nullptr); gVk.displayMemory = VK_NULL_HANDLE; }
    gTsRingW = gTsRingH = gTsRingSlots = 0;
    createBuffer(gVk.device, gVk.physicalDevice, need, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, gVk.displayBuffer, gVk.displayMemory);
    if (gVk.displayBuffer != VK_NULL_HANDLE && gVk.displayMemory != VK_NULL_HANDLE) {
        gVk.displayBytes = need;
        writeDisplayDescriptor();
        LOGI("Time Slice ring allocated: %llu bytes (%d slots, %zu px)", (unsigned long long)need, (int)ringSlots, pixelCount);
        return true;
    }
    LOGE("Time Slice ring allocation failed (%llu bytes) - restoring the single-frame display buffer", (unsigned long long)need);
    if (gVk.displayBuffer != VK_NULL_HANDLE) { vkDestroyBuffer(gVk.device, gVk.displayBuffer, nullptr); gVk.displayBuffer = VK_NULL_HANDLE; }
    if (gVk.displayMemory != VK_NULL_HANDLE) { vkFreeMemory(gVk.device, gVk.displayMemory, nullptr); gVk.displayMemory = VK_NULL_HANDLE; }
    const VkDeviceSize base = (VkDeviceSize)gVk.allocatedPixelCapacity * 16;
    createBuffer(gVk.device, gVk.physicalDevice, base, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, gVk.displayBuffer, gVk.displayMemory);
    gVk.displayBytes = base;
    writeDisplayDescriptor();
    return false;
}

// C2: gives the ring memory back (display buffer = one frame again, exactly as in step B). Called by process_timeslice_release.
static void releaseTimeSliceRing() {
    gTsRingW = gTsRingH = gTsRingSlots = 0;
    const VkDeviceSize base = (VkDeviceSize)gVk.allocatedPixelCapacity * 16;
    if (gVk.displayBuffer == VK_NULL_HANDLE || base == 0 || gVk.displayBytes <= base) return;
    if (gVk.displayBuffer != VK_NULL_HANDLE) { vkDestroyBuffer(gVk.device, gVk.displayBuffer, nullptr); gVk.displayBuffer = VK_NULL_HANDLE; }
    if (gVk.displayMemory != VK_NULL_HANDLE) { vkFreeMemory(gVk.device, gVk.displayMemory, nullptr); gVk.displayMemory = VK_NULL_HANDLE; }
    createBuffer(gVk.device, gVk.physicalDevice, base, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, gVk.displayBuffer, gVk.displayMemory);
    gVk.displayBytes = base;
    writeDisplayDescriptor();
    LOGI("Time Slice ring released (%llu bytes)", (unsigned long long)base);
}

float cpuSrgbToLinear(float c) {
    return (c <= 0.04045f) ? (c / 12.92f) : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

float cpuLinearToSrgb(float c) {
    c = std::max(0.0f, std::min(1.0f, c));
    return (c <= 0.0031308f) ? (c * 12.92f) : (1.055f * std::pow(c, 1.0f / 2.4f) - 0.055f);
}

// 192-float stride CPU fallback loop
void executeCpuFallbackGrading(const uint32_t* src, uint32_t* dst, int w, int h, const float* ubo) {
    int layerCount = static_cast<int>(ubo[1]);
    if (layerCount <= 0) {
        std::memcpy(dst, src, w * h * sizeof(uint32_t));
        return;
    }

    #pragma omp parallel for collapse(2)
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int idx = y * w + x;
            uint32_t pixel = src[idx];

            float r = cpuSrgbToLinear((pixel & 0xFF) / 255.0f);
            float g = cpuSrgbToLinear(((pixel >> 8) & 0xFF) / 255.0f);
            float b = cpuSrgbToLinear(((pixel >> 16) & 0xFF) / 255.0f);
            float a = ((pixel >> 24) & 0xFF) / 255.0f;

            for (int l = 0; l < std::min(layerCount, 10); l++) {
                int off = 32 + (l * 192); // Strict 192-float stride (must match LayerData in the shader)
                if (ubo[off + 0] < 0.5f) continue;

                float opacity = ubo[off + 1];
                float brightness = ubo[off + 3];
                float saturation = ubo[off + 4];
                float contrast = ubo[off + 5];

                float lr = (r + brightness - 0.18f) * contrast + 0.18f;
                float lg = (g + brightness - 0.18f) * contrast + 0.18f;
                float lb = (b + brightness - 0.18f) * contrast + 0.18f;

                float luma = 0.2126f * lr + 0.7152f * lg + 0.0722f * lb;
                lr = luma + saturation * (lr - luma);
                lg = luma + saturation * (lg - luma);
                lb = luma + saturation * (lb - luma);

                r = r * (1.0f - opacity) + lr * opacity;
                g = g * (1.0f - opacity) + lg * opacity;
                b = b * (1.0f - opacity) + lb * opacity;
            }

            uint32_t ur = static_cast<uint32_t>(cpuLinearToSrgb(r) * 255.0f + 0.5f);
            uint32_t ug = static_cast<uint32_t>(cpuLinearToSrgb(g) * 255.0f + 0.5f);
            uint32_t ub = static_cast<uint32_t>(cpuLinearToSrgb(b) * 255.0f + 0.5f);
            uint32_t ua = static_cast<uint32_t>(a * 255.0f + 0.5f);

            dst[idx] = (ua << 24) | (ub << 16) | (ug << 8) | ur;
        }
    }
}

// float -> IEEE half (round to nearest even), used for the 3D LUT texture
static uint16_t floatToHalf(float f) {
    uint32_t x;
    std::memcpy(&x, &f, sizeof(x));
    uint32_t sign = (x >> 16) & 0x8000u;
    int32_t exp = (int32_t)((x >> 23) & 0xFFu) - 127 + 15;
    uint32_t mant = x & 0x7FFFFFu;
    if (((x >> 23) & 0xFFu) == 0xFFu) return (uint16_t)(sign | 0x7C00u | (mant ? 0x200u : 0u));
    if (exp >= 31) return (uint16_t)(sign | 0x7C00u);
    if (exp <= 0) {
        if (exp < -10) return (uint16_t)sign;
        mant |= 0x800000u;
        uint32_t shift = (uint32_t)(14 - exp);
        uint32_t half = mant >> shift;
        uint32_t rem = mant & ((1u << shift) - 1u);
        uint32_t mid = 1u << (shift - 1);
        if (rem > mid || (rem == mid && (half & 1u))) half++;
        return (uint16_t)(sign | half);
    }
    uint32_t half = (uint32_t)(exp << 10) | (mant >> 13);
    uint32_t rem = mant & 0x1FFFu;
    if (rem > 0x1000u || (rem == 0x1000u && (half & 1u))) half++;
    return (uint16_t)(sign | half);
}

static uint64_t gLutHash = 0;

void uploadLutTo3DTexture(const float* lutTable, int32_t lutCount) {
    if (lutTable == nullptr || lutCount <= 0 || gVk.lutImage == VK_NULL_HANDLE) return;

    // Skip the whole upload when this exact LUT is already in the texture.
    uint64_t newHash = 1469598103934665603ull;
    {
        const uint32_t* bits = reinterpret_cast<const uint32_t*>(lutTable);
        const int32_t n = std::min<int32_t>(lutCount, 32 * 32 * 32 * 3);
        for (int32_t i = 0; i < n; ++i) { newHash ^= bits[i]; newHash *= 1099511628211ull; }
        newHash ^= (uint64_t)n;
        if (gVk.lutUploaded && newHash == gLutHash) return;
    }

    size_t totalPoints = 32 * 32 * 32;
    std::vector<uint16_t> rgbaLut(totalPoints * 4, 0);

    for (size_t i = 0; i < totalPoints; i++) {
        if ((i * 3 + 2) < (size_t)lutCount) {
            rgbaLut[i * 4 + 0] = floatToHalf(lutTable[i * 3 + 0]);
            rgbaLut[i * 4 + 1] = floatToHalf(lutTable[i * 3 + 1]);
            rgbaLut[i * 4 + 2] = floatToHalf(lutTable[i * 3 + 2]);
            rgbaLut[i * 4 + 3] = floatToHalf(1.0f);
        }
    }

    size_t copyBytes = rgbaLut.size() * sizeof(uint16_t);
    void* mappedStaging = nullptr;
    vkMapMemory(gVk.device, gVk.lutStagingMemory, 0, copyBytes, 0, &mappedStaging);
    std::memcpy(mappedStaging, rgbaLut.data(), copyBytes);
    VkMappedMemoryRange range{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.lutStagingMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &range);
    vkUnmapMemory(gVk.device, gVk.lutStagingMemory);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    vkBeginCommandBuffer(gVk.commandBuffer, &beginInfo);

    VkImageMemoryBarrier barrierToDst{};
    barrierToDst.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrierToDst.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrierToDst.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrierToDst.image = gVk.lutImage;
    barrierToDst.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrierToDst.subresourceRange.levelCount = 1;
    barrierToDst.subresourceRange.layerCount = 1;
    barrierToDst.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

    vkCmdPipelineBarrier(gVk.commandBuffer,
                         VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                         VK_PIPELINE_STAGE_TRANSFER_BIT,
                         0, 0, nullptr, 0, nullptr, 1, &barrierToDst);

    VkBufferImageCopy copyRegion{};
    copyRegion.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copyRegion.imageSubresource.layerCount = 1;
    copyRegion.imageExtent = {32, 32, 32};

    vkCmdCopyBufferToImage(gVk.commandBuffer, gVk.lutStagingBuffer, gVk.lutImage,
                           VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copyRegion);

    VkImageMemoryBarrier barrierToRead{};
    barrierToRead.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrierToRead.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrierToRead.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrierToRead.image = gVk.lutImage;
    barrierToRead.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrierToRead.subresourceRange.levelCount = 1;
    barrierToRead.subresourceRange.layerCount = 1;
    barrierToRead.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrierToRead.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(gVk.commandBuffer,
                         VK_PIPELINE_STAGE_TRANSFER_BIT,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                         0, 0, nullptr, 0, nullptr, 1, &barrierToRead);

    vkEndCommandBuffer(gVk.commandBuffer);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &gVk.commandBuffer;

    vkResetFences(gVk.device, 1, &gVk.computeFence);
    vkQueueSubmit(gVk.computeQueue, 1, &submitInfo, gVk.computeFence);
    vkWaitForFences(gVk.device, 1, &gVk.computeFence, VK_TRUE, UINT64_MAX);

    gVk.lutUploaded = true;
    gLutHash = newHash;
    LOGI("Uploaded 3D Volumetric LUT directly to hardware sampler.");
}

// =============================================================================
// ROBUST, BANDED GPU PIPELINE
//  * Every submit is short (bands of rows), so the Android GPU watchdog never kills a big render.
//  * Every VkResult is checked; a failed render is reported (status code) instead of silently
//    returning stale / half-written buffers.
//  * Bloom + composite + output buffers are cleared on every render, so nothing from a previous
//    (differently sized) render can leak into the next one as a "ghost".
// =============================================================================
static int32_t gLastRenderStatus = 0;   // 0 ok, 1 GPU error (CPU fallback used), 2 device lost, 3 timeout

constexpr uint64_t kFenceTimeoutNs = 30ull * 1000000000ull;
constexpr int32_t  kMaxPixelsPerSubmit = 4000000;  // upper cap only: the time budget below normally limits a band first

static int32_t gBandBudgetMs = 40;            // target wall time of ONE GPU submit (shorter = the phone UI stays fluid)
static double  gNsPerPx[14] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}; // smoothed GPU cost per pixel: [0] pass 0, [1] pass 6, [2] pass 10, [3] pass 13 (VFX), [4] pass 16 (Sapphire), [5] pass 18 (Motion S flow, per grid cell), [6] pass 21 (Motion S render), [7] pass 23 (dither + quantise, batch 12 step B), [8] pass 22 (Time Slice, step C1), [9] pass 24 (Time Slice store, step C1), [10] pass 25 (Metallic Bevel luma plane, batch 13), [11] pass 26 (Metallic Bevel, batch 13), [12] pass 27 (MathOps, batch 14), [13] pass 28 (4-Way Gradient, batch 14)
static int64_t gLastRenderUs = 0;
static int32_t gFlareLayer = -1;              // layer whose flare is pre-computed at half res (-1 = inline)
static bool    gFlareHalfEnabled = false;     // runtime switch (set_flare_half_res); off = same flare maths as before
// Text-suite vector mode (batch 5): rows (0..1 of the frame) the warp passes 11 / 12 have to cover. Inactive = no extra passes.
static bool    gWarpActive = false;
static float   gWarpY0n = 0.0f;
static float   gWarpY1n = 0.0f;
// Batch 6: which of the new passes have anything to do this frame (decided from the uniform buffer, mirrors the shader tests).
static bool    gVfxActive = false;    // passes 13 / 14
static bool    gSapGlint = false;     // pass 15 (+ glint inside 16)
static bool    gSapLeak = false;      // light leak inside pass 16
// Batch 13: Global Metallic Bevel (passes 25 + 26, between Time Slice and the dither). Block at float 7424 + layer * 16 (class Bevel in vfx_slots.dart):
// slot 0 = On, slot 6 = Mix. The FIRST enabled layer with On = 1 and Mix > 0 is the one that is applied (its index goes to pass 26 in srcW).
constexpr int kBevelBase = 7424;
static bool    gBevelActive = false;
static int32_t gBevelLayer = 0;
static_assert(kBevelBase + 160 <= 8192, "Metallic Bevel block must fit the uniform buffer");
// Batch 14: MathOps (pass 27) block at 7584 + layer * 16 (slot 0 = On, slot 4 = Mix) and 4-Way Gradient (pass 28) block at 7744 + layer * 16 (slot 0 = On,
// slot 13 = Mix). Per-pixel effects: each runs ONCE per frame and loops over the layers in order inside the shader.
constexpr int kMathOpsBase = 7584;
constexpr int kGrad4Base = 7744;
static bool    gMathOpsActive = false;
static bool    gGrad4Active = false;
static_assert(kBevelBase + 160 == kMathOpsBase, "MathOps block must start right after the Bevel block");
static_assert(kMathOpsBase + 160 == kGrad4Base, "4-Way Gradient block must start right after the MathOps block");
static_assert(kGrad4Base + 160 <= 8192, "4-Way Gradient block must fit the uniform buffer");

static int32_t adaptiveRows(int slot, int32_t width, int32_t height, int32_t capPixels) {
    int32_t rows;
    if (gNsPerPx[slot] <= 0.0) {
        rows = 131072 / std::max(width, 1);                         // cost unknown yet: small probe band
    } else {
        double px = (double)gBandBudgetMs * 1e6 / gNsPerPx[slot];
        px = std::min(px, (double)capPixels);
        rows = (int32_t)(px / std::max(width, 1));
    }
    rows = (rows / 16) * 16;                                         // multiple of the 16-row workgroup
    return std::max<int32_t>(16, std::min<int32_t>(rows, ((height + 15) / 16) * 16));
}

static void updateBandCost(int slot, std::chrono::steady_clock::time_point t0, int32_t rows, int32_t width) {
    const double ns = (double)std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now() - t0).count();
    const double v = ns / std::max(1.0, (double)rows * (double)width);
    gNsPerPx[slot] = (gNsPerPx[slot] <= 0.0) ? v : (0.6 * gNsPerPx[slot] + 0.4 * v);
}

// First enabled layer that has a flare (same test as the shader: enabled, intensity > 0.01, opacity > 0.01).
static int32_t findFlareLayer(const float* ubo, int32_t count) {
    if (ubo == nullptr || count < 33) return -1;
    const int layers = (int)std::max(1.0f, std::min(ubo[1], 10.0f));
    for (int l = 0; l < layers; ++l) {
        const int off = 32 + l * 192;
        if (off + 53 > count) break;
        if (ubo[off + 0] >= 0.5f && ubo[off + 14] > 0.01f && ubo[off + 52] > 0.01f) return l;
    }
    return -1;
}

// Text suite vector mode: the personal block starts at float 3872 (tx[i]); tx[0] = packed, tx[40] = vector on, tx[41] = point count.
// Margin and box must match executeTextWarp() in the shader (tMargin = max(0.03, 0.22 * boxH)).
// Batch 6: VFX block at 4096 + l*64 (slot 0 = mode), Sapphire block at 4736 + l*64 (slot 0 = glint on, slot 32 = leak on).
// Superset of the shader's own per-layer tests: a pass that has nothing to do just copies the picture through.
static void findBatch6Passes(const float* ubo, int32_t count) {
    gVfxActive = false;
    gSapGlint = false;
    gSapLeak = false;
    if (ubo == nullptr || count < (int32_t)kUboFloats) return;
    const int layers = (int)std::max(1.0f, std::min(ubo[1], 10.0f));
    for (int l = 0; l < layers; ++l) {
        if (ubo[32 + l * 192] < 0.5f) continue;                 // layer disabled
        const float* vx = ubo + 4096 + l * 64;
        const float* sx = ubo + 4736 + l * 64;
        if (vx[0] >= 0.5f && vx[1] > 0.001f) gVfxActive = true;
        if (sx[0] >= 0.5f && sx[1] > 0.001f && sx[15] > 0.001f) gSapGlint = true;
        if (sx[32] >= 0.5f && sx[33] > 0.001f && sx[45] > 0.001f) gSapLeak = true;
    }
}

static void findBevel(const float* ubo, int32_t count) {
    gBevelActive = false;
    gBevelLayer = 0;
    if (ubo == nullptr || count < (int32_t)kUboFloats) return;
    const int layers = (int)std::max(1.0f, std::min(ubo[1], 10.0f));
    for (int l = 0; l < layers; ++l) {
        if (ubo[32 + l * 192] < 0.5f) continue;                 // layer disabled
        const float* b = ubo + kBevelBase + l * 16;
        if (b[0] >= 0.5f && b[6] > 0.0001f) { gBevelActive = true; gBevelLayer = l; return; }
    }
}

static void findMathGrad(const float* ubo, int32_t count) {
    gMathOpsActive = false;
    gGrad4Active = false;
    if (ubo == nullptr || count < (int32_t)kUboFloats) return;
    const int layers = (int)std::max(1.0f, std::min(ubo[1], 10.0f));
    for (int l = 0; l < layers; ++l) {
        if (ubo[32 + l * 192] < 0.5f) continue;                 // layer disabled
        const float* m = ubo + kMathOpsBase + l * 16;
        const float* g = ubo + kGrad4Base + l * 16;
        if (m[0] >= 0.5f && m[4] > 0.0001f) gMathOpsActive = true;
        if (g[0] >= 0.5f && g[13] > 0.0001f) gGrad4Active = true;
    }
}

static void findTextWarpRows(const float* ubo, int32_t count) {
    gWarpActive = false;
    const int base = 3872;
    if (ubo == nullptr || count < base + 48) return;
    if (ubo[13] < 0.5f || ubo[base] < 0.5f || ubo[base + 40] < 0.5f || ubo[base + 41] < 0.5f) return;
    const float boxY = ubo[15];
    const float boxH = std::max(ubo[17], 1e-3f);
    const float margin = std::max(0.03f, 0.22f * boxH);
    gWarpY0n = std::max(0.0f, boxY - margin - 0.002f);
    gWarpY1n = std::min(1.0f, boxY + boxH + margin + 0.002f);
    gWarpActive = gWarpY1n > gWarpY0n;
}

static bool submitAndWait(const std::function<void()>& record) {
    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    vkResetCommandBuffer(gVk.commandBuffer, 0);
    if (vkBeginCommandBuffer(gVk.commandBuffer, &beginInfo) != VK_SUCCESS) {
        LOGE("vkBeginCommandBuffer failed");
        return false;
    }
    vkCmdBindPipeline(gVk.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, gVk.computePipeline);
    vkCmdBindDescriptorSets(gVk.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                            gVk.pipelineLayout, 0, 1, &gVk.descriptorSet, 0, nullptr);
    record();
    if (vkEndCommandBuffer(gVk.commandBuffer) != VK_SUCCESS) {
        LOGE("vkEndCommandBuffer failed");
        return false;
    }

    vkResetFences(gVk.device, 1, &gVk.computeFence);
    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &gVk.commandBuffer;

    VkResult sr = vkQueueSubmit(gVk.computeQueue, 1, &submitInfo, gVk.computeFence);
    if (sr != VK_SUCCESS) {
        LOGE("vkQueueSubmit failed: %d", (int)sr);
        gLastRenderStatus = (sr == VK_ERROR_DEVICE_LOST) ? 2 : 1;
        return false;
    }
    VkResult wr = vkWaitForFences(gVk.device, 1, &gVk.computeFence, VK_TRUE, kFenceTimeoutNs);
    if (wr != VK_SUCCESS) {
        LOGE("vkWaitForFences failed: %d (GPU timeout / device lost)", (int)wr);
        gLastRenderStatus = (wr == VK_ERROR_DEVICE_LOST) ? 2 : 3;
        return false;
    }
    return true;
}

static void recordBarrier() {
    VkMemoryBarrier mb{};
    mb.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    mb.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    mb.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
    vkCmdPipelineBarrier(gVk.commandBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                         VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &mb, 0, nullptr, 0, nullptr);
}

// One compute pass over rows [bandY, bandY + rows) of a (w x h) pass.
static void recordPass(int32_t pass, int32_t w, int32_t h, float radius, int32_t bandY, int32_t rows,
                       int32_t srcW = 0, int32_t srcH = 0) {
    ComputePushConstants pc{pass, w, h, radius, bandY, srcW, srcH, gFlareLayer};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT,
                       0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (w + 15) / 16, (rows + 15) / 16, 1);
}

// Batch 6: a full-frame effect that reads the composite and writes into the output buffer (scratch; pass 6 overwrites it later), followed by a
// copy-back pass. Two separate loops so a band never reads rows that an earlier band already replaced. Bands are time-budgeted like pass 0 / 6,
// so a heavy effect becomes more, shorter GPU submits instead of one long one (the phone UI and the watchdog stay happy).
static bool runScratchEffect(int32_t passA, int32_t passB, int32_t w, int32_t h, int slot, int32_t pixelsPerSubmit) {
    for (int32_t y = 0; y < h;) {
        const int32_t rows = std::min(adaptiveRows(slot, w, h, pixelsPerSubmit), h - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(passA, w, h, 0.0f, y, rows); })) return false;
        updateBandCost(slot, t0, rows, w);
        y += rows;
    }
    const int32_t chunk = std::max<int32_t>(16, ((2000000 / std::max<int32_t>(w, 1)) / 16) * 16);
    for (int32_t y = 0; y < h;) {
        const int32_t rows = std::min(chunk, h - y);
        if (!submitAndWait([&]() { recordPass(passB, w, h, 0.0f, y, rows); })) return false;
        y += rows;
    }
    return true;
}

// Batch 13: Metallic Bevel on the finished display image (slot 0). Pass 25 writes a luma plane into the output buffer (scratch, pass 23 overwrites it),
// pass 26 reads that plane + its own pixel and writes its own pixel. Two separate loops (and submits), so every luma value exists before any pixel changes.
static bool runBevel(int32_t w, int32_t h, int32_t pixelsPerSubmit) {
    for (int32_t y = 0; y < h;) {
        const int32_t rows = std::min(adaptiveRows(10, w, h, pixelsPerSubmit), h - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(25, w, h, 0.0f, y, rows); })) return false;
        updateBandCost(10, t0, rows, w);
        y += rows;
    }
    for (int32_t y = 0; y < h;) {
        const int32_t rows = std::min(adaptiveRows(11, w, h, pixelsPerSubmit), h - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(26, w, h, 0.0f, y, rows, gBevelLayer, 0); })) return false;
        updateBandCost(11, t0, rows, w);
        y += rows;
    }
    return true;
}

// Batch 14: one in-place per-pixel pass over the display image (pass 27 MathOps / pass 28 4-Way Gradient), banded like the other passes.
static bool runPixelPass(int32_t pass, int slot, int32_t w, int32_t h, int32_t pixelsPerSubmit) {
    for (int32_t y = 0; y < h;) {
        const int32_t rows = std::min(adaptiveRows(slot, w, h, pixelsPerSubmit), h - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(pass, w, h, 0.0f, y, rows); })) return false;
        updateBandCost(slot, t0, rows, w);
        y += rows;
    }
    return true;
}

static bool runGpuPipelineOnce(int32_t outWidth, int32_t outHeight, int32_t pixelsPerSubmit) {
    const int32_t wL0 = std::max(1, outWidth >> 1),  hL0 = std::max(1, outHeight >> 1);
    const int32_t wL1 = std::max(1, outWidth >> 2),  hL1 = std::max(1, outHeight >> 2);
    const int32_t wL2 = std::max(1, outWidth >> 3),  hL2 = std::max(1, outHeight >> 3);
    const int32_t wL3 = std::max(1, outWidth >> 4),  hL3 = std::max(1, outHeight >> 4);
    const int32_t wL4 = std::max(1, outWidth >> 5),  hL4 = std::max(1, outHeight >> 5);

    // 0. Clear exactly the bytes this frame reads or writes (buffers are sized for the LARGEST frame ever rendered).
    {
        const VkDeviceSize pxBytes = (VkDeviceSize)outWidth * (VkDeviceSize)outHeight * 8;
        auto lvlBytes = [](int32_t w, int32_t h) { return (VkDeviceSize)((size_t)w * (size_t)h + 64) * 8; };
        struct Clr { VkBuffer b; VkDeviceSize n; };
        const Clr clr[] = {
            {gVk.bloomL0Buffer, lvlBytes(wL0, hL0)}, {gVk.bloomL1Buffer, lvlBytes(wL1, hL1)},
            {gVk.bloomL2Buffer, lvlBytes(wL2, hL2)}, {gVk.bloomL3Buffer, lvlBytes(wL3, hL3)},
            {gVk.bloomL4Buffer, lvlBytes(wL4, hL4)}, {gVk.tempCompositeBuffer, pxBytes},
            {gVk.outBuffer, pxBytes}};
        if (!submitAndWait([&]() {
                for (const Clr& c : clr) vkCmdFillBuffer(gVk.commandBuffer, c.b, 0, c.n, 0);
                VkMemoryBarrier mb{};
                mb.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
                mb.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
                mb.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
                vkCmdPipelineBarrier(gVk.commandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT,
                                     VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &mb, 0, nullptr, 0, nullptr);
            })) return false;
    }

    // 1. Pass 0 (primary grade -> TempComposite), banded.
    for (int32_t y = 0; y < outHeight;) {
        const int32_t rows = std::min(adaptiveRows(0, outWidth, outHeight, pixelsPerSubmit), outHeight - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(0, outWidth, outHeight, 1.0f, y, rows); })) return false;
        updateBandCost(0, t0, rows, outWidth);
        y += rows;
    }

    // 1b. Text-suite vector warp (only when vector mode is on). Pass 11 reads the composite and writes the warped rows into the
    //     output buffer (used as scratch, pass 6 overwrites it later); pass 12 copies them back. Two separate loops so a band
    //     never reads rows that an earlier band already replaced.
    if (gWarpActive) {
        const int32_t y0 = std::max<int32_t>(0, (int32_t)std::floor(gWarpY0n * (float)outHeight));
        const int32_t y1 = std::min<int32_t>(outHeight, (int32_t)std::ceil(gWarpY1n * (float)outHeight) + 1);
        if (y1 > y0) {
            const int32_t chunk = std::max<int32_t>(16, ((2000000 / std::max<int32_t>(outWidth, 1)) / 16) * 16);
            for (int32_t y = y0; y < y1;) {
                const int32_t rows = std::min(chunk, y1 - y);
                if (!submitAndWait([&]() { recordPass(11, outWidth, outHeight, 0.0f, y, rows); })) return false;
                y += rows;
            }
            for (int32_t y = y0; y < y1;) {
                const int32_t rows = std::min(chunk, y1 - y);
                if (!submitAndWait([&]() { recordPass(12, outWidth, outHeight, 0.0f, y, rows); })) return false;
                y += rows;
            }
        }
    }

    // 1c. VFX bubbles / rain / particles (batch 6): pass 13 shade -> scratch, pass 14 copy back. Runs before the bloom pyramid, so glows see it.
    if (gVfxActive) {
        if (!runScratchEffect(13, 14, outWidth, outHeight, 3, pixelsPerSubmit)) return false;
    }

    // 1d. Sapphire (batch 6). Pass 15 builds the S_Glint highlight map in bloom L1 (scratch here: the pyramid below rewrites L1 from scratch),
    //     pass 16 gathers glint rays + light leak into the scratch, pass 17 copies back.
    if (gSapGlint || gSapLeak) {
        if (gSapGlint) {
            if (!submitAndWait([&]() { recordPass(15, wL1, hL1, 0.0f, 0, hL1, outWidth, outHeight); })) return false;
        }
        if (!runScratchEffect(16, 17, outWidth, outHeight, 4, pixelsPerSubmit)) return false;
    }

    // 2. Bloom pyramid (cheap, low-res) in a single submit.
    if (!submitAndWait([&]() {
            recordPass(1, wL0, hL0, 1.0f, 0, hL0); recordBarrier();
            recordPass(2, wL1, hL1, 1.5f, 0, hL1, wL0, hL0); recordBarrier();
            recordPass(3, wL2, hL2, 2.0f, 0, hL2, wL1, hL1); recordBarrier();
            recordPass(7, wL3, hL3, 2.0f, 0, hL3, wL2, hL2); recordBarrier();
            recordPass(8, wL4, hL4, 2.0f, 0, hL4, wL3, hL3); recordBarrier();
            recordPass(9, wL3, hL3, 2.0f, 0, hL3); recordBarrier();
            recordPass(4, wL1, hL1, 2.0f, 0, hL1); recordBarrier();
            recordPass(5, wL0, hL0, 1.5f, 0, hL0);
        })) return false;

    // 2b. Pass 10: flare beam at HALF resolution for the flare layer (only when enabled and a flare is active).
    if (gFlareLayer >= 0) {
        for (int32_t y = 0; y < hL0;) {
            const int32_t rows = std::min(adaptiveRows(2, wL0, hL0, pixelsPerSubmit), hL0 - y);
            const auto t0 = std::chrono::steady_clock::now();
            if (!submitAndWait([&]() { recordPass(10, wL0, hL0, 0.0f, y, rows, outWidth, outHeight); })) return false;
            updateBandCost(2, t0, rows, wL0);
            y += rows;
        }
    }

    // 3. Pass 6 (master composite -> float32 display image, binding 13; batch 12 step B: no dither / quantise here any more), banded.
    for (int32_t y = 0; y < outHeight;) {
        const int32_t rows = std::min(adaptiveRows(1, outWidth, outHeight, pixelsPerSubmit), outHeight - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(6, outWidth, outHeight, 1.0f, y, rows); })) return false;
        updateBandCost(1, t0, rows, outWidth);
        y += rows;
    }

    // 3b. Time Slice ingest (step C1, only inside process_timeslice_ingest): store the finished pre-dither frame in its ring slot with pass 24 and
    //     stop here. No dither, no pass 23, no read-back: the frame will be dithered once, when it is emitted. Normal grading never gets in here.
    if (gTsStoreSlot >= 0) {
        for (int32_t y = 0; y < outHeight;) {
            const int32_t rows = std::min(adaptiveRows(9, outWidth, outHeight, pixelsPerSubmit), outHeight - y);
            const auto t0 = std::chrono::steady_clock::now();
            if (!submitAndWait([&]() { recordPass(24, outWidth, outHeight, 0.0f, y, rows, gTsStoreSlot, 0); })) return false;
            updateBandCost(9, t0, rows, outWidth);
            y += rows;
        }
        return true;
    }

    // 3c. Batch 13: Global Metallic Bevel (passes 25 + 26), after pass 6, before the dither. (Time Slice wipe frames do the same in runTimeSliceEmit.)
    if (gBevelActive) {
        if (!runBevel(outWidth, outHeight, pixelsPerSubmit)) return false;
    }

    // 3d. Batch 14: MathOps (pass 27), then 4-Way Gradient (pass 28), after the Bevel, before the dither.
    if (gMathOpsActive) {
        if (!runPixelPass(27, 12, outWidth, outHeight, pixelsPerSubmit)) return false;
    }
    if (gGrad4Active) {
        if (!runPixelPass(28, 13, outWidth, outHeight, pixelsPerSubmit)) return false;
    }

    // 4. Pass 23 (batch 12 step B): TPDF dither + quantise, display image (float32) -> outBuffer, banded the same way as pass 6.
    //    Pass 22 (Time Slice) runs between pass 6 and pass 23 in runTimeSliceEmit() (step C1), never inside this function. Nothing runs after pass 23.
    for (int32_t y = 0; y < outHeight;) {
        const int32_t rows = std::min(adaptiveRows(7, outWidth, outHeight, pixelsPerSubmit), outHeight - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(23, outWidth, outHeight, 0.0f, y, rows); })) return false;
        updateBandCost(7, t0, rows, outWidth);
        y += rows;
    }
    gPass23Count++;   // C2 debug: one complete pass 23 per graded frame
    return true;
}

// Retries with smaller bands on a recoverable failure. Returns false if the GPU render failed.
static bool runGpuPipeline(int32_t outWidth, int32_t outHeight) {
    const auto tStart = std::chrono::steady_clock::now();
    gLastRenderStatus = 0;
    int32_t budget = kMaxPixelsPerSubmit;
    bool ok = false;
    for (int attempt = 0; attempt < 3; ++attempt) {
        if (runGpuPipelineOnce(outWidth, outHeight, budget)) { ok = true; break; }
        if (gLastRenderStatus == 2 || gLastRenderStatus == 3) break;   // device lost / hung: no point retrying
        budget = std::max(65536, budget / 4);
        LOGE("GPU render failed, retrying with smaller bands (%d px/submit)", budget);
    }
    gLastRenderUs = (int64_t)std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - tStart).count();
    if (ok) return true;
    if (gLastRenderStatus == 0) gLastRenderStatus = 1;
    LOGE("GPU render FAILED (status %d) for %dx%d", gLastRenderStatus, outWidth, outHeight);
    return false;
}


// Batch 12 step C1: Time Slice emit = pass 22 (ring -> display slot 0) then pass 23 (dither + quantise -> outBuffer), banded like the other passes.
// Runs only when the host asks for it (a wipe is active). Pass 23 is the ONLY place that dithers, and it runs exactly once here.
static bool runTimeSliceEmit(int32_t w, int32_t h) {
    const auto tStart = std::chrono::steady_clock::now();
    gLastRenderStatus = 0;
    const int32_t px = kMaxPixelsPerSubmit;
    for (int32_t y = 0; y < h;) {
        const int32_t rows = std::min(adaptiveRows(8, w, h, px), h - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(22, w, h, 0.0f, y, rows); })) return false;
        updateBandCost(8, t0, rows, w);
        y += rows;
    }
    if (gBevelActive) {   // batch 13: Time Slice (22) -> Metallic Bevel (25 + 26) -> Dither (23)
        if (!runBevel(w, h, px)) return false;
    }
    if (gMathOpsActive) {   // batch 14: ... Bevel (25 + 26) -> MathOps (27) -> 4-Way Gradient (28) -> Dither (23)
        if (!runPixelPass(27, 12, w, h, px)) return false;
    }
    if (gGrad4Active) {
        if (!runPixelPass(28, 13, w, h, px)) return false;
    }
    for (int32_t y = 0; y < h;) {
        const int32_t rows = std::min(adaptiveRows(7, w, h, px), h - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(23, w, h, 0.0f, y, rows); })) return false;
        updateBandCost(7, t0, rows, w);
        y += rows;
    }
    gPass23Count++;   // C2 debug: one complete pass 23 per emitted frame
    gLastRenderUs = (int64_t)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - tStart).count();
    return true;
}

// =============================================================================
// MOTION S (batch 9)
//   process_motion() runs one output frame of the Motion S effect: N packed 8-bit RGBA frames in, one RGBA frame out.
//   1. CPU (tiny): global similarity motion (translation, rotation, zoom) between the current frame and its neighbours, estimated on
//      48 / 96 / 192 px luma thumbnails. AE shakes / zooms / spins are exactly this kind of motion, so it stays accurate for big moves.
//      The result is written into the Motion S block of the uniform buffer (floats 5376 + 128 .. 143).
//   2. GPU passes 18 (residual block flow) / 19 (smooth) / 20 (dilate) on a coarse grid, then pass 21 (render, banded).
//   Passes 18..21 read only the frames buffer, the flow buffer and the uniform buffer: bloom L0..L4 and the composite are never touched
//   (so the S_Glint scratch rule for bloom L1 between pass 15 and pass 2 cannot be hit).
//   Cost slots: 5 = pass 18 (flow, per grid cell), 6 = pass 21 (render, per pixel).
// =============================================================================
constexpr int kMotionBase = 5376;   // motionS[0] inside the uniform buffer
static_assert(kMotionBase + 1024 <= 8192, "Motion S block must fit the uniform buffer");

struct MoGray {
    int w = 0, h = 0;
    std::vector<float> v;
};

static MoGray moMakeGray(const uint8_t* rgba, int w, int h, int longEdge) {
    MoGray g;
    const float sc = (float)longEdge / (float)std::max(w, h);
    g.w = std::min(w, std::max(8, (int)std::lround((float)w * sc)));
    g.h = std::min(h, std::max(8, (int)std::lround((float)h * sc)));
    g.v.assign((size_t)g.w * (size_t)g.h, 0.0f);
    for (int y = 0; y < g.h; ++y) {
        const int y0 = (int)((int64_t)y * h / g.h);
        const int y1 = std::max(y0 + 1, (int)((int64_t)(y + 1) * h / g.h));
        const int sy = std::max(1, (y1 - y0) / 3);
        for (int x = 0; x < g.w; ++x) {
            const int x0 = (int)((int64_t)x * w / g.w);
            const int x1 = std::max(x0 + 1, (int)((int64_t)(x + 1) * w / g.w));
            const int sx = std::max(1, (x1 - x0) / 3);
            float acc = 0.0f;
            int n = 0;
            for (int yy = y0; yy < y1 && yy < h; yy += sy) {
                for (int xx = x0; xx < x1 && xx < w; xx += sx) {
                    const uint8_t* p = rgba + ((size_t)yy * (size_t)w + (size_t)xx) * 4;
                    acc += 0.2126f * p[0] + 0.7152f * p[1] + 0.0722f * p[2];
                    ++n;
                }
            }
            g.v[(size_t)y * (size_t)g.w + (size_t)x] = n > 0 ? acc / ((float)n * 255.0f) : 0.0f;
        }
    }
    return g;
}

static inline float moTap(const MoGray& g, float x, float y) {
    const int x0 = (int)x, y0 = (int)y;
    const float fx = x - (float)x0, fy = y - (float)y0;
    const int x1 = std::min(x0 + 1, g.w - 1), y1 = std::min(y0 + 1, g.h - 1);
    const float a = g.v[(size_t)y0 * g.w + x0], b = g.v[(size_t)y0 * g.w + x1];
    const float c = g.v[(size_t)y1 * g.w + x0], d = g.v[(size_t)y1 * g.w + x1];
    return (a + (b - a) * fx) * (1.0f - fy) + (c + (d - c) * fx) * fy;
}

// tx / ty are normalised by the long edge of the level, so the same numbers are valid at every pyramid level and at full resolution.
struct MoSim {
    float tx = 0.0f, ty = 0.0f, rot = 0.0f, ls = 0.0f;   // ls = log(scale)
};

// mean absolute luma difference of a(p) vs b(T(p)); T(p) = c + s R (p - c) + t. 1e9 = not enough overlap.
static float moSad(const MoGray& a, const MoGray& b, const MoSim& t, int step) {
    const float L = (float)std::max(a.w, a.h);
    const float cx = (float)a.w * 0.5f, cy = (float)a.h * 0.5f;
    const float s = std::exp(t.ls);
    const float cs = std::cos(t.rot) * s, sn = std::sin(t.rot) * s;
    const float ox = t.tx * L, oy = t.ty * L;
    const int mx = std::max(2, a.w / 16), my = std::max(2, a.h / 16);
    double acc = 0.0;
    int n = 0, total = 0;
    for (int y = my; y < a.h - my; y += step) {
        for (int x = mx; x < a.w - mx; x += step) {
            ++total;
            const float dx = (float)x + 0.5f - cx, dy = (float)y + 0.5f - cy;
            const float px = cx + cs * dx - sn * dy + ox - 0.5f;
            const float py = cy + sn * dx + cs * dy + oy - 0.5f;
            if (px < 0.0f || py < 0.0f || px > (float)b.w - 1.001f || py > (float)b.h - 1.001f) continue;
            acc += std::fabs(a.v[(size_t)y * a.w + x] - moTap(b, px, py));
            ++n;
        }
    }
    if (n == 0 || (double)n < 0.5 * (double)total) return 1e9f;
    return (float)(acc / (double)n);
}

static MoSim moRefine(const MoGray& a, const MoGray& b, MoSim s, float rotStep, float lsStep, float tStep, int iters, int px) {
    float cur = moSad(a, b, s, px);
    for (int it = 0; it < iters; ++it) {
        bool improved = false;
        for (int k = 0; k < 4; ++k) {
            for (int sg = -1; sg <= 1; sg += 2) {
                MoSim c = s;
                if (k == 0) c.rot += (float)sg * rotStep;
                else if (k == 1) c.ls += (float)sg * lsStep;
                else if (k == 2) c.tx += (float)sg * tStep;
                else c.ty += (float)sg * tStep;
                const float v = moSad(a, b, c, px);
                if (v < cur) { cur = v; s = c; improved = true; }
            }
        }
        if (!improved) { rotStep *= 0.5f; lsStep *= 0.5f; tStep *= 0.5f; }
    }
    return s;
}

// Global motion current -> neighbour. Falls back to "no global motion" unless the match is clearly better than standing still,
// which also keeps static scenes (and tiny shakes) from producing fake motion.
static MoSim moEstimate(const uint8_t* cur, const uint8_t* nb, int w, int h, float* confOut) {
    *confOut = 0.0f;
    MoSim id;
    const MoGray a0 = moMakeGray(cur, w, h, 48), b0 = moMakeGray(nb, w, h, 48);
    const MoGray a1 = moMakeGray(cur, w, h, 96), b1 = moMakeGray(nb, w, h, 96);
    const MoGray a2 = moMakeGray(cur, w, h, 192), b2 = moMakeGray(nb, w, h, 192);

    double mean = 0.0, var = 0.0;
    for (float v : a1.v) mean += v;
    mean /= (double)a1.v.size();
    for (float v : a1.v) var += (v - mean) * (v - mean);
    var /= (double)a1.v.size();
    if (var < 1e-4) return id;                        // flat / black frame: nothing to track

    const float idSad = moSad(a2, b2, id, 1);
    if (idSad < 0.004f) return id;                    // frames are practically identical

    MoSim best;
    float bestS = moSad(a0, b0, id, 1);
    const float kDeg = 3.14159265f / 180.0f;
    for (int ri = -12; ri <= 12; ++ri) {
        for (int si = -6; si <= 6; ++si) {
            for (int yi = -3; yi <= 3; ++yi) {
                for (int xi = -3; xi <= 3; ++xi) {
                    MoSim c;
                    c.rot = (float)ri * 4.0f * kDeg;
                    c.ls = (float)si * 0.05f;
                    c.tx = (float)xi * 0.04f;
                    c.ty = (float)yi * 0.04f;
                    const float v = moSad(a0, b0, c, 1);
                    if (v < bestS) { bestS = v; best = c; }
                }
            }
        }
    }
    best = moRefine(a1, b1, best, 0.02f, 0.015f, 0.006f, 14, 1);
    best = moRefine(a2, b2, best, 0.006f, 0.005f, 0.002f, 10, 1);
    const float finalS = moSad(a2, b2, best, 1);
    if (!(finalS < 0.85f * idSad)) return id;
    *confOut = std::max(0.0f, std::min(1.0f, 1.0f - finalS / idSad));
    return best;
}

static void moWriteT(float* m, int base, const MoSim& s, int w, int h, float conf) {
    const float L = (float)std::max(w, h);
    m[base + 0] = 1.0f;
    m[base + 1] = s.tx * L;
    m[base + 2] = s.ty * L;
    m[base + 3] = s.rot;
    m[base + 4] = s.ls;
    m[base + 5] = (float)w * 0.5f;
    m[base + 6] = (float)h * 0.5f;
    m[base + 7] = conf;
}

// rows for a banded pass; the very first band of an unknown cost is a single workgroup row (probe)
static int32_t motionRows(int slot, int32_t width, int32_t height, int32_t capPixels) {
    if (gNsPerPx[slot] <= 0.0) return 16;
    return adaptiveRows(slot, width, height, capPixels);
}

static bool runMotionOnce(int32_t w, int32_t h, int32_t gw, int32_t gh, bool needFlow, int32_t budgetPx) {
    if (needFlow) {
        // pass 18: residual block flow, grid dispatch (slot 5, cost per grid cell)
        for (int32_t y = 0; y < gh;) {
            const int32_t rows = std::min(motionRows(5, gw, gh, std::max<int32_t>(1024, budgetPx / 64)), gh - y);
            const auto t0 = std::chrono::steady_clock::now();
            if (!submitAndWait([&]() { recordPass(18, gw, gh, 0.0f, y, rows, w, h); })) return false;
            updateBandCost(5, t0, rows, gw);
            y += rows;
        }
        // passes 19 / 20: cheap, fixed chunks
        for (int pass = 19; pass <= 20; ++pass) {
            for (int32_t y = 0; y < gh;) {
                const int32_t rows = std::min<int32_t>(64, gh - y);
                if (!submitAndWait([&]() { recordPass(pass, gw, gh, 0.0f, y, rows, w, h); })) return false;
                y += rows;
            }
        }
    }
    // pass 21: render, banded by time budget (slot 6, cost per pixel)
    for (int32_t y = 0; y < h;) {
        const int32_t rows = std::min(motionRows(6, w, h, budgetPx), h - y);
        const auto t0 = std::chrono::steady_clock::now();
        if (!submitAndWait([&]() { recordPass(21, w, h, 0.0f, y, rows, w, h); })) return false;
        updateBandCost(6, t0, rows, w);
        y += rows;
    }
    return true;
}

static bool runMotionPipeline(int32_t w, int32_t h, int32_t gw, int32_t gh, bool needFlow) {
    const auto tStart = std::chrono::steady_clock::now();
    gLastRenderStatus = 0;
    int32_t budget = kMaxPixelsPerSubmit;
    bool ok = false;
    for (int attempt = 0; attempt < 3; ++attempt) {
        if (runMotionOnce(w, h, gw, gh, needFlow, budget)) { ok = true; break; }
        if (gLastRenderStatus == 2 || gLastRenderStatus == 3) break;
        budget = std::max(65536, budget / 4);
        LOGE("Motion S render failed, retrying with smaller bands (%d px/submit)", budget);
    }
    gLastRenderUs = (int64_t)std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - tStart).count();
    if (!ok && gLastRenderStatus == 0) gLastRenderStatus = 1;
    return ok;
}

} // namespace

// -----------------------------------------------------------------------------------------------------------------
// Batch 17A: boot diagnostics. init_vulkan records WHAT failed (stage + exact VkResult name and number) and HOW LONG each stage took in
// gInitError / gInitLog. Dart reads them through get_last_init_error() / get_last_init_log() and shows them on the boot screen, because
// there is no logcat on the phone. Written only while pipelineMutex is held by init_vulkan.
// -----------------------------------------------------------------------------------------------------------------
static char gInitError[600] = "";
static char gInitLog[900] = "";

static const char* vkResultName(VkResult r) {
    switch (r) {
        case VK_SUCCESS: return "VK_SUCCESS";
        case VK_NOT_READY: return "VK_NOT_READY";
        case VK_TIMEOUT: return "VK_TIMEOUT";
        case VK_INCOMPLETE: return "VK_INCOMPLETE";
        case VK_ERROR_OUT_OF_HOST_MEMORY: return "VK_ERROR_OUT_OF_HOST_MEMORY";
        case VK_ERROR_OUT_OF_DEVICE_MEMORY: return "VK_ERROR_OUT_OF_DEVICE_MEMORY";
        case VK_ERROR_INITIALIZATION_FAILED: return "VK_ERROR_INITIALIZATION_FAILED";
        case VK_ERROR_DEVICE_LOST: return "VK_ERROR_DEVICE_LOST";
        case VK_ERROR_MEMORY_MAP_FAILED: return "VK_ERROR_MEMORY_MAP_FAILED";
        case VK_ERROR_LAYER_NOT_PRESENT: return "VK_ERROR_LAYER_NOT_PRESENT";
        case VK_ERROR_EXTENSION_NOT_PRESENT: return "VK_ERROR_EXTENSION_NOT_PRESENT";
        case VK_ERROR_FEATURE_NOT_PRESENT: return "VK_ERROR_FEATURE_NOT_PRESENT";
        case VK_ERROR_INCOMPATIBLE_DRIVER: return "VK_ERROR_INCOMPATIBLE_DRIVER";
        case VK_ERROR_TOO_MANY_OBJECTS: return "VK_ERROR_TOO_MANY_OBJECTS";
        case VK_ERROR_FORMAT_NOT_SUPPORTED: return "VK_ERROR_FORMAT_NOT_SUPPORTED";
        case VK_ERROR_FRAGMENTED_POOL: return "VK_ERROR_FRAGMENTED_POOL";
        default: return "VkResult (see number)";
    }
}

static void initFail(const char* stage, VkResult r) {
    snprintf(gInitError, sizeof(gInitError), "%s failed: %s (%d)", stage, vkResultName(r), (int)r);
    LOGE("init_vulkan: %s", gInitError);
}

static void initFailMsg(const char* msg) {
    snprintf(gInitError, sizeof(gInitError), "%s", msg);
    LOGE("init_vulkan: %s", gInitError);
}

static void initLog(const char* stage, long long ms) {
    char line[96];
    snprintf(line, sizeof(line), "%s %lldms; ", stage, ms);
    strncat(gInitLog, line, sizeof(gInitLog) - strlen(gInitLog) - 1);
    LOGI("init_vulkan: %s took %lld ms", stage, ms);
}

// -----------------------------------------------------------------------------------------------------------------
// Batch 17B: background init state + persistent VkPipelineCache.
//
// The driver compiles the whole grade shader inside vkCreateComputePipelines (about 90 s on the first boot). Two things fix the boot ANR:
//   1. VkPipelineCache persisted in <cache_dir>/shader_cache.bin: every boot after the first one skips the compile.
//   2. init_vulkan_async() runs init_vulkan on a native std::thread, so the UI thread never blocks (even on the very first boot).
// These atomics are the ONLY state Dart reads while the init thread runs (they never take pipelineMutex, which the init thread holds
// for the whole init). gInitError / gInitLog may only be read once the state is no longer "running".
// -----------------------------------------------------------------------------------------------------------------
static std::atomic<bool> gInitRunning{false};      // a background init thread exists and has not finished
static std::atomic<bool> gInitDone{false};         // the last background init finished (success or failure)
static std::atomic<int32_t> gInitResult{0};        // 1 = ok, 0 = failed; valid when gInitDone
static std::atomic<bool> gInitCold{true};          // true = no valid cache for this shader / GPU / driver: the compile will be slow (set before the compile starts)

// Our own small header in front of the raw driver blob, so a cache written for an OLDER shader build is never trusted:
//   u32 magic | u32 version | u64 fnv1a64(SPIR-V) | u64 blobSize | driver blob (vkGetPipelineCacheData)
static constexpr uint32_t kCacheMagic = 0x43444853u;   // "SHDC"
static constexpr uint32_t kCacheVersion = 1u;
static constexpr size_t kCacheHeaderBytes = 4 + 4 + 8 + 8;
static constexpr size_t kCacheMaxBytes = 128u * 1024u * 1024u;   // sanity limit for a file we are about to hand to the driver

static uint64_t fnv1a64(const uint8_t* d, size_t n) {
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) { h ^= d[i]; h *= 1099511628211ull; }
    return h;
}

static bool readWholeFile(const std::string& path, std::vector<uint8_t>& out) {
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return false;
    bool ok = false;
    if (fseek(f, 0, SEEK_END) == 0) {
        long sz = ftell(f);
        if (sz > 0 && (size_t)sz <= kCacheMaxBytes && fseek(f, 0, SEEK_SET) == 0) {
            out.resize((size_t)sz);
            ok = fread(out.data(), 1, (size_t)sz, f) == (size_t)sz;
        }
    }
    fclose(f);
    if (!ok) out.clear();
    return ok;
}

// Writes <path>.tmp then renames it over <path>: a crash / kill in the middle can never leave a half-written cache behind.
static bool writeFileAtomic(const std::string& path, const std::vector<uint8_t>& data) {
    std::string tmp = path + ".tmp";
    FILE* f = fopen(tmp.c_str(), "wb");
    if (!f) return false;
    bool ok = fwrite(data.data(), 1, data.size(), f) == data.size();
    ok = (fflush(f) == 0) && ok;
    fclose(f);
    if (!ok || rename(tmp.c_str(), path.c_str()) != 0) { remove(tmp.c_str()); return false; }
    return true;
}

// The first 32 bytes of the driver blob are VkPipelineCacheHeaderVersionOne: headerSize, headerVersion, vendorID, deviceID, UUID[16].
// Vulkan says the driver must reject a foreign blob; checking it here as well costs nothing and protects against buggy drivers.
static bool driverBlobMatchesDevice(const uint8_t* blob, size_t n, const VkPhysicalDeviceProperties& p) {
    if (n < 16 + VK_UUID_SIZE) return false;
    uint32_t headerSize, headerVersion, vendorId, deviceId;
    std::memcpy(&headerSize, blob + 0, 4);
    std::memcpy(&headerVersion, blob + 4, 4);
    std::memcpy(&vendorId, blob + 8, 4);
    std::memcpy(&deviceId, blob + 12, 4);
    if (headerSize < 16 + VK_UUID_SIZE || headerSize > n) return false;
    if (headerVersion != (uint32_t)VK_PIPELINE_CACHE_HEADER_VERSION_ONE) return false;
    if (vendorId != p.vendorID || deviceId != p.deviceID) return false;
    return std::memcmp(blob + 16, p.pipelineCacheUUID, VK_UUID_SIZE) == 0;
}

// Loads the cache file. true = [blob] holds a driver blob that is valid for THIS shader, GPU and driver.
static bool loadPipelineCacheBlob(const std::string& path, uint64_t shaderHash, const VkPhysicalDeviceProperties& props, std::vector<uint8_t>& blob) {
    blob.clear();
    std::vector<uint8_t> file;
    if (!readWholeFile(path, file)) return false;
    if (file.size() <= kCacheHeaderBytes) return false;
    uint32_t magic, version;
    uint64_t hash, size;
    std::memcpy(&magic, file.data() + 0, 4);
    std::memcpy(&version, file.data() + 4, 4);
    std::memcpy(&hash, file.data() + 8, 8);
    std::memcpy(&size, file.data() + 16, 8);
    if (magic != kCacheMagic || version != kCacheVersion) return false;
    if (hash != shaderHash) { LOGI("pipeline cache: written for a different shader build, ignoring it"); return false; }
    if (size != file.size() - kCacheHeaderBytes) return false;
    if (!driverBlobMatchesDevice(file.data() + kCacheHeaderBytes, (size_t)size, props)) { LOGI("pipeline cache: written for another GPU / driver, ignoring it"); return false; }
    blob.assign(file.begin() + kCacheHeaderBytes, file.end());
    return true;
}

static bool savePipelineCacheFile(const std::string& path, uint64_t shaderHash) {
    if (gVk.pipelineCache == VK_NULL_HANDLE || path.empty()) return false;
    size_t n = 0;
    if (vkGetPipelineCacheData(gVk.device, gVk.pipelineCache, &n, nullptr) != VK_SUCCESS || n == 0 || n > kCacheMaxBytes) return false;
    std::vector<uint8_t> file(kCacheHeaderBytes + n);
    VkResult r = vkGetPipelineCacheData(gVk.device, gVk.pipelineCache, &n, file.data() + kCacheHeaderBytes);
    if (r != VK_SUCCESS) return false;   // VK_INCOMPLETE = the cache grew between the two calls: skip this save, the next boot just compiles again
    file.resize(kCacheHeaderBytes + n);
    const uint64_t blobSize = (uint64_t)n;
    std::memcpy(file.data() + 0, &kCacheMagic, 4);
    std::memcpy(file.data() + 4, &kCacheVersion, 4);
    std::memcpy(file.data() + 8, &shaderHash, 8);
    std::memcpy(file.data() + 16, &blobSize, 8);
    const bool ok = writeFileAtomic(path, file);
    LOGI("pipeline cache: %s %zu bytes to %s", ok ? "saved" : "FAILED to save", n, path.c_str());
    return ok;
}

// Frees everything init_vulkan may have created, in reverse order, so a failed boot leaves a clean slate and RETRY starts from nothing
// (before this, a failed init leaked the instance / device and the next attempt created a second one). Caller holds pipelineMutex.
static void teardownAfterFailedInit() {
    if (gVk.device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(gVk.device);
        cleanupBuffers();
        if (gVk.computeFence != VK_NULL_HANDLE) { vkDestroyFence(gVk.device, gVk.computeFence, nullptr); gVk.computeFence = VK_NULL_HANDLE; }
        if (gVk.commandPool != VK_NULL_HANDLE) { vkDestroyCommandPool(gVk.device, gVk.commandPool, nullptr); gVk.commandPool = VK_NULL_HANDLE; }
        gVk.commandBuffer = VK_NULL_HANDLE;
        if (gVk.descriptorPool != VK_NULL_HANDLE) { vkDestroyDescriptorPool(gVk.device, gVk.descriptorPool, nullptr); gVk.descriptorPool = VK_NULL_HANDLE; }
        gVk.descriptorSet = VK_NULL_HANDLE;
        if (gVk.computePipeline != VK_NULL_HANDLE) { vkDestroyPipeline(gVk.device, gVk.computePipeline, nullptr); gVk.computePipeline = VK_NULL_HANDLE; }
        if (gVk.pipelineCache != VK_NULL_HANDLE) { vkDestroyPipelineCache(gVk.device, gVk.pipelineCache, nullptr); gVk.pipelineCache = VK_NULL_HANDLE; }
        if (gVk.pipelineLayout != VK_NULL_HANDLE) { vkDestroyPipelineLayout(gVk.device, gVk.pipelineLayout, nullptr); gVk.pipelineLayout = VK_NULL_HANDLE; }
        if (gVk.descriptorSetLayout != VK_NULL_HANDLE) { vkDestroyDescriptorSetLayout(gVk.device, gVk.descriptorSetLayout, nullptr); gVk.descriptorSetLayout = VK_NULL_HANDLE; }
        if (gVk.shaderModule != VK_NULL_HANDLE) { vkDestroyShaderModule(gVk.device, gVk.shaderModule, nullptr); gVk.shaderModule = VK_NULL_HANDLE; }
        if (gVk.lutImageView != VK_NULL_HANDLE) { vkDestroyImageView(gVk.device, gVk.lutImageView, nullptr); gVk.lutImageView = VK_NULL_HANDLE; }
        if (gVk.lutImage != VK_NULL_HANDLE) { vkDestroyImage(gVk.device, gVk.lutImage, nullptr); gVk.lutImage = VK_NULL_HANDLE; }
        if (gVk.lutMemory != VK_NULL_HANDLE) { vkFreeMemory(gVk.device, gVk.lutMemory, nullptr); gVk.lutMemory = VK_NULL_HANDLE; }
        if (gVk.linearSampler != VK_NULL_HANDLE) { vkDestroySampler(gVk.device, gVk.linearSampler, nullptr); gVk.linearSampler = VK_NULL_HANDLE; }
        if (gVk.lutSampler != VK_NULL_HANDLE) { vkDestroySampler(gVk.device, gVk.lutSampler, nullptr); gVk.lutSampler = VK_NULL_HANDLE; }
        vkDestroyDevice(gVk.device, nullptr);
        gVk.device = VK_NULL_HANDLE;
    }
    gVk.computeQueue = VK_NULL_HANDLE;
    gVk.physicalDevice = VK_NULL_HANDLE;
    if (gVk.instance != VK_NULL_HANDLE) { vkDestroyInstance(gVk.instance, nullptr); gVk.instance = VK_NULL_HANDLE; }
    gVk.isInitialized = false;
}

extern "C" {

// 0 = last render OK, 1 = GPU error (CPU fallback was used), 2 = device lost, 3 = GPU timeout
int32_t get_last_render_status() { return gLastRenderStatus; }

// Target wall time of one GPU submit in ms (4..500). Small = phone UI stays fluid, large = less submit overhead.
void set_band_budget_ms(int32_t ms) {
    gBandBudgetMs = std::max<int32_t>(4, std::min<int32_t>(ms, 500));
    gNsPerPx[0] = gNsPerPx[1] = gNsPerPx[2] = gNsPerPx[3] = gNsPerPx[4] = 0.0;      // re-learn the cost with the new target
    gNsPerPx[5] = gNsPerPx[6] = 0.0;                                                  // Motion S slots (batch 9)
    gNsPerPx[7] = 0.0;                                                                // pass 23 (batch 12 step B)
    gNsPerPx[8] = gNsPerPx[9] = 0.0;                                                  // passes 22 / 24 (Time Slice, step C1)
}

// Wall time of the last native GPU pipeline run, microseconds.
int64_t get_last_render_us() { return gLastRenderUs; }

// 1 = pre-compute the flare beam at half resolution (pass 10, ~4x less flare work), 0 = per-pixel flare.
void set_flare_half_res(int32_t on) { gFlareHalfEnabled = (on != 0); }

// Text of the last init_vulkan failure ("" = none) and the per-stage timings of the last run. Valid until the next init_vulkan call.
const char* get_last_init_error() { return gInitError; }
const char* get_last_init_log() { return gInitLog; }

// Batch 17A: returns 1 = ready (or already initialised), 0 = failed. EVERY Vulkan call that can fail is checked; the first failure
// records the exact VkResult (get_last_init_error), frees everything created so far and returns 0 immediately. Nothing here loops or
// retries. The Time Slice ring is NOT created here: ensureTimeSliceRing() only runs from process_timeslice_ingest, i.e. when Time Slice
// is switched on in the editor (the boot test grade is 64 x 64 with Time Slice off, so the display buffer is one tiny frame).
// Batch 17B: [cache_dir] (nullptr / "" = no cache) is a writable directory; the pipeline cache lives in <cache_dir>/shader_cache.bin. A missing,
// broken or foreign cache file is never an error: the pipeline is simply compiled (slow) and the file is written afterwards. This function is
// synchronous; the app calls it through init_vulkan_async() (below) so the UI thread never waits for it.
int32_t init_vulkan(const uint8_t* shaderBytes, int32_t length, int32_t precision, const char* cache_dir) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);

    if (gVk.isInitialized) return 1;

    gInitError[0] = '\0';
    gInitLog[0] = '\0';
    // a previous attempt that failed has already torn itself down; this also catches a half-built state left by anything else
    teardownAfterFailedInit();

    if (shaderBytes == nullptr || length < 20 || (length % 4) != 0) {
        char m[96];
        snprintf(m, sizeof(m), "The shader file is not valid SPIR-V (%d bytes).", (int)length);
        initFailMsg(m);
        return 0;
    }

    using Clock = std::chrono::steady_clock;
    auto t0 = Clock::now();
    auto lap = [&](const char* stage) {
        auto t1 = Clock::now();
        initLog(stage, (long long)std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count());
        t0 = t1;
    };

    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "AERealityEngine";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "AERealityVulkan";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;

    VkResult r = vkCreateInstance(&createInfo, nullptr, &gVk.instance);
    if (r != VK_SUCCESS) {
        gVk.instance = VK_NULL_HANDLE;
        initFail("vkCreateInstance", r);
        return 0;
    }

    uint32_t deviceCount = 0;
    r = vkEnumeratePhysicalDevices(gVk.instance, &deviceCount, nullptr);
    if (r != VK_SUCCESS || deviceCount == 0) {
        if (r != VK_SUCCESS) initFail("vkEnumeratePhysicalDevices", r);
        else initFailMsg("This phone reports no Vulkan GPU (0 physical devices).");
        teardownAfterFailedInit();
        return 0;
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    r = vkEnumeratePhysicalDevices(gVk.instance, &deviceCount, devices.data());
    if ((r != VK_SUCCESS && r != VK_INCOMPLETE) || deviceCount == 0) {
        initFail("vkEnumeratePhysicalDevices (list)", r);
        teardownAfterFailedInit();
        return 0;
    }
    gVk.physicalDevice = devices[0];
    {
        // Batch 12 step B: the pipeline layout uses 13 storage buffers (+1 sampler) in one stage. Log the device limit so a failure is explainable.
        VkPhysicalDeviceProperties devProps{};
        vkGetPhysicalDeviceProperties(gVk.physicalDevice, &devProps);
        char line[200];
        snprintf(line, sizeof(line), "GPU \"%s\", maxStorageBuffers/stage %u; ", devProps.deviceName, devProps.limits.maxPerStageDescriptorStorageBuffers);
        strncat(gInitLog, line, sizeof(gInitLog) - strlen(gInitLog) - 1);
        LOGI("maxPerStageDescriptorStorageBuffers = %u (need 13)", devProps.limits.maxPerStageDescriptorStorageBuffers);
        if (devProps.limits.maxPerStageDescriptorStorageBuffers < 13) {
            LOGE("Device allows only %u storage buffers per stage; the pipeline needs 13 - Vulkan grading may fail.", devProps.limits.maxPerStageDescriptorStorageBuffers);
        }
    }

    uint32_t queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(gVk.physicalDevice, &queueFamilyCount, nullptr);
    std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(gVk.physicalDevice, &queueFamilyCount, queueFamilies.data());

    bool foundCompute = false;
    for (uint32_t i = 0; i < queueFamilyCount; i++) {
        if (queueFamilies[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
            gVk.computeQueueFamilyIndex = i;
            foundCompute = true;
            break;
        }
    }
    if (!foundCompute) {
        initFailMsg("This GPU has no compute queue.");
        teardownAfterFailedInit();
        return 0;
    }

    float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo queueCreateInfo{};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = gVk.computeQueueFamilyIndex;
    queueCreateInfo.queueCount = 1;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    VkPhysicalDeviceFeatures deviceFeatures{};
    VkDeviceCreateInfo deviceCreateInfo{};
    deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    deviceCreateInfo.queueCreateInfoCount = 1;
    deviceCreateInfo.pQueueCreateInfos = &queueCreateInfo;
    deviceCreateInfo.pEnabledFeatures = &deviceFeatures;

    r = vkCreateDevice(gVk.physicalDevice, &deviceCreateInfo, nullptr, &gVk.device);
    if (r != VK_SUCCESS) {
        gVk.device = VK_NULL_HANDLE;
        initFail("vkCreateDevice", r);
        teardownAfterFailedInit();
        return 0;
    }
    lap("instance+device");

    vkGetDeviceQueue(gVk.device, gVk.computeQueueFamilyIndex, 0, &gVk.computeQueue);

    // createHardwareSamplers() logs its own failures and leaves the handle null; check them here so a failure stops the boot.
    // Batch 17A fix: createHardwareSamplers() makes ONLY the two samplers. The 32 x 32 x 32 LUT image (~0.5 MB) used to be created later, in
    // ensureBuffersCapacity(), so the check below could never pass and init_vulkan always returned 0. It is created here now (create3DLutImage()
    // returns at once if it already exists). Never the Time Slice ring.
    createHardwareSamplers();
    create3DLutImage();
    if (gVk.linearSampler == VK_NULL_HANDLE || gVk.lutSampler == VK_NULL_HANDLE ||
        gVk.lutImage == VK_NULL_HANDLE || gVk.lutMemory == VK_NULL_HANDLE || gVk.lutImageView == VK_NULL_HANDLE) {
        initFailMsg("Creating the samplers / 3D LUT image failed (vkCreateSampler, vkCreateImage, vkAllocateMemory or vkCreateImageView; see logcat tag ShaderlyVulkan).");
        teardownAfterFailedInit();
        return 0;
    }
    lap("samplers+lut");

    VkShaderModuleCreateInfo shaderModuleInfo{};
    shaderModuleInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    shaderModuleInfo.codeSize = length;
    shaderModuleInfo.pCode = reinterpret_cast<const uint32_t*>(shaderBytes);

    r = vkCreateShaderModule(gVk.device, &shaderModuleInfo, nullptr, &gVk.shaderModule);
    if (r != VK_SUCCESS) {
        gVk.shaderModule = VK_NULL_HANDLE;
        initFail("vkCreateShaderModule", r);
        teardownAfterFailedInit();
        return 0;
    }
    lap("shader module");

    VkDescriptorSetLayoutBinding bindings[14]{};
    for (int b = 0; b < 14; b++) {
        bindings[b].binding = b;
        bindings[b].descriptorType = (b == 3) ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        bindings[b].descriptorCount = 1;
        bindings[b].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    }

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 14;
    layoutInfo.pBindings = bindings;
    r = vkCreateDescriptorSetLayout(gVk.device, &layoutInfo, nullptr, &gVk.descriptorSetLayout);
    if (r != VK_SUCCESS) {
        gVk.descriptorSetLayout = VK_NULL_HANDLE;
        initFail("vkCreateDescriptorSetLayout", r);
        teardownAfterFailedInit();
        return 0;
    }

    VkPushConstantRange pushConstantRange{};
    pushConstantRange.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    pushConstantRange.offset = 0;
    pushConstantRange.size = sizeof(ComputePushConstants);

    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &gVk.descriptorSetLayout;
    pipelineLayoutInfo.pushConstantRangeCount = 1;
    pipelineLayoutInfo.pPushConstantRanges = &pushConstantRange;
    r = vkCreatePipelineLayout(gVk.device, &pipelineLayoutInfo, nullptr, &gVk.pipelineLayout);
    if (r != VK_SUCCESS) {
        gVk.pipelineLayout = VK_NULL_HANDLE;
        initFail("vkCreatePipelineLayout", r);
        teardownAfterFailedInit();
        return 0;
    }
    lap("layouts");

    // ---- Batch 17B: VkPipelineCache, loaded from disk when a valid file exists --------------------------------------------------------
    std::string cachePath;
    uint64_t shaderHash = 0;
    std::vector<uint8_t> cacheBlob;
    bool warm = false;   // a valid cache for this shader / GPU / driver was found: the compile below should be (almost) instant
    if (cache_dir != nullptr && cache_dir[0] != '\0') {
        cachePath = std::string(cache_dir) + "/shader_cache.bin";
        shaderHash = fnv1a64(shaderBytes, (size_t)length);
        VkPhysicalDeviceProperties cacheProps{};
        vkGetPhysicalDeviceProperties(gVk.physicalDevice, &cacheProps);
        warm = loadPipelineCacheBlob(cachePath, shaderHash, cacheProps, cacheBlob);
    }
    {
        VkPipelineCacheCreateInfo cacheInfo{};
        cacheInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
        cacheInfo.initialDataSize = warm ? cacheBlob.size() : 0;
        cacheInfo.pInitialData = warm ? cacheBlob.data() : nullptr;
        VkResult cr = vkCreatePipelineCache(gVk.device, &cacheInfo, nullptr, &gVk.pipelineCache);
        if (cr != VK_SUCCESS && warm) {
            // the driver refused the saved blob: start from an empty cache instead
            LOGE("vkCreatePipelineCache with saved data failed (%s), retrying empty", vkResultName(cr));
            warm = false;
            cacheBlob.clear();
            cacheInfo.initialDataSize = 0;
            cacheInfo.pInitialData = nullptr;
            cr = vkCreatePipelineCache(gVk.device, &cacheInfo, nullptr, &gVk.pipelineCache);
        }
        if (cr != VK_SUCCESS) {
            // not fatal: no cache, the pipeline is compiled and nothing is saved
            LOGE("vkCreatePipelineCache failed (%s): compiling without a cache", vkResultName(cr));
            gVk.pipelineCache = VK_NULL_HANDLE;
            warm = false;
        }
    }
    gInitCold.store(!warm);   // Dart reads this to pick the boot timeout: warm = seconds, cold = the one-time ~90 s compile
    {
        char line[64];
        snprintf(line, sizeof(line), "pipeline cache %s; ", warm ? "HIT" : "MISS");
        strncat(gInitLog, line, sizeof(gInitLog) - strlen(gInitLog) - 1);
    }
    lap("pipeline cache load");

    // THE expensive call (only on a cache miss): the driver compiles the whole grade shader here. It is synchronous and cannot be interrupted
    // from outside; the time it took is recorded in the init log so a slow compile is visible on the boot screen.
    VkComputePipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipelineInfo.layout = gVk.pipelineLayout;
    pipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipelineInfo.stage.module = gVk.shaderModule;
    pipelineInfo.stage.pName = "main";
    r = vkCreateComputePipelines(gVk.device, gVk.pipelineCache, 1, &pipelineInfo, nullptr, &gVk.computePipeline);
    if (r != VK_SUCCESS || gVk.computePipeline == VK_NULL_HANDLE) {
        gVk.computePipeline = VK_NULL_HANDLE;
        initFail("vkCreateComputePipelines", r);
        teardownAfterFailedInit();
        return 0;
    }
    lap("pipeline compile");

    // Batch 17B: write the cache after the pipeline exists. Skipped when the cache was valid and nothing new was added (no pointless rewrite).
    if (gVk.pipelineCache != VK_NULL_HANDLE && !cachePath.empty()) {
        size_t nowBytes = 0;
        const bool haveSize = vkGetPipelineCacheData(gVk.device, gVk.pipelineCache, &nowBytes, nullptr) == VK_SUCCESS;
        if (haveSize && (!warm || nowBytes != cacheBlob.size())) {
            savePipelineCacheFile(cachePath, shaderHash);
            lap("pipeline cache save");
        }
    }

    VkDescriptorPoolSize poolSizes[2]{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    poolSizes[0].descriptorCount = 13;   // bindings 0,1,2,4..13 (batch 9: +2 Motion S, batch 12 step B: +1 display image)
    poolSizes[1].type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    poolSizes[1].descriptorCount = 1;

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.poolSizeCount = 2;
    poolInfo.pPoolSizes = poolSizes;
    poolInfo.maxSets = 1;
    r = vkCreateDescriptorPool(gVk.device, &poolInfo, nullptr, &gVk.descriptorPool);
    if (r != VK_SUCCESS) {
        gVk.descriptorPool = VK_NULL_HANDLE;
        initFail("vkCreateDescriptorPool", r);
        teardownAfterFailedInit();
        return 0;
    }

    VkDescriptorSetAllocateInfo setAllocInfo{};
    setAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    setAllocInfo.descriptorPool = gVk.descriptorPool;
    setAllocInfo.descriptorSetCount = 1;
    setAllocInfo.pSetLayouts = &gVk.descriptorSetLayout;
    r = vkAllocateDescriptorSets(gVk.device, &setAllocInfo, &gVk.descriptorSet);
    if (r != VK_SUCCESS) {
        gVk.descriptorSet = VK_NULL_HANDLE;
        initFail("vkAllocateDescriptorSets", r);
        teardownAfterFailedInit();
        return 0;
    }

    VkCommandPoolCreateInfo cmdPoolInfo{};
    cmdPoolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cmdPoolInfo.queueFamilyIndex = gVk.computeQueueFamilyIndex;
    cmdPoolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    r = vkCreateCommandPool(gVk.device, &cmdPoolInfo, nullptr, &gVk.commandPool);
    if (r != VK_SUCCESS) {
        gVk.commandPool = VK_NULL_HANDLE;
        initFail("vkCreateCommandPool", r);
        teardownAfterFailedInit();
        return 0;
    }

    VkCommandBufferAllocateInfo cmdAllocInfo{};
    cmdAllocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAllocInfo.commandPool = gVk.commandPool;
    cmdAllocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAllocInfo.commandBufferCount = 1;
    r = vkAllocateCommandBuffers(gVk.device, &cmdAllocInfo, &gVk.commandBuffer);
    if (r != VK_SUCCESS) {
        gVk.commandBuffer = VK_NULL_HANDLE;
        initFail("vkAllocateCommandBuffers", r);
        teardownAfterFailedInit();
        return 0;
    }

    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = 0;
    r = vkCreateFence(gVk.device, &fenceInfo, nullptr, &gVk.computeFence);
    if (r != VK_SUCCESS) {
        gVk.computeFence = VK_NULL_HANDLE;
        initFail("vkCreateFence", r);
        teardownAfterFailedInit();
        return 0;
    }
    lap("pool+commands");

    gVk.isInitialized = true;
    LOGI("Vulkan Pipeline with Hardware Samplers & 3D LUT Texture Initialized.");
    return 1;
}

// -----------------------------------------------------------------------------------------------------------------
// Batch 17B: non-blocking boot.
//
// init_vulkan_async() copies the SPIR-V and the cache directory, starts init_vulkan on a native std::thread and returns at once, so the UI
// isolate keeps animating the loading screen (no more ANR on the first boot, when the empty cache means a ~90 s shader compile). Dart then
// polls is_vulkan_ready() / vulkan_init_state(). Rules:
//   * only one init thread at a time: a second call while one runs (the RETRY button) just returns 1 and the caller keeps waiting for it,
//   * after a FAILED init a new call starts a fresh attempt, after a successful one it returns 1 at once,
//   * process_image & co. take pipelineMutex, which the init thread holds, so a grade request that arrives early waits for the init
//     (it runs in the grade worker isolate, never on the UI thread).
// Return value: 1 = started / already running / already initialised, 0 = could not start (thread creation failed, invalid arguments).
// -----------------------------------------------------------------------------------------------------------------
struct InitJob {
    std::vector<uint8_t> shader;
    std::string cacheDir;
    int32_t precision;
};

int32_t init_vulkan_async(const uint8_t* shaderBytes, int32_t length, int32_t precision, const char* cache_dir) {
    if (shaderBytes == nullptr || length < 20 || (length % 4) != 0) {
        // same text the synchronous path gives; nothing is running, so writing the error buffer here is safe
        if (!gInitRunning.load()) {
            char m[96];
            snprintf(m, sizeof(m), "The shader file is not valid SPIR-V (%d bytes).", (int)length);
            gInitError[0] = '\0';
            initFailMsg(m);
            gInitResult.store(0);
            gInitDone.store(true);
        }
        return 0;
    }

    bool expected = false;
    if (!gInitRunning.compare_exchange_strong(expected, true)) return 1;   // a thread is already running: keep waiting for it
    if (gInitDone.load() && gInitResult.load() == 1) {                     // already initialised
        gInitRunning.store(false);
        return 1;
    }

    gInitDone.store(false);
    gInitResult.store(0);
    gInitCold.store(true);

    InitJob* job = new InitJob();
    job->shader.assign(shaderBytes, shaderBytes + length);   // Dart frees its buffer as soon as this function returns
    job->cacheDir = (cache_dir != nullptr) ? cache_dir : "";
    job->precision = precision;

    try {
        std::thread([job]() {
            int32_t res = 0;
            try {
                res = init_vulkan(job->shader.data(), (int32_t)job->shader.size(), job->precision, job->cacheDir.c_str());
            } catch (...) {
                initFailMsg("init_vulkan threw an exception on the background thread.");
                res = 0;
            }
            delete job;
            gInitResult.store(res == 1 ? 1 : 0);
            gInitDone.store(true, std::memory_order_release);   // the result (and gInitError / gInitLog) are published BEFORE this flag
            gInitRunning.store(false);
        }).detach();
    } catch (...) {
        delete job;
        gInitError[0] = '\0';
        initFailMsg("Could not start the background thread for the GPU pipeline.");
        gInitResult.store(0);
        gInitDone.store(true);
        gInitRunning.store(false);
        return 0;
    }
    return 1;
}

// true once the background init (init_vulkan_async) finished SUCCESSFULLY. Never blocks, never takes pipelineMutex.
bool is_vulkan_ready() { return gInitDone.load(std::memory_order_acquire) && gInitResult.load() == 1; }

// 0 = running / not started, 1 = finished OK, -1 = finished with an error (get_last_init_error() then has the text). Never blocks.
int32_t vulkan_init_state() {
    if (!gInitDone.load(std::memory_order_acquire)) return 0;
    return gInitResult.load() == 1 ? 1 : -1;
}

// 1 = no valid pipeline cache was found (the shader is being compiled: slow, once), 0 = cache hit (fast). Valid a few ms after the init
// thread started; before that it reads 1 (the conservative answer). Never blocks.
int32_t vulkan_init_is_cold() { return gInitCold.load() ? 1 : 0; }

void process_image(const uint8_t* inputBytes, int32_t inWidth, int32_t inHeight,
                   uint8_t* outputBytes, int32_t outWidth, int32_t outHeight,
                   const float* uniforms, int32_t uniformCount,
                   const float* lutTable, int32_t lutCount) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);

    size_t pixelCount = static_cast<size_t>(outWidth * outHeight);

    if (!gVk.isInitialized || !ensureBuffersCapacity(pixelCount)) {
        executeCpuFallbackGrading(reinterpret_cast<const uint32_t*>(inputBytes),
                                  reinterpret_cast<uint32_t*>(outputBytes),
                                  outWidth, outHeight, uniforms);
        return;
    }

    size_t inputByteSize = pixelCount * sizeof(uint32_t);

    // 1. Upload Input Pixels
    void* mappedInput = nullptr;
    vkMapMemory(gVk.device, gVk.inMemory, 0, inputByteSize, 0, &mappedInput);
    std::memcpy(mappedInput, inputBytes, inputByteSize);
    VkMappedMemoryRange inRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.inMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &inRange);
    vkUnmapMemory(gVk.device, gVk.inMemory);

    // 2. Upload Uniforms (up to kUboFloats capacity)
    void* mappedUbo = nullptr;
    size_t uboCopyBytes = std::min(size_t(uniformCount * sizeof(float)), size_t(kUboFloats * sizeof(float)));
    vkMapMemory(gVk.device, gVk.uboMemory, 0, uboCopyBytes, 0, &mappedUbo);
    std::memcpy(mappedUbo, uniforms, uboCopyBytes);
    VkMappedMemoryRange uboRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.uboMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &uboRange);
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    // 3. Upload 3D Volumetric LUT directly into 3D Texture
    if (lutTable != nullptr && lutCount > 0) {
        uploadLutTo3DTexture(lutTable, lutCount);
    }

    // 4. Banded, checked GPU pipeline (clears buffers, short submits, reports failure)
    gFlareLayer = gFlareHalfEnabled ? findFlareLayer(uniforms, uniformCount) : -1;
    findTextWarpRows(uniforms, uniformCount);
    findBatch6Passes(uniforms, uniformCount);
    findBevel(uniforms, uniformCount); findMathGrad(uniforms, uniformCount);   // batch 13
    if (!runGpuPipeline(outWidth, outHeight)) {
        executeCpuFallbackGrading(reinterpret_cast<const uint32_t*>(inputBytes),
                                  reinterpret_cast<uint32_t*>(outputBytes),
                                  outWidth, outHeight, uniforms);
        return;
    }

    // 6. Read Back Output
    void* mappedOutput = nullptr;
    vkMapMemory(gVk.device, gVk.outMemory, 0, inputByteSize, 0, &mappedOutput);
    VkMappedMemoryRange outRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.outMemory, 0, VK_WHOLE_SIZE};
    vkInvalidateMappedMemoryRanges(gVk.device, 1, &outRange);
    std::memcpy(outputBytes, mappedOutput, inputByteSize);
    vkUnmapMemory(gVk.device, gVk.outMemory);
}

// -----------------------------------------------------------------------------
// Batch 12 step C1: TIME SLICE entry points (8-bit path). process_image / process_image_16 are NOT changed: with Time Slice off nothing here runs.
//   process_timeslice_ingest: grades ONE frame (passes 0..6, full grade, no dither) and stores the finished look in ring slot `slot` (0 .. ringSlots-1).
//   process_timeslice_emit:   needs a ring filled by ingest at the same size; runs pass 22 + pass 23 for the wipe state in `uniforms` and returns RGBA8.
// Both return 0 = ok, -1 = not available (GPU path missing, allocation failed, GPU error, ring not valid): the caller then grades normally.
// -----------------------------------------------------------------------------
int32_t process_timeslice_ingest(const uint8_t* inputBytes, int32_t w, int32_t h,
                                 const float* uniforms, int32_t uniformCount,
                                 const float* lutTable, int32_t lutCount,
                                 int32_t slot, int32_t ringSlots) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);
    if (!gVk.isInitialized || w <= 0 || h <= 0 || slot < 0 || ringSlots < 1 || slot >= ringSlots) return -1;
    const size_t pixelCount = static_cast<size_t>(w) * static_cast<size_t>(h);
    if (!ensureBuffersCapacity(pixelCount)) return -1;
    if (!ensureTimeSliceRing(pixelCount, ringSlots)) return -1;
    if (gTsRingW != w || gTsRingH != h || gTsRingSlots != ringSlots) { gTsRingW = w; gTsRingH = h; gTsRingSlots = ringSlots; }

    const size_t inputByteSize = pixelCount * sizeof(uint32_t);
    void* mappedInput = nullptr;
    vkMapMemory(gVk.device, gVk.inMemory, 0, inputByteSize, 0, &mappedInput);
    std::memcpy(mappedInput, inputBytes, inputByteSize);
    VkMappedMemoryRange inRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.inMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &inRange);
    vkUnmapMemory(gVk.device, gVk.inMemory);

    void* mappedUbo = nullptr;
    const size_t uboCopyBytes = std::min(size_t(uniformCount * sizeof(float)), size_t(kUboFloats * sizeof(float)));
    vkMapMemory(gVk.device, gVk.uboMemory, 0, uboCopyBytes, 0, &mappedUbo);
    std::memcpy(mappedUbo, uniforms, uboCopyBytes);
    if (uboCopyBytes > (kTsStatePackedFlag + 1) * sizeof(float)) static_cast<float*>(mappedUbo)[kTsStatePackedFlag] = gTsPacked ? 1.0f : 0.0f;   // C2: ring format for pass 24
    VkMappedMemoryRange uboRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.uboMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &uboRange);
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    if (lutTable != nullptr && lutCount > 0) uploadLutTo3DTexture(lutTable, lutCount);

    gFlareLayer = gFlareHalfEnabled ? findFlareLayer(uniforms, uniformCount) : -1;
    findTextWarpRows(uniforms, uniformCount);
    findBatch6Passes(uniforms, uniformCount);
    findBevel(uniforms, uniformCount); findMathGrad(uniforms, uniformCount);   // batch 13
    gTsStoreSlot = slot;
    const bool ok = runGpuPipeline(w, h);
    gTsStoreSlot = -1;
    if (!ok) { gTsRingW = gTsRingH = gTsRingSlots = 0; return -1; }
    return 0;
}

int32_t process_timeslice_emit(int32_t w, int32_t h, uint8_t* outputBytes, const float* uniforms, int32_t uniformCount) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);
    if (!gVk.isInitialized || gVk.inBuffer == VK_NULL_HANDLE || gTsRingW != w || gTsRingH != h || gTsRingSlots < 1) return -1;

    void* mappedUbo = nullptr;
    const size_t uboCopyBytes = std::min(size_t(uniformCount * sizeof(float)), size_t(kUboFloats * sizeof(float)));
    vkMapMemory(gVk.device, gVk.uboMemory, 0, uboCopyBytes, 0, &mappedUbo);
    std::memcpy(mappedUbo, uniforms, uboCopyBytes);
    if (uboCopyBytes > (kTsStatePackedFlag + 1) * sizeof(float)) static_cast<float*>(mappedUbo)[kTsStatePackedFlag] = gTsPacked ? 1.0f : 0.0f;   // C2: ring format for pass 22
    VkMappedMemoryRange uboRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.uboMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &uboRange);
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    findBevel(uniforms, uniformCount); findMathGrad(uniforms, uniformCount);   // batch 13: the wipe frame's UBO decides whether pass 25 + 26 run between pass 22 and pass 23
    if (!runTimeSliceEmit(w, h)) return -1;

    const size_t byteSize = static_cast<size_t>(w) * static_cast<size_t>(h) * sizeof(uint32_t);
    void* mappedOutput = nullptr;
    vkMapMemory(gVk.device, gVk.outMemory, 0, byteSize, 0, &mappedOutput);
    VkMappedMemoryRange outRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.outMemory, 0, VK_WHOLE_SIZE};
    vkInvalidateMappedMemoryRanges(gVk.device, 1, &outRange);
    std::memcpy(outputBytes, mappedOutput, byteSize);
    vkUnmapMemory(gVk.device, gVk.outMemory);
    return 0;
}

// C2: frees the ring (display buffer back to one frame). Safe to call at any time; does nothing when no ring exists.
int32_t process_timeslice_release() {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);
    if (!gVk.isInitialized) return -1;
    releaseTimeSliceRing();
    return 0;
}

// C2 debug: complete pass 23 runs since start. Must grow by exactly 1 per graded / emitted frame (proves the dither runs once per frame).
int32_t get_pass23_count() { return gPass23Count; }

void process_image_16(const uint16_t* inputBytes, int32_t inWidth, int32_t inHeight,
                      uint16_t* outputBytes, int32_t outWidth, int32_t outHeight,
                      const float* uniforms, int32_t uniformCount,
                      const float* lutTable, int32_t lutCount) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);

    size_t pixelCount = static_cast<size_t>(outWidth * outHeight);

    if (!gVk.isInitialized || !ensureBuffersCapacity(pixelCount)) {
        std::memcpy(outputBytes, inputBytes, pixelCount * 8);
        return;
    }

    size_t total16BitByteSize = pixelCount * 8; // 64 bpp

    // 1. Upload 16-bit Input
    void* mappedInput = nullptr;
    vkMapMemory(gVk.device, gVk.inMemory, 0, total16BitByteSize, 0, &mappedInput);
    std::memcpy(mappedInput, inputBytes, total16BitByteSize);
    VkMappedMemoryRange inRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.inMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &inRange);
    vkUnmapMemory(gVk.device, gVk.inMemory);

    // 2. Upload Uniforms (up to kUboFloats capacity)
    void* mappedUbo = nullptr;
    size_t uboCopyBytes = std::min(size_t(uniformCount * sizeof(float)), size_t(kUboFloats * sizeof(float)));
    vkMapMemory(gVk.device, gVk.uboMemory, 0, uboCopyBytes, 0, &mappedUbo);
    std::memcpy(mappedUbo, uniforms, uboCopyBytes);
    VkMappedMemoryRange uboRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.uboMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &uboRange);
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    // 3. Upload 3D Volumetric LUT directly into 3D Texture
    if (lutTable != nullptr && lutCount > 0) {
        uploadLutTo3DTexture(lutTable, lutCount);
    }

    // 4. Banded, checked GPU pipeline (clears buffers, short submits, reports failure)
    gFlareLayer = gFlareHalfEnabled ? findFlareLayer(uniforms, uniformCount) : -1;
    findTextWarpRows(uniforms, uniformCount);
    findBatch6Passes(uniforms, uniformCount);
    findBevel(uniforms, uniformCount); findMathGrad(uniforms, uniformCount);   // batch 13
    if (!runGpuPipeline(outWidth, outHeight)) {
        std::memcpy(outputBytes, inputBytes, pixelCount * 8);
        return;
    }

    // 6. Direct Read Back of Full 16-Bit Words (Zero Truncation)
    void* mappedOutput = nullptr;
    vkMapMemory(gVk.device, gVk.outMemory, 0, total16BitByteSize, 0, &mappedOutput);
    VkMappedMemoryRange outRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.outMemory, 0, VK_WHOLE_SIZE};
    vkInvalidateMappedMemoryRanges(gVk.device, 1, &outRange);
    std::memcpy(outputBytes, mappedOutput, total16BitByteSize);
    vkUnmapMemory(gVk.device, gVk.outMemory);
}

// Motion S (batch 9): one output frame. frames = frameCount packed 8-bit RGBA frames (w * h * 4 bytes each), centerIdx = the frame being
// rendered, uniforms = the FULL uniform buffer (kUboFloats floats) with the Motion S block filled in (see class MotionS). On any problem the
// centre frame is returned unchanged and get_last_render_status() reports it.
void process_motion(const uint8_t* frames, int32_t w, int32_t h, int32_t frameCount, int32_t centerIdx,
                    uint8_t* outputBytes, const float* uniforms, int32_t uniformCount) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);
    gLastRenderStatus = 0;
    const size_t px = (size_t)std::max(w, 0) * (size_t)std::max(h, 0);
    const size_t frameBytes = px * 4;
    if (frames == nullptr || outputBytes == nullptr || w <= 0 || h <= 0 || frameCount < 1 || centerIdx < 0 || centerIdx >= frameCount) {
        gLastRenderStatus = 1;
        return;
    }
    const uint8_t* curFrame = frames + (size_t)centerIdx * frameBytes;
    auto fallback = [&]() {
        std::memcpy(outputBytes, curFrame, frameBytes);
        if (gLastRenderStatus == 0) gLastRenderStatus = 1;
    };
    if (uniforms == nullptr || uniformCount < (int32_t)kUboFloats || !gVk.isInitialized || !ensureBuffersCapacity(px)) {
        fallback();
        return;
    }

    std::vector<float> ubo(uniforms, uniforms + kUboFloats);
    float* m = ubo.data() + kMotionBase;
    int32_t cell = (int32_t)m[12];
    cell = std::max<int32_t>(4, std::min<int32_t>(64, cell));
    m[12] = (float)cell;
    m[5] = (float)frameCount;
    m[6] = (float)centerIdx;
    const int32_t gw = (w + cell - 1) / cell;
    const int32_t gh = (h + cell - 1) / cell;
    const bool needFlow = m[9] > 0.5f;
    const bool needFwd = needFlow && m[10] > 0.5f;
    const int32_t ps = (int32_t)m[7], ns = (int32_t)m[8];
    if (ps >= frameCount) m[7] = -1.0f;
    if (ns >= frameCount) m[8] = -1.0f;

    const VkDeviceSize flowBytes = (VkDeviceSize)3 * (VkDeviceSize)gw * (VkDeviceSize)gh * 8 * sizeof(float);
    if (!ensureMotionBuffers((VkDeviceSize)frameCount * (VkDeviceSize)frameBytes, flowBytes)) {
        fallback();
        return;
    }

    // 1. global motion (CPU) -> uniform block
    for (int i = 128; i < 144; ++i) m[i] = 0.0f;
    if (needFlow) {
        float conf = 0.0f;
        if (ps >= 0 && ps < frameCount) {
            const MoSim s = moEstimate(curFrame, frames + (size_t)ps * frameBytes, w, h, &conf);
            moWriteT(m, 128, s, w, h, conf);
        }
        if (needFwd && ns >= 0 && ns < frameCount) {
            const MoSim s = moEstimate(curFrame, frames + (size_t)ns * frameBytes, w, h, &conf);
            moWriteT(m, 136, s, w, h, conf);
        }
    }

    // 2. uploads
    void* mapped = nullptr;
    if (vkMapMemory(gVk.device, gVk.motionFramesMemory, 0, (VkDeviceSize)frameCount * frameBytes, 0, &mapped) != VK_SUCCESS || mapped == nullptr) {
        fallback();
        return;
    }
    std::memcpy(mapped, frames, (size_t)frameCount * frameBytes);
    VkMappedMemoryRange fr{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.motionFramesMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &fr);
    vkUnmapMemory(gVk.device, gVk.motionFramesMemory);

    void* mappedUbo = nullptr;
    vkMapMemory(gVk.device, gVk.uboMemory, 0, kUboFloats * sizeof(float), 0, &mappedUbo);
    std::memcpy(mappedUbo, ubo.data(), kUboFloats * sizeof(float));
    VkMappedMemoryRange ur{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.uboMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &ur);
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    // 3. GPU
    gFlareLayer = -1;
    if (!runMotionPipeline(w, h, gw, gh, needFlow)) {
        fallback();
        return;
    }

    // 4. read back (render pass wrote w * h packed 8-bit RGBA words)
    void* mappedOut = nullptr;
    vkMapMemory(gVk.device, gVk.outMemory, 0, frameBytes, 0, &mappedOut);
    VkMappedMemoryRange orr{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.outMemory, 0, VK_WHOLE_SIZE};
    vkInvalidateMappedMemoryRanges(gVk.device, 1, &orr);
    std::memcpy(outputBytes, mappedOut, frameBytes);
    vkUnmapMemory(gVk.device, gVk.outMemory);
}

void cleanup_processor() {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);
    if (!gVk.isInitialized) return;

    cleanupBuffers();

    if (gVk.lutImageView != VK_NULL_HANDLE) {
        vkDestroyImageView(gVk.device, gVk.lutImageView, nullptr);
        gVk.lutImageView = VK_NULL_HANDLE;
    }
    if (gVk.lutImage != VK_NULL_HANDLE) {
        vkDestroyImage(gVk.device, gVk.lutImage, nullptr);
        gVk.lutImage = VK_NULL_HANDLE;
    }
    if (gVk.lutMemory != VK_NULL_HANDLE) {
        vkFreeMemory(gVk.device, gVk.lutMemory, nullptr);
        gVk.lutMemory = VK_NULL_HANDLE;
    }
    if (gVk.linearSampler != VK_NULL_HANDLE) {
        vkDestroySampler(gVk.device, gVk.linearSampler, nullptr);
        gVk.linearSampler = VK_NULL_HANDLE;
    }
    if (gVk.lutSampler != VK_NULL_HANDLE) {
        vkDestroySampler(gVk.device, gVk.lutSampler, nullptr);
        gVk.lutSampler = VK_NULL_HANDLE;
    }

    if (gVk.computeFence != VK_NULL_HANDLE) {
        vkDestroyFence(gVk.device, gVk.computeFence, nullptr);
        gVk.computeFence = VK_NULL_HANDLE;
    }
    if (gVk.commandPool != VK_NULL_HANDLE) {
        vkDestroyCommandPool(gVk.device, gVk.commandPool, nullptr);
        gVk.commandPool = VK_NULL_HANDLE;
    }
    if (gVk.descriptorPool != VK_NULL_HANDLE) {
        vkDestroyDescriptorPool(gVk.device, gVk.descriptorPool, nullptr);
        gVk.descriptorPool = VK_NULL_HANDLE;
    }
    if (gVk.computePipeline != VK_NULL_HANDLE) {
        vkDestroyPipeline(gVk.device, gVk.computePipeline, nullptr);
        gVk.computePipeline = VK_NULL_HANDLE;
    }
    if (gVk.pipelineCache != VK_NULL_HANDLE) {   // batch 17B
        vkDestroyPipelineCache(gVk.device, gVk.pipelineCache, nullptr);
        gVk.pipelineCache = VK_NULL_HANDLE;
    }
    if (gVk.pipelineLayout != VK_NULL_HANDLE) {
        vkDestroyPipelineLayout(gVk.device, gVk.pipelineLayout, nullptr);
        gVk.pipelineLayout = VK_NULL_HANDLE;
    }
    if (gVk.descriptorSetLayout != VK_NULL_HANDLE) {
        vkDestroyDescriptorSetLayout(gVk.device, gVk.descriptorSetLayout, nullptr);
        gVk.descriptorSetLayout = VK_NULL_HANDLE;
    }
    if (gVk.shaderModule != VK_NULL_HANDLE) {
        vkDestroyShaderModule(gVk.device, gVk.shaderModule, nullptr);
        gVk.shaderModule = VK_NULL_HANDLE;
    }
    if (gVk.device != VK_NULL_HANDLE) {
        vkDestroyDevice(gVk.device, nullptr);
        gVk.device = VK_NULL_HANDLE;
    }
    if (gVk.instance != VK_NULL_HANDLE) {
        vkDestroyInstance(gVk.instance, nullptr);
        gVk.instance = VK_NULL_HANDLE;
    }

    gVk.isInitialized = false;
    LOGI("AEReality Vulkan Processor Destroyed Cleanly.");
}

// JNI Bridge Exports
JNIEXPORT jboolean JNICALL
Java_com_example_aereality_VulkanBridge_initVulkan(JNIEnv* env, jobject thiz, jbyteArray shaderBytes, jint precisionMode) {
    jsize len = env->GetArrayLength(shaderBytes);
    jbyte* buf = env->GetByteArrayElements(shaderBytes, nullptr);
    int32_t res = init_vulkan(reinterpret_cast<const uint8_t*>(buf), len, precisionMode, nullptr);   // batch 17B: no cache dir through this legacy JNI entry
    env->ReleaseByteArrayElements(shaderBytes, buf, JNI_ABORT);
    return res == 1 ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_aereality_VulkanBridge_processImage(JNIEnv* env, jobject thiz,
                                                     jbyteArray inputPixels,
                                                     jint inWidth, jint inHeight,
                                                     jint outWidth, jint outHeight,
                                                     jfloatArray uniformData,
                                                     jfloatArray lutData) {
    size_t pixelCount = static_cast<size_t>(outWidth * outHeight);
    jbyte* inPtr = env->GetByteArrayElements(inputPixels, nullptr);
    jfloat* uboPtr = env->GetFloatArrayElements(uniformData, nullptr);
    jsize uboLen = env->GetArrayLength(uniformData);

    jfloat* lutPtr = nullptr;
    jsize lutLen = 0;
    if (lutData != nullptr) {
        lutLen = env->GetArrayLength(lutData);
        lutPtr = env->GetFloatArrayElements(lutData, nullptr);
    }

    jbyteArray resultByteArray = env->NewByteArray(pixelCount * sizeof(uint32_t));
    std::vector<uint8_t> outBuffer(pixelCount * sizeof(uint32_t));

    process_image(reinterpret_cast<const uint8_t*>(inPtr), inWidth, inHeight,
                  outBuffer.data(), outWidth, outHeight,
                  uboPtr, uboLen, lutPtr, lutLen);

    env->SetByteArrayRegion(resultByteArray, 0, pixelCount * sizeof(uint32_t),
                            reinterpret_cast<const jbyte*>(outBuffer.data()));

    env->ReleaseByteArrayElements(inputPixels, inPtr, JNI_ABORT);
    env->ReleaseFloatArrayElements(uniformData, uboPtr, JNI_ABORT);
    if (lutData != nullptr) {
        env->ReleaseFloatArrayElements(lutData, lutPtr, JNI_ABORT);
    }

    return resultByteArray;
}

JNIEXPORT void JNICALL
Java_com_example_aereality_VulkanBridge_destroyVulkan(JNIEnv* env, jobject thiz) {
    cleanup_processor();
}

} // extern "C"

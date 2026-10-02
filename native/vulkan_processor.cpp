#include <jni.h>
#include <android/log.h>
#include <vulkan/vulkan.h>
#include <vector>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <memory>
#include <mutex>

#define LOG_TAG "ShaderlyVulkan"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

struct ComputePushConstants {
    int32_t passIndex;
    int32_t passWidth;
    int32_t passHeight;
    float passRadius;
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

    // Bloom Pyramid Buffers
    VkBuffer bloomL0Buffer = VK_NULL_HANDLE;
    VkDeviceMemory bloomL0Memory = VK_NULL_HANDLE;
    VkBuffer bloomL1Buffer = VK_NULL_HANDLE;
    VkDeviceMemory bloomL1Memory = VK_NULL_HANDLE;
    VkBuffer bloomL2Buffer = VK_NULL_HANDLE;
    VkDeviceMemory bloomL2Memory = VK_NULL_HANDLE;

    // Intermediate Linear Composite
    VkBuffer tempCompositeBuffer = VK_NULL_HANDLE;
    VkDeviceMemory tempCompositeMemory = VK_NULL_HANDLE;

    size_t allocatedPixelCapacity = 0;
    bool isInitialized = false;
    bool lutUploaded = false;
    std::mutex pipelineMutex;
};

static VulkanContext gVk;

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
    // 1. Linear Clamp-To-Edge Sampler (Standard for 2D Blurs, Downsampling & Edge Glows)
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

    // 2. Hardware 3D LUT Trilinear Sampler
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

    // 32 x 32 x 32 3D Texture Image
    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = VK_IMAGE_TYPE_3D;
    imageInfo.extent.width = 32;
    imageInfo.extent.height = 32;
    imageInfo.extent.depth = 32;
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
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

    // Create 3D View
    VkImageViewCreateInfo viewInfo{};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = gVk.lutImage;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_3D;
    viewInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
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
    safeDestroy(gVk.tempCompositeBuffer, gVk.tempCompositeMemory);

    gVk.allocatedPixelCapacity = 0;
}

bool ensureBuffersCapacity(size_t requiredPixels) {
    if (gVk.allocatedPixelCapacity >= requiredPixels && gVk.inBuffer != VK_NULL_HANDLE) {
        return true;
    }

    cleanupBuffers();

    VkDeviceSize pixelBufferSize = requiredPixels * 8; // 64bpp for up to 16-bit float/int
    VkDeviceSize uboBufferSize = 1024 * sizeof(float); // Expanded for 10 layers
    VkDeviceSize lutStagingSize = 32 * 32 * 32 * 4 * sizeof(float); // RGBA32F 3D table

    VkDeviceSize l0Size = ((requiredPixels / 4) + 64) * sizeof(uint32_t);
    VkDeviceSize l1Size = ((requiredPixels / 16) + 64) * sizeof(uint32_t);
    VkDeviceSize l2Size = ((requiredPixels / 64) + 64) * sizeof(uint32_t);

    createBuffer(gVk.device, gVk.physicalDevice, pixelBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.inBuffer, gVk.inMemory);

    createBuffer(gVk.device, gVk.physicalDevice, pixelBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
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
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.bloomL0Buffer, gVk.bloomL0Memory);

    createBuffer(gVk.device, gVk.physicalDevice, l1Size,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.bloomL1Buffer, gVk.bloomL1Memory);

    createBuffer(gVk.device, gVk.physicalDevice, l2Size,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.bloomL2Buffer, gVk.bloomL2Memory);

    createBuffer(gVk.device, gVk.physicalDevice, pixelBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                 gVk.tempCompositeBuffer, gVk.tempCompositeMemory);

    create3DLutImage();

    // Descriptor Writes for all bindings
    VkDescriptorBufferInfo inBufferInfo{gVk.inBuffer, 0, pixelBufferSize};
    VkDescriptorBufferInfo outBufferInfo{gVk.outBuffer, 0, pixelBufferSize};
    VkDescriptorBufferInfo uboBufferInfo{gVk.uboBuffer, 0, uboBufferSize};
    VkDescriptorImageInfo lutImageInfo{gVk.lutSampler, gVk.lutImageView, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkDescriptorBufferInfo l0BufferInfo{gVk.bloomL0Buffer, 0, l0Size};
    VkDescriptorBufferInfo l1BufferInfo{gVk.bloomL1Buffer, 0, l1Size};
    VkDescriptorBufferInfo l2BufferInfo{gVk.bloomL2Buffer, 0, l2Size};
    VkDescriptorBufferInfo tempCompInfo{gVk.tempCompositeBuffer, 0, pixelBufferSize};

    VkWriteDescriptorSet descriptorWrites[8]{};

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

    // Binding 3: True Hardware 3D LUT Combined Image Sampler
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

    vkUpdateDescriptorSets(gVk.device, 8, descriptorWrites, 0, nullptr);

    gVk.allocatedPixelCapacity = requiredPixels;
    LOGI("Configured Vulkan Samplers, 3D LUT Image, and Buffers for %zu pixels.", requiredPixels);
    return true;
}

float cpuSrgbToLinear(float c) {
    return (c <= 0.04045f) ? (c / 12.92f) : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

float cpuLinearToSrgb(float c) {
    c = std::max(0.0f, std::min(1.0f, c));
    return (c <= 0.0031308f) ? (c * 12.92f) : (1.055f * std::pow(c, 1.0f / 2.4f) - 0.055f);
}

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
                int off = 32 + (l * 96);
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

void uploadLutTo3DTexture(const float* lutTable, int32_t lutCount) {
    if (lutTable == nullptr || lutCount <= 0 || gVk.lutImage == VK_NULL_HANDLE) return;

    size_t totalPoints = 32 * 32 * 32;
    std::vector<float> rgbaLut(totalPoints * 4);

    // Expand RGB triplets to RGBA32F for optimal 3D GPU alignment
    for (size_t i = 0; i < totalPoints; i++) {
        if ((i * 3 + 2) < (size_t)lutCount) {
            rgbaLut[i * 4 + 0] = lutTable[i * 3 + 0];
            rgbaLut[i * 4 + 1] = lutTable[i * 3 + 1];
            rgbaLut[i * 4 + 2] = lutTable[i * 3 + 2];
            rgbaLut[i * 4 + 3] = 1.0f;
        }
    }

    size_t copyBytes = rgbaLut.size() * sizeof(float);
    void* mappedStaging = nullptr;
    vkMapMemory(gVk.device, gVk.lutStagingMemory, 0, copyBytes, 0, &mappedStaging);
    std::memcpy(mappedStaging, rgbaLut.data(), copyBytes);
    VkMappedMemoryRange range{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.lutStagingMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &range);
    vkUnmapMemory(gVk.device, gVk.lutStagingMemory);

    // Transition 3D Image & Copy from Staging
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
    LOGI("Uploaded 3D Volumetric LUT directly to hardware sampler.");
}

} // namespace

extern "C" {

int32_t init_vulkan(const uint8_t* shaderBytes, int32_t length, int32_t precision) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);

    if (gVk.isInitialized) return 1;

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

    if (vkCreateInstance(&createInfo, nullptr, &gVk.instance) != VK_SUCCESS) {
        LOGE("Failed to create Vulkan instance.");
        return 0;
    }

    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(gVk.instance, &deviceCount, nullptr);
    if (deviceCount == 0) return 0;

    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(gVk.instance, &deviceCount, devices.data());
    gVk.physicalDevice = devices[0];

    uint32_t queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(gVk.physicalDevice, &queueFamilyCount, nullptr);
    std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(gVk.physicalDevice, &queueFamilyCount, queueFamilies.data());

    for (uint32_t i = 0; i < queueFamilyCount; i++) {
        if (queueFamilies[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
            gVk.computeQueueFamilyIndex = i;
            break;
        }
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

    if (vkCreateDevice(gVk.physicalDevice, &deviceCreateInfo, nullptr, &gVk.device) != VK_SUCCESS) {
        LOGE("Failed to create logical device.");
        return 0;
    }

    vkGetDeviceQueue(gVk.device, gVk.computeQueueFamilyIndex, 0, &gVk.computeQueue);

    createHardwareSamplers();

    VkShaderModuleCreateInfo shaderModuleInfo{};
    shaderModuleInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    shaderModuleInfo.codeSize = length;
    shaderModuleInfo.pCode = reinterpret_cast<const uint32_t*>(shaderBytes);

    if (vkCreateShaderModule(gVk.device, &shaderModuleInfo, nullptr, &gVk.shaderModule) != VK_SUCCESS) {
        LOGE("Failed to create shader module.");
        return 0;
    }

    // 8 Bindings with hardware sampler at Binding 3
    VkDescriptorSetLayoutBinding bindings[8]{};
    for (int b = 0; b < 8; b++) {
        bindings[b].binding = b;
        bindings[b].descriptorType = (b == 3) ? VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER : VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        bindings[b].descriptorCount = 1;
        bindings[b].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    }

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 8;
    layoutInfo.pBindings = bindings;
    vkCreateDescriptorSetLayout(gVk.device, &layoutInfo, nullptr, &gVk.descriptorSetLayout);

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
    vkCreatePipelineLayout(gVk.device, &pipelineLayoutInfo, nullptr, &gVk.pipelineLayout);

    VkComputePipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipelineInfo.layout = gVk.pipelineLayout;
    pipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipelineInfo.stage.module = gVk.shaderModule;
    pipelineInfo.stage.pName = "main";
    vkCreateComputePipelines(gVk.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &gVk.computePipeline);

    VkDescriptorPoolSize poolSizes[2]{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    poolSizes[0].descriptorCount = 7;
    poolSizes[1].type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    poolSizes[1].descriptorCount = 1;

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.poolSizeCount = 2;
    poolInfo.pPoolSizes = poolSizes;
    poolInfo.maxSets = 1;
    vkCreateDescriptorPool(gVk.device, &poolInfo, nullptr, &gVk.descriptorPool);

    VkDescriptorSetAllocateInfo setAllocInfo{};
    setAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    setAllocInfo.descriptorPool = gVk.descriptorPool;
    setAllocInfo.descriptorSetCount = 1;
    setAllocInfo.pSetLayouts = &gVk.descriptorSetLayout;
    vkAllocateDescriptorSets(gVk.device, &setAllocInfo, &gVk.descriptorSet);

    VkCommandPoolCreateInfo cmdPoolInfo{};
    cmdPoolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cmdPoolInfo.queueFamilyIndex = gVk.computeQueueFamilyIndex;
    cmdPoolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    vkCreateCommandPool(gVk.device, &cmdPoolInfo, nullptr, &gVk.commandPool);

    VkCommandBufferAllocateInfo cmdAllocInfo{};
    cmdAllocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAllocInfo.commandPool = gVk.commandPool;
    cmdAllocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAllocInfo.commandBufferCount = 1;
    vkAllocateCommandBuffers(gVk.device, &cmdAllocInfo, &gVk.commandBuffer);

    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = 0;
    vkCreateFence(gVk.device, &fenceInfo, nullptr, &gVk.computeFence);

    gVk.isInitialized = true;
    LOGI("Vulkan Pipeline with Hardware Samplers & 3D LUT Texture Initialized.");
    return 1;
}

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

    // 2. Upload Uniforms (1024 floats capacity for 10 layers)
    void* mappedUbo = nullptr;
    size_t uboCopyBytes = std::min(size_t(uniformCount * sizeof(float)), size_t(1024 * sizeof(float)));
    vkMapMemory(gVk.device, gVk.uboMemory, 0, uboCopyBytes, 0, &mappedUbo);
    std::memcpy(mappedUbo, uniforms, uboCopyBytes);
    VkMappedMemoryRange uboRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.uboMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &uboRange);
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    // 3. Upload 3D Volumetric LUT directly into 3D Texture
    if (lutTable != nullptr && lutCount > 0) {
        uploadLutTo3DTexture(lutTable, lutCount);
    }

    // 4. Record Multi-Pass Compute Commands with integer bit-shifts (>> 1)
    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    vkBeginCommandBuffer(gVk.commandBuffer, &beginInfo);
    vkCmdBindPipeline(gVk.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, gVk.computePipeline);
    vkCmdBindDescriptorSets(gVk.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                            gVk.pipelineLayout, 0, 1, &gVk.descriptorSet, 0, nullptr);

    auto insertBarrier = []() {
        VkMemoryBarrier memoryBarrier{};
        memoryBarrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
        memoryBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        memoryBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(gVk.commandBuffer,
                             VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                             VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                             0, 1, &memoryBarrier, 0, nullptr, 0, nullptr);
    };

    int32_t wL0 = std::max(1, outWidth >> 1);
    int32_t hL0 = std::max(1, outHeight >> 1);
    int32_t wL1 = std::max(1, outWidth >> 2);
    int32_t hL1 = std::max(1, outHeight >> 2);
    int32_t wL2 = std::max(1, outWidth >> 3);
    int32_t hL2 = std::max(1, outHeight >> 3);

    ComputePushConstants pc{};

    // Pass 0: Primary Grade & Input Restoration -> TempCompositeBuffer
    pc = {0, outWidth, outHeight, 1.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (outWidth + 15) / 16, (outHeight + 15) / 16, 1);
    insertBarrier();

    // Pass 1: Karis-Weighted Highlight Extraction -> Bloom L0
    pc = {1, wL0, hL0, 1.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL0 + 15) / 16, (hL0 + 15) / 16, 1);
    insertBarrier();

    // Pass 2: 13-Tap Anti-Grid Downsample L0 -> L1
    pc = {2, wL1, hL1, 1.5f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL1 + 15) / 16, (hL1 + 15) / 16, 1);
    insertBarrier();

    // Pass 3: 13-Tap Anti-Grid Downsample L1 -> L2
    pc = {3, wL2, hL2, 2.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL2 + 15) / 16, (hL2 + 15) / 16, 1);
    insertBarrier();

    // Pass 4: Continuous Upsample L2 -> L1
    pc = {4, wL1, hL1, 2.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL1 + 15) / 16, (hL1 + 15) / 16, 1);
    insertBarrier();

    // Pass 5: Continuous Upsample L1 -> L0
    pc = {5, wL0, hL0, 1.5f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL0 + 15) / 16, (hL0 + 15) / 16, 1);
    insertBarrier();

    // Pass 6: Master Composite, FXAA, Tonemap & IGN Dither -> outBuffer
    pc = {6, outWidth, outHeight, 1.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (outWidth + 15) / 16, (outHeight + 15) / 16, 1);

    vkEndCommandBuffer(gVk.commandBuffer);

    // 5. Submit with Fence Synchronization
    vkResetFences(gVk.device, 1, &gVk.computeFence);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &gVk.commandBuffer;

    vkQueueSubmit(gVk.computeQueue, 1, &submitInfo, gVk.computeFence);
    vkWaitForFences(gVk.device, 1, &gVk.computeFence, VK_TRUE, UINT64_MAX);

    // 6. Read Back Output
    void* mappedOutput = nullptr;
    vkMapMemory(gVk.device, gVk.outMemory, 0, inputByteSize, 0, &mappedOutput);
    VkMappedMemoryRange outRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.outMemory, 0, VK_WHOLE_SIZE};
    vkInvalidateMappedMemoryRanges(gVk.device, 1, &outRange);
    std::memcpy(outputBytes, mappedOutput, inputByteSize);
    vkUnmapMemory(gVk.device, gVk.outMemory);
}

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

    // 1. Direct Upload of Pure 16-bit Input
    void* mappedInput = nullptr;
    vkMapMemory(gVk.device, gVk.inMemory, 0, total16BitByteSize, 0, &mappedInput);
    std::memcpy(mappedInput, inputBytes, total16BitByteSize);
    VkMappedMemoryRange inRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.inMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &inRange);
    vkUnmapMemory(gVk.device, gVk.inMemory);

    // 2. Upload Uniforms (1024 floats capacity)
    void* mappedUbo = nullptr;
    size_t uboCopyBytes = std::min(size_t(uniformCount * sizeof(float)), size_t(1024 * sizeof(float)));
    vkMapMemory(gVk.device, gVk.uboMemory, 0, uboCopyBytes, 0, &mappedUbo);
    std::memcpy(mappedUbo, uniforms, uboCopyBytes);
    VkMappedMemoryRange uboRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.uboMemory, 0, VK_WHOLE_SIZE};
    vkFlushMappedMemoryRanges(gVk.device, 1, &uboRange);
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    // 3. Upload 3D Volumetric LUT directly into 3D Texture
    if (lutTable != nullptr && lutCount > 0) {
        uploadLutTo3DTexture(lutTable, lutCount);
    }

    // 4. Record Multi-Pass Compute Commands with integer bit-shifts (>> 1)
    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    vkBeginCommandBuffer(gVk.commandBuffer, &beginInfo);
    vkCmdBindPipeline(gVk.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, gVk.computePipeline);
    vkCmdBindDescriptorSets(gVk.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                            gVk.pipelineLayout, 0, 1, &gVk.descriptorSet, 0, nullptr);

    auto insertBarrier = []() {
        VkMemoryBarrier memoryBarrier{};
        memoryBarrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
        memoryBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        memoryBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(gVk.commandBuffer,
                             VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                             VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                             0, 1, &memoryBarrier, 0, nullptr, 0, nullptr);
    };

    int32_t wL0 = std::max(1, outWidth >> 1);
    int32_t hL0 = std::max(1, outHeight >> 1);
    int32_t wL1 = std::max(1, outWidth >> 2);
    int32_t hL1 = std::max(1, outHeight >> 2);
    int32_t wL2 = std::max(1, outWidth >> 3);
    int32_t hL2 = std::max(1, outHeight >> 3);

    ComputePushConstants pc{};

    // Pass 0: 16-Bit Primary Color Grade & Input Restoration -> TempCompositeBuffer
    pc = {0, outWidth, outHeight, 1.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (outWidth + 15) / 16, (outHeight + 15) / 16, 1);
    insertBarrier();

    // Pass 1: Karis-Weighted Highlight Extraction -> Bloom L0
    pc = {1, wL0, hL0, 1.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL0 + 15) / 16, (hL0 + 15) / 16, 1);
    insertBarrier();

    // Pass 2: 13-Tap Anti-Grid Downsample L0 -> L1
    pc = {2, wL1, hL1, 1.5f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL1 + 15) / 16, (hL1 + 15) / 16, 1);
    insertBarrier();

    // Pass 3: 13-Tap Anti-Grid Downsample L1 -> L2
    pc = {3, wL2, hL2, 2.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL2 + 15) / 16, (hL2 + 15) / 16, 1);
    insertBarrier();

    // Pass 4: Continuous Upsample L2 -> L1
    pc = {4, wL1, hL1, 2.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL1 + 15) / 16, (hL1 + 15) / 16, 1);
    insertBarrier();

    // Pass 5: Continuous Upsample L1 -> L0
    pc = {5, wL0, hL0, 1.5f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (wL0 + 15) / 16, (hL0 + 15) / 16, 1);
    insertBarrier();

    // Pass 6: Master Composite & 16-Bit Tonemapped Pack with IGN Dither -> outBuffer
    pc = {6, outWidth, outHeight, 1.0f};
    vkCmdPushConstants(gVk.commandBuffer, gVk.pipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(ComputePushConstants), &pc);
    vkCmdDispatch(gVk.commandBuffer, (outWidth + 15) / 16, (outHeight + 15) / 16, 1);

    vkEndCommandBuffer(gVk.commandBuffer);

    // 5. Submit with Fence Synchronization
    vkResetFences(gVk.device, 1, &gVk.computeFence);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &gVk.commandBuffer;

    vkQueueSubmit(gVk.computeQueue, 1, &submitInfo, gVk.computeFence);
    vkWaitForFences(gVk.device, 1, &gVk.computeFence, VK_TRUE, UINT64_MAX);

    // 6. Direct Read Back of Full 16-Bit Words (Zero Truncation)
    void* mappedOutput = nullptr;
    vkMapMemory(gVk.device, gVk.outMemory, 0, total16BitByteSize, 0, &mappedOutput);
    VkMappedMemoryRange outRange{VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE, nullptr, gVk.outMemory, 0, VK_WHOLE_SIZE};
    vkInvalidateMappedMemoryRanges(gVk.device, 1, &outRange);
    std::memcpy(outputBytes, mappedOutput, total16BitByteSize);
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
    int32_t res = init_vulkan(reinterpret_cast<const uint8_t*>(buf), len, precisionMode);
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

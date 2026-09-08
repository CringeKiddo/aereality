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

    // Buffers: In, Out, Uniforms, 3D LUT
    VkBuffer inBuffer = VK_NULL_HANDLE;
    VkDeviceMemory inMemory = VK_NULL_HANDLE;
    VkBuffer outBuffer = VK_NULL_HANDLE;
    VkDeviceMemory outMemory = VK_NULL_HANDLE;
    VkBuffer uboBuffer = VK_NULL_HANDLE;
    VkDeviceMemory uboMemory = VK_NULL_HANDLE;
    VkBuffer lutBuffer = VK_NULL_HANDLE;
    VkDeviceMemory lutMemory = VK_NULL_HANDLE;

    size_t allocatedPixelCapacity = 0;
    bool isInitialized = false;
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
    LOGE("Failed to find suitable memory type!");
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
        LOGE("Failed to create Vulkan buffer!");
        return;
    }

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(device, buffer, &memRequirements);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = findMemoryType(physicalDevice, memRequirements.memoryTypeBits, properties);

    if (vkAllocateMemory(device, &allocInfo, nullptr, &bufferMemory) != VK_SUCCESS) {
        LOGE("Failed to allocate Vulkan memory!");
        return;
    }

    vkBindBufferMemory(device, buffer, bufferMemory, 0);
}

void cleanupBuffers() {
    if (gVk.device == VK_NULL_HANDLE) return;

    if (gVk.inBuffer != VK_NULL_HANDLE) {
        vkDestroyBuffer(gVk.device, gVk.inBuffer, nullptr);
        gVk.inBuffer = VK_NULL_HANDLE;
    }
    if (gVk.inMemory != VK_NULL_HANDLE) {
        vkFreeMemory(gVk.device, gVk.inMemory, nullptr);
        gVk.inMemory = VK_NULL_HANDLE;
    }
    if (gVk.outBuffer != VK_NULL_HANDLE) {
        vkDestroyBuffer(gVk.device, gVk.outBuffer, nullptr);
        gVk.outBuffer = VK_NULL_HANDLE;
    }
    if (gVk.outMemory != VK_NULL_HANDLE) {
        vkFreeMemory(gVk.device, gVk.outMemory, nullptr);
        gVk.outMemory = VK_NULL_HANDLE;
    }
    if (gVk.uboBuffer != VK_NULL_HANDLE) {
        vkDestroyBuffer(gVk.device, gVk.uboBuffer, nullptr);
        gVk.uboBuffer = VK_NULL_HANDLE;
    }
    if (gVk.uboMemory != VK_NULL_HANDLE) {
        vkFreeMemory(gVk.device, gVk.uboMemory, nullptr);
        gVk.uboMemory = VK_NULL_HANDLE;
    }
    if (gVk.lutBuffer != VK_NULL_HANDLE) {
        vkDestroyBuffer(gVk.device, gVk.lutBuffer, nullptr);
        gVk.lutBuffer = VK_NULL_HANDLE;
    }
    if (gVk.lutMemory != VK_NULL_HANDLE) {
        vkFreeMemory(gVk.device, gVk.lutMemory, nullptr);
        gVk.lutMemory = VK_NULL_HANDLE;
    }
    gVk.allocatedPixelCapacity = 0;
}

bool ensureBuffersCapacity(size_t requiredPixels) {
    if (gVk.allocatedPixelCapacity >= requiredPixels && gVk.inBuffer != VK_NULL_HANDLE) {
        return true;
    }

    cleanupBuffers();

    VkDeviceSize pixelBufferSize = requiredPixels * sizeof(uint32_t);
    VkDeviceSize uboBufferSize = 512 * sizeof(float); // 2048 bytes (Matches 4x aligned LayerData structs)
    VkDeviceSize lutBufferSize = 32 * 32 * 32 * 3 * sizeof(float); // 98,304 floats (393,216 bytes)

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

    createBuffer(gVk.device, gVk.physicalDevice, lutBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.lutBuffer, gVk.lutMemory);

    VkDescriptorBufferInfo inBufferInfo{};
    inBufferInfo.buffer = gVk.inBuffer;
    inBufferInfo.offset = 0;
    inBufferInfo.range = pixelBufferSize;

    VkDescriptorBufferInfo outBufferInfo{};
    outBufferInfo.buffer = gVk.outBuffer;
    outBufferInfo.offset = 0;
    outBufferInfo.range = pixelBufferSize;

    VkDescriptorBufferInfo uboBufferInfo{};
    uboBufferInfo.buffer = gVk.uboBuffer;
    uboBufferInfo.offset = 0;
    uboBufferInfo.range = uboBufferSize;

    VkDescriptorBufferInfo lutBufferInfo{};
    lutBufferInfo.buffer = gVk.lutBuffer;
    lutBufferInfo.offset = 0;
    lutBufferInfo.range = lutBufferSize;

    VkWriteDescriptorSet descriptorWrites[4]{};

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
    descriptorWrites[3].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    descriptorWrites[3].descriptorCount = 1;
    descriptorWrites[3].pBufferInfo = &lutBufferInfo;

    vkUpdateDescriptorSets(gVk.device, 4, descriptorWrites, 0, nullptr);

    gVk.allocatedPixelCapacity = requiredPixels;
    LOGI("Vulkan Frame & LUT Buffers Allocated for %zu pixels.", requiredPixels);
    return true;
}

// 32-bit Floating Point CPU Fallback Grading Pipeline
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

            float r = (pixel & 0xFF) / 255.0f;
            float g = ((pixel >> 8) & 0xFF) / 255.0f;
            float b = ((pixel >> 16) & 0xFF) / 255.0f;
            float a = ((pixel >> 24) & 0xFF) / 255.0f;

            for (int l = 0; l < std::min(layerCount, 4); l++) {
                int off = 8 + (l * 64);
                if (ubo[off + 0] < 0.5f) continue;

                float opacity = ubo[off + 1];
                int mode = static_cast<int>(ubo[off + 2]);
                float brightness = ubo[off + 3];
                float saturation = ubo[off + 4];
                float contrast = ubo[off + 5];
                float gamma = std::max(0.001f, ubo[off + 7]);

                float lr = r + brightness;
                float lg = g + brightness;
                float lb = b + brightness;

                lr = (lr - 0.18f) * contrast + 0.18f;
                lg = (lg - 0.18f) * contrast + 0.18f;
                lb = (lb - 0.18f) * contrast + 0.18f;

                lr = std::pow(std::max(0.0f, lr), 1.0f / gamma);
                lg = std::pow(std::max(0.0f, lg), 1.0f / gamma);
                lb = std::pow(std::max(0.0f, lb), 1.0f / gamma);

                float luma = 0.299f * lr + 0.587f * lg + 0.114f * lb;
                lr = luma + saturation * (lr - luma);
                lg = luma + saturation * (lg - luma);
                lb = luma + saturation * (lb - luma);

                if (mode == 1) { // Screen
                    r = 1.0f - (1.0f - r) * (1.0f - lr * opacity);
                    g = 1.0f - (1.0f - g) * (1.0f - lg * opacity);
                    b = 1.0f - (1.0f - b) * (1.0f - lb * opacity);
                } else if (mode == 2) { // Linear Add
                    r = std::min(1.0f, r + lr * opacity);
                    g = std::min(1.0f, g + lg * opacity);
                    b = std::min(1.0f, b + lb * opacity);
                } else { // Normal
                    r = r * (1.0f - opacity) + lr * opacity;
                    g = g * (1.0f - opacity) + lg * opacity;
                    b = b * (1.0f - opacity) + lb * opacity;
                }
            }

            uint32_t ur = static_cast<uint32_t>(std::max(0.0f, std::min(255.0f, r * 255.0f)));
            uint32_t ug = static_cast<uint32_t>(std::max(0.0f, std::min(255.0f, g * 255.0f)));
            uint32_t ub = static_cast<uint32_t>(std::max(0.0f, std::min(255.0f, b * 255.0f)));
            uint32_t ua = static_cast<uint32_t>(std::max(0.0f, std::min(255.0f, a * 255.0f)));

            dst[idx] = (ua << 24) | (ub << 16) | (ug << 8) | ur;
        }
    }
}

} // namespace

extern "C" {

int32_t init_vulkan(const uint8_t* shaderBytes, int32_t length, int32_t precision) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);

    if (gVk.isInitialized) return 1;

    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "ShaderlyCore";
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

    bool foundQueue = false;
    for (uint32_t i = 0; i < queueFamilyCount; i++) {
        if (queueFamilies[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
            gVk.computeQueueFamilyIndex = i;
            foundQueue = true;
            break;
        }
    }
    if (!foundQueue) return 0;

    float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo queueCreateInfo{};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = gVk.computeQueueFamilyIndex;
    queueCreateInfo.queueCount = 1;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    VkDeviceCreateInfo deviceCreateInfo{};
    deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    deviceCreateInfo.queueCreateInfoCount = 1;
    deviceCreateInfo.pQueueCreateInfos = &queueCreateInfo;

    if (vkCreateDevice(gVk.physicalDevice, &deviceCreateInfo, nullptr, &gVk.device) != VK_SUCCESS) {
        return 0;
    }

    vkGetDeviceQueue(gVk.device, gVk.computeQueueFamilyIndex, 0, &gVk.computeQueue);

    VkShaderModuleCreateInfo shaderModuleInfo{};
    shaderModuleInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    shaderModuleInfo.codeSize = length;
    shaderModuleInfo.pCode = reinterpret_cast<const uint32_t*>(shaderBytes);

    if (vkCreateShaderModule(gVk.device, &shaderModuleInfo, nullptr, &gVk.shaderModule) != VK_SUCCESS) {
        return 0;
    }

    // 4 Storage Buffer Bindings: 0=Input, 1=Output, 2=Uniforms, 3=LUT
    VkDescriptorSetLayoutBinding bindings[4]{};
    for (int b = 0; b < 4; b++) {
        bindings[b].binding = b;
        bindings[b].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        bindings[b].descriptorCount = 1;
        bindings[b].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    }

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 4;
    layoutInfo.pBindings = bindings;

    vkCreateDescriptorSetLayout(gVk.device, &layoutInfo, nullptr, &gVk.descriptorSetLayout);

    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &gVk.descriptorSetLayout;

    vkCreatePipelineLayout(gVk.device, &pipelineLayoutInfo, nullptr, &gVk.pipelineLayout);

    VkComputePipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipelineInfo.layout = gVk.pipelineLayout;
    pipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipelineInfo.stage.module = gVk.shaderModule;
    pipelineInfo.stage.pName = "main";

    vkCreateComputePipelines(gVk.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &gVk.computePipeline);

    VkDescriptorPoolSize poolSizes[1]{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    poolSizes[0].descriptorCount = 4;

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.poolSizeCount = 1;
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

    gVk.isInitialized = true;
    LOGI("Shaderly 4-Slot Vulkan Compute Pipeline Initialized.");
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

    void* mappedInput = nullptr;
    vkMapMemory(gVk.device, gVk.inMemory, 0, pixelCount * sizeof(uint32_t), 0, &mappedInput);
    std::memcpy(mappedInput, inputBytes, pixelCount * sizeof(uint32_t));
    vkUnmapMemory(gVk.device, gVk.inMemory);

    void* mappedUbo = nullptr;
    vkMapMemory(gVk.device, gVk.uboMemory, 0, std::min(size_t(uniformCount * sizeof(float)), size_t(512 * sizeof(float))), 0, &mappedUbo);
    std::memcpy(mappedUbo, uniforms, std::min(size_t(uniformCount * sizeof(float)), size_t(512 * sizeof(float))));
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    if (lutTable != nullptr && lutCount > 0) {
        void* mappedLut = nullptr;
        vkMapMemory(gVk.device, gVk.lutMemory, 0, std::min(size_t(lutCount * sizeof(float)), size_t(32 * 32 * 32 * 3 * sizeof(float))), 0, &mappedLut);
        std::memcpy(mappedLut, lutTable, std::min(size_t(lutCount * sizeof(float)), size_t(32 * 32 * 32 * 3 * sizeof(float))));
        vkUnmapMemory(gVk.device, gVk.lutMemory);
    }

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    vkBeginCommandBuffer(gVk.commandBuffer, &beginInfo);
    vkCmdBindPipeline(gVk.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, gVk.computePipeline);
    vkCmdBindDescriptorSets(gVk.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE,
                            gVk.pipelineLayout, 0, 1, &gVk.descriptorSet, 0, nullptr);

    uint32_t groupCountX = (outWidth + 15) / 16;
    uint32_t groupCountY = (outHeight + 15) / 16;
    vkCmdDispatch(gVk.commandBuffer, groupCountX, groupCountY, 1);
    vkEndCommandBuffer(gVk.commandBuffer);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &gVk.commandBuffer;

    vkQueueSubmit(gVk.computeQueue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(gVk.computeQueue);

    void* mappedOutput = nullptr;
    vkMapMemory(gVk.device, gVk.outMemory, 0, pixelCount * sizeof(uint32_t), 0, &mappedOutput);
    std::memcpy(outputBytes, mappedOutput, pixelCount * sizeof(uint32_t));
    vkUnmapMemory(gVk.device, gVk.outMemory);
}

void process_image_16(const uint16_t* inputBytes, int32_t inWidth, int32_t inHeight,
                      uint16_t* outputBytes, int32_t outWidth, int32_t outHeight,
                      const float* uniforms, int32_t uniformCount,
                      const float* lutTable, int32_t lutCount) {
    size_t pixelCount = static_cast<size_t>(outWidth * outHeight);
    std::vector<uint32_t> stage8In(pixelCount);
    std::vector<uint32_t> stage8Out(pixelCount);

    #pragma omp parallel for
    for (size_t p = 0; p < pixelCount; p++) {
        uint8_t r = static_cast<uint8_t>(inputBytes[p * 4 + 0] >> 8);
        uint8_t g = static_cast<uint8_t>(inputBytes[p * 4 + 1] >> 8);
        uint8_t b = static_cast<uint8_t>(inputBytes[p * 4 + 2] >> 8);
        uint8_t a = static_cast<uint8_t>(inputBytes[p * 4 + 3] >> 8);
        stage8In[p] = (a << 24) | (b << 16) | (g << 8) | r;
    }

    process_image(reinterpret_cast<const uint8_t*>(stage8In.data()), inWidth, inHeight,
                  reinterpret_cast<uint8_t*>(stage8Out.data()), outWidth, outHeight,
                  uniforms, uniformCount, lutTable, lutCount);

    #pragma omp parallel for
    for (size_t p = 0; p < pixelCount; p++) {
        uint32_t pix = stage8Out[p];
        uint16_t r8 = (pix & 0xFF);
        uint16_t g8 = ((pix >> 8) & 0xFF);
        uint16_t b8 = ((pix >> 16) & 0xFF);
        uint16_t a8 = ((pix >> 24) & 0xFF);

        outputBytes[p * 4 + 0] = (r8 << 8) | r8;
        outputBytes[p * 4 + 1] = (g8 << 8) | g8;
        outputBytes[p * 4 + 2] = (b8 << 8) | b8;
        outputBytes[p * 4 + 3] = (a8 << 8) | a8;
    }
}

void cleanup_processor() {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);
    if (!gVk.isInitialized) return;

    cleanupBuffers();

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
}

} // extern "C"

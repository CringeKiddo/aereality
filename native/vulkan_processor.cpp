#include <jni.h>
#include <android/log.h>
#include <vulkan/vulkan.h>
#include <vector>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <memory>
#include <mutex>

#define LOG_TAG "ShadelyVulkan"
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

    // Buffer references
    VkBuffer inBuffer = VK_NULL_HANDLE;
    VkDeviceMemory inMemory = VK_NULL_HANDLE;
    VkBuffer outBuffer = VK_NULL_HANDLE;
    VkDeviceMemory outMemory = VK_NULL_HANDLE;
    VkBuffer uboBuffer = VK_NULL_HANDLE;
    VkDeviceMemory uboMemory = VK_NULL_HANDLE;

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
    gVk.allocatedPixelCapacity = 0;
}

bool ensureBuffersCapacity(size_t requiredPixels) {
    if (gVk.allocatedPixelCapacity >= requiredPixels && gVk.inBuffer != VK_NULL_HANDLE) {
        return true;
    }

    cleanupBuffers();

    VkDeviceSize pixelBufferSize = requiredPixels * sizeof(uint32_t);
    VkDeviceSize uboBufferSize = 256 * sizeof(float); // 1024 bytes (Matches UniformBlock exactly)

    createBuffer(gVk.device, gVk.physicalDevice, pixelBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.inBuffer, gVk.inMemory);

    createBuffer(gVk.device, gVk.physicalDevice, pixelBufferSize,
                 VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.outBuffer, gVk.outMemory);

    createBuffer(gVk.device, gVk.physicalDevice, uboBufferSize,
                 VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 gVk.uboBuffer, gVk.uboMemory);

    // Update Descriptor Sets with newly allocated buffers
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

    VkWriteDescriptorSet descriptorWrites[3]{};

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
    descriptorWrites[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    descriptorWrites[2].descriptorCount = 1;
    descriptorWrites[2].pBufferInfo = &uboBufferInfo;

    vkUpdateDescriptorSets(gVk.device, 3, descriptorWrites, 0, nullptr);

    gVk.allocatedPixelCapacity = requiredPixels;
    LOGI("Allocated Vulkan Pixel Buffer Capacity for %zu pixels (up to 4K Master ready).", requiredPixels);
    return true;
}

// Catmull-Rom Spline Evaluator for CPU Fallback Mode
float evalSplineCPU(float x, float p0, float p1, float p2, float p3, float p4) {
    x = std::max(0.0f, std::min(1.0f, x));
    float seg = x * 4.0f;
    int idx = static_cast<int>(std::floor(seg));
    if (idx >= 4) return p4;
    float t = seg - static_cast<float>(idx);

    float cp0 = (idx == 0) ? p0 : (idx == 1) ? p0 : (idx == 2) ? p1 : p2;
    float cp1 = (idx == 0) ? p0 : (idx == 1) ? p1 : (idx == 2) ? p2 : p3;
    float cp2 = (idx == 0) ? p1 : (idx == 1) ? p2 : (idx == 2) ? p3 : p4;
    float cp3 = (idx == 0) ? p2 : (idx == 1) ? p3 : (idx == 2) ? p4 : p4;

    float m1 = 0.5f * (cp2 - cp0);
    float m2 = 0.5f * (cp3 - cp1);

    float t2 = t * t;
    float t3 = t2 * t;

    float h00 = 2.0f * t3 - 3.0f * t2 + 1.0f;
    float h10 = t3 - 2.0f * t2 + t;
    float h01 = -2.0f * t3 + 3.0f * t2;
    float h11 = t3 - t2;

    return std::max(0.0f, std::min(1.0f, h00 * cp1 + h10 * m1 + h01 * cp2 + h11 * m2));
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
                int off = 8 + (l * 55);
                if (ubo[off + 0] < 0.5f) continue; // Layer Disabled

                float opacity = ubo[off + 1];
                int mode = static_cast<int>(ubo[off + 2]);
                float brightness = ubo[off + 3];
                float saturation = ubo[off + 4];
                float contrast = ubo[off + 5];
                float gamma = std::max(0.001f, ubo[off + 7]);

                float lr = r + brightness;
                float lg = g + brightness;
                float lb = b + brightness;

                // 0.18 Mid-Gray Pivot Contrast
                lr = (lr - 0.18f) * contrast + 0.18f;
                lg = (lg - 0.18f) * contrast + 0.18f;
                lb = (lb - 0.18f) * contrast + 0.18f;

                // Master Spline Curves
                lr = evalSplineCPU(lr, ubo[off + 38], ubo[off + 39], ubo[off + 40], ubo[off + 41], ubo[off + 42]);
                lg = evalSplineCPU(lg, ubo[off + 38], ubo[off + 39], ubo[off + 40], ubo[off + 41], ubo[off + 42]);
                lb = evalSplineCPU(lb, ubo[off + 38], ubo[off + 39], ubo[off + 40], ubo[off + 41], ubo[off + 42]);

                // Gamma
                lr = std::pow(std::max(0.0f, lr), 1.0f / gamma);
                lg = std::pow(std::max(0.0f, lg), 1.0f / gamma);
                lb = std::pow(std::max(0.0f, lb), 1.0f / gamma);

                // Saturation
                float luma = 0.299f * lr + 0.587f * lg + 0.114f * lb;
                lr = luma + saturation * (lr - luma);
                lg = luma + saturation * (lg - luma);
                lb = luma + saturation * (lb - luma);

                // Blend Modes
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

JNIEXPORT jboolean JNICALL
Java_com_shadely_app_VulkanBridge_initVulkan(JNIEnv* env, jobject thiz, jbyteArray shaderBytes, jint precisionMode) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);

    if (gVk.isInitialized) {
        return JNI_TRUE;
    }

    // 1. Create Vulkan Instance
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "ShadelyCore";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "ShadelyCompute";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;

    if (vkCreateInstance(&createInfo, nullptr, &gVk.instance) != VK_SUCCESS) {
        LOGE("Failed to create Vulkan instance! Falling back to 32-bit CPU pipeline.");
        return JNI_FALSE;
    }

    // 2. Pick Physical Device with Compute Queue
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(gVk.instance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        LOGE("No Vulkan physical devices found.");
        return JNI_FALSE;
    }

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

    if (!foundQueue) {
        LOGE("No compute queue family found on device.");
        return JNI_FALSE;
    }

    // 3. Create Logical Device
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
        LOGE("Failed to create Vulkan logical device.");
        return JNI_FALSE;
    }

    vkGetDeviceQueue(gVk.device, gVk.computeQueueFamilyIndex, 0, &gVk.computeQueue);

    // 4. Create Shader Module from SPIR-V
    jsize shaderLen = env->GetArrayLength(shaderBytes);
    jbyte* shaderBuffer = env->GetByteArrayElements(shaderBytes, nullptr);

    VkShaderModuleCreateInfo shaderModuleInfo{};
    shaderModuleInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    shaderModuleInfo.codeSize = shaderLen;
    shaderModuleInfo.pCode = reinterpret_cast<const uint32_t*>(shaderBuffer);

    if (vkCreateShaderModule(gVk.device, &shaderModuleInfo, nullptr, &gVk.shaderModule) != VK_SUCCESS) {
        LOGE("Failed to create Vulkan shader module.");
        env->ReleaseByteArrayElements(shaderBytes, shaderBuffer, JNI_ABORT);
        return JNI_FALSE;
    }
    env->ReleaseByteArrayElements(shaderBytes, shaderBuffer, JNI_ABORT);

    // 5. Create Descriptor Set Layout
    VkDescriptorSetLayoutBinding bindings[3]{};
    bindings[0].binding = 0;
    bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    bindings[0].descriptorCount = 1;
    bindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    bindings[1].binding = 1;
    bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    bindings[1].descriptorCount = 1;
    bindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    bindings[2].binding = 2;
    bindings[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    bindings[2].descriptorCount = 1;
    bindings[2].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 3;
    layoutInfo.pBindings = bindings;

    vkCreateDescriptorSetLayout(gVk.device, &layoutInfo, nullptr, &gVk.descriptorSetLayout);

    // 6. Create Pipeline Layout
    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &gVk.descriptorSetLayout;

    vkCreatePipelineLayout(gVk.device, &pipelineLayoutInfo, nullptr, &gVk.pipelineLayout);

    // 7. Create Compute Pipeline
    VkComputePipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipelineInfo.layout = gVk.pipelineLayout;
    pipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipelineInfo.stage.module = gVk.shaderModule;
    pipelineInfo.stage.pName = "main";

    vkCreateComputePipelines(gVk.device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &gVk.computePipeline);

    // 8. Create Descriptor Pool & Allocate Set
    VkDescriptorPoolSize poolSizes[2]{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    poolSizes[0].descriptorCount = 2;
    poolSizes[1].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
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

    // 9. Command Pool & Command Buffer
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
    LOGI("Shadely Vulkan Hardware Compute Pipeline Initialized Successfully.");
    return JNI_TRUE;
}

JNIEXPORT jbyteArray JNICALL
Java_com_shadely_app_VulkanBridge_processImage(JNIEnv* env, jobject thiz,
                                               jbyteArray inputPixels,
                                               jint inWidth, jint inHeight,
                                               jint outWidth, jint outHeight,
                                               jfloatArray uniformData) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);

    size_t pixelCount = static_cast<size_t>(outWidth * outHeight);
    jsize inputByteLength = env->GetArrayLength(inputPixels);
    jbyte* inPtr = env->GetByteArrayElements(inputPixels, nullptr);

    jsize uniformLen = env->GetArrayLength(uniformData);
    jfloat* uboPtr = env->GetFloatArrayElements(uniformData, nullptr);

    jbyteArray resultByteArray = env->NewByteArray(pixelCount * sizeof(uint32_t));

    if (!gVk.isInitialized || !ensureBuffersCapacity(pixelCount)) {
        // Fallback to optimized 32-bit floating point CPU pipeline
        std::vector<uint32_t> fallbackDst(pixelCount);
        executeCpuFallbackGrading(reinterpret_cast<const uint32_t*>(inPtr),
                                  fallbackDst.data(), outWidth, outHeight, uboPtr);
        env->SetByteArrayRegion(resultByteArray, 0, pixelCount * sizeof(uint32_t),
                                reinterpret_cast<const jbyte*>(fallbackDst.data()));

        env->ReleaseByteArrayElements(inputPixels, inPtr, JNI_ABORT);
        env->ReleaseFloatArrayElements(uniformData, uboPtr, JNI_ABORT);
        return resultByteArray;
    }

    // Copy Input Pixels into Vulkan Input Staging Buffer
    void* mappedInput = nullptr;
    vkMapMemory(gVk.device, gVk.inMemory, 0, pixelCount * sizeof(uint32_t), 0, &mappedInput);
    std::memcpy(mappedInput, inPtr, std::min(static_cast<size_t>(inputByteLength), pixelCount * sizeof(uint32_t)));
    vkUnmapMemory(gVk.device, gVk.inMemory);

    // Copy Uniforms into Vulkan UBO Staging Buffer
    void* mappedUbo = nullptr;
    vkMapMemory(gVk.device, gVk.uboMemory, 0, 256 * sizeof(float), 0, &mappedUbo);
    std::memcpy(mappedUbo, uboPtr, std::min(static_cast<size_t>(uniformLen * sizeof(float)), 256 * sizeof(float)));
    vkUnmapMemory(gVk.device, gVk.uboMemory);

    // Record Compute Command Buffer
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

    // Execute on GPU Compute Queue
    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &gVk.commandBuffer;

    vkQueueSubmit(gVk.computeQueue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(gVk.computeQueue);

    // Read Back Rendered Pixels
    void* mappedOutput = nullptr;
    vkMapMemory(gVk.device, gVk.outMemory, 0, pixelCount * sizeof(uint32_t), 0, &mappedOutput);
    env->SetByteArrayRegion(resultByteArray, 0, pixelCount * sizeof(uint32_t),
                            reinterpret_cast<const jbyte*>(mappedOutput));
    vkUnmapMemory(gVk.device, gVk.outMemory);

    env->ReleaseByteArrayElements(inputPixels, inPtr, JNI_ABORT);
    env->ReleaseFloatArrayElements(uniformData, uboPtr, JNI_ABORT);

    return resultByteArray;
}

JNIEXPORT jshortArray JNICALL
Java_com_shadely_app_VulkanBridge_processImage16Bit(JNIEnv* env, jobject thiz,
                                                    jshortArray inputPixels16,
                                                    jint inWidth, jint inHeight,
                                                    jint outWidth, jint outHeight,
                                                    jfloatArray uniformData) {
    std::lock_guard<std::mutex> lock(gVk.pipelineMutex);

    size_t pixelCount = static_cast<size_t>(outWidth * outHeight);
    jshort* inPtr16 = env->GetShortArrayElements(inputPixels16, nullptr);
    jfloat* uboPtr = env->GetFloatArrayElements(uniformData, nullptr);

    // Downsample 16-bit to 8-bit for Vulkan staging
    std::vector<uint32_t> stage8(pixelCount);
    const uint16_t* uin16 = reinterpret_cast<const uint16_t*>(inPtr16);

    #pragma omp parallel for
    for (size_t p = 0; p < pixelCount; p++) {
        uint8_t r = static_cast<uint8_t>(uin16[p * 4 + 0] >> 8);
        uint8_t g = static_cast<uint8_t>(uin16[p * 4 + 1] >> 8);
        uint8_t b = static_cast<uint8_t>(uin16[p * 4 + 2] >> 8);
        uint8_t a = static_cast<uint8_t>(uin16[p * 4 + 3] >> 8);
        stage8[p] = (a << 24) | (b << 16) | (g << 8) | r;
    }

    std::vector<uint32_t> out8(pixelCount);

    if (gVk.isInitialized && ensureBuffersCapacity(pixelCount)) {
        void* mappedInput = nullptr;
        vkMapMemory(gVk.device, gVk.inMemory, 0, pixelCount * sizeof(uint32_t), 0, &mappedInput);
        std::memcpy(mappedInput, stage8.data(), pixelCount * sizeof(uint32_t));
        vkUnmapMemory(gVk.device, gVk.inMemory);

        void* mappedUbo = nullptr;
        vkMapMemory(gVk.device, gVk.uboMemory, 0, 256 * sizeof(float), 0, &mappedUbo);
        std::memcpy(mappedUbo, uboPtr, 256 * sizeof(float));
        vkUnmapMemory(gVk.device, gVk.uboMemory);

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
        std::memcpy(out8.data(), mappedOutput, pixelCount * sizeof(uint32_t));
        vkUnmapMemory(gVk.device, gVk.outMemory);
    } else {
        executeCpuFallbackGrading(stage8.data(), out8.data(), outWidth, outHeight, uboPtr);
    }

    // Reconstruct 16-bit RGBA Channels
    jshortArray result16Array = env->NewShortArray(pixelCount * 4);
    std::vector<uint16_t> out16(pixelCount * 4);

    #pragma omp parallel for
    for (size_t p = 0; p < pixelCount; p++) {
        uint32_t pix = out8[p];
        uint16_t r8 = (pix & 0xFF);
        uint16_t g8 = ((pix >> 8) & 0xFF);
        uint16_t b8 = ((pix >> 16) & 0xFF);
        uint16_t a8 = ((pix >> 24) & 0xFF);

        out16[p * 4 + 0] = (r8 << 8) | r8;
        out16[p * 4 + 1] = (g8 << 8) | g8;
        out16[p * 4 + 2] = (b8 << 8) | b8;
        out16[p * 4 + 3] = (a8 << 8) | a8;
    }

    env->SetShortArrayRegion(result16Array, 0, pixelCount * 4,
                             reinterpret_cast<const jshort*>(out16.data()));

    env->ReleaseShortArrayElements(inputPixels16, inPtr16, JNI_ABORT);
    env->ReleaseFloatArrayElements(uniformData, uboPtr, JNI_ABORT);

    return result16Array;
}

JNIEXPORT void JNICALL
Java_com_shadely_app_VulkanBridge_destroyVulkan(JNIEnv* env, jobject thiz) {
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
    LOGI("Shadely Vulkan Hardware Pipeline Destroyed Cleanly.");
}

} // extern "C"

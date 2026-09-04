// native/vulkan_processor.cpp
#include <vulkan/vulkan.h>
#include <android/log.h>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <cmath>

#define LOG_TAG "VulkanProcessor"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static VkInstance gInstance = VK_NULL_HANDLE;
static VkPhysicalDevice gPhysicalDevice = VK_NULL_HANDLE;
static VkDevice gDevice = VK_NULL_HANDLE;
static VkQueue gComputeQueue = VK_NULL_HANDLE;
static uint32_t gComputeQueueFamilyIndex = 0;

static VkCommandPool gCommandPool = VK_NULL_HANDLE;
static VkShaderModule gShaderModule = VK_NULL_HANDLE;
static VkDescriptorSetLayout gDescriptorSetLayout = VK_NULL_HANDLE;
static VkPipelineLayout gPipelineLayout = VK_NULL_HANDLE;
static VkPipeline gComputePipeline = VK_NULL_HANDLE;

static bool gInitialized = false;

// Helper to find memory types
static uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(gPhysicalDevice, &memProperties);

    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    return 0;
}

// Create a GPU buffer
static bool createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties,
                         VkBuffer& buffer, VkDeviceMemory& bufferMemory) {
    VkBufferCreateInfo bufferInfo{};
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = size;
    bufferInfo.usage = usage;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    if (vkCreateBuffer(gDevice, &bufferInfo, nullptr, &buffer) != VK_SUCCESS) {
        LOGE("Failed to create buffer!");
        return false;
    }

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(gDevice, buffer, &memRequirements);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = findMemoryType(memRequirements.memoryTypeBits, properties);

    if (vkAllocateMemory(gDevice, &allocInfo, nullptr, &bufferMemory) != VK_SUCCESS) {
        LOGE("Failed to allocate buffer memory!");
        return false;
    }

    vkBindBufferMemory(gDevice, buffer, bufferMemory, 0);
    return true;
}

extern "C" {

int init_vulkan(const uint8_t* shaderBytes, int length, int precision) {
    if (gInitialized) return 1;

    // 1. Create Vulkan Instance
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "AEReality Studio Engine";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "AEReality Compute";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;

    if (vkCreateInstance(&createInfo, nullptr, &gInstance) != VK_SUCCESS) {
        LOGE("Failed to create Vulkan instance!");
        return 0;
    }

    // 2. Select Physical Device
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(gInstance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        LOGE("Failed to find GPUs with Vulkan support!");
        return 0;
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(gInstance, &deviceCount, devices.data());
    gPhysicalDevice = devices[0];

    // 3. Find Compute Queue Family
    uint32_t queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(gPhysicalDevice, &queueFamilyCount, nullptr);
    std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(gPhysicalDevice, &queueFamilyCount, queueFamilies.data());

    bool foundQueue = false;
    for (uint32_t i = 0; i < queueFamilyCount; i++) {
        if (queueFamilies[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
            gComputeQueueFamilyIndex = i;
            foundQueue = true;
            break;
        }
    }

    if (!foundQueue) {
        LOGE("No compute queue found!");
        return 0;
    }

    // 4. Create Logical Device
    VkDeviceQueueCreateInfo queueCreateInfo{};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = gComputeQueueFamilyIndex;
    queueCreateInfo.queueCount = 1;
    float queuePriority = 1.0f;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    VkDeviceCreateInfo deviceCreateInfo{};
    deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    deviceCreateInfo.queueCreateInfoCount = 1;
    deviceCreateInfo.pQueueCreateInfos = &queueCreateInfo;

    if (vkCreateDevice(gPhysicalDevice, &deviceCreateInfo, nullptr, &gDevice) != VK_SUCCESS) {
        LOGE("Failed to create logical device!");
        return 0;
    }

    vkGetDeviceQueue(gDevice, gComputeQueueFamilyIndex, 0, &gComputeQueue);

    // 5. Create Command Pool (WITH EXACT KHRONOS SPEC FIX)
    VkCommandPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = gComputeQueueFamilyIndex;

    if (vkCreateCommandPool(gDevice, &poolInfo, nullptr, &gCommandPool) != VK_SUCCESS) {
        LOGE("Failed to create command pool!");
        return 0;
    }

    // 6. Create Shader Module
    VkShaderModuleCreateInfo shaderInfo{};
    shaderInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    shaderInfo.codeSize = length;
    shaderInfo.pCode = reinterpret_cast<const uint32_t*>(shaderBytes);

    if (vkCreateShaderModule(gDevice, &shaderInfo, nullptr, &gShaderModule) != VK_SUCCESS) {
        LOGE("Failed to create compute shader module!");
        return 0;
    }

    // 7. Descriptor Set Layout (Binding 0: In, Binding 1: Out, Binding 2: Uniforms)
    VkDescriptorSetLayoutBinding bindings[3]{};
    // Input Buffer
    bindings[0].binding = 0;
    bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    bindings[0].descriptorCount = 1;
    bindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    // Output Buffer
    bindings[1].binding = 1;
    bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    bindings[1].descriptorCount = 1;
    bindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    // Uniforms Buffer
    bindings[2].binding = 2;
    bindings[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    bindings[2].descriptorCount = 1;
    bindings[2].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 3;
    layoutInfo.pBindings = bindings;

    if (vkCreateDescriptorSetLayout(gDevice, &layoutInfo, nullptr, &gDescriptorSetLayout) != VK_SUCCESS) {
        LOGE("Failed to create descriptor set layout!");
        return 0;
    }

    // 8. Pipeline Layout
    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &gDescriptorSetLayout;

    if (vkCreatePipelineLayout(gDevice, &pipelineLayoutInfo, nullptr, &gPipelineLayout) != VK_SUCCESS) {
        LOGE("Failed to create pipeline layout!");
        return 0;
    }

    // 9. Compute Pipeline
    VkComputePipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipelineInfo.stage.module = gShaderModule;
    pipelineInfo.stage.pName = "main";
    pipelineInfo.layout = gPipelineLayout;

    if (vkCreateComputePipelines(gDevice, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &gComputePipeline) != VK_SUCCESS) {
        LOGE("Failed to create compute pipeline!");
        return 0;
    }

    gInitialized = true;
    LOGI("Vulkan Compute Pipeline successfully initialized (FP32 precision)");
    return 1;
}

void process_image(
    const uint8_t* inputBytes,
    int inWidth,
    int inHeight,
    uint8_t* outputBytes,
    int outWidth,
    int outHeight,
    const float* uniforms,
    int uniformCount
) {
    if (!gInitialized) {
        std::memcpy(outputBytes, inputBytes, inWidth * inHeight * 4);
        return;
    }

    VkDeviceSize inSize = inWidth * inHeight * 4 * sizeof(uint8_t);
    VkDeviceSize outSize = outWidth * outHeight * 4 * sizeof(uint8_t);
    VkDeviceSize uniformSize = uniformCount * sizeof(float);

    VkBuffer inBuffer, outBuffer, uBuffer;
    VkDeviceMemory inMem, outMem, uMem;

    createBuffer(inSize, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 inBuffer, inMem);

    createBuffer(outSize, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 outBuffer, outMem);

    createBuffer(uniformSize, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 uBuffer, uMem);

    // Map input and uniforms
    void* data;
    vkMapMemory(gDevice, inMem, 0, inSize, 0, &data);
    std::memcpy(data, inputBytes, inSize);
    vkUnmapMemory(gDevice, inMem);

    vkMapMemory(gDevice, uMem, 0, uniformSize, 0, &data);
    std::memcpy(data, uniforms, uniformSize);
    vkUnmapMemory(gDevice, uMem);

    // Descriptor Pool & Set
    VkDescriptorPoolSize poolSizes[2]{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    poolSizes[0].descriptorCount = 2;
    poolSizes[1].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    poolSizes[1].descriptorCount = 1;

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.maxSets = 1;
    poolInfo.poolSizeCount = 2;
    poolInfo.pPoolSizes = poolSizes;

    VkDescriptorPool descPool;
    vkCreateDescriptorPool(gDevice, &poolInfo, nullptr, &descPool);

    VkDescriptorSetAllocateInfo setAllocInfo{};
    setAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    setAllocInfo.descriptorPool = descPool;
    setAllocInfo.descriptorSetCount = 1;
    setAllocInfo.pSetLayouts = &gDescriptorSetLayout;

    VkDescriptorSet descSet;
    vkAllocateDescriptorSets(gDevice, &setAllocInfo, &descSet);

    VkDescriptorBufferInfo inBufferInfo{inBuffer, 0, inSize};
    VkDescriptorBufferInfo outBufferInfo{outBuffer, 0, outSize};
    VkDescriptorBufferInfo uBufferInfo{uBuffer, 0, uniformSize};

    VkWriteDescriptorSet writes[3]{};
    writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[0].dstSet = descSet;
    writes[0].dstBinding = 0;
    writes[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    writes[0].descriptorCount = 1;
    writes[0].pBufferInfo = &inBufferInfo;

    writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[1].dstSet = descSet;
    writes[1].dstBinding = 1;
    writes[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    writes[1].descriptorCount = 1;
    writes[1].pBufferInfo = &outBufferInfo;

    writes[2].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[2].dstSet = descSet;
    writes[2].dstBinding = 2;
    writes[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    writes[2].descriptorCount = 1;
    writes[2].pBufferInfo = &uBufferInfo;

    vkUpdateDescriptorSets(gDevice, 3, writes, 0, nullptr);

    // Command Buffer Execution
    VkCommandBufferAllocateInfo cmdAllocInfo{};
    cmdAllocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAllocInfo.commandPool = gCommandPool;
    cmdAllocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAllocInfo.commandBufferCount = 1;

    VkCommandBuffer cmd;
    vkAllocateCommandBuffers(gDevice, &cmdAllocInfo, &cmd);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    vkBeginCommandBuffer(cmd, &beginInfo);

    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, gComputePipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, gPipelineLayout, 0, 1, &descSet, 0, nullptr);

    uint32_t groupX = (outWidth + 15) / 16;
    uint32_t groupY = (outHeight + 15) / 16;
    vkCmdDispatch(cmd, groupX, groupY, 1);

    vkEndCommandBuffer(cmd);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmd;

    vkQueueSubmit(gComputeQueue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(gComputeQueue);

    // Read back output
    vkMapMemory(gDevice, outMem, 0, outSize, 0, &data);
    std::memcpy(outputBytes, data, outSize);
    vkUnmapMemory(gDevice, outMem);

    // Cleanup resources
    vkFreeCommandBuffers(gDevice, gCommandPool, 1, &cmd);
    vkDestroyDescriptorPool(gDevice, descPool, nullptr);
    vkDestroyBuffer(gDevice, inBuffer, nullptr);
    vkFreeMemory(gDevice, inMem, nullptr);
    vkDestroyBuffer(gDevice, outBuffer, nullptr);
    vkFreeMemory(gDevice, outMem, nullptr);
    vkDestroyBuffer(gDevice, uBuffer, nullptr);
    vkFreeMemory(gDevice, uMem, nullptr);
}

void process_image_16(
    const uint16_t* inputBytes,
    int inWidth,
    int inHeight,
    uint16_t* outputBytes,
    int outWidth,
    int outHeight,
    const float* uniforms,
    int uniformCount
) {
    if (!gInitialized) {
        std::memcpy(outputBytes, inputBytes, inWidth * inHeight * 4 * sizeof(uint16_t));
        return;
    }

    VkDeviceSize inSize = inWidth * inHeight * 4 * sizeof(uint16_t);
    VkDeviceSize outSize = outWidth * outHeight * 4 * sizeof(uint16_t);
    VkDeviceSize uniformSize = uniformCount * sizeof(float);

    VkBuffer inBuffer, outBuffer, uBuffer;
    VkDeviceMemory inMem, outMem, uMem;

    createBuffer(inSize, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 inBuffer, inMem);

    createBuffer(outSize, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 outBuffer, outMem);

    createBuffer(uniformSize, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 uBuffer, uMem);

    void* data;
    vkMapMemory(gDevice, inMem, 0, inSize, 0, &data);
    std::memcpy(data, inputBytes, inSize);
    vkUnmapMemory(gDevice, inMem);

    vkMapMemory(gDevice, uMem, 0, uniformSize, 0, &data);
    std::memcpy(data, uniforms, uniformSize);
    vkUnmapMemory(gDevice, uMem);

    VkDescriptorPoolSize poolSizes[2]{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    poolSizes[0].descriptorCount = 2;
    poolSizes[1].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    poolSizes[1].descriptorCount = 1;

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.maxSets = 1;
    poolInfo.poolSizeCount = 2;
    poolInfo.pPoolSizes = poolSizes;

    VkDescriptorPool descPool;
    vkCreateDescriptorPool(gDevice, &poolInfo, nullptr, &descPool);

    VkDescriptorSetAllocateInfo setAllocInfo{};
    setAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    setAllocInfo.descriptorPool = descPool;
    setAllocInfo.descriptorSetCount = 1;
    setAllocInfo.pSetLayouts = &gDescriptorSetLayout;

    VkDescriptorSet descSet;
    vkAllocateDescriptorSets(gDevice, &setAllocInfo, &descSet);

    VkDescriptorBufferInfo inBufferInfo{inBuffer, 0, inSize};
    VkDescriptorBufferInfo outBufferInfo{outBuffer, 0, outSize};
    VkDescriptorBufferInfo uBufferInfo{uBuffer, 0, uniformSize};

    VkWriteDescriptorSet writes[3]{};
    writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[0].dstSet = descSet;
    writes[0].dstBinding = 0;
    writes[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    writes[0].descriptorCount = 1;
    writes[0].pBufferInfo = &inBufferInfo;

    writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[1].dstSet = descSet;
    writes[1].dstBinding = 1;
    writes[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    writes[1].descriptorCount = 1;
    writes[1].pBufferInfo = &outBufferInfo;

    writes[2].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[2].dstSet = descSet;
    writes[2].dstBinding = 2;
    writes[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    writes[2].descriptorCount = 1;
    writes[2].pBufferInfo = &uBufferInfo;

    vkUpdateDescriptorSets(gDevice, 3, writes, 0, nullptr);

    VkCommandBufferAllocateInfo cmdAllocInfo{};
    cmdAllocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAllocInfo.commandPool = gCommandPool;
    cmdAllocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAllocInfo.commandBufferCount = 1;

    VkCommandBuffer cmd;
    vkAllocateCommandBuffers(gDevice, &cmdAllocInfo, &cmd);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    vkBeginCommandBuffer(cmd, &beginInfo);

    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, gComputePipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, gPipelineLayout, 0, 1, &descSet, 0, nullptr);

    uint32_t groupX = (outWidth + 15) / 16;
    uint32_t groupY = (outHeight + 15) / 16;
    vkCmdDispatch(cmd, groupX, groupY, 1);

    vkEndCommandBuffer(cmd);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmd;

    vkQueueSubmit(gComputeQueue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(gComputeQueue);

    vkMapMemory(gDevice, outMem, 0, outSize, 0, &data);
    std::memcpy(outputBytes, data, outSize);
    vkUnmapMemory(gDevice, outMem);

    vkFreeCommandBuffers(gDevice, gCommandPool, 1, &cmd);
    vkDestroyDescriptorPool(gDevice, descPool, nullptr);
    vkDestroyBuffer(gDevice, inBuffer, nullptr);
    vkFreeMemory(gDevice, inMem, nullptr);
    vkDestroyBuffer(gDevice, outBuffer, nullptr);
    vkFreeMemory(gDevice, outMem, nullptr);
    vkDestroyBuffer(gDevice, uBuffer, nullptr);
    vkFreeMemory(gDevice, uMem, nullptr);
}

} // extern "C"

// native/vulkan_processor.cpp – Part 1 of 2
#include <vulkan/vulkan.h>
#include <vector>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <algorithm>
#include <fstream>          // ✅ for file logging
#include <chrono>           // ✅ for timestamps

#define CHECK_VK(call) if ((call) != VK_SUCCESS) { \
    fprintf(stderr, "❌ Vulkan error at %s:%d\n", __FILE__, __LINE__); \
    logFile << "❌ VK error at " << __LINE__ << "\n"; logFile.flush(); \
    return; }

static std::ofstream logFile;
static bool logInitialized = false;

void initLog() {
    if (logInitialized) return;
    logFile.open("/data/user/0/com.example.aereality/cache/vulkan_log.txt", std::ios::trunc);
    if (logFile.is_open()) {
        logFile << "🟢 Vulkan log started\n";
        logFile.flush();
        logInitialized = true;
    }
}

void writeLog(const std::string& msg) {
    if (logFile.is_open()) {
        logFile << msg << "\n";
        logFile.flush();
    }
}

static VkInstance instance;
static VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
static VkDevice device;
static VkQueue queue;
static uint32_t queueFamilyIndex = 0;
static VkCommandPool cmdPool;
static VkShaderModule shaderModule;
static VkPipelineLayout pipelineLayout;
static VkPipeline pipeline;
static VkDescriptorSetLayout descSetLayout;
static VkDescriptorPool descPool;
static VkDescriptorSet descSet;
static VkSampler sampler;
static VkCommandBuffer cmdBuffer;
static VkFence fence;

static VkImage inputImage;
static VkDeviceMemory inputMemory;
static VkImageView inputView;
static VkImage outputImage;
static VkDeviceMemory outputMemory;
static VkImageView outputView;
static VkBuffer stagingBuffer;
static VkDeviceMemory stagingMemory;
static VkBuffer outputStagingBuffer;
static VkDeviceMemory outputStagingMemory;

static int width = 0, height = 0;
static bool initialized = false;
static bool imagesCreated = false;

VkShaderModule createShaderModule(const uint32_t* code, size_t size) {
    writeLog("createShaderModule start");
    VkShaderModuleCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = size;
    createInfo.pCode = code;
    VkShaderModule module;
    if (vkCreateShaderModule(device, &createInfo, nullptr, &module) != VK_SUCCESS) {
        writeLog("❌ Failed to create shader module");
        return VK_NULL_HANDLE;
    }
    writeLog("✅ Shader module created");
    return module;
}

uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    writeLog("findMemoryType start");
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);
    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            writeLog("findMemoryType found index " + std::to_string(i));
            return i;
        }
    }
    writeLog("❌ No suitable memory type found");
    return UINT32_MAX;
}

void initVulkan() {
    initLog();
    writeLog("🔄 initVulkan started");

    VkApplicationInfo appInfo = {};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "AEReality";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instInfo = {};
    instInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instInfo.pApplicationInfo = &appInfo;
    instInfo.enabledLayerCount = 0;
    instInfo.ppEnabledLayerNames = nullptr;
    instInfo.enabledExtensionCount = 0;

    if (vkCreateInstance(&instInfo, nullptr, &instance) != VK_SUCCESS) {
        writeLog("❌ Failed to create Vulkan instance");
        return;
    }
    writeLog("✅ Vulkan instance created");

    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        writeLog("❌ No Vulkan devices found");
        return;
    }
    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(instance, &deviceCount, devices.data());
    for (auto dev : devices) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(dev, &props);
        writeLog("📱 Found device: " + std::string(props.deviceName));
        if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ||
            props.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
            physicalDevice = dev;
            break;
        }
    }
    if (physicalDevice == VK_NULL_HANDLE) {
        physicalDevice = devices[0];
    }
    writeLog("✅ Physical device selected");

    uint32_t familyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &familyCount, nullptr);
    std::vector<VkQueueFamilyProperties> families(familyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &familyCount, families.data());
    bool found = false;
    for (uint32_t i = 0; i < familyCount; i++) {
        if (families[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
            queueFamilyIndex = i;
            found = true;
            break;
        }
    }
    if (!found) {
        writeLog("❌ No compute queue found");
        return;
    }
    writeLog("✅ Compute queue family found: " + std::to_string(queueFamilyIndex));

    float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo queueInfo = {};
    queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueInfo.queueFamilyIndex = queueFamilyIndex;
    queueInfo.queueCount = 1;
    queueInfo.pQueuePriorities = &queuePriority;

    VkDeviceCreateInfo devInfo = {};
    devInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    devInfo.queueCreateInfoCount = 1;
    devInfo.pQueueCreateInfos = &queueInfo;
    devInfo.enabledExtensionCount = 0;

    if (vkCreateDevice(physicalDevice, &devInfo, nullptr, &device) != VK_SUCCESS) {
        writeLog("❌ Failed to create device");
        return;
    }
    writeLog("✅ Device created");

    vkGetDeviceQueue(device, queueFamilyIndex, 0, &queue);
    writeLog("✅ Queue obtained");

    VkCommandPoolCreateInfo poolInfo = {};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = queueFamilyIndex;
    if (vkCreateCommandPool(device, &poolInfo, nullptr, &cmdPool) != VK_SUCCESS) {
        writeLog("❌ Failed to create command pool");
        return;
    }
    writeLog("✅ Command pool created");

    VkFenceCreateInfo fenceInfo = {};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    vkCreateFence(device, &fenceInfo, nullptr, &fence);
    writeLog("✅ Fence created");

    VkSamplerCreateInfo samplerInfo = {};
    samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    samplerInfo.magFilter = VK_FILTER_LINEAR;
    samplerInfo.minFilter = VK_FILTER_LINEAR;
    samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.maxLod = 1.0f;
    vkCreateSampler(device, &samplerInfo, nullptr, &sampler);
    writeLog("✅ Sampler created");
}

void initShader(const uint32_t* spirv, size_t size) {
    writeLog("🔄 initShader called with size: " + std::to_string(size));
    shaderModule = createShaderModule(spirv, size);
    if (!shaderModule) {
        writeLog("❌ Shader module is null");
        return;
    }

    VkDescriptorSetLayoutBinding bindings[3] = {};
    bindings[0].binding = 0;
    bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    bindings[0].descriptorCount = 1;
    bindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    bindings[1].binding = 1;
    bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    bindings[1].descriptorCount = 1;
    bindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    bindings[2].binding = 2;
    bindings[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    bindings[2].descriptorCount = 1;
    bindings[2].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo layoutInfo = {};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 3;
    layoutInfo.pBindings = bindings;
    vkCreateDescriptorSetLayout(device, &layoutInfo, nullptr, &descSetLayout);
    writeLog("✅ Descriptor set layout created");

    VkPipelineLayoutCreateInfo pipeLayoutInfo = {};
    pipeLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipeLayoutInfo.setLayoutCount = 1;
    pipeLayoutInfo.pSetLayouts = &descSetLayout;
    vkCreatePipelineLayout(device, &pipeLayoutInfo, nullptr, &pipelineLayout);
    writeLog("✅ Pipeline layout created");

    VkComputePipelineCreateInfo pipeInfo = {};
    pipeInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipeInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipeInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipeInfo.stage.module = shaderModule;
    pipeInfo.stage.pName = "main";
    pipeInfo.layout = pipelineLayout;
    if (vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeInfo, nullptr, &pipeline) != VK_SUCCESS) {
        writeLog("❌ Failed to create compute pipeline");
        return;
    }
    writeLog("✅ Compute pipeline created");

    VkDescriptorPoolSize poolSizes[3] = {};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    poolSizes[0].descriptorCount = 1;
    poolSizes[1].type = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    poolSizes[1].descriptorCount = 1;
    poolSizes[2].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    poolSizes[2].descriptorCount = 1;

    VkDescriptorPoolCreateInfo poolInfo = {};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.poolSizeCount = 3;
    poolInfo.pPoolSizes = poolSizes;
    poolInfo.maxSets = 1;
    vkCreateDescriptorPool(device, &poolInfo, nullptr, &descPool);
    writeLog("✅ Descriptor pool created");

    VkDescriptorSetAllocateInfo allocInfo = {};
    allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    allocInfo.descriptorPool = descPool;
    allocInfo.descriptorSetCount = 1;
    allocInfo.pSetLayouts = &descSetLayout;
    vkAllocateDescriptorSets(device, &allocInfo, &descSet);
    writeLog("✅ Descriptor set allocated");

    VkCommandBufferAllocateInfo cmdAlloc = {};
    cmdAlloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAlloc.commandPool = cmdPool;
    cmdAlloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAlloc.commandBufferCount = 1;
    vkAllocateCommandBuffers(device, &cmdAlloc, &cmdBuffer);
    writeLog("✅ Command buffer allocated");
}
// native/vulkan_processor.cpp – Part 2 of 2 (real logic with logging)

void createImages(int w, int h) {
    writeLog("🔄 createImages called: " + std::to_string(w) + "x" + std::to_string(h));
    if (imagesCreated) {
        // Simplified cleanup
    }
    width = w;
    height = h;

    // Input image (32‑bit float) – read only
    VkImageCreateInfo imgInfo = {};
    imgInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imgInfo.imageType = VK_IMAGE_TYPE_2D;
    imgInfo.extent.width = w;
    imgInfo.extent.height = h;
    imgInfo.extent.depth = 1;
    imgInfo.mipLevels = 1;
    imgInfo.arrayLayers = 1;
    imgInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
    imgInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imgInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    imgInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    imgInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imgInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateImage(device, &imgInfo, nullptr, &inputImage);
    writeLog("✅ Input image created (rgba32f)");

    VkMemoryRequirements memReq;
    vkGetImageMemoryRequirements(device, inputImage, &memReq);
    VkMemoryAllocateInfo memAlloc = {};
    memAlloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &inputMemory);
    vkBindImageMemory(device, inputImage, inputMemory, 0);
    writeLog("✅ Input image memory allocated");

    VkImageViewCreateInfo viewInfo = {};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = inputImage;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.layerCount = 1;
    vkCreateImageView(device, &viewInfo, nullptr, &inputView);
    writeLog("✅ Input image view created");

    // Output image (32‑bit float) – storage + transfer
    imgInfo.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_STORAGE_BIT;
    vkCreateImage(device, &imgInfo, nullptr, &outputImage);
    vkGetImageMemoryRequirements(device, outputImage, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &outputMemory);
    vkBindImageMemory(device, outputImage, outputMemory, 0);
    writeLog("✅ Output image created (rgba32f)");

    viewInfo.image = outputImage;
    viewInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
    vkCreateImageView(device, &viewInfo, nullptr, &outputView);
    writeLog("✅ Output image view created");

    // Staging buffer for input (CPU → GPU)
    VkBufferCreateInfo bufInfo = {};
    bufInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufInfo.size = w * h * 4 * 4; // 4 channels * 4 bytes (float)
    bufInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    bufInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateBuffer(device, &bufInfo, nullptr, &stagingBuffer);
    vkGetBufferMemoryRequirements(device, stagingBuffer, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(
        memReq.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
    );
    vkAllocateMemory(device, &memAlloc, nullptr, &stagingMemory);
    vkBindBufferMemory(device, stagingBuffer, stagingMemory, 0);
    writeLog("✅ Input staging buffer created");

    // Staging buffer for output (GPU → CPU)
    bufInfo.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    vkCreateBuffer(device, &bufInfo, nullptr, &outputStagingBuffer);
    vkGetBufferMemoryRequirements(device, outputStagingBuffer, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(
        memReq.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
    );
    vkAllocateMemory(device, &memAlloc, nullptr, &outputStagingMemory);
    vkBindBufferMemory(device, outputStagingBuffer, outputStagingMemory, 0);
    writeLog("✅ Output staging buffer created");

    imagesCreated = true;

    // Update descriptor set
    VkDescriptorImageInfo imageInfo = {};
    imageInfo.imageView = inputView;
    imageInfo.sampler = sampler;
    imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    VkDescriptorImageInfo outputInfo = {};
    outputInfo.imageView = outputView;
    outputInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;

    VkWriteDescriptorSet writes[3] = {};
    writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[0].dstSet = descSet;
    writes[0].dstBinding = 0;
    writes[0].descriptorCount = 1;
    writes[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    writes[0].pImageInfo = &imageInfo;

    writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[1].dstSet = descSet;
    writes[1].dstBinding = 1;
    writes[1].descriptorCount = 1;
    writes[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    writes[1].pImageInfo = &outputInfo;

    vkUpdateDescriptorSets(device, 2, writes, 0, nullptr);
    writeLog("✅ Descriptor set updated");
}

void uploadInput(const uint8_t* rgba, int w, int h) {
    writeLog("📤 Uploading input frame...");
    float* data;
    vkMapMemory(device, stagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&data);
    writeLog("📤 Mapped staging memory");
    for (int i = 0; i < w * h; i++) {
        int src = i * 4;
        int dst = i * 4;
        data[dst]   = rgba[src] / 255.0f;
        data[dst+1] = rgba[src+1] / 255.0f;
        data[dst+2] = rgba[src+2] / 255.0f;
        data[dst+3] = rgba[src+3] / 255.0f;
    }
    vkUnmapMemory(device, stagingMemory);
    writeLog("📤 Unmapped staging memory");

    VkCommandBufferBeginInfo beginInfo = {};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmdBuffer, &beginInfo);
    writeLog("📤 Command buffer begun");

    // Transition input to transfer dst
    VkImageMemoryBarrier barrier = {};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = inputImage;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.layerCount = 1;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy region = {};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.layerCount = 1;
    region.imageExtent.width = w;
    region.imageExtent.height = h;
    region.imageExtent.depth = 1;
    vkCmdCopyBufferToImage(cmdBuffer, stagingBuffer, inputImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
    writeLog("📤 Buffer copied to image");

    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    barrier.image = outputImage;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &descSet, 0, nullptr);
    writeLog("📤 Pipeline bound, descriptor set bound");

    uint32_t groupX = (w + 15) / 16;
    uint32_t groupY = (h + 15) / 16;
    vkCmdDispatch(cmdBuffer, groupX, groupY, 1);
    writeLog("📤 Dispatch called");

    // Memory barrier: ensure shader writes are visible to transfer
    VkMemoryBarrier memBarrier = {};
    memBarrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    memBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    memBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(
        cmdBuffer,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0,
        1, &memBarrier,
        0, nullptr,
        0, nullptr
    );

    // Transition output to transfer source
    barrier.image = outputImage;
    barrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy copyRegion = {};
    copyRegion.bufferOffset = 0;
    copyRegion.bufferRowLength = 0;
    copyRegion.bufferImageHeight = 0;
    copyRegion.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copyRegion.imageSubresource.layerCount = 1;
    copyRegion.imageExtent.width = w;
    copyRegion.imageExtent.height = h;
    copyRegion.imageExtent.depth = 1;
    vkCmdCopyImageToBuffer(cmdBuffer, outputImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, outputStagingBuffer, 1, &copyRegion);
    writeLog("📤 Image copied to output staging buffer");

    vkEndCommandBuffer(cmdBuffer);

    VkSubmitInfo submitInfo = {};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmdBuffer;
    vkQueueSubmit(queue, 1, &submitInfo, fence);
    writeLog("📤 Submit done");

    vkQueueWaitIdle(queue);
    writeLog("📤 Queue wait idle done");

    writeLog("📤 Upload and dispatch complete");
}

void readOutput(uint8_t* rgba, int w, int h) {
    writeLog("📥 Reading output...");

    VkMappedMemoryRange range = {};
    range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    range.memory = outputStagingMemory;
    range.offset = 0;
    range.size = VK_WHOLE_SIZE;
    vkInvalidateMappedMemoryRanges(device, 1, &range);
    writeLog("📥 Invalidate done");

    float* data;
    vkMapMemory(device, outputStagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&data);
    writeLog("📥 Mapped output staging memory");

    std::string msg = "🔍 First pixel floats: R=" + std::to_string(data[0]) +
                      " G=" + std::to_string(data[1]) +
                      " B=" + std::to_string(data[2]) +
                      " A=" + std::to_string(data[3]);
    writeLog(msg);

    for (int i = 0; i < w * h; i++) {
        int src = i * 4;
        int dst = i * 4;
        rgba[dst]   = (uint8_t)(std::clamp(data[src],   0.0f, 1.0f) * 255.0f);
        rgba[dst+1] = (uint8_t)(std::clamp(data[src+1], 0.0f, 1.0f) * 255.0f);
        rgba[dst+2] = (uint8_t)(std::clamp(data[src+2], 0.0f, 1.0f) * 255.0f);
        rgba[dst+3] = (uint8_t)(std::clamp(data[src+3], 0.0f, 1.0f) * 255.0f);
    }
    vkUnmapMemory(device, outputStagingMemory);
    writeLog("📥 Output read complete");
}

void cleanupImages() {
    if (!imagesCreated) return;
    imagesCreated = false;
}

void cleanupVulkan() {
    writeLog("🔄 Cleaning up Vulkan resources");
    vkDeviceWaitIdle(device);
    vkDestroyFence(device, fence, nullptr);
    vkDestroyCommandPool(device, cmdPool, nullptr);
    vkDestroyPipeline(device, pipeline, nullptr);
    vkDestroyPipelineLayout(device, pipelineLayout, nullptr);
    vkDestroyDescriptorSetLayout(device, descSetLayout, nullptr);
    vkDestroyDescriptorPool(device, descPool, nullptr);
    vkDestroySampler(device, sampler, nullptr);
    vkDestroyShaderModule(device, shaderModule, nullptr);
    vkDestroyDevice(device, nullptr);
    vkDestroyInstance(instance, nullptr);
    initialized = false;
    writeLog("✅ Cleanup complete");
}

extern "C" {

void init_processor(const uint32_t* spirv, size_t size) {
    initLog();
    writeLog("🔄 init_processor called with size: " + std::to_string(size));
    if (initialized) return;
    initVulkan();
    initShader(spirv, size);
    initialized = true;
    writeLog("✅ init_processor complete");
}

// ✅ REAL process_frame with logging
void process_frame(const uint8_t* input, int w, int h, uint8_t* output) {
    initLog();
    writeLog("🔄 process_frame ENTERED (real)");
    if (!initialized) {
        writeLog("❌ Vulkan not initialized");
        return;
    }
    writeLog("🔄 process_frame: initialized OK");
    if (!imagesCreated || w != width || h != height) {
        writeLog("🔄 Creating/recreating images");
        if (imagesCreated) cleanupImages();
        createImages(w, h);
    }
    writeLog("🔄 Calling uploadInput");
    uploadInput(input, w, h);
    writeLog("🔄 Calling readOutput");
    readOutput(output, w, h);
    writeLog("✅ process_frame complete");
}

void cleanup_processor() {
    writeLog("🔄 cleanup_processor called");
    if (!initialized) return;
    cleanupVulkan();
    initialized = false;
    writeLog("✅ cleanup_processor complete");
}

} // extern "C"

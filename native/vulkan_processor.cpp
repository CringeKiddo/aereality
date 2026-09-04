#include <vulkan/vulkan.h>
#include <vector>
#include <cstring>
#include <cmath>
#include <stdexcept>
#include <algorithm>

#ifdef _WIN32
#define EXPORT_API __declspec(dllexport)
#else
#define EXPORT_API __attribute__((visibility("default")))
#endif

extern "C" {

struct EngineContext {
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue computeQueue = VK_NULL_HANDLE;
    uint32_t computeFamily = 0;

    VkCommandPool commandPool = VK_NULL_HANDLE;
    VkDescriptorPool descriptorPool = VK_NULL_HANDLE;
    VkDescriptorSetLayout descSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
    VkPipeline pipeline = VK_NULL_HANDLE;
    VkShaderModule shaderModule = VK_NULL_HANDLE;

    // Staging resources for 8-bit pipeline
    VkBuffer stagingIn8 = VK_NULL_HANDLE;
    VkDeviceMemory stagingInMem8 = VK_NULL_HANDLE;
    VkBuffer stagingOut8 = VK_NULL_HANDLE;
    VkDeviceMemory stagingOutMem8 = VK_NULL_HANDLE;
    size_t stagingSize8 = 0;

    // Staging resources for genuine 16-bit pipeline
    VkBuffer stagingIn16 = VK_NULL_HANDLE;
    VkDeviceMemory stagingInMem16 = VK_NULL_HANDLE;
    VkBuffer stagingOut16 = VK_NULL_HANDLE;
    VkDeviceMemory stagingOutMem16 = VK_NULL_HANDLE;
    size_t stagingSize16 = 0;

    // Uniform buffer (66 floats = 264 bytes)
    VkBuffer uniformBuffer = VK_NULL_HANDLE;
    VkDeviceMemory uniformMemory = VK_NULL_HANDLE;

    // GPU Compute Images (RGBA16F storage)
    VkImage inImage = VK_NULL_HANDLE;
    VkDeviceMemory inImageMem = VK_NULL_HANDLE;
    VkImageView inImageView = VK_NULL_HANDLE;
    int currentInW = 0, currentInH = 0;

    VkImage outImage = VK_NULL_HANDLE;
    VkDeviceMemory outImageMem = VK_NULL_HANDLE;
    VkImageView outImageView = VK_NULL_HANDLE;
    int currentOutW = 0, currentOutH = 0;

    VkDescriptorSet descriptorSet = VK_NULL_HANDLE;
    int precisionMode = 16; // 16 = FP16, 32 = FP32
    bool isReady = false;
};

static EngineContext g_ctx;

static uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(g_ctx.physicalDevice, &memProperties);
    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    return 0;
}

static void createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties,
                         VkBuffer& buffer, VkDeviceMemory& memory) {
    VkBufferCreateInfo bufInfo{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bufInfo.size = size;
    bufInfo.usage = usage;
    bufInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateBuffer(g_ctx.device, &bufInfo, nullptr, &buffer);

    VkMemoryRequirements memReq;
    vkGetBufferMemoryRequirements(g_ctx.device, buffer, &memReq);

    VkMemoryAllocateInfo allocInfo{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    allocInfo.allocationSize = memReq.size;
    allocInfo.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, properties);
    vkAllocateMemory(g_ctx.device, &allocInfo, nullptr, &memory);
    vkBindBufferMemory(g_ctx.device, buffer, memory, 0);
}

static void createImage(int width, int height, VkFormat format, VkImage& image, VkDeviceMemory& mem, VkImageView& view) {
    VkImageCreateInfo imgInfo{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    imgInfo.imageType = VK_IMAGE_TYPE_2D;
    imgInfo.extent = { (uint32_t)width, (uint32_t)height, 1 };
    imgInfo.mipLevels = 1;
    imgInfo.arrayLayers = 1;
    imgInfo.format = format;
    imgInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imgInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    imgInfo.usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    imgInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imgInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    vkCreateImage(g_ctx.device, &imgInfo, nullptr, &image);

    VkMemoryRequirements memReq;
    vkGetImageMemoryRequirements(g_ctx.device, image, &memReq);

    VkMemoryAllocateInfo allocInfo{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    allocInfo.allocationSize = memReq.size;
    allocInfo.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(g_ctx.device, &allocInfo, nullptr, &mem);
    vkBindImageMemory(g_ctx.device, image, mem, 0);

    VkImageViewCreateInfo viewInfo{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    viewInfo.image = image;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = format;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.layerCount = 1;
    vkCreateImageView(g_ctx.device, &viewInfo, nullptr, &view);
}

static void freeImage(VkImage& img, VkDeviceMemory& mem, VkImageView& view) {
    if (view != VK_NULL_HANDLE) { vkDestroyImageView(g_ctx.device, view, nullptr); view = VK_NULL_HANDLE; }
    if (img != VK_NULL_HANDLE) { vkDestroyImage(g_ctx.device, img, nullptr); img = VK_NULL_HANDLE; }
    if (mem != VK_NULL_HANDLE) { vkFreeMemory(g_ctx.device, mem, nullptr); mem = VK_NULL_HANDLE; }
}

EXPORT_API void set_engine_precision(int mode) {
    g_ctx.precisionMode = (mode == 32) ? 32 : 16;
}

EXPORT_API void init_processor(const uint32_t* spirvCode, size_t spirvSize) {
    if (g_ctx.isReady) return;

    VkApplicationInfo appInfo{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    appInfo.pApplicationName = "AERealityVulkanCore";
    appInfo.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instInfo{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    instInfo.pApplicationInfo = &appInfo;
    vkCreateInstance(&instInfo, nullptr, &g_ctx.instance);

    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(g_ctx.instance, &deviceCount, nullptr);
    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(g_ctx.instance, &deviceCount, devices.data());
    g_ctx.physicalDevice = devices[0];

    uint32_t queueCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(g_ctx.physicalDevice, &queueCount, nullptr);
    std::vector<VkQueueFamilyProperties> queueFamilies(queueCount);
    vkGetPhysicalDeviceQueueFamilyProperties(g_ctx.physicalDevice, &queueCount, queueFamilies.data());

    for (uint32_t i = 0; i < queueCount; i++) {
        if (queueFamilies[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
            g_ctx.computeFamily = i;
            break;
        }
    }

    float priority = 1.0f;
    VkDeviceQueueCreateInfo queueInfo{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    queueInfo.queueFamilyIndex = g_ctx.computeFamily;
    queueInfo.queueCount = 1;
    queueInfo.pQueuePriorities = &priority;

    VkPhysicalDeviceFeatures feats{};
    feats.shaderInt64 = VK_TRUE;

    VkDeviceCreateInfo devInfo{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    devInfo.queueCreateInfoCount = 1;
    devInfo.pQueueCreateInfos = &queueInfo;
    devInfo.pEnabledFeatures = &feats;
    vkCreateDevice(g_ctx.physicalDevice, &devInfo, nullptr, &g_ctx.device);

    vkGetDeviceQueue(g_ctx.device, g_ctx.computeFamily, 0, &g_ctx.computeQueue);

    VkCommandPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    poolInfo.queueFamilyIndex = g_ctx.computeFamily;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    vkCreateCommandPool(g_ctx.device, &poolInfo, nullptr, &g_ctx.commandPool);

    createBuffer(66 * sizeof(float),
                 VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                 VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                 g_ctx.uniformBuffer, g_ctx.uniformMemory);

    VkDescriptorSetLayoutBinding bindings[3]{};
    bindings[0].binding = 0;
    bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
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

    VkDescriptorSetLayoutCreateInfo dslInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    dslInfo.bindingCount = 3;
    dslInfo.pBindings = bindings;
    vkCreateDescriptorSetLayout(g_ctx.device, &dslInfo, nullptr, &g_ctx.descSetLayout);

    VkDescriptorPoolSize poolSizes[2]{};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    poolSizes[0].descriptorCount = 2;
    poolSizes[1].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    poolSizes[1].descriptorCount = 1;

    VkDescriptorPoolCreateInfo descPoolInfo{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    descPoolInfo.maxSets = 1;
    descPoolInfo.poolSizeCount = 2;
    descPoolInfo.pPoolSizes = poolSizes;
    vkCreateDescriptorPool(g_ctx.device, &descPoolInfo, nullptr, &g_ctx.descriptorPool);

    VkDescriptorSetAllocateInfo dsAlloc{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    dsAlloc.descriptorPool = g_ctx.descriptorPool;
    dsAlloc.descriptorSetCount = 1;
    dsAlloc.pSetLayouts = &g_ctx.descSetLayout;
    vkAllocateDescriptorSets(g_ctx.device, &dsAlloc, &g_ctx.descriptorSet);

    VkPipelineLayoutCreateInfo pipeLayoutInfo{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    pipeLayoutInfo.setLayoutCount = 1;
    pipeLayoutInfo.pSetLayouts = &g_ctx.descSetLayout;
    vkCreatePipelineLayout(g_ctx.device, &pipeLayoutInfo, nullptr, &g_ctx.pipelineLayout);

    VkShaderModuleCreateInfo smInfo{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    smInfo.codeSize = spirvSize;
    smInfo.pCode = spirvCode;
    vkCreateShaderModule(g_ctx.device, &smInfo, nullptr, &g_ctx.shaderModule);

    VkComputePipelineCreateInfo compPipeInfo{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    compPipeInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    compPipeInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    compPipeInfo.stage.module = g_ctx.shaderModule;
    compPipeInfo.stage.pName = "main";
    compPipeInfo.layout = g_ctx.pipelineLayout;
    vkCreateComputePipelines(g_ctx.device, VK_NULL_HANDLE, 1, &compPipeInfo, nullptr, &g_ctx.pipeline);

    g_ctx.isReady = true;
}

static void updateDescriptorSet() {
    VkDescriptorImageInfo imgInInfo{};
    imgInInfo.imageView = g_ctx.inImageView;
    imgInInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;

    VkDescriptorImageInfo imgOutInfo{};
    imgOutInfo.imageView = g_ctx.outImageView;
    imgOutInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;

    VkDescriptorBufferInfo bufInfo{};
    bufInfo.buffer = g_ctx.uniformBuffer;
    bufInfo.offset = 0;
    bufInfo.range = 66 * sizeof(float);

    VkWriteDescriptorSet writes[3]{};
    writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[0].dstSet = g_ctx.descriptorSet;
    writes[0].dstBinding = 0;
    writes[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    writes[0].descriptorCount = 1;
    writes[0].pImageInfo = &imgInInfo;

    writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[1].dstSet = g_ctx.descriptorSet;
    writes[1].dstBinding = 1;
    writes[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    writes[1].descriptorCount = 1;
    writes[1].pImageInfo = &imgOutInfo;

    writes[2].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[2].dstSet = g_ctx.descriptorSet;
    writes[2].dstBinding = 2;
    writes[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    writes[2].descriptorCount = 1;
    writes[2].pBufferInfo = &bufInfo;

    vkUpdateDescriptorSets(g_ctx.device, 3, writes, 0, nullptr);
}

// 8-BIT PROCESSING ENTRYPOINT (Preview & 8-bit Export)
EXPORT_API void process_frame(
    const uint8_t* input, int inW, int inH,
    int outW, int outH,
    uint8_t* output, const float* uniforms
) {
    if (!g_ctx.isReady) return;

    void* mapped = nullptr;
    vkMapMemory(g_ctx.device, g_ctx.uniformMemory, 0, 66 * sizeof(float), 0, &mapped);
    std::memcpy(mapped, uniforms, 66 * sizeof(float));
    vkUnmapMemory(g_ctx.device, g_ctx.uniformMemory);

    bool resized = false;
    if (inW != g_ctx.currentInW || inH != g_ctx.currentInH) {
        freeImage(g_ctx.inImage, g_ctx.inImageMem, g_ctx.inImageView);
        createImage(inW, inH, VK_FORMAT_R16G16B16A16_SFLOAT, g_ctx.inImage, g_ctx.inImageMem, g_ctx.inImageView);
        g_ctx.currentInW = inW; g_ctx.currentInH = inH;
        resized = true;
    }
    if (outW != g_ctx.currentOutW || outH != g_ctx.currentOutH) {
        freeImage(g_ctx.outImage, g_ctx.outImageMem, g_ctx.outImageView);
        createImage(outW, outH, VK_FORMAT_R16G16B16A16_SFLOAT, g_ctx.outImage, g_ctx.outImageMem, g_ctx.outImageView);
        g_ctx.currentOutW = outW; g_ctx.currentOutH = outH;
        resized = true;
    }
    if (resized) updateDescriptorSet();

    size_t inBytes = inW * inH * 4 * sizeof(uint8_t);
    size_t outBytes = outW * outH * 4 * sizeof(uint8_t);
    if (inBytes > g_ctx.stagingSize8) {
        if (g_ctx.stagingIn8) { vkDestroyBuffer(g_ctx.device, g_ctx.stagingIn8, nullptr); vkFreeMemory(g_ctx.device, g_ctx.stagingInMem8, nullptr); }
        if (g_ctx.stagingOut8) { vkDestroyBuffer(g_ctx.device, g_ctx.stagingOut8, nullptr); vkFreeMemory(g_ctx.device, g_ctx.stagingOutMem8, nullptr); }
        createBuffer(inBytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, g_ctx.stagingIn8, g_ctx.stagingInMem8);
        createBuffer(outBytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, g_ctx.stagingOut8, g_ctx.stagingOutMem8);
        g_ctx.stagingSize8 = inBytes;
    }

    vkMapMemory(g_ctx.device, g_ctx.stagingInMem8, 0, inBytes, 0, &mapped);
    std::memcpy(mapped, input, inBytes);
    vkUnmapMemory(g_ctx.device, g_ctx.stagingInMem8);

    VkCommandBufferAllocateInfo cmdAlloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cmdAlloc.commandPool = g_ctx.commandPool;
    cmdAlloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAlloc.commandBufferCount = 1;
    VkCommandBuffer cmd;
    vkAllocateCommandBuffers(g_ctx.device, &cmdAlloc, &cmd);

    VkCommandBufferBeginInfo beginInfo{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &beginInfo);

    VkImageMemoryBarrier barrierIn{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrierIn.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrierIn.newLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrierIn.image = g_ctx.inImage;
    barrierIn.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
    barrierIn.srcAccessMask = 0;
    barrierIn.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrierIn);

    VkBufferImageCopy copyRegion{};
    copyRegion.imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
    copyRegion.imageExtent = { (uint32_t)inW, (uint32_t)inH, 1 };
    vkCmdCopyBufferToImage(cmd, g_ctx.stagingIn8, g_ctx.inImage, VK_IMAGE_LAYOUT_GENERAL, 1, &copyRegion);

    VkImageMemoryBarrier barrierOut = barrierIn;
    barrierOut.image = g_ctx.outImage;
    barrierOut.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrierOut);

    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, g_ctx.pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, g_ctx.pipelineLayout, 0, 1, &g_ctx.descriptorSet, 0, nullptr);
    vkCmdDispatch(cmd, (outW + 15) / 16, (outH + 15) / 16, 1);

    VkImageMemoryBarrier readBarrier = barrierOut;
    readBarrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
    readBarrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    readBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    readBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &readBarrier);

    VkBufferImageCopy outCopyRegion{};
    outCopyRegion.imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
    outCopyRegion.imageExtent = { (uint32_t)outW, (uint32_t)outH, 1 };
    vkCmdCopyImageToBuffer(cmd, g_ctx.outImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, g_ctx.stagingOut8, 1, &outCopyRegion);

    vkEndCommandBuffer(cmd);

    VkSubmitInfo submitInfo{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmd;
    vkQueueSubmit(g_ctx.computeQueue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(g_ctx.computeQueue);
    vkFreeCommandBuffers(g_ctx.device, g_ctx.commandPool, 1, &cmd);

    vkMapMemory(g_ctx.device, g_ctx.stagingOutMem8, 0, outBytes, 0, &mapped);
    std::memcpy(output, mapped, outBytes);
    vkUnmapMemory(g_ctx.device, g_ctx.stagingOutMem8);
}

// GENUINE 16-BIT PROCESSING ENTRYPOINT (10-bit & 16-bit Master Export)
EXPORT_API void process_frame_16(
    const uint16_t* input, int inW, int inH,
    int outW, int outH,
    uint16_t* output, const float* uniforms
) {
    if (!g_ctx.isReady) return;

    void* mapped = nullptr;
    vkMapMemory(g_ctx.device, g_ctx.uniformMemory, 0, 66 * sizeof(float), 0, &mapped);
    std::memcpy(mapped, uniforms, 66 * sizeof(float));
    vkUnmapMemory(g_ctx.device, g_ctx.uniformMemory);

    bool resized = false;
    if (inW != g_ctx.currentInW || inH != g_ctx.currentInH) {
        freeImage(g_ctx.inImage, g_ctx.inImageMem, g_ctx.inImageView);
        createImage(inW, inH, VK_FORMAT_R16G16B16A16_SFLOAT, g_ctx.inImage, g_ctx.inImageMem, g_ctx.inImageView);
        g_ctx.currentInW = inW; g_ctx.currentInH = inH;
        resized = true;
    }
    if (outW != g_ctx.currentOutW || outH != g_ctx.currentOutH) {
        freeImage(g_ctx.outImage, g_ctx.outImageMem, g_ctx.outImageView);
        createImage(outW, outH, VK_FORMAT_R16G16B16A16_SFLOAT, g_ctx.outImage, g_ctx.outImageMem, g_ctx.outImageView);
        g_ctx.currentOutW = outW; g_ctx.currentOutH = outH;
        resized = true;
    }
    if (resized) updateDescriptorSet();

    size_t inBytes = inW * inH * 4 * sizeof(uint16_t);
    size_t outBytes = outW * outH * 4 * sizeof(uint16_t);
    if (inBytes > g_ctx.stagingSize16) {
        if (g_ctx.stagingIn16) { vkDestroyBuffer(g_ctx.device, g_ctx.stagingIn16, nullptr); vkFreeMemory(g_ctx.device, g_ctx.stagingInMem16, nullptr); }
        if (g_ctx.stagingOut16) { vkDestroyBuffer(g_ctx.device, g_ctx.stagingOut16, nullptr); vkFreeMemory(g_ctx.device, g_ctx.stagingOutMem16, nullptr); }
        createBuffer(inBytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, g_ctx.stagingIn16, g_ctx.stagingInMem16);
        createBuffer(outBytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, g_ctx.stagingOut16, g_ctx.stagingOutMem16);
        g_ctx.stagingSize16 = inBytes;
    }

    vkMapMemory(g_ctx.device, g_ctx.stagingInMem16, 0, inBytes, 0, &mapped);
    std::memcpy(mapped, input, inBytes);
    vkUnmapMemory(g_ctx.device, g_ctx.stagingInMem16);

    VkCommandBufferAllocateInfo cmdAlloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cmdAlloc.commandPool = g_ctx.commandPool;
    cmdAlloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAlloc.commandBufferCount = 1;
    VkCommandBuffer cmd;
    vkAllocateCommandBuffers(g_ctx.device, &cmdAlloc, &cmd);

    VkCommandBufferBeginInfo beginInfo{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmd, &beginInfo);

    VkImageMemoryBarrier barrierIn{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrierIn.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrierIn.newLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrierIn.image = g_ctx.inImage;
    barrierIn.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
    barrierIn.srcAccessMask = 0;
    barrierIn.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrierIn);

    VkBufferImageCopy copyRegion{};
    copyRegion.imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
    copyRegion.imageExtent = { (uint32_t)inW, (uint32_t)inH, 1 };
    vkCmdCopyBufferToImage(cmd, g_ctx.stagingIn16, g_ctx.inImage, VK_IMAGE_LAYOUT_GENERAL, 1, &copyRegion);

    VkImageMemoryBarrier barrierOut = barrierIn;
    barrierOut.image = g_ctx.outImage;
    barrierOut.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrierOut);

    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, g_ctx.pipeline);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, g_ctx.pipelineLayout, 0, 1, &g_ctx.descriptorSet, 0, nullptr);
    vkCmdDispatch(cmd, (outW + 15) / 16, (outH + 15) / 16, 1);

    VkImageMemoryBarrier readBarrier = barrierOut;
    readBarrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
    readBarrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    readBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    readBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &readBarrier);

    VkBufferImageCopy outCopyRegion{};
    outCopyRegion.imageSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
    outCopyRegion.imageExtent = { (uint32_t)outW, (uint32_t)outH, 1 };
    vkCmdCopyImageToBuffer(cmd, g_ctx.outImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, g_ctx.stagingOut16, 1, &outCopyRegion);

    vkEndCommandBuffer(cmd);

    VkSubmitInfo submitInfo{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmd;
    vkQueueSubmit(g_ctx.computeQueue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(g_ctx.computeQueue);
    vkFreeCommandBuffers(g_ctx.device, g_ctx.commandPool, 1, &cmd);

    vkMapMemory(g_ctx.device, g_ctx.stagingOutMem16, 0, outBytes, 0, &mapped);
    std::memcpy(output, mapped, outBytes);
    vkUnmapMemory(g_ctx.device, g_ctx.stagingOutMem16);
}

EXPORT_API void cleanup_processor() {
    if (!g_ctx.isReady) return;
    vkDeviceWaitIdle(g_ctx.device);

    freeImage(g_ctx.inImage, g_ctx.inImageMem, g_ctx.inImageView);
    freeImage(g_ctx.outImage, g_ctx.outImageMem, g_ctx.outImageView);

    if (g_ctx.stagingIn8) { vkDestroyBuffer(g_ctx.device, g_ctx.stagingIn8, nullptr); vkFreeMemory(g_ctx.device, g_ctx.stagingInMem8, nullptr); }
    if (g_ctx.stagingOut8) { vkDestroyBuffer(g_ctx.device, g_ctx.stagingOut8, nullptr); vkFreeMemory(g_ctx.device, g_ctx.stagingOutMem8, nullptr); }
    if (g_ctx.stagingIn16) { vkDestroyBuffer(g_ctx.device, g_ctx.stagingIn16, nullptr); vkFreeMemory(g_ctx.device, g_ctx.stagingInMem16, nullptr); }
    if (g_ctx.stagingOut16) { vkDestroyBuffer(g_ctx.device, g_ctx.stagingOut16, nullptr); vkFreeMemory(g_ctx.device, g_ctx.stagingOutMem16, nullptr); }

    if (g_ctx.uniformBuffer) { vkDestroyBuffer(g_ctx.device, g_ctx.uniformBuffer, nullptr); vkFreeMemory(g_ctx.device, g_ctx.uniformMemory, nullptr); }

    vkDestroyPipeline(g_ctx.device, g_ctx.pipeline, nullptr);
    vkDestroyPipelineLayout(g_ctx.device, g_ctx.pipelineLayout, nullptr);
    vkDestroyShaderModule(g_ctx.device, g_ctx.shaderModule, nullptr);
    vkDestroyDescriptorPool(g_ctx.device, g_ctx.descriptorPool, nullptr);
    vkDestroyDescriptorSetLayout(g_ctx.device, g_ctx.descSetLayout, nullptr);
    vkDestroyCommandPool(g_ctx.device, g_ctx.commandPool, nullptr);
    vkDestroyDevice(g_ctx.device, nullptr);
    vkDestroyInstance(g_ctx.instance, nullptr);

    g_ctx = EngineContext();
}

} // extern "C"

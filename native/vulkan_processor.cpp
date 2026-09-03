// native/vulkan_processor.cpp – Fixed, High-Performance Vulkan FFI Engine
#include <vulkan/vulkan.h>
#include <vector>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <algorithm>

static VkInstance instance = VK_NULL_HANDLE;
static VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
static VkDevice device = VK_NULL_HANDLE;
static VkQueue queue = VK_NULL_HANDLE;
static uint32_t queueFamilyIndex = 0;
static VkCommandPool cmdPool = VK_NULL_HANDLE;
static VkShaderModule shaderModule = VK_NULL_HANDLE;
static VkPipelineLayout pipelineLayout = VK_NULL_HANDLE;
static VkPipeline pipeline = VK_NULL_HANDLE;
static VkDescriptorSetLayout descSetLayout = VK_NULL_HANDLE;
static VkDescriptorPool descPool = VK_NULL_HANDLE;
static VkDescriptorSet descSet = VK_NULL_HANDLE;
static VkSampler sampler = VK_NULL_HANDLE;
static VkCommandBuffer cmdBuffer = VK_NULL_HANDLE;
static VkFence fence = VK_NULL_HANDLE;

static VkImage inputImage = VK_NULL_HANDLE;
static VkDeviceMemory inputMemory = VK_NULL_HANDLE;
static VkImageView inputView = VK_NULL_HANDLE;
static VkImage outputImage = VK_NULL_HANDLE;
static VkDeviceMemory outputMemory = VK_NULL_HANDLE;
static VkImageView outputView = VK_NULL_HANDLE;
static VkBuffer stagingBuffer = VK_NULL_HANDLE;
static VkDeviceMemory stagingMemory = VK_NULL_HANDLE;
static VkBuffer outputStagingBuffer = VK_NULL_HANDLE;
static VkDeviceMemory outputStagingMemory = VK_NULL_HANDLE;

static VkBuffer uniformBuffer = VK_NULL_HANDLE;
static VkDeviceMemory uniformMemory = VK_NULL_HANDLE;
static void* uniformMapped = nullptr;

static int inputWidth = 0, inputHeight = 0;
static int outputWidth = 0, outputHeight = 0;
static bool initialized = false;
static bool imagesCreated = false;

// Half float converters
uint16_t floatToHalf(float f) {
    uint32_t x; memcpy(&x, &f, 4);
    uint32_t sign = (x >> 16) & 0x8000;
    int32_t exponent = ((x >> 23) & 0xFF) - 127 + 15;
    uint32_t mantissa = x & 0x7FFFFF;
    if (exponent <= 0) return (uint16_t)sign;
    if (exponent >= 31) return (uint16_t)(sign | 0x7C00);
    return (uint16_t)(sign | (exponent << 10) | (mantissa >> 13));
}

float halfToFloat(uint16_t h) {
    uint32_t sign = (uint32_t)(h & 0x8000) << 16;
    uint32_t exponent = (h >> 10) & 0x1F;
    uint32_t mantissa = h & 0x3FF;
    uint32_t bits;
    if (exponent == 0) {
        bits = sign;
    } else if (exponent == 31) {
        bits = sign | 0x7F800000 | (mantissa << 13);
    } else {
        bits = sign | ((exponent - 15 + 127) << 23) | (mantissa << 13);
    }
    float f; memcpy(&f, &bits, 4);
    return f;
}

uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);
    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    return UINT32_MAX;
}

void initVulkan() {
    VkApplicationInfo appInfo = {};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "AEReality";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instInfo = {};
    instInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instInfo.pApplicationInfo = &appInfo;
    if (vkCreateInstance(&instInfo, nullptr, &instance) != VK_SUCCESS) return;

    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);
    if (deviceCount == 0) return;
    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(instance, &deviceCount, devices.data());
    for (auto dev : devices) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(dev, &props);
        if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ||
            props.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
            physicalDevice = dev;
            break;
        }
    }
    if (physicalDevice == VK_NULL_HANDLE) physicalDevice = devices[0];

    uint32_t familyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &familyCount, nullptr);
    std::vector<VkQueueFamilyProperties> families(familyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &familyCount, families.data());
    for (uint32_t i = 0; i < familyCount; i++) {
        if (families[i].queueFlags & VK_QUEUE_COMPUTE_BIT) {
            queueFamilyIndex = i;
            break;
        }
    }

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
    if (vkCreateDevice(physicalDevice, &devInfo, nullptr, &device) != VK_SUCCESS) return;

    vkGetDeviceQueue(device, queueFamilyIndex, 0, &queue);

    VkCommandPoolCreateInfo poolInfo = {};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = queueFamilyIndex;
    vkCreateCommandPool(device, &poolInfo, nullptr, &cmdPool);

    VkFenceCreateInfo fenceInfo = {};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = 0;
    vkCreateFence(device, &fenceInfo, nullptr, &fence);

    VkSamplerCreateInfo samplerInfo = {};
    samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    samplerInfo.magFilter = VK_FILTER_LINEAR;
    samplerInfo.minFilter = VK_FILTER_LINEAR;
    samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.maxLod = 1.0f;
    vkCreateSampler(device, &samplerInfo, nullptr, &sampler);
}

VkShaderModule createShaderModule(const uint32_t* code, size_t size) {
    VkShaderModuleCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = size;
    createInfo.pCode = code;
    VkShaderModule module;
    if (vkCreateShaderModule(device, &createInfo, nullptr, &module) != VK_SUCCESS) return VK_NULL_HANDLE;
    return module;
}

void initShader(const uint32_t* spirv, size_t size) {
    shaderModule = createShaderModule(spirv, size);
    if (!shaderModule) return;

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

    VkPipelineLayoutCreateInfo pipeLayoutInfo = {};
    pipeLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipeLayoutInfo.setLayoutCount = 1;
    pipeLayoutInfo.pSetLayouts = &descSetLayout;
    vkCreatePipelineLayout(device, &pipeLayoutInfo, nullptr, &pipelineLayout);

    VkComputePipelineCreateInfo pipeInfo = {};
    pipeInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipeInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipeInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipeInfo.stage.module = shaderModule;
    pipeInfo.stage.pName = "main";
    pipeInfo.layout = pipelineLayout;
    vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeInfo, nullptr, &pipeline);

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

    VkDescriptorSetAllocateInfo allocInfo = {};
    allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    allocInfo.descriptorPool = descPool;
    allocInfo.descriptorSetCount = 1;
    allocInfo.pSetLayouts = &descSetLayout;
    vkAllocateDescriptorSets(device, &allocInfo, &descSet);

    VkCommandBufferAllocateInfo cmdAlloc = {};
    cmdAlloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAlloc.commandPool = cmdPool;
    cmdAlloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAlloc.commandBufferCount = 1;
    vkAllocateCommandBuffers(device, &cmdAlloc, &cmdBuffer);
}

void cleanupImages() {
    if (!imagesCreated) return;
    vkDeviceWaitIdle(device);

    vkDestroyImageView(device, inputView, nullptr);
    vkDestroyImage(device, inputImage, nullptr);
    vkFreeMemory(device, inputMemory, nullptr);

    vkDestroyImageView(device, outputView, nullptr);
    vkDestroyImage(device, outputImage, nullptr);
    vkFreeMemory(device, outputMemory, nullptr);

    vkDestroyBuffer(device, stagingBuffer, nullptr);
    vkFreeMemory(device, stagingMemory, nullptr);

    vkDestroyBuffer(device, outputStagingBuffer, nullptr);
    vkFreeMemory(device, outputStagingMemory, nullptr);

    imagesCreated = false;
    inputWidth = inputHeight = outputWidth = outputHeight = 0;
}

void createImages(int inW, int inH, int outW, int outH) {
    if (imagesCreated) cleanupImages();
    inputWidth = inW; inputHeight = inH;
    outputWidth = outW; outputHeight = outH;

    VkImageCreateInfo imgInfo = {};
    imgInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imgInfo.imageType = VK_IMAGE_TYPE_2D;
    imgInfo.extent.depth = 1;
    imgInfo.mipLevels = 1;
    imgInfo.arrayLayers = 1;
    imgInfo.format = VK_FORMAT_R16G16B16A16_SFLOAT;
    imgInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imgInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    imgInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imgInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    // Input image
    imgInfo.extent.width = inW; imgInfo.extent.height = inH;
    imgInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    vkCreateImage(device, &imgInfo, nullptr, &inputImage);
    VkMemoryRequirements memReq;
    vkGetImageMemoryRequirements(device, inputImage, &memReq);
    VkMemoryAllocateInfo memAlloc = {};
    memAlloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &inputMemory);
    vkBindImageMemory(device, inputImage, inputMemory, 0);

    VkImageViewCreateInfo viewInfo = {};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = VK_FORMAT_R16G16B16A16_SFLOAT;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.layerCount = 1;
    viewInfo.image = inputImage;
    vkCreateImageView(device, &viewInfo, nullptr, &inputView);

    // Output image
    imgInfo.extent.width = outW; imgInfo.extent.height = outH;
    imgInfo.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_STORAGE_BIT;
    vkCreateImage(device, &imgInfo, nullptr, &outputImage);
    vkGetImageMemoryRequirements(device, outputImage, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &outputMemory);
    vkBindImageMemory(device, outputImage, outputMemory, 0);
    viewInfo.image = outputImage;
    vkCreateImageView(device, &viewInfo, nullptr, &outputView);

    // Staging buffers
    VkBufferCreateInfo bufInfo = {};
    bufInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufInfo.size = inW * inH * 4 * sizeof(uint16_t);
    bufInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    bufInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateBuffer(device, &bufInfo, nullptr, &stagingBuffer);
    vkGetBufferMemoryRequirements(device, stagingBuffer, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &stagingMemory);
    vkBindBufferMemory(device, stagingBuffer, stagingMemory, 0);

    bufInfo.size = outW * outH * 4 * sizeof(uint16_t);
    bufInfo.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    vkCreateBuffer(device, &bufInfo, nullptr, &outputStagingBuffer);
    vkGetBufferMemoryRequirements(device, outputStagingBuffer, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &outputStagingMemory);
    vkBindBufferMemory(device, outputStagingBuffer, outputStagingMemory, 0);

    // Uniform buffer (26 floats: resolution(2) + time(1) + 23 parameters)
    if (!uniformBuffer) {
        VkBufferCreateInfo uniformBufInfo = {};
        uniformBufInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        uniformBufInfo.size = 26 * sizeof(float);
        uniformBufInfo.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
        uniformBufInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        vkCreateBuffer(device, &uniformBufInfo, nullptr, &uniformBuffer);
        vkGetBufferMemoryRequirements(device, uniformBuffer, &memReq);
        memAlloc.allocationSize = memReq.size;
        memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
        vkAllocateMemory(device, &memAlloc, nullptr, &uniformMemory);
        vkBindBufferMemory(device, uniformBuffer, uniformMemory, 0);
        vkMapMemory(device, uniformMemory, 0, VK_WHOLE_SIZE, 0, &uniformMapped);
    }

    VkDescriptorImageInfo imageInfo = {};
    imageInfo.imageView = inputView;
    imageInfo.sampler = sampler;
    imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    VkDescriptorImageInfo outputInfo = {};
    outputInfo.imageView = outputView;
    outputInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;

    VkDescriptorBufferInfo uniformDesc = {};
    uniformDesc.buffer = uniformBuffer;
    uniformDesc.range = VK_WHOLE_SIZE;
    uniformDesc.offset = 0;

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

    writes[2].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[2].dstSet = descSet;
    writes[2].dstBinding = 2;
    writes[2].descriptorCount = 1;
    writes[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    writes[2].pBufferInfo = &uniformDesc;

    vkUpdateDescriptorSets(device, 3, writes, 0, nullptr);
    imagesCreated = true;
}

void uploadInput(const uint8_t* rgba, int inW, int inH) {
    uint16_t* data;
    vkMapMemory(device, stagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&data);
    for (int i = 0; i < inW * inH; i++) {
        int idx = i * 4;
        data[idx]   = floatToHalf(rgba[idx]   / 255.0f);
        data[idx+1] = floatToHalf(rgba[idx+1] / 255.0f);
        data[idx+2] = floatToHalf(rgba[idx+2] / 255.0f);
        data[idx+3] = floatToHalf(rgba[idx+3] / 255.0f);
    }
    VkMappedMemoryRange flushRange = {};
    flushRange.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    flushRange.memory = stagingMemory;
    flushRange.offset = 0;
    flushRange.size = VK_WHOLE_SIZE;
    vkFlushMappedMemoryRanges(device, 1, &flushRange);
    vkUnmapMemory(device, stagingMemory);

    // CRITICAL: Reset command buffer before recording
    vkResetCommandBuffer(cmdBuffer, 0);

    VkCommandBufferBeginInfo beginInfo = {};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmdBuffer, &beginInfo);

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
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.layerCount = 1;
    region.imageExtent = {(uint32_t)inW, (uint32_t)inH, 1};
    vkCmdCopyBufferToImage(cmdBuffer, stagingBuffer, inputImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

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

    uint32_t groupX = (outputWidth + 15) / 16;
    uint32_t groupY = (outputHeight + 15) / 16;
    vkCmdDispatch(cmdBuffer, groupX, groupY, 1);

    VkMemoryBarrier memBarrier = {};
    memBarrier.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    memBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    memBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 1, &memBarrier, 0, nullptr, 0, nullptr);

    barrier.image = outputImage;
    barrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy copyRegion = {};
    copyRegion.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copyRegion.imageSubresource.layerCount = 1;
    copyRegion.imageExtent = {(uint32_t)outputWidth, (uint32_t)outputHeight, 1};
    vkCmdCopyImageToBuffer(cmdBuffer, outputImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, outputStagingBuffer, 1, &copyRegion);

    vkEndCommandBuffer(cmdBuffer);

    // CRITICAL: Reset fence before queue submit to prevent DEVICE_LOST
    vkResetFences(device, 1, &fence);
    VkSubmitInfo submitInfo = {};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmdBuffer;
    vkQueueSubmit(queue, 1, &submitInfo, fence);

    vkWaitForFences(device, 1, &fence, VK_TRUE, UINT64_MAX);
}

void readOutput(uint8_t* rgba, int outW, int outH) {
    VkMappedMemoryRange range = {};
    range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    range.memory = outputStagingMemory;
    range.offset = 0;
    range.size = VK_WHOLE_SIZE;
    vkInvalidateMappedMemoryRanges(device, 1, &range);

    uint16_t* data;
    vkMapMemory(device, outputStagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&data);

    for (int i = 0; i < outW * outH; i++) {
        int idx = i * 4;
        rgba[idx]   = (uint8_t)(std::clamp(halfToFloat(data[idx]),   0.0f, 1.0f) * 255.0f);
        rgba[idx+1] = (uint8_t)(std::clamp(halfToFloat(data[idx+1]), 0.0f, 1.0f) * 255.0f);
        rgba[idx+2] = (uint8_t)(std::clamp(halfToFloat(data[idx+2]), 0.0f, 1.0f) * 255.0f);
        rgba[idx+3] = (uint8_t)(std::clamp(halfToFloat(data[idx+3]), 0.0f, 1.0f) * 255.0f);
    }
    vkUnmapMemory(device, outputStagingMemory);
}

void cleanupVulkan() {
    vkDeviceWaitIdle(device);
    cleanupImages();

    vkDestroyFence(device, fence, nullptr);
    vkDestroyCommandPool(device, cmdPool, nullptr);
    vkDestroyPipeline(device, pipeline, nullptr);
    vkDestroyPipelineLayout(device, pipelineLayout, nullptr);
    vkDestroyDescriptorSetLayout(device, descSetLayout, nullptr);
    vkDestroyDescriptorPool(device, descPool, nullptr);
    vkDestroySampler(device, sampler, nullptr);
    vkDestroyShaderModule(device, shaderModule, nullptr);

    if (uniformBuffer) {
        vkDestroyBuffer(device, uniformBuffer, nullptr);
        vkFreeMemory(device, uniformMemory, nullptr);
        uniformBuffer = VK_NULL_HANDLE;
    }

    vkDestroyDevice(device, nullptr);
    vkDestroyInstance(instance, nullptr);
    initialized = false;
}

extern "C" {

void init_processor(const uint32_t* spirv, size_t size) {
    if (initialized) return;
    initVulkan();
    initShader(spirv, size);
    initialized = true;
}

// 23 parameters + time + outW/outH resolution = 26 floats
void process_frame(const uint8_t* input, int inW, int inH, int outW, int outH, uint8_t* output, const float* uniforms) {
    if (!initialized) return;
    if (!imagesCreated || inputWidth != inW || inputHeight != inH || outputWidth != outW || outputHeight != outH) {
        createImages(inW, inH, outW, outH);
    }

    if (uniformMapped != nullptr) {
        float* ubo = (float*)uniformMapped;
        ubo[0] = (float)outW;
        ubo[1] = (float)outH;
        // Copy 24 floats (time + 23 parameters)
        memcpy(ubo + 2, uniforms, 24 * sizeof(float));

        VkMappedMemoryRange flushRange = {};
        flushRange.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
        flushRange.memory = uniformMemory;
        flushRange.offset = 0;
        flushRange.size = VK_WHOLE_SIZE;
        vkFlushMappedMemoryRanges(device, 1, &flushRange);
    }

    uploadInput(input, inW, inH);
    readOutput(output, outW, outH);
}

void cleanup_processor() {
    if (!initialized) return;
    cleanupVulkan();
    initialized = false;
}

} // extern "C"

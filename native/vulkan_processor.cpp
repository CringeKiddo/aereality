// native/vulkan_processor.cpp – Full updated version
#include <vulkan/vulkan.h>
#include <vector>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <algorithm>

#define CHECK_VK(call) if ((call) != VK_SUCCESS) { fprintf(stderr, "❌ Vulkan error at %s:%d\n", __FILE__, __LINE__); return; }

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

static VkBuffer uniformBuffer;
static VkDeviceMemory uniformMemory;
static void* uniformMapped = nullptr;

static int inputWidth = 0, inputHeight = 0;
static int outputWidth = 0, outputHeight = 0;
static bool initialized = false;
static bool imagesCreated = false;

// ---------- HALF FLOAT CONVERSION ----------
uint16_t floatToHalf(float f) {
    uint32_t x; memcpy(&x, &f, 4);
    uint32_t sign = (x >> 16) & 0x8000;
    int32_t exponent = ((x >> 23) & 0xFF) - 127 + 15;
    uint32_t mantissa = x & 0x7FFFFF;
    if (exponent <= 0) return (uint16_t)sign;              // flush to 0
    if (exponent >= 31) return (uint16_t)(sign | 0x7C00);  // inf
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

// ---------- VULKAN INITIALIZATION ----------
void initVulkan() {
    fprintf(stderr, "🔄 initVulkan started\n");
    VkApplicationInfo appInfo = {};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "AEReality";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instInfo = {};
    instInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instInfo.pApplicationInfo = &appInfo;
    instInfo.enabledLayerCount = 0;
    instInfo.enabledExtensionCount = 0;

    if (vkCreateInstance(&instInfo, nullptr, &instance) != VK_SUCCESS) {
        fprintf(stderr, "❌ Failed to create Vulkan instance\n");
        return;
    }
    fprintf(stderr, "✅ Vulkan instance created\n");

    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        fprintf(stderr, "❌ No Vulkan devices found\n");
        return;
    }
    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(instance, &deviceCount, devices.data());
    for (auto dev : devices) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(dev, &props);
        fprintf(stderr, "📱 Found device: %s (type: %d)\n", props.deviceName, props.deviceType);
        if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ||
            props.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
            physicalDevice = dev;
            break;
        }
    }
    if (physicalDevice == VK_NULL_HANDLE) {
        physicalDevice = devices[0];
    }
    fprintf(stderr, "✅ Physical device selected\n");

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
        fprintf(stderr, "❌ No compute queue found\n");
        return;
    }
    fprintf(stderr, "✅ Compute queue family found: %d\n", queueFamilyIndex);

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
        fprintf(stderr, "❌ Failed to create device\n");
        return;
    }
    fprintf(stderr, "✅ Device created\n");

    vkGetDeviceQueue(device, queueFamilyIndex, 0, &queue);
    fprintf(stderr, "✅ Queue obtained\n");

    VkCommandPoolCreateInfo poolInfo = {};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = queueFamilyIndex;
    if (vkCreateCommandPool(device, &poolInfo, nullptr, &cmdPool) != VK_SUCCESS) {
        fprintf(stderr, "❌ Failed to create command pool\n");
        return;
    }
    fprintf(stderr, "✅ Command pool created\n");

    VkFenceCreateInfo fenceInfo = {};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    vkCreateFence(device, &fenceInfo, nullptr, &fence);
    fprintf(stderr, "✅ Fence created\n");

    VkSamplerCreateInfo samplerInfo = {};
    samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    samplerInfo.magFilter = VK_FILTER_LINEAR;
    samplerInfo.minFilter = VK_FILTER_LINEAR;
    samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.maxLod = 1.0f;
    vkCreateSampler(device, &samplerInfo, nullptr, &sampler);
    fprintf(stderr, "✅ Sampler created\n");
}

VkShaderModule createShaderModule(const uint32_t* code, size_t size) {
    VkShaderModuleCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = size;
    createInfo.pCode = code;
    VkShaderModule module;
    if (vkCreateShaderModule(device, &createInfo, nullptr, &module) != VK_SUCCESS) {
        fprintf(stderr, "❌ Failed to create shader module\n");
        return VK_NULL_HANDLE;
    }
    fprintf(stderr, "✅ Shader module created\n");
    return module;
}

uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);
    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    fprintf(stderr, "❌ No suitable memory type found\n");
    return UINT32_MAX;
}

void initShader(const uint32_t* spirv, size_t size) {
    fprintf(stderr, "🔄 initShader called with size: %zu\n", size);
    shaderModule = createShaderModule(spirv, size);
    if (!shaderModule) {
        fprintf(stderr, "❌ Shader module is null\n");
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
    fprintf(stderr, "✅ Descriptor set layout created\n");

    VkPipelineLayoutCreateInfo pipeLayoutInfo = {};
    pipeLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipeLayoutInfo.setLayoutCount = 1;
    pipeLayoutInfo.pSetLayouts = &descSetLayout;
    vkCreatePipelineLayout(device, &pipeLayoutInfo, nullptr, &pipelineLayout);
    fprintf(stderr, "✅ Pipeline layout created\n");

    VkComputePipelineCreateInfo pipeInfo = {};
    pipeInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipeInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipeInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipeInfo.stage.module = shaderModule;
    pipeInfo.stage.pName = "main";
    pipeInfo.layout = pipelineLayout;
    if (vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeInfo, nullptr, &pipeline) != VK_SUCCESS) {
        fprintf(stderr, "❌ Failed to create compute pipeline\n");
        return;
    }
    fprintf(stderr, "✅ Compute pipeline created\n");

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
    fprintf(stderr, "✅ Descriptor pool created\n");

    VkDescriptorSetAllocateInfo allocInfo = {};
    allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    allocInfo.descriptorPool = descPool;
    allocInfo.descriptorSetCount = 1;
    allocInfo.pSetLayouts = &descSetLayout;
    vkAllocateDescriptorSets(device, &allocInfo, &descSet);
    fprintf(stderr, "✅ Descriptor set allocated\n");

    VkCommandBufferAllocateInfo cmdAlloc = {};
    cmdAlloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAlloc.commandPool = cmdPool;
    cmdAlloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAlloc.commandBufferCount = 1;
    vkAllocateCommandBuffers(device, &cmdAlloc, &cmdBuffer);
    fprintf(stderr, "✅ Command buffer allocated\n");
}

// ---------- CLEANUP IMAGES (fixes crash on re-import) ----------
void cleanupImages() {
    if (!imagesCreated) return;
    fprintf(stderr, "🔄 Cleaning up Vulkan image resources\n");
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

    // Uniform buffer and memory are reused, so keep them.

    imagesCreated = false;
    inputWidth = inputHeight = outputWidth = outputHeight = 0;
    fprintf(stderr, "✅ Image resources cleaned up\n");
}

// ---------- CREATE IMAGES (with separate input/output dims) ----------
void createImages(int inW, int inH, int outW, int outH) {
    fprintf(stderr, "🔄 createImages called: in=%dx%d, out=%dx%d\n", inW, inH, outW, outH);
    if (imagesCreated) {
        cleanupImages();
    }
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
    fprintf(stderr, "✅ Input image created (%dx%d)\n", inW, inH);

    // Output image (canvas size)
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
    fprintf(stderr, "✅ Output image created (%dx%d)\n", outW, outH);

    // Input staging buffer (for upload) – sized for input
    VkBufferCreateInfo bufInfo = {};
    bufInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufInfo.size = inW * inH * 4 * 2; // half-float
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

    // Output staging buffer (for readback) – sized for output
    bufInfo.size = outW * outH * 4 * 2;
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

    // Uniform buffer (18 floats: resolution (2) + 16 params)
    VkBufferCreateInfo uniformBufInfo = {};
    uniformBufInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    uniformBufInfo.size = 18 * sizeof(float);
    uniformBufInfo.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    uniformBufInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateBuffer(device, &uniformBufInfo, nullptr, &uniformBuffer);
    vkGetBufferMemoryRequirements(device, uniformBuffer, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(
        memReq.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
    );
    vkAllocateMemory(device, &memAlloc, nullptr, &uniformMemory);
    vkBindBufferMemory(device, uniformBuffer, uniformMemory, 0);
    vkMapMemory(device, uniformMemory, 0, VK_WHOLE_SIZE, 0, &uniformMapped);
    fprintf(stderr, "✅ Uniform buffer created (18 floats)\n");

    // Update descriptor set
    VkDescriptorImageInfo imageInfo = {};
    imageInfo.imageView = inputView;
    imageInfo.sampler = sampler;
    imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    VkDescriptorImageInfo outputInfo = {};
    outputInfo.imageView = outputView;
    outputInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;

    VkDescriptorBufferInfo uniformDescriptorBufferInfo = {};
    uniformDescriptorBufferInfo.buffer = uniformBuffer;
    uniformDescriptorBufferInfo.range = VK_WHOLE_SIZE;
    uniformDescriptorBufferInfo.offset = 0;

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
    writes[2].pBufferInfo = &uniformDescriptorBufferInfo;

    vkUpdateDescriptorSets(device, 3, writes, 0, nullptr);
    fprintf(stderr, "✅ Descriptor set updated\n");

    imagesCreated = true;
}

// ---------- UPLOAD INPUT ----------
void uploadInput(const uint8_t* rgba, int inW, int inH) {
    fprintf(stderr, "📤 Uploading input frame (%dx%d)\n", inW, inH);
    uint16_t* data;
    vkMapMemory(device, stagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&data);
    for (int i = 0; i < inW * inH; i++) {
        int src = i * 4;
        int dst = i * 4;
        data[dst]   = floatToHalf(rgba[src]   / 255.0f);
        data[dst+1] = floatToHalf(rgba[src+1] / 255.0f);
        data[dst+2] = floatToHalf(rgba[src+2] / 255.0f);
        data[dst+3] = floatToHalf(rgba[src+3] / 255.0f);
    }
    vkUnmapMemory(device, stagingMemory);

    VkCommandBufferBeginInfo beginInfo = {};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmdBuffer, &beginInfo);

    // Transition input image to TRANSFER_DST_OPTIMAL
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
    region.imageExtent.width = inW;
    region.imageExtent.height = inH;
    region.imageExtent.depth = 1;
    vkCmdCopyBufferToImage(cmdBuffer, stagingBuffer, inputImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    // Transition input to SHADER_READ_ONLY_OPTIMAL
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    // Transition output image to GENERAL (storage)
    barrier.image = outputImage;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    // Bind pipeline and descriptors
    vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &descSet, 0, nullptr);

    // Dispatch compute – using output dimensions
    uint32_t groupX = (outputWidth + 15) / 16;
    uint32_t groupY = (outputHeight + 15) / 16;
    vkCmdDispatch(cmdBuffer, groupX, groupY, 1);

    // Memory barrier: shader write -> transfer read
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

    // Transition output to TRANSFER_SRC_OPTIMAL for copy to staging
    barrier.image = outputImage;
    barrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    // Copy output image to staging buffer
    VkBufferImageCopy copyRegion = {};
    copyRegion.bufferOffset = 0;
    copyRegion.bufferRowLength = 0;
    copyRegion.bufferImageHeight = 0;
    copyRegion.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copyRegion.imageSubresource.layerCount = 1;
    copyRegion.imageExtent.width = outputWidth;
    copyRegion.imageExtent.height = outputHeight;
    copyRegion.imageExtent.depth = 1;
    vkCmdCopyImageToBuffer(cmdBuffer, outputImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, outputStagingBuffer, 1, &copyRegion);

    vkEndCommandBuffer(cmdBuffer);

    VkSubmitInfo submitInfo = {};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmdBuffer;
    vkQueueSubmit(queue, 1, &submitInfo, fence);

    vkQueueWaitIdle(queue);
    fprintf(stderr, "📤 Upload and dispatch complete\n");
}

// ---------- READ OUTPUT ----------
void readOutput(uint8_t* rgba, int outW, int outH) {
    fprintf(stderr, "📥 Reading output (%dx%d)\n", outW, outH);
    VkMappedMemoryRange range = {};
    range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    range.memory = outputStagingMemory;
    range.offset = 0;
    range.size = VK_WHOLE_SIZE;
    vkInvalidateMappedMemoryRanges(device, 1, &range);

    uint16_t* data;
    vkMapMemory(device, outputStagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&data);

    for (int i = 0; i < outW * outH; i++) {
        int src = i * 4;
        int dst = i * 4;
        rgba[dst]   = (uint8_t)(std::clamp(halfToFloat(data[src]),   0.0f, 1.0f) * 255.0f);
        rgba[dst+1] = (uint8_t)(std::clamp(halfToFloat(data[src+1]), 0.0f, 1.0f) * 255.0f);
        rgba[dst+2] = (uint8_t)(std::clamp(halfToFloat(data[src+2]), 0.0f, 1.0f) * 255.0f);
        rgba[dst+3] = (uint8_t)(std::clamp(halfToFloat(data[src+3]), 0.0f, 1.0f) * 255.0f);
    }
    vkUnmapMemory(device, outputStagingMemory);
    fprintf(stderr, "📥 Output read complete\n");
}

// ---------- CLEANUP VULKAN ----------
void cleanupVulkan() {
    fprintf(stderr, "🔄 Cleaning up Vulkan resources\n");
    vkDeviceWaitIdle(device);
    cleanupImages(); // also destroys image resources

    vkDestroyFence(device, fence, nullptr);
    vkDestroyCommandPool(device, cmdPool, nullptr);
    vkDestroyPipeline(device, pipeline, nullptr);
    vkDestroyPipelineLayout(device, pipelineLayout, nullptr);
    vkDestroyDescriptorSetLayout(device, descSetLayout, nullptr);
    vkDestroyDescriptorPool(device, descPool, nullptr);
    vkDestroySampler(device, sampler, nullptr);
    vkDestroyShaderModule(device, shaderModule, nullptr);

    vkDestroyBuffer(device, uniformBuffer, nullptr);
    vkFreeMemory(device, uniformMemory, nullptr);

    vkDestroyDevice(device, nullptr);
    vkDestroyInstance(instance, nullptr);
    initialized = false;
    fprintf(stderr, "✅ Cleanup complete\n");
}

// ---------- EXTERN "C" EXPORTS ----------
extern "C" {

void init_processor(const uint32_t* spirv, size_t size) {
    fprintf(stderr, "🔄 init_processor called with size: %zu\n", size);
    if (initialized) return;
    initVulkan();
    initShader(spirv, size);
    initialized = true;
    fprintf(stderr, "✅ init_processor complete\n");
}

void process_frame(const uint8_t* input, int inW, int inH, int outW, int outH, uint8_t* output, const float* uniforms) {
    if (!initialized) {
        fprintf(stderr, "❌ Vulkan not initialized\n");
        return;
    }
    // Recreate images if dimensions changed or not created yet
    if (!imagesCreated || inputWidth != inW || inputHeight != inH || outputWidth != outW || outputHeight != outH) {
        createImages(inW, inH, outW, outH);
    }

    // Update uniform buffer: first two floats = resolution (output width/height)
    if (uniformMapped != nullptr) {
        float* ubo = (float*)uniformMapped;
        ubo[0] = (float)outW;
        ubo[1] = (float)outH;
        // Copy the 16 grading parameters (uniforms points to 16 floats)
        memcpy(ubo + 2, uniforms, 16 * sizeof(float));

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
    fprintf(stderr, "🔄 cleanup_processor called\n");
    if (!initialized) return;
    cleanupVulkan();
    initialized = false;
    fprintf(stderr, "✅ cleanup_processor complete\n");
}

} // extern "C"

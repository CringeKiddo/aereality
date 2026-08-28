// native/vulkan_processor.cpp – Part 1 of 3
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
static VkSampler sampler;        // sampler for input image
static VkSampler lutSampler;     // sampler for LUT (3D)
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

// Uniform buffer (14 floats: resolution(2) + brightness..splitToning(11) + lutIntensity(1))
static VkBuffer uniformBuffer;
static VkDeviceMemory uniformMemory;
static void* uniformMapped = nullptr;

// LUT 3D texture
static VkImage lutImage;
static VkDeviceMemory lutMemory;
static VkImageView lutView;
static bool lutLoaded = false;

static int width = 0, height = 0;
static bool initialized = false;
static bool imagesCreated = false;

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
    instInfo.ppEnabledLayerNames = nullptr;
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

    // Create sampler for input image
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

void initShader(const uint32_t* spirv, size_t size) {
    fprintf(stderr, "🔄 initShader called with size: %zu\n", size);
    shaderModule = createShaderModule(spirv, size);
    if (!shaderModule) {
        fprintf(stderr, "❌ Shader module is null\n");
        return;
    }

    // 4 bindings: 0=input image, 1=output image, 2=uniform, 3=LUT sampler
    VkDescriptorSetLayoutBinding bindings[4] = {};
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

    bindings[3].binding = 3;
    bindings[3].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    bindings[3].descriptorCount = 1;
    bindings[3].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo layoutInfo = {};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 4;
    layoutInfo.pBindings = bindings;
    vkCreateDescriptorSetLayout(device, &layoutInfo, nullptr, &descSetLayout);
    fprintf(stderr, "✅ Descriptor set layout created (4 bindings)\n");

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

    // Descriptor pool with 4 types
    VkDescriptorPoolSize poolSizes[4] = {};
    poolSizes[0].type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    poolSizes[0].descriptorCount = 2; // input + LUT
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
// native/vulkan_processor.cpp – Part 2 of 3 (full, with identity LUT)

void createImages(int w, int h) {
    fprintf(stderr, "🔄 createImages called: %dx%d\n", w, h);
    if (imagesCreated) {
        // Simplified cleanup
    }
    width = w;
    height = h;

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
    fprintf(stderr, "✅ Input image created (rgba32f)\n");

    VkMemoryRequirements memReq;
    vkGetImageMemoryRequirements(device, inputImage, &memReq);
    VkMemoryAllocateInfo memAlloc = {};
    memAlloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &inputMemory);
    vkBindImageMemory(device, inputImage, inputMemory, 0);
    fprintf(stderr, "✅ Input image memory allocated\n");

    VkImageViewCreateInfo viewInfo = {};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = inputImage;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.layerCount = 1;
    vkCreateImageView(device, &viewInfo, nullptr, &inputView);
    fprintf(stderr, "✅ Input image view created\n");

    // Output image
    imgInfo.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_STORAGE_BIT;
    vkCreateImage(device, &imgInfo, nullptr, &outputImage);
    vkGetImageMemoryRequirements(device, outputImage, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &outputMemory);
    vkBindImageMemory(device, outputImage, outputMemory, 0);
    fprintf(stderr, "✅ Output image created (rgba32f)\n");

    viewInfo.image = outputImage;
    viewInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
    vkCreateImageView(device, &viewInfo, nullptr, &outputView);
    fprintf(stderr, "✅ Output image view created\n");

    // Staging buffer input
    VkBufferCreateInfo bufInfo = {};
    bufInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufInfo.size = w * h * 4 * 4;
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
    fprintf(stderr, "✅ Input staging buffer created\n");

    // Staging buffer output
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
    fprintf(stderr, "✅ Output staging buffer created\n");

    // Uniform buffer (14 floats)
    VkBufferCreateInfo uniformBufferCreateInfo = {};
    uniformBufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    uniformBufferCreateInfo.size = 14 * sizeof(float);
    uniformBufferCreateInfo.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    uniformBufferCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateBuffer(device, &uniformBufferCreateInfo, nullptr, &uniformBuffer);
    vkGetBufferMemoryRequirements(device, uniformBuffer, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(
        memReq.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
    );
    vkAllocateMemory(device, &memAlloc, nullptr, &uniformMemory);
    vkBindBufferMemory(device, uniformBuffer, uniformMemory, 0);
    vkMapMemory(device, uniformMemory, 0, VK_WHOLE_SIZE, 0, &uniformMapped);
    fprintf(stderr, "✅ Uniform buffer created (14 floats)\n");

    // LUT sampler (trilinear)
    VkSamplerCreateInfo lutSamplerInfo = {};
    lutSamplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    lutSamplerInfo.magFilter = VK_FILTER_LINEAR;
    lutSamplerInfo.minFilter = VK_FILTER_LINEAR;
    lutSamplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    lutSamplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    lutSamplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    lutSamplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    lutSamplerInfo.maxLod = 1.0f;
    vkCreateSampler(device, &lutSamplerInfo, nullptr, &lutSampler);
    fprintf(stderr, "✅ LUT sampler created (trilinear)\n");

    imagesCreated = true;

    // ---- Update descriptor set (4 bindings) ----
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

    // LUT image info (initially empty – will be updated by identity LUT)
    VkDescriptorImageInfo lutImageInfo = {};
    lutImageInfo.imageView = VK_NULL_HANDLE;
    lutImageInfo.sampler = lutSampler;
    lutImageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    VkWriteDescriptorSet writes[4] = {};
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

    writes[3].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    writes[3].dstSet = descSet;
    writes[3].dstBinding = 3;
    writes[3].descriptorCount = 1;
    writes[3].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    writes[3].pImageInfo = &lutImageInfo;

    vkUpdateDescriptorSets(device, 4, writes, 0, nullptr);
    fprintf(stderr, "✅ Descriptor set updated (4 bindings)\n");

    // ---- Upload a default identity LUT (2x2x2) so the sampler is never null ----
    extern void upload_lut(const float* data, int size);

    const int idSize = 2;
    const int numPoints = idSize * idSize * idSize;
    float* identityData = new float[numPoints * 3];
    int idx = 0;
    for (int r = 0; r < idSize; r++) {
        for (int g = 0; g < idSize; g++) {
            for (int b = 0; b < idSize; b++) {
                identityData[idx++] = (float)r / (idSize - 1);
                identityData[idx++] = (float)g / (idSize - 1);
                identityData[idx++] = (float)b / (idSize - 1);
            }
        }
    }
    upload_lut(identityData, idSize);
    delete[] identityData;
    fprintf(stderr, "✅ Default identity LUT uploaded (size %d)\n", idSize);
}
// native/vulkan_processor.cpp – Part 3 of 3 (corrected)

void uploadInput(const uint8_t* rgba, int w, int h) {
    fprintf(stderr, "📤 Uploading input frame...\n");
    float* data;
    vkMapMemory(device, stagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&data);
    for (int i = 0; i < w * h; i++) {
        int src = i * 4;
        int dst = i * 4;
        data[dst]   = rgba[src] / 255.0f;
        data[dst+1] = rgba[src+1] / 255.0f;
        data[dst+2] = rgba[src+2] / 255.0f;
        data[dst+3] = rgba[src+3] / 255.0f;
    }
    vkUnmapMemory(device, stagingMemory);

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
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.layerCount = 1;
    region.imageExtent.width = w;
    region.imageExtent.height = h;
    region.imageExtent.depth = 1;
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

    uint32_t groupX = (w + 15) / 16;
    uint32_t groupY = (h + 15) / 16;
    vkCmdDispatch(cmdBuffer, groupX, groupY, 1);

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

    vkEndCommandBuffer(cmdBuffer);

    VkSubmitInfo submitInfo = {};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmdBuffer;
    vkQueueSubmit(queue, 1, &submitInfo, fence);

    vkQueueWaitIdle(queue);

    fprintf(stderr, "📤 Upload and dispatch complete\n");
}

void readOutput(uint8_t* rgba, int w, int h) {
    fprintf(stderr, "📥 Reading output...\n");

    VkMappedMemoryRange range = {};
    range.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    range.memory = outputStagingMemory;
    range.offset = 0;
    range.size = VK_WHOLE_SIZE;
    vkInvalidateMappedMemoryRanges(device, 1, &range);

    float* data;
    vkMapMemory(device, outputStagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&data);

    static bool printed = false;
    if (!printed) {
        fprintf(stderr, "🔍 First pixel floats: R=%f G=%f B=%f A=%f\n",
            data[0], data[1], data[2], data[3]);
        printed = true;
    }

    for (int i = 0; i < w * h; i++) {
        int src = i * 4;
        int dst = i * 4;
        rgba[dst]   = (uint8_t)(std::clamp(data[src],   0.0f, 1.0f) * 255.0f);
        rgba[dst+1] = (uint8_t)(std::clamp(data[src+1], 0.0f, 1.0f) * 255.0f);
        rgba[dst+2] = (uint8_t)(std::clamp(data[src+2], 0.0f, 1.0f) * 255.0f);
        rgba[dst+3] = (uint8_t)(std::clamp(data[src+3], 0.0f, 1.0f) * 255.0f);
    }
    vkUnmapMemory(device, outputStagingMemory);
    fprintf(stderr, "📥 Output read complete\n");
}

void cleanupImages() {
    if (!imagesCreated) return;
    imagesCreated = false;
}

void cleanupVulkan() {
    fprintf(stderr, "🔄 Cleaning up Vulkan resources\n");
    vkDeviceWaitIdle(device);
    vkDestroyFence(device, fence, nullptr);
    vkDestroyCommandPool(device, cmdPool, nullptr);
    vkDestroyPipeline(device, pipeline, nullptr);
    vkDestroyPipelineLayout(device, pipelineLayout, nullptr);
    vkDestroyDescriptorSetLayout(device, descSetLayout, nullptr);
    vkDestroyDescriptorPool(device, descPool, nullptr);
    vkDestroySampler(device, sampler, nullptr);
    if (lutSampler) vkDestroySampler(device, lutSampler, nullptr);
    if (lutView) vkDestroyImageView(device, lutView, nullptr);
    if (lutImage) vkDestroyImage(device, lutImage, nullptr);
    if (lutMemory) vkFreeMemory(device, lutMemory, nullptr);
    vkDestroyShaderModule(device, shaderModule, nullptr);
    vkDestroyBuffer(device, uniformBuffer, nullptr);
    vkFreeMemory(device, uniformMemory, nullptr);
    vkDestroyDevice(device, nullptr);
    vkDestroyInstance(instance, nullptr);
    initialized = false;
    lutLoaded = false;
    fprintf(stderr, "✅ Cleanup complete\n");
}

// ---------- LUT UPLOAD (inside extern "C" only) ----------
extern "C" {

void init_processor(const uint32_t* spirv, size_t size) {
    fprintf(stderr, "🔄 init_processor called with size: %zu\n", size);
    if (initialized) return;
    initVulkan();
    initShader(spirv, size);
    initialized = true;
    fprintf(stderr, "✅ init_processor complete\n");
}

void process_frame(const uint8_t* input, int w, int h, uint8_t* output, const float* uniforms) {
    if (!initialized) {
        fprintf(stderr, "❌ Vulkan not initialized\n");
        return;
    }
    if (!imagesCreated || w != width || h != height) {
        if (imagesCreated) cleanupImages();
        createImages(w, h);
    }

    // Copy uniforms (14 floats)
    if (uniformMapped != nullptr) {
        float* ubo = (float*)uniformMapped;
        ubo[0] = (float)w;
        ubo[1] = (float)h;
        memcpy(ubo + 2, uniforms, 12 * sizeof(float));

        VkMappedMemoryRange flushRange = {};
        flushRange.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
        flushRange.memory = uniformMemory;
        flushRange.offset = 0;
        flushRange.size = VK_WHOLE_SIZE;
        vkFlushMappedMemoryRanges(device, 1, &flushRange);
    }

    uploadInput(input, w, h);
    readOutput(output, w, h);
}

// ✅ LUT UPLOAD – defined once, inside extern "C"
void upload_lut(const float* data, int size) {
    if (!initialized) {
        fprintf(stderr, "❌ Vulkan not initialized\n");
        return;
    }

    fprintf(stderr, "🔄 Uploading LUT: %dx%dx%d\n", size, size, size);

    // Create 3D image
    VkImageCreateInfo imgInfo = {};
    imgInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imgInfo.imageType = VK_IMAGE_TYPE_3D;
    imgInfo.extent.width = size;
    imgInfo.extent.height = size;
    imgInfo.extent.depth = size;
    imgInfo.mipLevels = 1;
    imgInfo.arrayLayers = 1;
    imgInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
    imgInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imgInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    imgInfo.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    imgInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imgInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateImage(device, &imgInfo, nullptr, &lutImage);

    VkMemoryRequirements memReq;
    vkGetImageMemoryRequirements(device, lutImage, &memReq);
    VkMemoryAllocateInfo memAlloc = {};
    memAlloc.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &lutMemory);
    vkBindImageMemory(device, lutImage, lutMemory, 0);

    // Staging buffer
    VkBuffer stagingBuffer;
    VkDeviceMemory stagingMemory;
    VkBufferCreateInfo bufInfo = {};
    bufInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufInfo.size = size * size * size * 4 * sizeof(float);
    bufInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    vkCreateBuffer(device, &bufInfo, nullptr, &stagingBuffer);
    vkGetBufferMemoryRequirements(device, stagingBuffer, &memReq);
    memAlloc.allocationSize = memReq.size;
    memAlloc.memoryTypeIndex = findMemoryType(memReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(device, &memAlloc, nullptr, &stagingMemory);
    vkBindBufferMemory(device, stagingBuffer, stagingMemory, 0);

    float* mapped;
    vkMapMemory(device, stagingMemory, 0, VK_WHOLE_SIZE, 0, (void**)&mapped);
    for (int i = 0; i < size * size * size; i++) {
        mapped[i*4 + 0] = data[i*3 + 0];
        mapped[i*4 + 1] = data[i*3 + 1];
        mapped[i*4 + 2] = data[i*3 + 2];
        mapped[i*4 + 3] = 1.0f;
    }
    vkUnmapMemory(device, stagingMemory);

    // One-time command buffer
    VkCommandBuffer cmdBuf;
    VkCommandBufferAllocateInfo cmdAlloc = {};
    cmdAlloc.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmdAlloc.commandPool = cmdPool;
    cmdAlloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmdAlloc.commandBufferCount = 1;
    vkAllocateCommandBuffers(device, &cmdAlloc, &cmdBuf);

    VkCommandBufferBeginInfo beginInfo = {};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(cmdBuf, &beginInfo);

    // Transition LUT image to TRANSFER_DST_OPTIMAL
    VkImageMemoryBarrier barrier = {};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = lutImage;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    vkCmdPipelineBarrier(cmdBuf, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy region = {};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageExtent.width = size;
    region.imageExtent.height = size;
    region.imageExtent.depth = size;
    vkCmdCopyBufferToImage(cmdBuf, stagingBuffer, lutImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    // Transition to SHADER_READ_ONLY_OPTIMAL – FIXED enum
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    vkCmdPipelineBarrier(cmdBuf, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    vkEndCommandBuffer(cmdBuf);

    VkSubmitInfo submitInfo = {};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmdBuf;
    vkQueueSubmit(queue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(queue);

    vkDestroyBuffer(device, stagingBuffer, nullptr);
    vkFreeMemory(device, stagingMemory, nullptr);
    vkFreeCommandBuffers(device, cmdPool, 1, &cmdBuf);

    // Create image view
    VkImageViewCreateInfo viewInfo = {};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = lutImage;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_3D;
    viewInfo.format = VK_FORMAT_R32G32B32A32_SFLOAT;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.baseMipLevel = 0;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.baseArrayLayer = 0;
    viewInfo.subresourceRange.layerCount = 1;
    vkCreateImageView(device, &viewInfo, nullptr, &lutView);

    // Update descriptor set with LUT view
    VkDescriptorImageInfo lutImageInfo = {};
    lutImageInfo.imageView = lutView;
    lutImageInfo.sampler = lutSampler;
    lutImageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    VkWriteDescriptorSet write = {};
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = descSet;
    write.dstBinding = 3;
    write.descriptorCount = 1;
    write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo = &lutImageInfo;
    vkUpdateDescriptorSets(device, 1, &write, 0, nullptr);

    lutLoaded = true;
    fprintf(stderr, "✅ LUT uploaded and descriptor set updated\n");
}

void cleanup_processor() {
    fprintf(stderr, "🔄 cleanup_processor called\n");
    if (!initialized) return;
    cleanupVulkan();
    initialized = false;
    fprintf(stderr, "✅ cleanup_processor complete\n");
}

} // extern "C"

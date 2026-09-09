#include <opencv2/opencv.hpp>
#include <opencv2/video/tracking.hpp>
#include <vector>
#include <cstring>
#include <android/log.h>

#define LOG_TAG "ShaderlyOpticalFlow"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

struct FlowResult {
    float* data;
    int width;
    int height;
};

extern "C" {

FlowResult compute_dis_optical_flow(float* frame_prev_rgba, float* frame_curr_rgba, int width, int height) {
    FlowResult result{nullptr, width, height};
    if (!frame_prev_rgba || !frame_curr_rgba || width <= 0 || height <= 0) {
        LOGE("Invalid arguments to compute_dis_optical_flow");
        return result;
    }

    try {
        // 1. Wrap raw 32-bit float pointers
        cv::Mat prev_rgba(height, width, CV_32FC4, frame_prev_rgba);
        cv::Mat curr_rgba(height, width, CV_32FC4, frame_curr_rgba);

        // 2. Grayscale conversion for luminance tracking
        cv::Mat prev_gray, curr_gray;
        cv::cvtColor(prev_rgba, prev_gray, cv::COLOR_RGBA2GRAY);
        cv::cvtColor(curr_rgba, curr_gray, cv::COLOR_RGBA2GRAY);

        // Map to 8-bit unsigned for DIS tracking pyramid
        cv::Mat prev_gray_8u, curr_gray_8u;
        prev_gray.convertTo(prev_gray_8u, CV_8U, 255.0);
        curr_gray.convertTo(curr_gray_8u, CV_8U, 255.0);

        // 3. Fast mobile preset
        cv::Ptr<cv::DISOpticalFlow> dis_flow = cv::DISOpticalFlow::create(cv::DISOpticalFlow::PRESET_FAST);
        cv::Mat flow_output;

        // 4. Calculate DIS motion displacement vectors
        dis_flow->calc(prev_gray_8u, curr_gray_8u, flow_output);

        // 5. Convert back to 32-bit float coordinates
        cv::Mat flow_float;
        flow_output.convertTo(flow_float, CV_32F);

        size_t total_elements = static_cast<size_t>(width * height * 2);
        float* output_buffer = new float[total_elements];
        std::memcpy(output_buffer, flow_float.data, total_elements * sizeof(float));

        result.data = output_buffer;
    } catch (const cv::Exception& e) {
        LOGE("OpenCV DIS Optical Flow Exception: %s", e.what());
    }

    return result;
}

void free_flow_buffer(float* buffer) {
    if (buffer) {
        delete[] buffer;
    }
}

} // extern "C"

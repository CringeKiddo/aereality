void process_frame(const uint8_t* input, int w, int h, uint8_t* output, const float* uniforms) {
    if (!initialized) {
        return;
    }
    if (!imagesCreated || w != width || h != height) {
        if (imagesCreated) cleanupImages();
        createImages(w, h);
    }

    // Copy uniforms into mapped memory using memcpy (fast and safe)
    if (uniformMapped != nullptr) {
        float* ubo = (float*)uniformMapped;
        ubo[0] = (float)w;
        ubo[1] = (float)h;
        // Copy the 11 grading parameters
        memcpy(ubo + 2, uniforms, 11 * sizeof(float));
    }

    uploadInput(input, w, h);
    readOutput(output, w, h);
}

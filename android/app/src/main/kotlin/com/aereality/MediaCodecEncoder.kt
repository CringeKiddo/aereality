package com.aereality

// =============================================================================
// AEReality / Shaderly - MediaCodecEncoder (hardware H.264 / HEVC, no FFmpeg)
//
//  * Surface mode (zero copy): MediaCodec is configured with COLOR_FormatSurface, createInputSurface() gives a Surface, Vulkan renders the finished frames
//    straight into it (vulkan_processor.cpp: attach_android_surface / process_image_to_surface). Nothing is read back to the CPU.
//  * Buffer mode (fallback when the GPU driver cannot present to a Surface): Dart sends NV12 frames (queueNv12), they are copied into the encoder's input image.
//  * Output: MediaMuxer (MP4). Constant frame rate: in surface mode the presentation times of the encoded frames are rewritten to index / fps (the swapchain
//    only gives wall-clock times); in buffer mode the times we queued (index / fps) are kept.
//  * Settings: codec (h264 / hevc), size, fps, bitrate (Mbps, clamped to what the encoder supports), 10-bit.
//  * 10-bit: Main10 / High10 profile + BT.2020 colour tags. Surface mode only (Android 13+, encoder must list the 10-bit profile). If the device cannot do it,
//    configure() throws, the exception is caught, and the SAME export is started again in 8-bit (BT.709); the result says which one was used ("tenBit").
//  * Audio: an AAC track of the source video is copied (no re-encode) between startMs and startMs + durationMs. Other audio formats are skipped and reported.
// =============================================================================

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

private const val TAG = "AEMediaCodec"

/** ANativeWindow bridge. The JNI functions live in libvulkan_processor.so (vulkan_processor.cpp). */
object NativeSurface {
    private var loaded = false

    @JvmStatic
    fun available(): Boolean {
        if (loaded) return true
        return try {
            System.loadLibrary("vulkan_processor")
            loaded = ping()
            loaded
        } catch (t: Throwable) {
            Log.w(TAG, "NativeSurface unavailable: ${t.message}")
            false
        }
    }

    /** Returns the ANativeWindow* (one reference held) as a number, 0 on failure. */
    fun fromSurface(s: Surface): Long = try { if (available()) windowFromSurface(s) else 0L } catch (t: Throwable) { 0L }

    fun release(handle: Long) {
        if (handle != 0L) try { windowRelease(handle) } catch (_: Throwable) {}
    }

    @JvmStatic private external fun ping(): Boolean
    @JvmStatic private external fun windowFromSurface(surface: Surface): Long
    @JvmStatic private external fun windowRelease(handle: Long)
}

data class EncoderConfig(
    val codec: String,            // "hevc" | "h264"
    val width: Int,
    val height: Int,
    val fps: Double,              // 24 / 30 / 45 / 60 / 90 (or a source rate such as 29.97)
    val bitrateMbps: Int,         // 10 15 25 30 40 50 80 (any positive value is accepted, then clamped to the encoder's range)
    val tenBit: Boolean,
    val outputPath: String,
    val useSurface: Boolean,
    val audioPath: String?,
    val audioStartMs: Long,
    val audioDurationMs: Long,
)

class MediaCodecEncoder(private val cfg: EncoderConfig) {
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    var inputSurface: Surface? = null
        private set
    private var drainThread: Thread? = null
    private var audio: AudioCopier? = null

    @Volatile private var cancelled = false
    @Volatile private var failure: String? = null
    @Volatile private var framesWritten = 0L
    @Volatile private var muxerStopped = false

    var surfaceMode = false
        private set
    var tenBit = false
        private set
    var encoderName = ""
        private set
    var hardware = false
        private set
    val notes = ArrayList<String>()
    private var audioStatus = "none"
    private var bitrateUsed = 0

    private val mime get() = if (cfg.codec == "hevc") MediaFormat.MIMETYPE_VIDEO_HEVC else MediaFormat.MIMETYPE_VIDEO_AVC
    private val frameBytes get() = cfg.width * cfg.height * 3 / 2

    // -------------------------------------------------------------------------------------------------------------
    companion object {
        fun isHardware(info: MediaCodecInfo): Boolean {
            if (Build.VERSION.SDK_INT >= 29) return info.isHardwareAccelerated && !info.isSoftwareOnly
            val n = info.name.lowercase()
            return !(n.startsWith("omx.google.") || n.startsWith("c2.android.") || n.contains(".sw."))
        }

        fun tenBitProfile(codec: String) =
            if (codec == "hevc") MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 else MediaCodecInfo.CodecProfileLevel.AVCProfileHigh10

        fun supportsTenBit(info: MediaCodecInfo, mime: String, codec: String): Boolean = try {
            val p = tenBitProfile(codec)
            info.getCapabilitiesForType(mime).profileLevels.any { it.profile == p }
        } catch (_: Throwable) { false }

        /** Hardware encoders first (in list order), then any other encoder of that type. */
        fun pick(mime: String, needTenBit: Boolean, codec: String): MediaCodecInfo? {
            var soft: MediaCodecInfo? = null
            for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
                if (!info.isEncoder || info.supportedTypes.none { it.equals(mime, true) }) continue
                if (needTenBit && !supportsTenBit(info, mime, codec)) continue
                if (isHardware(info)) return info
                if (soft == null) soft = info
            }
            return soft
        }

        fun describe(mime: String, codec: String): Map<String, Any?> {
            val hw = pick(mime, false, codec)
            val ten = pick(mime, true, codec)
            var maxW = 0; var maxH = 0
            try {
                if (hw != null) {
                    val vc = hw.getCapabilitiesForType(mime).videoCapabilities
                    maxW = vc.supportedWidths.upper; maxH = vc.supportedHeights.upper
                }
            } catch (_: Throwable) {}
            return mapOf(
                "available" to (hw != null), "hardware" to (hw != null && isHardware(hw)), "name" to hw?.name,
                "tenBit" to (ten != null && Build.VERSION.SDK_INT >= 33), "tenBitName" to ten?.name,
                "maxWidth" to maxW, "maxHeight" to maxH,
            )
        }
    }

    // -------------------------------------------------------------------------------------------------------------
    /** Starts the encoder. Throws with a readable message when nothing works. */
    fun start() {
        File(cfg.outputPath).parentFile?.mkdirs()
        try { File(cfg.outputPath).delete() } catch (_: Throwable) {}

        val tenAllowed = cfg.tenBit && cfg.useSurface && Build.VERSION.SDK_INT >= 33
        if (cfg.tenBit && !tenAllowed) {
            notes.add(if (!cfg.useSurface) "10-bit needs the surface pipeline; encoding in 8-bit."
                      else "10-bit encoding needs Android 13 or newer; encoding in 8-bit.")
        }
        val tries = if (tenAllowed) listOf(true, false) else listOf(false)
        var last: Throwable? = null
        for (ten in tries) {
            val info = pick(mime, ten, cfg.codec)
            if (info == null) {
                if (ten) notes.add("This phone's encoder has no 10-bit ${cfg.codec.uppercase()} profile; falling back to 8-bit.")
                continue
            }
            // first with an explicit profile (High / Main, better quality than the default Baseline), then without
            for (withProfile in listOf(true, false)) {
                for (clamp in listOf(false, true)) {
                    try {
                        configureAndStart(info, ten, withProfile, clamp)
                        startDrain()
                        return
                    } catch (t: Throwable) {
                        last = t
                        Log.w(TAG, "configure failed (ten=$ten profile=$withProfile clamp=$clamp on ${info.name}): ${t.message}")
                        releaseCodecQuietly()
                    }
                }
            }
            if (ten) notes.add("10-bit encoder start failed (${last?.message}); falling back to 8-bit.")
        }
        throw IllegalStateException("No ${cfg.codec.uppercase()} encoder could start at ${cfg.width}x${cfg.height}: ${last?.message ?: "none available"}")
    }

    private fun configureAndStart(info: MediaCodecInfo, ten: Boolean, withProfile: Boolean, clampBitrate: Boolean) {
        val caps = info.getCapabilitiesForType(mime)
        val vc = caps.videoCapabilities
        // The Java capability lists (media_codecs.xml) are often more conservative than the encoder really is (many phones list 1080p but encode 2K / 4K fine).
        // So size / bitrate are NOT used as a gate: the real configure() below decides. Only if it fails is the bitrate clamped to the listed range and tried again.
        var bitrate = cfg.bitrateMbps.coerceAtLeast(1) * 1_000_000
        if (clampBitrate) {
            val range = vc.bitrateRange
            if (bitrate > range.upper) { notes.add("Bitrate limited to ${range.upper / 1_000_000} Mbps by this encoder."); bitrate = range.upper }
            if (bitrate < range.lower) bitrate = range.lower
        }
        bitrateUsed = bitrate
        try {
            if (!vc.isSizeSupported(cfg.width, cfg.height)) notes.add("This encoder's list says ${cfg.width}x${cfg.height} is above its profile; trying it anyway.")
        } catch (_: Throwable) {}

        val f = MediaFormat.createVideoFormat(mime, cfg.width, cfg.height)
        f.setInteger(MediaFormat.KEY_COLOR_FORMAT,
            if (cfg.useSurface) MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface else MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
        f.setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
        f.setInteger(MediaFormat.KEY_FRAME_RATE, Math.round(cfg.fps).toInt().coerceAtLeast(1))
        f.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        if (caps.encoderCapabilities.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)) {
            f.setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
        }
        // Rate-control hints: tell the encoder the REAL frame rate, because in surface mode the input times are not real time (frames are rendered faster / slower
        // than playback). Without this an encoder that derives its bit budget from input times can starve the picture (soft / blocky output at a high bitrate).
        if (Build.VERSION.SDK_INT >= 23) f.setInteger(MediaFormat.KEY_OPERATING_RATE, Math.round(cfg.fps).toInt().coerceAtLeast(1))
        if (Build.VERSION.SDK_INT >= 29) f.setFloat(MediaFormat.KEY_CAPTURE_RATE, cfg.fps.toFloat())
        if (Build.VERSION.SDK_INT >= 29) f.setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)   // frames leave in the order they came in (CFR times stay valid)
        if (Build.VERSION.SDK_INT >= 24) {
            // 8-bit: BT.709 limited. 10-bit: BT.2020 limited, SDR transfer (set KEY_COLOR_TRANSFER to COLOR_TRANSFER_ST2084 for a PQ / HDR10 file instead).
            f.setInteger(MediaFormat.KEY_COLOR_STANDARD, if (ten) MediaFormat.COLOR_STANDARD_BT2020 else MediaFormat.COLOR_STANDARD_BT709)
            f.setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
            f.setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
        }
        if (withProfile) {
            val profile = when {
                ten -> tenBitProfile(cfg.codec)
                cfg.codec == "hevc" -> MediaCodecInfo.CodecProfileLevel.HEVCProfileMain
                else -> MediaCodecInfo.CodecProfileLevel.AVCProfileHigh
            }
            f.setInteger(MediaFormat.KEY_PROFILE, profile)
        }

        val c = MediaCodec.createByCodecName(info.name)
        codec = c
        c.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)   // throws here when the device cannot do this combination
        if (cfg.useSurface) inputSurface = c.createInputSurface()
        c.start()

        surfaceMode = cfg.useSurface
        tenBit = ten
        encoderName = info.name
        hardware = isHardware(info)
    }

    private fun releaseCodecQuietly() {
        try { inputSurface?.release() } catch (_: Throwable) {}
        inputSurface = null
        try { codec?.release() } catch (_: Throwable) {}
        codec = null
    }

    // -------------------------------------------------------------------------------------------------------------
    // BUFFER MODE
    // -------------------------------------------------------------------------------------------------------------
    /** Buffer mode: one NV12 frame (w * h * 3 / 2 bytes, Y plane then interleaved UV). Returns false when the encoder did not take it in time. */
    fun queueNv12(data: ByteArray, index: Long): Boolean {
        val c = codec ?: return false
        if (surfaceMode || data.size < frameBytes || failure != null) return false
        val i = c.dequeueInputBuffer(2_000_000)
        if (i < 0) return false
        val pts = (index * 1_000_000.0 / cfg.fps).toLong()
        val img = try { c.getInputImage(i) } catch (_: Throwable) { null }
        if (img != null) {
            copyNv12Into(img, data)
        } else {
            val bb = c.getInputBuffer(i) ?: return false
            bb.clear()
            bb.put(data, 0, minOf(frameBytes, bb.remaining()))   // semi-planar layout assumed when the encoder gives no Image
        }
        c.queueInputBuffer(i, 0, frameBytes, pts, 0)
        return true
    }

    private fun copyNv12Into(img: android.media.Image, nv12: ByteArray) {
        val w = cfg.width
        val h = cfg.height
        val planes = img.planes
        val y = planes[0]
        val yBuf = y.buffer
        if (y.rowStride == w) {
            yBuf.position(0); yBuf.put(nv12, 0, w * h)
        } else {
            for (r in 0 until h) { yBuf.position(r * y.rowStride); yBuf.put(nv12, r * w, w) }
        }
        val uvOff = w * h
        val u = planes[1]
        val v = planes[2]
        if (u.pixelStride == 2 && u.rowStride == w) {
            // NV12-compatible: the U plane buffer already spans the interleaved UV data
            val ub = u.buffer
            ub.position(0)
            ub.put(nv12, uvOff, minOf(ub.remaining(), w * h / 2))
            if (ub.capacity() < w * h / 2 && v.buffer.capacity() > 0) {
                // some drivers cut the last byte off the U plane view; V's own view still starts at the first V sample
                v.buffer.position(v.buffer.capacity() - 1); v.buffer.put(nv12[uvOff + w * h / 2 - 1])
            }
        } else {
            val ub = u.buffer
            val vb = v.buffer
            for (r in 0 until h / 2) {
                for (cIdx in 0 until w / 2) {
                    val s = uvOff + r * w + cIdx * 2
                    ub.put(r * u.rowStride + cIdx * u.pixelStride, nv12[s])
                    vb.put(r * v.rowStride + cIdx * v.pixelStride, nv12[s + 1])
                }
            }
        }
    }

    // -------------------------------------------------------------------------------------------------------------
    // DRAIN + MUX (own thread)
    // -------------------------------------------------------------------------------------------------------------
    private fun startDrain() {
        val m = MediaMuxer(cfg.outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        muxer = m
        if (cfg.audioPath != null) {
            val a = AudioCopier(cfg.audioPath, cfg.audioStartMs * 1000L, cfg.audioDurationMs * 1000L)
            if (a.open()) { audio = a } else { audioStatus = "skipped: ${a.reason}"; a.close() }
        }
        drainThread = Thread({ drainLoop() }, "AEEncoderDrain").also { it.start() }
    }

    private fun drainLoop() {
        val c = codec ?: return
        val m = muxer ?: return
        val info = MediaCodec.BufferInfo()
        var videoTrack = -1
        var audioTrack = -1
        var started = false
        var n = 0L
        try {
            loop@ while (true) {
                val idx = c.dequeueOutputBuffer(info, 20_000)
                when {
                    idx == MediaCodec.INFO_TRY_AGAIN_LATER -> if (cancelled) break@loop
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        videoTrack = m.addTrack(c.outputFormat)
                        audio?.let { a -> a.format?.let { audioTrack = m.addTrack(it) } }
                        m.start()
                        started = true
                    }
                    idx >= 0 -> {
                        val out = c.getOutputBuffer(idx)
                        if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) info.size = 0
                        if (info.size > 0 && started && out != null && !cancelled) {
                            out.position(info.offset)
                            out.limit(info.offset + info.size)
                            // constant frame rate: frame k is shown at k / fps
                            if (surfaceMode) info.presentationTimeUs = (n * 1_000_000.0 / cfg.fps).toLong()
                            n++
                            m.writeSampleData(videoTrack, out, info)
                            if (audioTrack >= 0) audio?.pump(m, audioTrack, info.presentationTimeUs)
                        }
                        c.releaseOutputBuffer(idx, false)
                        if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break@loop
                    }
                }
            }
            framesWritten = n
            if (started) {
                if (audioTrack >= 0) { audio?.pump(m, audioTrack, Long.MAX_VALUE); audioStatus = "copied" }
                m.stop()
                muxerStopped = true
            } else if (!cancelled) {
                failure = failure ?: "The encoder produced no frames."
            }
        } catch (t: Throwable) {
            failure = failure ?: "Encoder error: ${t.message}"
            Log.e(TAG, "drain failed", t)
        } finally {
            try { m.release() } catch (_: Throwable) {}
            audio?.close()
        }
    }

    // -------------------------------------------------------------------------------------------------------------
    /** Ends the stream, waits for the last frame, closes the file. Call AFTER the last frame was presented / queued. */
    fun finish(): Map<String, Any?> {
        val c = codec
        try {
            if (c != null && failure == null) {
                if (surfaceMode) {
                    c.signalEndOfInputStream()
                } else {
                    val i = c.dequeueInputBuffer(5_000_000)
                    if (i >= 0) c.queueInputBuffer(i, 0, 0, (framesWritten + 1) * 1_000_000L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                }
            }
            drainThread?.join(90_000)
            if (drainThread?.isAlive == true) { failure = failure ?: "The encoder did not finish in time."; cancelled = true; drainThread?.join(3_000) }
        } catch (t: Throwable) {
            failure = failure ?: "Could not finish the encoder: ${t.message}"
        }
        releaseCodecQuietly()
        val f = File(cfg.outputPath)
        val ok = failure == null && muxerStopped && f.exists() && f.length() > 1024
        if (!ok) try { f.delete() } catch (_: Throwable) {}
        return mapOf(
            "ok" to ok, "path" to cfg.outputPath, "bytes" to (if (f.exists()) f.length() else 0L), "frames" to framesWritten,
            "error" to failure, "audio" to audioStatus, "tenBit" to tenBit, "encoder" to encoderName, "hardware" to hardware,
            "bitrateMbps" to (bitrateUsed / 1_000_000), "notes" to notes,
        )
    }

    fun cancel() {
        cancelled = true
        try { drainThread?.join(3_000) } catch (_: Throwable) {}
        try { codec?.stop() } catch (_: Throwable) {}
        releaseCodecQuietly()
        try { muxer?.release() } catch (_: Throwable) {}
        audio?.close()
        try { File(cfg.outputPath).delete() } catch (_: Throwable) {}
    }
}

/** Copies the AAC samples of a source file into the muxer (no re-encode). */
private class AudioCopier(private val path: String, private val startUs: Long, private val durationUs: Long) {
    private val ex = MediaExtractor()
    var format: MediaFormat? = null
    var reason = "no audio track"
    private var eof = false
    private val buf = ByteBuffer.allocate(512 * 1024)
    private val bi = MediaCodec.BufferInfo()

    fun open(): Boolean {
        try {
            ex.setDataSource(path)
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (!m.startsWith("audio/")) continue
                if (m != MediaFormat.MIMETYPE_AUDIO_AAC) { reason = "audio is $m (only AAC is copied into the MP4)"; continue }
                ex.selectTrack(i)
                format = f
                ex.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                return true
            }
        } catch (t: Throwable) {
            reason = "could not read the audio: ${t.message}"
        }
        return false
    }

    /** Writes every audio sample whose time (relative to startUs) is <= [upToUs]. */
    fun pump(m: MediaMuxer, track: Int, upToUs: Long) {
        while (!eof) {
            val t = ex.sampleTime
            if (t < 0) { eof = true; break }
            val rel = t - startUs
            if (durationUs > 0 && rel > durationUs) { eof = true; break }
            if (rel > upToUs) break
            buf.clear()
            val n = ex.readSampleData(buf, 0)
            if (n < 0) { eof = true; break }
            if (rel >= 0) {
                val flags = if ((ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                bi.set(0, n, rel, flags)
                m.writeSampleData(track, buf, bi)
            }
            ex.advance()
        }
    }

    fun close() { try { ex.release() } catch (_: Throwable) {} }
}

/** MethodChannel "com.aereality/encoder": the Dart side is native_encoder.dart. One export at a time. */
object EncoderBridge {
    const val CHANNEL = "com.aereality/encoder"
    private var enc: MediaCodecEncoder? = null
    private var windowHandle = 0L
    private val io = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())

    private fun cfgOf(a: Map<*, *>, surface: Boolean) = EncoderConfig(
        codec = (a["codec"] as? String) ?: "hevc",
        width = (a["width"] as Number).toInt(),
        height = (a["height"] as Number).toInt(),
        fps = (a["fps"] as Number).toDouble(),
        bitrateMbps = (a["bitrateMbps"] as Number).toInt(),
        tenBit = (a["tenBit"] as? Boolean) ?: false,
        outputPath = a["outputPath"] as String,
        useSurface = surface,
        audioPath = a["audioPath"] as? String,
        audioStartMs = (a["audioStartMs"] as? Number)?.toLong() ?: 0L,
        audioDurationMs = (a["audioDurationMs"] as? Number)?.toLong() ?: 0L,
    )

    private fun drop() {
        NativeSurface.release(windowHandle); windowHandle = 0L
        enc = null
    }

    fun register(m: BinaryMessenger) {
        MethodChannel(m, CHANNEL).setMethodCallHandler { call, result ->
            fun reply(v: Any?) = ui.post { result.success(v) }
            when (call.method) {
                "capabilities" -> io.execute {
                    reply(mapOf(
                        "api" to Build.VERSION.SDK_INT,
                        "surfaceBridge" to NativeSurface.available(),
                        "hevc" to MediaCodecEncoder.describe(MediaFormat.MIMETYPE_VIDEO_HEVC, "hevc"),
                        "h264" to MediaCodecEncoder.describe(MediaFormat.MIMETYPE_VIDEO_AVC, "h264"),
                    ))
                }
                "start" -> {
                    val a = call.arguments as Map<*, *>
                    io.execute {
                        try {
                            enc?.cancel(); drop()
                            val wantSurface = (a["preferSurface"] as? Boolean) ?: true
                            var e = MediaCodecEncoder(cfgOf(a, wantSurface && NativeSurface.available()))
                            e.start()
                            var handle = 0L
                            var surfaceFallback: String? = null
                            if (e.surfaceMode) {
                                handle = NativeSurface.fromSurface(e.inputSurface!!)
                                if (handle == 0L) {   // the Surface could not be handed to Vulkan: restart in buffer mode
                                    e.cancel()
                                    surfaceFallback = "The encoder surface could not be passed to the GPU; using buffer mode."
                                    e = MediaCodecEncoder(cfgOf(a, false))
                                    e.start()
                                }
                            }
                            enc = e
                            windowHandle = handle
                            val notes = ArrayList(e.notes)
                            surfaceFallback?.let { notes.add(it) }
                            reply(mapOf(
                                "ok" to true, "mode" to (if (e.surfaceMode) "surface" else "buffer"), "windowHandle" to handle,
                                "tenBit" to e.tenBit, "encoder" to e.encoderName, "hardware" to e.hardware, "notes" to notes,
                            ))
                        } catch (t: Throwable) {
                            Log.e(TAG, "start failed", t)
                            enc?.cancel(); drop()
                            reply(mapOf("ok" to false, "error" to (t.message ?: t.toString())))
                        }
                    }
                }
                "queueNv12" -> {
                    val data = call.argument<ByteArray>("data")
                    val index = (call.argument<Number>("index") ?: 0).toLong()
                    val e = enc
                    if (data == null || e == null) result.success(false)
                    else io.execute { reply(try { e.queueNv12(data, index) } catch (t: Throwable) { Log.e(TAG, "queueNv12", t); false }) }
                }
                "finish" -> io.execute {
                    val e = enc
                    if (e == null) reply(mapOf("ok" to false, "error" to "No export is running."))
                    else reply(try { e.finish() } catch (t: Throwable) { mapOf("ok" to false, "error" to (t.message ?: t.toString())) })
                }
                "releaseWindow" -> io.execute { drop(); reply(true) }
                "cancel" -> io.execute { enc?.cancel(); drop(); reply(true) }
                else -> result.notImplemented()
            }
        }
    }

    fun shutdown() { try { enc?.cancel() } catch (_: Throwable) {}; drop() }
}

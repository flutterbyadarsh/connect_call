import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Generates and plays system-feedback audio tones without requiring
/// any bundled asset files. All PCM data is synthesised at runtime.
class CallFeedbackService {
  CallFeedbackService._();

  static final CallFeedbackService instance = CallFeedbackService._();

  AudioPlayer? _busyPlayer;
  AudioPlayer? _waitingPlayer;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Plays 3× alternating 480 Hz / 620 Hz busy-tone beeps (UK/US style).
  /// Triggers heavy haptic simultaneously.
  Future<void> playBusyTone() async {
    await stopAll();
    HapticFeedback.heavyImpact();

    _busyPlayer = AudioPlayer();
    await _busyPlayer!.setVolume(1.0);

    // Generate 3 cycles: 500ms ON (alternating freq) + 500ms silence
    final bytes = _buildBusyToneWav();
    try {
      await _busyPlayer!.play(BytesSource(bytes));
    } catch (e) {
      debugPrint('[CallFeedbackService] playBusyTone error: $e');
    }
  }

  /// Plays a single short 1000 Hz call-waiting beep at reduced volume.
  Future<void> playCallWaitingBeep() async {
    _waitingPlayer?.stop();
    _waitingPlayer = AudioPlayer();
    await _waitingPlayer!.setVolume(0.4);

    final bytes = _buildSingleBeepWav(frequencyHz: 1000, durationMs: 250);
    try {
      await _waitingPlayer!.play(BytesSource(bytes));
    } catch (e) {
      debugPrint('[CallFeedbackService] playCallWaitingBeep error: $e');
    }
  }

  /// Stops all playing audio immediately.
  Future<void> stopAll() async {
    await Future.wait([
      if (_busyPlayer != null) _busyPlayer!.stop(),
      if (_waitingPlayer != null) _waitingPlayer!.stop(),
    ]);
    _busyPlayer?.dispose();
    _waitingPlayer?.dispose();
    _busyPlayer = null;
    _waitingPlayer = null;
  }

  // ── PCM / WAV Synthesis ────────────────────────────────────────────────────

  static const int _sampleRate = 44100;

  /// Builds a WAV containing the classic telephony busy tone:
  /// 3 × [480 Hz for 500ms → silence 500ms] totalling ~3 s.
  static Uint8List _buildBusyToneWav() {
    const int cycleCount = 3;
    const int beepMs = 500;
    const int silenceMs = 500;
    final int beepSamples = (_sampleRate * beepMs / 1000).round();
    final int silenceSamples = (_sampleRate * silenceMs / 1000).round();
    final int totalSamples = cycleCount * (beepSamples + silenceSamples);

    final Int16List pcm = Int16List(totalSamples);
    int offset = 0;

    for (int i = 0; i < cycleCount; i++) {
      final double freq = (i % 2 == 0) ? 480.0 : 620.0;
      for (int s = 0; s < beepSamples; s++) {
        final double t = s / _sampleRate;
        // Sine wave with mild fade-in/out envelope
        final double envelope = math.min(
          1.0,
          math.min(s / 200.0, (beepSamples - s) / 200.0),
        );
        pcm[offset + s] = (math.sin(2 * math.pi * freq * t) * 28000 * envelope)
            .round()
            .clamp(-32768, 32767);
      }
      offset += beepSamples;
      // Silence
      for (int s = 0; s < silenceSamples; s++) {
        pcm[offset + s] = 0;
      }
      offset += silenceSamples;
    }

    return _wrapInWav(pcm);
  }

  /// Builds a short single-frequency beep WAV (for call-waiting notification).
  static Uint8List _buildSingleBeepWav({
    required double frequencyHz,
    required int durationMs,
  }) {
    final int samples = (_sampleRate * durationMs / 1000).round();
    final Int16List pcm = Int16List(samples);

    for (int s = 0; s < samples; s++) {
      final double t = s / _sampleRate;
      final double envelope = math.min(
        1.0,
        math.min(s / 150.0, (samples - s) / 150.0),
      );
      pcm[s] = (math.sin(2 * math.pi * frequencyHz * t) * 20000 * envelope)
          .round()
          .clamp(-32768, 32767);
    }

    return _wrapInWav(pcm);
  }

  /// Wraps raw 16-bit mono PCM samples into a standard RIFF/WAV byte array.
  static Uint8List _wrapInWav(Int16List pcm) {
    const int channels = 1;
    const int bitsPerSample = 16;
    final int byteRate = _sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;
    final int dataSize = pcm.length * blockAlign;
    final int fileSize = 36 + dataSize;

    final ByteData header = ByteData(44);
    // RIFF chunk
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49); // 'R' 'I'
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46); // 'F' 'F'
    header.setInt32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41); // 'W' 'A'
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45); // 'V' 'E'
    // fmt chunk
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D); // 'f' 'm'
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20); // 't' ' '
    header.setInt32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61); // 'd' 'a'
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61); // 't' 'a'
    header.setInt32(40, dataSize, Endian.little);

    // Combine header + PCM samples
    final Uint8List result = Uint8List(44 + dataSize);
    result.setAll(0, header.buffer.asUint8List());
    final Uint8List pcmBytes = pcm.buffer.asUint8List(
      pcm.offsetInBytes,
      pcm.lengthInBytes,
    );
    result.setAll(44, pcmBytes);
    return result;
  }
}

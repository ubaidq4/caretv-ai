import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'aws_bedrock_service.dart';

/// Current state of the speech engine.
enum TtsStatus { idle, speaking, error }

/// Reads advice aloud through the TV speakers.
///
/// Tuned for a living room: a slightly slower speech rate, full volume,
/// headings turned into short spoken sentences, and long answers split into
/// chunks so the Android 4000 character limit is never hit.
class TtsService {
  TtsService() : status = ValueNotifier<TtsStatus>(TtsStatus.idle);

  final FlutterTts _tts = FlutterTts();

  /// Listen to this to update the "Replay / Stop" button.
  final ValueNotifier<TtsStatus> status;

  Future<void>? _initFuture;
  bool _available = false;
  bool _disposed = false;
  int _session = 0;

  static const int _maxChunkLength = 3000;

  /// Configures the engine once. Safe to call many times.
  Future<void> init() => _initFuture ??= _configure();

  Future<void> _configure() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.42);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _tts.setErrorHandler((dynamic message) {
        debugPrint('TTS error: $message');
        _setStatus(TtsStatus.error);
      });
      _available = true;
    } catch (e) {
      debugPrint('TTS init failed: $e');
      _available = false;
      _setStatus(TtsStatus.error);
    }
  }

  /// Speaks [text], replacing anything that is currently being read.
  Future<void> speak(String text) async {
    await init();
    if (!_available || _disposed) return;

    final int session = ++_session;
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing was playing.
    }
    _setStatus(TtsStatus.speaking);

    for (final String chunk in _chunk(_prepareForSpeech(text))) {
      if (session != _session || _disposed) return;
      try {
        await _tts.speak(chunk).timeout(
              const Duration(minutes: 3),
              onTimeout: () => 0,
            );
      } catch (e) {
        debugPrint('TTS speak failed: $e');
        _setStatus(TtsStatus.error);
        return;
      }
    }
    if (session == _session) _setStatus(TtsStatus.idle);
  }

  /// Stops speech immediately.
  Future<void> stop() async {
    _session++;
    if (_available) {
      try {
        await _tts.stop();
      } catch (_) {
        // Ignore - the engine may already be idle.
      }
    }
    _setStatus(TtsStatus.idle);
  }

  void dispose() {
    _disposed = true;
    _session++;
    _tts.stop();
    status.dispose();
  }

  void _setStatus(TtsStatus value) {
    if (_disposed) return;
    status.value = value;
  }

  /// Turns the on-screen text into text that sounds natural when spoken.
  String _prepareForSpeech(String text) {
    final StringBuffer out = StringBuffer();
    for (final String raw in text.split('\n')) {
      String line = raw.trim();
      if (line.isEmpty) continue;

      if (AdviceFormat.isHeading(line)) {
        final String lower =
            line.substring(0, line.length - 1).toLowerCase();
        line = '${lower[0].toUpperCase()}${lower.substring(1)}.';
      } else {
        line = line.replaceFirst(RegExp(r'^-\s+'), '');
        if (!RegExp(r'[.!?:]$').hasMatch(line)) line = '$line.';
      }

      line = line
          .replaceAll('\u00B0C', ' degrees Celsius')
          .replaceAll('\u00B0F', ' degrees Fahrenheit')
          .replaceAll('%', ' percent');
      out.writeln(line);
    }
    return out.toString();
  }

  List<String> _chunk(String text) {
    final List<String> chunks = <String>[];
    final StringBuffer current = StringBuffer();
    for (final String line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      if (current.length + line.length + 1 > _maxChunkLength &&
          current.isNotEmpty) {
        chunks.add(current.toString());
        current.clear();
      }
      current.writeln(line);
    }
    if (current.isNotEmpty) chunks.add(current.toString());
    return chunks;
  }
}

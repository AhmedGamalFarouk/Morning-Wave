import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'paper_card.dart';
import 'sun_painter.dart';
import 'whole_words_text.dart';

/// A short recording, tap to start and tap to stop, cut off on its own at
/// [maxDuration]. Pops the recorded bytes on "Send this", or null if the
/// person backs out.
class VoiceNoteRecorderSheet extends StatefulWidget {
  const VoiceNoteRecorderSheet({
    super.key,
    required this.parentName,
    this.maxDuration = const Duration(seconds: 60),
  });

  final String parentName;
  final Duration maxDuration;

  @override
  State<VoiceNoteRecorderSheet> createState() => _VoiceNoteRecorderSheetState();
}

enum _Stage { idle, recording, recorded, denied }

class _VoiceNoteRecorderSheetState extends State<VoiceNoteRecorderSheet> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  var _stage = _Stage.idle;
  var _elapsed = Duration.zero;
  Timer? _ticker;
  String? _path;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _stage = _Stage.denied);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_note_${DateTime.now().microsecondsSinceEpoch}.aac';
    // Low bitrate mono: a minute of hello is a few hundred KB, well under
    // the bucket's cap.
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        numChannels: 1,
      ),
      path: path,
    );
    setState(() {
      _stage = _Stage.recording;
      _elapsed = Duration.zero;
      _path = path;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      setState(() => _elapsed += const Duration(milliseconds: 200));
      if (_elapsed >= widget.maxDuration) await _stop();
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _ticker = null;
    await _recorder.stop();
    if (mounted) setState(() => _stage = _Stage.recorded);
  }

  Future<void> _playBack() async {
    final path = _path;
    if (path == null) return;
    await _player.play(DeviceFileSource(path));
  }

  Future<void> _rerecord() async {
    await _player.stop();
    setState(() => _stage = _Stage.idle);
    await _start();
  }

  Future<void> _send() async {
    final path = _path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (mounted) Navigator.pop(context, Uint8List.fromList(bytes));
  }

  String _clock(Duration d) {
    final seconds = d.inSeconds.toString().padLeft(2, '0');
    return '0:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WholeWordsText(
              'A hello for ${widget.parentName}',
              style: text.headlineMedium,
            ),
            const SizedBox(height: 12),
            if (_stage == _Stage.denied)
              Text(
                'Morning Wave needs the microphone to record a hello. '
                'Allow it in your phone’s settings and try again.',
                style: text.bodyLarge,
              )
            else
              Text(
                _stage == _Stage.recorded
                    ? 'Listen back, then send it.'
                    : 'Tap to record up to a minute.',
                style: text.bodyLarge,
              ),
            const SizedBox(height: 24),
            Center(
              child: GestureDetector(
                onTap: switch (_stage) {
                  _Stage.idle => _start,
                  _Stage.recording => _stop,
                  _ => null,
                },
                child: PaperCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SunMark(
                        size: 88,
                        warmth: _stage == _Stage.recording ? 1.0 : 0.6,
                      ),
                      const SizedBox(height: 12),
                      WholeWordsText(switch (_stage) {
                        _Stage.idle => 'Start recording',
                        _Stage.recording => 'Stop',
                        _Stage.recorded => _clock(_elapsed),
                        _Stage.denied => 'Not allowed',
                      }, style: text.titleLarge),
                      if (_stage == _Stage.recording) ...[
                        const SizedBox(height: 6),
                        Text(_clock(_elapsed), style: text.bodyMedium),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (_stage == _Stage.recorded) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _send,
                child: const WholeWordsText('Send this'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _playBack,
                child: const WholeWordsText('Listen back'),
              ),
              TextButton(
                onPressed: _rerecord,
                child: const WholeWordsText('Record again'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await _recorder.cancel();
                if (context.mounted) Navigator.pop(context);
              },
              child: const WholeWordsText('Never mind'),
            ),
          ],
        ),
      ),
    );
  }
}

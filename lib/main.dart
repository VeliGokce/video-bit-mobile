import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() => runApp(const BitShiftApp());

class BitShiftApp extends StatelessWidget {
  const BitShiftApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BitShift',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF080808),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE21B2D),
            secondary: Color(0xFFFF5A67),
            surface: Color(0xFF151515),
          ),
          useMaterial3: true,
        ),
        home: const ConverterPage(),
      );
}

class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  static const _storage = MethodChannel('com.veligokce.bitshift/storage');
  static const _presets = <String>[
    '512 kbps',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15'
  ];

  final _bitrateController = TextEditingController(text: '5');
  String? _inputPath;
  String? _outputPath;
  String _sourceBitrate = 'Unknown';
  String? _selectedPreset = '5';
  double _progress = 0;
  int _durationMs = 0;
  bool _working = false;
  String _status = 'Ready';

  @override
  void dispose() {
    _bitrateController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _inputPath = path;
      _outputPath = null;
      _sourceBitrate = 'Reading…';
      _progress = 0;
      _status = 'Video selected';
    });
    await _readSourceBitrate(path);
  }

  Future<void> _readSourceBitrate(String path) async {
    try {
      final probe = await FFprobeKit.getMediaInformation(path);
      final properties = probe.getMediaInformation()?.getAllProperties();
      final streams =
          (properties?['streams'] as List?)?.cast<Map>() ?? const [];
      int? bitrate;
      for (final stream in streams) {
        if (stream['codec_type'] == 'video') {
          bitrate = int.tryParse('${stream['bit_rate'] ?? ''}');
          break;
        }
      }
      final format = properties?['format'] as Map?;
      bitrate ??= int.tryParse('${format?['bit_rate'] ?? ''}');
      if (!mounted || _inputPath != path) return;
      setState(() => _sourceBitrate = _formatBitrate(bitrate));
    } catch (_) {
      if (!mounted || _inputPath != path) return;
      setState(() => _sourceBitrate = 'Unknown');
    }
  }

  String _formatBitrate(int? bitsPerSecond) {
    if (bitsPerSecond == null || bitsPerSecond <= 0) return 'Unknown';
    if (bitsPerSecond < 1000000) {
      return '${(bitsPerSecond / 1000).round()} kbps';
    }
    final mbps = bitsPerSecond / 1000000;
    final hundredths = (mbps * 100).round();
    if (hundredths % 100 == 0) return '${hundredths ~/ 100} Mbps';
    if (hundredths % 10 == 0)
      return '${(hundredths / 100).toStringAsFixed(1)} Mbps';
    return '${(hundredths / 100).toStringAsFixed(2)} Mbps';
  }

  int? _targetKbps() {
    final value = double.tryParse(
      _bitrateController.text.trim().replaceAll(',', '.'),
    );
    if (value == null || value < 0.512 || value > 30) return null;
    return (value * 1000).round();
  }

  String _encoderFor(String? codec) => switch (codec) {
        'hevc' || 'h265' => 'libx265',
        'vp9' => 'libvpx-vp9',
        'av1' => 'libaom-av1',
        'mpeg4' => 'mpeg4',
        _ => 'libx264',
      };

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  Future<void> _convert() async {
    final input = _inputPath;
    final kbps = _targetKbps();
    if (input == null) {
      _message('Select a video first.');
      return;
    }
    if (kbps == null) {
      _message('Enter a bitrate from 1 to 30 Mbps.');
      return;
    }

    setState(() {
      _working = true;
      _progress = 0;
      _status = 'Inspecting source…';
    });

    try {
      final probe = await FFprobeKit.getMediaInformation(input);
      final properties = probe.getMediaInformation()?.getAllProperties();
      final format = properties?['format'] as Map?;
      final duration = double.tryParse('${format?['duration'] ?? 0}') ?? 0;
      _durationMs = (duration * 1000).round();
      final streams =
          (properties?['streams'] as List?)?.cast<Map>() ?? const [];
      Map? video;
      for (final stream in streams) {
        if (stream['codec_type'] == 'video') {
          video = stream;
          break;
        }
      }
      final encoder = _encoderFor(video?['codec_name']?.toString());

      final tempDir = await getTemporaryDirectory();
      final safeName = p
          .basenameWithoutExtension(input)
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final tempOutput = p.join(tempDir.path, '${safeName}_${kbps}kbps.mp4');
      final tempFile = File(tempOutput);
      if (await tempFile.exists()) await tempFile.delete();

      setState(() => _status = 'Changing video bitrate…');
      final command =
          '-y -i ${_quote(input)} -map 0:v:0 -map 0:a? -map_metadata 0 '
          '-c copy -c:v:0 $encoder -b:v:0 ${kbps}k '
          '-maxrate:v:0 ${kbps}k -bufsize:v:0 ${kbps * 2}k '
          '-movflags +faststart ${_quote(tempOutput)}';

      final completed = Completer<bool>();
      await FFmpegKit.executeAsync(
        command,
        (session) async {
          final code = await session.getReturnCode();
          if (!completed.isCompleted) {
            completed.complete(ReturnCode.isSuccess(code));
          }
        },
        null,
        (Statistics stats) {
          if (!mounted || _durationMs <= 0) return;
          setState(() {
            _progress = (stats.getTime() / _durationMs).clamp(0.0, 1.0);
          });
        },
      );
      if (!await completed.future) {
        throw Exception('The video could not be converted.');
      }

      final savedPath = Platform.isAndroid
          ? await _storage.invokeMethod<String>('saveToDownloads', {
              'path': tempOutput,
              'name': p.basename(tempOutput),
            })
          : await _saveToIosDocuments(tempOutput);
      if (savedPath == null) throw Exception('The output could not be saved.');

      setState(() {
        _outputPath = savedPath;
        _progress = 1;
        _status = Platform.isAndroid ? 'Saved to Downloads' : 'Saved to Files';
      });
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
      setState(() => _status = 'Conversion failed');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String> _saveToIosDocuments(String source) async {
    final documents = await getApplicationDocumentsDirectory();
    final destination = p.join(documents.path, p.basename(source));
    await File(source).copy(destination);
    return destination;
  }

  Future<void> _openOutput() async {
    final path = _outputPath;
    if (path == null) return;
    if (Platform.isAndroid && path.startsWith('content://')) {
      await _storage.invokeMethod('openVideo', {'uri': path});
    } else {
      await OpenFilex.open(path, type: 'video/mp4');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final fileName =
        _inputPath == null ? 'No video selected' : p.basename(_inputPath!);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.2,
            colors: [Color(0xFF3B0710), Color(0xFF080808)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.tune_rounded,
                        color: Color(0xFFE21B2D), size: 46),
                    const SizedBox(height: 10),
                    const Text('BITSHIFT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 5)),
                    const Text('VIDEO BITRATE CONVERTER',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF9A9A9A),
                            fontSize: 12,
                            letterSpacing: 2)),
                    const SizedBox(height: 28),
                    _Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Label('SOURCE VIDEO'),
                          const SizedBox(height: 10),
                          _MetalButton(
                              icon: Icons.video_library_outlined,
                              label: 'SELECT VIDEO',
                              onPressed: _working ? null : _pickVideo),
                          const SizedBox(height: 12),
                          Text(fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFBDBDBD))),
                          if (_inputPath != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Source bitrate: $_sourceBitrate',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFF6874),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Label('TARGET BITRATE'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _presets.map((value) {
                              final selected = _selectedPreset == value;
                              return ChoiceChip(
                                label: Text(value),
                                selected: selected,
                                onSelected: _working
                                    ? null
                                    : (_) {
                                        setState(() {
                                          _selectedPreset = value;
                                          _bitrateController.text =
                                              value == '512 kbps'
                                                  ? '0.512'
                                                  : value;
                                        });
                                      },
                                selectedColor: const Color(0xFFE21B2D),
                                backgroundColor: const Color(0xFF252525),
                                side: BorderSide(
                                    color: selected
                                        ? const Color(0xFFFF6874)
                                        : const Color(0xFF454545)),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _bitrateController,
                            enabled: !_working,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d{0,2}([.,]\d{0,3})?'))
                            ],
                            onChanged: (_) =>
                                setState(() => _selectedPreset = null),
                            decoration: const InputDecoration(
                              labelText: 'Custom value (1–30)',
                              suffixText: 'Mbps',
                              filled: true,
                              fillColor: Color(0xFF0D0D0D),
                              border: OutlineInputBorder(),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                    color: Color(0xFFE21B2D), width: 2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Resolution, frame rate, audio, metadata and extra streams stay as close to the source as the format allows.',
                            style: TextStyle(
                                color: Color(0xFF8A8A8A),
                                fontSize: 12,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_working || _progress > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _durationMs > 0 ? _progress : null,
                          minHeight: 8,
                          backgroundColor: const Color(0xFF242424),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(_status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFBDBDBD))),
                    const SizedBox(height: 14),
                    _MetalButton(
                        icon: Icons.bolt_rounded,
                        label: _working ? 'PROCESSING…' : 'CHANGE BITRATE',
                        accent: true,
                        onPressed: _working ? null : _convert),
                    if (_outputPath != null) ...[
                      const SizedBox(height: 12),
                      _MetalButton(
                          icon: Icons.folder_open_rounded,
                          label: 'GO TO VIDEO',
                          onPressed: _openOutput),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xD9121212),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF353535)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))
          ],
        ),
        child: child,
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.8,
          color: Color(0xFFD0D0D0)));
}

class _MetalButton extends StatelessWidget {
  const _MetalButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: accent
                  ? const [Color(0xFFFF3848), Color(0xFF9E0715)]
                  : const [Color(0xFF5C5C5C), Color(0xFF242424)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  accent ? const Color(0xFFFF7B85) : const Color(0xFF777777)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 8, offset: Offset(0, 4))
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
      );
}

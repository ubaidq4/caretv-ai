import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/care_option.dart';
import '../services/aws_bedrock_service.dart';
import '../services/tts_service.dart';
import '../widgets/tv_app_logo.dart';

/// Keys that act as "OK / Select" on a TV remote or game controller.
final Set<LogicalKeyboardKey> _activateKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

const Color _panel = Color(0xFF111C33);
const Color _tile = Color(0xFF1E293B);
const Color _muted = Color(0xFF94A3B8);

/// Where the pharmacy QR code points. Override with `--dart-define`:
///   CARETV_PHARMACY_WHATSAPP  digits only, international format (no "+")
///   CARETV_PHARMACY_URL       optional web ordering page (takes priority)
class _PharmacyConfig {
  _PharmacyConfig._();

  /// Demo placeholder number - replace with a real pharmacy before release.
  static const String whatsappNumber = String.fromEnvironment(
    'CARETV_PHARMACY_WHATSAPP',
    defaultValue: '15551234567',
  );

  static const String webUrl = String.fromEnvironment('CARETV_PHARMACY_URL');

  static String buildLink(CareOption option, String symptom) {
    if (webUrl.isNotEmpty) {
      final Uri uri = Uri.parse(webUrl);
      return uri.replace(queryParameters: <String, String>{
        ...uri.queryParameters,
        'category': option.id,
        'concern': symptom,
        'source': 'caretv_ai',
      }).toString();
    }
    final String message =
        'Hello, I need help ordering medicines/supplies for "$symptom" '
        '(${option.title}). Sent from CareTV AI.';
    return 'https://wa.me/$whatsappNumber?text=${Uri.encodeComponent(message)}';
  }

  static bool get isWhatsApp => webUrl.isEmpty;
}

/// Shows AI guidance for one category. The viewer can switch concern with the
/// D-Pad; every new answer is requested from AWS Bedrock and read aloud.
class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.option});

  final CareOption option;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final AWSBedrockService _bedrock;
  late final TtsService _tts;
  late final List<FocusNode> _symptomNodes;
  final FocusNode _responseNode = FocusNode(debugLabel: 'response');
  final ScrollController _scroll = ScrollController();

  late String _symptom;
  AdviceResult? _result;
  bool _loading = true;
  bool _responseFocused = false;
  int _requestId = 0;

  CareOption get _option => widget.option;

  @override
  void initState() {
    super.initState();
    _bedrock = context.read<AWSBedrockService>();
    _tts = context.read<TtsService>();
    _symptomNodes = List<FocusNode>.generate(
      _option.symptoms.length,
      (int i) => FocusNode(debugLabel: 'symptom_$i'),
    );
    _symptom = _option.symptoms.first;
    unawaited(_loadAdvice(_symptom));
  }

  @override
  void dispose() {
    _requestId++;
    unawaited(_tts.stop());
    for (final FocusNode node in _symptomNodes) {
      node.dispose();
    }
    _responseNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAdvice(String symptom) async {
    final int id = ++_requestId;
    await _tts.stop();
    if (!mounted || id != _requestId) return;

    setState(() {
      _symptom = symptom;
      _loading = true;
      _result = null;
    });

    final AdviceResult result =
        await _bedrock.getAdvice(option: _option, symptom: symptom);
    if (!mounted || id != _requestId) return;

    setState(() {
      _result = result;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_tts.speak(result.text));
  }

  void _toggleVoice() {
    final AdviceResult? result = _result;
    if (result == null) return;
    if (_tts.status.value == TtsStatus.speaking) {
      unawaited(_tts.stop());
    } else {
      unawaited(_tts.speak(result.text));
    }
  }

  KeyEventResult _onResponseKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;

    if (event is KeyDownEvent && _activateKeys.contains(key)) {
      _toggleVoice();
      return KeyEventResult.handled;
    }

    if (!_scroll.hasClients) return KeyEventResult.ignored;
    final ScrollPosition pos = _scroll.position;
    const double step = 140;

    if (key == LogicalKeyboardKey.arrowDown &&
        pos.pixels < pos.maxScrollExtent - 1) {
      _scroll.animateTo(
        math.min(pos.pixels + step, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && pos.pixels > 1) {
      _scroll.animateTo(
        math.max(pos.pixels - step, 0),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF0F172A), Color(0xFF14213D)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
          child: Column(
            children: <Widget>[
              _buildHeader(),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 4, child: _buildLeftPanel()),
                    const SizedBox(width: 22),
                    Expanded(flex: 7, child: _buildResponsePanel()),
                    const SizedBox(width: 22),
                    Expanded(flex: 3, child: _buildQrPanel()),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: <Widget>[
        const TVAppLogo(size: 52),
        const SizedBox(width: 16),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _option.accent.withOpacity(0.2),
          ),
          child: Icon(_option.icon, color: _option.accent, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _option.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const Text(
                'CareTV AI Assistant - Powered by AWS Bedrock',
                style: TextStyle(fontSize: 15, color: Color(0xFF38BDF8)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeftPanel() {
    return SingleChildScrollView(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Select a concern',
            style: TextStyle(fontSize: 17, color: _muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < _option.symptoms.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FocusTile(
                focusNode: _symptomNodes[i],
                autofocus: i == 0,
                accent: _option.accent,
                selected: _symptom == _option.symptoms[i],
                onActivate: () => unawaited(_loadAdvice(_option.symptoms[i])),
                builder: (BuildContext context, bool focused) {
                  final bool selected = _symptom == _option.symptoms[i];
                  return Row(
                    children: <Widget>[
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected || focused ? _option.accent : _muted,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _option.symptoms[i],
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TtsStatus>(
            valueListenable: _tts.status,
            builder: (BuildContext context, TtsStatus status, Widget? _) {
              final bool speaking = status == TtsStatus.speaking;
              return _FocusTile(
                accent: const Color(0xFF38BDF8),
                onActivate: _toggleVoice,
                builder: (BuildContext context, bool focused) => Row(
                  children: <Widget>[
                    Icon(
                      speaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                      color: const Color(0xFF38BDF8),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        speaking
                            ? 'Stop Voice'
                            : (status == TtsStatus.error
                                ? 'Voice Unavailable - Retry'
                                : 'Replay Voice'),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _FocusTile(
            accent: Colors.white,
            onActivate: () => Navigator.of(context).maybePop(),
            builder: (BuildContext context, bool focused) => const Row(
              children: <Widget>[
                Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Back to Categories',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsePanel() {
    final bool f = _responseFocused;
    return Focus(
      focusNode: _responseNode,
      onFocusChange: (bool value) => setState(() => _responseFocused = value),
      onKeyEvent: _onResponseKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: f ? _option.accent : Colors.white12,
            width: f ? 3 : 1.5,
          ),
          boxShadow: f
              ? <BoxShadow>[
                  BoxShadow(
                    color: _option.accent.withOpacity(0.4),
                    blurRadius: 28,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: _loading ? _buildLoading() : _buildAdvice(),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SpinKitPulse(color: _option.accent, size: 72),
          const SizedBox(height: 20),
          Text(
            'Analyzing "$_symptom" with AWS Bedrock...',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, color: Color(0xFFCBD5E1)),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvice() {
    final AdviceResult? result = _result;
    if (result == null) return const SizedBox.shrink();

    final Color chipColor =
        result.isLive ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: chipColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: chipColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.circle, size: 10, color: chipColor),
                  const SizedBox(width: 8),
                  Text(
                    result.isLive
                        ? 'LIVE - ${result.modelLabel}'
                        : 'OFFLINE DEMO',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: chipColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _symptom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFCBD5E1),
                ),
              ),
            ),
          ],
        ),
        if (result.note != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(result.note!, style: const TextStyle(fontSize: 13, color: _muted)),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _renderAdvice(result.text),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _responseFocused
              ? 'Up / Down: scroll   |   OK: play or stop voice'
              : 'Move right from the list to scroll the full answer',
          style: const TextStyle(fontSize: 13, color: _muted),
        ),
      ],
    );
  }

  List<Widget> _renderAdvice(String text) {
    final List<Widget> widgets = <Widget>[];
    for (final String raw in text.split('\n')) {
      final String line = raw.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else if (AdviceFormat.isHeading(line)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            line.trim(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: _option.accent,
            ),
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line,
            style: const TextStyle(fontSize: 19, height: 1.45, color: Colors.white),
          ),
        ));
      }
    }
    return widgets;
  }

  Widget _buildQrPanel() {
    final String link = _PharmacyConfig.buildLink(_option, _symptom);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12, width: 1.5),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double qrSize = math.max(110, math.min(constraints.maxWidth - 20, 210));
          return SingleChildScrollView(
            child: Column(
              children: <Widget>[
                const Icon(Icons.local_pharmacy_rounded,
                    color: Color(0xFF2DD4BF), size: 30),
                const SizedBox(height: 6),
                const Text(
                  'Order Medicines & Supplies',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(
                    data: link,
                    version: QrVersions.auto,
                    size: qrSize,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _PharmacyConfig.isWhatsApp
                      ? 'Scan with your phone camera to chat with a pharmacy on WhatsApp.'
                      : 'Scan with your phone camera to open the pharmacy ordering page.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.35, color: _muted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    return const Row(
      children: <Widget>[
        Icon(Icons.info_outline_rounded, size: 18, color: _muted),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'General information only - not a substitute for professional medical or veterinary advice. In an emergency, call your local emergency number.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }
}

/// A focusable list item / button with a visible TV focus state.
class _FocusTile extends StatefulWidget {
  const _FocusTile({
    required this.onActivate,
    required this.builder,
    required this.accent,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
  });

  final VoidCallback onActivate;
  final Widget Function(BuildContext context, bool focused) builder;
  final Color accent;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool selected;

  @override
  State<_FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<_FocusTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bool f = _focused;
    final Color accent = widget.accent;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (bool value) => setState(() => _focused = value),
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent && _activateKeys.contains(event.logicalKey)) {
          widget.onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onActivate,
        child: AnimatedScale(
          scale: f ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: f
                  ? accent.withOpacity(0.25)
                  : (widget.selected ? accent.withOpacity(0.12) : _tile),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: f
                    ? accent
                    : (widget.selected ? accent.withOpacity(0.6) : Colors.white12),
                width: f ? 3 : 1.5,
              ),
              boxShadow: f
                  ? <BoxShadow>[
                      BoxShadow(color: accent.withOpacity(0.45), blurRadius: 22),
                    ]
                  : const <BoxShadow>[],
            ),
            child: widget.builder(context, f),
          ),
        ),
      ),
    );
  }
}

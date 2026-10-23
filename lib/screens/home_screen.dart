import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/care_option.dart';
import '../widgets/tv_app_logo.dart';
import 'detail_screen.dart';

/// Keys that act as "OK / Select" on a TV remote or game controller.
final Set<LogicalKeyboardKey> _activateKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

const Color _sky = Color(0xFF38BDF8);
const Color _muted = Color(0xFF94A3B8);

/// 10-foot home screen: a 2 x 2 grid of care categories navigated with the
/// D-Pad. Flutter's directional focus traversal moves between the cards.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, CareOption option) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => DetailScreen(option: option),
        transitionsBuilder: (_, Animation<double> animation, __, Widget child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

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
          // Keeps content inside the TV safe area (overscan).
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _Header(),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: const <Widget>[
                  Text(
                    'How can we help today?',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'Choose a category with your remote.',
                    style: TextStyle(fontSize: 18, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: _CategoryGrid(
                  onSelected: (CareOption o) => _open(context, o),
                ),
              ),
              const _Footer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const TVAppLogo(size: 72),
        const SizedBox(width: 20),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'CareTV AI Assistant',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Icon(Icons.cloud_rounded, color: _sky, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Powered by AWS Bedrock',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: _sky,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: const Text(
            'Fire TV Edition',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.gamepad_rounded, size: 20, color: _muted),
            SizedBox(width: 8),
            Text(
              'D-Pad: move   |   OK: open   |   Back: exit',
              style: TextStyle(fontSize: 16, color: _muted),
            ),
          ],
        ),
        SizedBox(height: 4),
        Text(
          'General information only - not a substitute for professional medical or veterinary advice. In an emergency, call your local emergency number.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.onSelected});

  final ValueChanged<CareOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<CareOption> options = CareOption.all;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = 28;
        const double inset = 14;
        final int columns = constraints.maxWidth >= 700 ? 2 : 1;
        final int rows = (options.length / columns).ceil();

        final double availW = constraints.maxWidth - inset * 2;
        final double availH = constraints.maxHeight - inset * 2;
        final double cardW = (availW - spacing * (columns - 1)) / columns;
        final double cardH =
            math.max(170, (availH - spacing * (rows - 1)) / rows);

        return GridView.count(
          crossAxisCount: columns,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: cardW / cardH,
          padding: const EdgeInsets.all(inset),
          clipBehavior: Clip.none,
          children: <Widget>[
            for (int i = 0; i < options.length; i++)
              _CareCard(
                option: options[i],
                autofocus: i == 0,
                onSelected: () => onSelected(options[i]),
              ),
          ],
        );
      },
    );
  }
}

/// A category card with a clear focus state: scale-up, glowing border and a
/// brighter background when the D-Pad highlights it.
class _CareCard extends StatefulWidget {
  const _CareCard({
    required this.option,
    required this.onSelected,
    this.autofocus = false,
  });

  final CareOption option;
  final VoidCallback onSelected;
  final bool autofocus;

  @override
  State<_CareCard> createState() => _CareCardState();
}

class _CareCardState extends State<_CareCard> {
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CareOption option = widget.option;
    final Color accent = option.accent;
    final bool f = _focused;

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onFocusChange: (bool value) => setState(() => _focused = value),
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent && _activateKeys.contains(event.logicalKey)) {
          widget.onSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedScale(
          scale: f ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: f
                    ? <Color>[accent.withOpacity(0.32), const Color(0xFF1E293B)]
                    : <Color>[const Color(0xFF1E293B), const Color(0xFF172033)],
              ),
              border: Border.all(
                color: f ? accent : Colors.white12,
                width: f ? 3.5 : 1.5,
              ),
              boxShadow: f
                  ? <BoxShadow>[
                      BoxShadow(
                        color: accent.withOpacity(0.55),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withOpacity(f ? 0.35 : 0.18),
                      ),
                      child: Icon(option.icon, color: accent, size: 32),
                    ),
                    const Spacer(),
                    Text(
                      '${option.symptoms.length} common concerns',
                      style: const TextStyle(fontSize: 15, color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  option.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    option.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.35,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Text(
                      f ? 'Press OK to open' : 'Open',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, color: accent, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

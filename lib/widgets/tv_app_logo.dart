import 'dart:math' as math;

import 'package:flutter/material.dart';

/// CareTV AI logo: a TV screen, a medical cross and an AI sparkle.
///
/// Drawn entirely with [CustomPaint], so no PNG asset is needed at build time.
/// `tools/generate_assets.py` mirrors this geometry to produce the launcher
/// icons and the Fire TV banner PNGs.
class TVAppLogo extends StatelessWidget {
  const TVAppLogo({
    super.key,
    this.size = 96,
    this.showBackground = true,
  });

  /// Width and height of the (square) logo.
  final double size;

  /// Draws the rounded gradient tile behind the TV. Turn off when the logo
  /// sits on a dark surface that already provides contrast.
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CareTV AI logo',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: TVLogoPainter(showBackground: showBackground),
        ),
      ),
    );
  }
}

/// Paints the CareTV AI mark inside a square area.
class TVLogoPainter extends CustomPainter {
  const TVLogoPainter({this.showBackground = true});

  final bool showBackground;

  static const Color _slate = Color(0xFF0F172A);
  static const Color _cross = Color(0xFFF43F5E);
  static const Color _sparkle = Color(0xFFFBBF24);

  @override
  void paint(Canvas canvas, Size size) {
    final double s = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);

    // Background tile.
    if (showBackground) {
      final Rect full = Rect.fromLTWH(0, 0, s, s);
      final Paint bg = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0EA5E9), Color(0xFF14B8A6)],
        ).createShader(full);
      canvas.drawRRect(
        RRect.fromRectAndRadius(full, Radius.circular(s * 0.22)),
        bg,
      );
    }

    // TV body.
    final RRect tv = RRect.fromLTRBR(
      s * 0.13,
      s * 0.20,
      s * 0.87,
      s * 0.67,
      Radius.circular(s * 0.07),
    );
    canvas.drawRRect(tv, Paint()..color = _slate);
    canvas.drawRRect(
      tv,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..color = Colors.white,
    );

    // TV stand.
    final Paint stand = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.5, s * 0.67), Offset(s * 0.5, s * 0.77), stand);
    canvas.drawLine(Offset(s * 0.34, s * 0.79), Offset(s * 0.66, s * 0.79), stand);

    // Medical cross.
    final Paint cross = Paint()..color = _cross;
    final Offset c = Offset(s * 0.42, s * 0.435);
    final double arm = s * 0.13;
    final double thick = s * 0.075;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: arm * 2, height: thick),
        Radius.circular(thick * 0.35),
      ),
      cross,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: thick, height: arm * 2),
        Radius.circular(thick * 0.35),
      ),
      cross,
    );

    // AI sparkles.
    _drawSparkle(canvas, Offset(s * 0.69, s * 0.35), s * 0.12,
        Paint()..color = _sparkle);
    _drawSparkle(canvas, Offset(s * 0.72, s * 0.55), s * 0.05,
        Paint()..color = Colors.white);

    canvas.restore();
  }

  /// A four-pointed star.
  void _drawSparkle(Canvas canvas, Offset center, double radius, Paint paint) {
    final Path path = Path();
    for (int i = 0; i < 8; i++) {
      final double r = i.isEven ? radius : radius * 0.28;
      final double angle = -math.pi / 2 + i * math.pi / 4;
      final Offset p = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant TVLogoPainter oldDelegate) =>
      oldDelegate.showBackground != showBackground;
}

/// 16:9 launcher banner (logo + wordmark), matching Android TV / Fire TV
/// banner proportions (320 x 180).
class TVBannerLogo extends StatelessWidget {
  const TVBannerLogo({super.key, this.width = 320});

  final double width;

  @override
  Widget build(BuildContext context) {
    final double h = width * 9 / 16;
    return SizedBox(
      width: width,
      height: h,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF0F172A), Color(0xFF134E4A)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(h * 0.12),
          child: Row(
            children: <Widget>[
              TVAppLogo(size: h * 0.62, showBackground: false),
              SizedBox(width: h * 0.08),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'CareTV AI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: h * 0.145,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Smart care on your TV',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: h * 0.07,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

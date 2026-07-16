import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../theme/shape_theme.dart';
import '../widgets/brand.dart';
import 'editor_screen.dart';

/// A brief, witty, *busy* splash. A field of pastel shapes drifts and spins
/// behind a calm, simple mark and wordmark while persistence boots in the
/// background; it dissolves into the editor once both finish.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _quips = [
    'Negotiating with negative space…',
    'Teaching circles to behave like squares…',
    'Convincing vectors they are not just math…',
    'Aligning pixels to a higher purpose…',
    'Warming up the Béziers…',
    'Rounding corners, sharpening ideas…',
    'Measuring twice, snapping once…',
  ];
  late final String _quip = _quips[math.Random().nextInt(_quips.length)];

  late final AnimationController _ambient = AnimationController(
      vsync: this, duration: const Duration(seconds: 12))
    ..repeat();
  late final AnimationController _draw = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();

  /// The splash is the loading screen, so it stays for [_minShow] or however
  /// long the project takes to load — whichever is longer.
  static const _minShow = Duration(seconds: 5);

  /// Drives the progress bar. It creeps to 92% across the minimum window and
  /// only completes when the document is actually ready, so a slow load holds
  /// the bar short of full rather than lying about being done.
  late final AnimationController _bar =
      AnimationController(vsync: this, duration: _minShow)
        ..animateTo(0.92, curve: Curves.easeOut);

  late final List<_Floater> _floaters = _buildFloaters();
  bool _leaving = false;

  // A more vivid, saturated palette just for the splash's confetti.
  static const _confetti = [
    Color(0xFF8B7BE8), Color(0xFF5BD6A8), Color(0xFFFFB070),
    Color(0xFFFF8FB0), Color(0xFF6FB7F2), Color(0xFFF6CE5A),
    Color(0xFFEE7AD9), Color(0xFF7CE0D0),
  ];

  List<_Floater> _buildFloaters() {
    final r = math.Random(7);
    return List.generate(30, (i) {
      return _Floater(
        kind: i % 4,
        color: _confetti[i % _confetti.length],
        x: r.nextDouble(),
        y: r.nextDouble(),
        size: 18 + r.nextDouble() * 74,
        phase: r.nextDouble() * math.pi * 2,
        speed: 0.4 + r.nextDouble() * 1.1,
        spin: (r.nextBool() ? 1 : -1) * (0.3 + r.nextDouble()),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final model = AppScope.read(context);
    final started = DateTime.now();
    await model.bootstrap();
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minShow) await Future.delayed(_minShow - elapsed);
    if (!mounted) return;
    // Loaded and the minimum has elapsed — fill the bar, then hand over.
    await _bar.animateTo(1, duration: const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _leaving = true);
    await Future.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 440),
      pageBuilder: (_, __, ___) => const EditorScreen(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  void dispose() {
    _ambient.dispose();
    _draw.dispose();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedOpacity(
        duration: const Duration(milliseconds: 340),
        opacity: _leaving ? 0 : 1,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ShapeColors.bgTop,
                ShapeColors.bgMid,
                ShapeColors.bgBottom
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Busy, drifting pastel field.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _ambient,
                  builder: (context, _) => CustomPaint(
                    painter: _FloatersPainter(_floaters, _ambient.value),
                  ),
                ),
              ),
              // Soft scrim so the branding reads over the busy field.
              Center(
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      ShapeColors.paper.withValues(alpha: 0.86),
                      ShapeColors.paper.withValues(alpha: 0.0),
                    ], stops: const [0.55, 1.0]),
                  ),
                ),
              ),
              // Calm foreground branding (enlarged).
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: Listenable.merge([_draw, _ambient]),
                      builder: (context, _) {
                        final t = Curves.easeOutBack
                            .transform(_draw.value.clamp(0.0, 1.0));
                        return Transform.rotate(
                          angle: 0.05 * math.sin(_ambient.value * math.pi * 2),
                          child: Transform.scale(
                            scale: 0.85 + 0.15 * t,
                            child:
                                ShapeMark(size: 132, progress: _draw.value),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 26),
                    Transform.scale(
                      scale: 1.5,
                      // The wordmark's own credit is left-aligned and would be
                      // scaled to ~18px here; the splash sets its own centred
                      // one below instead.
                      child: const Wordmark(large: true, showCredit: false),
                    ),
                    const SizedBox(height: 18),
                    // Credit — rises in just after the wordmark settles.
                    AnimatedBuilder(
                      animation: _draw,
                      builder: (context, child) {
                        final t = Curves.easeOut.transform(
                            ((_draw.value - 0.45) / 0.55).clamp(0.0, 1.0));
                        return Opacity(
                          opacity: t,
                          child: Transform.translate(
                              offset: Offset(0, 8 * (1 - t)), child: child),
                        );
                      },
                      child: const _Credit(),
                    ),
                    const SizedBox(height: 34),
                    SizedBox(
                      width: 280,
                      child: Text(
                        _quip,
                        textAlign: TextAlign.center,
                        style: ShapeText.labelLG.copyWith(
                            color: ShapeColors.secondaryText,
                            fontWeight: FontWeight.w500,
                            height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _LoadingBar(_bar),
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

/// "by dio.stesso", set as a deliberate credit line: hairline rules either side
/// of an italic periwinkle signature, centred under the wordmark.
class _Credit extends StatelessWidget {
  const _Credit();

  @override
  Widget build(BuildContext context) {
    Widget rule() => Container(
          width: 28,
          height: 1,
          color: ShapeColors.shapeBlue.withValues(alpha: 0.26),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        rule(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Text(
            'by dio.stesso',
            style: ShapeText.labelMD.copyWith(
              color: ShapeColors.shapeBlue.withValues(alpha: 0.88),
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.3,
              fontSize: 13,
            ),
          ),
        ),
        rule(),
      ],
    );
  }
}

/// The splash's progress bar. Picks up visually where the HTML boot bar left
/// off, so engine-load and project-load read as one continuous screen.
class _LoadingBar extends StatelessWidget {
  const _LoadingBar(this.progress);
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        height: 4,
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, _) => ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(children: [
              Container(color: ShapeColors.shapeBlue.withValues(alpha: 0.16)),
              FractionallySizedBox(
                widthFactor: progress.value.clamp(0.0, 1.0),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [ShapeColors.mint, ShapeColors.shapeBlue]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _Floater {
  _Floater({
    required this.kind,
    required this.color,
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.speed,
    required this.spin,
  });
  final int kind;
  final Color color;
  final double x, y, size, phase, speed, spin;
}

class _FloatersPainter extends CustomPainter {
  _FloatersPainter(this.floaters, this.t);
  final List<_Floater> floaters;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in floaters) {
      final drift = math.sin(t * 2 * math.pi * f.speed + f.phase);
      final drift2 = math.cos(t * 2 * math.pi * f.speed * 0.7 + f.phase);
      final cx = f.x * size.width + drift * 30;
      final cy = (f.y * size.height + (t * f.speed * 120)) % (size.height + 120) -
          60 +
          drift2 * 16;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(t * 2 * math.pi * f.spin + f.phase);
      final paint = Paint()..color = f.color.withValues(alpha: 0.30);
      final s = f.size;
      switch (f.kind) {
        case 0:
          canvas.drawCircle(Offset.zero, s / 2, paint);
        case 1:
          canvas.drawRRect(
              RRect.fromRectXY(
                  Rect.fromCenter(
                      center: Offset.zero, width: s, height: s),
                  s * 0.22,
                  s * 0.22),
              paint);
        case 2:
          // ring
          canvas.drawCircle(
              Offset.zero,
              s / 2,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = s * 0.16
                ..color = f.color.withValues(alpha: 0.30));
        default:
          final p = Path()
            ..moveTo(0, -s / 2)
            ..lineTo(s / 2, s / 2)
            ..lineTo(-s / 2, s / 2)
            ..close();
          canvas.drawPath(p, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FloatersPainter old) => old.t != t;
}

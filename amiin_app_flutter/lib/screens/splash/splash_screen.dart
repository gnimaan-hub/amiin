// ─── SplashScreen — écran de lancement Amiin ─────────────────────────────────
//
// Port natif de l'animation générée (images/Animation du logo splashscreen) :
//   · le mark « A » se matérialise en particules qui convergent depuis un
//     anneau autour du centre (échantillonnées dans le PNG officiel)
//   · fondu vers le logo net, puis balayage lumineux masqué au logo
//   · nom AMIIN + sous-titre qui montent, trois points de chargement
//
// Affiché dès la première frame (main() ne bloque plus). Pendant que
// l'animation tourne, ensureBootstrap() ouvre Hive/boxes et authService.init()
// restaure la session (offline-first, sans attendre le backend).
//
// Le splash natif (flutter_native_splash) montre déjà le même mark sur le
// même fond — la transition est invisible, aucun écran noir.
// Clair : fond Sel d'Assal + mark turquoise · Sombre : Encre de Nuit + crème.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../services/auth_service.dart';
import '../../services/bootstrap.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Formation du mark en particules (une fois)
  late final AnimationController _formCtrl;
  // Balayage lumineux + pulsation des points (en boucle)
  late final AnimationController _loopCtrl;
  // Montée du texte (une fois, après la formation)
  late final AnimationController _riseCtrl;

  _ParticleField? _particles;
  bool _formed = false;

  Timer? _taglineTimer;
  int _taglineIndex = 0;

  static const _taglines = [
    'Votre assistant personnel',
    'Vos démarches en confiance',
    'Djibouti en poche',
    'Au cœur de Djibouti',
    'Une envie, une adresse',
    'De quoi avez-vous envie ?',
    'Un assistant qui connaît Djibouti',
  ];

  // Durées calquées sur l'animation d'origine (DUR 0.95 s + délais ≤ 0.55 s)
  static const _formDuration = Duration(milliseconds: 1600);

  bool get _isDark =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;

  String get _logoAsset => _isDark
      ? 'assets/logo/amiin-A-selassal.png'
      : 'assets/logo/amiin-A-turquoise.png';

  @override
  void initState() {
    super.initState();

    _formCtrl = AnimationController(duration: _formDuration, vsync: this);
    _loopCtrl = AnimationController(
      duration: const Duration(milliseconds: 3400),
      vsync: this,
    )..repeat();
    _riseCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _formCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _formed = true);
        _riseCtrl.forward();
      }
    });

    _taglineTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (mounted && _formed) {
        setState(() => _taglineIndex = (_taglineIndex + 1) % _taglines.length);
      }
    });

    _startLoading();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // L'asset dépend de la luminosité plateforme → préparé ici, une fois.
    _particles ??= _initParticles();
  }

  _ParticleField _initParticles() {
    final field = _ParticleField(assetPath: _logoAsset);
    field.load().then((_) {
      if (mounted) {
        _formCtrl.forward();
        setState(() {});
      }
    }).catchError((Object e) {
      // Si l'échantillonnage échoue, on montre directement le logo net
      debugPrint('Particules : $e');
      if (mounted) {
        setState(() => _formed = true);
        _riseCtrl.forward();
      }
    });
    return field;
  }

  Future<void> _startLoading() async {
    // Temps minimum : formation (1.6 s) + une respiration du logo net
    final minSplash = Future.delayed(const Duration(milliseconds: 2800));

    try {
      await Future.wait([
        ensureBootstrap(),
        authService.init(),
      ]);
    } catch (e) {
      // Un échec d'init ne doit jamais laisser l'utilisateur bloqué ici
      debugPrint('Bootstrap : $e');
    }
    await minSplash;
    if (!mounted) return;

    // IMPORTANT : la navigation ne dépend que de Future.delayed — jamais
    // d'un TickerFuture. Si l'app est en arrière-plan, les tickers sont
    // suspendus et un `await animateTo(...)` ne se résoudrait jamais.
    context.go(authService.isLoggedIn ? '/home' : '/login');
  }

  @override
  void dispose() {
    _taglineTimer?.cancel();
    _formCtrl.dispose();
    _loopCtrl.dispose();
    _riseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark;
    final bg = dark ? ColorsAmiin.encreNuit : ColorsAmiin.selAssal;
    final ink = dark ? ColorsAmiin.onDark : ColorsAmiin.ink;
    final accent = dark ? ColorsAmiin.turquoiseMid : ColorsAmiin.turquoise;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final logoSize = math.min(w * 0.56, h * 0.28).clamp(120.0, 300.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Halo radial doux derrière le logo (comme le fond d'origine)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.18),
                      radius: 1.05,
                      colors: dark
                          ? const [Color(0xFF1C2E52), ColorsAmiin.encreNuit]
                          : const [Color(0xFFFFFFFF), ColorsAmiin.selAssal],
                    ),
                  ),
                ),

                SafeArea(
                  child: Column(
                    children: [
                      const Spacer(flex: 5),

                      // ── Mark : particules → logo net + balayage ─────────
                      SizedBox(
                        width: logoSize,
                        height: logoSize,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Logo net (apparaît sous le nuage de particules)
                            AnimatedOpacity(
                              opacity: _formed ? 1 : 0,
                              duration: const Duration(milliseconds: 600),
                              child: AnimatedBuilder(
                                animation: _loopCtrl,
                                builder: (context, child) => _LightSweep(
                                  sweep: _loopCtrl.value,
                                  enabled: _formed,
                                  child: child!,
                                ),
                                child: Image.asset(
                                  _logoAsset,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                            ),
                            // Particules en formation
                            if (!_formed && _particles != null)
                              AnimatedBuilder(
                                animation: _formCtrl,
                                builder: (context, _) => CustomPaint(
                                  painter: _ParticlePainter(
                                    field: _particles!,
                                    t: _formCtrl.value *
                                        _formDuration.inMilliseconds /
                                        1000.0,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 26),

                      // ── AMIIN + sous-titre (montent après la formation) ──
                      AnimatedBuilder(
                        animation: _riseCtrl,
                        builder: (context, child) {
                          final e =
                              Curves.easeOutCubic.transform(_riseCtrl.value);
                          return Opacity(
                            opacity: e,
                            child: Transform.translate(
                              offset: Offset(0, 18 * (1 - e)),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            Text(
                              'AMIIN',
                              style: TextStyle(
                                fontFamily: FontFamily.geoBold,
                                fontWeight: FontWeight.w800,
                                fontSize: (w * 0.105).clamp(32.0, 50.0),
                                letterSpacing: (w * 0.028).clamp(8.0, 14.0),
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ASSISTANT IA · DJIBOUTI',
                              style: TextStyle(
                                fontFamily: FontFamily.mono,
                                fontSize: 11,
                                letterSpacing: 3.2,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(flex: 3),

                      // ── Trois points de chargement ───────────────────────
                      AnimatedBuilder(
                        animation: _loopCtrl,
                        builder: (context, _) => _LoadingDots(
                          // 3400 ms de boucle ≈ 2,8 cycles de 1,2 s d'origine
                          phase: (_loopCtrl.value * 3400 / 1200) % 1.0,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Phrases d'attente
                      SizedBox(
                        height: 24,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 480),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                begin: const Offset(0, 0.6),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Text(
                            _formed ? _taglines[_taglineIndex] : '',
                            key: ValueKey(_formed ? _taglineIndex : -1),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: FontFamily.sans,
                              fontWeight: FontWeight.w300,
                              fontSize: 14,
                              letterSpacing: 0.4,
                              color: ink.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),

                      const Spacer(flex: 2),

                      // Signature discrète
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(
                          'DJIBOUTI',
                          style: TextStyle(
                            fontFamily: FontFamily.mono,
                            fontSize: 10,
                            letterSpacing: 4,
                            color: ink.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Champ de particules échantillonné dans le PNG du mark ────────────────────

class _Particle {
  final double tx, ty; // cible (0..1 dans la boîte du logo)
  final double sx, sy; // départ (anneau autour du centre)
  final Color color;
  final double delay; // secondes

  _Particle({
    required this.tx,
    required this.ty,
    required this.sx,
    required this.sy,
    required this.color,
    required this.delay,
  });
}

class _ParticleField {
  final String assetPath;
  List<_Particle> particles = const [];
  bool loaded = false;

  _ParticleField({required this.assetPath});

  Future<void> load() async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      // Échantillonnage : ~120 px suffisent pour un nuage dense
      targetWidth: 120,
    );
    final img = (await codec.getNextFrame()).image;
    final bytes =
        (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    final w = img.width, h = img.height;
    final out = <_Particle>[];
    final rnd = math.Random(7);
    const step = 2;
    for (int y = 0; y < h; y += step) {
      for (int x = 0; x < w; x += step) {
        final i = (y * w + x) * 4;
        final a = bytes.getUint8(i + 3);
        if (a > 130) {
          final ang = rnd.nextDouble() * math.pi * 2;
          final dist = 0.9 + rnd.nextDouble() * 1.4; // en fractions de boîte
          out.add(_Particle(
            tx: x / w,
            ty: y / h,
            sx: 0.5 + math.cos(ang) * dist,
            sy: 0.5 + math.sin(ang) * dist,
            color: Color.fromARGB(
              255,
              bytes.getUint8(i),
              bytes.getUint8(i + 1),
              bytes.getUint8(i + 2),
            ),
            delay: rnd.nextDouble() * 0.5,
          ));
        }
      }
    }
    img.dispose();
    particles = out;
    loaded = true;
  }
}

class _ParticlePainter extends CustomPainter {
  final _ParticleField field;
  final double t; // secondes écoulées

  static const _dur = 0.95; // durée de vol d'une particule (comme l'original)

  _ParticlePainter({required this.field, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    if (!field.loaded) return;
    final paint = Paint();
    final ps = (size.width / 110).clamp(1.6, 3.2); // taille d'un grain

    for (final p in field.particles) {
      final lp = ((t - p.delay) / _dur).clamp(0.0, 1.0);
      final e = 1 - math.pow(1 - lp, 3).toDouble(); // easeOutCubic
      final x = (p.sx + (p.tx - p.sx) * e) * size.width;
      final y = (p.sy + (p.ty - p.sy) * e) * size.height;
      paint.color = p.color.withValues(alpha: (lp * 1.4).clamp(0.0, 1.0));
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: ps, height: ps),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.t != t || old.field != field;
}

// ── Balayage lumineux masqué au logo (amSweep de l'original) ─────────────────

class _LightSweep extends StatelessWidget {
  final double sweep; // 0..1 sur la boucle de 3,4 s
  final bool enabled;
  final Widget child;

  const _LightSweep({
    required this.sweep,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    // La bande traverse pendant les premiers 18 % du cycle, puis repos
    final local = (sweep / 0.18).clamp(0.0, 1.0);
    final x = ui.lerpDouble(-1.8, 1.8, Curves.easeInOut.transform(local))!;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment(x - 0.45, -0.3),
        end: Alignment(x + 0.45, 0.3),
        colors: const [
          Color(0x00FFFFFF),
          Color(0xB3FFFFFF),
          Color(0x00FFFFFF),
        ],
      ).createShader(bounds),
      child: child,
    );
  }
}

// ── Trois points de chargement (amDot de l'original) ─────────────────────────

class _LoadingDots extends StatelessWidget {
  final double phase; // 0..1
  final Color color;

  const _LoadingDots({required this.phase, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 9),
          _dot(((phase - i * 0.15) % 1.0 + 1.0) % 1.0),
        ],
      ],
    );
  }

  Widget _dot(double p) {
    // 0.28 → 1 → 0.28 (sinus), échelle 0.72 → 1
    final s = math.sin(p * math.pi);
    return Opacity(
      opacity: 0.28 + 0.72 * s,
      child: Transform.scale(
        scale: 0.72 + 0.28 * s,
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

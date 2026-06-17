import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/amiin_logo.dart';
import '../../widgets/horizon_line.dart';
import '../../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _lineOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _logoScale = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _logoOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _textOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.52, 0.80, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.52, 0.80, curve: Curves.easeOut),
      ),
    );
    _lineOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.70, 1.0, curve: Curves.easeOut),
      ),
    );

    // Lance l'animation ET l'init auth en parallèle, attend les deux
    Future.wait([
      _ctrl.forward(),
      authService.init(),
    ]).then((_) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) {
          context.go(authService.isLoggedIn ? '/home' : '/login');
        }
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.encreNuit,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: const AmiinLogo(
                          size: 72,
                          variant: AmiinLogoVariant.turquoise,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Nom
                    Opacity(
                      opacity: _textOpacity.value,
                      child: SlideTransition(
                        position: _textSlide,
                        child: Column(
                          children: [
                            Text(
                              'AMIIN',
                              style: TextStyle(
                                fontFamily: FontFamily.geo,
                                fontWeight: FontWeight.w700,
                                fontSize: 28,
                                letterSpacing: 8,
                                color: ColorsAmiin.onDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Votre assistant national',
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontWeight: FontWeight.w300,
                                fontSize: 13,
                                letterSpacing: 0.3,
                                color: ColorsAmiin.onDark.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Ligne d'horizon en bas
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: _lineOpacity.value,
                  child: const HorizonLine(
                    color: ColorsAmiin.turquoise,
                    animating: true,
                    height: 2,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

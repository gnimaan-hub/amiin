import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/amiin_logo.dart';

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
  late final Animation<double> _ringScale;

  @override
  void initState() {
    super.initState();
    // Durée courte : main() a déjà tout initialisé avant runApp,
    // inutile de faire payer une seconde attente à l'utilisateur.
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    );

    _logoScale = Tween(begin: 0.35, end: 1.0).animate(
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
    _ringScale = Tween(begin: 0.6, end: 1.15).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.3, 0.65, curve: Curves.easeOut),
      ),
    );
    _textOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.52, 0.80, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.52, 0.80, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) context.go('/home');
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
      backgroundColor: ColorsAmiin.ink,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Halo ring
                      Transform.scale(
                        scale: _ringScale.value,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ColorsAmiin.terra.withValues(
                              alpha: (1 - _ringScale.value / 1.15) * 0.18,
                            ),
                          ),
                        ),
                      ),
                      // Logo
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: const AmiinLogo(
                            size: 80,
                            variant: AmiinLogoVariant.terra,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Opacity(
                  opacity: _textOpacity.value,
                  child: SlideTransition(
                    position: _textSlide,
                    child: Text(
                      'A M I I N',
                      style: TextStyle(
                        fontFamily: FontFamily.serif,
                        fontSize: 26,
                        letterSpacing: 10,
                        color: ColorsAmiin.onDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: _textOpacity.value,
                  child: Text(
                    'Votre assistant personnel',
                    style: TextStyle(
                      fontFamily: FontFamily.sansLight,
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: ColorsAmiin.onDark.withValues(alpha: 0.45),
                    ),
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

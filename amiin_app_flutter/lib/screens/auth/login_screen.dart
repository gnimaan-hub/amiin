// ─── LoginScreen ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../services/auth_service.dart';
import '../../widgets/amiin_logo.dart';
import 'auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  bool    _loading      = false;
  bool    _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      await authService.login(
        email:    _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      // GoRouter redirige automatiquement vers /home via refreshListenable
    } on DioException catch (e) {
      setState(() { _error = authErrorMessage(e); });
    } catch (_) {
      setState(() { _error = 'Une erreur inattendue est survenue.'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.encreNuit,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // ── Logo ──────────────────────────────────────────────────
                const Center(
                  child: AmiinLogo(size: 56, variant: AmiinLogoVariant.turquoise),
                ),
                const SizedBox(height: 28),

                // ── Titre ─────────────────────────────────────────────────
                Text(
                  'Bon retour',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FontFamily.geo,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: ColorsAmiin.onDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Connectez-vous à votre compte Amiin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 14,
                    color: ColorsAmiin.onDark.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 40),

                // ── Email ─────────────────────────────────────────────────
                AuthDarkField(
                  controller: _emailCtrl,
                  label: 'Adresse e-mail',
                  hint: 'vous@example.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Champ requis';
                    if (!v.contains('@')) return 'Email invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Mot de passe ──────────────────────────────────────────
                AuthDarkField(
                  controller: _passCtrl,
                  label: 'Mot de passe',
                  hint: '••••••••',
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: ColorsAmiin.onDark.withValues(alpha: 0.45),
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Champ requis';
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // ── Mot de passe oublié ───────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showForgotDialog(context),
                    style: TextButton.styleFrom(
                      foregroundColor: ColorsAmiin.turquoiseMid,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(
                      'Mot de passe oublié ?',
                      style: TextStyle(fontFamily: FontFamily.sans, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Erreur ────────────────────────────────────────────────
                if (_error != null) ...[
                  AuthErrorBanner(_error!),
                  const SizedBox(height: 16),
                ],

                // ── Bouton Se connecter ───────────────────────────────────
                AuthPrimaryButton(
                  label: 'Se connecter',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 28),

                // ── Divider ───────────────────────────────────────────────
                const AuthDivider(),
                const SizedBox(height: 24),

                // ── Lien créer un compte ──────────────────────────────────
                TextButton(
                  onPressed: () => context.go('/register'),
                  style: TextButton.styleFrom(
                    foregroundColor: ColorsAmiin.onDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: ColorsAmiin.onDark.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  child: Text(
                    'Créer un compte',
                    style: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColorsAmiin.darkMid,
        title: Text(
          'Mot de passe oublié',
          style: TextStyle(fontFamily: FontFamily.geo, color: ColorsAmiin.onDark),
        ),
        content: Text(
          'Contactez le support à support@amiin.dj pour réinitialiser votre mot de passe.',
          style: TextStyle(
            fontFamily: FontFamily.sans,
            color: ColorsAmiin.onDark.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: TextStyle(
                color: ColorsAmiin.turquoiseMid,
                fontFamily: FontFamily.geo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

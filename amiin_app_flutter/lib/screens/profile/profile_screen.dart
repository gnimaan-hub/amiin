// ─── ProfileScreen ───────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = true;
  String _language = 'Français';

  void _onLanguageTap() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('Français'), onTap: () { setState(() => _language = 'Français'); Navigator.pop(context); }),
            ListTile(title: const Text('عربية'), onTap: () { setState(() => _language = 'عربية'); Navigator.pop(context); }),
            ListTile(title: const Text('Soomaali'), onTap: () { setState(() => _language = 'Soomaali'); Navigator.pop(context); }),
          ],
        ),
      ),
    );
  }

  void _onLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await authService.logout();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Profil'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: ColorsAmiin.turquoise,
                      child: Text('MA', style: TextStyle(fontSize: 26, fontFamily: FontFamily.geoBold, color: ColorsAmiin.white)),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text('Mohamed A.', style: TextStyle(fontFamily: FontFamily.geo, fontSize: 20, color: ColorsAmiin.ink)),
                    const SizedBox(height: 4),
                    Text('m.ahmed@example.dj', style: TextStyle(fontFamily: FontFamily.sans, fontSize: 13, color: ColorsAmiin.muted)),
                    const SizedBox(height: Spacing.xl),
                    // Groupes
                    _buildSectionTitle('Compte'),
                    AmiinCard(
                      child: Column(
                        children: [
                          _settingRow('👤', 'Informations personnelles', onTap: () {}),
                          const Divider(color: ColorsAmiin.border, indent: 52),
                          _settingRow('🔒', 'Sécurité', onTap: () {}),
                          const Divider(color: ColorsAmiin.border, indent: 52),
                          _settingRow('🌐', 'Langue', value: _language, onTap: _onLanguageTap),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    _buildSectionTitle('Notifications'),
                    AmiinCard(
                      child: Column(
                        children: [
                          _settingRow('🔔', 'Activer les notifications', toggle: true, toggleValue: _notificationsEnabled, onToggle: (v) => setState(() => _notificationsEnabled = v)),
                          const Divider(color: ColorsAmiin.border, indent: 52),
                          _settingRow('📅', 'Rappels agenda', toggle: true, toggleValue: _notificationsEnabled, onToggle: (_) {}),
                          const Divider(color: ColorsAmiin.border, indent: 52),
                          _settingRow('📋', 'Mises à jour démarches', toggle: true, toggleValue: _notificationsEnabled, onToggle: (_) {}),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    _buildSectionTitle('Application'),
                    AmiinCard(
                      child: Column(
                        children: [
                          _settingRow('📖', 'Guide d\'utilisation', onTap: () {}),
                          const Divider(color: ColorsAmiin.border, indent: 52),
                          _settingRow('🔏', 'Politique de confidentialité', onTap: () {}),
                          const Divider(color: ColorsAmiin.border, indent: 52),
                          _settingRow('ℹ️', 'Version', value: '1.0.0'),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    AmiinCard(
                      child: _settingRow('🚪', 'Se déconnecter', destructive: true, onTap: _onLogout),
                    ),
                    const SizedBox(height: Spacing.xxxl),
                    Text('Amiin', style: TextStyle(fontFamily: FontFamily.geo, fontSize: 22, color: ColorsAmiin.turquoise, letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text('App Assistance Djibouti · v1.0', style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: ColorsAmiin.muted)),
                    const SizedBox(height: 4),
                    Text('أمين', style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: ColorsAmiin.muted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 8),
        child: Text(title, style: TextStyle(
          fontFamily: FontFamily.geoBold,
          fontSize: 10,
          letterSpacing: 1.2,
          color: ColorsAmiin.muted,
        )),
      ),
    );
  }

  Widget _settingRow(String icon, String label, {String? value, bool toggle = false, bool toggleValue = false, Function(bool)? onToggle, VoidCallback? onTap, bool destructive = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(icon, style: const TextStyle(fontSize: 17), textAlign: TextAlign.center),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(label, style: TextStyle(
                fontFamily: FontFamily.sans,
                fontSize: 15,
                color: destructive ? Colors.red : ColorsAmiin.ink,
              )),
            ),
            if (value != null)
              Text(value, style: TextStyle(fontFamily: FontFamily.sans, fontSize: 14, color: ColorsAmiin.muted)),
            if (toggle)
              Switch(
                value: toggleValue,
                onChanged: onToggle,
                activeColor: ColorsAmiin.turquoise,
              ),
            if (!toggle && onTap != null)
              const Icon(Icons.chevron_right, color: ColorsAmiin.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

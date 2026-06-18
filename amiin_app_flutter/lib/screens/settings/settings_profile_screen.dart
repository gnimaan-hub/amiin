// ─── SettingsProfileScreen ── Profil utilisateur (injecté dans Amiin) ─────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../services/settings_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';

class SettingsProfileScreen extends StatefulWidget {
  const SettingsProfileScreen({super.key});
  @override
  State<SettingsProfileScreen> createState() => _SettingsProfileScreenState();
}

class _SettingsProfileScreenState extends State<SettingsProfileScreen> {
  late final TextEditingController _firstnameCtrl;
  late final TextEditingController _lastnameCtrl;
  late final TextEditingController _professionCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _nativeLangCtrl;

  @override
  void initState() {
    super.initState();
    final s = settingsService;

    // Pré-remplir depuis authService si le profil local est vierge
    String firstname = s.profileFirstname;
    String lastname  = s.profileLastname;
    if (firstname.isEmpty && lastname.isEmpty) {
      final authName = authService.currentUser?.displayName ?? '';
      if (authName.isNotEmpty) {
        final parts = authName.trim().split(RegExp(r'\s+'));
        firstname = parts.first;
        lastname  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
    }

    _firstnameCtrl  = TextEditingController(text: firstname);
    _lastnameCtrl   = TextEditingController(text: lastname);
    _professionCtrl = TextEditingController(text: s.profileProfession);
    _phoneCtrl      = TextEditingController(text: s.profilePhone);
    _nativeLangCtrl = TextEditingController(text: s.profileNativeLanguage);
  }

  @override
  void dispose() {
    _firstnameCtrl.dispose();
    _lastnameCtrl.dispose();
    _professionCtrl.dispose();
    _phoneCtrl.dispose();
    _nativeLangCtrl.dispose();
    super.dispose();
  }

  void _save() {
    settingsService
      ..profileFirstname = _firstnameCtrl.text.trim()
      ..profileLastname = _lastnameCtrl.text.trim()
      ..profileProfession = _professionCtrl.text.trim()
      ..profilePhone = _phoneCtrl.text.trim()
      ..profileNativeLanguage = _nativeLangCtrl.text.trim();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profil enregistré'), duration: Duration(seconds: 2)),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Mon profil', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info banner
                    AmiinCard(
                      variant: CardVariant.surface2,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, size: 18, color: primary),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              'Ces informations permettent à Amiin de personnaliser ses réponses à votre situation.',
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 13,
                                color: ColorsAmiin.ink,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),

                    _label('Identité'),
                    _field('Prénom', _firstnameCtrl, hint: 'Mohamed'),
                    const SizedBox(height: Spacing.sm),
                    _field('Nom', _lastnameCtrl, hint: 'Ahmed'),

                    const SizedBox(height: Spacing.lg),
                    _label('Année de naissance'),
                    _BirthYearPicker(
                      value: settings.profileBirthYear,
                      onChanged: (y) => settingsService.profileBirthYear = y,
                    ),

                    const SizedBox(height: Spacing.lg),
                    _label('Profession'),
                    _field('Profession ou secteur d\'activité', _professionCtrl,
                        hint: 'Enseignant, commerçant…'),

                    const SizedBox(height: Spacing.lg),
                    _label('Situation professionnelle'),
                    _EmploymentPicker(
                      value: settings.profileEmployment,
                      onChanged: (v) => settingsService.profileEmployment = v,
                    ),

                    const SizedBox(height: Spacing.lg),
                    _label('Téléphone'),
                    _field('Numéro de téléphone', _phoneCtrl,
                        hint: '+253 77 XX XX XX',
                        keyboardType: TextInputType.phone),

                    const SizedBox(height: Spacing.lg),
                    _label('Langue maternelle'),
                    _field('Langue maternelle', _nativeLangCtrl,
                        hint: 'Somali, Afar, Arabe…'),

                    const SizedBox(height: Spacing.xl),
                  ],
                ),
              ),
            ),
            // Bouton Enregistrer — toujours visible, collé au bas de l'écran
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xl),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _save,
                  child: Text('Enregistrer', style: TextStyle(
                    fontFamily: FontFamily.geoBold,
                    fontSize: 16,
                  )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.xs),
    child: Text(text, style: TextStyle(
      fontFamily: FontFamily.geoBold,
      fontSize: 10,
      letterSpacing: 1.2,
      color: ColorsAmiin.muted,
    )),
  );

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: ColorsAmiin.white,
        hintStyle: TextStyle(color: ColorsAmiin.muted, fontFamily: FontFamily.sans),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ColorsAmiin.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ColorsAmiin.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
      style: TextStyle(fontFamily: FontFamily.sans, fontSize: 15, color: ColorsAmiin.ink),
    );
  }
}

// ── Sélecteur année de naissance ─────────────────────────────────────────────

class _BirthYearPicker extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  const _BirthYearPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List.generate(80, (i) => currentYear - 16 - i);

    return GestureDetector(
      onTap: () async {
        await showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Année de naissance', style: TextStyle(
                    fontFamily: FontFamily.geoBold, fontSize: 16, color: ColorsAmiin.ink,
                  )),
                ),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    itemCount: years.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text('${years[i]}', style: TextStyle(
                        fontFamily: FontFamily.sans,
                        color: years[i] == value ? Theme.of(context).colorScheme.primary : ColorsAmiin.ink,
                        fontWeight: years[i] == value ? FontWeight.bold : FontWeight.normal,
                      )),
                      trailing: years[i] == value
                          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        onChanged(years[i]);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Ne pas préciser', style: TextStyle(color: Colors.red)),
                  onTap: () { onChanged(null); Navigator.pop(ctx); },
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: ColorsAmiin.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ColorsAmiin.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value != null ? '$value' : 'Sélectionner…',
                style: TextStyle(
                  fontFamily: FontFamily.sans,
                  fontSize: 15,
                  color: value != null ? ColorsAmiin.ink : ColorsAmiin.muted,
                ),
              ),
            ),
            const Icon(Icons.expand_more, color: ColorsAmiin.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Sélecteur situation professionnelle ───────────────────────────────────────

class _EmploymentPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _EmploymentPicker({required this.value, required this.onChanged});

  static const _options = [
    ('employee', 'Salarié(e)'),
    ('freelance', 'Indépendant(e)'),
    ('unemployed', 'Sans emploi'),
    ('student', 'Étudiant(e)'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: _options.map((opt) {
        final selected = opt.$1 == value;
        return GestureDetector(
          onTap: () => onChanged(opt.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? primary.withValues(alpha: 0.1) : ColorsAmiin.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: selected ? primary : ColorsAmiin.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Text(opt.$2, style: TextStyle(
              fontFamily: FontFamily.geoMedium,
              fontSize: 13,
              color: selected ? primary : ColorsAmiin.mid,
            )),
          ),
        );
      }).toList(),
    );
  }
}



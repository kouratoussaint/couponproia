import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/studio_models.dart';
import '../data/studio_repository.dart';

const _swatches = [
  '#0E7C47',
  '#14532D',
  '#0B3D2E',
  '#1F2A44',
  '#1D4ED8',
  '#0F766E',
  '#7C2D12',
  '#991B1B',
  '#6D28D9',
  '#111827',
  '#F2C230',
  '#D4AF37',
  '#A3E635',
  '#E4572E',
  '#F97316',
  '#FFFFFF',
];

/// Identité visuelle du Tipster : nom affiché, couleurs, logo, couverture, signature.
class BrandingScreen extends ConsumerWidget {
  const BrandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rights = ref.watch(studioRightsProvider);
    final branding = ref.watch(brandingProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon identité visuelle')),
      body: switch ((rights, branding)) {
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) =>
          InfoMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Indisponible',
              body: userMessageFor(error)),
        (AsyncData(value: final r), AsyncData(value: final b)) =>
          _BrandingForm(rights: r, initial: b),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _BrandingForm extends ConsumerStatefulWidget {
  const _BrandingForm({required this.rights, required this.initial});

  final StudioRights rights;
  final Branding initial;

  @override
  ConsumerState<_BrandingForm> createState() => _BrandingFormState();
}

class _BrandingFormState extends ConsumerState<_BrandingForm> {
  late final _name =
      TextEditingController(text: widget.initial.displayName ?? '');
  late final _signature =
      TextEditingController(text: widget.initial.signature ?? '');
  late String? _primary = widget.initial.primaryColor;
  late String? _accent = widget.initial.accentColor;
  late String? _logo = widget.initial.logoPath;
  late String? _cover = widget.initial.coverPath;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _pick(String kind) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: kind == 'logo' ? 600 : 1920,
      maxHeight: kind == 'logo' ? 600 : 1920,
      imageQuality: 88,
    );
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw const StudioException('Image trop lourde (2 Mo maximum).');
      }
      final ext = file.name.split('.').last;
      final path = await ref
          .read(studioRepositoryProvider)
          .uploadImage(kind, bytes, ext);
      setState(() => kind == 'logo' ? _logo = path : _cover = path);
    } catch (e) {
      if (mounted) showMessage(context, studioErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    for (final t in [_name.text, _signature.text]) {
      final bad = forbiddenWordIn(t);
      if (bad != null) {
        showMessage(context,
            'Texte refusé : « $bad ». Les pronostics sont des estimations.',
            error: true);
        return;
      }
    }
    setState(() => _busy = true);
    final repo = ref.read(studioRepositoryProvider);
    try {
      await repo.saveBranding(Branding(
        displayName: _name.text,
        primaryColor: _primary,
        accentColor: _accent,
        signature: _signature.text,
        logoPath: _logo,
        coverPath: _cover,
      ));
      // Images remplacées, retirées ou non retenues : supprimées du stockage.
      await repo.removeUnusedImages({_logo, _cover}).catchError((_) {});
      ref.invalidate(brandingProvider);
      if (mounted) {
        showMessage(context, 'Identité visuelle enregistrée.');
        context.pop();
      }
    } catch (e) {
      if (mounted) showMessage(context, studioErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.rights;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (!r.canName)
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Personnalisation à partir du forfait STARTER'),
              subtitle: const Text(
                  'Votre nom et vos couleurs sur les visuels ; logo, couverture et signature avec PRO TIPSTER.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.billing),
            ),
          ),
        const SectionTitle('Nom affiché'),
        TextField(
          controller: _name,
          enabled: r.canName,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Ex. : Kouassi Pronos'),
        ),
        const SectionTitle('Couleurs'),
        Text('Principale', style: theme.textTheme.labelLarge),
        _SwatchRow(
            selected: _primary,
            enabled: r.canName,
            onSelected: (c) => setState(() => _primary = c)),
        const SizedBox(height: 8),
        Text('Accent (cotes, cote totale)', style: theme.textTheme.labelLarge),
        _SwatchRow(
            selected: _accent,
            enabled: r.canName,
            onSelected: (c) => setState(() => _accent = c)),
        Text('Sans choix, chaque modèle utilise ses propres couleurs.',
            style: muted),
        const SectionTitle('Logo et couverture'),
        if (!r.canFull)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Disponible à partir du forfait PRO TIPSTER.',
                style: muted),
          ),
        _ImageTile(
          label: 'Logo (carré, 600 px)',
          path: _logo,
          enabled: r.canFull && !_busy,
          onPick: () => _pick('logo'),
          onClear: () => setState(() => _logo = null),
        ),
        _ImageTile(
          label: 'Image de couverture (modèle Prestige)',
          path: _cover,
          enabled: r.canFull && !_busy,
          onPick: () => _pick('cover'),
          onClear: () => setState(() => _cover = null),
        ),
        const SectionTitle('Signature'),
        TextField(
          controller: _signature,
          enabled: r.canFull,
          maxLength: 80,
          decoration: const InputDecoration(
              hintText: 'Ex. : Analyses du week-end par Kouassi'),
        ),
        Text(
            'Pas de promesse de résultat : « sûr », « garanti », « gain »… sont refusés.',
            style: muted),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _busy || !r.canName ? null : _save,
            child: const Text('Enregistrer')),
      ],
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow(
      {required this.selected,
      required this.enabled,
      required this.onSelected});

  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          InkWell(
            onTap: enabled ? () => onSelected(null) : null,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 17,
              backgroundColor: scheme.surfaceContainerHighest,
              child: Icon(selected == null ? Icons.check : Icons.auto_awesome,
                  size: 16),
            ),
          ),
          for (final hex in _swatches)
            InkWell(
              onTap: enabled ? () => onSelected(hex) : null,
              customBorder: const CircleBorder(),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parseHexColor(hex),
                  border: Border.all(
                    color: selected == hex
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: selected == hex ? 3 : 1,
                  ),
                ),
                child: selected == hex
                    ? Icon(Icons.check,
                        size: 18,
                        color: parseHexColor(hex)!.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageTile extends ConsumerWidget {
  const _ImageTile({
    required this.label,
    required this.path,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String? path;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(brandingImageProvider(path)).valueOrNull;
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: bytes == null
                ? const ColoredBox(
                    color: Colors.black12, child: Icon(Icons.image_outlined))
                : Image.memory(bytes, fit: BoxFit.cover),
          ),
        ),
        title: Text(label),
        subtitle: Text(path == null ? 'Aucune image' : 'Image choisie'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (path != null)
              IconButton(
                  tooltip: 'Retirer',
                  onPressed: enabled ? onClear : null,
                  icon: const Icon(Icons.close)),
            IconButton(
                tooltip: 'Choisir',
                onPressed: enabled ? onPick : null,
                icon: const Icon(Icons.upload)),
          ],
        ),
      ),
    );
  }
}

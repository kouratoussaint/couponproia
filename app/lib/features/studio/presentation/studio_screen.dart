import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../assistant/data/assistant_repository.dart';
import '../../coupons/data/coupon_repository.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/studio_export.dart';
import '../data/studio_models.dart';
import '../data/studio_repository.dart';
import 'coupon_visual.dart';

/// Coupon à mettre en forme : coupon de la plateforme ou coupon enregistré par l'utilisateur.
final studioCouponProvider = FutureProvider.autoDispose
    .family<StudioCoupon?, ({String kind, String id})>((ref, src) async {
  if (src.kind == 'platform') {
    final c = await ref.watch(couponProvider(src.id).future);
    if (c == null || c.locked || c.selections.isEmpty) return null;
    return StudioCoupon.fromPlatform(c);
  }
  final c = await ref.watch(userCouponProvider(src.id).future);
  if (c == null || c.selections.isEmpty) return null;
  return StudioCoupon.fromUser(c);
});

class StudioScreen extends ConsumerWidget {
  const StudioScreen({super.key, required this.kind, required this.id});

  final String kind;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupon = ref.watch(studioCouponProvider((kind: kind, id: id)));
    final rights = ref.watch(studioRightsProvider);
    final branding = ref.watch(brandingProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio graphique'),
        actions: [
          IconButton(
            tooltip: 'Mon identité visuelle',
            icon: const Icon(Icons.badge_outlined),
            onPressed: () => context.push(AppRoutes.studioBranding),
          ),
        ],
      ),
      body: switch ((coupon, rights, branding)) {
        (AsyncError(:final error), _, _) ||
        (_, AsyncError(:final error), _) ||
        (_, _, AsyncError(:final error)) =>
          InfoMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Studio indisponible',
              body: userMessageFor(error)),
        (
          AsyncData(value: final c),
          AsyncData(value: final r),
          AsyncData(value: final b)
        ) =>
          c == null
              ? const InfoMessage(
                  icon: Icons.lock_outline,
                  title: 'Coupon indisponible',
                  body:
                      'Ce coupon est réservé ou introuvable. Un visuel ne peut être créé qu’à partir '
                      'd’un coupon dont toutes les sélections vous sont visibles.')
              : !r.enabled
                  ? const InfoMessage(
                      icon: Icons.construction,
                      title: 'Studio momentanément indisponible')
                  : _Editor(coupon: c, rights: r, branding: b),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor(
      {required this.coupon, required this.rights, required this.branding});

  final StudioCoupon coupon;
  final StudioRights rights;
  final Branding branding;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _boundary = GlobalKey();
  final _text = TextEditingController();
  late String _template;
  StudioFormat _format = StudioFormat.portrait;
  StudioFileType _type = StudioFileType.png;
  bool _showProbability = true;
  bool _showLogos = true;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final available = widget.rights.templates.where((t) => t.available);
    _template = available.isEmpty ? 'classique' : available.first.code;
    WidgetsBinding.instance.addPostFrameCallback((_) => _preload());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Logos des équipes et polices chargés avant tout export (sinon ils manqueraient sur l'image).
  Future<void> _preload() async {
    final urls = {
      for (final l in widget.coupon.lines) ...[l.homeLogo, l.awayLogo]
    }.whereType<String>();
    await Future.wait([
      for (final u in urls)
        precacheImage(NetworkImage(u), context, onError: (_, __) {}),
      GoogleFonts.pendingFonts(),
    ]).timeout(const Duration(seconds: 10), onTimeout: () => const []);
    if (mounted) setState(() => _ready = true);
  }

  StudioTemplate? get _tpl {
    for (final t in widget.rights.templates) {
      if (t.code == _template) return t;
    }
    return null;
  }

  StudioOptions _options(Branding b) {
    final r = widget.rights;
    final t = _tpl;
    final ownColors = r.canName && b.primaryColor != null;
    return StudioOptions(
      template: _template,
      format: _format,
      primary: (ownColors ? parseHexColor(b.primaryColor) : null) ??
          t?.primary ??
          const Color(0xFF0E7C47),
      accent: (ownColors ? parseHexColor(b.accentColor) : null) ??
          t?.accent ??
          const Color(0xFFF2C230),
      showProbability: _showProbability,
      showLogos: _showLogos,
      customText: _text.text,
      watermark: r.watermark,
      displayName: r.canName ? b.displayName : null,
      signature: r.canFull ? b.signature : null,
      logo: r.canFull
          ? ref.watch(brandingImageProvider(b.logoPath)).valueOrNull
          : null,
      cover: r.canFull
          ? ref.watch(brandingImageProvider(b.coverPath)).valueOrNull
          : null,
    );
  }

  Future<void> _export({required bool save}) async {
    final bad = forbiddenWordIn(_text.text);
    if (bad != null) {
      showMessage(context,
          'Texte refusé : « $bad ». Les pronostics sont des estimations.',
          error: true);
      return;
    }
    final type =
        save && _type == StudioFileType.pdf ? StudioFileType.png : _type;
    setState(() => _busy = true);
    try {
      await GoogleFonts.pendingFonts();
      // Le serveur vérifie modèle, coupon et quota, et journalise l'export.
      await ref.read(studioRepositoryProvider).authorizeExport(
          coupon: widget.coupon,
          template: _template,
          format: _format,
          fileType: type);
      final boundary = _boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final name = studioFileName(widget.coupon, _format);
      var file = await renderStudioFile(boundary,
          format: _format, type: StudioFileType.png, baseName: name);
      file = switch (type) {
        StudioFileType.png => file,
        StudioFileType.jpg => encodeStudioFile(file.bytes,
            format: _format, type: type, baseName: name),
        StudioFileType.pdf =>
          await encodeStudioPdf(file.bytes, format: _format, baseName: name),
      };
      ref.invalidate(studioRightsProvider);
      if (save) {
        final ok = await saveStudioImage(file);
        if (mounted) {
          showMessage(
              context,
              ok
                  ? 'Visuel enregistré dans la galerie.'
                  : 'Accès à la galerie refusé.',
              error: !ok);
        }
      } else {
        await shareStudioFile(file);
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
    final options = _options(widget.branding);
    final remaining = r.remaining;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            children: [
              Container(
                height: 380,
                alignment: Alignment.center,
                child: AspectRatio(
                  aspectRatio: _format.width / _format.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ]),
                    child: FittedBox(
                      child: RepaintBoundary(
                        key: _boundary,
                        child: CouponVisual(
                            coupon: widget.coupon, options: options),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Toutes les informations viennent du coupon : équipes, issues, cotes et horaires ne sont pas modifiables.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SectionTitle('Modèle'),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in r.templates)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t.name),
                          avatar: t.available
                              ? null
                              : const Icon(Icons.lock_outline, size: 16),
                          selected: _template == t.code,
                          onSelected: (_) {
                            if (t.available) {
                              setState(() => _template = t.code);
                            } else {
                              _locked(
                                  'Le modèle « ${t.name} » est inclus à partir du forfait ${t.minPlan.replaceAll('_', ' ')}.');
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              if (_tpl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child:
                      Text(_tpl!.description, style: theme.textTheme.bodySmall),
                ),
              const SectionTitle('Format'),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in StudioFormat.values)
                    ChoiceChip(
                      label: Text(
                          '${f.label} ${f.width.toInt()}×${f.height.toInt()}'),
                      selected: _format == f,
                      onSelected: (_) => setState(() => _format = f),
                    ),
                ],
              ),
              const SectionTitle('Contenu'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Probabilité estimée par le modèle'),
                value: _showProbability,
                onChanged: (v) => setState(() => _showProbability = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Logos des équipes'),
                value: _showLogos,
                onChanged: (v) => setState(() => _showLogos = v),
              ),
              TextField(
                controller: _text,
                maxLength: 120,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Texte personnalisé (facultatif)',
                  helperText:
                      'Ex. : « Ma sélection du week-end ». Pas de promesse de résultat.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Mon identité visuelle'),
                  subtitle: Text(switch (r.branding) {
                    'full' => 'Nom, couleurs, logo, couverture et signature',
                    'name' =>
                      'Nom et couleurs (logo et couverture à partir de PRO TIPSTER)',
                    _ => 'Disponible à partir du forfait STARTER',
                  }),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.studioBranding),
                ),
              ),
              if (r.watermark)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'La mention « Réalisé avec Coupon Pro IA » est ajoutée avec votre forfait. '
                    'L’avertissement « Estimations, aucun gain garanti, 18+ » figure sur tous les visuels.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Material(
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy || !_ready) const LinearProgressIndicator(),
                  Row(
                    children: [
                      DropdownButton<StudioFileType>(
                        value: _type,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                              value: StudioFileType.png, child: Text('PNG')),
                          DropdownMenuItem(
                              value: StudioFileType.jpg, child: Text('JPG')),
                          DropdownMenuItem(
                              value: StudioFileType.pdf, child: Text('PDF')),
                        ],
                        onChanged: (v) =>
                            setState(() => _type = v ?? StudioFileType.png),
                      ),
                      const Spacer(),
                      // Galerie : téléphone uniquement (sur le web, « Partager » télécharge).
                      if (_type != StudioFileType.pdf && !kIsWeb)
                        IconButton.outlined(
                          tooltip: 'Enregistrer dans la galerie',
                          onPressed: _busy || !_ready
                              ? null
                              : () => _export(save: true),
                          icon: const Icon(Icons.download),
                        ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _busy || !_ready
                            ? null
                            : () => _export(save: false),
                        icon: const Icon(Icons.share),
                        label: const Text('Partager'),
                      ),
                    ],
                  ),
                  if (remaining != null)
                    Text(
                        '$remaining visuel${remaining > 1 ? 's' : ''} restant${remaining > 1 ? 's' : ''} aujourd’hui',
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _locked(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: SnackBarAction(
            label: 'Forfaits',
            onPressed: () => context.push(AppRoutes.billing)),
      ));
  }
}

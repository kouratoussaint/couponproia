import 'package:flutter/material.dart';
import 'package:coupon_pro_ia/core/widgets/unsaved_changes_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/form_widgets.dart';
import '../../legal/legal_repository.dart';
import '../../legal/legal_screens.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/admin_repository.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Documents légaux : version en vigueur et publication d'une nouvelle version.
/// Une nouvelle version des CGU ou de la politique de confidentialité redemande l'acceptation
/// à tous les utilisateurs à leur prochaine ouverture de l'app.
class LegalAdminScreen extends ConsumerWidget {
  const LegalAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Documents légaux'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          const EditorIdentityCard(),
          SectionTitle(tr('Documents')),
          Text(
              tr('Faites relire les textes par un juriste avant l’ouverture commerciale.'),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final code in legalCodes)
            Card(
              child: ref.watch(legalDocumentProvider(code)).when(
                    loading: () =>
                        const ListTile(title: LinearProgressIndicator()),
                    error: (e, _) =>
                        ListTile(title: Text(adminErrorMessage(e))),
                    data: (d) => ListTile(
                      title: Text(legalTitles[code]!),
                      subtitle: Text(d == null
                          ? tr('Aucune version publiée')
                          : '${trf('Version {0} · publiée le {1}/{2}', [
                                  d.version,
                                  shortDate(d.publishedAt),
                                  d.publishedAt.year
                                ])} · ${d.english == null ? tr('sans traduction anglaise') : tr('traduction anglaise à jour')}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) => switch (a) {
                          'read' => openLegalDocument(context, code),
                          'english' =>
                            Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) =>
                                    _EnglishEditor(code: code, document: d!))),
                          _ => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      _LegalEditor(code: code, current: d))),
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'read', child: Text(tr('Lire'))),
                          PopupMenuItem(
                              value: 'edit',
                              child: Text(tr('Publier une nouvelle version'))),
                          if (d != null)
                            PopupMenuItem(
                                value: 'english',
                                child: Text(tr('Traduction anglaise'))),
                        ],
                      ),
                    ),
                  ),
            ),
        ],
      ),
    );
  }
}

class _LegalEditor extends ConsumerStatefulWidget {
  const _LegalEditor({required this.code, this.current});

  final String code;
  final LegalDocument? current;

  @override
  ConsumerState<_LegalEditor> createState() => _LegalEditorState();
}

class _LegalEditorState extends ConsumerState<_LegalEditor> {
  late final _title = TextEditingController(
      text: widget.current?.frTitle ?? legalTitles[widget.code]);
  late final _body = TextEditingController(text: widget.current?.frBody ?? '');
  late final _version = TextEditingController(text: _today());
  bool _busy = false;

  /// Saisie au chargement, pour savoir si quelque chose a changé (lot 27).
  String? _baseline;
  String _signature() => [_title.text, _body.text].join('\u0001');
  bool _dirty() => _baseline != null && _signature() != _baseline;

  static String _today() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _version.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final needsAcceptance = widget.code != 'community';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Publier cette version ?')),
        content: Text(needsAcceptance
            ? tr(
                'Tous les utilisateurs devront l’accepter à leur prochaine ouverture de l’app. La version précédente reste archivée.')
            : tr(
                'Elle remplace la version affichée. La version précédente reste archivée.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Publier'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(legalRepositoryProvider).publish(
            code: widget.code,
            version: _version.text.trim(),
            title: _title.text.trim(),
            body: _body.text,
          );
      ref.invalidate(legalDocumentProvider(widget.code));
      ref.invalidate(legalStatusProvider);
      if (!mounted) return;
      showMessage(context, tr('Nouvelle version publiée.'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _baseline ??= _signature();
    return UnsavedChangesGuard(
        isDirty: _dirty,
        child: Scaffold(
          appBar: AppBar(title: Text(legalTitles[widget.code]!)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TextField(
                controller: _version,
                decoration: InputDecoration(
                    labelText: tr('Version'),
                    helperText: tr('AAAA-MM-JJ (ou AAAA-MM-JJ.2)')),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: _title,
                  decoration: InputDecoration(labelText: tr('Titre'))),
              const SizedBox(height: 8),
              TextField(
                controller: _body,
                minLines: 12,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: tr('Texte'),
                  alignLabelWithHint: true,
                  helperText: tr(
                      '« ## » titre, « - » puce, **gras**. Champs : {{editeur}}, {{forme}}, {{adresse}}, {{pays}}, {{immatriculation}}, {{contact}}.'),
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _busy ? null : _publish,
                  child: Text(tr('Publier'))),
            ],
          ),
        ));
  }
}

/// Traduction anglaise de la version en vigueur : affichée aux utilisateurs anglophones,
/// la version française reste celle qui fait foi et qui est acceptée.
class _EnglishEditor extends ConsumerStatefulWidget {
  const _EnglishEditor({required this.code, required this.document});

  final String code;
  final LegalDocument document;

  @override
  ConsumerState<_EnglishEditor> createState() => _EnglishEditorState();
}

class _EnglishEditorState extends ConsumerState<_EnglishEditor> {
  late final _title =
      TextEditingController(text: widget.document.english?.title ?? '');
  late final _body =
      TextEditingController(text: widget.document.english?.body ?? '');
  bool _busy = false;

  /// Saisie au chargement, pour savoir si quelque chose a changé (lot 27).
  String? _baseline;
  String _signature() => [_title.text, _body.text].join('\u0001');
  bool _dirty() => _baseline != null && _signature() != _baseline;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(legalRepositoryProvider).saveEnglish(
          documentId: widget.document.id,
          title: _title.text.trim(),
          body: _body.text);
      ref.invalidate(legalDocumentProvider(widget.code));
      if (!mounted) return;
      showMessage(context, tr('Traduction anglaise enregistrée.'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _baseline ??= _signature();
    final theme = Theme.of(context);
    return UnsavedChangesGuard(
        isDirty: _dirty,
        child: Scaffold(
          appBar: AppBar(title: Text(tr('Traduction anglaise'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                  trf('Version {0}. La version française fait foi : c’est elle que les utilisateurs acceptent.',
                      [widget.document.version]),
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                  controller: _title,
                  decoration:
                      InputDecoration(labelText: tr('Titre en anglais'))),
              const SizedBox(height: 8),
              TextField(
                controller: _body,
                minLines: 12,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: tr('Texte en anglais'),
                  alignLabelWithHint: true,
                  helperText: tr(
                      'Même mise en forme et mêmes champs {{…}} que la version française.'),
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(tr('Enregistrer'))),
            ],
          ),
        ));
  }
}

final editorFields = {
  'name': tr('Nom ou raison sociale'),
  'legal_form': tr('Forme juridique (ex. SARL, entreprise individuelle)'),
  'address': tr('Adresse'),
  'country': tr('Pays'),
  'registration': tr('Immatriculation (RCCM, IFU…)'),
};

/// Identité de l'éditeur et e-mail du support, affichés dans les CGU et la politique de
/// confidentialité (réglages publics « legal.editor » et « app.support_email »).
class EditorIdentityCard extends ConsumerWidget {
  const EditorIdentityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(publicSettingsProvider).valueOrNull ??
        const <String, dynamic>{};
    final editor = settings['legal.editor'] is Map
        ? Map<String, dynamic>.from(settings['legal.editor'] as Map)
        : <String, dynamic>{};
    final email = (settings['app.support_email'] as String? ?? '').trim();
    final missing = [
      if ((editor['name'] as String? ?? '').trim().isEmpty) 'nom',
      if ((editor['address'] as String? ?? '').trim().isEmpty) 'adresse',
      if (email.isEmpty) tr('e-mail du support'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Identité de l’éditeur et contact'),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final e in editorFields.entries)
              Text(
                  '${e.value.split(' (').first} : ${(editor[e.key] as String? ?? '').trim().isEmpty ? '–' : editor[e.key]}',
                  style: theme.textTheme.bodyMedium),
            Text(trf('E-mail du support : {0}', [email.isEmpty ? '–' : email]),
                style: theme.textTheme.bodyMedium),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(trf('À compléter : {0}.', [missing.join(', ')]),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (c) => Padding(
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(c).bottom),
                    child: _EditorIdentityForm(editor: editor, email: email),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr('Modifier')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorIdentityForm extends ConsumerStatefulWidget {
  const _EditorIdentityForm({required this.editor, required this.email});

  final Map<String, dynamic> editor;
  final String email;

  @override
  ConsumerState<_EditorIdentityForm> createState() =>
      _EditorIdentityFormState();
}

class _EditorIdentityFormState extends ConsumerState<_EditorIdentityForm> {
  late final _ctrls = {
    for (final k in editorFields.keys)
      k: TextEditingController(text: widget.editor[k] as String? ?? ''),
  };
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = tr('Adresse e-mail invalide.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(adminRepositoryProvider);
      await repo.setSetting('legal.editor', {
        for (final e in _ctrls.entries) e.key: e.value.text.trim(),
      });
      await repo.setSetting('app.support_email', email.isEmpty ? null : email);
      ref.invalidate(publicSettingsProvider);
      ref.invalidate(adminSettingsProvider);
      if (!mounted) return;
      showMessage(context, tr('Identité de l’éditeur enregistrée.'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Identité de l’éditeur'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
                tr('Affichée dans les conditions d’utilisation et la politique de confidentialité. Un champ vide n’apparaît pas.'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final e in editorFields.entries) ...[
              TextField(
                controller: _ctrls[e.key],
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    InputDecoration(labelText: e.value, counterText: ''),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: tr('E-mail du support'),
                  helperText: tr(
                      'Bouton « Contacter le support » et documents légaux')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(tr('Enregistrer'))),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/form_widgets.dart';
import '../../legal/legal_repository.dart';
import '../../legal/legal_screens.dart';
import '../../matches/data/sports_format.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../system/system_providers.dart';
import '../data/admin_repository.dart';

/// Documents légaux : version en vigueur et publication d'une nouvelle version.
/// Une nouvelle version des CGU ou de la politique de confidentialité redemande l'acceptation
/// à tous les utilisateurs à leur prochaine ouverture de l'app.
class LegalAdminScreen extends ConsumerWidget {
  const LegalAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Documents légaux')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          const EditorIdentityCard(),
          const SectionTitle('Documents'),
          Text(
              'Faites relire les textes par un juriste avant l’ouverture commerciale.',
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
                          ? 'Aucune version publiée'
                          : 'Version ${d.version} · publiée le ${shortDate(d.publishedAt)}/${d.publishedAt.year}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) => a == 'read'
                            ? openLegalDocument(context, code)
                            : Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        _LegalEditor(code: code, current: d))),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'read', child: Text('Lire')),
                          PopupMenuItem(
                              value: 'edit',
                              child: Text('Publier une nouvelle version')),
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
      text: widget.current?.title ?? legalTitles[widget.code]);
  late final _body = TextEditingController(text: widget.current?.body ?? '');
  late final _version = TextEditingController(text: _today());
  bool _busy = false;

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
        title: const Text('Publier cette version ?'),
        content: Text(needsAcceptance
            ? 'Tous les utilisateurs devront l’accepter à leur prochaine ouverture de l’app. '
                'La version précédente reste archivée.'
            : 'Elle remplace la version affichée. La version précédente reste archivée.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Publier')),
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
      showMessage(context, 'Nouvelle version publiée.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, adminErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(legalTitles[widget.code]!)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _version,
            decoration: const InputDecoration(
                labelText: 'Version',
                helperText: 'AAAA-MM-JJ (ou AAAA-MM-JJ.2)'),
          ),
          const SizedBox(height: 8),
          TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Titre')),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            minLines: 12,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Texte',
              alignLabelWithHint: true,
              helperText:
                  '« ## » titre, « - » puce, **gras**. Champs : {{editeur}}, {{forme}}, {{adresse}}, {{pays}}, {{immatriculation}}, {{contact}}.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _busy ? null : _publish, child: const Text('Publier')),
        ],
      ),
    );
  }
}

const editorFields = {
  'name': 'Nom ou raison sociale',
  'legal_form': 'Forme juridique (ex. SARL, entreprise individuelle)',
  'address': 'Adresse',
  'country': 'Pays',
  'registration': 'Immatriculation (RCCM, IFU…)',
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
      if (email.isEmpty) 'e-mail du support',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Identité de l’éditeur et contact',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final e in editorFields.entries)
              Text(
                  '${e.value.split(' (').first} : ${(editor[e.key] as String? ?? '').trim().isEmpty ? '–' : editor[e.key]}',
                  style: theme.textTheme.bodyMedium),
            Text('E-mail du support : ${email.isEmpty ? '–' : email}',
                style: theme.textTheme.bodyMedium),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('À compléter : ${missing.join(', ')}.',
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
                label: const Text('Modifier'),
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
      setState(() => _error = 'Adresse e-mail invalide.');
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
      showMessage(context, 'Identité de l’éditeur enregistrée.');
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
            Text('Identité de l’éditeur',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
                'Affichée dans les conditions d’utilisation et la politique de confidentialité. '
                'Un champ vide n’apparaît pas.',
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
              decoration: const InputDecoration(
                  labelText: 'E-mail du support',
                  helperText:
                      'Bouton « Contacter le support » et documents légaux'),
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
                child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
  }
}

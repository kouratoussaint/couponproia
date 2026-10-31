import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/form_widgets.dart';
import '../../legal/legal_repository.dart';
import '../../legal/legal_screens.dart';
import '../../matches/data/sports_format.dart';
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
          Text(
              'L’identité de l’éditeur affichée dans les documents vient du réglage « legal.editor » et le contact '
              'de « app.support_email » (Réglages et forfaits). Faites relire les textes par un juriste avant '
              'l’ouverture commerciale.',
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

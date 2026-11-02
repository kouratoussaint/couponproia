import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../../studio/data/studio_models.dart';
import '../data/community_models.dart';
import '../data/community_repository.dart';
import 'community_widgets.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Créer ou modifier son profil Tipster.
class TipsterEditScreen extends ConsumerWidget {
  const TipsterEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rights = ref.watch(communityRightsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mon profil Tipster'))),
      body: rights.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: tr('Indisponible'),
            body: userMessageFor(e)),
        data: (r) {
          if (r.profile == null && !r.canPublish) {
            return InfoMessage(
              icon: Icons.workspace_premium_outlined,
              title: tr('Devenir Tipster'),
              body: tr(
                  'Un profil Tipster public et la publication de coupons sont inclus dans les forfaits PRO TIPSTER et BUSINESS. Tout le monde peut suivre, réagir et commenter.'),
              action: FilledButton(
                onPressed: () => context.push(AppRoutes.billing),
                child: Text(tr('Voir les forfaits')),
              ),
            );
          }
          return _Form(initial: r.profile);
        },
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({this.initial});

  final TipsterProfile? initial;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _key = GlobalKey<FormState>();
  late final _handle =
      TextEditingController(text: widget.initial?.handle ?? '');
  late final _name =
      TextEditingController(text: widget.initial?.displayName ?? '');
  late final _bio = TextEditingController(text: widget.initial?.bio ?? '');
  late String? _avatar = widget.initial?.avatarPath;
  bool _busy = false;

  bool get _create => widget.initial == null;

  @override
  void dispose() {
    _handle.dispose();
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 1024 * 1024) {
        throw FormatException(tr('Image trop lourde (1 Mo maximum).'));
      }
      final path = await ref
          .read(communityRepositoryProvider)
          .uploadAvatar(bytes, file.name.split('.').last);
      setState(() => _avatar = path);
    } catch (e) {
      if (mounted) {
        showMessage(context,
            e is FormatException ? e.message : communityErrorMessage(e),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    for (final t in [_handle.text, _name.text, _bio.text]) {
      final bad = forbiddenWordIn(t);
      if (bad != null) {
        showMessage(context,
            trf('Texte refusé : « {0} ». Pas de promesse de résultat.', [bad]),
            error: true);
        return;
      }
    }
    setState(() => _busy = true);
    final repo = ref.read(communityRepositoryProvider);
    try {
      await repo.saveProfile(
        create: _create,
        handle: _handle.text,
        displayName: _name.text,
        bio: _bio.text,
        avatarPath: _avatar,
      );
      await repo.cleanAvatars(_avatar).catchError((_) {});
      ref.invalidate(communityRightsProvider);
      ref.invalidate(tipsterProvider);
      if (mounted) {
        showMessage(context,
            _create ? tr('Profil Tipster créé.') : tr('Profil mis à jour.'));
        context.pop();
      }
    } catch (e) {
      if (mounted) showMessage(context, communityErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = TipsterProfile(
      userId: widget.initial?.userId ?? '',
      handle: _handle.text,
      displayName: _name.text.isEmpty ? '?' : _name.text,
      avatarPath: _avatar,
    );
    return Form(
      key: _key,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Center(
            child: Stack(
              children: [
                TipsterAvatar(profile: preview, radius: 44),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filledTonal(
                    tooltip: tr('Changer la photo'),
                    onPressed: _busy ? null : _pickAvatar,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _handle,
            maxLength: 20,
            decoration:
                InputDecoration(labelText: tr('Identifiant'), prefixText: '@'),
            validator: validateHandle,
            onChanged: (_) => setState(() {}),
          ),
          TextFormField(
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(labelText: tr('Nom affiché')),
            validator: Validators.displayName,
            onChanged: (_) => setState(() {}),
          ),
          TextFormField(
            controller: _bio,
            maxLength: 280,
            maxLines: 4,
            minLines: 2,
            decoration:
                InputDecoration(labelText: tr('Présentation (facultatif)')),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Vos statistiques sont calculées par Coupon Pro IA à partir des résultats réels de vos coupons publiés : elles ne se saisissent pas et ne se modifient pas. Un coupon publié reste visible, pertes comprises.'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _busy ? null : _save,
              child:
                  Text(_create ? tr('Créer mon profil') : tr('Enregistrer'))),
        ],
      ),
    );
  }
}

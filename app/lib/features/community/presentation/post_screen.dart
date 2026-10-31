import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../matches/presentation/sports_widgets.dart';
import '../data/community_models.dart';
import '../data/community_repository.dart';
import 'community_widgets.dart';

/// Une publication et ses commentaires.
class PostScreen extends ConsumerStatefulWidget {
  const PostScreen({super.key, required this.postId});

  final int postId;

  @override
  ConsumerState<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends ConsumerState<PostScreen> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(postProvider(widget.postId));
    ref.invalidate(feedProvider);
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(communityRepositoryProvider).comment(widget.postId, body);
      _text.clear();
      _refresh();
    } catch (e) {
      if (mounted) showMessage(context, communityErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = ref.watch(postProvider(widget.postId));
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Publication')),
      body: post.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InfoMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Publication indisponible',
            body: userMessageFor(e)),
        data: (p) => Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _refresh();
                  await ref.read(postProvider(widget.postId).future);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  children: [
                    PostCard(post: p, openOnTap: false, onChanged: _refresh),
                    SectionTitle('Commentaires (${p.commentList.length})'),
                    if (p.commentList.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Aucun commentaire pour l’instant.')),
                    for (final c in p.commentList)
                      Card(
                        child: ListTile(
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(c.author,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                              if (c.authorIsTipster) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.verified_outlined,
                                    size: 16, color: theme.colorScheme.primary),
                              ],
                              const SizedBox(width: 6),
                              Text(relativeTime(c.createdAt, now),
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                          subtitle: Text(c.hidden
                              ? '${c.body}\n(masqué par la modération)'
                              : c.body),
                          trailing:
                              _CommentMenu(comment: c, onChanged: _refresh),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            hintText: 'Ajouter un commentaire',
                            counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: 'Envoyer',
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentMenu extends ConsumerWidget {
  const _CommentMenu({required this.comment, required this.onChanged});

  final PostComment comment;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        tooltip: 'Options',
        onSelected: (a) async {
          final repo = ref.read(communityRepositoryProvider);
          try {
            if (a == 'delete') {
              await repo.deleteComment(comment.id);
              onChanged();
            } else if (a == 'report') {
              await showReportSheet(context, ref, 'comment', '${comment.id}');
            } else if (a == 'block' &&
                await confirmBlock(context, comment.author)) {
              await repo.block(comment.authorId);
              onChanged();
            }
          } catch (e) {
            if (context.mounted) {
              showMessage(context, communityErrorMessage(e), error: true);
            }
          }
        },
        itemBuilder: (_) => [
          if (comment.isMine)
            const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
          if (!comment.isMine)
            const PopupMenuItem(value: 'report', child: Text('Signaler')),
          if (!comment.isMine)
            PopupMenuItem(
                value: 'block', child: Text('Bloquer ${comment.author}')),
        ],
      );
}

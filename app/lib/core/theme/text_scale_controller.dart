import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Taille du texte choisie dans l'app (s'ajoute au réglage du téléphone).
enum TextSize {
  small('Petit', 0.9),
  normal('Normal', 1.0),
  large('Grand', 1.15),
  extraLarge('Très grand', 1.3);

  const TextSize(this._label, this.factor);

  final String _label;
  String get label => tr(_label);
  final double factor;

  static TextSize fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => normal);
}

/// Échelle finale : réglage du téléphone × choix dans l'app, bornée pour garder des écrans lisibles.
double effectiveTextScale(double system, TextSize size) =>
    (system * size.factor).clamp(0.8, 1.6);

class TextSizeController extends Notifier<TextSize> {
  static const storageKey = 'text_size';

  @override
  TextSize build() => TextSize.fromName(
      ref.watch(sharedPreferencesProvider).getString(storageKey));

  Future<void> set(TextSize size) async {
    state = size;
    await ref.read(sharedPreferencesProvider).setString(storageKey, size.name);
  }
}

final textSizeProvider =
    NotifierProvider<TextSizeController, TextSize>(TextSizeController.new);

/// Applique la taille choisie à toute l'app (placé dans MaterialApp.builder).
class AppTextScale extends ConsumerWidget {
  const AppTextScale({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mq = MediaQuery.of(context);
    final size = ref.watch(textSizeProvider);
    return MediaQuery(
      data: mq.copyWith(
        textScaler:
            TextScaler.linear(effectiveTextScale(mq.textScaler.scale(1), size)),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'studio_models.dart';
import 'package:coupon_pro_ia/core/i18n/tr.dart';

/// Fichier produit sur le téléphone.
class StudioFile {
  const StudioFile(this.bytes, this.name, this.mimeType);

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// Capture le visuel (taille réelle du format) et l'encode dans le type demandé.
Future<StudioFile> renderStudioFile(
  RenderRepaintBoundary boundary, {
  required StudioFormat format,
  required StudioFileType type,
  required String baseName,
}) async {
  final image =
      await boundary.toImage(pixelRatio: format.width / boundary.size.width);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final png = data!.buffer.asUint8List();
    return encodeStudioFile(png,
        format: format, type: type, baseName: baseName);
  } finally {
    image.dispose();
  }
}

StudioFile encodeStudioFile(Uint8List png,
    {required StudioFormat format,
    required StudioFileType type,
    required String baseName}) {
  switch (type) {
    case StudioFileType.png:
      return StudioFile(png, '$baseName.png', 'image/png');
    case StudioFileType.jpg:
      final decoded = img.decodePng(png)!;
      return StudioFile(Uint8List.fromList(img.encodeJpg(decoded, quality: 92)),
          '$baseName.jpg', 'image/jpeg');
    case StudioFileType.pdf:
      throw ArgumentError('PDF : utiliser encodeStudioPdf');
  }
}

/// Une page au format du visuel (1 px = 0,75 pt, soit 96 ppp).
Future<StudioFile> encodeStudioPdf(Uint8List png,
    {required StudioFormat format, required String baseName}) async {
  final doc = pw.Document(title: baseName, creator: tr('Coupon Pro IA'));
  final pageFormat = PdfPageFormat(format.width * 0.75, format.height * 0.75);
  doc.addPage(pw.Page(
    pageFormat: pageFormat,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
  ));
  return StudioFile(await doc.save(), '$baseName.pdf', 'application/pdf');
}

Future<void> shareStudioFile(StudioFile file, {String? text}) async {
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile.fromData(file.bytes, mimeType: file.mimeType, name: file.name)
    ],
    fileNameOverrides: [file.name],
    text: text,
  ));
}

/// Enregistre une image dans la galerie (album « Coupon Pro IA »).
Future<bool> saveStudioImage(StudioFile file) async {
  if (!await Gal.hasAccess(toAlbum: true) &&
      !await Gal.requestAccess(toAlbum: true)) {
    return false;
  }
  await Gal.putImageBytes(file.bytes,
      album: tr('Coupon Pro IA'), name: file.name.split('.').first);
  return true;
}

/// Nom de fichier lisible : coupon-du-jour-31-10-carre
String studioFileName(StudioCoupon c, StudioFormat f) {
  String slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final d = c.firstKickoff;
  final day =
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}';
  final title = slug(c.title);
  return '${title.isEmpty ? 'coupon' : title}-$day-${slug(f.label)}';
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n.dart';

/// JPEG image or PDF document of a certificate.
enum CertFormat { jpeg, pdf }

/// Turns the certificate on screen into a JPEG or PDF, then saves it to the
/// phone (Gallery / Downloads) or hands it to the share sheet.
class CertificateExport {
  CertificateExport(this.boundary, {required this.fileName, required this.title});

  /// The RepaintBoundary drawn around the certificate.
  final GlobalKey boundary;

  /// Without extension, e.g. "HOLA-certificate-CERT-2026-000001".
  final String fileName;
  final String title;

  static const _storage = MethodChannel('hola/storage');

  /// The certificate as pixels: sharp (3× the screen), on white.
  Future<Uint8List> _png() async {
    final ro = boundary.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) throw StateError('Certificate not on screen');
    final image = await ro.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<Uint8List> bytes(CertFormat f) async {
    final png = await _png();
    final jpg = await compute(_toJpeg, png);
    if (f == CertFormat.jpeg) return jpg;
    return compute(_toPdf, (jpg, title));
  }

  String name(CertFormat f) => '$fileName.${f == CertFormat.jpeg ? 'jpg' : 'pdf'}';
  String mime(CertFormat f) => f == CertFormat.jpeg ? 'image/jpeg' : 'application/pdf';

  /// Saves to the phone. Returns where it went, for the confirmation.
  Future<String> save(CertFormat f) async {
    final data = await bytes(f);
    if (f == CertFormat.jpeg) {
      if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) throw const _NoAccess();
      await Gal.putImageBytes(data, album: 'HOLA', name: fileName);
      return tr('Gallery › HOLA');
    }
    if (Platform.isAndroid) {
      return await _storage.invokeMethod<String>('saveToDownloads', {'bytes': data, 'name': name(f), 'mime': mime(f)}) ?? 'Downloads';
    }
    // iOS has no Downloads folder: the share sheet's "Save to Files" does it.
    await share(f, data: data);
    return tr('Files');
  }

  /// Opens the phone's share sheet (WhatsApp, Gmail, Bluetooth…).
  Future<void> share(CertFormat f, {Uint8List? data, Rect? origin}) async {
    final d = data ?? await bytes(f);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(d, mimeType: mime(f), name: name(f))],
        fileNameOverrides: [name(f)],
        subject: title,
        sharePositionOrigin: origin,
      ),
    );
  }
}

/// Gallery access was refused.
class _NoAccess implements Exception {
  const _NoAccess();
}

bool isNoAccess(Object e) => e is _NoAccess || e is GalException;

/// PNG with transparent rounded corners → JPEG on white.
Uint8List _toJpeg(Uint8List png) {
  final src = img.decodePng(png)!;
  final out = img.Image(width: src.width, height: src.height)..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(out, src);
  return img.encodeJpg(out, quality: 92);
}

/// One A4 page with the certificate centred.
Future<Uint8List> _toPdf((Uint8List, String) a) async {
  final (jpg, title) = a;
  final doc = pw.Document(title: title, author: 'HOLA Professional', creator: 'HOLA Professional');
  final image = pw.MemoryImage(jpg);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ),
  );
  return doc.save();
}

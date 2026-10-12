import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/config/app_config.dart';
import '../../data/api/api_client.dart';
import '../../models/session.dart';
import '../auth_controller.dart';
import 'pdf_kit.dart';

/// Builds documents with the lab header and sends them to the system print dialog.
class PrintService {
  PrintService({required this.lab, required this.logoLoader, this.printer});

  final LabInfo lab;
  final Future<Uint8List?> Function(LabInfo lab) logoLoader;

  /// Replaced in tests (receives the generated PDF instead of opening a dialog).
  final Future<void> Function(Uint8List bytes, String name, PdfPageFormat format)? printer;

  Future<PdfKit> kit() async => PdfKit.load(lab, logo: await logoLoader(lab));

  Future<void> printPdf(Uint8List bytes, {required String name, PdfPageFormat? format}) async {
    final target = printer;
    final pageFormat = format ?? PdfPageFormat.a4;
    if (target != null) return target(bytes, name, pageFormat);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: name, format: pageFormat);
  }
}

/// Lab logo: downloaded when online and kept on disk so offline prints still have it.
class LogoCache {
  LogoCache(this._http);

  final http.Client _http;
  final Map<String, Uint8List?> _memory = {};

  Future<Uint8List?> load(LabInfo lab) async {
    final url = lab.logo;
    if (url == null || url.isEmpty) return null;
    if (_memory.containsKey(url)) return _memory[url];
    File? file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File(p.join(dir.path, 'lab_logo_${lab.id}.img'));
    } catch (_) {
      file = null;
    }
    Uint8List? bytes;
    try {
      final base = Uri.parse(AppConfig.apiBaseUrl);
      final response = await _http.get(base.resolve(url)).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        bytes = response.bodyBytes;
        await file?.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {
      // Offline: fall back to the copy on disk.
    }
    if (bytes == null && file != null && await file.exists()) bytes = await file.readAsBytes();
    return _memory[url] = bytes;
  }
}

final logoCacheProvider = Provider<LogoCache>((ref) => LogoCache(ref.watch(httpClientProvider)));

final printServiceProvider = Provider<PrintService>((ref) {
  final session = ref.watch(sessionProvider);
  final cache = ref.watch(logoCacheProvider);
  return PrintService(
    lab: session?.lab ?? const LabInfo(id: 0, name: ''),
    logoLoader: cache.load,
  );
});

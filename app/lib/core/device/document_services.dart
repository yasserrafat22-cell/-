import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// جدول بالعربية لملف PDF أو للطباعة (نتائج البحث والتقارير).
class TableDocument {
  const TableDocument({
    required this.title,
    required this.headers,
    required this.rows,
    this.subtitle,
    this.sections = const [],
  });

  final String title;
  final String? subtitle;
  final List<String> headers;
  final List<List<String>> rows;

  /// أقسام إضافية بعناوين (مثل «الموردون» ثم «العملاء») تُعرض بالترتيب قبل [rows].
  final List<(String, List<List<String>>)> sections;
}

/// إنشاء PDF عربي وطباعته؛ منفصل حتى يُستبدل في الاختبارات.
class DocumentServices {
  const DocumentServices();

  Future<Uint8List> pdf(TableDocument doc) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/cairo/Cairo-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/cairo/Cairo-Bold.ttf'),
    );
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    pw.Widget table(List<List<String>> rows) => pw.TableHelper.fromTextArray(
      headers: doc.headers,
      data: rows,
      headerStyle: const pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
      cellAlignment: pw.Alignment.centerRight,
      headerAlignment: pw.Alignment.centerRight,
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              doc.title,
              style: const pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (doc.subtitle case final s?)
              pw.Text(s, style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          for (final (heading, rows) in doc.sections)
            if (rows.isNotEmpty) ...[
              pw.Text(
                '$heading (${rows.length})',
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              table(rows),
              pw.SizedBox(height: 12),
            ],
          if (doc.rows.isNotEmpty) table(doc.rows),
        ],
      ),
    );
    return pdf.save();
  }

  /// يفتح نافذة الطباعة في الجهاز (أي طابعة متاحة، أو حفظ PDF).
  Future<void> print(TableDocument doc, String name) async {
    final bytes = await pdf(doc);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
  }
}

final documentServicesProvider = Provider<DocumentServices>(
  (ref) => const DocumentServices(),
);

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'domain.dart';

typedef PeriodReportPdfData = ({
  PeriodReport report,
  String period,
  String filterLabel,
  ByteData regularFont,
  ByteData boldFont,
});

const _plum = PdfColor.fromInt(0xFF49374F);
const _lilac = PdfColor.fromInt(0xFF8E72B1);
const _rose = PdfColor.fromInt(0xFFCF849B);
const _ink = PdfColor.fromInt(0xFF24202A);
const _muted = PdfColor.fromInt(0xFF675C71);
const _lavender = PdfColor.fromInt(0xFFF0EAF5);
const _stripe = PdfColor.fromInt(0xFFF8F5FA);
const _rule = PdfColor.fromInt(0xFFE7DFEB);

String _issueDateText(DateTime now) =>
    '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

Future<Uint8List> buildPeriodReportPdf(PeriodReportPdfData data) {
  final report = data.report;
  final issueDate = _issueDateText(DateTime.now());
  final document = pw.Document(title: 'تقرير الفترة', author: 'حصيلة');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 32),
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(data.regularFont),
        bold: pw.Font.ttf(data.boldFont),
      ),
      textDirection: pw.TextDirection.rtl,
      // Each row is shorter than a page, even for the longest product name.
      maxPages: report.items.length + 3,
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.only(bottom: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _rule, width: .7),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _text(
                    'حصيلة  ·  تقرير الفترة',
                    size: 10.5,
                    bold: true,
                    color: _plum,
                  ),
                  _text(data.filterLabel, size: 9.5, color: _muted),
                ],
              ),
            ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 14),
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _rule, width: .7)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _text('حصيلة', size: 9.5, bold: true, color: _plum),
            _text(
              'صفحة ${context.pageNumber} من ${context.pagesCount}',
              size: 9,
              color: _muted,
            ),
          ],
        ),
      ),
      build: (_) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: pw.BoxDecoration(
            color: _plum,
            borderRadius: pw.BorderRadius.circular(14),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _lilac,
                      borderRadius: pw.BorderRadius.circular(7),
                    ),
                    child: _text(
                      'حصيلة · ملخص الأصناف',
                      size: 10,
                      bold: true,
                      color: PdfColors.white,
                    ),
                  ),
                  _text(
                    'تاريخ الإصدار: $issueDate',
                    size: 9.5,
                    color: _lavender,
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              _text(
                'تقرير الفترة',
                size: 26,
                bold: true,
                color: PdfColors.white,
              ),
              pw.SizedBox(height: 5),
              _text(
                '${data.filterLabel} · ${data.period}',
                size: 11.5,
                color: _lavender,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            pw.Expanded(
              flex: 2,
              child: _metricCard(
                'إجمالي المبلغ المطلوب',
                moneyText(report.amount),
                unit: 'ريال',
                accent: _rose,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricCard(
                'إجمالي الكمية',
                '${report.quantity}',
                unit: 'قطعة',
                accent: _lilac,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricCard(
                'عدد الأصناف',
                '${report.items.length}',
                unit: 'صنف',
                accent: _plum,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        if (report.items.isEmpty)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: _stripe,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: _rule, width: .8),
            ),
            child: _text(
              'لا توجد أصناف في هذه الفترة',
              size: 12,
              color: _muted,
              align: pw.TextAlign.center,
            ),
          )
        else ...[
          pw.Table(
            border: const pw.TableBorder(
              top: pw.BorderSide(color: _rule, width: .7),
              bottom: pw.BorderSide(color: _plum, width: 1.1),
              left: pw.BorderSide(color: _rule, width: .7),
              right: pw.BorderSide(color: _rule, width: .7),
              horizontalInside: pw.BorderSide(color: _rule, width: .5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.1),
              1: pw.FlexColumnWidth(1.05),
              2: pw.FlexColumnWidth(4.3),
              3: pw.FlexColumnWidth(0.65),
            },
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: _plum),
                children: [
                  _cell('المبلغ (ريال)', heading: true),
                  _cell('العدد', heading: true),
                  _cell('الصنف', heading: true, name: true),
                  _cell('#', heading: true),
                ],
              ),
              for (final (index, item) in report.items.indexed)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: index.isEven ? _stripe : PdfColors.white,
                  ),
                  children: [
                    _cell(item.amount == null ? '-' : moneyText(item.amount!)),
                    _cell('${item.quantity}'),
                    _cell(item.name, name: true),
                    _cell('${index + 1}', muted: true),
                  ],
                ),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _lavender),
                children: [
                  _cell(moneyText(report.amount), bold: true),
                  _cell('${report.quantity}', bold: true),
                  _cell('الإجمالي العام', name: true, bold: true),
                  _cell(''),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          _text(
            'المبالغ محسوبة بأسعار البيع للطلبات غير الملغاة خلال الفترة المحددة.',
            size: 9,
            color: _muted,
          ),
        ],
      ],
    ),
  );
  return document.save();
}

pw.Widget _metricCard(
  String label,
  String value, {
  String? unit,
  required PdfColor accent,
}) => pw.Container(
  padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
  decoration: pw.BoxDecoration(
    color: _lavender,
    borderRadius: pw.BorderRadius.circular(10),
    border: pw.Border.all(color: _rule, width: .8),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 6,
            height: 6,
            decoration: pw.BoxDecoration(
              color: accent,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 5),
          _text(label, size: 10, color: _muted),
        ],
      ),
      pw.SizedBox(height: 5),
      pw.Wrap(
        spacing: 4,
        crossAxisAlignment: pw.WrapCrossAlignment.center,
        children: [
          _text(value, size: 17, bold: true, color: _plum, numeric: true),
          if (unit != null) _text(unit, size: 9.5, color: _muted),
        ],
      ),
    ],
  ),
);

pw.Widget _cell(
  String value, {
  bool heading = false,
  bool name = false,
  bool bold = false,
  bool muted = false,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
  child: _text(
    value,
    size: 10.5,
    bold: heading || bold,
    color: heading
        ? PdfColors.white
        : muted
        ? _muted
        : _ink,
    numeric: !heading && !name,
    align: name ? pw.TextAlign.right : pw.TextAlign.center,
  ),
);

pw.Text _text(
  String value, {
  required double size,
  PdfColor color = _ink,
  bool bold = false,
  bool numeric = false,
  pw.TextAlign align = pw.TextAlign.right,
}) => pw.Text(
  value,
  textAlign: align,
  textDirection: numeric ? pw.TextDirection.ltr : pw.TextDirection.rtl,
  style: pw.TextStyle(
    fontSize: size,
    color: color,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  ),
);

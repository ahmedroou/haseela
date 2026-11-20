import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'domain.dart';

typedef PeriodReportPdfData = ({
  PeriodReport report,
  String period,
  String? filterLabel,
  ByteData regularFont,
  ByteData boldFont,
});

const _plum = PdfColor.fromInt(0xFF49374F);
const _ink = PdfColor.fromInt(0xFF24202A);
const _muted = PdfColor.fromInt(0xFF675C71);
const _lavender = PdfColor.fromInt(0xFFF0EAF5);
const _stripe = PdfColor.fromInt(0xFFF8F5FA);
const _rule = PdfColor.fromInt(0xFFE7DFEB);

class _ReportFont extends pw.TtfFont {
  _ReportFont(super.data);

  @override
  PdfTtfFont buildFont(PdfDocument document) {
    final font = PdfTtfFont(document, data);
    final glyphs = font.font.charToGlyphIndexMap;
    // pdf 3.12 aliases yeh to alef maksura and can leave isolated yeh unmapped.
    glyphs[0xFEF1] = glyphs[0x064A]!;
    glyphs[0xFEEF] = glyphs[0x0649]!;
    return font;
  }
}

String _issueDateText(DateTime now) =>
    '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

Future<Uint8List> buildPeriodReportPdf(PeriodReportPdfData data) {
  final report = data.report;
  final issueDate = _issueDateText(DateTime.now());
  final document = pw.Document(title: 'تقرير الأصناف', author: 'حصيلة');
  final subtitle = [?data.filterLabel, data.period].join(' · ');
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 32),
      theme: pw.ThemeData.withFont(
        base: _ReportFont(data.regularFont),
        bold: _ReportFont(data.boldFont),
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
                    'حصيلة  ·  تقرير الأصناف',
                    size: 10.5,
                    bold: true,
                    color: _plum,
                  ),
                  _text(data.period, size: 9.5, color: _muted),
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
          padding: const pw.EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: pw.BoxDecoration(
            color: _plum,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _text('حصيلة', size: 12, bold: true, color: _lavender),
                  _text(
                    'تاريخ الإصدار: $issueDate',
                    size: 9.5,
                    color: _lavender,
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              _text(
                'تقرير الأصناف',
                size: 25,
                bold: true,
                color: PdfColors.white,
              ),
              pw.SizedBox(height: 5),
              _text(subtitle, size: 11.5, color: _lavender),
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
                primary: true,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricCard(
                'إجمالي الكمية',
                '${report.quantity}',
                unit: 'قطعة',
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: _metricCard(
                'عدد الأصناف',
                '${report.items.length}',
                unit: 'صنف',
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
              0: pw.FlexColumnWidth(1.8),
              1: pw.FlexColumnWidth(1.5),
              2: pw.FlexColumnWidth(0.9),
              3: pw.FlexColumnWidth(4.4),
            },
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: _plum),
                children: [
                  _cell('الإجمالي (ريال)', heading: true),
                  _cell('سعر الوحدة', heading: true),
                  _cell('العدد', heading: true),
                  _cell('الصنف', heading: true, name: true),
                ],
              ),
              for (final (index, item) in report.items.indexed)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: index.isEven ? _stripe : PdfColors.white,
                  ),
                  children: [
                    _cell(_amountText(item.amount), bold: true),
                    _cell(_amountText(item.unitPrice)),
                    _cell('${item.quantity}'),
                    _cell(item.name, name: true),
                  ],
                ),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _lavender),
                children: [
                  _cell(moneyText(report.amount), bold: true),
                  _cell(''),
                  _cell('${report.quantity}', bold: true),
                  _cell('الإجمالي العام', name: true, bold: true),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          _text(
            'المبالغ بالريال السعودي وتُحسب بأسعار قائمة المنتجات عند توفرها، وبالسعر المسجّل للمنتجات الأخرى. الطلبات الملغاة مستبعدة.',
            size: 9.5,
            color: _muted,
          ),
          if (report.items.any((item) => item.unitPrice == null))
            _text(
              'الشرطة في عمود سعر الوحدة تعني أن السعر غير محدد أو يختلف بين الكميات.',
              size: 9.5,
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
  bool primary = false,
}) => pw.Container(
  padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
  decoration: pw.BoxDecoration(
    color: primary ? _lavender : _stripe,
    borderRadius: pw.BorderRadius.circular(10),
    border: pw.Border.all(color: _rule, width: .8),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _text(label, size: 10, color: _muted),
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

String _amountText(int? amount) => amount == null ? '-' : moneyText(amount);

pw.Widget _cell(
  String value, {
  bool heading = false,
  bool name = false,
  bool bold = false,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
  child: _text(
    value,
    size: 10.5,
    bold: heading || bold,
    color: heading ? PdfColors.white : _ink,
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
    wordSpacing: numeric ? 1 : 1.5,
    lineSpacing: 3,
  ),
);

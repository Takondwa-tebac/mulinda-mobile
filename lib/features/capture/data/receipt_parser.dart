import 'receipt_ocr.dart';
import 'receipt_text.dart';

/// What sort of document a receipt photo turned out to be.
enum ReceiptKind {
  /// An MRA fiscal (EFD) till receipt or tax invoice.
  tillReceipt,

  /// A bank app's payment / transfer confirmation screen.
  bankTransfer,

  /// A mobile operator's (TNM, Airtel) transaction receipt screen.
  mobileMoney,

  /// An ATM withdrawal slip.
  atmSlip,

  /// A bill, quote or form that is not proof of a payment.
  notPayment,

  /// Anything else, including handwritten receipt books.
  unknown,
}

/// A transaction proposed from a receipt photo. Never recorded directly: the
/// user reviews it, and a low-confidence draft goes to the AI fallback.
class ReceiptDraft {
  const ReceiptDraft({
    required this.kind,
    required this.confidence,
    this.amount,
    this.fee,
    this.merchant,
    this.payee,
    this.reference,
    this.occurredAt,
    this.currency = 'MWK',
  });

  /// Below this, the draft is not trusted: send the image to the AI fallback.
  static const fallbackBelow = 0.6;

  final ReceiptKind kind;
  final double? amount;
  final double? fee;
  final String currency;
  /// The shop, or the bank / operator for app transfer receipts.
  final String? merchant;

  /// Who a bank or mobile-money transfer was sent to, when shown.
  final String? payee;
  final String? reference;
  final DateTime? occurredAt;

  /// 0–1: how sure the parser is about the draft as a whole.
  final double confidence;

  bool get isReceipt => kind != ReceiptKind.notPayment;

  bool get needsFallback => isReceipt && (amount == null || confidence < fallbackBelow);

  /// The payload shape the API already stores for AI-parsed receipts.
  Map<String, dynamic> toPayload() => {
        'is_receipt': isReceipt,
        'type': isReceipt ? 'expense' : 'unknown',
        'amount': amount,
        'fee': fee,
        'currency': currency,
        'merchant': merchant,
        'payee': payee,
        'reference': reference,
        'occurred_at': occurredAt?.toIso8601String(),
        'line_items': const <Map<String, dynamic>>[],
        'confidence': confidence,
        'kind': kind.name,
        'parser': 'device',
        'parser_version': ReceiptParser.version,
      };
}

/// A merchant recognised by its MRA TIN or by a name printed on the receipt.
class KnownMerchant {
  const KnownMerchant(this.name, {this.tin, this.pattern});

  final String name;
  final String? tin;
  final RegExp? pattern;
}

/// Seed list; grows as approved scans show which TINs belong to whom.
const knownMerchants = [
  KnownMerchant('Chipiku Plus', tin: '20164753'),
  KnownMerchant('Lucky Shopping Center', tin: '31617337'),
  KnownMerchant('Ekhaya Farm Foods', tin: '70113247'),
];

final _namedMerchants = [
  KnownMerchant('ESCOM', pattern: RegExp(r'\bESCOM\b|ELECTRICITY SUPPLY CORPORATION', caseSensitive: false)),
  KnownMerchant('NBS Bank', pattern: RegExp(r'^NBS BANK\b', caseSensitive: false)),
  KnownMerchant('National Bank of Malawi', pattern: RegExp(r'^National Bank\b', caseSensitive: false)),
  KnownMerchant('FDH Bank', pattern: RegExp(r'^FDH\b', caseSensitive: false)),
  KnownMerchant('Standard Bank', pattern: RegExp(r'^Standard Bank\b', caseSensitive: false)),
  KnownMerchant('TNM', pattern: RegExp(r'^tnm$', caseSensitive: false)),
  KnownMerchant('Airtel', pattern: RegExp(r'^airtel$', caseSensitive: false)),
];

/// Turns the text read from a receipt photo into a [ReceiptDraft], entirely
/// on the device. Each kind of document has its own reader; the parser picks
/// the kind from tell-tale words, then reads the fields the way that layout
/// prints them.
class ReceiptParser {
  const ReceiptParser({this.merchants = knownMerchants, this.now});

  /// Bump when parsing rules change, so accuracy can be compared per version.
  static const version = 1;

  final List<KnownMerchant> merchants;

  /// The current time, for rejecting impossible dates (tests pin it).
  final DateTime? now;

  ReceiptDraft parse(OcrDocument doc) {
    final text = doc.text;
    final flat = squash(text);

    if (_notPayment.hasMatch(flat)) {
      return const ReceiptDraft(kind: ReceiptKind.notPayment, confidence: 0.9);
    }
    if (RegExp(r'paymentcomplete|paymentsenddetails|transfersuccessful').hasMatch(flat)) {
      return _keyValueScreen(doc, ReceiptKind.bankTransfer);
    }
    if (RegExp(r'^(tnm|airtel)', caseSensitive: false).hasMatch(text) && flat.contains('transactionreceipt')) {
      return _keyValueScreen(doc, ReceiptKind.mobileMoney);
    }
    if (flat.contains('withdraw') && RegExp(r'card|atm|avail').hasMatch(flat)) {
      return _atmSlip(doc);
    }
    if (RegExp(r'legal+receipt|taxinvoice|vatregistered|regi.tered').hasMatch(flat) ||
        (RegExp(r'\bT?I?N\s*:', caseSensitive: false).hasMatch(text) && flat.contains('total'))) {
      return _tillReceipt(doc);
    }
    return _unknown(doc);
  }

  /// Pro-formas, quotes and forms list prices but prove no payment.
  static final _notPayment = RegExp(
    r'p(ro|re)forma|quotation|jobcard|deliverynote|estimate|statementfor|ministatement|orderform',
  );

  // ---------------------------------------------------------------------------
  // Bank and mobile-money app screens: "Label    value" rows.

  static final _refValue = RegExp(r'^[A-Za-z0-9][A-Za-z0-9/-]{4,}$');

  ReceiptDraft _keyValueScreen(OcrDocument doc, ReceiptKind kind) {
    bool isAmount(String v) => parseAmountLine(v) != null || parseAmountLine(v.replaceFirst(RegExp(r'\s*VAT.*$'), '')) != null;
    double? amountOf(String? v) => v == null ? null : parseAmountLine(v) ?? parseAmountLine(v.replaceFirst(RegExp(r'\s*VAT.*$'), ''));

    final amount = amountOf(doc
        .valueFor(RegExp(r'^(Payment/Send( Amount)?|Total Deduction|Amount Sent|Total Amount|Amount)\b', caseSensitive: false), isAmount)
        ?.value);
    final fee = amountOf(doc.valueFor(RegExp(r'^(Payment Fee|Transaction Fee|Fee|Charges?)\b', caseSensitive: false), isAmount)?.value);
    final reference = doc
        .valueFor(
          RegExp(r'^(Payment Own Ref|Own Ref|Transaction ID|Trans(action)? Ref(erence)?|Reference( number)?|Ref)\b\s*:?', caseSensitive: false),
          (v) => _refValue.hasMatch(v.replaceAll(' ', '')),
        )
        ?.value
        .replaceAll(' ', '');
    final occurredAt = _date(doc, RegExp(r'^(On|Date and time|Date|Date & Time)\b\s*:?', caseSensitive: false));

    // The merchant is the bank or operator whose receipt this is; who the
    // money went to is kept as the payee (unless it is the sender's own
    // account, as on a bundle purchase).
    final issuer = _named(doc);
    var payee = _payee(doc);
    final self = doc.valueFor(RegExp(r'^Account name\b', caseSensitive: false), (_) => true)?.value;
    if (payee != null && self != null && squash(payee) == squash(self)) payee = null;
    final merchant = issuer ?? payee;

    var confidence = 0.0;
    if (amount != null) confidence += 0.6;
    if (reference != null) confidence += 0.15;
    if (occurredAt != null) confidence += 0.15;
    if (merchant != null) confidence += 0.1;
    return ReceiptDraft(
      kind: kind,
      amount: amount,
      fee: fee,
      merchant: merchant,
      payee: payee,
      reference: reference,
      occurredAt: occurredAt,
      confidence: confidence,
    );
  }

  /// The first name printed in the "To" / destination block: below the
  /// sender's account and above the amount row.
  String? _payee(OcrDocument doc) {
    final named = doc.valueFor(
      RegExp(r'^(Destination name|Paid to|Recipient|Beneficiary name|Merchant)\b', caseSensitive: false),
      (v) => RegExp(r'[A-Za-z]{2}').hasMatch(v),
    );
    if (named != null) return named.value;

    final to = doc.labelled(RegExp(r'^To$', caseSensitive: false)).firstOrNull;
    final from = doc.labelled(RegExp(r'^From$', caseSensitive: false)).firstOrNull;
    final amountRow = doc.labelled(RegExp(r'^Payment/Send( Amount)?$|^Amount$', caseSensitive: false)).firstOrNull;
    if (to == null || from == null || amountRow == null) return null;
    // The sender's (masked) account number closes the "From" block.
    final fromEnd = doc.lines
        .where((l) => l.left > from.right && l.top >= from.top - doc.lineHeight && RegExp(r'\d{3,}').hasMatch(l.text))
        .firstOrNull;
    final start = fromEnd?.bottom ?? to.top - doc.lineHeight * 2;
    for (final l in doc.lines) {
      if (l.left <= to.right || l.centerY <= start || l.centerY >= amountRow.top) continue;
      if (RegExp(r'[A-Za-z]{2}').hasMatch(l.text) && !RegExp(r'^\W*\d[\d\s]*$').hasMatch(l.text)) return l.text.trim();
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // MRA fiscal till receipts: a header, items, then a totals block.

  static final _roles = <String, RegExp>{
    'total': RegExp(r'^(GRAND\s*TOTAL|TOTAL(?!\s*VAT)(\s*\(?Incl.*)?|Amount Due|Balance Due|Total Charges)\s*:?-?\s*$', caseSensitive: false),
    'tendered': RegExp(r'^(CASH|Amount Paid|Tendered|Paid)\s*:?\s*$', caseSensitive: false),
    'change': RegExp(r'^(CHANGE|Cash Balance)\s*:?\s*$', caseSensitive: false),
    'subtotal': RegExp(r'^(Sub\s*Tota\s*l|Subtotal|TAXABLE\b.*)$', caseSensitive: false),
    'vat': RegExp(r'^([UV]AT\b.*|TOTAL VAT|Sales VAT.*)$', caseSensitive: false),
  };

  ReceiptDraft _tillReceipt(OcrDocument doc) {
    final totals = _readTotals(doc);
    final merchant = _merchantByTin(doc) ?? _named(doc) ?? _headerName(doc);
    final reference = doc
        .valueFor(
          RegExp(r'^(EIS\s*)?(Re)?ce\s*ipt\s*(#|No\.?|Number)?\s*[:\-]*|^Invoice\s*(#|No\.?)\s*:?', caseSensitive: false),
          (v) => RegExp(r'[A-Za-z0-9]').hasMatch(v) && RegExp(r'^[A-Za-z0-9][A-Za-z0-9/ -]{3,}$').hasMatch(v) && parseDate(v, now: now) == null,
        )
        ?.value
        .replaceAll(' ', '');
    final occurredAt = _date(doc, RegExp(r'^(Date\s*&\s*Time|DATE|Date)\b\s*:?', caseSensitive: false));

    var confidence = 0.0;
    if (totals.amount != null) confidence += totals.labelled ? 0.5 : 0.25;
    if (totals.consistent) confidence += 0.15;
    if (merchant != null) confidence += 0.15;
    if (occurredAt != null) confidence += 0.1;
    if (reference != null) confidence += 0.1;
    return ReceiptDraft(
      kind: ReceiptKind.tillReceipt,
      amount: totals.amount,
      merchant: merchant,
      reference: reference,
      occurredAt: occurredAt,
      confidence: confidence > 1 ? 1 : confidence,
    );
  }

  /// Pairs totals-block labels with amounts. Till printers do not always put
  /// a value on its label's row (Chipiku prints each value a row higher), so
  /// several row offsets are tried and the one whose numbers make sense wins:
  /// one value per label, TOTAL no more than the cash tendered, change less
  /// than the cash.
  ({double? amount, bool labelled, bool consistent}) _readTotals(OcrDocument doc) {
    // "Total:- MK 5,000.00" carries its own value.
    for (final l in doc.lines) {
      final m = RegExp(r'^(GRAND\s*)?TOTAL\s*:-?\s*(.+)$', caseSensitive: false).firstMatch(l.text.trim());
      final amount = m == null ? null : parseAmountLine(m[2]!);
      if (amount != null) return (amount: amount, labelled: true, consistent: false);
    }

    final labels = <({OcrLine line, String role})>[
      for (final l in doc.lines)
        for (final MapEntry(key: role, value: re) in _roles.entries)
          if (re.hasMatch(l.text.trim())) (line: l, role: role),
    ];
    final values = [for (final l in doc.lines) if (l.left > doc.width * 0.45 && parseAmountLine(l.text) != null) l];
    if (labels.where((l) => l.role == 'total').isEmpty || values.isEmpty) {
      return (amount: null, labelled: false, consistent: false);
    }

    final gaps = [for (var i = 1; i < values.length; i++) values[i].centerY - values[i - 1].centerY]..sort();
    // Row height: the lower quartile of gaps, as item lines often skip rows.
    final pitch = gaps.isEmpty ? doc.lineHeight : gaps[gaps.length ~/ 4].clamp(doc.lineHeight * 0.8, doc.lineHeight * 2.5);

    ({double cost, Map<String, double> byRole})? best;
    for (final shift in const [0, -1, 1]) {
      var cost = 0.0;
      final used = <OcrLine>{};
      final byRole = <String, double>{};
      for (final label in labels) {
        if (label.line.left > doc.width * 0.45) continue;
        final target = label.line.centerY + shift * pitch;
        OcrLine? nearest;
        for (final v in values) {
          if (nearest == null || (v.centerY - target).abs() < (nearest.centerY - target).abs()) nearest = v;
        }
        final residual = (nearest!.centerY - target).abs() / pitch;
        if (residual > 0.6) {
          cost += 1;
          continue;
        }
        cost += residual;
        if (!used.add(nearest)) cost += 1.5;
        // The last TOTAL-type label wins ("Sub Total" … "Grand Total").
        byRole[label.role] = parseAmountLine(nearest.text)!;
      }
      final total = byRole['total'];
      final tendered = byRole['tendered'];
      final change = byRole['change'];
      if (total == null) cost += 5;
      if (total != null && tendered != null && total > tendered) cost += 3;
      if (tendered != null && change != null && change >= tendered) cost += 3;
      if (shift != 0) cost += 0.25; // prefer the printed row when it fits as well
      if (best == null || cost < best.cost) best = (cost: cost, byRole: byRole);
    }

    final total = best!.byRole['total'];
    final tendered = best.byRole['tendered'];
    final change = best.byRole['change'];
    final consistent = total != null && tendered != null && change != null && (tendered - total - change).abs() < 0.01;
    return (amount: total, labelled: total != null, consistent: consistent);
  }

  /// MRA receipts print the seller's TIN, which OCR reads more reliably than
  /// the shop name. Dot-matrix 0s read as 8s, so compare with 8s folded to 0.
  String? _merchantByTin(OcrDocument doc) {
    String fold(String s) => s.replaceAll('8', '0');
    for (final l in doc.lines) {
      final m = RegExp(r'\bT?P?IN\s*[:#]\s*([0-9]{8})\b', caseSensitive: false).firstMatch(l.text);
      if (m == null) continue;
      for (final known in merchants) {
        if (known.tin != null && fold(known.tin!) == fold(m[1]!)) return known.name;
      }
    }
    return null;
  }

  String? _named(OcrDocument doc) {
    for (final known in [...merchants, ..._namedMerchants]) {
      if (known.pattern != null && doc.lines.any((l) => known.pattern!.hasMatch(l.text.trim()))) return known.name;
    }
    return null;
  }

  /// The shop name: the first line of the header that is not boilerplate.
  String? _headerName(OcrDocument doc) {
    final boilerplate = RegExp(
      r'LEGAL|RECEIPT|INVOICE|P\.?\s*O\.?\s*BOX|BOX\b|Tel|Phone|E-?MAIL|@|TIN|VAT|REGISTERED|Till|Branch|^\W*$',
      caseSensitive: false,
    );
    for (final l in doc.lines.take(8)) {
      final t = l.text.trim().replaceAll(RegExp(r'[^\w\s&.-]'), '').trim();
      if (t.length >= 3 && RegExp(r'[A-Za-z]{3}').hasMatch(t) && !boilerplate.hasMatch(t)) return t;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // ATM slips and everything else.

  ReceiptDraft _atmSlip(OcrDocument doc) {
    final withdraw = doc.labelled(RegExp(r'^WITHDRAW', caseSensitive: false)).firstOrNull;
    double? amount;
    if (withdraw != null) {
      // The first amount at or below the WITHDRAW line (not the balance after).
      for (final l in doc.lines) {
        if (l.bottom < withdraw.top) continue;
        if (RegExp(r'AVAIL|BAL', caseSensitive: false).hasMatch(l.text)) break;
        amount = parseAmountLine(l.text);
        if (amount != null) break;
      }
    }
    final seq = doc.valueFor(RegExp(r'^SEQ\w*\s*NU?MB?\w*[\s.:\-]*', caseSensitive: false), (v) => RegExp(r'^\d{2,}$').hasMatch(v));
    final occurredAt = _date(doc, null);
    final merchant = _named(doc);

    var confidence = 0.0;
    if (amount != null) confidence += 0.6;
    if (occurredAt != null) confidence += 0.15;
    if (merchant != null) confidence += 0.15;
    if (seq != null) confidence += 0.1;
    return ReceiptDraft(
      kind: ReceiptKind.atmSlip,
      amount: amount,
      merchant: merchant,
      reference: seq?.value,
      occurredAt: occurredAt,
      confidence: confidence,
    );
  }

  /// No recognised layout: only a labelled total counts, and even that stays
  /// below the fallback bar, so the AI or the user takes over.
  ReceiptDraft _unknown(OcrDocument doc) {
    final totals = _readTotals(doc);
    return ReceiptDraft(
      kind: ReceiptKind.unknown,
      amount: totals.amount,
      merchant: _merchantByTin(doc) ?? _named(doc),
      occurredAt: _date(doc, null),
      confidence: totals.amount == null ? 0.1 : 0.4,
    );
  }

  /// The labelled date if there is one, else the first date anywhere,
  /// skipping dates that are not the transaction's (EFD activation dates).
  DateTime? _date(OcrDocument doc, RegExp? label) {
    if (label != null) {
      final labelled = doc.valueFor(label, (v) => parseDate(v, now: now) != null);
      if (labelled != null) return parseDate(labelled.value, now: now);
    }
    for (final l in doc.lines) {
      if (RegExp(r'ACTIVATION|EXPIR|PRINTED|Opened', caseSensitive: false).hasMatch(l.text)) continue;
      final date = parseDate(l.text, now: now);
      if (date != null) return date;
    }
    return null;
  }
}

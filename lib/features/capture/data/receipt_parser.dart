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

  /// A bank card machine (POS) slip from paying at a shop.
  cardSlip,

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

/// Shops whose names OCR mangles in known ways ("BUY MOkL", "BLY-MU",
/// "EKhaya Fars Foods"). Checked before the issuing bank, which also heads
/// card slips.
final _shops = [
  KnownMerchant('Buy More', pattern: RegExp(r'\bB[UL]Y[\s-]*M(ORE|OKL|GRE|U)\b', caseSensitive: false)),
  KnownMerchant('Sana Cash & Carry', pattern: RegExp(r'\bSANA\b', caseSensitive: false)),
  KnownMerchant('PEP Stores', pattern: RegExp(r'\bPEP\s+(STORES|MAL)', caseSensitive: false)),
  KnownMerchant('Easy Mart', pattern: RegExp(r'\bEASY\s*MART\b', caseSensitive: false)),
  KnownMerchant('Lilongwe Dairy', pattern: RegExp(r'\bL\w?l?ongwe\s*Dairy', caseSensitive: false)),
  KnownMerchant('Ekhaya Farm Foods', pattern: RegExp(r'\bE[kK]h?l?i?aya\b|\bFar[mns]\s*Foods\b', caseSensitive: false)),
  KnownMerchant('Lucky Shopping Center', pattern: RegExp(r'\bLUCKY\s*SHO', caseSensitive: false)),
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
  static const version = 2;

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
    final till = RegExp(r'legal+receipt|taxin\w*oice|vatregistered|regi.tered|cash[sg]ale|laybye|salesreceipt|totalamount')
            .hasMatch(flat) ||
        (RegExp(r'\bT?I?N\s*:', caseSensitive: false).hasMatch(text) && flat.contains('total'));
    if (!till && _cardSignals.hasMatch(flat)) {
      if (_declined.hasMatch(flat)) return const ReceiptDraft(kind: ReceiptKind.notPayment, confidence: 0.9);
      return _cardSlip(doc);
    }
    if (till) return _tillReceipt(doc);
    return _unknown(doc);
  }

  /// Pro-formas, quotes and forms list prices but prove no payment.
  static final _notPayment = RegExp(
    r'p(ro|re)forma|quotation|jobcard|deliverynote|estimate|statementfor|ministatement|orderform',
  );

  // ---------------------------------------------------------------------------
  // Card machine (POS) slips: the bank's logo, the shop, then one amount.

  static final _cardSignals =
      RegExp(r'approv|au[it]hori[sz]|authcode|declined|donothonor|terminalid|merchantid|c?ardho\w*cop|customercop|visadeb');
  static final _declined = RegExp(r'declined|donothonor|notapproved|transactionfailed');

  ReceiptDraft _cardSlip(OcrDocument doc) {
    double? amount;
    for (final l in doc.lines) {
      amount = _slipAmount(l.text);
      if (amount != null) break;
    }
    final reference = doc
        .valueFor(RegExp(r'^(RRN|Receipt\s*No|Recept\s*INO)\b\s*:?', caseSensitive: false),
            (v) => RegExp(r'^[A-Za-z0-9]{5,}$').hasMatch(v.replaceAll(' ', '')))
        ?.value
        .replaceAll(' ', '');
    final occurredAt = _date(doc, RegExp(r'^(DATE|Date)\b\s*:?', caseSensitive: false));
    final merchant = _shop(doc);
    final approved = RegExp(r'approv|authori[sz]ed').hasMatch(squash(doc.text));

    var confidence = 0.0;
    if (amount != null) confidence += 0.6;
    if (approved) confidence += 0.15;
    if (occurredAt != null) confidence += 0.1;
    if (merchant != null) confidence += 0.15;
    return ReceiptDraft(
      kind: ReceiptKind.cardSlip,
      amount: amount,
      merchant: merchant,
      reference: reference,
      occurredAt: occurredAt,
      confidence: confidence > 1 ? 1 : confidence,
    );
  }

  /// The slip's amount: a decimal number with only money words around it
  /// ("Amount: MWK 22,600.00", "MYIK60830.00", "168, 166.00 MWK"), so card
  /// numbers, times and ids don't count.
  static double? _slipAmount(String text) {
    final m = RegExp(r'(\d{1,3}(?:,\s?\d{3})+|\d{1,3}(?:\s\d{3})+|\d+)\s?\.\s?(\d{2})(?!\d)').firstMatch(text);
    if (m == null) return null;
    final rest = text.replaceFirst(m[0]!, ' ');
    if (!RegExp(r'^(\W|A?r?mount|AMT|MWK|MK|M[YVW]+I?K|M|K|\s)*$', caseSensitive: false).hasMatch(rest)) return null;
    final value = double.tryParse('${m[1]!.replaceAll(RegExp(r'[,\s]'), '')}.${m[2]}');
    return value != null && value > 0 ? value : null;
  }

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
    // "Payment": what a PEP layby slip says was paid.
    'total': RegExp(
      r'^(GRAND\s*TOTAL|TOTAL(?!\s*VAT)(\s*\(?Incl.*)?|TOTAL\s*AMOUNT|Amount Due|Balance Due|Total Charges|Payment)\s*:?-?\s*$',
      caseSensitive: false,
    ),
    'tendered': RegExp(r'^(CASH|Amount Paid|Tendered|Paid)\s*:?\s*$', caseSensitive: false),
    'change': RegExp(r'^(CHANGE|Cash Balance)\s*:?\s*$', caseSensitive: false),
    'subtotal': RegExp(r'^(Sub\s*Tota\s*l|Subtotal|TAXABLE\b.*)$', caseSensitive: false),
    'vat': RegExp(r'^([UV]AT\b.*|TOTAL VAT|Sales VAT.*)$', caseSensitive: false),
  };

  ReceiptDraft _tillReceipt(OcrDocument doc) {
    final totals = _checkTotal(doc, _readTotals(doc));
    final merchant = _merchantByTin(doc) ?? _shop(doc) ?? _named(doc) ?? _headerName(doc);
    final reference = doc
        .valueFor(
          RegExp(r'^(EIS\s*)?(Re)?ce\s*ipt\s*(#|No\.?|Number)?\s*[:\-]*|^Invoice\s*(#|No\.?)\s*:?', caseSensitive: false),
          (v) => RegExp(r'[A-Za-z0-9]').hasMatch(v) && RegExp(r'^[A-Za-z0-9][A-Za-z0-9/ -]{3,}$').hasMatch(v) && parseDate(v, now: now) == null,
        )
        ?.value
        .replaceAll(' ', '');
    final occurredAt = _date(doc, RegExp(r'^(Date\s*&\s*Time|DATE|Date)\b\s*:?', caseSensitive: false));

    // A total nothing else on the receipt confirms is never trusted: on a
    // photo, the TOTAL label is easily paired with the change or a 0.00.
    var confidence = 0.0;
    if (totals.amount != null) confidence += totals.supported ? 0.65 : 0.25;
    if (merchant != null) confidence += 0.15;
    if (occurredAt != null) confidence += 0.1;
    if (reference != null) confidence += 0.1;
    if (!totals.supported && confidence >= ReceiptDraft.fallbackBelow) confidence = ReceiptDraft.fallbackBelow - 0.05;
    return ReceiptDraft(
      kind: ReceiptKind.tillReceipt,
      amount: totals.amount,
      merchant: merchant,
      reference: reference,
      occurredAt: occurredAt,
      confidence: confidence > 1 ? 1 : confidence,
    );
  }

  /// Malawi's VAT rates, current and past.
  static const _vatRates = [0.165, 0.175];

  /// Confirms the total against the rest of the receipt. Each of these is
  /// one confirmation: the VAT printed for it (VAT = total x r / (1 + r)),
  /// two printed values that differ by it (cash less change) or add up to it
  /// (taxable plus VAT, or items), and the same value printed twice.
  ///
  /// The total paired with its label needs one. When it has none (the TOTAL
  /// line may not have been read at all), the printed value with the most
  /// confirmations, at least two, is used instead: one is not enough there,
  /// as a single VAT-rated item is confirmed by its own VAT line. OCR'd 8s may
  /// really be 0s, so values are also tried with them folded. Works in cents.
  ({double? amount, bool supported}) _checkTotal(
    OcrDocument doc,
    ({double? amount, bool labelled, bool consistent, bool inline}) totals,
  ) {
    int cents(double v) => (v * 100).round();
    final printed = [for (final l in doc.lines) ..._amountsIn(l.text)];
    // Whole-number receipts (PEP prints "18870") count bare numbers as
    // candidates, but not as terms of sums, where ids would add up by chance.
    final bare = [
      for (final l in doc.lines)
        if (RegExp(r'^\d{3,7}$').hasMatch(l.text.trim())) double.parse(l.text.trim()),
    ];
    // Zero-rated VAT lines print 0.00, and x + 0 confirms nothing.
    final values = {for (final v in printed) for (final f in _eightsAsZeros(v)) if (f > 0) cents(f)}.toList();
    final sums = <int>{};
    final differences = <int>{};
    for (var i = 0; i < values.length; i++) {
      for (var j = 0; j < values.length; j++) {
        if (i == j) continue;
        sums.add(values[i] + values[j]);
        if (values[i] > values[j]) differences.add(values[i] - values[j]);
      }
    }
    final seen = <int, int>{};
    for (final v in [...printed, ...bare]) {
      for (final c in {for (final f in _eightsAsZeros(v)) cents(f)}) {
        seen[c] = (seen[c] ?? 0) + 1;
      }
    }
    int confirmations(int total) {
      final vat = values.any((v) => v < total && _vatRates.any((r) => (total * r / (1 + r) - v).abs() <= 1.5));
      return (vat ? 1 : 0) +
          (differences.contains(total) ? 1 : 0) +
          (sums.contains(total) ? 1 : 0) +
          ((seen[total] ?? 0) >= 2 ? 1 : 0);
    }

    final confirmed = {
      for (final c in {...values, for (final v in bare) cents(v)})
        if (c > 0 && confirmations(c) >= 2) c: confirmations(c),
    };
    // One part of a larger confirmed total is a subtotal (an item, the
    // VAT-rated part), however well confirmed itself.
    bool isPart(int c) => confirmed.keys.any((bigger) => bigger > c && values.contains(bigger - c));
    ({int cents, int score})? best;
    for (final MapEntry(key: c, value: score) in confirmed.entries) {
      if (isPart(c)) continue;
      if (best == null || score > best.score || (score == best.score && c > best.cents)) best = (cents: c, score: score);
    }

    final total = totals.amount;
    if (total != null && total > 0) {
      if (totals.inline || totals.consistent) return (amount: total, supported: true);
      for (final t in _eightsAsZeros(total)) {
        if (confirmations(cents(t)) < 1 || isPart(cents(t))) continue;
        return (amount: t, supported: true);
      }
    }
    if (best != null) return (amount: best.cents / 100, supported: true);
    return (amount: total != null && total > 0 ? total : null, supported: false);
  }

  /// Every decimal amount printed in [text] ("30,638.30", "X 36.000.00").
  static Iterable<double> _amountsIn(String text) sync* {
    for (final m in RegExp(r'\d{1,3}(?:[,.]\d{3})+[.,]\d{2}(?!\d)|\d+[.,]\d{2}(?!\d)').allMatches(text)) {
      final v = parseAmountLine(m[0]!);
      if (v != null) yield v;
    }
  }

  /// [value] as read, then with its 8s turned into 0s (dot-matrix printers).
  static Iterable<double> _eightsAsZeros(double value) sync* {
    yield value;
    final digits = value.toStringAsFixed(2);
    final eights = [for (var i = 0; i < digits.length; i++) if (digits[i] == '8') i];
    if (eights.isEmpty || eights.length > 4) return;
    for (var mask = 1; mask < 1 << eights.length; mask++) {
      final chars = digits.split('');
      for (var b = 0; b < eights.length; b++) {
        if (mask & (1 << b) != 0) chars[eights[b]] = '0';
      }
      yield double.parse(chars.join());
    }
  }

  /// Pairs totals-block labels with amounts. Till printers do not always put
  /// a value on its label's row (Chipiku prints each value a row higher), so
  /// several row offsets are tried and the one whose numbers make sense wins:
  /// one value per label, TOTAL no more than the cash tendered, change less
  /// than the cash.
  ({double? amount, bool labelled, bool consistent, bool inline}) _readTotals(OcrDocument doc) {
    // "Total:- MK 5,000.00" carries its own value.
    for (final l in doc.lines) {
      final m = RegExp(r'^(GRAND\s*)?TOTAL\s*:-?\s*(.+)$', caseSensitive: false).firstMatch(l.text.trim());
      final amount = m == null ? null : parseAmountLine(m[2]!);
      if (amount != null && amount > 0) return (amount: amount, labelled: true, consistent: false, inline: true);
    }

    final labels = <({OcrLine line, String role})>[
      for (final l in doc.lines)
        for (final MapEntry(key: role, value: re) in _roles.entries)
          if (re.hasMatch(l.text.trim())) (line: l, role: role),
    ];
    // PEP prints whole numbers only ("47800"): when nothing has decimals,
    // bare numbers in the value column count.
    final wholeNumbers = !doc.lines.any((l) => parseAmountLine(l.text) != null);
    double? valueOf(OcrLine l) =>
        parseAmountLine(l.text) ?? (wholeNumbers && RegExp(r'^\d{3,7}$').hasMatch(l.text.trim()) ? double.parse(l.text.trim()) : null);
    final values = [for (final l in doc.lines) if (l.left > doc.width * 0.45 && valueOf(l) != null) l];
    if (labels.where((l) => l.role == 'total').isEmpty || values.isEmpty) {
      return (amount: null, labelled: false, consistent: false, inline: false);
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
        byRole[label.role] = valueOf(nearest)!;
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
    return (amount: total, labelled: total != null, consistent: consistent, inline: false);
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

  String? _shop(OcrDocument doc) {
    for (final known in _shops) {
      if (doc.lines.any((l) => known.pattern!.hasMatch(l.text.trim()))) return known.name;
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
      amount: totals.amount != null && totals.amount! > 0 ? totals.amount : null,
      merchant: _merchantByTin(doc) ?? _shop(doc) ?? _named(doc),
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
    // EFD receipts print the "EJ ACTIVATION DATE" value on its own line, often
    // a row off its label, so dates near that label are skipped too.
    final skip = RegExp(r'ACTIVATION|EXPIR|PRINTED|Opened', caseSensitive: false);
    final skipped = doc.lines.where((l) => skip.hasMatch(l.text)).toList();
    for (final l in doc.lines) {
      if (skip.hasMatch(l.text)) continue;
      if (skipped.any((s) => (s.centerY - l.centerY).abs() < doc.lineHeight * 2.2)) continue;
      final date = parseDate(l.text, now: now);
      if (date != null) return date;
    }
    return null;
  }
}

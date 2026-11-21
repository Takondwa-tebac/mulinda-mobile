/// Which provider an SMS sender belongs to, for filtering the phone's inbox.
///
/// Sender ids are compared normalised (lower case, letters and digits only).
/// The lists mirror the API's SMS matchers (app/Sms/Matchers), so short codes
/// such as FDH's 52525 and NBM's 626626 are recognised, not only named
/// senders.
class SmsSenders {
  SmsSenders._();

  static const known = <String, ({String name, List<String> senders})>{
    'mpamba': (name: 'TNM Mpamba', senders: ['mpamba', 'tnm']),
    'airtel': (name: 'Airtel Money', senders: ['airtel']),
    'fdh': (name: 'FDH Bank', senders: ['52525', 'fdh']),
    'nbm': (name: 'NBM', senders: ['626626', 'nbm', 'mo626']),
    'nbs': (name: 'NBS Bank', senders: ['nbs']),
    'centenary': (
      name: 'Centenary Bank',
      senders: ['centebank', 'centenary', 'cbank'],
    ),
  };

  /// Prefix of a filter on one exact sender that is not a known provider
  /// (for example a SACCO or another bank).
  static const senderPrefix = 'sender:';

  static String normalise(String sender) =>
      sender.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// The known provider id a sender belongs to, or null.
  static String? providerFor(String sender) {
    final normalised = normalise(sender);
    if (normalised.isEmpty) return null;
    for (final entry in known.entries) {
      if (entry.value.senders.any(normalised.contains)) return entry.key;
    }
    return null;
  }

  /// Whether [sender] passes [filter]: a known provider id, or
  /// [senderPrefix] followed by one exact sender.
  static bool matches(String sender, String filter) {
    if (filter.startsWith(senderPrefix)) {
      return normalise(sender) == normalise(filter.substring(senderPrefix.length));
    }
    return providerFor(sender) == filter;
  }
}

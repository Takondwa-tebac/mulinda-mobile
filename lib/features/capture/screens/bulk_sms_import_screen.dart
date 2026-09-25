import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:another_telephony/another_telephony.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../data/inbox_repository.dart';

class BulkSmsImportScreen extends ConsumerStatefulWidget {
  const BulkSmsImportScreen({super.key});

  @override
  ConsumerState<BulkSmsImportScreen> createState() => _BulkSmsImportScreenState();
}

class _BulkSmsImportScreenState extends ConsumerState<BulkSmsImportScreen> {
  final Telephony _telephony = Telephony.instance;
  bool _loading = false;
  bool _scanning = false;
  List<Map<String, dynamic>> _selectedSms = [];
  String? _selectedVendor;
  int _totalSms = 0;

  final _vendors = [
    {'id': null, 'name': 'All Vendors'},
    {'id': 'tnm', 'name': 'TNM Mpamba'},
    {'id': 'airtel', 'name': 'Airtel Money'},
    {'id': 'fdh', 'name': 'FDH'},
    {'id': 'nbm', 'name': 'NBM'},
    {'id': 'centenary', 'name': 'Centenary'},
  ];

  @override
  void initState() {
    super.initState();
    _scanSms();
  }

  Future<void> _scanSms() async {
    setState(() => _scanning = true);
    try {
      final granted = await _telephony.requestSmsPermissions ?? false;
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('SMS permission required')));
        }
        setState(() => _scanning = false);
        return;
      }

      final messages = await _telephony.getInboxSms();
      final financialSms = messages.where((msg) => _isFinancialSms(msg.body ?? '')).toList();

      setState(() {
        _totalSms = financialSms.length;
        _selectedSms = financialSms.map((msg) => {
          'body': msg.body ?? '',
          'sender': msg.sender ?? '',
          'received_at': msg.date ?? DateTime.now().toIso8601String(),
        }).toList();
        _scanning = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Failed to scan SMS: $e')));
      }
      setState(() => _scanning = false);
    }
  }

  bool _isFinancialSms(String body) {
    final b = body.toLowerCase();
    const keywords = [
      'mwk', 'kwacha', 'airtel', 'mpamba', 'tnm', 'mo626',
      'received', 'sent', 'withdrawn', 'deposited', 'payment',
      'balance', 'transaction', 'national bank', 'standard bank',
      'fdh', 'nbs', 'paid', 'debited', 'credited',
    ];
    return keywords.any(b.contains);
  }

  Future<void> _importSms() async {
    if (_selectedSms.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('No SMS selected for import')));
      return;
    }

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/v1/sms/bulk-import', data: {
        'messages': _selectedSms,
        'vendor_filter': _selectedVendor,
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('${_selectedSms.length} SMS imported successfully'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ));
        ref.invalidate(pendingSmsProvider);
        ref.invalidate(pendingReceiptsProvider);
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bulk SMS Import'),
        actions: [
          if (_selectedSms.isNotEmpty)
            TextButton(
              onPressed: _loading ? null : _importSms,
              child: _loading
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Import (${_selectedSms.length})'),
            ),
        ],
      ),
      body: SafeArea(
        child: _scanning
            ? Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Vendor filter
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<String?>(
                      value: _selectedVendor,
                      decoration: InputDecoration(
                        labelText: 'Filter by vendor',
                        border: OutlineInputBorder(),
                      ),
                      items: _vendors.map((vendor) {
                        return DropdownMenuItem<String?>(
                          value: vendor['id'] as String?,
                          child: Text(vendor['name'] as String),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedVendor = value);
                        _filterSms();
                      },
                    ),
                  ),
                  // SMS list
                  Expanded(
                    child: _selectedSms.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.sms_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                const SizedBox(height: 16),
                                Text(
                                  'No financial SMS found',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _scanSms,
                                  child: Text('Rescan'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _selectedSms.length,
                            itemBuilder: (context, index) {
                              final sms = _selectedSms[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Icon(Icons.sms, color: Theme.of(context).colorScheme.primary),
                                  title: Text(
                                    sms['sender'] ?? 'Unknown',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    _truncate(sms['body'] ?? '', 50),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    _formatAmount(sms['body'] ?? ''),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  void _filterSms() {
    if (_selectedVendor == null) {
      // Rescan to get all SMS
      _scanSms();
      return;
    }

    // Filter existing list by vendor
    final filtered = _selectedSms.where((sms) {
      final sender = (sms['sender'] ?? '').toLowerCase();
      final vendor = _selectedVendor!.toLowerCase();
      return sender.contains(vendor);
    }).toList();

    setState(() => _selectedSms = filtered);
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + '...';
  }

  String _formatAmount(String body) {
    // Try to extract amount from SMS body
    final amountRegex = RegExp(r'[\d,.]+\s*MWK|MWK\s*[\d,.]+');
    final match = amountRegex.firstMatch(body);
    if (match != null) {
      return match.group(0) ?? '';
    }
    return '';
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:another_telephony/telephony.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../data/inbox_repository.dart';

class ManualSmsScanScreen extends ConsumerStatefulWidget {
  const ManualSmsScanScreen({super.key});

  @override
  ConsumerState<ManualSmsScanScreen> createState() => _ManualSmsScanScreenState();
}

class _ManualSmsScanScreenState extends ConsumerState<ManualSmsScanScreen> {
  final Telephony _telephony = Telephony.instance;
  bool _loading = false;
  bool _scanning = false;
  List<Map<String, dynamic>> _allSms = [];
  Set<int> _selectedSmsIndices = {};
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedVendor;

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
    // Default to today's date
    _fromDate = DateTime.now();
    _toDate = DateTime.now();
  }

  List<Map<String, dynamic>> get _filteredSms {
    var filtered = _allSms;

    // Filter by date range
    if (_fromDate != null) {
      filtered = filtered.where((sms) {
        final smsDate = DateTime.parse(sms['received_at'] as String);
        return smsDate.isAfter(_fromDate!.subtract(const Duration(days: 1))) ||
               smsDate.isAtSameMomentAs(_fromDate!);
      }).toList();
    }

    if (_toDate != null) {
      filtered = filtered.where((sms) {
        final smsDate = DateTime.parse(sms['received_at'] as String);
        return smsDate.isBefore(_toDate!.add(const Duration(days: 1))) ||
               smsDate.isAtSameMomentAs(_toDate!);
      }).toList();
    }

    // Filter by vendor
    if (_selectedVendor != null) {
      filtered = filtered.where((sms) {
        final sender = (sms['sender'] as String).toLowerCase();
        return sender.contains(_selectedVendor!.toLowerCase());
      }).toList();
    }

    return filtered;
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
      final financialSms = messages
          .where((msg) => _isFinancialSms(msg.body ?? ''))
          .toList();

      setState(() {
        _allSms = financialSms
            .map(
              (msg) => {
                'body': msg.body ?? '',
                'sender': msg.sender ?? '',
                'received_at': msg.date ?? DateTime.now().toIso8601String(),
              },
            )
            .toList();
        _selectedSmsIndices.clear();
        _scanning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Found ${_allSms.length} financial SMS'),
          ));
      }
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

  Future<void> _importSelectedSms() async {
    final selectedSms = _filteredSms.asMap().entries
        .where((entry) => _selectedSmsIndices.contains(entry.key))
        .map((entry) => entry.value)
        .toList();

    if (selectedSms.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('No SMS selected for import')));
      return;
    }

    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        '/v1/sms/bulk-import',
        data: {'messages': selectedSms, 'vendor_filter': _selectedVendor},
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${selectedSms.length} SMS imported successfully'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
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

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fromDate!, end: _toDate!),
    );

    if (picked != null && mounted) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
    }
  }

  void _toggleSelectAll() {
    if (_selectedSmsIndices.length == _filteredSms.length) {
      setState(() => _selectedSmsIndices.clear());
    } else {
      setState(() {
        _selectedSmsIndices = Set.from(List.generate(_filteredSms.length, (i) => i));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSms;

    return Scaffold(
      appBar: AppBar(
        title: Text('Manual SMS Scan'),
        actions: [
          if (_selectedSmsIndices.isNotEmpty)
            TextButton(
              onPressed: _loading ? null : _importSelectedSms,
              child: _loading
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Import (${_selectedSmsIndices.length})'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Date range filter
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _selectDateRange,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date Range',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _fromDate != null && _toDate != null
                              ? '${_formatDate(_fromDate!)} - ${_formatDate(_toDate!)}'
                              : 'Select date range',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _scanning ? null : _scanSms,
                    child: _scanning
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Scan'),
                  ),
                ],
              ),
            ),
            // Vendor filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                },
              ),
            ),
            const SizedBox(height: 12),
            // Select all / deselect all
            if (filtered.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectedSmsIndices.length == filtered.length,
                      onChanged: (_) => _toggleSelectAll(),
                    ),
                    TextButton(
                      onPressed: _toggleSelectAll,
                      child: Text(
                        _selectedSmsIndices.length == filtered.length
                            ? 'Deselect All'
                            : 'Select All',
                      ),
                    ),
                    const Spacer(),
                    Text('${_selectedSmsIndices.length} selected'),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // SMS list
            Expanded(
              child: _scanning
                  ? Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.sms_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _allSms.isEmpty
                                    ? 'No financial SMS found. Tap Scan to search.'
                                    : 'No SMS match current filters.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final sms = filtered[index];
                            final isSelected = _selectedSmsIndices.contains(index);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (_) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedSmsIndices.remove(index);
                                    } else {
                                      _selectedSmsIndices.add(index);
                                    }
                                  });
                                },
                                leading: Icon(
                                  Icons.sms,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(
                                  sms['sender'] ?? 'Unknown',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _truncate(sms['body'] ?? '', 50),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDateTime(sms['received_at'] as String),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
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

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength) + '...';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  String _formatAmount(String body) {
    final amountRegex = RegExp(r'[\d,.]+\s*MWK|MWK\s*[\d,.]+');
    final match = amountRegex.firstMatch(body);
    if (match != null) {
      return match.group(0) ?? '';
    }
    return '';
  }
}

extension on SmsMessage {
  String get sender => address ?? '';
}

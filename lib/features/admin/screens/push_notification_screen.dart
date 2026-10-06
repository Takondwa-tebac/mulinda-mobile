import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../data/admin_repository.dart';

class PushNotificationScreen extends ConsumerStatefulWidget {
  const PushNotificationScreen({super.key});

  @override
  ConsumerState<PushNotificationScreen> createState() =>
      _PushNotificationScreenState();
}

class _PushNotificationScreenState
    extends ConsumerState<PushNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _broadcastAll = true;
  bool _sending = false;
  String? _imagePath;

  /// Chosen recipients when targeting specific users: id → display label.
  final Map<String, String> _recipients = {};

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1024);
    if (picked == null) return;
    setState(() => _imagePath = picked.path);
  }

  void _removeImage() {
    setState(() => _imagePath = null);
  }

  Future<void> _chooseUsers() async {
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RecipientPicker(initial: Map.of(_recipients)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _recipients
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_broadcastAll && _recipients.isEmpty) {
      _showError('Choose at least one user to send to.');
      return;
    }
    setState(() => _sending = true);
    try {
      final count = await ref.read(adminRepositoryProvider).broadcastNotification(
            title: _title.text.trim(),
            body: _body.text.trim(),
            imagePath: _imagePath,
            userIds: _broadcastAll ? null : _recipients.keys.toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Sent to $count user${count == 1 ? '' : 's'}.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ));
      _title.clear();
      _body.clear();
      _removeImage();
      setState(_recipients.clear);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.displayMessage);
    } catch (_) {
      if (!mounted) return;
      _showError('Failed to send notification. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(message),
              backgroundColor: Theme.of(context).colorScheme.error));
  }

  String get _sendLabel {
    if (_sending) return 'Sending…';
    if (_broadcastAll) return 'Send to all users';
    final n = _recipients.length;
    return 'Send to $n user${n == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Send Notification')),
      // SafeArea keeps the form clear of the status/navigation bars; the
      // centred max-width keeps it readable on tablets and landscape.
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                children: [
                  // Preview card
                  Card(
                    color: scheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            child: const Icon(Icons.notifications, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ValueListenableBuilder(
                                  valueListenable: _title,
                                  builder: (_, v, _) => Text(
                                    v.text.isEmpty ? 'Notification title' : v.text,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ValueListenableBuilder(
                                  valueListenable: _body,
                                  builder: (_, v, _) => Text(
                                    v.text.isEmpty
                                        ? 'Your notification body will appear here...'
                                        : v.text,
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant, fontSize: 13),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('Compose',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _title,
                    maxLength: 100,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'Keep it short and clear',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _body,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Message body',
                      hintText: 'What do you want users to know?',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Body is required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Image picker
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Image (optional)',
                              style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 8),
                          if (_imagePath != null)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(_imagePath!),
                                    height: 150,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                    ),
                                    onPressed: _removeImage,
                                  ),
                                ),
                              ],
                            )
                          else
                            InkWell(
                              onTap: _pickImage,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: scheme.surfaceContainerHighest,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        size: 32,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Tap to add image',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text('Recipients',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),

                  Card(
                    child: RadioGroup<bool>(
                      groupValue: _broadcastAll,
                      onChanged: (v) => setState(() => _broadcastAll = v!),
                      child: Column(
                        children: [
                          const RadioListTile<bool>(
                            value: true,
                            title: Text('All users'),
                            subtitle: Text('Send to every registered user'),
                          ),
                          const RadioListTile<bool>(
                            value: false,
                            title: Text('Specific users'),
                            subtitle: Text('Pick the people who should receive it'),
                          ),
                          if (!_broadcastAll)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_recipients.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          for (final e in _recipients.entries)
                                            InputChip(
                                              label: Text(e.value),
                                              onDeleted: () =>
                                                  setState(() => _recipients.remove(e.key)),
                                            ),
                                        ],
                                      ),
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: _chooseUsers,
                                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                                    label: Text(
                                      _recipients.isEmpty ? 'Choose users' : 'Edit recipients',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Icon(Icons.send_rounded),
                    label: Text(_sendLabel),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Searchable, multi-select list of users for targeting a notification.
/// Selections persist across searches; returns the final id → label map.
class _RecipientPicker extends ConsumerStatefulWidget {
  const _RecipientPicker({required this.initial});

  final Map<String, String> initial;

  @override
  ConsumerState<_RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends ConsumerState<_RecipientPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late final Map<String, String> _selected = Map.of(widget.initial);
  final List<Map<String, dynamic>> _users = [];

  Timer? _debounce;
  String _query = '';
  int _page = 1;
  int? _lastPage;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        !_loading &&
        (_lastPage == null || _page < _lastPage!)) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value.trim();
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _users.clear();
      _page = 1;
    });
    try {
      final data = await ref
          .read(adminRepositoryProvider)
          .listUsers(page: 1, search: _query);
      if (!mounted) return;
      final items = (data['data'] as List?) ?? [];
      final meta = data['meta'] as Map<String, dynamic>?;
      setState(() {
        _users.addAll(items.cast<Map<String, dynamic>>());
        _lastPage = (meta?['last_page'] as num?)?.toInt();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.displayMessage; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final data = await ref
          .read(adminRepositoryProvider)
          .listUsers(page: next, search: _query);
      if (!mounted) return;
      final items = (data['data'] as List?) ?? [];
      setState(() {
        _page = next;
        _users.addAll(items.cast<Map<String, dynamic>>());
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _label(Map<String, dynamic> u) =>
      (u['full_name'] ?? u['username'] ?? u['email'] ?? 'User').toString();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Choose users',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Text('${_selected.length} selected',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name, email or username…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                  onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : _users.isEmpty
                          ? const Center(child: Text('No users found.'))
                          : ListView.builder(
                              controller: _scroll,
                              itemCount: _users.length + (_loadingMore ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i == _users.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                final u = _users[i];
                                final id = u['id'].toString();
                                return CheckboxListTile(
                                  value: _selected.containsKey(id),
                                  title: Text(_label(u),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(u['email']?.toString() ?? '',
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  onChanged: (checked) => setState(() {
                                    if (checked == true) {
                                      _selected[id] = _label(u);
                                    } else {
                                      _selected.remove(id);
                                    }
                                  }),
                                );
                              },
                            ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  child: Text('Done (${_selected.length})'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/events_providers.dart';

class EventCheckInScreen extends ConsumerStatefulWidget {
  final int eventId;
  final String eventTitle;

  const EventCheckInScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  ConsumerState<EventCheckInScreen> createState() => _EventCheckInScreenState();
}

class _EventCheckInScreenState extends ConsumerState<EventCheckInScreen> {
  final _tokenController = TextEditingController();
  bool _checking = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value != null && value.isNotEmpty) await _submit(value);
  }

  Future<void> _submit(String value) async {
    if (_checking || _success != null) return;
    String token;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic> ||
          decoded['event_id'] != widget.eventId ||
          decoded['ticket_token'] is! String) {
        throw const FormatException('This QR code is not for this event.');
      }
      token = decoded['ticket_token'] as String;
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    if (token.length < 32 || token.length > 128) {
      setState(() => _error = 'This QR code is not a valid event pass.');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(eventsRepositoryProvider)
          .checkIn(widget.eventId, token);
      if (!mounted) return;
      setState(() {
        _success = result['event_title'] as String? ?? widget.eventTitle;
        _tokenController.clear();
      });
      ref.invalidate(myAttendanceProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Could not reach the server. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan event pass')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.eventTitle,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (_success case final success?)
          Card(
            color: AppColors.success.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_outline, size: 44),
                  const SizedBox(height: 8),
                  Text('Attendance recorded for $success'),
                  TextButton(
                    onPressed: () => setState(() {
                      _success = null;
                      _error = null;
                    }),
                    child: const Text('Scan another pass'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 320,
              child: MobileScanner(onDetect: _onDetect),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Point the camera at the attendee’s event QR code.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(
              labelText: 'Or enter the ticket token',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _checking
                ? null
                : () => _submit(
                    jsonEncode({
                      'event_id': widget.eventId,
                      'ticket_token': _tokenController.text.trim(),
                    }),
                  ),
            child: _checking
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Validate pass'),
          ),
        ],
        if (_error case final message?) ...[
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ],
      ],
    ),
  );
}

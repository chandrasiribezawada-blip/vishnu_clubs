import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/event.dart';
import '../../../models/event_ticket.dart';
import '../../../shared/widgets/state_views.dart';
import '../providers/events_providers.dart';

class EventPassScreen extends ConsumerStatefulWidget {
  final Event event;

  const EventPassScreen({super.key, required this.event});

  @override
  ConsumerState<EventPassScreen> createState() => _EventPassScreenState();
}

class _EventPassScreenState extends ConsumerState<EventPassScreen> {
  late Future<EventTicket> _ticketFuture;

  @override
  void initState() {
    super.initState();
    _ticketFuture = ref
        .read(eventsRepositoryProvider)
        .issuePass(widget.event.id);
  }

  void _retry() {
    setState(() {
      _ticketFuture = ref
          .read(eventsRepositoryProvider)
          .issuePass(widget.event.id);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Event pass')),
    body: FutureBuilder<EventTicket>(
      future: _ticketFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          final error = snapshot.error;
          final message = error is ApiException
              ? error.message
              : 'Could not reach the server. Check your connection and try again.';
          return ErrorState(message: message, onRetry: _retry);
        }
        final ticket = snapshot.requireData;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.event.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(widget.event.clubName),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: QrImageView(
                      data: ticket.qrValue,
                      version: QrVersions.auto,
                      size: 240,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Show this QR code to the event coordinator. '
                  'It can only be used once.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Valid until ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(ticket.expiresAt.toLocal()))}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

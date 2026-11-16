import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/report.dart';
import '../services/report_service.dart';

/// Community "My reports" screen: residents follow their reports from
/// Reported -> Worker on the way -> Fixed (read-only; workers update the
/// status from their dashboard).
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final service = ReportService.instance;
  String filter = 'mine';
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  List<Report> _filtered() {
    final all = service.reports.values.toList();
    final list = switch (filter) {
      'mine' => all.where((r) => service.mine.contains(r.id)).toList(),
      'fixed' => all.where((r) => r.isCleared).toList(),
      _ => all.where((r) => !r.isCleared).toList(),
    };
    list.sort((a, b) => b.ts - a.ts);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final list = _filtered();
        return RefreshIndicator(
          onRefresh: () async {
            if (!service.isOnline) await service.connect();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (key, label) in const [('mine', 'My reports'), ('open', 'All open'), ('fixed', 'Fixed')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: filter == key,
                        onSelected: (_) => setState(() => filter = key),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Text(
                    filter == 'mine' ? 'You haven’t reported anything yet.' : 'Nothing here yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              for (final r in list) _ReportCard(report: r, isMine: service.mine.contains(r.id)),
            ],
          ),
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.isMine});
  final Report report;
  final bool isMine;

  static Color typeColor(String t) => switch (t) {
        'blocked' => Colors.deepPurple,
        'overflowing' => Colors.red,
        'damaged' => Colors.orange,
        _ => Colors.blueGrey,
      };

  String _ago(int ts) {
    final m = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    if (m < 1440) return '${m ~/ 60} h ago';
    return '${m ~/ 1440} d ago';
  }

  Future<void> _share(BuildContext context) async {
    final r = report;
    final where = r.hasLocation ? 'https://maps.google.com/?q=${r.lat},${r.lng}' : '';
    final msg = StringBuffer()
      ..writeln('🚨 Drain problem reported to the municipality (${r.id})')
      ..writeln(r.typeLabel)
      ..writeln('📍 ${r.landmark.isEmpty ? 'See map' : r.landmark}');
    if (where.isNotEmpty) msg.writeln(where);
    if (r.note.isNotEmpty) msg.writeln('📝 ${r.note}');
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg.toString())}'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t open WhatsApp')));
    }
  }

  Widget _badge(String text, Color c) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withAlpha(36), borderRadius: BorderRadius.circular(6)),
        child: Text(text.toUpperCase(), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4)),
      );

  Widget _step(BuildContext context, String label, bool on) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: on ? Colors.green.withAlpha(40) : Colors.blueGrey.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? Colors.green.shade700 : Colors.blueGrey)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = report;
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline);
    final photo = r.photoBytes;
    final after = r.donePhotoBytes;
    final onWay = r.status == 'progress' || r.status == 'cleared';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: photo != null
                    ? Image.memory(photo, width: 76, height: 76, fit: BoxFit.cover, gaplessPlayback: true)
                    : Container(width: 76, height: 76, color: Colors.blueGrey.withAlpha(40), child: const Icon(Icons.water_damage_outlined, size: 32)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    _badge(r.typeLabel, typeColor(r.type)),
                    if (isMine)
                      Text('YOUR REPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                  ]),
                  const SizedBox(height: 4),
                  Text(r.landmark.isEmpty ? 'Location pinned on map' : r.landmark,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('${r.id} · ${_ago(r.ts)}${r.status == 'progress' ? ' · a worker is on the way' : ''}', style: muted),
                  if (r.note.isNotEmpty) ...[const SizedBox(height: 4), Text(r.note)],
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _step(context, 'Reported', true),
              _step(context, 'Worker on the way', onWay),
              _step(context, 'Fixed', r.isCleared),
            ]),
            if (r.isCleared) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.green.withAlpha(30), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  if (after != null) ...[
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(after, width: 56, height: 56, fit: BoxFit.cover)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      'Fixed${r.statusTs != null ? ' ${_ago(r.statusTs!)}' : ''} by ${r.doneBy ?? 'a municipal worker'}'
                      '${(r.doneNote ?? '').isNotEmpty ? '\n${r.doneNote}' : ''}',
                      style: TextStyle(color: Colors.green.shade800, fontSize: 13),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share on WhatsApp'),
            ),
          ],
        ),
      ),
    );
  }
}

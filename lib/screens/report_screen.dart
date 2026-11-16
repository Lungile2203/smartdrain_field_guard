import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/report.dart';
import '../services/location_helper.dart';
import '../services/report_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.onSent});
  final VoidCallback onSent;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final service = ReportService.instance;
  final _landmark = TextEditingController();
  final _note = TextEditingController();

  String? _type;
  String _severity = 'medium';
  Position? _pos;
  String _locMsg = 'Getting GPS location…';
  bool _locating = false;
  Uint8List? _photo;
  bool _sending = false;

  static const _types = [
    ('blocked', 'Blocked', Icons.block),
    ('overflowing', 'Overflowing', Icons.water),
    ('damaged', 'Damaged / open', Icons.construction),
    ('other', 'Other', Icons.help_outline),
  ];

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  @override
  void dispose() {
    _landmark.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() {
      _locating = true;
      _locMsg = 'Getting GPS location…';
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setLoc(null, 'Location is turned off. Turn on GPS, or type the street below.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _setLoc(null, 'Location permission denied. Allow it in phone Settings, or type the street below.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: gpsSettings());
      _setLoc(p, null);
    } catch (e) {
      // GPS timed out (e.g. indoors): fall back to the last known fix
      Position? last;
      try {
        last = await lastKnownPosition();
      } catch (_) {}
      _setLoc(last, last == null ? 'Couldn\'t get GPS. Step outside and tap refresh, or type the street below.' : null);
    }
  }

  void _setLoc(Position? p, String? msg) {
    if (!mounted) return;
    setState(() {
      _locating = false;
      _pos = p;
      _locMsg = p != null
          ? '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}  (±${p.accuracy.round()} m)'
          : (msg ?? 'No location');
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      // Small photo (~60 KB) so it sends quickly on weak signal
      final x = await ImagePicker().pickImage(source: source, maxWidth: 640, maxHeight: 640, imageQuality: 60);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _photo = bytes);
    } catch (e) {
      _toast('Couldn\'t open the camera: $e');
    }
  }

  Future<void> _submit() async {
    if (_type == null) {
      _toast('Choose what\'s wrong first');
      return;
    }
    if (_pos == null && _landmark.text.trim().isEmpty) {
      _toast('Add a location: GPS or a street name');
      return;
    }
    setState(() => _sending = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final r = Report(
      id: Report.newId(),
      type: _type!,
      severity: _severity,
      lat: _pos == null ? null : double.parse(_pos!.latitude.toStringAsFixed(6)),
      lng: _pos == null ? null : double.parse(_pos!.longitude.toStringAsFixed(6)),
      acc: _pos?.accuracy.round(),
      landmark: _landmark.text.trim(),
      note: _note.text.trim(),
      photo: _photo == null ? null : 'data:image/jpeg;base64,${base64Encode(_photo!)}',
      reporter: service.reporterLabel,
      ts: now,
      history: [
        {'status': 'reported', 'by': service.reporterLabel, 'ts': now}
      ],
    );
    final sentNow = await service.submit(r);
    if (!mounted) return;
    _toast(sentNow ? 'Thank you! Your report was sent ✓' : 'No signal: saved, it will send automatically');
    setState(() {
      _sending = false;
      _type = null;
      _photo = null;
      _severity = 'medium';
      _landmark.clear();
      _note.clear();
    });
    widget.onSent();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section(context, '1. What\'s wrong?', GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.2,
          children: [
            for (final (key, label, icon) in _types)
              _TypeButton(
                label: label,
                icon: icon,
                selected: _type == key,
                onTap: () => setState(() => _type = key),
              ),
          ],
        )),
        _section(context, '2. Where?', Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(_pos != null ? Icons.gps_fixed : Icons.gps_not_fixed, color: _pos != null ? Colors.green : cs.outline, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_locMsg)),
              IconButton(
                tooltip: 'Refresh location',
                onPressed: _locating ? null : _getLocation,
                icon: _locating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _landmark,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Street or landmark',
                hintText: 'e.g. Corner of Zastron St & Kellner St',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        )),
        _section(context, '3. Photo and details', Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Take photo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ]),
            if (_photo != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_photo!, height: 200, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _severity,
              decoration: const InputDecoration(labelText: 'How serious is it?', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low: it can wait')),
                DropdownMenuItem(value: 'medium', child: Text('Medium: please fix soon')),
                DropdownMenuItem(value: 'high', child: Text('High: flooding road or homes now')),
              ],
              onChanged: (v) => setState(() => _severity = v ?? 'medium'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Anything else? (optional)',
                hintText: 'e.g. Plastic and sand filling the grate, water standing 10 cm',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        )),
        FilledButton.icon(
          onPressed: _sending ? null : _submit,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          icon: const Icon(Icons.send),
          label: const Text('Send report to the municipality', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        ListenableBuilder(
          listenable: service,
          builder: (context, _) => service.queued == 0
              ? const SizedBox(height: 24)
              : Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 24),
                  child: Text('${service.queued} report(s) waiting for signal',
                      textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title, Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

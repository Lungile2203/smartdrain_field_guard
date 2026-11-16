import 'package:flutter/material.dart';

import '../services/report_service.dart';

/// Community "About" screen: optional first name, how it works, privacy.
/// No login: the app connects with the shared community login in config.dart.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final service = ReportService.instance;
  late final _name = TextEditingController(text: service.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _card(BuildContext context, String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(context, 'How it works', const [
          Text('1. You report a drain problem with its location and a photo.'),
          SizedBox(height: 6),
          Text('2. Municipal workers see it on their dashboard and tap “On my way”.'),
          SizedBox(height: 6),
          Text('3. When it’s fixed, your report shows “Fixed”, with the worker’s note and an after photo.'),
        ]),
        _card(context, 'Your name (optional)', [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'First name',
              hintText: 'Leave empty to stay anonymous',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () async {
              FocusScope.of(context).unfocus();
              await service.setName(_name.text);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
            },
            child: const Text('Save'),
          ),
        ]),
        _card(context, 'Your privacy', const [
          Text('No account and no phone number. Your name is optional. Reports only contain the drain’s location, the photo and your notes.'),
        ]),
        ListenableBuilder(
          listenable: service,
          builder: (context, _) => service.lastError.isEmpty
              ? const SizedBox.shrink()
              : Text('Connection problem: ${service.lastError}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/report.dart';

enum ConnState { connecting, online, offline, error }

/// Community app service. Residents never sign in: the app uses the shared,
/// limited community login from config.dart. It sends new reports, keeps
/// every report the residents can see, applies worker status updates from
/// the dashboard, and queues reports made with no signal.
class ReportService extends ChangeNotifier {
  ReportService._();
  static final ReportService instance = ReportService._();

  late SharedPreferences _prefs;
  bool _initialised = false;
  MqttServerClient? _client;
  StreamSubscription? _updatesSub;
  Timer? _retryTimer;

  final Map<String, Report> reports = {};
  final Map<String, Map<String, dynamic>> _statuses = {}; // id -> latest worker status
  final List<Report> _queue = [];
  final Set<String> mine = {}; // ids of reports sent from this phone
  ConnState state = ConnState.connecting;
  String lastError = '';

  /// Called when a worker updates one of MY reports (the app shows a banner)
  void Function(Report r)? onMyReportUpdated;

  // ---------------- optional resident name ----------------
  String get name => _prefs.getString('name') ?? '';
  String get reporterLabel => name.isEmpty ? 'a resident' : '$name (resident)';
  int get queued => _queue.length;
  bool get isOnline => state == ConnState.online;

  Future<void> setName(String value) async {
    await _prefs.setString('name', value.trim());
    notifyListeners();
  }

  Future<void> init() async {
    if (_initialised) return;
    _prefs = await SharedPreferences.getInstance();
    _initialised = true;
    mine.addAll(_prefs.getStringList('mine') ?? <String>[]);
    for (final s in _prefs.getStringList('queue') ?? <String>[]) {
      try {
        final r = Report.fromJson(jsonDecode(s) as Map<String, dynamic>);
        _queue.add(r);
        reports[r.id] = r;
      } catch (_) {}
    }
    // Connect in the background: never let the network hold up opening the app
    unawaited(connect().catchError((Object e) {
      lastError = e.toString();
      state = ConnState.error;
      notifyListeners();
    }));
  }

  // ---------------- connection ----------------
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 10), connect);
  }

  Future<void> connect() async {
    _retryTimer?.cancel();
    await _updatesSub?.cancel();
    _client?.autoReconnect = false;
    _client?.disconnect();

    final clientId = 'sdg-community-${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final c = MqttServerClient.withPort(AppConfig.brokerHost, clientId, AppConfig.brokerPort);
    c.secure = true; // TLS
    c.setProtocolV311();
    c.keepAlivePeriod = 30;
    c.connectTimeoutPeriod = 10000;
    c.autoReconnect = true;
    c.resubscribeOnAutoReconnect = true;
    c.logging(on: false);
    c.onConnected = _onConnected;
    c.onAutoReconnected = _onConnected;
    c.onAutoReconnect = () {
      state = ConnState.connecting;
      notifyListeners();
    };
    c.onDisconnected = () {
      if (state != ConnState.error) state = ConnState.offline;
      notifyListeners();
    };
    c.connectionMessage = MqttConnectMessage().withClientIdentifier(clientId).startClean();
    _client = c;

    state = ConnState.connecting;
    notifyListeners();
    try {
      await c.connect(AppConfig.brokerUser, AppConfig.brokerPassword);
    } catch (e) {
      lastError = e.toString();
      state = ConnState.error;
      c.autoReconnect = false;
      c.disconnect();
      notifyListeners();
      debugPrint('MQTT connect failed: $e');
      _scheduleRetry();
      return;
    }
    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      lastError = 'Server refused: ${c.connectionStatus?.returnCode}';
      state = ConnState.error;
      notifyListeners();
      _scheduleRetry();
      return;
    }
    c.subscribe(AppConfig.reportTopicFilter, MqttQos.atLeastOnce);
    c.subscribe(AppConfig.statusTopicFilter, MqttQos.atLeastOnce);
    _updatesSub = c.updates?.listen(_onMessages);
  }

  void _onConnected() {
    state = ConnState.online;
    lastError = '';
    notifyListeners();
    _flushQueue();
  }

  // Typed loosely on purpose: works whichever way the mqtt_client version types its stream
  void _onMessages(List<MqttReceivedMessage<MqttMessage?>>? msgs) {
    var changed = false;
    for (final m in msgs ?? <MqttReceivedMessage<MqttMessage?>>[]) {
      final pub = m.payload;
      if (pub is! MqttPublishMessage) continue;
      try {
        final json = jsonDecode(utf8.decode(pub.payload.message)) as Map<String, dynamic>;
        final id = json['id']?.toString();
        if (id == null) continue;
        if (m.topic.startsWith('sdg/status/')) {
          final prev = _statuses[id];
          _statuses[id] = json;
          final r = reports[id];
          if (r != null) {
            r.applyStatus(json);
            final fresh = DateTime.now().millisecondsSinceEpoch - ((json['ts'] as num?)?.toInt() ?? 0) < 10 * 60 * 1000;
            if (mine.contains(id) && fresh && prev?['status'] != json['status']) onMyReportUpdated?.call(r);
          }
        } else {
          final r = Report.fromJson(json);
          final st = _statuses[id];
          if (st != null) r.applyStatus(st); // status may arrive before the report
          reports[id] = r;
        }
        changed = true;
      } catch (e) {
        debugPrint('Skipped a message on ${m.topic}: $e');
      }
    }
    if (changed) notifyListeners();
  }

  // ---------------- sending ----------------
  /// Retained: the server keeps the latest copy, so the workers' dashboard
  /// still sees the report even if it was closed when the report was sent.
  void _publish(Report r) {
    final builder = MqttClientPayloadBuilder()..addUTF8String(jsonEncode(r.toJson()));
    _client!.publishMessage('${AppConfig.reportTopicPrefix}${r.id}', MqttQos.atLeastOnce, builder.payload!, retain: true);
  }

  /// Returns true if sent now, false if saved to send later
  Future<bool> submit(Report r) async {
    reports[r.id] = r;
    mine.add(r.id);
    await _prefs.setStringList('mine', mine.toList());
    if (isOnline) {
      _publish(r);
      notifyListeners();
      return true;
    }
    _queue.add(r);
    await _saveQueue();
    notifyListeners();
    return false;
  }

  Future<void> _flushQueue() async {
    if (_queue.isEmpty || !isOnline) return;
    for (final r in List<Report>.from(_queue)) {
      _publish(r);
    }
    _queue.clear();
    await _saveQueue();
    notifyListeners();
  }

  Future<void> _saveQueue() =>
      _prefs.setStringList('queue', _queue.map((r) => jsonEncode(r.toJson())).toList());
}

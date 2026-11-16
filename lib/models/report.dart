import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// One drain problem reported from the field.
/// The JSON shape is identical to worker.html, so the website dashboard,
/// the web app and this Flutter app all understand each other's reports.
class Report {
  final String id;
  final String type; // blocked | overflowing | damaged | other
  final String severity; // low | medium | high
  final double? lat;
  final double? lng;
  final int? acc;
  final String landmark;
  final String note;
  final String? photo; // "data:image/jpeg;base64,..."
  final String reporter;
  final String team;
  final int ts; // milliseconds since 1970
  String status; // reported | progress | cleared
  String? assignee;
  List<Map<String, dynamic>> history;

  // Filled in from the workers' dashboard (topic sdg/status/{id})
  String? doneBy;
  String? doneNote;
  String? donePhoto;
  int? statusTs;

  Report({
    required this.id,
    required this.type,
    required this.severity,
    this.lat,
    this.lng,
    this.acc,
    this.landmark = '',
    this.note = '',
    this.photo,
    required this.reporter,
    this.team = '',
    required this.ts,
    this.status = 'reported',
    this.assignee,
    List<Map<String, dynamic>>? history,
  }) : history = history ?? [];

  static const typeLabels = {
    'blocked': 'Blocked',
    'overflowing': 'Overflowing',
    'damaged': 'Damaged / open',
    'other': 'Other',
  };
  static const statusLabels = {
    'reported': 'Reported',
    'progress': 'Worker on the way',
    'cleared': 'Fixed',
  };

  /// Apply a status message published by a worker on the dashboard
  void applyStatus(Map<String, dynamic> st) {
    status = (st['status'] ?? status).toString();
    doneBy = st['by'] as String?;
    statusTs = _toInt(st['ts']);
    if (status == 'cleared') {
      doneNote = st['note'] as String?;
      donePhoto = st['photo'] as String?;
      _donePhotoBytes = null;
    }
  }

  Uint8List? _donePhotoBytes;
  Uint8List? get donePhotoBytes {
    if (donePhoto == null || donePhoto!.isEmpty) return null;
    if (_donePhotoBytes != null) return _donePhotoBytes;
    try {
      final comma = donePhoto!.indexOf(',');
      _donePhotoBytes = base64Decode(comma >= 0 ? donePhoto!.substring(comma + 1) : donePhoto!);
    } catch (_) {
      return null;
    }
    return _donePhotoBytes;
  }

  String get typeLabel => typeLabels[type] ?? type;
  String get statusLabel => statusLabels[status] ?? status;
  bool get isCleared => status == 'cleared';
  bool get hasLocation => lat != null && lng != null;

  String get title {
    if (landmark.isNotEmpty) return landmark;
    if (hasLocation) return '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}';
    return 'No location';
  }

  /// Same style of ID as the web app, e.g. "RK3J9QX2A"
  static String newId() {
    final r = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final time = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final tail = time.length > 6 ? time.substring(time.length - 6) : time;
    final rand = List.generate(2, (_) => chars[r.nextInt(chars.length)]).join();
    return 'R$tail$rand';
  }

  Uint8List? _photoBytes;

  /// Decoded photo, cached so the list scrolls smoothly
  Uint8List? get photoBytes {
    if (photo == null || photo!.isEmpty) return null;
    if (_photoBytes != null) return _photoBytes;
    try {
      final comma = photo!.indexOf(',');
      _photoBytes = base64Decode(comma >= 0 ? photo!.substring(comma + 1) : photo!);
    } catch (_) {
      return null;
    }
    return _photoBytes;
  }

  static double? _toDouble(dynamic v) => v == null ? null : (v as num).toDouble();
  static int? _toInt(dynamic v) => v == null ? null : (v as num).round();

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: j['id'].toString(),
        type: (j['type'] ?? 'other').toString(),
        severity: (j['severity'] ?? 'medium').toString(),
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        acc: _toInt(j['acc']),
        landmark: (j['landmark'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
        photo: j['photo'] as String?,
        reporter: (j['reporter'] ?? 'Unknown').toString(),
        team: (j['team'] ?? '').toString(),
        ts: _toInt(j['ts']) ?? DateTime.now().millisecondsSinceEpoch,
        status: (j['status'] ?? 'reported').toString(),
        assignee: j['assignee'] as String?,
        history: ((j['history'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'severity': severity,
        'lat': lat,
        'lng': lng,
        'acc': acc,
        'landmark': landmark,
        'note': note,
        'photo': photo,
        'reporter': reporter,
        'team': team,
        'ts': ts,
        'status': status,
        'assignee': assignee,
        'history': history,
      };
}

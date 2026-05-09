// lib/screens/manage_alarm.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';
import '../models/alarm_model.dart';
import '../services/notification_service.dart';

class ManageAlarmsScreen extends StatefulWidget {
  const ManageAlarmsScreen({super.key});

  @override
  State<ManageAlarmsScreen> createState() => _ManageAlarmsScreenState();
}

class _ManageAlarmsScreenState extends State<ManageAlarmsScreen> {
  List<Alarm> _alarms = [];
  bool _loading = true;

  // ── CSV column order (must match import parser) ────────────────────────────
  static const _csvHeader =
      'label,scheduled_at,recurrence,auto_delete,notification_id,hourly_interval';

  @override
  void initState() {
    super.initState();
    _loadAlarms();
  }

  Future<void> _loadAlarms() async {
    setState(() => _loading = true);
    final alarms = await DatabaseHelper.instance.getAllAlarms();
    if (mounted) {
      setState(() {
        _alarms = alarms;
        _loading = false;
      });
    }
  }

  // ── Complete toggle ────────────────────────────────────────────────────────

  Future<void> _onCompleteToggle(Alarm alarm) async {
    final now = DateTime.now();

    if (alarm.recurrence == RecurrenceType.once) {
      if (alarm.autoDelete) {
        await NotificationService.instance.cancelNotification(
          alarm.notificationId,
        );
        await DatabaseHelper.instance.deleteAlarm(alarm.id!);
        _showSnack('"${alarm.label}" completed & deleted');
      } else {
        final updated = alarm.copyWith(isCompleted: true, isCompletedAt: now);
        await DatabaseHelper.instance.updateAlarm(updated);
        await NotificationService.instance.cancelNotification(
          alarm.notificationId,
        );
        _showSnack('"${alarm.label}" marked as done');
      }
    } else {
      if (alarm.autoDelete) {
        await NotificationService.instance.cancelNotification(
          alarm.notificationId,
        );
        await DatabaseHelper.instance.deleteAlarm(alarm.id!);
        _showSnack('"${alarm.label}" completed & deleted');
      } else {
        final alarmForNextSchedule = alarm.copyWith(
          scheduledAt: alarm.nextOccurrence(from: now),
          isCompleted: true,
          isCompletedAt: now,
        );
        await DatabaseHelper.instance.updateAlarm(alarmForNextSchedule);
        await NotificationService.instance.cancelNotification(
          alarm.notificationId,
        );
        await NotificationService.instance.scheduleAlarm(alarmForNextSchedule);
        _showSnack(
          '"${alarm.label}" done — next: ${_formatFull(alarmForNextSchedule.nextOccurrence())}',
        );
      }
    }

    await _loadAlarms();
  }

  // ── Delete alarm ───────────────────────────────────────────────────────────

  Future<void> _deleteAlarm(Alarm alarm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Alarm',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${alarm.label}"? This cannot be undone.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await NotificationService.instance.cancelNotification(
        alarm.notificationId,
      );
      await DatabaseHelper.instance.deleteAlarm(alarm.id!);
      _showSnack('"${alarm.label}" deleted');
      await _loadAlarms();
    }
  }

  // ── EXPORT ────────────────────────────────────────────────────────────────
  //
  // Exports only recurring alarms that are NOT permanently completed.
  // (Once alarms are excluded because they are single-fire and non-transferable.)

  Future<void> _exportAlarms() async {
    final exportable = _alarms.where((a) {
      // Exclude once-type alarms entirely
      if (a.recurrence == RecurrenceType.once) return false;
      // Exclude permanently completed (shouldn't happen for recurring, but guard)
      if (a.isCompleted && a.recurrence == RecurrenceType.once) return false;
      return true;
    }).toList();

    if (exportable.isEmpty) {
      _showSnack('Nothing to export — no active recurring alarms found');
      return;
    }

    // Build CSV
    final buffer = StringBuffer();
    buffer.writeln(_csvHeader);
    for (final a in exportable) {
      // RFC-4180: wrap label in double-quotes, escape internal quotes
      final safeLabel = '"${a.label.replaceAll('"', '""')}"';
      buffer.writeln(
        '$safeLabel,'
        '${a.scheduledAt.toIso8601String()},'
        '${a.recurrence.name},'
        '${a.autoDelete ? 1 : 0},'
        '${a.notificationId},'
        '${a.hourlyInterval}',
      );
    }

    // Write to temp file
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/alarms_export_$ts.csv');
    await file.writeAsString(buffer.toString());

    // Open system share sheet — user can save to Files, send via email, etc.
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Alarm App — exported alarms',
      text: 'Exported ${exportable.length} recurring alarm(s)',
    );
  }

  // ── IMPORT ────────────────────────────────────────────────────────────────
  //
  // Picks a CSV file, parses it, re-assigns notification IDs, inserts into
  // SQLite and schedules notifications for every valid recurring alarm row.

  Future<void> _importAlarms() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) {
      _showSnack('Could not read the selected file');
      return;
    }

    String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      _showSnack('Failed to open the file');
      return;
    }

    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      _showSnack('The file is empty');
      return;
    }

    // Validate header row - check for both old and new format
    final header = lines.first.toLowerCase();
    const oldHeader =
        'label,scheduled_at,recurrence,auto_delete,notification_id';
    final newHeader = _csvHeader.toLowerCase();

    if (header != oldHeader && header != newHeader) {
      _showSnack('Invalid CSV — header does not match expected format');
      return;
    }

    final isOldFormat = header == oldHeader;

    int imported = 0;
    int skipped = 0;

    for (final line in lines.skip(1)) {
      try {
        final cols = _parseCsvLine(line);
        if (cols.length < 5) {
          skipped++;
          continue;
        }

        final label = cols[0];
        final scheduledAt = DateTime.parse(cols[1]);
        final recurrence = RecurrenceType.values.firstWhere(
          (e) => e.name == cols[2],
          orElse: () => RecurrenceType.once,
        );
        final autoDelete = cols[3] == '1';

        // Parse hourly_interval if available (new format), otherwise default to 1
        final hourlyInterval = isOldFormat
            ? 1
            : (cols.length >= 6 ? (int.tryParse(cols[5]) ?? 1) : 1);

        // Safety: never import once-type rows
        if (recurrence == RecurrenceType.once) {
          skipped++;
          continue;
        }
        if (label.isEmpty) {
          skipped++;
          continue;
        }

        // Fresh notification ID so it never collides with existing alarms
        final nextId = (await DatabaseHelper.instance.maxNotificationId()) + 1;

        final alarm = Alarm(
          label: label,
          scheduledAt: scheduledAt,
          recurrence: recurrence,
          autoDelete: autoDelete,
          notificationId: nextId,
          hourlyInterval: hourlyInterval,
        );

        final id = await DatabaseHelper.instance.insertAlarm(alarm);
        await NotificationService.instance.scheduleAlarm(
          alarm.copyWith(id: id),
        );
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    await _loadAlarms();

    _showSnack(
      imported > 0
          ? 'Imported $imported alarm(s)'
                '${skipped > 0 ? ', skipped $skipped invalid row(s)' : ''}'
          : 'No alarms imported'
                '${skipped > 0 ? ' — $skipped invalid row(s) skipped' : ''}',
    );
  }

  // ── CSV parser (RFC-4180 compliant quoted fields) ──────────────────────────

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final current = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped double-quote inside quoted field
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString());
    return result;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF2A2A2A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatFull(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}  $hour:$min';
  }

  String _nextLabel(Alarm alarm) {
    if (alarm.recurrence == RecurrenceType.once) {
      return alarm.isCompleted
          ? 'Completed'
          : 'Fires: ${_formatFull(alarm.scheduledAt)}';
    }
    return 'Next: ${_formatFull(alarm.nextOccurrence())}';
  }

  Color _recurrenceColor(RecurrenceType r) {
    switch (r) {
      case RecurrenceType.once:
        return Colors.grey;
      case RecurrenceType.hourly:
        return Colors.tealAccent;
      case RecurrenceType.daily:
        return Colors.blueAccent;
      case RecurrenceType.weekly:
        return Colors.purpleAccent;
      case RecurrenceType.monthly:
        return Colors.orangeAccent;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Manage Alarms',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          // ── Import ────────────────────────────────────────────────
          IconButton(
            icon: const Icon(LucideIcons.upload, size: 20),
            tooltip: 'Import from CSV',
            onPressed: _importAlarms,
          ),
          // ── Export ────────────────────────────────────────────────
          IconButton(
            icon: const Icon(LucideIcons.download, size: 20),
            tooltip: 'Export to CSV',
            onPressed: _exportAlarms,
          ),
          // ── Refresh ───────────────────────────────────────────────
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadAlarms,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _alarms.isEmpty
          ? _EmptyState()
          : RefreshIndicator(
              onRefresh: _loadAlarms,
              color: Colors.white,
              backgroundColor: const Color(0xFF1A1A1A),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _alarms.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _AlarmCard(
                  alarm: _alarms[index],
                  onComplete: () => _onCompleteToggle(_alarms[index]),
                  onDelete: () => _deleteAlarm(_alarms[index]),
                  nextLabel: _nextLabel(_alarms[index]),
                  recurrenceColor: _recurrenceColor(_alarms[index].recurrence),
                ),
              ),
            ),
    );
  }
}

// ── Alarm card ────────────────────────────────────────────────────────────────

class _AlarmCard extends StatelessWidget {
  final Alarm alarm;
  final VoidCallback onComplete;
  final VoidCallback onDelete;
  final String nextLabel;
  final Color recurrenceColor;

  const _AlarmCard({
    required this.alarm,
    required this.onComplete,
    required this.onDelete,
    required this.nextLabel,
    required this.recurrenceColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool done =
        alarm.isCompleted && alarm.recurrence == RecurrenceType.once;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done ? Colors.grey[850]! : const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: recurrenceColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: recurrenceColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  alarm.recurrenceLabel,
                  style: TextStyle(
                    color: recurrenceColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (alarm.autoDelete) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Text(
                    'Auto-delete',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: onDelete,
                child: Icon(
                  LucideIcons.trash2,
                  size: 16,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Label ───────────────────────────────────────────────────
          Text(
            alarm.label,
            style: TextStyle(
              color: done ? Colors.grey[600] : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: Colors.grey[600],
            ),
          ),

          const SizedBox(height: 4),

          Text(
            nextLabel,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),

          if (alarm.isCompletedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Last completed: ${_fmt(alarm.isCompletedAt!)}',
              style: TextStyle(color: Colors.grey[700], fontSize: 11),
            ),
          ],

          const SizedBox(height: 12),

          // ── is_completed toggle ─────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    done ? LucideIcons.checkCircle2 : LucideIcons.circle,
                    size: 16,
                    color: done ? Colors.green[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    done ? 'Completed' : 'Mark as completed',
                    style: TextStyle(
                      color: done ? Colors.green[400] : Colors.grey[400],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (!done)
                GestureDetector(
                  onTap: onComplete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Complete',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}  $h:$m';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.bellOff, size: 52, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text(
            'No alarms yet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create one from the home screen',
            style: TextStyle(color: Colors.grey[800], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

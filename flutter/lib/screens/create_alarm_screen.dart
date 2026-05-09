// lib/screens/create_alarm_screen.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../db/database_helper.dart';
import '../models/alarm_model.dart';
import '../services/notification_service.dart';

class CreateAlarmScreen extends StatefulWidget {
  const CreateAlarmScreen({super.key});

  @override
  State<CreateAlarmScreen> createState() => _CreateAlarmScreenState();
}

class _CreateAlarmScreenState extends State<CreateAlarmScreen> {
  // ── Form state ─────────────────────────────────────────────────────────────
  final _labelController = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(minutes: 5));
  TimeOfDay _selectedTime = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(minutes: 5)),
  );
  RecurrenceType _recurrence = RecurrenceType.once;
  bool _autoDelete = false;
  bool _isSaving = false;
  int _hourlyInterval = 1; // Custom hours for hourly recurrence
  final _hourIntervalController = TextEditingController(text: '1');

  @override
  void dispose() {
    _labelController.dispose();
    _hourIntervalController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  DateTime get _scheduledDateTime => DateTime(
    _selectedDate.year,
    _selectedDate.month,
    _selectedDate.day,
    _selectedTime.hour,
    _selectedTime.minute,
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: _darkPickerTheme,
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: _darkPickerTheme,
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Widget _darkPickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white,
        ),
      ),
      child: child!,
    );
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Label is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final scheduled = _scheduledDateTime;
    if (_recurrence == RecurrenceType.once &&
        scheduled.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please pick a future date & time'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final nextId = (await DatabaseHelper.instance.maxNotificationId()) + 1;

      final alarm = Alarm(
        label: label,
        scheduledAt: scheduled,
        recurrence: _recurrence,
        autoDelete: _autoDelete,
        notificationId: nextId,
        hourlyInterval: _recurrence == RecurrenceType.hourly
            ? _hourlyInterval
            : 1,
      );

      final id = await DatabaseHelper.instance.insertAlarm(alarm);
      final savedAlarm = alarm.copyWith(id: id);

      await NotificationService.instance.scheduleAlarm(savedAlarm);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alarm "${savedAlarm.label}" saved!'),
            backgroundColor: Colors.green[700],
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving alarm: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
          'Create New Alarm',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          // ── Label ──────────────────────────────────────────────────────
          const _SectionLabel(label: 'Label', icon: LucideIcons.tag),
          const SizedBox(height: 8),
          TextField(
            controller: _labelController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g. Take medicine',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white54, width: 1),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Date ───────────────────────────────────────────────────────
          const _SectionLabel(label: 'Date', icon: LucideIcons.calendar),
          const SizedBox(height: 8),
          _PickerTile(
            icon: LucideIcons.calendar,
            label: _formatDate(_selectedDate),
            onTap: _pickDate,
          ),

          const SizedBox(height: 16),

          // ── Time ───────────────────────────────────────────────────────
          const _SectionLabel(label: 'Time', icon: LucideIcons.clock),
          const SizedBox(height: 8),
          _PickerTile(
            icon: LucideIcons.clock,
            label: _selectedTime.format(context),
            onTap: _pickTime,
          ),

          const SizedBox(height: 28),

          // ── Recurrence ─────────────────────────────────────────────────
          const _SectionLabel(label: 'Repeat', icon: LucideIcons.repeat),
          const SizedBox(height: 12),
          _RecurrencePicker(
            current: _recurrence,
            onChanged: (r) => setState(() {
              _recurrence = r;
              // Reset hourly interval when switching to hourly
              if (r == RecurrenceType.hourly && _hourlyInterval == 24) {
                _hourlyInterval = 1;
                _hourIntervalController.text = '1';
              }
            }),
          ),

          // ── Hour Interval Selector (only for hourly) ────────────────
          if (_recurrence == RecurrenceType.hourly) ...[
            const SizedBox(height: 16),
            const _SectionLabel(
              label: 'Every X Hours',
              icon: LucideIcons.clock4,
            ),
            const SizedBox(height: 8),
            _HourIntervalSelector(
              interval: _hourlyInterval,
              onChanged: (value) {
                setState(() {
                  if (value >= 24) {
                    // Switch to daily if 24 hours selected
                    _recurrence = RecurrenceType.daily;
                    _hourlyInterval = 24;
                  } else {
                    _hourlyInterval = value;
                  }
                });
              },
            ),
          ],

          const SizedBox(height: 28),

          // ── Options ────────────────────────────────────────────────────
          const _SectionLabel(label: 'Options', icon: LucideIcons.settings2),
          const SizedBox(height: 8),
          _ToggleTile(
            icon: LucideIcons.trash2,
            label: 'Auto-delete after it goes off',
            subtitle: 'Alarm will be deleted once marked as completed',
            value: _autoDelete,
            onChanged: (v) => setState(() => _autoDelete = v),
          ),

          const SizedBox(height: 40),

          // ── Save button ────────────────────────────────────────────────
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(LucideIcons.save, size: 20),
              label: Text(
                _isSaving ? 'Saving…' : 'Save Alarm',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ── Hour Interval Selector ────────────────────────────────────────────────────

class _HourIntervalSelector extends StatelessWidget {
  final int interval;
  final ValueChanged<int> onChanged;

  const _HourIntervalSelector({
    required this.interval,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$interval ${interval == 1 ? 'hour' : 'hours'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: interval == 24
                      ? Colors.orangeAccent.withValues(alpha: 0.1)
                      : Colors.tealAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: interval == 24
                        ? Colors.orangeAccent.withValues(alpha: 0.3)
                        : Colors.tealAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  interval == 24 ? 'Switching to Daily' : 'Custom',
                  style: TextStyle(
                    color: interval == 24
                        ? Colors.orangeAccent
                        : Colors.tealAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.grey[800],
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            ),
            child: Slider(
              value: interval.toDouble(),
              min: 1,
              max: 24,
              divisions: 23,
              label: '$interval ${interval == 1 ? 'hour' : 'hours'}',
              onChanged: (value) => onChanged(value.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '1h',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                '6h',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                '12h',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                '18h',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                '24h→Daily',
                style: TextStyle(color: Colors.orangeAccent[200], fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            interval == 24
                ? '24 hours will switch to Every Day recurrence'
                : 'Alarm will repeat every $interval ${interval == 1 ? 'hour' : 'hours'}',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recurrence picker ─────────────────────────────────────────────────────────

class _RecurrencePicker extends StatelessWidget {
  final RecurrenceType current;
  final ValueChanged<RecurrenceType> onChanged;

  const _RecurrencePicker({required this.current, required this.onChanged});

  static const _options = [
    (RecurrenceType.once, LucideIcons.alarmCheck, 'Once'),
    (RecurrenceType.hourly, LucideIcons.clock4, 'Every Hour'),
    (RecurrenceType.daily, LucideIcons.sun, 'Every Day'),
    (RecurrenceType.weekly, LucideIcons.calendarDays, 'Every Week'),
    (RecurrenceType.monthly, LucideIcons.calendarRange, 'Every Month'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _options.map((opt) {
        final (type, icon, label) = opt;
        final selected = current == type;
        return GestureDetector(
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: selected ? Colors.white : Colors.grey[800]!,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.black : Colors.grey[400],
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.grey[400],
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[400]),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(LucideIcons.chevronRight, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.grey[700],
            inactiveThumbColor: Colors.grey[600],
            inactiveTrackColor: Colors.grey[900],
          ),
        ],
      ),
    );
  }
}

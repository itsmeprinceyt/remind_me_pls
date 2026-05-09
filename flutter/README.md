# Alarm App — Setup Guide

A Flutter-based alarm/reminder application that allows users to set recurring alarms with labels, date/time picking, and various recurrence options (Once, Hourly, Daily, Weekly, Monthly). Features include auto-delete on completion, persistent storage via SQLite, reliable notifications using flutter_local_notifications, and proper handling of device reboots and timezones.

## Project Structure

```
lib/
├── main.dart                         ← App entry, notification routing
├── models/
│   └── alarm_model.dart              ← Alarm data model + recurrence logic
├── db/
│   └── database_helper.dart          ← SQLite CRUD via sqflite
├── services/
│   └── notification_service.dart     ← flutter_local_notifications wrapper
└── screens/
    ├── home_screen.dart              ← Landing page (Create / Manage buttons)
    ├── create_alarm_screen.dart      ← Form: label, date, time, recurrence, options
    └── manage_alarms_screen.dart     ← List of alarms, complete & delete actions
```

---

## 1. Install dependencies

```bash
flutter pub get
```

---

## 2. Android setup

Replace the contents of `android/app/src/main/AndroidManifest.xml` with the
file provided as `android_AndroidManifest.xml` in this zip.

The key additions are:

- `POST_NOTIFICATIONS` — show notifications on Android 13+
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` — schedule exact alarms on Android 12+
- `RECEIVE_BOOT_COMPLETED` — reschedule after reboot
- `WAKE_LOCK` — fire alarms in Doze mode
- The three `flutter_local_notifications` receivers

---

## 3. iOS setup

In `ios/Runner/Info.plist`, add:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

No additional entitlements are needed for local notifications on iOS.

---

## 4. Timezone (required)

`flutter_local_notifications` uses the `timezone` package for exact scheduling.
No extra configuration is needed — `tz.initializeTimeZones()` is already called
in `NotificationService.init()`.

---

## 5. Run

```bash
flutter run
```

---

## How it works

### Creating an alarm

1. Fill in the **label** (mandatory), pick a **date** and **time**.
2. Choose a **recurrence** type: Once / Every Hour / Every Day / Every Week / Every Month.
3. Optionally enable **Auto-delete** — when you mark the alarm as complete, it will
   be permanently deleted (for recurring alarms, this stops all future occurrences).
4. Tap **Save Alarm** — the alarm is stored in SQLite and a local notification
   is scheduled via `flutter_local_notifications`.

### Completing an alarm

Open **Manage Alarms** and tap the **Complete** button on any alarm card.

| Recurrence    | Auto-delete OFF                                       | Auto-delete ON   |
| ------------- | ----------------------------------------------------- | ---------------- |
| **Once**      | Marked as completed, notification cancelled           | Deleted entirely |
| **Recurring** | `is_completed_at` recorded, next occurrence scheduled | Deleted entirely |

### Tapping a notification

Tapping any alarm notification opens the app directly to the **Manage Alarms**
screen so you can mark it as complete.

---

## Dependencies

| Package                       | Version  | Purpose                                |
| ----------------------------- | -------- | -------------------------------------- |
| `flutter_local_notifications` | ^17.2.2  | Schedule & fire notifications          |
| `sqflite`                     | ^2.3.3+1 | Local SQLite storage                   |
| `path`                        | ^1.9.0   | Database path helper                   |
| `lucide_icons`                | ^0.0.3   | Icons throughout the app               |
| `timezone`                    | ^0.9.4   | Exact scheduling with timezone support |
| `permission_handler`          | ^11.3.1  | Runtime notification permissions       |

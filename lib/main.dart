import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:liquid_progress_indicator_v2/liquid_progress_indicator.dart';
import 'package:pomodoro2/util/confet_edit.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('tasks');
  await Hive.openBox('stats');
  await Hive.openBox('analytics');
  await Hive.openBox('focus');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PomodoroApp());
}

class PomodoroApp extends StatefulWidget {
  const PomodoroApp({Key? key}) : super(key: key);

  @override
  State<PomodoroApp> createState() => _PomodoroAppState();
}

class _PomodoroAppState extends State<PomodoroApp> {
  bool _isDark = true;

  void toggleTheme() => setState(() => _isDark = !_isDark);

  @override
  void initState() {
    super.initState();
    _isDark = Hive.box('settings').get('isDark', defaultValue: true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pomodoro Pro',
      debugShowCheckedModeBanner: false,
      theme: _isDark ? _darkTheme : _lightTheme,
      home: PomodoroHome(isDark: _isDark, onThemeToggle: toggleTheme),
    );
  }

  ThemeData get _darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0F043A),
    useMaterial3: true,
  );

  ThemeData get _lightTheme => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    useMaterial3: true,
  );
}

// ==================== MODELS ====================
class Task {
  String id, title;
  List<SubTask> subTasks;
  bool isCompleted;
  int pomodorosCompleted, priority;
  DateTime createdAt;
  String? category;

  Task({
    required this.id,
    required this.title,
    List<SubTask>? subTasks,
    this.isCompleted = false,
    this.pomodorosCompleted = 0,
    required this.createdAt,
    this.category,
    this.priority = 0,
  }) : subTasks = subTasks ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subTasks': subTasks.map((s) => s.toJson()).toList(),
    'isCompleted': isCompleted,
    'pomodorosCompleted': pomodorosCompleted,
    'createdAt': createdAt.toIso8601String(),
    'category': category,
    'priority': priority,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    subTasks:
        (json['subTasks'] as List?)
            ?.map((s) => SubTask.fromJson(Map<String, dynamic>.from(s)))
            .toList() ??
        [],
    isCompleted: json['isCompleted'] ?? false,
    pomodorosCompleted: json['pomodorosCompleted'] ?? 0,
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    category: json['category'],
    priority: json['priority'] ?? 0,
  );
}

class SubTask {
  String id, title;
  bool isCompleted;
  int duration;

  SubTask({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.duration = 25,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isCompleted': isCompleted,
    'duration': duration,
  };

  factory SubTask.fromJson(Map<String, dynamic> json) => SubTask(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    isCompleted: json['isCompleted'] ?? false,
    duration: json['duration'] ?? 25,
  );
}

class FocusSession {
  DateTime date;
  int hour;
  int minutes;
  int pomodoros;
  bool isDeepWork;

  FocusSession({
    required this.date,
    required this.hour,
    required this.minutes,
    required this.pomodoros,
    this.isDeepWork = false,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'hour': hour,
    'minutes': minutes,
    'pomodoros': pomodoros,
    'isDeepWork': isDeepWork,
  };

  factory FocusSession.fromJson(Map<String, dynamic> json) => FocusSession(
    date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
    hour: json['hour'] ?? 0,
    minutes: json['minutes'] ?? 0,
    pomodoros: json['pomodoros'] ?? 0,
    isDeepWork: json['isDeepWork'] ?? false,
  );
}

class DailyGoal {
  int targetPomodoros;
  int targetMinutes;
  int completedPomodoros;
  int completedMinutes;
  DateTime date;

  DailyGoal({
    this.targetPomodoros = 8,
    this.targetMinutes = 200,
    this.completedPomodoros = 0,
    this.completedMinutes = 0,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'targetPomodoros': targetPomodoros,
    'targetMinutes': targetMinutes,
    'completedPomodoros': completedPomodoros,
    'completedMinutes': completedMinutes,
    'date': date.toIso8601String(),
  };

  factory DailyGoal.fromJson(Map<String, dynamic> json) => DailyGoal(
    targetPomodoros: json['targetPomodoros'] ?? 8,
    targetMinutes: json['targetMinutes'] ?? 200,
    completedPomodoros: json['completedPomodoros'] ?? 0,
    completedMinutes: json['completedMinutes'] ?? 0,
    date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
  );

  double get pomodoroProgress => targetPomodoros > 0
      ? (completedPomodoros / targetPomodoros).clamp(0.0, 1.0)
      : 0.0;

  double get minutesProgress => targetMinutes > 0
      ? (completedMinutes / targetMinutes).clamp(0.0, 1.0)
      : 0.0;
}

// ==================== MAIN HOME ====================
class PomodoroHome extends StatefulWidget {
  final bool isDark;
  final VoidCallback onThemeToggle;

  const PomodoroHome({
    Key? key,
    required this.isDark,
    required this.onThemeToggle,
  }) : super(key: key);

  @override
  State<PomodoroHome> createState() => _PomodoroHomeState();
}

class _PomodoroHomeState extends State<PomodoroHome>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer bgAudioPlayer = AudioPlayer();
  late ConfettiController _confettiController;
  late Box settingsBox, tasksBox, statsBox, analyticsBox, focusBox;

  List<Task> tasks = [];
  Task? currentTask;
  SubTask? currentSubTask;

  int workDuration = 25 * 60,
      shortBreakDuration = 5 * 60,
      longBreakDuration = 15 * 60;
  int currentSeconds = 25 * 60,
      totalPomodoros = 0,
      todayPomodoros = 0,
      totalFocusTime = 0;
  List<int> weeklyPomodoros = [0, 0, 0, 0, 0, 0, 0];

  Timer? timer;
  bool isRunning = false, isBreak = false, isFullscreenMode = false;
  int pomodoroCount = 0, currentPage = 0;

  bool autoStartBreak = false,
      autoStartPomodoro = false,
      enableNotifications = true,
      enableVibration = true,
      keepScreenOn = false;

  // Sound settings
  bool soundEnabled = true;
  int selectedSoundIndex = 0;
  final List<String> soundFiles = [
    'rain.mp3',
    'night.mp3',
    'ocean.mp3',
    'fire.mp3',
    'job.mp3',
    'birds.mp3',
    'piano.mp3',
    'motiv.mp3',
  ];
  final List<String> soundNames = [
    'Rain',
    'Night Drive',
    'Ocean',
    'Fire',
    'Job',
    'Birds',
    'Piano',
    'Motiv',
  ];

  String selectedCategory = 'All';
  List<String> categories = ['All', 'Work', 'Study', 'Personal', 'Other'];

  // ========== FOCUS MODE ==========
  bool focusModeEnabled = true;
  int focusStreak = 0;
  int deepWorkSessions = 0;
  DateTime? lastFocusDate;
  DailyGoal? todayGoal;
  int weeklyGoalPomodoros = 40;
  int weeklyCompletedPomodoros = 0;

  // ========== ANALYTICS ==========
  List<FocusSession> focusSessions = [];
  Map<String, int> heatmapData = {};
  List<int> hourlyProductivity = List.filled(24, 0);
  int totalTasksCompleted = 0;
  double avgFocusTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    settingsBox = Hive.box('settings');
    tasksBox = Hive.box('tasks');
    statsBox = Hive.box('stats');
    analyticsBox = Hive.box('analytics');
    focusBox = Hive.box('focus');
    _initNotifications();
    _loadData();
    _loadAnalytics();
    _loadFocusData();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    bgAudioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isRunning && focusModeEnabled && state == AppLifecycleState.paused) {
      _showFocusWarning();
    }
  }

  void _showFocusWarning() {
    notifications.show(
      1,
      '🎯 Stay Focused!',
      'Come back to your Pomodoro session!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'focus_channel',
          'Focus Notifications',
          importance: Importance.max,
          priority: Priority.max,
          ongoing: true,
        ),
      ),
    );
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(
      const InitializationSettings(android: android),
    );
  }

  void _loadData() {
    setState(() {
      workDuration = settingsBox.get('workDuration', defaultValue: 25 * 60);
      shortBreakDuration = settingsBox.get(
        'shortBreakDuration',
        defaultValue: 5 * 60,
      );
      longBreakDuration = settingsBox.get(
        'longBreakDuration',
        defaultValue: 15 * 60,
      );
      autoStartBreak = settingsBox.get('autoStartBreak', defaultValue: false);
      autoStartPomodoro = settingsBox.get(
        'autoStartPomodoro',
        defaultValue: false,
      );
      enableNotifications = settingsBox.get(
        'enableNotifications',
        defaultValue: true,
      );
      enableVibration = settingsBox.get('enableVibration', defaultValue: true);
      keepScreenOn = settingsBox.get('keepScreenOn', defaultValue: false);
      soundEnabled = settingsBox.get('soundEnabled', defaultValue: true);
      selectedSoundIndex = settingsBox.get(
        'selectedSoundIndex',
        defaultValue: 0,
      );
      focusModeEnabled = settingsBox.get(
        'focusModeEnabled',
        defaultValue: true,
      );
      totalPomodoros = statsBox.get('totalPomodoros', defaultValue: 0);
      todayPomodoros = statsBox.get('todayPomodoros', defaultValue: 0);
      totalFocusTime = statsBox.get('totalFocusTime', defaultValue: 0);
      pomodoroCount = statsBox.get('pomodoroCount', defaultValue: 0);

      final weeklyData = statsBox.get('weeklyPomodoros');
      if (weeklyData != null && weeklyData is List) {
        weeklyPomodoros = List<int>.from(weeklyData);
      }

      final tasksData = tasksBox.get('tasksList');
      if (tasksData != null && tasksData is List) {
        tasks = tasksData
            .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      currentSeconds = workDuration;
    });
  }

  void _loadFocusData() {
    setState(() {
      focusStreak = focusBox.get('focusStreak', defaultValue: 0);
      deepWorkSessions = focusBox.get('deepWorkSessions', defaultValue: 0);
      weeklyGoalPomodoros = focusBox.get(
        'weeklyGoalPomodoros',
        defaultValue: 40,
      );
      weeklyCompletedPomodoros = focusBox.get(
        'weeklyCompletedPomodoros',
        defaultValue: 0,
      );

      final lastDate = focusBox.get('lastFocusDate');
      if (lastDate != null) lastFocusDate = DateTime.tryParse(lastDate);

      final goalData = focusBox.get('todayGoal');
      if (goalData != null) {
        todayGoal = DailyGoal.fromJson(Map<String, dynamic>.from(goalData));
        if (!_isSameDay(todayGoal!.date, DateTime.now())) {
          todayGoal = DailyGoal(date: DateTime.now());
        }
      } else {
        todayGoal = DailyGoal(date: DateTime.now());
      }

      _checkAndUpdateStreak();
    });
  }

  void _loadAnalytics() {
    final sessionsData = analyticsBox.get('focusSessions');
    if (sessionsData != null && sessionsData is List) {
      focusSessions = sessionsData
          .map((e) => FocusSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final heatmap = analyticsBox.get('heatmapData');
    if (heatmap != null && heatmap is Map) {
      heatmapData = Map<String, int>.from(heatmap);
    }

    final hourly = analyticsBox.get('hourlyProductivity');
    if (hourly != null && hourly is List) {
      hourlyProductivity = List<int>.from(hourly);
    }

    totalTasksCompleted = analyticsBox.get(
      'totalTasksCompleted',
      defaultValue: 0,
    );
    avgFocusTime = analyticsBox.get('avgFocusTime', defaultValue: 0.0);
  }

  void _checkAndUpdateStreak() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (lastFocusDate != null) {
      final lastDate = DateTime(
        lastFocusDate!.year,
        lastFocusDate!.month,
        lastFocusDate!.day,
      );
      final diff = today.difference(lastDate).inDays;

      if (diff > 1) {
        focusStreak = 0;
        _saveFocusData();
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _saveTasks() async =>
      await tasksBox.put('tasksList', tasks.map((t) => t.toJson()).toList());

  Future<void> _saveSettings() async {
    await settingsBox.put('workDuration', workDuration);
    await settingsBox.put('shortBreakDuration', shortBreakDuration);
    await settingsBox.put('longBreakDuration', longBreakDuration);
    await settingsBox.put('autoStartBreak', autoStartBreak);
    await settingsBox.put('autoStartPomodoro', autoStartPomodoro);
    await settingsBox.put('enableNotifications', enableNotifications);
    await settingsBox.put('enableVibration', enableVibration);
    await settingsBox.put('keepScreenOn', keepScreenOn);
    await settingsBox.put('isDark', widget.isDark);
    await settingsBox.put('soundEnabled', soundEnabled);
    await settingsBox.put('selectedSoundIndex', selectedSoundIndex);
    await settingsBox.put('focusModeEnabled', focusModeEnabled);
  }

  Future<void> _saveStats() async {
    await statsBox.put('totalPomodoros', totalPomodoros);
    await statsBox.put('todayPomodoros', todayPomodoros);
    await statsBox.put('totalFocusTime', totalFocusTime);
    await statsBox.put('weeklyPomodoros', weeklyPomodoros);
    await statsBox.put('pomodoroCount', pomodoroCount);
  }

  Future<void> _saveFocusData() async {
    await focusBox.put('focusStreak', focusStreak);
    await focusBox.put('deepWorkSessions', deepWorkSessions);
    await focusBox.put('lastFocusDate', lastFocusDate?.toIso8601String());
    await focusBox.put('todayGoal', todayGoal?.toJson());
    await focusBox.put('weeklyGoalPomodoros', weeklyGoalPomodoros);
    await focusBox.put('weeklyCompletedPomodoros', weeklyCompletedPomodoros);
  }

  Future<void> _saveAnalytics() async {
    await analyticsBox.put(
      'focusSessions',
      focusSessions.map((s) => s.toJson()).toList(),
    );
    await analyticsBox.put('heatmapData', heatmapData);
    await analyticsBox.put('hourlyProductivity', hourlyProductivity);
    await analyticsBox.put('totalTasksCompleted', totalTasksCompleted);
    await analyticsBox.put('avgFocusTime', avgFocusTime);
  }

  void _startTimer() async {
    if (keepScreenOn) WakelockPlus.enable();
    if (soundEnabled) _playBgSound();

    setState(() => isRunning = true);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (currentSeconds > 0) {
        setState(() => currentSeconds--);
      } else {
        _completeSession();
      }
    });
  }

  void _playBgSound() async {
    try {
      await bgAudioPlayer.play(
        AssetSource('sounds/${soundFiles[selectedSoundIndex]}'),
      );
    } catch (e) {
      debugPrint("Sound error: $e");
    }
  }

  void _stopBgSound() async => await bgAudioPlayer.stop();

  void _pauseTimer() async {
    timer?.cancel();
    _stopBgSound();
    if (keepScreenOn) WakelockPlus.disable();

    setState(() => isRunning = false);
  }

  void _resetTimer() {
    timer?.cancel();
    _stopBgSound();
    if (keepScreenOn) WakelockPlus.disable();
    setState(() {
      isRunning = false;
      currentSeconds = isBreak
          ? (pomodoroCount % 4 == 0 ? longBreakDuration : shortBreakDuration)
          : workDuration;
    });
  }

  Future<void> _completeSession() async {
    timer?.cancel();
    _stopBgSound();
    if (keepScreenOn) WakelockPlus.disable();

    if (!isBreak) _confettiController.play();

    if (enableVibration) {
      final hv = await Vibration.hasVibrator() ?? false;
      if (hv) Vibration.vibrate(duration: 1000, pattern: [0, 200, 100, 200]);
    }

    if (enableNotifications) {
      await notifications.show(
        0,
        isBreak ? 'Break Complete!' : 'Pomodoro Complete!',
        isBreak ? 'Time to focus again' : 'Time for a break',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'pomodoro_channel',
            'Pomodoro Notifications',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }

    if (!isBreak) {
      final now = DateTime.now();
      pomodoroCount++;
      totalPomodoros++;
      todayPomodoros++;
      totalFocusTime += workDuration;
      weeklyPomodoros[now.weekday - 1]++;
      weeklyCompletedPomodoros++;

      // Update daily goal
      todayGoal!.completedPomodoros++;
      todayGoal!.completedMinutes += workDuration ~/ 60;

      // Update streak
      if (lastFocusDate == null || !_isSameDay(lastFocusDate!, now)) {
        if (lastFocusDate != null) {
          final diff = DateTime(now.year, now.month, now.day)
              .difference(
                DateTime(
                  lastFocusDate!.year,
                  lastFocusDate!.month,
                  lastFocusDate!.day,
                ),
              )
              .inDays;
          if (diff == 1)
            focusStreak++;
          else if (diff > 1)
            focusStreak = 1;
        } else {
          focusStreak = 1;
        }
      }
      lastFocusDate = now;

      // Deep work check (4+ consecutive pomodoros)
      if (pomodoroCount > 0 && pomodoroCount % 4 == 0) {
        deepWorkSessions++;
      }

      // Analytics
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      heatmapData[dateKey] = (heatmapData[dateKey] ?? 0) + 1;
      hourlyProductivity[now.hour]++;

      focusSessions.add(
        FocusSession(
          date: now,
          hour: now.hour,
          minutes: workDuration ~/ 60,
          pomodoros: 1,
          isDeepWork: pomodoroCount % 4 == 0,
        ),
      );

      // Update average focus time
      final totalSessions = focusSessions.length;
      avgFocusTime = totalFocusTime / 60 / max(1, totalSessions);

      if (currentTask != null) {
        currentTask!.pomodorosCompleted++;
        if (currentSubTask != null) currentSubTask!.isCompleted = true;
      }

      await _saveStats();
      await _saveTasks();
      await _saveFocusData();
      await _saveAnalytics();
    }

    setState(() {
      isBreak = !isBreak;
      currentSeconds = isBreak
          ? (pomodoroCount % 4 == 0 ? longBreakDuration : shortBreakDuration)
          : workDuration;
      isRunning = false;
    });

    if ((isBreak && autoStartBreak) || (!isBreak && autoStartPomodoro)) {
      await Future.delayed(const Duration(seconds: 1));
      _startTimer();
    }
  }

  void _skipSession() {
    _resetTimer();
    setState(() {
      isBreak = !isBreak;
      currentSeconds = isBreak
          ? (pomodoroCount % 4 == 0 ? longBreakDuration : shortBreakDuration)
          : workDuration;
    });
  }

  void _startSubTask(Task task, SubTask sub) {
    setState(() {
      currentTask = task;
      currentSubTask = sub;
      currentSeconds = sub.duration * 60;
      isBreak = false;
      currentPage = 0;
    });
  }

  void _startTask(Task task) {
    setState(() {
      currentTask = task;
      currentSubTask = null;
      currentSeconds = workDuration;
      isBreak = false;
      currentPage = 0;
    });
  }

  int getProductivityScore() {
    if (todayGoal == null) return 0;
    double pomScore = todayGoal!.pomodoroProgress * 40;
    double timeScore = todayGoal!.minutesProgress * 30;
    double streakScore = min(focusStreak, 7) / 7 * 20;
    double deepScore = min(deepWorkSessions, 5) / 5 * 10;
    return (pomScore + timeScore + streakScore + deepScore).round().clamp(
      0,
      100,
    );
  }

  double getTaskCompletionRate() {
    if (tasks.isEmpty) return 0;
    return tasks.where((t) => t.isCompleted).length / tasks.length;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    _confettiController.dispose();
    bgAudioPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Color get _bgStart =>
      widget.isDark ? const Color(0xFF0F043A) : const Color(0xFFE8E8FF);

  Color get _bgMid =>
      widget.isDark ? const Color(0xFF1A0B5E) : const Color(0xFFD0D0FF);

  Color get _textColor => widget.isDark ? Colors.white : Colors.black87;

  Color get _textSecondary => widget.isDark ? Colors.white70 : Colors.black54;

  Color get _cardBg => widget.isDark
      ? Colors.white.withOpacity(0.1)
      : Colors.white.withOpacity(0.8);

  Color get _borderColor => widget.isDark
      ? Colors.white.withOpacity(0.2)
      : Colors.black.withOpacity(0.1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_bgStart, _bgMid, _bgStart],
              ),
            ),
          ),
          SafeArea(
            child: IndexedStack(
              index: currentPage,
              children: [
                _buildTimerPage(),
                _buildTasksPage(),
                _buildAnalyticsPage(),
                _buildSettingsPage(),
              ],
            ),
          ),
          if (!isFullscreenMode)
            Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomNav()),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.1,
              numberOfParticles: 40,
              maxBlastForce: 150,
              minBlastForce: 80,
              gravity: 0.1,
              colors: const [
                Colors.red,
                Colors.yellow,
                Colors.orange,
                Colors.pink,
                Colors.blue,
                Colors.purple,
              ],
              createParticlePath: createMixedParticles,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TIMER PAGE ====================
  Widget _buildTimerPage() {
    if (isFullscreenMode) return _buildFullscreenTimer();
    final progress = 1 - (currentSeconds / _getCurrentDuration());

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 15),
          _buildFocusStatsBar(),
          const SizedBox(height: 15),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isBreak ? 'Break Time' : 'Focus Time',
                          style: TextStyle(
                            fontSize: 22,
                            letterSpacing: 2,
                            color: _textColor,
                          ),
                        ),
                        _buildGlassButton(
                          icon: Icons.fullscreen,
                          onTap: () => setState(() => isFullscreenMode = true),
                          size: 40,
                          iconSize: 20,
                        ),
                      ],
                    ),
                    if (currentTask != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        currentTask!.title,
                        style: TextStyle(fontSize: 16, color: _textSecondary),
                      ),
                    ],
                    if (currentSubTask != null)
                      Text(
                        '→ ${currentSubTask!.title}',
                        style: TextStyle(
                          fontSize: 14,
                          color: _textSecondary.withOpacity(0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: 240,
            height: 240,
            child: LiquidCircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              valueColor: AlwaysStoppedAnimation(
                isBreak ? Colors.greenAccent : Colors.orangeAccent,
              ),
              backgroundColor: _cardBg,
              borderColor: _borderColor,
              borderWidth: 5,
              direction: Axis.vertical,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(currentSeconds),
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 4,
                      color: _textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pomodoro ${pomodoroCount + 1}',
                    style: TextStyle(fontSize: 14, color: _textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildGlassButton(icon: Icons.skip_next, onTap: _skipSession),
              const SizedBox(width: 20),
              _buildGlassButton(
                icon: isRunning ? Icons.pause : Icons.play_arrow,
                onTap: isRunning ? _pauseTimer : _startTimer,
                size: 80,
                iconSize: 40,
              ),
              const SizedBox(width: 20),
              _buildGlassButton(icon: Icons.refresh, onTap: _resetTimer),
            ],
          ),
          const SizedBox(height: 15),
          _buildSoundControls(),
          const SizedBox(height: 15),
          _buildDailyGoalProgress(),
          const SizedBox(height: 15),
          _buildQuickStats(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildFocusStatsBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _buildMiniStat('🔥', '$focusStreak', 'Streak')),
          const SizedBox(width: 10),
          Expanded(
            child: _buildMiniStat('🎯', '${getProductivityScore()}', 'Score'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildMiniStat('💪', '$deepWorkSessions', 'Deep Work'),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String emoji, String value, String label) {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _textColor,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: _textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyGoalProgress() {
    if (todayGoal == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Goal',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                    ),
                  ),
                  GestureDetector(
                    onTap: _showGoalSettingsDialog,
                    child: Icon(
                      Icons.settings,
                      size: 18,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pomodoros: ${todayGoal!.completedPomodoros}/${todayGoal!.targetPomodoros}',
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: todayGoal!.pomodoroProgress,
                          backgroundColor: _borderColor,
                          valueColor: AlwaysStoppedAnimation(
                            Colors.orangeAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Minutes: ${todayGoal!.completedMinutes}/${todayGoal!.targetMinutes}',
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: todayGoal!.minutesProgress,
                          backgroundColor: _borderColor,
                          valueColor: AlwaysStoppedAnimation(
                            Colors.greenAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Weekly: $weeklyCompletedPomodoros/$weeklyGoalPomodoros pomodoros',
                style: TextStyle(fontSize: 12, color: _textSecondary),
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: weeklyGoalPomodoros > 0
                    ? (weeklyCompletedPomodoros / weeklyGoalPomodoros).clamp(
                        0.0,
                        1.0,
                      )
                    : 0,
                backgroundColor: _borderColor,
                valueColor: AlwaysStoppedAnimation(Colors.purpleAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGoalSettingsDialog() {
    int dailyPom = todayGoal?.targetPomodoros ?? 8;
    int dailyMin = todayGoal?.targetMinutes ?? 200;
    int weeklyPom = weeklyGoalPomodoros;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: widget.isDark
              ? const Color(0xFF1A0B5E)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Goal Settings', style: TextStyle(color: _textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGoalSlider(
                'Daily Pomodoros',
                dailyPom,
                1,
                20,
                (v) => setD(() => dailyPom = v),
              ),
              _buildGoalSlider(
                'Daily Minutes',
                dailyMin,
                30,
                480,
                (v) => setD(() => dailyMin = v),
              ),
              _buildGoalSlider(
                'Weekly Pomodoros',
                weeklyPom,
                10,
                100,
                (v) => setD(() => weeklyPom = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  todayGoal!.targetPomodoros = dailyPom;
                  todayGoal!.targetMinutes = dailyMin;
                  weeklyGoalPomodoros = weeklyPom;
                });
                _saveFocusData();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _cardBg,
                foregroundColor: _textColor,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalSlider(
    String label,
    int value,
    int min,
    int max,
    Function(int) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: $value',
          style: TextStyle(color: _textSecondary, fontSize: 14),
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (v) => onChanged(v.round()),
          activeColor: _textColor,
        ),
      ],
    );
  }

  Widget _buildFullscreenTimer() {
    final progress = 1 - (currentSeconds / _getCurrentDuration());
    return GestureDetector(
      onTap: () => setState(() => isFullscreenMode = false),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgStart, _bgMid, _bgStart],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    height: 280,
                    child: LiquidCircularProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      valueColor: AlwaysStoppedAnimation(
                        isBreak ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                      backgroundColor: _cardBg,
                      borderColor: _borderColor,
                      borderWidth: 4,
                      direction: Axis.vertical,
                      center: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(currentSeconds),
                            style: TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 4,
                              color: _textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isBreak ? 'BREAK' : 'FOCUS',
                            style: TextStyle(
                              fontSize: 16,
                              color: _textSecondary,
                              letterSpacing: 3,
                            ),
                          ),
                          if (currentTask != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              currentTask!.title,
                              style: TextStyle(
                                fontSize: 14,
                                color: _textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildGlassButton(
                        icon: Icons.skip_next,
                        onTap: _skipSession,
                        size: 60,
                        iconSize: 28,
                      ),
                      const SizedBox(width: 20),
                      _buildGlassButton(
                        icon: isRunning ? Icons.pause : Icons.play_arrow,
                        onTap: isRunning ? _pauseTimer : _startTimer,
                        size: 80,
                        iconSize: 40,
                      ),
                      const SizedBox(width: 20),
                      _buildGlassButton(
                        icon: Icons.refresh,
                        onTap: _resetTimer,
                        size: 60,
                        iconSize: 28,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: _buildGlassButton(
                icon: Icons.fullscreen_exit,
                onTap: () => setState(() => isFullscreenMode = false),
                size: 50,
                iconSize: 24,
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: _buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text(
                        '🔥 $focusStreak',
                        style: TextStyle(fontSize: 14, color: _textColor),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Pom ${pomodoroCount + 1}',
                        style: TextStyle(fontSize: 14, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoundControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              setState(() => soundEnabled = !soundEnabled);
              _saveSettings();
              if (!soundEnabled && isRunning) _stopBgSound();
              if (soundEnabled && isRunning) _playBgSound();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: Icon(
                soundEnabled ? Icons.volume_up : Icons.volume_off,
                color: _textColor,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 15),
          GestureDetector(
            onTap: _showSoundPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.music_note, color: _textColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    soundNames[selectedSoundIndex],
                    style: TextStyle(color: _textColor, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_drop_down, color: _textColor, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSoundPicker() {
    final controller = FixedExtentScrollController(
      initialItem: selectedSoundIndex,
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: 300,
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1A0B5E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 15),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _textSecondary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'Select Sound',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: controller,
                itemExtent: 50,
                perspective: 0.005,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) {
                  setState(() => selectedSoundIndex = i);
                  _saveSettings();
                  if (soundEnabled && isRunning) {
                    _stopBgSound();
                    _playBgSound();
                  }
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: soundNames.length,
                  builder: (ctx, i) => Center(
                    child: Text(
                      soundNames[i],
                      style: TextStyle(
                        fontSize: i == selectedSoundIndex ? 20 : 16,
                        fontWeight: i == selectedSoundIndex
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: i == selectedSoundIndex
                            ? _textColor
                            : _textSecondary.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cardBg,
                    foregroundColor: _textColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TASKS PAGE ====================
  Widget _buildTasksPage() {
    final filtered = selectedCategory == 'All'
        ? tasks
        : tasks.where((t) => t.category == selectedCategory).toList();
    return Column(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text('Tasks', style: TextStyle(fontSize: 28, color: _textColor)),
              const Spacer(),
              _buildGlassButton(icon: Icons.add, onTap: _showAddTaskDialog),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: categories
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() => selectedCategory = c),
                      child: _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              color: c == selectedCategory
                                  ? _textColor
                                  : _textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.task_alt,
                        size: 64,
                        color: _textSecondary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No tasks yet',
                        style: TextStyle(color: _textSecondary, fontSize: 18),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _buildTaskCard(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(Task task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: _buildGlassCard(
        child: InkWell(
          onTap: () => _showTaskDetailDialog(task),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          task.isCompleted = !task.isCompleted;
                          if (task.isCompleted) {
                            _confettiController.play();
                            totalTasksCompleted++;
                            _saveAnalytics();
                          }
                        });
                        _saveTasks();
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _textSecondary, width: 2),
                          color: task.isCompleted
                              ? _textSecondary.withOpacity(0.3)
                              : Colors.transparent,
                        ),
                        child: task.isCompleted
                            ? Icon(Icons.check, size: 16, color: _textColor)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 16,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: _textColor,
                        ),
                      ),
                    ),
                    if (task.priority > 0)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: List.generate(
                            task.priority,
                            (i) => Icon(
                              Icons.flag,
                              size: 12,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (task.subTasks.isNotEmpty) ...[
                  const SizedBox(height: 15),
                  Text(
                    '${task.subTasks.where((s) => s.isCompleted).length}/${task.subTasks.length} subtasks',
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ],
                if (task.pomodorosCompleted > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.timer, size: 14, color: _textSecondary),
                      const SizedBox(width: 5),
                      Text(
                        '${task.pomodorosCompleted} pomodoros',
                        style: TextStyle(fontSize: 12, color: _textSecondary),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== ANALYTICS PAGE ====================
  Widget _buildAnalyticsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Analytics',
              style: TextStyle(fontSize: 28, color: _textColor),
            ),
            GestureDetector(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.download, color: _textColor, size: 24),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildProductivityScoreCard(),
        const SizedBox(height: 20),
        _buildStatsOverview(),
        const SizedBox(height: 20),
        _buildHeatmapCalendar(),
        const SizedBox(height: 20),
        _buildHourlyProductivityChart(),
        const SizedBox(height: 20),
        _buildWeeklyChart(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildProductivityScoreCard() {
    final score = getProductivityScore();
    Color scoreColor = score >= 80
        ? Colors.greenAccent
        : score >= 50
        ? Colors.orangeAccent
        : Colors.redAccent;
    String scoreLabel = score >= 80
        ? 'Excellent!'
        : score >= 50
        ? 'Good'
        : 'Keep Going!';

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    backgroundColor: _borderColor,
                    valueColor: AlwaysStoppedAnimation(scoreColor),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$score',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _textColor,
                        ),
                      ),
                      Text(
                        'Score',
                        style: TextStyle(fontSize: 12, color: _textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    scoreLabel,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Based on your daily goals, streak, and deep work sessions',
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsOverview() {
    final rate = getTaskCompletionRate();
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStatRow('Total Pomodoros', '$totalPomodoros'),
            Divider(height: 25, color: _borderColor),
            _buildStatRow('Today Pomodoros', '$todayPomodoros'),
            Divider(height: 25, color: _borderColor),
            _buildStatRow(
              'Total Focus Time',
              '${(totalFocusTime / 3600).toStringAsFixed(1)}h',
            ),
            Divider(height: 25, color: _borderColor),
            _buildStatRow(
              'Avg Session',
              '${avgFocusTime.toStringAsFixed(1)} min',
            ),
            Divider(height: 25, color: _borderColor),
            _buildStatRow(
              'Task Completion',
              '${(rate * 100).toStringAsFixed(0)}%',
            ),
            Divider(height: 25, color: _borderColor),
            _buildStatRow('Focus Streak', '$focusStreak days'),
            Divider(height: 25, color: _borderColor),
            _buildStatRow('Deep Work Sessions', '$deepWorkSessions'),
          ],
        ),
      ),
    );
  }

  Widget _buildHeatmapCalendar() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Activity Heatmap - ${_getMonthName(now.month)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 15),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: daysInMonth,
              itemBuilder: (ctx, i) {
                final day = i + 1;
                final dateKey =
                    '${now.year}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                final count = heatmapData[dateKey] ?? 0;
                final intensity = count == 0 ? 0.0 : min(count / 8, 1.0);

                return Container(
                  decoration: BoxDecoration(
                    color: count == 0
                        ? _borderColor
                        : Colors.greenAccent.withOpacity(0.3 + intensity * 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 10,
                        color: count > 0 ? Colors.white : _textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Less',
                  style: TextStyle(fontSize: 10, color: _textSecondary),
                ),
                const SizedBox(width: 5),
                ...List.generate(
                  5,
                  (i) => Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? _borderColor
                          : Colors.greenAccent.withOpacity(0.3 + (i / 4) * 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'More',
                  style: TextStyle(fontSize: 10, color: _textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
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
    return months[month - 1];
  }

  Widget _buildHourlyProductivityChart() {
    final maxVal = hourlyProductivity.reduce(max).toDouble();

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Most Productive Hours',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal > 0 ? maxVal + 2 : 10,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (v, m) => v.toInt() % 4 == 0
                            ? Text(
                                '${v.toInt()}h',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _textSecondary,
                                ),
                              )
                            : const SizedBox(),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(
                    24,
                    (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: hourlyProductivity[i].toDouble(),
                          width: 8,
                          borderRadius: BorderRadius.circular(4),
                          color: _getHourColor(i),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildBestHoursText(),
          ],
        ),
      ),
    );
  }

  Color _getHourColor(int hour) {
    if (hour >= 6 && hour < 12) return Colors.orangeAccent;
    if (hour >= 12 && hour < 18) return Colors.blueAccent;
    if (hour >= 18 && hour < 22) return Colors.purpleAccent;
    return Colors.grey;
  }

  Widget _buildBestHoursText() {
    int bestHour = 0;
    int bestCount = 0;
    for (int i = 0; i < 24; i++) {
      if (hourlyProductivity[i] > bestCount) {
        bestCount = hourlyProductivity[i];
        bestHour = i;
      }
    }
    if (bestCount == 0)
      return Text(
        'Start focusing to see your best hours!',
        style: TextStyle(fontSize: 12, color: _textSecondary),
      );
    return Text(
      '🏆 Your most productive hour: ${bestHour}:00 - ${bestHour + 1}:00',
      style: TextStyle(fontSize: 12, color: Colors.greenAccent),
    );
  }

  Widget _buildWeeklyChart() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxVal = weeklyPomodoros.reduce(max).toDouble();

    final barColors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.pink,
    ];

    return SizedBox(
      height: 280, // chart balandligi
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal > 0 ? maxVal + 2 : 10,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${days[group.x.toInt()]}\n${rod.toY.toInt()} Pomodoro',
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36, // 🔥 Pastdagi matn to‘liq chiqadi
                getTitlesWidget: (v, m) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    days[v.toInt()],
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, m) => Text(
                  v.toInt().toString(),
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: _borderColor.withOpacity(0.3), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: weeklyPomodoros.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.toDouble(),
                  width: 18,
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    colors: [
                      barColors[e.key],
                      barColors[e.key].withOpacity(0.6),
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Text('Settings', style: TextStyle(fontSize: 28, color: _textColor)),
        const SizedBox(height: 30),
        _buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: TextStyle(
                    fontSize: 18,
                    letterSpacing: 1,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 20),
                _buildSwitchSetting('Dark Mode', widget.isDark, (v) {
                  widget.onThemeToggle();
                  _saveSettings();
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Timer Duration',
                  style: TextStyle(
                    fontSize: 18,
                    letterSpacing: 1,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 20),
                _buildDurationSetting('Work', workDuration, (v) {
                  setState(() => workDuration = v);
                  _saveSettings();
                }),
                const SizedBox(height: 15),
                _buildDurationSetting('Short Break', shortBreakDuration, (v) {
                  setState(() => shortBreakDuration = v);
                  _saveSettings();
                }),
                const SizedBox(height: 15),
                _buildDurationSetting('Long Break', longBreakDuration, (v) {
                  setState(() => longBreakDuration = v);
                  _saveSettings();
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildSwitchSetting('Auto Start Break', autoStartBreak, (v) {
                  setState(() => autoStartBreak = v);
                  _saveSettings();
                }),
                Divider(height: 30, color: _borderColor),
                _buildSwitchSetting('Auto Start Pomodoro', autoStartPomodoro, (
                  v,
                ) {
                  setState(() => autoStartPomodoro = v);
                  _saveSettings();
                }),
                Divider(height: 30, color: _borderColor),
                _buildSwitchSetting('Notifications', enableNotifications, (v) {
                  setState(() => enableNotifications = v);
                  _saveSettings();
                }),
                Divider(height: 30, color: _borderColor),
                _buildSwitchSetting('Vibration', enableVibration, (v) {
                  setState(() => enableVibration = v);
                  _saveSettings();
                }),
                Divider(height: 30, color: _borderColor),
                _buildSwitchSetting('Keep Screen On', keepScreenOn, (v) {
                  setState(() => keepScreenOn = v);
                  _saveSettings();
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildGlassCard(
          child: InkWell(
            onTap: _showResetDialog,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_forever, color: Colors.red),
                  SizedBox(width: 10),
                  Text(
                    'Reset All Data',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: child,
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 60,
    double iconSize = 28,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _borderColor, width: 1),
        ),
        child: Icon(icon, size: iconSize, color: _textColor),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(Icons.timer, 0),
            _buildNavItem(Icons.check_circle_outline, 1),
            _buildNavItem(Icons.bar_chart, 2),
            _buildNavItem(Icons.settings, 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    final isSelected = currentPage == index;
    return GestureDetector(
      onTap: () => setState(() => currentPage = index),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? _cardBg : Colors.transparent,
        ),
        child: Icon(
          icon,
          color: isSelected ? _textColor : _textSecondary.withOpacity(0.5),
          size: 28,
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildQuickStat(
                Icons.local_fire_department,
                pomodoroCount.toString(),
              ),
              Container(width: 1, height: 40, color: _borderColor),
              _buildQuickStat(Icons.today, todayPomodoros.toString()),
              Container(width: 1, height: 40, color: _borderColor),
              _buildQuickStat(Icons.timer, '${(totalFocusTime / 60).toInt()}m'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStat(IconData icon, String value) => Column(
    children: [
      Icon(icon, color: _textSecondary, size: 20),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(fontSize: 16, color: _textColor)),
    ],
  );

  Widget _buildStatRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(color: _textSecondary)),
      Text(value, style: TextStyle(fontSize: 18, color: _textColor)),
    ],
  );

  Widget _buildDurationSetting(
    String label,
    int value,
    Function(int) onChange,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: _textSecondary)),
        Row(
          children: [
            GestureDetector(
              onTap: () {
                if (value > 60) onChange(value - 60);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cardBg,
                ),
                child: Icon(Icons.remove, size: 20, color: _textSecondary),
              ),
            ),
            SizedBox(
              width: 60,
              child: Center(
                child: Text(
                  '${value ~/ 60}m',
                  style: TextStyle(fontSize: 16, color: _textColor),
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                if (value < 3600) onChange(value + 60);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cardBg,
                ),
                child: Icon(Icons.add, size: 20, color: _textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSwitchSetting(
    String label,
    bool value,
    Function(bool) onChange,
  ) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(color: _textSecondary)),
      Switch(
        value: value,
        onChanged: onChange,
        activeColor: _textColor,
        activeTrackColor: _textSecondary.withOpacity(0.3),
      ),
    ],
  );

  void _showAddTaskDialog() {
    String title = '', selectedCat = 'Work';
    int selectedPriority = 0;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: widget.isDark
              ? const Color(0xFF1A0B5E)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('New Task', style: TextStyle(color: _textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => title = v,
                style: TextStyle(color: _textColor),
                decoration: InputDecoration(
                  hintText: 'Task title',
                  hintStyle: TextStyle(color: _textSecondary.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _textColor),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: selectedCat,
                dropdownColor: widget.isDark
                    ? const Color(0xFF1A0B5E)
                    : Colors.white,
                style: TextStyle(color: _textColor),
                decoration: InputDecoration(
                  labelText: 'Category',
                  labelStyle: TextStyle(color: _textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _borderColor),
                  ),
                ),
                items: categories
                    .skip(1)
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setD(() => selectedCat = v!),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Text('Priority:', style: TextStyle(color: _textSecondary)),
                  const Spacer(),
                  ...List.generate(
                    3,
                    (i) => GestureDetector(
                      onTap: () => setD(() => selectedPriority = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Icon(
                          Icons.flag,
                          color: i < selectedPriority
                              ? _textColor
                              : _textSecondary.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (title.isNotEmpty) {
                  setState(
                    () => tasks.add(
                      Task(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: title,
                        createdAt: DateTime.now(),
                        category: selectedCat,
                        priority: selectedPriority,
                      ),
                    ),
                  );
                  _saveTasks();
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _cardBg,
                foregroundColor: _textColor,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTaskDetailDialog(Task task) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: widget.isDark
              ? const Color(0xFF1A0B5E)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(task.title, style: TextStyle(color: _textColor)),
              ),
              IconButton(
                icon: Icon(Icons.delete, color: _textSecondary),
                onPressed: () {
                  setState(() => tasks.remove(task));
                  _saveTasks();
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.category, size: 16, color: _textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      task.category ?? 'No category',
                      style: TextStyle(color: _textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.timer, size: 16, color: _textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      '${task.pomodorosCompleted} pomodoros',
                      style: TextStyle(color: _textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Subtasks (${task.subTasks.length})',
                      style: TextStyle(fontSize: 16, color: _textSecondary),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.add, size: 20, color: _textColor),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAddSubTaskDialog(task);
                      },
                    ),
                  ],
                ),
                if (task.subTasks.isNotEmpty)
                  ...task.subTasks.map(
                    (sub) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              setState(
                                () => sub.isCompleted = !sub.isCompleted,
                              );
                              setD(() {});
                              _saveTasks();
                            },
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _textSecondary,
                                  width: 2,
                                ),
                                color: sub.isCompleted
                                    ? _textSecondary.withOpacity(0.3)
                                    : Colors.transparent,
                              ),
                              child: sub.isCompleted
                                  ? Icon(
                                      Icons.check,
                                      size: 12,
                                      color: _textColor,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              sub.title,
                              style: TextStyle(
                                color: _textSecondary,
                                decoration: sub.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          Text(
                            '${sub.duration}m',
                            style: TextStyle(
                              fontSize: 12,
                              color: _textSecondary,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.play_arrow,
                              size: 18,
                              color: _textSecondary,
                            ),
                            onPressed: () {
                              _startSubTask(task, sub);
                              Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _startTask(task);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cardBg,
                  foregroundColor: _textColor,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text('Start Task'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSubTaskDialog(Task task) {
    String title = '';
    int duration = 25;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: widget.isDark
              ? const Color(0xFF1A0B5E)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('New Subtask', style: TextStyle(color: _textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (v) => title = v,
                style: TextStyle(color: _textColor),
                decoration: InputDecoration(
                  hintText: 'Subtask title',
                  hintStyle: TextStyle(color: _textSecondary.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _textColor),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Duration', style: TextStyle(color: _textSecondary)),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (duration > 5) setD(() => duration -= 5);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _cardBg,
                          ),
                          child: Icon(
                            Icons.remove,
                            size: 20,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Center(
                          child: Text(
                            '${duration}m',
                            style: TextStyle(fontSize: 16, color: _textColor),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (duration < 120) setD(() => duration += 5);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _cardBg,
                          ),
                          child: Icon(
                            Icons.add,
                            size: 20,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (title.isNotEmpty) {
                  setState(
                    () => task.subTasks.add(
                      SubTask(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: title,
                        duration: duration,
                      ),
                    ),
                  );
                  _saveTasks();
                  Navigator.pop(ctx);
                  _showTaskDetailDialog(task);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _cardBg,
                foregroundColor: _textColor,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1A0B5E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Icon(Icons.warning_amber_rounded, size: 48, color: _textSecondary),
            const SizedBox(height: 15),
            Text('Reset All Data?', style: TextStyle(color: _textColor)),
          ],
        ),
        content: Text(
          'This will delete all tasks, statistics, and settings.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await settingsBox.clear();
              await tasksBox.clear();
              await statsBox.clear();
              setState(() {
                tasks.clear();
                totalPomodoros = 0;
                todayPomodoros = 0;
                totalFocusTime = 0;
                pomodoroCount = 0;
                workDuration = 25 * 60;
                shortBreakDuration = 5 * 60;
                longBreakDuration = 15 * 60;
                currentSeconds = workDuration;
                currentTask = null;
                currentSubTask = null;
                isFullscreenMode = false;
                weeklyPomodoros = [0, 0, 0, 0, 0, 0, 0];
                isBreak = false;
                isRunning = false;
              });
              _stopBgSound();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.2),
              foregroundColor: Colors.red,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  int _getCurrentDuration() {
    if (currentSubTask != null) return currentSubTask!.duration * 60;
    if (isBreak)
      return pomodoroCount % 4 == 0 ? longBreakDuration : shortBreakDuration;
    return workDuration;
  }
}

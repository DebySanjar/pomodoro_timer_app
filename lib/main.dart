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
    with TickerProviderStateMixin {
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer bgAudioPlayer = AudioPlayer();
  late ConfettiController _confettiController;
  late Box settingsBox, tasksBox, statsBox;

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
    'forest.mp3',
    'ocean.mp3',
    'fire.mp3',
    'wind.mp3',
    'birds.mp3',
    'thunder.mp3',
    'cafe.mp3',
    'piano.mp3',
    'white_noise.mp3',
  ];
  final List<String> soundNames = [
    'Rain',
    'Forest',
    'Ocean',
    'Fire',
    'Wind',
    'Birds',
    'Thunder',
    'Cafe',
    'Piano',
    'White Noise',
  ];

  String selectedCategory = 'All';
  List<String> categories = ['All', 'Work', 'Study', 'Personal', 'Other'];

  @override
  void initState() {
    super.initState();
    settingsBox = Hive.box('settings');
    tasksBox = Hive.box('tasks');
    statsBox = Hive.box('stats');
    _initNotifications();
    _loadData();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    bgAudioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(
      const InitializationSettings(android: android),
    );
  }

  void _loadData() {
    setState(() {
      // Settings
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

      // Stats - muhim!
      totalPomodoros = statsBox.get('totalPomodoros', defaultValue: 0);
      todayPomodoros = statsBox.get('todayPomodoros', defaultValue: 0);
      totalFocusTime = statsBox.get('totalFocusTime', defaultValue: 0);

      // Weekly chart data
      final weeklyData = statsBox.get('weeklyPomodoros');
      if (weeklyData != null && weeklyData is List) {
        weeklyPomodoros = List<int>.from(weeklyData);
      } else {
        weeklyPomodoros = [0, 0, 0, 0, 0, 0, 0];
      }

      // Pomodorocount session uchun
      pomodoroCount = statsBox.get('pomodoroCount', defaultValue: 0);

      // Tasks
      final tasksData = tasksBox.get('tasksList');
      if (tasksData != null && tasksData is List) {
        tasks = tasksData
            .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      currentSeconds = workDuration;
    });
  }

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
  }

  Future<void> _saveStats() async {
    await statsBox.put('totalPomodoros', totalPomodoros);
    await statsBox.put('todayPomodoros', todayPomodoros);
    await statsBox.put('totalFocusTime', totalFocusTime);
    await statsBox.put('weeklyPomodoros', weeklyPomodoros);
    await statsBox.put('pomodoroCount', pomodoroCount);
  }

  void _startTimer() {
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

  void _stopBgSound() async {
    await bgAudioPlayer.stop();
  }

  void _pauseTimer() {
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
      pomodoroCount++;
      totalPomodoros++;
      todayPomodoros++;
      totalFocusTime += workDuration;
      weeklyPomodoros[DateTime.now().weekday - 1]++;
      if (currentTask != null) {
        currentTask!.pomodorosCompleted++;
        if (currentSubTask != null) currentSubTask!.isCompleted = true;
      }
      await _saveStats();
      await _saveTasks();
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

  @override
  void dispose() {
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

  Color get _borderColor => !widget.isDark
      ? Colors.black.withOpacity(0.1)
      : Colors.white.withOpacity(0.2);

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
                _buildStatsPage(),
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
              numberOfParticles: 60,
              maxBlastForce: 120,
              minBlastForce: 50,
              createParticlePath: createMixedParticles,
              gravity: 0.2,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
                Colors.yellow,
                Colors.red,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerPage() {
    if (isFullscreenMode) return _buildFullscreenTimer();
    final progress = 1 - (currentSeconds / _getCurrentDuration());

    return Column(
      children: [
        const SizedBox(height: 20),
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
        const SizedBox(height: 30),
        SizedBox(
          width: 260,
          height: 260,
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
                    fontSize: 48,
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
        const SizedBox(height: 30),
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
        const SizedBox(height: 20),
        _buildSoundControls(),
        const Spacer(),
        _buildQuickStats(),
        const SizedBox(height: 100),
      ],
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
    final FixedExtentScrollController scrollController =
        FixedExtentScrollController(initialItem: selectedSoundIndex);

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
                controller: scrollController,
                itemExtent: 50,
                perspective: 0.005,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (index) {
                  setState(() => selectedSoundIndex = index);
                  _saveSettings();
                  if (soundEnabled && isRunning) {
                    _stopBgSound();
                    _playBgSound();
                  }
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: soundNames.length,
                  builder: (ctx, index) {
                    final isSelected = index == selectedSoundIndex;
                    return Center(
                      child: Text(
                        soundNames[index],
                        style: TextStyle(
                          fontSize: isSelected ? 20 : 16,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? _textColor
                              : _textSecondary.withOpacity(0.5),
                        ),
                      ),
                    );
                  },
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
                    width: 300,
                    height: 300,
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
                              fontSize: 56,
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
                                fontSize: 16,
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
                  child: Text(
                    'Pomodoro ${pomodoroCount + 1}',
                    style: TextStyle(fontSize: 14, color: _textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksPage() {
    final filteredTasks = selectedCategory == 'All'
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
            children: categories.map((cat) {
              final isSelected = cat == selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => setState(() => selectedCategory = cat),
                  child: _buildGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: isSelected ? _textColor : _textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: filteredTasks.isEmpty
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
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to add your first task',
                        style: TextStyle(
                          color: _textSecondary.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  itemCount: filteredTasks.length,
                  itemBuilder: (ctx, i) => _buildTaskCard(filteredTasks[i]),
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
                          if (task.isCompleted) _confettiController.play();
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

  Widget _buildStatsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Text('Statistics', style: TextStyle(fontSize: 28, color: _textColor)),
        const SizedBox(height: 30),
        _buildGlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStatRow('Total Pomodoros', totalPomodoros.toString()),
                Divider(height: 30, color: _borderColor),
                _buildStatRow('Today Pomodoros', todayPomodoros.toString()),
                Divider(height: 30, color: _borderColor),
                _buildStatRow(
                  'Total Focus Time',
                  '${(totalFocusTime / 3600).toStringAsFixed(1)}h',
                ),
                Divider(height: 30, color: _borderColor),
                _buildStatRow(
                  'Tasks Completed',
                  tasks.where((t) => t.isCompleted).length.toString(),
                ),
                Divider(height: 30, color: _borderColor),
                _buildStatRow(
                  'Active Tasks',
                  tasks.where((t) => !t.isCompleted).length.toString(),
                ),
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
                  'Categories',
                  style: TextStyle(
                    fontSize: 18,
                    letterSpacing: 1,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 20),
                ...categories
                    .skip(1)
                    .map(
                      (cat) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildStatRow(
                          cat,
                          tasks
                              .where((t) => t.category == cat)
                              .length
                              .toString(),
                        ),
                      ),
                    ),
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
                  'Weekly Progress',
                  style: TextStyle(
                    fontSize: 18,
                    letterSpacing: 1,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(height: 200, child: _buildWeeklyChart()),
              ],
            ),
          ),
        ),
      ],
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

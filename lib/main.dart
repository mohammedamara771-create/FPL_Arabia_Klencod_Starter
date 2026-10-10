import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const purple = Color(0xFF37003C);
const green = Color(0xFF00FF87);
const cyan = Color(0xFF04F5FF);
const apiBase = 'https://fantasy.premierleague.com/api/';

final notifications = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await notifications.initialize(initSettings);
  runApp(const FPLArabiaApp());
}

class FPLArabiaApp extends StatelessWidget {
  const FPLArabiaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FPL Arabia',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101014),
        colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.dark),
        appBarTheme: const AppBarTheme(backgroundColor: purple, foregroundColor: Colors.white),
        cardTheme: CardTheme(
          color: const Color(0xFF1C1B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool loading = true;
  String? error;
  Map<String, dynamic> bootstrap = {};
  List<dynamic> fixtures = [];
  List<int> squadIds = [];
  int? selectedPosition;
  String search = '';

  @override
  void initState() {
    super.initState();
    _loadSavedSquad();
    _loadData();
  }

  Future<void> _loadSavedSquad() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => squadIds = prefs.getStringList('squad_ids')?.map(int.parse).toList() ?? []);
  }

  Future<void> _saveSquad() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('squad_ids', squadIds.map((e) => e.toString()).toList());
  }

  Future<void> _loadData() async {
    setState(() { loading = true; error = null; });
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('${apiBase}bootstrap-static/')).timeout(const Duration(seconds: 20)),
        http.get(Uri.parse('${apiBase}fixtures/')).timeout(const Duration(seconds: 20)),
      ]);
      if (responses[0].statusCode != 200 || responses[1].statusCode != 200) {
        throw Exception('تعذر الاتصال بخدمة FPL. حاول مرة أخرى لاحقًا.');
      }
      final data = jsonDecode(responses[0].body) as Map<String, dynamic>;
      final fix = jsonDecode(responses[1].body) as List<dynamic>;
      if (!mounted) return;
      setState(() { bootstrap = data; fixtures = fix; loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { loading = false; error = 'لم نتمكن من تحميل البيانات. تأكد من الإنترنت ثم اضغط تحديث.'; });
    }
  }

  List<dynamic> get players => (bootstrap['elements'] as List<dynamic>? ?? []);
  List<dynamic> get teams => (bootstrap['teams'] as List<dynamic>? ?? []);
  List<dynamic> get events => (bootstrap['events'] as List<dynamic>? ?? []);

  Map<String, dynamic>? get currentEvent {
    for (final e in events) {
      if (e['is_current'] == true) return Map<String, dynamic>.from(e);
    }
    for (final e in events) {
      if (e['is_next'] == true) return Map<String, dynamic>.from(e);
    }
    return events.isNotEmpty ? Map<String, dynamic>.from(events.first) : null;
  }

  String teamName(dynamic id) {
    final found = teams.where((t) => t['id'] == id);
    if (found.isEmpty) return 'نادي غير معروف';
    return found.first['name']?.toString() ?? 'نادي';
  }

  String positionName(dynamic id) {
    switch (id) {
      case 1: return 'حارس';
      case 2: return 'دفاع';
      case 3: return 'وسط';
      case 4: return 'هجوم';
      default: return 'لاعب';
    }
  }

  String price(dynamic cost) => '£${((cost ?? 0) / 10).toStringAsFixed(1)}م';

  Future<void> _scheduleReminder() async {
    final androidPlugin = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    const androidDetails = AndroidNotificationDetails(
      'fpl_deadline_channel', 'تذكيرات فانتازي',
      channelDescription: 'تذكيرات مواعيد فانتازي الدوري الإنجليزي',
      importance: Importance.max, priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await notifications.zonedSchedule(
      100,
      'FPL Arabia',
      'تذكير تجريبي: لا تنسَ مراجعة تشكيلتك قبل إغلاق الجولة.',
      tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1)),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم ضبط إشعار تجريبي بعد دقيقة واحدة.')),
    );
  }

  Future<void> _togglePlayer(int id) async {
    setState(() {
      if (squadIds.contains(id)) {
        squadIds.remove(id);
      } else if (squadIds.length < 15) {
        squadIds.add(id);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('التشكيلة تحتوي على 15 لاعبًا بالفعل.')));
      }
    });
    await _saveSquad();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _homeTab(),
      _playersTab(),
      _squadTab(),
      _fixturesTab(),
      _settingsTab(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(children: [
            Icon(Icons.sports_soccer, color: green),
            SizedBox(width: 8),
            Text('FPL Arabia', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          actions: [
            IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh), tooltip: 'تحديث البيانات'),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: green))
            : error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.wifi_off, size: 48, color: cyan),
                      const SizedBox(height: 12),
                      Text(error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
                    ]),
                  ))
                : pages[tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          backgroundColor: purple,
          indicatorColor: green.withOpacity(.18),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'اللاعبون'),
            NavigationDestination(icon: Icon(Icons.stadium_outlined), selectedIcon: Icon(Icons.stadium), label: 'تشكيلتي'),
            NavigationDestination(icon: Icon(Icons.sports_soccer_outlined), selectedIcon: Icon(Icons.sports_soccer), label: 'المباريات'),
            NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }

  Widget _homeTab() {
    final event = currentEvent;
    final deadline = event?['deadline_time']?.toString();
    String deadlineText = 'غير متاح';
    if (deadline != null) {
      final dt = DateTime.tryParse(deadline)?.toLocal();
      if (dt != null) deadlineText = '${dt.day}/${dt.month}/${dt.year} - ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final totalPoints = squadIds.fold<int>(0, (sum, id) {
      final p = players.where((x) => x['id'] == id);
      return sum + (p.isEmpty ? 0 : ((p.first['total_points'] ?? 0) as num).toInt());
    });
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [purple, Color(0xFF5A1765)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('مرحبًا بك في فانتازي', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(event?['name']?.toString() ?? 'الجولة القادمة', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            const Text('موعد إغلاق الجولة', style: TextStyle(color: Colors.white70)),
            Text(deadlineText, style: const TextStyle(fontSize: 18, color: green, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _statCard('لاعبو تشكيلتي', '${squadIds.length}/15', Icons.groups, green)),
          const SizedBox(width: 10),
          Expanded(child: _statCard('مجموع نقاطهم', '$totalPoints', Icons.stars, cyan)),
        ]),
        const SizedBox(height: 16),
        _sectionTitle('ابدأ من هنا'),
        _actionCard(Icons.groups, 'اختيار اللاعبين', 'أضف حتى 15 لاعبًا إلى تشكيلتك', () => setState(() => tab = 1)),
        _actionCard(Icons.stadium, 'عرض تشكيلتي', 'راجع اللاعبين الذين حفظتهم', () => setState(() => tab = 2)),
        _actionCard(Icons.notifications_active, 'تجربة الإشعارات', 'إشعار تجريبي بعد دقيقة واحدة', _scheduleReminder),
        const SizedBox(height: 14),
        const Text('البيانات تُجلب من واجهة FPL العامة، وقد تتغير أو تتوقف إذا غيّرت الخدمة طريقة الوصول.', style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 26), const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      Text(title, style: const TextStyle(color: Colors.white70)),
    ])),
  );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
  );

  Widget _actionCard(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    child: ListTile(leading: CircleAvatar(backgroundColor: purple, child: Icon(icon, color: green)),
      title: Text(title), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_left), onTap: onTap),
  );

  Widget _playersTab() {
    final filtered = players.where((p) {
      final fullName = '${p['first_name'] ?? ''} ${p['second_name'] ?? ''}'.toLowerCase();
      final matchesSearch = fullName.contains(search.toLowerCase());
      final matchesPosition = selectedPosition == null || p['element_type'] == selectedPosition;
      return matchesSearch && matchesPosition;
    }).toList();
    filtered.sort((a, b) => ((b['total_points'] ?? 0) as num).compareTo((a['total_points'] ?? 0) as num));
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: TextField(
        onChanged: (v) => setState(() => search = v),
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'ابحث عن لاعب...', filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
      )),
      SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
        _positionChip('الكل', null),
        _positionChip('حراس', 1),
        _positionChip('دفاع', 2),
        _positionChip('وسط', 3),
        _positionChip('هجوم', 4),
      ])),
      Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (context, i) {
        final p = filtered[i] as Map<String, dynamic>;
        final id = p['id'] as int;
        final selected = squadIds.contains(id);
        return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(
          leading: CircleAvatar(backgroundColor: purple, child: Text('${p['total_points'] ?? 0}', style: const TextStyle(color: green, fontWeight: FontWeight.bold))),
          title: Text('${p['first_name'] ?? ''} ${p['second_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${teamName(p['team'])} • ${positionName(p['element_type'])} • ${price(p['now_cost'])}'),
          trailing: IconButton(onPressed: () => _togglePlayer(id), icon: Icon(selected ? Icons.remove_circle : Icons.add_circle, color: selected ? Colors.redAccent : green)),
        ));
      })),
    ]);
  }

  Widget _positionChip(String label, int? value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
    child: ChoiceChip(label: Text(label), selected: selectedPosition == value,
      selectedColor: green.withOpacity(.25), onSelected: (_) => setState(() => selectedPosition = value)),
  );

  Widget _squadTab() {
    final selected = players.where((p) => squadIds.contains(p['id'])).toList();
    final cost = selected.fold<double>(0, (sum, p) => sum + ((p['now_cost'] ?? 0) as num).toDouble() / 10);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('تشكيلتي المحفوظة'), Text('${selected.length} من 15 لاعبًا', style: const TextStyle(color: green))]),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text('قيمة اللاعبين'), Text('£${cost.toStringAsFixed(1)}م', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
      ]))),
      const SizedBox(height: 8),
      if (selected.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Text('لم تضف لاعبين بعد. افتح تبويب اللاعبين واضغط علامة + بجانب اللاعب.', textAlign: TextAlign.center))
      else ...selected.map((p) => Card(child: ListTile(
        leading: const Icon(Icons.person, color: green),
        title: Text('${p['first_name']} ${p['second_name']}'),
        subtitle: Text('${teamName(p['team'])} • ${positionName(p['element_type'])} • ${price(p['now_cost'])}'),
        trailing: IconButton(onPressed: () => _togglePlayer(p['id'] as int), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
      ))),
      const Padding(padding: EdgeInsets.all(8), child: Text('ملاحظة: هذه نسخة أولية لحفظ قائمة اللاعبين محليًا، وليست إرسالًا رسميًا لتشكيلتك إلى حساب FPL.', style: TextStyle(color: Colors.white54, fontSize: 12))),
    ]);
  }

  Widget _fixturesTab() {
    final next = fixtures.where((f) => f['event'] != null && f['finished'] != true).toList()
      ..sort((a, b) => (a['event'] as int).compareTo(b['event'] as int));
    final show = next.take(80).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      _sectionTitle('المباريات القادمة'),
      if (show.isEmpty) const Text('لا توجد مباريات قادمة متاحة حاليًا.'),
      ...show.map((f) {
        final kick = DateTime.tryParse(f['kickoff_time']?.toString() ?? '')?.toLocal();
        final when = kick == null ? 'موعد غير محدد' : '${kick.day}/${kick.month} ${kick.hour.toString().padLeft(2, '0')}:${kick.minute.toString().padLeft(2, '0')}';
        return Card(child: ListTile(
          leading: CircleAvatar(backgroundColor: purple, child: Text('ج${f['event']}', style: const TextStyle(color: green, fontSize: 12))),
          title: Text('${teamName(f['team_h'])}  -  ${teamName(f['team_a'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(when),
          trailing: Text('${f['team_h_difficulty'] ?? '-'} / ${f['team_a_difficulty'] ?? '-'}', style: const TextStyle(color: cyan)),
        ));
      }),
    ]);
  }

  Widget _settingsTab() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('الإعدادات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    _actionCard(Icons.notifications_active, 'اختبار الإشعارات', 'إرسال إشعار تجريبي بعد دقيقة', _scheduleReminder),
    _actionCard(Icons.sync, 'تحديث بيانات FPL', 'تحميل اللاعبين والمباريات من الإنترنت', _loadData),
    _actionCard(Icons.delete_sweep, 'مسح تشكيلتي', 'حذف قائمة اللاعبين المحفوظة على الهاتف', () async {
      setState(() => squadIds.clear());
      await _saveSquad();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم مسح التشكيلة.')));
    }),
    const SizedBox(height: 16),
    const Card(child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('عن التطبيق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      SizedBox(height: 8),
      Text('FPL Arabia — نسخة تجريبية عربية لمتابعة بيانات فانتازي الدوري الإنجليزي.'),
      SizedBox(height: 8),
      Text('غير تابع رسميًا للدوري الإنجليزي الممتاز أو Fantasy Premier League.', style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]))),
  ]);
}
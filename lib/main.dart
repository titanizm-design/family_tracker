import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sensors_plus/sensors_plus.dart';

const String serverUrl = 'http://2.27.194.53:3000';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', 'Семейный трекер',
    description: 'Служба отслеживания', importance: Importance.low,
  );
  
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, autoStart: false, isForegroundMode: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'Семейный трекер', initialNotificationContent: 'Отслеживание активно',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart, onBackground: onIosBackground),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async { return true; }

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  
  service.on('stopService').listen((event) => service.stopSelf());

  final token = prefs.getString('tracker_token');
  if (token == null) return;

  // --- ЛОГИКА УМНОГО ДАТЧИКА ДВИЖЕНИЯ ---
  DateTime lastMovementTime = DateTime.now();
  bool wasMoving = false;
  const double movementThreshold = 0.5; // Порог чувствительности (гравитация = 9.8)

  // Слушаем акселерометр
  accelerometerEventStream().listen((AccelerometerEvent event) {
    // Вычисляем общую силу ускорения
    double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    
    // Если телефон тряхнуло (сила отличается от состояния покоя)
    if ((magnitude - 9.8).abs() > movementThreshold) {
      lastMovementTime = DateTime.now();
      wasMoving = true;
    }
  });

  // Отправляем координаты
  Future<void> sendLocation() async {
    // Проверяем: двигался ли телефон за последние 5 минут?
    if (DateTime.now().difference(lastMovementTime).inMinutes > 5) {
      if (wasMoving) {
        print('Фон: телефон неподвижен 5 минут. GPS спит.');
        wasMoving = false;
      }
      return; // Выходим, не тратим GPS
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _sendToServer(token, position);
    } catch (e) {
      Position? lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) await _sendToServer(token, lastPosition);
    }
  }

  // Запускаем проверку каждую минуту
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    await sendLocation();
  });
}

Future<void> _sendToServer(String token, Position position) async {
  try {
    final response = await http.post(
      Uri.parse('$serverUrl/api/location'),
      headers: {'Content-Type': 'application/json', 'x-auth-token': token},
      body: jsonEncode({
        'lat': position.latitude, 'lon': position.longitude,
        'accuracy': position.accuracy, 'battery': 100,
        'is_charging': false, 'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    print('Фон: отправлено (${response.statusCode})');
  } catch (e) {
    print('Фон: ошибка сети $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Family Tracker', theme: ThemeData(primarySwatch: Colors.blue), home: const SplashScreen());
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  void _checkRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    final token = prefs.getString('token');

    if (role == 'admin' && token != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminMapScreen()));
    } else if (role == 'tracker' && token != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TrackerScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SetupScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  void _loginAsAdmin() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('$serverUrl/api/admin/login'), 
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'password': _controller.text}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('role', 'admin');
        await prefs.setString('token', data['token']);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminMapScreen()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка')));
    }
    setState(() => _isLoading = false);
  }

  void _pairAsTracker() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('$serverUrl/api/pair'), 
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'code': _controller.text}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('role', 'tracker');
        await prefs.setString('token', data['token']);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TrackerScreen()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка')));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройка Family Tracker')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Введите пароль (если вы Админ) или 6-значный код (если вы Трекер):'),
            TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Пароль или код')),
            const SizedBox(height: 20),
            _isLoading ? const CircularProgressIndicator() : Column(
              children: [
                ElevatedButton(onPressed: _loginAsAdmin, child: const Text('Войти как Админ (Пароль)')),
                ElevatedButton(onPressed: _pairAsTracker, child: const Text('Стать Трекером (Код)')),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});
  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  final MapController _mapController = MapController();
  LatLng? _momLocation;
  List<LatLng> _routePoints = [];
  Timer? _timer;
  String? _adminToken;
  LatLng? _lastLocation; 
  bool _autoCenter = true;

  @override
  void initState() {
    super.initState();
    _initAdmin();
  }

  void _initAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    _adminToken = prefs.getString('token');
    
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _fetchMomData();
      await _fetchRouteHistory();
    });
  }

  void _checkMovement(LatLng newLoc) async {
    if (_lastLocation != null) {
      double distance = Geolocator.distanceBetween(
        _lastLocation!.latitude, _lastLocation!.longitude,
        newLoc.latitude, newLoc.longitude
      );
      if (distance > 10) {
        // Уведомление, если нужно, можно раскомментировать
        /*
        await notificationsPlugin.show(
          0, 'Мама в пути!', 'Она переместилась на ${distance.toStringAsFixed(0)} метров.',
          const NotificationDetails(android: AndroidNotificationDetails('move', 'Движение', importance: Importance.max, priority: Priority.high, playSound: true)),
        );
        */
      }
    }
    _lastLocation = newLoc;
  }

  void _fetchMomData() async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/location/mom'),
        headers: {'x-auth-token': _adminToken!},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newLoc = LatLng(data['lat'], data['lon']);
        
        setState(() => _momLocation = newLoc);
        _checkMovement(newLoc);

        if (_autoCenter) {
          _mapController.move(newLoc, _mapController.camera.zoom);
        }
      }
    } catch (e) {}
  }

  void _fetchRouteHistory() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).millisecondsSinceEpoch;
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/history/mom?from=$todayStart&to=$now'),
        headers: {'x-auth-token': _adminToken!},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _routePoints = data.map((e) => LatLng(e['lat'], e['lon'])).toList();
        });
      }
    } catch (e) {}
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SetupScreen()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта мамы'),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.exit_to_app))],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _momLocation ?? const LatLng(55.75, 37.61),
              initialZoom: 15.0,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) setState(() => _autoCenter = false);
              },
            ),
            children: [
              TileLayer(urlTemplate: 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png'),
              if (_routePoints.isNotEmpty)
                PolylineLayer(polylines: [Polyline(points: _routePoints, strokeWidth: 4.0, color: Colors.blue)]),
              if (_momLocation != null)
                MarkerLayer(markers: [
                  Marker(point: _momLocation!, width: 40, height: 40, child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
                ]),
            ],
          ),
          Positioned(
            bottom: 20, right: 20,
            child: FloatingActionButton(
              onPressed: () {
                setState(() => _autoCenter = true);
                if (_momLocation != null) _mapController.move(_momLocation!, _mapController.camera.zoom);
              },
              child: Icon(_autoCenter ? Icons.gps_fixed : Icons.gps_not_fixed),
            ),
          ),
        ],
      ),
    );
  }
}

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});
  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  String? _trackerToken;

  @override
  void initState() {
    super.initState();
    _initTracker();
  }

  void _initTracker() async {
    final prefs = await SharedPreferences.getInstance();
    _trackerToken = prefs.getString('token');
    FlutterBackgroundService().startService();
  }

  void _fetchAdminLocation() async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/location/admin'),
        headers: {'x-auth-token': _trackerToken!},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final adminLocation = LatLng(data['lat'], data['lon']);
        Navigator.push(context, MaterialPageRoute(builder: (_) => AdminLocationScreen(location: adminLocation)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось найти местоположение')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка сети')));
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    FlutterBackgroundService().invoke("stopService");
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Режим Трекера'),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.exit_to_app))],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text('Вы подключены к семье', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                textStyle: const TextStyle(fontSize: 24),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.person_pin_circle, size: 40),
              label: const Text('ГДЕ СЫН?'),
              onPressed: _fetchAdminLocation,
            ),
          ],
        ),
      ),
    );
  }
}

class AdminLocationScreen extends StatelessWidget {
  final LatLng location;
  const AdminLocationScreen({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Местоположение сына')),
      body: FlutterMap(
        options: MapOptions(initialCenter: location, initialZoom: 16.0),
        children: [
          TileLayer(urlTemplate: 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png'),
          MarkerLayer(markers: [
            Marker(point: location, width: 40, height: 40, child: const Icon(Icons.location_on, color: Colors.blue, size: 40)),
          ]),
        ],
      ),
    );
  }
}
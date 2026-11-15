import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const StartScreen(),
    );
  }
}

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family Tracker'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Я Наблюдатель (Админ)'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLoginScreen())),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.phone_android),
              label: const Text('Я Трекер (Телефон мамы)'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackerScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _passController = TextEditingController();
  final String serverUrl = 'http://2.27.194.53:3000';
  bool _isLoading = false;

  void _login() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/api/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': _passController.text}),
      );
      if (response.statusCode == 200) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminMapScreen()));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверный пароль')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сети: $e')));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход Админа')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _passController,
              decoration: const InputDecoration(labelText: 'Мастер-пароль (admin123)'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _login, child: const Text('Войти')),
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
  final String serverUrl = 'http://2.27.194.53:3000';
  LatLng? _momLocation;
  Timer? _timer;
  String? _pairingCode;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) => _fetchMomLocation());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _generateCode() async {
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/api/admin/generate-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': 'admin123'}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _pairingCode = data['code']);
      }
    } catch (e) {
      debugPrint('Ошибка генерации кода: $e');
    }
  }

  void _fetchMomLocation() async {
    try {
      final token = '58f61cb290eeec9e77cfd825dd4a2f9f735c553400ee0ef3'; 
      
      final response = await http.get(
        Uri.parse('$serverUrl/api/location/mom'),
        headers: {'x-auth-token': token},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _momLocation = LatLng(data['lat'], data['lon']);
        });
      }
    } catch (e) {
      // Игнорируем
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Карта мамы')),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _momLocation ?? const LatLng(55.75, 37.61),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.family_tracker',
              ),
              if (_momLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _momLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_pairingCode != null)
                      Text('Код для мамы: $_pairingCode', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_link),
                      label: const Text('Создать код привязки'),
                      onPressed: _generateCode,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- ЭКРАН ТРЕКЕРА ---
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  final TextEditingController _codeController = TextEditingController();
  final String serverUrl = 'http://2.27.194.53:3000';
  bool _isTracking = false;
  Timer? _locationTimer;
  String? _token;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
  }

  void _loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('tracker_token');
    if (savedToken != null) {
      setState(() => _token = savedToken);
    }
  }

  void _pairDevice() async {
    setState(() {
      _isTracking = true;
      _statusMessage = 'Отправка кода на сервер...';
    });
    
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/api/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': _codeController.text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newToken = data['token'];
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('tracker_token', newToken);
        
        setState(() {
          _token = newToken;
          _statusMessage = 'Устройство привязано!';
        });
        
        _startTracking();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Устройство привязано!')));
      } else {
        setState(() {
          _isTracking = false;
          _statusMessage = 'Сервер отклонил код';
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неверный код')));
      }
    } catch (e) {
      setState(() {
        _isTracking = false;
        _statusMessage = 'Ошибка: $e';
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  void _startTracking() async {
    if (_token == null) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = 'Нет разрешения на GPS');
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      setState(() => _statusMessage = 'GPS заблокирован навсегда. Разрешите в настройках');
      return;
    }

    setState(() => _statusMessage = 'GPS включен. Ждем первый сигнал...');

    // Отправляем координаты сразу при запуске
    _sendCurrentLocation();

    // И запускаем таймер каждые 60 секунд
    _locationTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      _sendCurrentLocation();
    });
  }

  void _sendCurrentLocation() async {
    try {
      setState(() => _statusMessage = 'Получаем координаты...');
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
      );
      
      setState(() => _statusMessage = 'Отправка на сервер...');

      final response = await http.post(
        Uri.parse('$serverUrl/api/location'),
        headers: {
          'Content-Type': 'application/json',
          'x-auth-token': _token!,
        },
        body: jsonEncode({
          'lat': position.latitude,
          'lon': position.longitude,
          'accuracy': position.accuracy,
          'battery': 100,
          'is_charging': false,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );

      if (response.statusCode == 200) {
        setState(() => _statusMessage = 'Координаты отправлены!');
      } else {
        setState(() => _statusMessage = 'Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Ошибка отправки: $e');
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Режим Трекера')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_token == null) ...[
              const Text('Введите код, который вам продиктовал Админ:', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 10),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '6-значный код', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              _isTracking 
                ? const CircularProgressIndicator() 
                : ElevatedButton(onPressed: _pairDevice, child: const Text('Подключиться к семье')),
            ] else ...[
              Icon(_isTracking ? Icons.gps_fixed : Icons.check_circle, color: Colors.green, size: 80),
              const SizedBox(height: 20),
              const Text('Устройство успешно привязано!', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 10),
              Text('Статус: $_statusMessage', style: const TextStyle(color: Colors.blue, fontSize: 16)),
              const SizedBox(height: 20),
              if (_isTracking)
                ElevatedButton(
                  onPressed: _sendCurrentLocation, 
                  child: const Text('Отправить координаты сейчас')
                )
            ]
          ],
        ),
      ),
    );
  }
}
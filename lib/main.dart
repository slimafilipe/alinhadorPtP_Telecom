import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const CompassApp());
}

class CompassApp extends StatelessWidget {
  const CompassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alinhador Telecom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6C63FF),
          secondary: const Color(0xFF00D4FF),
          surface: const Color(0xFF1A1F37),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1F37).withValues(alpha: 0.6),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1F37).withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF00D4FF), width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 5,
          ),
        ),
      ),
      home: const CompassHomePage(),
    );
  }
}

class CompassHomePage extends StatefulWidget {
  const CompassHomePage({super.key});

  @override
  State<CompassHomePage> createState() => _CompassHomePageState();
}

class _CompassHomePageState extends State<CompassHomePage> with SingleTickerProviderStateMixin {
  // Controllers
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();
  
  // State variables
  Position? _currentPosition;
  double? _targetLat;
  double? _targetLon;
  double? _compassHeading;
  double _targetBearing = 0;
  bool _compassAvailable = false;
  bool _needsCalibration = false;
  bool _usingGpsHeading = false;
  double _distance = 0;
  bool _isTracking = false;
  String _statusMessage = 'Aguardando coordenadas...';
  
  // Streams
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  
  // Animation
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _checkPermissions();
    _checkCompassAvailability();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _positionStream?.cancel();
    _compassStream?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    // Check location permission
    final locationStatus = await Permission.location.request();
    
    if (!locationStatus.isGranted) {
      setState(() {
        _statusMessage = 'Permissão de localização necessária';
      });
      return;
    }
    
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = 'Ative o serviço de localização';
      });
      return;
    }
    
    setState(() {
      _statusMessage = 'Permissões concedidas';
    });
  }

  Future<void> _checkCompassAvailability() async {
    try {
      final compassEvent = await FlutterCompass.events?.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw Exception('No compass sensor'),
      );
      
      // Check if heading is always 0 (sensor not working)
      if (compassEvent?.heading == null || compassEvent!.heading == 0.0) {
        setState(() {
          _compassAvailable = false;
          _statusMessage = 'Usando GPS para navegação';
        });
        print('⚠️ Magnetometer not available, will use GPS heading');
      } else {
        setState(() {
          _compassAvailable = true;
        });
        print('🧭 Compass available: $_compassAvailable');
      }
    } catch (e) {
      print('❌ No magnetometer detected: $e');
      setState(() {
        _compassAvailable = false;
        _statusMessage = 'Usando GPS para navegação';
      });
    }
  }

  void _startTracking() async {
    if (_latController.text.isEmpty || _lonController.text.isEmpty) {
      _showSnackBar('Por favor, insira as coordenadas de destino');
      return;
    }

    try {
      _targetLat = double.parse(_latController.text);
      _targetLon = double.parse(_lonController.text);
      
      // Validate coordinates
      if (_targetLat! < -90 || _targetLat! > 90 || 
          _targetLon! < -180 || _targetLon! > 180) {
        _showSnackBar('Coordenadas inválidas');
        return;
      }
    } catch (e) {
      _showSnackBar('Formato de coordenadas inválido');
      return;
    }

    setState(() {
      _isTracking = true;
      _statusMessage = 'Rastreando...';
    });

    // Start position stream
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen((Position position) {
      setState(() {
        _currentPosition = position;
        
        // If device has no magnetometer, use GPS heading when moving
        if (!_compassAvailable && position.heading != null && position.heading >= 0) {
          _compassHeading = position.heading;
          _usingGpsHeading = true;
          print('📍 Using GPS heading: ${position.heading}°');
        }
        
        _calculateBearingAndDistance();
      });
    });

    // Start compass stream
    print('🧭 Starting compass stream...');
    int zeroCount = 0;
    _compassStream = FlutterCompass.events?.listen(
      (CompassEvent event) {
        print('🧭 Compass event: heading=${event.heading}, accuracy=${event.accuracy}');
        setState(() {
          // Some devices return null, use 0 as fallback
          final heading = event.heading ?? 0;
          _compassHeading = heading;
          
          // Detect if compass needs calibration (stuck at 0)
          if (heading == 0.0) {
            zeroCount++;
            if (zeroCount > 10) {  // After 10 readings at 0, show calibration warning
              _needsCalibration = true;
            }
          } else {
            zeroCount = 0;
            _needsCalibration = false;
          }
        });
      },
      onError: (error) {
        print('❌ Compass error: $error');
        setState(() {
          _statusMessage = 'Erro no sensor de bússola';
        });
      },
      cancelOnError: false,
    );
    
    if (_compassStream == null) {
      print('⚠️ Compass stream is null - sensor may not be available');
      setState(() {
        _statusMessage = 'Sensor de bússola não disponível';
      });
    }
  }

  void _stopTracking() {
    setState(() {
      _isTracking = false;
      _statusMessage = 'Rastreamento pausado';
    });
    
    _positionStream?.cancel();
    _compassStream?.cancel();
  }

  void _calculateBearingAndDistance() {
    if (_currentPosition == null || _targetLat == null || _targetLon == null) {
      return;
    }

    final lat1 = _currentPosition!.latitude * pi / 180;
    final lat2 = _targetLat! * pi / 180;
    final lon1 = _currentPosition!.longitude * pi / 180;
    final lon2 = _targetLon! * pi / 180;

    // Calculate bearing
    final dLon = lon2 - lon1;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final bearing = atan2(y, x) * 180 / pi;
    _targetBearing = (bearing + 360) % 360;

    // Calculate distance using Haversine formula
    final dLat = lat2 - lat1;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    _distance = 6371000 * c; // Earth radius in meters

    setState(() {
      _statusMessage = 'Distância: ${_formatDistance(_distance)}';
    });
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate arrow rotation
    double arrowRotation = _targetBearing;
    if (_compassHeading != null) {
      arrowRotation = _targetBearing - _compassHeading!;
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0A0E21),
              const Color(0xFF1A1F37),
              const Color(0xFF0A0E21),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                Text(
                  '🧭 Bússola Georreferenciada',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    foreground: Paint()
                      ..shader = const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
                      ).createShader(const Rect.fromLTWH(0, 0, 300, 70)),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // Compass Display
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Compass Circle
                        Container(
                          width: 280,
                          height: 280,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFF6C63FF).withValues(alpha: 0.2),
                                const Color(0xFF1A1F37),
                              ],
                            ),
                            border: Border.all(
                              color: const Color(0xFF6C63FF),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Cardinal directions
                              Positioned(top: 10, child: _buildDirectionLabel('N')),
                              Positioned(bottom: 10, child: _buildDirectionLabel('S')),
                              Positioned(left: 10, child: _buildDirectionLabel('O')),
                              Positioned(right: 10, child: _buildDirectionLabel('L')),
                              
                              // Arrow
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: arrowRotation),
                                duration: const Duration(milliseconds: 300),
                                builder: (context, value, child) {
                                  return Transform.rotate(
                                    angle: value * pi / 180,
                                    child: Icon(
                                      Icons.navigation,
                                      size: 80,
                                      color: _isTracking
                                          ? const Color(0xFF00D4FF)
                                          : Colors.grey,
                                      shadows: [
                                        Shadow(
                                          color: const Color(0xFF00D4FF).withValues(alpha: 0.5),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Status and bearing info
                        Text(
                          _statusMessage,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF00D4FF),
                          ),
                        ),
                        if (!_compassAvailable && _isTracking)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue, width: 1),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue, size: 16),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Usando GPS (caminhe para obter direção)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_needsCalibration && _isTracking && _compassAvailable)
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange, width: 1),
                            ),
                            child: Column(
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Bússola precisa de calibração',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Mova o celular em forma de "8" no ar várias vezes',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        if (_isTracking && _compassHeading != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Direção alvo: ${_targetBearing.toStringAsFixed(0)}°',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Heading atual: ${_compassHeading!.toStringAsFixed(0)}°',
                            style: TextStyle(
                              fontSize: 12,
                              color: _compassHeading == 0.0 ? Colors.orange : Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Coordinates Input
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Coordenadas de Destino',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: _latController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            hintText: 'Ex: -23.5505',
                            prefixIcon: Icon(Icons.location_on),
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: _lonController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            hintText: 'Ex: -46.6333',
                            prefixIcon: Icon(Icons.location_on),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Current Position Display
                if (_currentPosition != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Posição Atual',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.my_location, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}\n'
                                  'Lon: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // Control Button
                ElevatedButton.icon(
                  onPressed: _isTracking ? _stopTracking : _startTracking,
                  icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                  label: Text(
                    _isTracking ? 'Parar Rastreamento' : 'Iniciar Rastreamento',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isTracking
                        ? Colors.red.shade400
                        : const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionLabel(String label) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

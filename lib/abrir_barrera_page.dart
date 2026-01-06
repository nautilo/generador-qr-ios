import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class AbrirBarreraPage extends StatefulWidget {
  final String rutUsuario;
  const AbrirBarreraPage({super.key, required this.rutUsuario});

  @override
  State<AbrirBarreraPage> createState() => _AbrirBarreraPageState();
}

class _AbrirBarreraPageState extends State<AbrirBarreraPage> {
  // ✅ Pon aquí los UUID reales de tu ESP32 BLE
  // Ejemplo típico: servicio custom + característica writable
  final Guid _serviceUuid = Guid("0000ffff-0000-1000-8000-00805f9b34fb");
  final Guid _charUuid = Guid("0000ff01-0000-1000-8000-00805f9b34fb");

  String mensaje = '🔍 Preparando Bluetooth...';
  bool _scanning = false;

  // Resultados de escaneo BLE
  final List<ScanResult> _scanResults = [];
  ScanResult? _selected;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  @override
  void initState() {
    super.initState();
    _initBleFlow();
  }

  Future<void> _initBleFlow() async {
    // Estado del adaptador (iOS/Android)
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() {
        if (state == BluetoothAdapterState.on) {
          mensaje = '✅ Bluetooth encendido. Puedes escanear.';
        } else {
          mensaje = '⚠️ Bluetooth está apagado o no disponible: $state';
        }
      });
    });

    // Pedir permisos SOLO en Android (iOS lo maneja diferente)
    if (Platform.isAndroid) {
      await _pedirPermisosAndroidBle();
    }

    // Suscribirse a resultados de escaneo
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;

      // Actualiza lista sin duplicados por deviceId
      for (final r in results) {
        final idx = _scanResults.indexWhere((x) => x.device.remoteId == r.device.remoteId);
        if (idx >= 0) {
          _scanResults[idx] = r;
        } else {
          _scanResults.add(r);
        }
      }

      setState(() {});
    });

    // Arranca escaneo de inmediato (como tu app original)
    await _iniciarEscaneo();
  }

  Future<void> _pedirPermisosAndroidBle() async {
    // Android 12+ usa bluetoothScan/bluetoothConnect. En versiones antiguas puede requerir Location.
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // por compatibilidad con Android < 12 y ciertos vendors
    ].request();
  }

  Future<void> _iniciarEscaneo() async {
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      setState(() {
        mensaje = '⚠️ Enciende Bluetooth para escanear (estado: $state)';
      });
      return;
    }

    setState(() {
      mensaje = '🔍 Escaneando dispositivos BLE...';
      _scanResults.clear();
      _selected = null;
      _scanning = true;
    });

    try {
      // Detén escaneo previo si existía
      await FlutterBluePlus.stopScan();

      // Escanea por 6 segundos
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

      // startScan con timeout se detiene solo, pero por seguridad:
      await FlutterBluePlus.stopScan();

      if (!mounted) return;
      setState(() {
        _scanning = false;
        mensaje = _scanResults.isEmpty ? '❌ No se detectaron dispositivos' : '✅ Escaneo completado';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        mensaje = '❌ Error escaneando BLE:\n$e';
      });
    }
  }

  Future<void> _conectarYEnviarBle() async {
    final selected = _selected;
    if (selected == null) {
      setState(() => mensaje = '⚠️ Selecciona un dispositivo');
      return;
    }

    final device = selected.device;

    try {
      setState(() => mensaje = '🔌 Conectando a ${device.platformName.isEmpty ? device.remoteId.str : device.platformName}...');

      // Conectar (corto y con timeout)
      await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);

      // Descubrir servicios
      final services = await device.discoverServices();

      // Buscar el servicio objetivo
      final service = services.where((s) => s.uuid == _serviceUuid).toList();
      if (service.isEmpty) {
        throw Exception('No encontré el servicio BLE $_serviceUuid en el dispositivo.');
      }

      // Buscar characteristic writable
      final chars = service.first.characteristics.where((c) => c.uuid == _charUuid).toList();
      if (chars.isEmpty) {
        throw Exception('No encontré la characteristic $_charUuid dentro del servicio $_serviceUuid.');
      }

      final ch = chars.first;

      // Verifica que permita escritura
      if (!(ch.properties.write || ch.properties.writeWithoutResponse)) {
        throw Exception('La characteristic existe, pero no permite WRITE.');
      }

      // Enviar comando "abrir\n" como bytes UTF-8
      final payload = utf8.encode("abrir\n");

      if (ch.properties.writeWithoutResponse) {
        await ch.write(payload, withoutResponse: true);
      } else {
        await ch.write(payload, withoutResponse: false);
      }

      if (!mounted) return;
      setState(() {
        mensaje = '✅ Señal BLE enviada a ${device.platformName.isEmpty ? device.remoteId.str : device.platformName}';
      });

      // Desconectar
      await device.disconnect();
    } catch (e) {
      // Asegura desconexión si falló a medias
      try {
        await selected.device.disconnect();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        mensaje = '❌ Error BLE:\n$e';
      });
    }
  }

  Future<void> _enviarSenalWifi() async {
    try {
      final response = await http.get(Uri.parse('http://192.168.4.1/abrir'));
      if (response.statusCode == 200) {
        setState(() => mensaje = '✅ Señal enviada por Wi-Fi');
      } else {
        setState(() => mensaje = '❌ Error Wi-Fi: Código ${response.statusCode}');
      }
    } catch (e) {
      setState(() => mensaje = '❌ Error Wi-Fi:\n$e');
    }
  }

  String _displayName(ScanResult r) {
    final name = r.device.platformName.trim();
    if (name.isNotEmpty) return name;
    return r.device.remoteId.str;
  }

  @override
  void dispose() {
    // Detener escaneo y cerrar subs
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abrir Barrera'),
        actions: [
          IconButton(
            onPressed: _iniciarEscaneo,
            icon: const Icon(Icons.refresh),
            tooltip: "Volver a escanear",
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mensaje, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),

            const Text(
              "📡 Dispositivos BLE disponibles",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            if (_scanning) const Center(child: CircularProgressIndicator()),

            if (!_scanning && _scanResults.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _scanResults.length,
                itemBuilder: (context, index) {
                  final r = _scanResults[index];
                  return ListTile(
                    leading: const Icon(Icons.bluetooth_searching, color: Colors.black54),
                    title: Text(_displayName(r)),
                    subtitle: Text(r.device.remoteId.str),
                    trailing: Radio<ScanResult>(
                      value: r,
                      groupValue: _selected,
                      onChanged: (val) => setState(() => _selected = val),
                    ),
                  );
                },
              ),

            if (!_scanning && _scanResults.isEmpty)
              const Text("No se detectaron dispositivos"),

            const SizedBox(height: 30),

            Center(
              child: Column(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _conectarYEnviarBle,
                    icon: const Icon(Icons.bluetooth),
                    label: const Text(
                      'Abrir por Bluetooth (BLE)',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _enviarSenalWifi,
                    icon: const Icon(Icons.wifi),
                    label: const Text(
                      'Abrir por Wi-Fi',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

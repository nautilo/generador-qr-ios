import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class AbrirBarreraPage extends StatefulWidget {
  final String rutUsuario;
  const AbrirBarreraPage({super.key, required this.rutUsuario});

  @override
  State<AbrirBarreraPage> createState() => _AbrirBarreraPageState();
}

class _AbrirBarreraPageState extends State<AbrirBarreraPage> {
  BluetoothConnection? _connection;
  String mensaje = '🔍 Escaneando dispositivos...';
  bool _seEnvioBluetooth = false;

  List<BluetoothDevice> _bondedDevices = [];
  List<BluetoothDiscoveryResult> _discoveredDevices = [];
  BluetoothDevice? _selectedBonded;
  BluetoothDiscoveryResult? _selectedDiscovered;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _pedirPermisosBluetooth().then((_) {
      _cargarVinculados();
      _iniciarEscaneo();
    });
  }

  Future<void> _pedirPermisosBluetooth() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location
    ].request();
  }

  Future<void> _cargarVinculados() async {
    try {
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() => _bondedDevices = bonded);
    } catch (e) {
      setState(() => mensaje = '❌ Error al cargar vinculados:\n$e');
    }
  }

  void _iniciarEscaneo() {
    setState(() {
      mensaje = '🔍 Escaneando dispositivos...';
      _discoveredDevices.clear();
      _scanning = true;
    });

    FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
      setState(() {
        final existingIndex = _discoveredDevices.indexWhere(
              (d) => d.device.address == r.device.address,
        );
        if (existingIndex >= 0) {
          _discoveredDevices[existingIndex] = r;
        } else {
          _discoveredDevices.add(r);
        }
      });
    }).onDone(() {
      setState(() {
        _scanning = false;
        mensaje = '✅ Escaneo completado';
      });
    });
  }

  Future<void> _conectarYEnviarBluetooth() async {
    final device = _selectedBonded ??
        (_selectedDiscovered != null ? _selectedDiscovered!.device : null);

    if (device == null) {
      setState(() => mensaje = '⚠️ Selecciona un dispositivo');
      return;
    }

    try {
      final connection = await BluetoothConnection.toAddress(device.address);
      connection.output.add(ascii.encode("abrir\n"));
      await connection.output.allSent;

      setState(() {
        mensaje = '✅ Señal enviada a ${device.name ?? device.address}';
        _seEnvioBluetooth = true;
      });

      await Future.delayed(const Duration(milliseconds: 500));
      await connection.close();
    } catch (e) {
      if (!_seEnvioBluetooth) {
        setState(() =>
        mensaje = '❌ Error con ${device.name ?? device.address}:\n$e');
      }
    }
  }

  Future<void> _enviarSenalWifi() async {
    try {
      final response = await http.get(Uri.parse('http://192.168.4.1/abrir'));
      if (response.statusCode == 200) {
        setState(() => mensaje = '✅ Señal enviada por Wi-Fi');
      } else {
        setState(() =>
        mensaje = '❌ Error Wi-Fi: Código ${response.statusCode}');
      }
    } catch (e) {
      setState(() => mensaje = '❌ Error Wi-Fi:\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abrir Barrera'),
        actions: [
          IconButton(
            onPressed: () {
              _cargarVinculados();
              _iniciarEscaneo();
            },
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

            // 🔹 Lista de dispositivos vinculados
            if (_bondedDevices.isNotEmpty) ...[
              const Text(
                "🔗 Dispositivos vinculados",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _bondedDevices.length,
                itemBuilder: (context, index) {
                  final device = _bondedDevices[index];
                  return ListTile(
                    leading: const Icon(Icons.devices_other,
                        color: Colors.black54),
                    title: Text(device.name ?? "Sin nombre"),
                    subtitle: Text(device.address),
                    trailing: Radio<BluetoothDevice>(
                      value: device,
                      groupValue: _selectedBonded,
                      onChanged: (val) {
                        setState(() {
                          _selectedBonded = val;
                          _selectedDiscovered = null;
                        });
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],

            // 🔹 Lista de dispositivos descubiertos
            const Text(
              "📡 Dispositivos disponibles",
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 8),
            if (_scanning) const Center(child: CircularProgressIndicator()),
            if (!_scanning && _discoveredDevices.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _discoveredDevices.length,
                itemBuilder: (context, index) {
                  final r = _discoveredDevices[index];
                  final device = r.device;
                  return ListTile(
                    leading: const Icon(Icons.bluetooth_searching,
                        color: Colors.black54),
                    title: Text(device.name ?? "Sin nombre"),
                    subtitle: Text(device.address),
                    trailing: Radio<BluetoothDiscoveryResult>(
                      value: r,
                      groupValue: _selectedDiscovered,
                      onChanged: (val) {
                        setState(() {
                          _selectedDiscovered = val;
                          _selectedBonded = null;
                        });
                      },
                    ),
                  );
                },
              ),
            if (!_scanning && _discoveredDevices.isEmpty)
              const Text("No se detectaron dispositivos"),

            const SizedBox(height: 30),

            // 🔹 Botones sobrios
            Center(
              child: Column(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _conectarYEnviarBluetooth,
                    icon: const Icon(Icons.bluetooth),
                    label: const Text(
                      'Abrir por Bluetooth',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 15),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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

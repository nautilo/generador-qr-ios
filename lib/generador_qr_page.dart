import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

class GeneradorQRPage extends StatefulWidget {
  final String rutUsuario;

  const GeneradorQRPage({super.key, required this.rutUsuario});

  @override
  _GeneradorQRPageState createState() => _GeneradorQRPageState();
}

class _GeneradorQRPageState extends State<GeneradorQRPage> {
  final _nombreCtrl = TextEditingController();
  final _apellidoCtrl = TextEditingController();
  final _rutCtrl = TextEditingController();
  final _patenteCtrl = TextEditingController();

  bool invitacionEterna = false;

  String? selectedTipoVisita;
  String? selectedDestino;
  List<dynamic> tiposVisita = [];
  List<dynamic> destinos = [];

  String? qrBase64;
  String? qrTexto;
  String? mensajeError;
  String? invitacionId;
  Timer? qrTimer;

  DateTime fechaDesde = DateTime.now();
  DateTime fechaHasta = DateTime.now().add(Duration(hours: 2));

  final String baseUrl = 'http://209.46.126.62:9999';

  @override
  void initState() {
    super.initState();
    cargarOpciones();
  }

  @override
  void dispose() {
    qrTimer?.cancel();
    super.dispose();
  }

  Future<void> cargarOpciones() async {
    final response = await http.get(Uri.parse('$baseUrl/qr/obtener_opciones'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        tiposVisita = data['tipos_visita'];
        destinos = data['tipos_destino'];
      });
    } else {
      setState(() {
        mensajeError = 'Error al cargar opciones';
      });
    }
  }

  Future<void> generarInvitacion() async {
    final url = Uri.parse('$baseUrl/api/generar_invitacion_api');

    final body = {
      'nombre': _nombreCtrl.text,
      'rut': _rutCtrl.text,
      'apellido1': _apellidoCtrl.text,
      'tipo_visita': selectedTipoVisita,
      'tipo_destino': selectedDestino,
      'fecha_desde': fechaDesde.toIso8601String(),
      'fecha_hasta': invitacionEterna ? '2099-12-31T23:59:00' : fechaHasta.toIso8601String(),
      'patente': _patenteCtrl.text,
      'rut_usuario': widget.rutUsuario
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        invitacionId = data['invitacion_id'];
      });
      await obtenerQR();
      iniciarAutoRefreshQR();
    } else {
      setState(() {
        mensajeError = 'Error al generar la invitación: ${response.body}';
      });
    }
  }

  Future<void> obtenerQR() async {
    if (invitacionId == null) return;
    final response = await http.get(Uri.parse('$baseUrl/qr/qr_dynamic/$invitacionId'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        qrBase64 = data['qr_base64'];
        qrTexto = data['qr_data'];
        mensajeError = null;
      });
    } else {
      setState(() {
        mensajeError = 'Error al obtener QR: ${response.body}';
      });
    }
  }

  void iniciarAutoRefreshQR() {
    qrTimer?.cancel();
    qrTimer = Timer.periodic(Duration(seconds: 10), (_) => obtenerQR());
  }

  Future<void> seleccionarFechaDesde() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: fechaDesde,
      firstDate: DateTime.now(),
      lastDate: DateTime(2099),
    );
    if (picked != null) setState(() => fechaDesde = picked);
  }

  Future<void> seleccionarFechaHasta() async {
    if (invitacionEterna) return;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: fechaHasta,
      firstDate: fechaDesde,
      lastDate: DateTime(2099),
    );
    if (picked != null) setState(() => fechaHasta = picked);
  }

  void compartirQRWeb() {
    if (invitacionId != null) {
      final urlCompartir = '$baseUrl/qr/ver_qr/$invitacionId';
      Share.share('Aquí está tu QR de invitación: $urlCompartir');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generador QR')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 10),
            TextField(controller: _apellidoCtrl, decoration: const InputDecoration(labelText: 'Apellido')),
            const SizedBox(height: 10),
            TextField(controller: _rutCtrl, decoration: const InputDecoration(labelText: 'RUT')),
            const SizedBox(height: 10),
            TextField(controller: _patenteCtrl, decoration: const InputDecoration(labelText: 'Patente')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Tipo de Visita'),
              value: selectedTipoVisita,
              items: tiposVisita
                  .map((item) => DropdownMenuItem(
                value: item['id_tipo_visita'].toString(),
                child: Text(item['nombre']),
              ))
                  .toList(),
              onChanged: (val) => setState(() => selectedTipoVisita = val),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Destino'),
              value: selectedDestino,
              items: destinos
                  .map((item) => DropdownMenuItem(
                value: item['id'].toString(),
                child: Text(item['nombre']),
              ))
                  .toList(),
              onChanged: (val) => setState(() => selectedDestino = val),
            ),
            Row(
              children: [
                Checkbox(
                  value: invitacionEterna,
                  onChanged: (value) => setState(() => invitacionEterna = value ?? false),
                ),
                const Text('Invitación eterna')
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: seleccionarFechaDesde,
                    child: Text('Desde: ${fechaDesde.toLocal().toString().split(" ")[0]}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: invitacionEterna ? null : seleccionarFechaHasta,
                    child: Text('Hasta: ${fechaHasta.toLocal().toString().split(" ")[0]}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: generarInvitacion,
                child: const Text('Generar QR'),
              ),
            ),
            if (mensajeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(mensajeError!, style: const TextStyle(color: Colors.red)),
              ),
            if (qrBase64 != null)
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 30),
                    const Text('Código QR de Invitación', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Image.memory(base64Decode(qrBase64!), width: 200, height: 200),
                    const SizedBox(height: 10),
                    Text(qrTexto ?? '', style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: compartirQRWeb,
                      icon: Icon(Icons.share),
                      label: Text('Compartir enlace'),
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

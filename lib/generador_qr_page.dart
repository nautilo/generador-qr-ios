import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'app_config.dart';

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

  // NUEVO: acompañantes
  bool vieneConCompania = false;
  int numAcompanantes = 0; // 0 = sin compañía
  final _acompanantesCtrl = TextEditingController(); // nombres opcionales

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

  // --- Fechas ---
  DateTime fechaDesde = DateTime.now();
  DateTime fechaHasta = DateTime.now().add(const Duration(hours: 2));

  // NUEVO: modo auto para "Desde"
  bool autoFechaDesde = true;
  Timer? _autoDesdeTimer;
  @override
  void initState() {
    super.initState();

    // Inicializamos "desde" con la hora actual exacta (con segundos)
    fechaDesde = _nowExact();

    // Que "hasta" siempre quede después
    if (!invitacionEterna && !fechaHasta.isAfter(fechaDesde)) {
      fechaHasta = fechaDesde.add(const Duration(hours: 2));
    }

    // Arrancar timer que mantiene "desde" actualizada cada segundo si no hay selección manual
    _autoDesdeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (autoFechaDesde) {
        setState(() {
          fechaDesde = _nowExact(); // ahora exacto con segundos
          if (!invitacionEterna && !fechaHasta.isAfter(fechaDesde)) {
            fechaHasta = fechaDesde.add(const Duration(hours: 2));
          }
        });
      }
    });

    cargarOpciones();
  }


  @override
  void dispose() {
    qrTimer?.cancel();
    _autoDesdeTimer?.cancel();
    _acompanantesCtrl.dispose();
    super.dispose();
  }

// === Helpers de fecha ===
  DateTime _nowExact() {
    // Devuelve la hora actual exacta con segundos y milisegundos
    return DateTime.now();
  }

  // === Carga de opciones ===
  Future<void> cargarOpciones() async {
    final response = await http.get(AppConfig.uri('/qr/obtener_opciones'));
    if (!mounted) return;
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        tiposVisita = data['tipos_visita'];
        destinos = data['tipos_destino'];
      });
    } else {
      setState(() => mensajeError = 'Error al cargar opciones');
    }
  }
// === Generar invitación ===
  Future<void> generarInvitacion() async {
    // Si seguimos en modo auto, recalcular "desde" al instante exacto del envío
    if (autoFechaDesde) {
      setState(() {
        fechaDesde = _nowExact(); // <-- hora actual con segundos
      });
    }

    // Asegurar que "hasta" > "desde" para no pegar con validación
    if (!invitacionEterna && !fechaHasta.isAfter(fechaDesde)) {
      setState(() {
        fechaHasta = fechaDesde.add(const Duration(hours: 2));
      });
    }

    // Validaciones
// if (fechaDesde.isBefore(DateTime.now())) {
//   setState(() => mensajeError = 'La fecha desde no puede ser anterior a la hora actual');
//   return;
// }

    if (!invitacionEterna && fechaHasta.isBefore(fechaDesde)) {
      setState(() => mensajeError = 'La fecha hasta no puede ser anterior a la fecha desde');
      return;
    }
    if (vieneConCompania && (numAcompanantes <= 0)) {
      setState(() => mensajeError = 'Indica cuántas personas acompañan');
      return;
    }

    final url = AppConfig.uri('/api/generar_invitacion_api');

    final body = {
      'nombre': _nombreCtrl.text,
      'rut': _rutCtrl.text,
      'apellido1': _apellidoCtrl.text,
      'tipo_visita': selectedTipoVisita,
      'tipo_destino': selectedDestino,
      'fecha_desde': fechaDesde.toIso8601String(),
      'fecha_hasta': invitacionEterna
          ? '2099-12-31T23:59:00'
          : fechaHasta.toIso8601String(),
      'patente': _patenteCtrl.text,
      'rut_usuario': widget.rutUsuario,
      'eterno': invitacionEterna,
      // Acompañantes
      'num_acompanantes': vieneConCompania ? numAcompanantes : 0,
      'acompanantes': _acompanantesCtrl.text.trim(),
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (!mounted) return;
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        invitacionId = data['invitacion_id'];
        mensajeError = null;
      });
      await obtenerQR();
      iniciarAutoRefreshQR();
    } else {
      setState(() =>
      mensajeError = 'Error al generar la invitación: ${response.body}');
    }
  }


  Future<void> obtenerQR() async {
    if (invitacionId == null) return;
    final response = await http.get(AppConfig.uri('/qr/qr_dynamic/$invitacionId'));
    if (!mounted) return;
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        qrBase64 = data['qr_base64'];
        qrTexto = data['qr_data'];
        mensajeError = null;
      });
    } else {
      setState(() => mensajeError = 'Error al obtener QR: ${response.body}');
    }
  }

  void iniciarAutoRefreshQR() {
    qrTimer?.cancel();
    qrTimer = Timer.periodic(const Duration(seconds: 10), (_) => obtenerQR());
  }

  // === Pickers ===
  Future<void> seleccionarFechaDesde() async {
    // Al tocar, entendemos que quiere fijar manualmente -> desactivar auto
    setState(() => autoFechaDesde = false);

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: fechaDesde,
      firstDate: DateTime.now(),
      lastDate: DateTime(2099),
    );
    if (pickedDate == null) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.input,
      helpText: 'Seleccionar tiempo',
      initialTime: TimeOfDay.fromDateTime(fechaDesde),
    );
    if (pickedTime == null) return;

    setState(() {
      fechaDesde = DateTime(
        pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute,
      );
      if (!invitacionEterna && !fechaHasta.isAfter(fechaDesde)) {
        fechaHasta = fechaDesde.add(const Duration(hours: 2));
      }
    });
  }

  Future<void> seleccionarFechaHasta() async {
    if (invitacionEterna) return;

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: fechaHasta.isAfter(fechaDesde) ? fechaHasta : fechaDesde,
      firstDate: fechaDesde,
      lastDate: DateTime(2099),
    );
    if (pickedDate == null) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.input,
      helpText: 'Seleccionar tiempo',
      initialTime: TimeOfDay.fromDateTime(
        fechaHasta.isAfter(fechaDesde) ? fechaHasta : fechaDesde.add(const Duration(hours: 2)),
      ),
    );
    if (pickedTime == null) return;

    setState(() {
      fechaHasta = DateTime(
        pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute,
      );
      if (!fechaHasta.isAfter(fechaDesde)) {
        fechaHasta = fechaDesde.add(const Duration(hours: 2));
      }
    });
  }

  // === Compartir ===
  void compartirQRWeb() {
    if (invitacionId != null) {
      final urlCompartir = 'https://gladiatorcontrolbase.com/qr/ver_qr/$invitacionId';
      Share.share('Aquí está tu QR de invitación: $urlCompartir');
    }
  }

  // === UI helpers ===
  String _formatearFechaHora(DateTime fecha) {
    return '${fecha.year}-${_dos(fecha.month)}-${_dos(fecha.day)} ${_dos(fecha.hour)}:${_dos(fecha.minute)}';
  }

  String _dos(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF3A7CA5);
    const grisOscuro = Color(0xFF444444);

    final estiloInput = InputDecoration(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Generador de Invitación')),
      backgroundColor: const Color(0xFFF6F8FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _nombreCtrl, decoration: estiloInput.copyWith(labelText: 'Nombre'), inputFormatters: [
              LengthLimitingTextInputFormatter(80)
            ],),
            const SizedBox(height: 12),
            TextField(controller: _apellidoCtrl, decoration: estiloInput.copyWith(labelText: 'Apellido'), inputFormatters: [
              LengthLimitingTextInputFormatter(50)
            ],),
            const SizedBox(height: 12),
            TextField(controller: _rutCtrl, decoration: estiloInput.copyWith(labelText: 'RUT'), inputFormatters: [
              LengthLimitingTextInputFormatter(8)
            ],),
            const SizedBox(height: 12),
            TextField(controller: _patenteCtrl, decoration: estiloInput.copyWith(labelText: 'Patente'), inputFormatters: [
              LengthLimitingTextInputFormatter(8)
            ],),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: estiloInput.copyWith(labelText: 'Tipo de Visita'),
              value: selectedTipoVisita,
              items: tiposVisita.map((item) => DropdownMenuItem(
                value: item['id_tipo_visita'].toString(),
                child: Text(item['nombre']),
              )).toList(),
              onChanged: (val) => setState(() => selectedTipoVisita = val),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: estiloInput.copyWith(labelText: 'Destino'),
              value: selectedDestino,
              items: destinos.map((item) => DropdownMenuItem(
                value: item['id'].toString(),
                child: Text(item['nombre']),
              )).toList(),
              onChanged: (val) => setState(() => selectedDestino = val),
            ),
            const SizedBox(height: 10),

            // Invitación eterna
            Row(
              children: [
                Checkbox(
                  value: invitacionEterna,
                  activeColor: Colors.black,
                  onChanged: (value) => setState(() {
                    invitacionEterna = value ?? false;
                    if (!invitacionEterna && !fechaHasta.isAfter(fechaDesde)) {
                      fechaHasta = fechaDesde.add(const Duration(hours: 2));
                    }
                  }),
                ),
                const Text('Invitación eterna', style: TextStyle(color: grisOscuro)),
              ],
            ),

            // ¿Viene con compañía?
            const SizedBox(height: 10),
            Row(
              children: [
                Switch(
                  value: vieneConCompania,
                  onChanged: (v) {
                    setState(() {
                      vieneConCompania = v;
                      if (!v) {
                        numAcompanantes = 0;
                        _acompanantesCtrl.clear();
                      } else if (numAcompanantes == 0) {
                        numAcompanantes = 1; // default si activa
                      }
                    });
                  },
                  activeColor: Colors.black,
                ),
                const SizedBox(width: 8),
                const Text('¿Viene con compañía?'),
              ],
            ),
            if (vieneConCompania) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: numAcompanantes == 0 ? 1 : numAcompanantes,
                decoration: estiloInput.copyWith(labelText: '¿Cuántas personas?'),
                items: List.generate(10, (i) => i + 1)
                    .map((n) => DropdownMenuItem(value: n, child: Text(n.toString())))
                    .toList(),
                onChanged: (val) => setState(() => numAcompanantes = val ?? 1),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _acompanantesCtrl,
                minLines: 2,
                maxLines: 5,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(1000)
                ],
                decoration: estiloInput.copyWith(
                  labelText: 'Nombres de acompañantes (opcional)',
                  hintText: 'Ej: Juan Pérez; María López; Ana Torres',
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Controles de fechas
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                      autoFechaDesde ? Icons.access_time_filled : Icons.date_range,
                      size: 18,
                      color: grisOscuro,
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: grisOscuro),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    label: Text(
                      // Indicamos si está en modo automático
                      (autoFechaDesde ? 'Desde:\n' : 'Desde:\n') +
                          _formatearFechaHora(fechaDesde),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: azul, fontWeight: FontWeight.w600),
                    ),
                    onPressed: seleccionarFechaDesde, // al tocar se apaga auto y permite fijar
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.lock_clock, size: 18, color: grisOscuro),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: grisOscuro),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    label: Text(
                      'Hasta:\n${_formatearFechaHora(fechaHasta)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: invitacionEterna ? Colors.grey : azul,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: invitacionEterna ? null : seleccionarFechaHasta,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: generarInvitacion,
              icon: const Icon(Icons.qr_code),
              label: const Text('Generar QR'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
            ),
            if (mensajeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(mensajeError!, style: const TextStyle(color: Colors.red)),
              ),
            if (qrBase64 != null)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Column(
                  children: [
                    const Text('Código QR generado',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Image.memory(base64Decode(qrBase64!), width: 200, height: 200),
                    const SizedBox(height: 10),
                    Text(qrTexto ?? '', style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: compartirQRWeb,
                      icon: const Icon(Icons.share),
                      label: const Text('Compartir enlace'),
                      style: ElevatedButton.styleFrom(backgroundColor: azul),
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
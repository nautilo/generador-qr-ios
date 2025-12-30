import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'app_config.dart';

class HistorialInvitacionesPage extends StatefulWidget {
  final String rutUsuario;
  const HistorialInvitacionesPage({super.key, required this.rutUsuario});

  @override
  State<HistorialInvitacionesPage> createState() =>
      _HistorialInvitacionesPageState();
}

class _HistorialInvitacionesPageState
    extends State<HistorialInvitacionesPage> {
  List<dynamic> invitaciones = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    fetchInvitaciones();
  }

  Future<void> fetchInvitaciones() async {
    try {
      final url = AppConfig.uri('/invitaciones/invitaciones/${widget.rutUsuario}');
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        setState(() {
          invitaciones = jsonDecode(resp.body);
          cargando = false;
        });
      } else {
        setState(() => cargando = false);
      }
    } catch (e) {
      setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          "Historial de Invitaciones",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF6F8FB),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : invitaciones.isEmpty
          ? const Center(
        child: Text(
          "No has generado invitaciones todavía",
          style: TextStyle(color: Colors.black54, fontSize: 15),
        ),
      )
          : ListView.builder(
        padding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        itemCount: invitaciones.length,
        itemBuilder: (context, index) {
          final inv = invitaciones[index];

          // 🔹 Normalizamos "vino"
          final dynamic vinoRaw = inv["vino"];
          final bool vino = (vinoRaw == true || vinoRaw == 1);

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DetalleInvitacionPage(invitacion: inv),
                ),
              );
            },
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.qr_code,
                            color: Color(0xFF5BA5A0), size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            (inv["nombre_invitado"] ?? "Invitado")
                                .toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (vino)
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 22)
                        else
                          const Icon(Icons.cancel,
                              color: Colors.red, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          (inv["fecha_creacion"] ?? "").toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Patente: ${(inv["patente"] ?? "-").toString()}",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Destino: ${(inv["destino"] ?? "N/A").toString()}",
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Desde: ${(inv["fecha_desde"] ?? "-").toString()}\nHasta: ${(inv["fecha_hasta"] ?? "-").toString()}",
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
class DetalleInvitacionPage extends StatefulWidget {
  final Map<String, dynamic> invitacion;
  const DetalleInvitacionPage({super.key, required this.invitacion});

  @override
  State<DetalleInvitacionPage> createState() => _DetalleInvitacionPageState();
}

class _DetalleInvitacionPageState extends State<DetalleInvitacionPage> {
  String? qrBase64;
  String? qrTexto;
  bool cargandoQR = true;
  Timer? _qrTimer; // 👈 añadimos un timer

  @override
  void initState() {
    super.initState();
    obtenerQRDinamico();

    // 🔁 Auto-refresh cada 10 segundos
    _qrTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) obtenerQRDinamico();
    });
  }

  @override
  void dispose() {
    _qrTimer?.cancel(); // 👈 paramos el timer al salir
    super.dispose();
  }

  Future<void> obtenerQRDinamico() async {
    try {
      final id = widget.invitacion["id_invitacion"].toString();
      final url = AppConfig.uri('/qr/qr_dynamic/$id');

      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          qrBase64 = data["qr_base64"];
          qrTexto = data["qr_data"];
          cargandoQR = false;
        });
      } else {
        setState(() => cargandoQR = false);
      }
    } catch (e) {
      setState(() => cargandoQR = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final inv = widget.invitacion;
    final numAcomp = inv["num_acompanantes"]?.toString() ?? "0";
    final dynamic vinoRaw = inv["vino"];
    final bool vino = (vinoRaw == true || vinoRaw == 1);

    final String acompRaw = (inv["acompanantes"] ?? "").toString();
    final List<String> nombresAcomp = acompRaw.isNotEmpty
        ? acompRaw.split(",").map((e) => e.trim()).toList()
        : [];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          "Detalle de Invitación",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF6F8FB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 🔹 Contenedor del QR dinámico
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                  )
                ],
              ),
              child: cargandoQR
                  ? const Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(),
              )
                  : (qrBase64 != null
                  ? Column(
                children: [
                  Image.memory(base64Decode(qrBase64!), width: 220, height: 220),
                  const SizedBox(height: 10),
                  Text(
                    "${qrTexto ?? inv["id_invitacion"]}",
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              )
                  : const Text(
                "No se pudo cargar el QR dinámico",
                style: TextStyle(color: Colors.redAccent),
              )),
            ),
            const SizedBox(height: 24),

            // Información principal
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _rowInfo("RUT Invitado", (inv["rut_invitado"] ?? "-").toString()),
                    _rowInfo("Invitado", (inv["nombre_invitado"] ?? "Invitado").toString()),
                    _rowInfo("Patente", (inv["patente"] ?? "-").toString()),
                    _rowInfo("Tipo de visita", (inv["tipo_visita"] ?? "N/A").toString()),
                    _rowInfo("Destino", (inv["destino"] ?? "N/A").toString()),
                    _rowInfo("Desde", (inv["fecha_desde"] ?? "-").toString()),
                    _rowInfo("Hasta", (inv["fecha_hasta"] ?? "-").toString()),
                    _rowInfo("Creada", (inv["fecha_creacion"] ?? "-").toString()),
                    _rowInfo("N° Acompañantes", numAcomp),
                    _rowInfo("Asistencia", vino ? "✅ Vino" : "❌ No vino"),
                  ],
                ),
              ),
            ),

            if (nombresAcomp.isNotEmpty) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Lista de Acompañantes",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: nombresAcomp
                              .map((n) => Padding(
                            padding:
                            const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              n,
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.black54),
                            ),
                          ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black87)),
          ),
          Expanded(
            flex: 6,
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.black54)),
          ),
        ],
      ),
    );
  }
}
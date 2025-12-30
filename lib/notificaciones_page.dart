import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart'; // Para CapturaScreen y notificacionStream
import 'app_config.dart';

class NotificacionesPage extends StatefulWidget {
  final String rutUsuario;
  const NotificacionesPage({super.key, required this.rutUsuario});

  @override
  State<NotificacionesPage> createState() => _NotificacionesPageState();
}

class _NotificacionesPageState extends State<NotificacionesPage> {
  List<dynamic> notificaciones = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    fetchNotificaciones();
  }

  Future<void> fetchNotificaciones() async {
    setState(() => cargando = true);
    try {
      final url = AppConfig.uri('/admin/notificaciones/${widget.rutUsuario}');
      final resp = await http.get(url);

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);

        if (decoded is List) {
          setState(() {
            notificaciones = decoded;
            cargando = false;
          });
        } else {
          setState(() {
            notificaciones = [];
            cargando = false;
          });
        }
      } else {
        setState(() => cargando = false);
      }
    } catch (e) {
      print("❌ Error fetchNotificaciones: $e");
      setState(() => cargando = false);
    }
  }

  Future<void> _marcarLeida(int notifId) async {
    try {
      final url = AppConfig.uri('/admin/notificaciones/${widget.rutUsuario}/$notifId/leida');
      final resp = await http.post(url);
      print("➡️ POST marcarLeida (${resp.statusCode}): ${resp.body}");

      notificacionStream.add({
        "rut_usuario": widget.rutUsuario,
        "id_notificacion": notifId,
        "accion": "leida"
      });
    } catch (e) {
      print("❌ Error marcarLeida: $e");
    }
  }

  Future<void> _openNoti(Map<String, dynamic> n) async {
    final int? id = n["id"] is int ? n["id"] : int.tryParse("${n['id']}");

    if (id != null) {
      await _marcarLeida(id);
      await fetchNotificaciones();
    }

    final tipo = (n["tipo"] ?? "").toString();
    if (tipo == "captura" || tipo == "captura_visita") {
      final capturaId = n["captura_id"]?.toString() ?? "";
      final hora = n["hora_local"]?.toString();

      final urls = <String>[
        n["foto1_url"]?.toString() ?? "",
        n["foto2_url"]?.toString() ?? "",
        n["foto3_url"]?.toString() ?? "",
      ].where((e) => e.isNotEmpty).toList();

      final detalle = n["invitacion"];

      if (urls.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No hay imágenes disponibles")),
          );
        }
        return;
      }

      final openUrl = capturaId.isNotEmpty
          ? "https://gladiatorcontrolbase.com/api/reportes/ver/$capturaId"
          : null;

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CapturaScreen(
            urls: urls,
            hora: hora,
            openUrl: openUrl,
            detalle: detalle,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color unreadBg = const Color(0xFFEAF6F5);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          "Historial de Notificaciones",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF6F8FB),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : notificaciones.isEmpty
          ? const Center(
        child: Text(
          "No tienes notificaciones",
          style: TextStyle(color: Colors.black54, fontSize: 15),
        ),
      )
          : RefreshIndicator(
        onRefresh: fetchNotificaciones,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 16),
          itemCount: notificaciones.length,
          itemBuilder: (context, index) {
            final n = notificaciones[index];
            final bool leida = n["leida"] ?? false;
            final String fechaHora =
                n["fecha_hora"]?.toString() ?? "";

            return InkWell(
              onTap: () => _openNoti(n),
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 3,
                color: leida ? Colors.white : unreadBg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications,
                              color: Color(0xFF5BA5A0), size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              n["titulo"] ?? "",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: leida
                                    ? Colors.black87
                                    : Colors.black,
                              ),
                            ),
                          ),
                          Text(
                            n["tipo"] ?? "",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        n["mensaje"] ?? "",
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      if (fechaHora.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 14, color: Colors.black54),
                            const SizedBox(width: 4),
                            Text(
                              fechaHora,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ]
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

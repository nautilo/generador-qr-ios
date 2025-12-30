import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';

class QRPersonalPage extends StatefulWidget {
  final String rutUsuario;
  const QRPersonalPage({super.key, required this.rutUsuario});

  @override
  State<QRPersonalPage> createState() => _QRPersonalPageState();
}

class _QRPersonalPageState extends State<QRPersonalPage> {
  String? qrBase64;
  String? qrTexto;
  String? mensajeError;
  Timer? qrTimer;
  @override
  void initState() {
    super.initState();
    _obtenerQRPersonal();
    _iniciarAutoRefresh();
  }

  @override
  void dispose() {
    qrTimer?.cancel();
    super.dispose();
  }

  Future<void> _obtenerQRPersonal() async {
    final url = AppConfig.uri('/api/qr_personal/${widget.rutUsuario}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          qrBase64 = data['qr_base64'];
          qrTexto = data['qr_data'];
          mensajeError = null;
        });
      } else {
        setState(() {
          mensajeError = 'Error al cargar QR: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        mensajeError = 'Error de conexión: $e';
      });
    }
  }

  void _iniciarAutoRefresh() {
    qrTimer?.cancel();
    qrTimer = Timer.periodic(const Duration(seconds: 10), (_) => _obtenerQRPersonal());
  }

  @override
  Widget build(BuildContext context) {
    const Color fondo = Color(0xFFF6F8FB);
    const Color gris = Color(0xFF444444);
    const Color botonColor = Color(0xFF5BA5A0);

    return Scaffold(
      backgroundColor: fondo,
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado personalizado
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Acceso',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),

            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_open_rounded, size: 80, color: gris),
                      const SizedBox(height: 10),
                      const Text(
                        'Este es tu QR de acceso',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: gris),
                      ),
                      const SizedBox(height: 20),

                      if (mensajeError != null)
                        Text(
                          mensajeError!,
                          style: const TextStyle(color: Colors.red, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),

                      if (qrBase64 != null)
                        Column(
                          children: [
                            Image.memory(
                              base64Decode(qrBase64!),
                              width: 220,
                              height: 220,
                            ),
                            const SizedBox(height: 12),
                            Text(qrTexto ?? '', style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _obtenerQRPersonal,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Actualizar QR'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: botonColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
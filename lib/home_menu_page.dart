import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'generador_qr_page.dart';
import 'qr_personal_page.dart';
import 'abrir_barrera_page.dart';
import 'login_page.dart';
import 'reportes_webview_page.dart';
import 'notificaciones_page.dart';
import 'historial_invitaciones_page.dart';
import 'main.dart' show notificacionStream; // 👈 importamos el stream global

class HomeMenuPage extends StatefulWidget {
  final String rutUsuario;
  const HomeMenuPage({super.key, required this.rutUsuario});

  @override
  State<HomeMenuPage> createState() => _HomeMenuPageState();
}

class _HomeMenuPageState extends State<HomeMenuPage> {
  static const Color botonColor = Color(0xFF5BA5A0);
  int noLeidas = 0;
  final String base = "http://209.46.126.62:9999/admin";

  IO.Socket? socket;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _checkNotificaciones();
    _initSocket();

    // 👂 Escuchamos el stream de FCM (instantáneo)
    _sub = notificacionStream.stream.listen((data) {
      if (!mounted) return;
      // Si la notificación es de este usuario → refrescamos badge
      if ("${data['rut_usuario']}" == widget.rutUsuario ||
          data['rut_usuario'] == null) {
        _checkNotificaciones();
      }
    });
  }

  @override
  void dispose() {
    socket?.disconnect();
    _sub?.cancel();
    super.dispose();
  }

  void _initSocket() {
    try {
      socket = IO.io(
        "http://209.46.126.62:9999",
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      );

      socket!.connect();

      socket!.onConnect((_) {
        print("✅ Conectado a Socket.IO");
        socket!.emit("join", {"rut_usuario": widget.rutUsuario});
      });

      socket!.on("nueva_notificacion", (data) {
        print("🔔 Evento nueva_notificacion: $data");
        if ("${data['rut_usuario']}" == widget.rutUsuario) {
          _checkNotificaciones();
        }
      });

      socket!.onDisconnect((_) => print("❌ Socket desconectado"));
    } catch (e) {
      print("❌ Error en socket: $e");
    }
  }

  Future<void> _checkNotificaciones() async {
    try {
      final url = Uri.parse("$base/notificaciones/${widget.rutUsuario}");
      final resp = await http.get(url);

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);

        if (decoded is List) {
          final count =
              decoded.where((n) => (n["leida"] ?? false) == false).length;

          if (mounted) {
            setState(() {
              noLeidas = count;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              noLeidas = 0;
            });
          }
        }
      }
    } catch (e) {
      print("❌ Error al verificar notificaciones: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: Padding(
        //H 24 y V 40
        padding: Platform.isIOS
            ? const EdgeInsets.fromLTRB(24, 58, 24, 40)
            : const EdgeInsets.fromLTRB(24, 40, 24, 40),
        child: SingleChildScrollView(   // 👈 añadido
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo y encabezado con campanita
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/logo.gif',
                          height: 50,
                          width: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'GLADIATOR CONTROL',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'V1.0',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // 🔔 Icono campanita con badge
                  Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none_outlined,
                            size: 30, color: Colors.black87),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotificacionesPage(
                                rutUsuario: widget.rutUsuario,
                              ),
                            ),
                          );
                          _checkNotificaciones(); // refrescar al volver
                        },
                      ),
                      if (noLeidas > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            width: 16,
                            height: 16,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: Text(
                              "$noLeidas",
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const Divider(thickness: 1.2, color: Colors.black12),
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'MENÚ PRINCIPAL',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),

              // Acceso QR
              _menuCard(
                context,
                icon: Icons.person_outline,
                title: 'Acceso',
                subtitle: 'Tu código QR individual',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          QRPersonalPage(rutUsuario: widget.rutUsuario),
                    ),
                  );
                },
              ),

              // Invitaciones
              _menuCard(
                context,
                icon: Icons.qr_code_2_outlined,
                title: 'Invitaciones',
                subtitle: 'Gestiona tus invitaciones',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          InvitacionesMenuPage(rutUsuario: widget.rutUsuario),
                    ),
                  );
                },
              ),

              // Abrir barrera
              _menuCard(
                context,
                icon: Icons.door_front_door_outlined,
                title: 'Abrir',
                subtitle: 'Control de acceso',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AbrirBarreraPage(rutUsuario: widget.rutUsuario),
                    ),
                  );
                },
              ),

              // 🚨 Incendio
              _menuCard(
                context,
                icon: Icons.local_fire_department_outlined,
                title: 'Incendio',
                subtitle: 'Alertas de emergencia por fuego',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportesWebViewPage(
                        title: 'Incendios',
                        url: Uri.parse('https://gladiatorcontrolbase.com/reportes#inc'),
                      ),
                    ),
                  );
                },
              ),

              // 🚔 Robo
              _menuCard(
                context,
                icon: Icons.security_outlined,
                title: 'Robo',
                subtitle: 'Alertas de emergencia por robo',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportesWebViewPage(
                        title: 'Robos',
                        url: Uri.parse('https://gladiatorcontrolbase.com/reportes#rob'),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Cerrar sesión
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                    );
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
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
          ),
        ),
      ),
    );
  }


  Widget _menuCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: const Color(0xFFEAECEE),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
            child: Row(
              children: [
                Icon(icon, size: 32, color: Colors.black87),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          )),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          )),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 18, color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InvitacionesMenuPage extends StatelessWidget {
  final String rutUsuario;
  const InvitacionesMenuPage({super.key, required this.rutUsuario});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          "Invitaciones",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF6F8FB),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _submenuCard(
              context,
              icon: Icons.qr_code_2,
              title: "Generar invitación",
              subtitle: "Crear nueva invitación QR",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GeneradorQRPage(rutUsuario: rutUsuario),
                  ),
                );
              },
            ),
            _submenuCard(
              context,
              icon: Icons.history,
              title: "Ver invitaciones generadas",
              subtitle: "Historial de invitaciones realizadas",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        HistorialInvitacionesPage(rutUsuario: rutUsuario),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _submenuCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: const Color(0xFFEAECEE),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 30, color: Colors.black87),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          )),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 18, color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

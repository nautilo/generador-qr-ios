import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:async'; // 👈 para StreamController
import 'login_page.dart';
import 'app_config.dart';

Future<bool> verificarSesion(String rutUsuario) async {
  final url = AppConfig.uri('/api/fcm/verificar_sesion/$rutUsuario');
  final res = await http.get(url);
  if (res.statusCode == 200) {
    final json = jsonDecode(res.body);
    return json['activo'] == true;
  }
  return false;
}

/// =================== CONFIG ===================
final StreamController<Map<String, dynamic>> notificacionStream =
StreamController<Map<String, dynamic>>.broadcast();

/// Clave global para navegar desde listeners (sin BuildContext directo)
final navigatorKey = GlobalKey<NavigatorState>();

/// =================== BG HANDLER ===================
/// Debe ser top-level y con @pragma
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🌙 BG handler → data=${message.data}');
  // ✅ Enviamos al stream global para que Home/Notificaciones reaccionen
  notificacionStream.add(message.data);
}


/// =================== HELPERS ===================
Future<void> _ensureNavigatorReady() async {
  var tries = 0;
  while (navigatorKey.currentState == null && tries < 40) {
    await Future.delayed(const Duration(milliseconds: 75));
    tries++;
  }
  debugPrint('🧭 Navigator ready: ${navigatorKey.currentState != null} (tries=$tries)');
}

void _showLoading() {
  final ctx = navigatorKey.currentState?.overlay?.context;
  if (ctx == null) {
    debugPrint('⚠️ No overlay context para loading');
    return;
  }
  showDialog(
    context: ctx,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
}

void _hideLoading() {
  final ctx = navigatorKey.currentState?.overlay?.context;
  if (ctx != null && Navigator.of(ctx).canPop()) {
    Navigator.of(ctx).pop();
  }
}

/// Abre URL en navegador externo (para open_url o visor HTML)
Future<void> _openUrlExtern(String url) async {
  try {
    final uri = Uri.parse(url);
    debugPrint('🌐 launchUrl → $uri');
    // Si canLaunchUrl devuelve false, intentamos igual con launchUrl; en algunos OEM falla el can*
    final can = await canLaunchUrl(uri);
    if (!can) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('❌ _openUrlExtern: $e');
  }
}

/// GET /api/reportes/<captura_id> y devuelve las URLs (⚠️ JSON, NO /ver)
Future<List<String>> _fetchUrlsByCapturaId(String capturaId) async {
  final url = AppConfig.uri('/api/reportes/$capturaId').toString(); // ← JSON con ["urls": [...]]
  debugPrint('🌐 GET $url');
  try {
    final res = await http.get(Uri.parse(url));
    debugPrint('🌐 RES ${res.statusCode} ${res.reasonPhrase}');
    if (res.statusCode != 200) return [];
    final jsonBody = jsonDecode(res.body);
    debugPrint('🌐 BODY $jsonBody');
    final list = (jsonBody['urls'] as List?)?.cast<String>() ?? <String>[];
    return list.where((e) => e.isNotEmpty).toList();
  } catch (e) {
    debugPrint('❌ _fetchUrlsByCapturaId error: $e');
    return [];
  }
}
// =================== PROCESA CAPTURA DE NOTIFICACIÓN ===================
Future<void> _openCapturaFromData(Map<String, dynamic> data) async {
  try {
    debugPrint('📦 payload data: $data');

    // 1) Caso open_url directo
    final maybeUrl = (data['open_url'] ?? '').toString();
    if (maybeUrl.isNotEmpty) {
      await _openUrlExtern(maybeUrl);
      return;
    }

    // 2) Validamos tipo
    final tipo = (data['tipo'] ?? '').toString();
    if (tipo != 'captura_visita' && tipo != 'captura') {
      debugPrint('ℹ️ Tipo no compatible: $tipo');
      return;
    }

    // 3) ID captura
    final capturaId = (data['captura_id'] ?? data['reporte_id'])?.toString() ?? '';
    if (capturaId.isEmpty) {
      debugPrint('❌ No se encontró captura_id/reporte_id en payload');
      return;
    }

    // 4) URLs iniciales
    var urls = <String>[
      data['foto1_url']?.toString() ?? '',
      data['foto2_url']?.toString() ?? '',
      data['foto3_url']?.toString() ?? '',
    ].where((e) => e.isNotEmpty).toList();

    // 5) Detalle inicial
    Map<String, dynamic> detalle = {};
    if (data['invitacion'] is Map) {
      detalle.addAll(Map<String, dynamic>.from(data['invitacion']));
    }
    for (var k in data.keys) {
      if (!detalle.containsKey(k)) detalle[k] = data[k];
    }

    // 🚩 Si faltan datos → pedimos a NOTIFICACIONES (trae invitación + captura)
    final bool detalleIncompleto =
        detalle.isEmpty || !(detalle.containsKey("nombre_invitado") || detalle.containsKey("rut_invitado"));

    if (detalleIncompleto) {
      _showLoading();
      try {
        final url = AppConfig.uri('/admin/notificacion/captura/$capturaId');
        final res = await http.get(url);
        if (res.statusCode == 200) {
          final jsonBody = jsonDecode(res.body);
          if (jsonBody is Map) {
            if (jsonBody['urls'] is List) {
              urls = (jsonBody['urls'] as List).cast<String>();
            }
            if (jsonBody['invitacion'] is Map) {
              detalle.addAll(Map<String, dynamic>.from(jsonBody['invitacion']));
            }
          }
        } else {
          debugPrint("❌ Error API notificaciones: ${res.statusCode}");
        }
      } finally {
        _hideLoading();
      }
    }

    if (urls.isEmpty) {
      debugPrint('❌ No hay imágenes para mostrar');
      return;
    }

    // 7) Hora
    final hora = data['hora_local']?.toString();
    if (hora != null && hora.contains(" ")) {
      final partes = hora.split(" ");
      detalle["fecha_evento"] = partes[0];
      detalle["hora_evento"] = partes.length > 1 ? partes[1] : "";
    }

    // 8) URL navegador
    final openUrlVisor = 'https://gladiatorcontrolbase.com/api/reportes/ver/$capturaId';

    // 9) Abrir pantalla CapturaScreen
    await _ensureNavigatorReady();
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) {
      debugPrint('⚠️ No hay contexto disponible para navegar');
      return;
    }

    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => CapturaScreen(
          urls: urls,
          hora: hora,
          openUrl: openUrlVisor,
          detalle: detalle,
        ),
      ),
    );

    debugPrint('✅ CapturaScreen abierta correctamente con datos');
  } catch (e, st) {
    debugPrint('❌ _openCapturaFromData error: $e\n$st');
    _hideLoading();
  }
}


/// =================== MAIN ===================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  debugPrint('🚀 App init');

  // 🔹 Escucha notificaciones en segundo plano (cuando la app está cerrada o minimizada)
  FirebaseMessaging.onBackgroundMessage(_bgHandler);

  // 🔹 Configurar presentación de notificaciones en primer plano (Android/iOS)
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // 🔹 Cuando llega una notificación estando la app ABIERTA
  FirebaseMessaging.onMessage.listen((RemoteMessage m) async {
    debugPrint('🔔 [FOREGROUND] Notificación → title=${m.notification?.title} body=${m.notification?.body}');
    debugPrint('🔔 [FOREGROUND] Data → ${m.data}');

    // Enviar al stream global (para notificaciones en tiempo real)
    notificacionStream.add(m.data);

    // Si la notificación contiene imágenes o capturas, las abre
    await _openCapturaFromData(m.data);

    // Mostrar un SnackBar si hay un título disponible
    final ctx = navigatorKey.currentState?.context;
    if (ctx != null && m.notification?.title != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(m.notification!.title!),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  });

  // 🔹 Cuando el usuario toca la notificación (app en segundo plano)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) async {
    debugPrint('📲 [BACKGROUND TAP] → data=${m.data}');
    notificacionStream.add(m.data);
    await _openCapturaFromData(m.data);
  });

  // 🔹 Cuando la app fue ABIERTA desde una notificación estando CERRADA
  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null) {
    debugPrint('🧊 [TERMINATED] Inicial desde notificación → data=${initialMsg.data}');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      notificacionStream.add(initialMsg.data);
      await _openCapturaFromData(initialMsg.data);
    });
  }

  // 🔹 Iniciar aplicación principal
  runApp(const MyApp());
}

/// =================== APP ROOT ===================
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Acceso Residencial',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false, // ← sin banner DEBUG
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
      ),
      home: const SafeArea(child: LoginPage()),
    );
  }
}
/// =================== PANTALLA DE CAPTURAS (grilla + bloques con alias + “ver en navegador”) ===================
class CapturaScreen extends StatelessWidget {
  final List<String> urls;
  final String? hora;
  final String? openUrl;
  final Map<String, dynamic>? detalle;

  const CapturaScreen({
    super.key,
    required this.urls,
    this.hora,
    this.openUrl,
    this.detalle,
  });

  Future<void> _abrirEnNavegador(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final can = await canLaunchUrl(uri);
      if (!can) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el navegador')),
        );
      }
    }
  }

  void _abrirFullscreen(BuildContext context, int initialIndex) {
    if (urls.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenGallery(
          urls: urls,
          initialIndex: initialIndex,
          hora: hora,
          openUrl: openUrl,
        ),
      ),
    );
  }

  /// 🔹 Mapeo de alias
  static const Map<String, String> fieldAliases = {
    "fecha_creacion": "Fecha de creación",
    "fecha_desde": "Válida desde",
    "fecha_hasta": "Válida hasta",
    "num_acompanantes": "Número de acompañantes",
    "acompanantes": "Lista de acompañantes",
    "id_invitacion": "Código de invitación",
    "nombre_invitado": "Nombre del invitado",
    "apellido_1_invitado": "Apellido paterno",
    "apellido_2_invitado": "Apellido materno",
    "patente": "Patente vehículo",
    "rut_invitado": "RUT invitado",
    "rut_usuario": "RUT usuario",
    "tipo_visita": "Tipo de visita",
    "destino": "Destino",
  };

  /// 🔹 Helper para construir bloques con alias
  Widget buildBlock(IconData icon, String title, Map<String, dynamic> data, List<String> keys) {
    final entries = keys
        .where((k) => data[k] != null && data[k].toString().trim().isNotEmpty)
        .map((k) => "${fieldAliases[k] ?? k}: ${data[k]}")
        .toList();

    if (entries.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.black87),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries
                .map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(e, style: const TextStyle(fontSize: 13)),
            ))
                .toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final navegadorUrl = openUrl ?? '';

    final tiempoKeys = ["fecha_creacion", "fecha_desde", "fecha_hasta"];
    final acompKeys = ["num_acompanantes", "acompanantes"];
    final datosKeys = [
      "id_invitacion",
      "nombre_invitado",
      "apellido_1_invitado",
      "apellido_2_invitado",
      "patente",
      "rut_invitado",
      "rut_usuario",
      "tipo_visita",
      "destino"
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(hora != null ? 'Ingreso: $hora' : 'Ingreso'),
        actions: [
          if (navegadorUrl.isNotEmpty)
            IconButton(
              tooltip: 'Ver en navegador',
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => _abrirEnNavegador(context, navegadorUrl),
            ),
        ],
      ),
    body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Capturas primero
            if (urls.isNotEmpty) ...[
              const Text(
                "Capturas",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(4),
                itemCount: urls.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _abrirFullscreen(context, i),
                  child: Hero(
                    tag: urls[i],
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        urls[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ] else
              const Center(child: Text('Sin imágenes')),

// 🔹 Bloques con alias
            if (detalle != null) ...[
              buildBlock(
                Icons.calendar_today,
                "Ingreso",
                {
                  "Fecha": (hora ?? "").split(" ").isNotEmpty ? (hora ?? "").split(" ")[0] : "",
                  "Hora": (hora ?? "").split(" ").length > 1 ? (hora ?? "").split(" ")[1] : "",
                },
                ["Fecha", "Hora"],
              ),
              buildBlock(Icons.access_time, "Tiempo", detalle!, tiempoKeys),
              buildBlock(Icons.people, "Acompañantes", detalle!, acompKeys),
              buildBlock(Icons.badge, "Datos de invitación", detalle!, datosKeys),
            ],
          ],
        ),
      ),
      floatingActionButton: (navegadorUrl.isNotEmpty)
          ? FloatingActionButton.extended(
        onPressed: () => _abrirEnNavegador(context, navegadorUrl),
        icon: const Icon(Icons.open_in_browser),
        label: const Text('Ver en navegador'),
      )
          : null,
    );
  }
}


/// =================== VISOR FULLSCREEN (swipe + zoom + abrir navegador) ===================
class FullscreenGallery extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final String? hora;
  final String? openUrl; // URL del visor HTML completo

  const FullscreenGallery({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.hora,
    this.openUrl,
  });

  @override
  State<FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<FullscreenGallery> {
  late final PageController _controller;
  late int _index;
  final _tc = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, (widget.urls.length - 1).clamp(0, 999));
    _controller = PageController(initialPage: _index);
  }

  void _onDoubleTapDown(TapDownDetails d) {
    if (_zoomed) {
      _tc.value = Matrix4.identity();
      _zoomed = false;
      return;
    }
    // Zoom x2 centrado en el punto tocado
    final pos = d.localPosition;
    const scale = 2.0;
    final dx = -pos.dx * (scale - 1);
    final dy = -pos.dy * (scale - 1);
    _tc.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
    _zoomed = true;
  }

  Future<void> _abrirActualEnNavegador() async {
    final elegido = (widget.openUrl?.isNotEmpty == true)
        ? widget.openUrl!                       // ← abre el visor HTML
        : '';                                    // si no hay openUrl, no abrimos nada aquí
    if (elegido.isEmpty) return;
    try {
      final uri = Uri.parse(elegido);
      final can = await canLaunchUrl(uri);
      if (!can) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el navegador')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Foto ${_index + 1}/$total ${widget.hora != null ? "· ${widget.hora}" : ""}',
        ),
        actions: [
          if (widget.openUrl?.isNotEmpty == true)
            IconButton(
              tooltip: 'Ver en navegador',
              icon: const Icon(Icons.open_in_browser, color: Colors.white),
              onPressed: _abrirActualEnNavegador,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (i) {
          setState(() {
            _index = i;
            _tc.value = Matrix4.identity();
            _zoomed = false;
          });
        },
        itemCount: total,
        itemBuilder: (_, i) {
          final url = widget.urls[i];
          return GestureDetector(
            onDoubleTapDown: _onDoubleTapDown,
            onDoubleTap: () {}, // el zoom está en onDoubleTapDown
            child: Hero(
              tag: url,
              child: InteractiveViewer(
                transformationController: _tc,
                panEnabled: true,
                scaleEnabled: true,
                minScale: 1.0,  // ajustado a pantalla
                maxScale: 8.0,  // zoom alto
                clipBehavior: Clip.hardEdge,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox.expand(
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (c, e, s) => const Icon(
                      Icons.broken_image,
                      color: Colors.white70,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
// lib/services/push_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';

class PushService {
  PushService._();
  static final instance = PushService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _initialized = false;
  String? _lastRut; // para re-registrar si rota el token

  Future<void> init() async {
    if (_initialized) return;
    await Firebase.initializeApp(); // necesita google-services.json correcto
    // Pedimos permiso (Android 13+/iOS)
    final perm = await _fcm.requestPermission(alert: true, badge: true, sound: true);
    debugPrint('[PushService] permiso: ${perm.authorizationStatus}');

    // Mostrar notis en fg en iOS/macOS (no afecta Android)
    await _fcm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    // Si el token rota, reenvía al backend si ya hay rut logueado
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('[PushService] NEW TOKEN: $newToken');
      final rut = _lastRut;
      if (rut != null && newToken.isNotEmpty) {
        await _enviarTokenAlBackend(rutUsuario: rut, token: newToken);
      }
    });

    _initialized = true;
  }

  /// Llama esto **después** de que el usuario haga login OK
  Future<void> registerAfterLogin({required String rutUsuario}) async {
    await init(); // asegura firebase listo

    // Reintenta varias veces por si al primer intento devuelve null
    String? token;
    for (var i = 0; i < 6; i++) {
      try {
        token = await _fcm.getToken();
      } catch (e) {
        debugPrint('[PushService] getToken error: $e');
      }
      if (token != null && token.isNotEmpty) break;
      await Future.delayed(const Duration(seconds: 2));
    }

    debugPrint('[PushService] TOKEN tras login($rutUsuario): ${token ?? "NULL"}');

    if (token == null || token.isEmpty) {
      debugPrint('[PushService] No hay token (¿Play Services? ¿google-services.json correcto?)');
      return;
    }

    _lastRut = rutUsuario;
    await _enviarTokenAlBackend(rutUsuario: rutUsuario, token: token);
  }

  Future<void> _enviarTokenAlBackend({
    required String rutUsuario,
    required String token,
  }) async {
    try {
      final uri = AppConfig.uri('/api/fcm/register');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rut_usuario': int.tryParse(rutUsuario) ?? rutUsuario,
          'token': token,
          'plataforma': 'android',
        }),
      );
      debugPrint('[PushService] /api/fcm/register -> ${res.statusCode} ${res.body}');
    } catch (e) {
      debugPrint('[PushService] Error enviando token al backend: $e');
    }
  }
}
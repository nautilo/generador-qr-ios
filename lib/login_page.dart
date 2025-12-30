import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // ✅ nuevo para guardar sesión
import 'home_menu_page.dart';
import 'push_service.dart'; // para registrar token FCM tras login
import 'app_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _rutCtrl = TextEditingController();
  final _claveCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _ocultarClave = true;
  bool _cargando = false;
  String? _mensajeError;
  @override
  void dispose() {
    _rutCtrl.dispose();
    _claveCtrl.dispose();
    super.dispose();
  }

  /// ✅ Guarda el RUT localmente para mantener sesión abierta
  Future<void> _guardarSesion(String rut) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rut_usuario', rut);
    debugPrint('🟢 Sesión guardada localmente para $rut');
  }

  Future<void> _doLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _mensajeError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() => _cargando = true);

    final url = AppConfig.uri('/api/login_usuario');
    final body = {
      'rut': _rutCtrl.text.trim(),
      'clave': _claveCtrl.text.trim(),
    };

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);

        if (data['status'] == 'ok') {
          final rut = _rutCtrl.text.trim();

          // ✅ Guardar sesión local
          await _guardarSesion(rut);

          // ✅ Registrar token FCM después de login
          try {
            await PushService.instance.registerAfterLogin(rutUsuario: rut);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Notificaciones activadas')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('⚠️ No se pudo registrar FCM: $e')),
              );
            }
          }

          // ✅ Ir directo al Home
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => HomeMenuPage(rutUsuario: rut)),
            );
          }

        } else {
          setState(() => _mensajeError = data['message'] ?? 'Credenciales inválidas');
        }

      } else if (resp.statusCode == 401) {
        setState(() => _mensajeError = 'Credenciales inválidas');
      } else {
        setState(() => _mensajeError = 'Error de servidor (${resp.statusCode})');
      }

    } catch (e) {
      setState(() => _mensajeError = 'Error de red: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 24),
                Image.asset('assets/logo.gif', height: 120),
                const SizedBox(height: 16),
                const Divider(thickness: 1, color: Colors.black12),
                const SizedBox(height: 16),

                const Row(
                  children: [
                    Icon(Icons.person_outline, color: Colors.teal, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Ingrese rut y clave de generador',
                      style: TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Campo RUT
                TextFormField(
                  controller: _rutCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [LengthLimitingTextInputFormatter(8)],
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF6F6F6),
                    hintText: 'Rut Generador',
                    prefixIcon: const Icon(Icons.person_outline),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Ingrese su RUT';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Campo Clave
                TextFormField(
                  controller: _claveCtrl,
                  obscureText: _ocultarClave,
                  inputFormatters: [LengthLimitingTextInputFormatter(512)],
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF6F6F6),
                    hintText: 'Clave Generador',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _ocultarClave ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _ocultarClave = !_ocultarClave),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Ingrese su clave';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),
                const Divider(thickness: 1, color: Colors.black12),
                const SizedBox(height: 24),

                // Botón ACCEDER
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _cargando ? null : _doLogin,
                    icon: const Icon(Icons.login_rounded, color: Colors.white),
                    label: _cargando
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Text('ACCEDER'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5E9FA3),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                if (_mensajeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text(
                      _mensajeError!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'generador_qr_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _rutCtrl = TextEditingController();
  final _claveCtrl = TextEditingController();
  String? _errorMensaje;

  final String apiUrl = 'http://209.46.126.62:9999/api/login_usuario';

  Future<void> iniciarSesion() async {
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'rut': _rutCtrl.text,
        'clave': _claveCtrl.text,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GeneradorQRPage(rutUsuario: data['rut_usuario']),
        ),
      );
    } else {
      setState(() {
        _errorMensaje = 'Credenciales incorrectas';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _rutCtrl,
              decoration: const InputDecoration(labelText: 'RUT Usuario'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _claveCtrl,
              decoration: const InputDecoration(labelText: 'Clave'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: iniciarSesion,
              child: const Text('Ingresar'),
            ),
            if (_errorMensaje != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_errorMensaje!, style: const TextStyle(color: Colors.red)),
              )
          ],
        ),
      ),
    );
  }
}

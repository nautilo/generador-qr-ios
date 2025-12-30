import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ReportesWebViewPage extends StatefulWidget {
  final String title;
  final Uri url;

  const ReportesWebViewPage({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<ReportesWebViewPage> createState() => _ReportesWebViewPageState();
}

class _ReportesWebViewPageState extends State<ReportesWebViewPage> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();

    // Recomendado por webview_flutter para Android
    if (Platform.isAndroid) {
      WebViewPlatform.instance;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onNavigationRequest: (NavigationRequest req) {
            // Permitimos todo dentro del mismo WebView
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${error.description}')),
            );
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  Future<bool> _onWillPop() async {
    if (await _controller.canGoBack()) {
      _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final showProgress = _progress > 0 && _progress < 100;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Recargar',
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              tooltip: 'Abrir en navegador',
              icon: const Icon(Icons.open_in_browser),
              onPressed: () async {
                // Si prefieres abrir externo, puedes usar url_launcher.
                // Aquí recargamos dentro del WebView.
                await _controller.loadRequest(widget.url);
              },
            ),
          ],
          bottom: showProgress
              ? PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: LinearProgressIndicator(value: _progress / 100),
          )
              : null,
        ),
        body: RefreshIndicator(
          onRefresh: () async => _controller.reload(),
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}

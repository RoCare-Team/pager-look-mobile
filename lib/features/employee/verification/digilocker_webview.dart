import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';

/// Runs the DigiLocker consent flow inside the app.
///
/// After consent the backend callback redirects to a PagerLook page
/// (`/employee/verification/aadhaar?status=…` or `/employee/settings/digilocker?…`),
/// on the web origin or the `pagerlook://` deep link. That navigation is caught
/// here instead of loading the website, and the URI is returned so the caller
/// can show the result in the app. Returns null if the user closes the sheet.
Future<Uri?> openDigiLockerInApp(BuildContext context, String authorizationUrl) {
  return Navigator.of(context, rootNavigator: true).push<Uri>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _DigiLockerWebView(url: authorizationUrl)),
  );
}

/// True for the PagerLook page the callback returns to — never for the
/// `/api/digilocker/callback` hop itself, which has to load.
bool _isReturnUri(Uri uri) {
  if (uri.scheme == 'pagerlook') return true;
  final host = uri.host;
  final ours = host == 'localhost' || host == '10.0.2.2' || host == 'pagerlook.com' || host.endsWith('.pagerlook.com');
  return ours && uri.path.startsWith('/employee/');
}

class _DigiLockerWebView extends StatefulWidget {
  const _DigiLockerWebView({required this.url});

  final String url;

  @override
  State<_DigiLockerWebView> createState() => _DigiLockerWebViewState();
}

class _DigiLockerWebViewState extends State<_DigiLockerWebView> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && _isReturnUri(uri)) {
              _finish(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          // Android does not report server-side redirects to onNavigationRequest.
          onPageStarted: (url) {
            final uri = Uri.tryParse(url);
            if (uri != null && _isReturnUri(uri)) _finish(uri);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _finish(Uri uri) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DigiLocker'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  color: AppColors.brand600,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

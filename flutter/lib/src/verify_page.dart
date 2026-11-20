import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'contract.dart';

/// Full-screen capture page. Pops with a [VerifyResult]. Most apps call [Akwelo.verify] instead.
class AkweloVerifyPage extends StatefulWidget {
  const AkweloVerifyPage({super.key, required this.url});

  final Uri url;

  @override
  State<AkweloVerifyPage> createState() => _AkweloVerifyPageState();
}

class _AkweloVerifyPageState extends State<AkweloVerifyPage> {
  late final WebViewController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    final origin = originOf(widget.url.toString());

    _controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (request) {
        // Only the camera; navigation is pinned to the Akwelo origin below.
        final camOnly = request.types.every((t) => t == WebViewPermissionResourceType.camera);
        camOnly ? request.grant() : request.deny();
      },
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('AkweloBridge', onMessageReceived: (m) async {
        // The channel is visible to any loaded page; only trust the Akwelo origin.
        final current = await _controller.currentUrl();
        if (origin == null || originOf(current) != origin) return;
        final r = VerifyResult.parse(m.message);
        if (r != null) _finish(r);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) => origin != null && originOf(req.url) == origin
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            _finish(VerifyResult(VerifyStatus.error, error: e.description));
          }
        },
      ));

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    _controller.loadRequest(widget.url);
  }

  void _finish(VerifyResult r) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(VerifyResult.cancelled);
      },
      child: Scaffold(body: SafeArea(child: WebViewWidget(controller: _controller))),
    );
  }
}

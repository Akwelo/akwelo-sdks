import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'contract.dart';

/// Full-screen capture page. Pops with a [VerifyResult]. Most apps call [Akwelo.verify] instead.
class AkweloVerifyPage extends StatefulWidget {
  const AkweloVerifyPage({super.key, required this.url, this.screenCaptureActive, this.watchScreenCapture});

  final Uri url;

  /// See [AkweloOptions.screenCaptureActive].
  final bool? screenCaptureActive;

  /// See [AkweloOptions.watchScreenCapture].
  final ScreenCaptureWatcher? watchScreenCapture;

  @override
  State<AkweloVerifyPage> createState() => _AkweloVerifyPageState();
}

/// What a failed main-document load means for the capture: an error result, or null to ignore it
/// (a link the person tapped that did not open, or a navigation the SDK itself stopped).
VerifyResult? resultForLoadError({
  required String? pageOrigin,
  required String? failingUrl,
  required bool isForMainFrame,
  required bool processTerminated,
  required int errorCode,
  required String description,
}) {
  if (processTerminated) {
    return const VerifyResult.failure('webview_crashed', 'The capture page stopped unexpectedly');
  }
  if (!isForMainFrame) return null;
  // WebKit reports a navigation the app cancelled as -999 or as "frame load interrupted" (102).
  if (errorCode == -999 || errorCode == 102) return null;
  if (failingUrl != null && originOf(failingUrl) != pageOrigin) return null;
  return VerifyResult.failure(
    'page_load_failed',
    description.isEmpty ? 'The capture page did not load' : description,
  );
}

/// True when an HTTP error answer is for the capture page itself, not for one of its resources.
bool isPageRequest(Uri page, Uri? request) =>
    request != null && originOf(request.toString()) == originOf(page.toString()) && request.path == page.path;

class _AkweloVerifyPageState extends State<AkweloVerifyPage> {
  late final WebViewController _controller;
  bool _done = false;
  bool _loading = true;
  bool _pageLoaded = false;
  final HostSignalState _capture = HostSignalState();
  void Function()? _stopWatching;

  /// Screen capture reached the page: after every load and on every change.
  void _sendCapture() {
    final script = _capture.script();
    if (!_pageLoaded || script == null || _done) return;
    _controller.runJavaScript(script).catchError((Object _) {});
  }

  void _onCapture(bool active) {
    if (_capture.set(active)) _sendCapture();
  }

  void _watchCapture() {
    final watch = widget.watchScreenCapture;
    if (watch != null) {
      try {
        _stopWatching = watch((active) {
          if (mounted) _onCapture(active);
        });
      } catch (_) {
        // The host's native code failed: send nothing, Akwelo records `unknown`.
      }
    } else if (widget.screenCaptureActive != null) {
      _capture.set(widget.screenCaptureActive!);
    }
  }

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
        onNavigationRequest: (req) {
          if (origin != null && originOf(req.url) == origin) return NavigationDecision.navigate;
          // Never leave the Akwelo origin in here. A link the person tapped (privacy notice,
          // help) opens in the system browser instead.
          if (req.isMainFrame) _openOutside(req.url);
          return NavigationDecision.prevent;
        },
        onPageFinished: (url) {
          if (mounted && _loading) setState(() => _loading = false);
          if (origin != null && originOf(url) == origin) {
            _pageLoaded = true;
            _sendCapture();
          }
        },
        onHttpError: (e) {
          if (!isPageRequest(widget.url, e.request?.uri)) return;
          _finish(VerifyResult.failure(
            'page_load_failed',
            'The capture page answered HTTP ${e.response?.statusCode ?? 0}',
          ));
        },
        onWebResourceError: (e) {
          final r = resultForLoadError(
            pageOrigin: origin,
            failingUrl: e.url,
            isForMainFrame: e.isForMainFrame ?? true,
            processTerminated: e.errorType == WebResourceErrorType.webContentProcessTerminated,
            errorCode: e.errorCode,
            description: e.description,
          );
          if (r != null) _finish(r);
        },
      ));

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    _watchCapture();
    final env = _capture.env();
    _controller.loadRequest(env == null
        ? widget.url
        : widget.url.replace(fragment: '${widget.url.fragment}&env=$env'));
  }

  @override
  void dispose() {
    try {
      _stopWatching?.call();
    } catch (_) {}
    _stopWatching = null;
    super.dispose();
  }

  Future<void> _openOutside(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser to open it: the link does nothing, capture carries on.
    }
  }

  void _finish(VerifyResult r) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    // Widgets only (no Material or Cupertino), so the page works in any app.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(VerifyResult.cancelled);
      },
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: SafeArea(
          child: Column(
            children: [
              // Always there, so a page that fails to draw can never trap the person
              // (iOS has no back button).
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Semantics(
                  button: true,
                  label: 'Close',
                  child: GestureDetector(
                    key: const ValueKey('akwelo-close'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _finish(VerifyResult.cancelled),
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: ExcludeSemantics(
                          child: Text(
                            '\u2715',
                            style: TextStyle(fontSize: 20, color: Color(0xFF111111)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (_loading) const Center(child: _Spinner()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small turning arc shown until the page has loaded.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turn =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _turn,
        child: const CustomPaint(size: Size.square(28), painter: _ArcPainter()),
      );
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6B7280)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Offset.zero & size, 0, math.pi * 1.5, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => false;
}

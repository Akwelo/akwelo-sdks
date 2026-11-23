// The capture page end to end against a fake WebView: what the app is told for each thing that
// can happen in the WebView.
import 'package:akwelo/akwelo.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'fake_webview.dart';

class FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final List<String> opened = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

const _submitted = '{"type":"akwelo.verify.result","sessionId":"vs_1","status":"submitted"}';

void main() {
  late FakeWebViewPlatform web;
  late FakeLauncher launcher;

  setUp(() {
    web = FakeWebViewPlatform();
    WebViewPlatform.instance = web;
    launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  /// Pumps an app, calls `Akwelo.verify` and waits for the capture page to be on screen.
  Future<Future<VerifyResult>> open(
    WidgetTester tester, {
    String token = 'vst_abc',
    AkweloOptions options = const AkweloOptions(),
    bool expectPage = true,
  }) async {
    late BuildContext context;
    await tester.pumpWidget(WidgetsApp(
      color: const Color(0xFFFFFFFF),
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) =>
          PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, __) => b(c)),
      home: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
    ));
    final result = Akwelo.verify(context, sessionToken: token, options: options);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    if (expectPage) expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);
    return result;
  }

  Future<VerifyResult> settle(WidgetTester tester, Future<VerifyResult> result) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return result;
  }

  testWidgets('loads the capture URL and returns what the page reports', (tester) async {
    final result = await open(tester);
    expect(web.controller!.loaded.toString(), 'https://flow.akwelo.com/verify/selfie#token=vst_abc');
    web.controller!.post('AkweloBridge', _submitted);
    web.controller!.post('AkweloBridge', '{"type":"akwelo.verify.result","status":"cancelled"}');
    expect(await settle(tester, result), const VerifyResult(VerifyStatus.submitted, sessionId: 'vs_1'));
    expect(find.byKey(const ValueKey('fake-webview')), findsNothing);
  });

  testWidgets('a blank token or unusable baseUrl never opens the page', (tester) async {
    expect((await open(tester, token: ' ', expectPage: false)).then((r) => r.error),
        completion('invalid_session_token'));
    final r = await open(tester,
        options: const AkweloOptions(baseUrl: 'http://flow.akwelo.com'), expectPage: false);
    expect((await r).error, 'invalid_base_url');
    expect(web.controller, isNull);
  });

  testWidgets('one capture at a time; the open one is left untouched', (tester) async {
    final first = await open(tester);
    final context = tester.element(find.byKey(const ValueKey('fake-webview')));
    final second = await Akwelo.verify(context, sessionToken: 'vst_other');
    expect(second.error, 'already_in_progress');
    web.controller!.post('AkweloBridge', _submitted);
    expect((await settle(tester, first)).status, VerifyStatus.submitted);
    // Free again afterwards.
    final third = await open(tester);
    await tester.tap(find.byKey(const ValueKey('akwelo-close')));
    expect(await settle(tester, third), VerifyResult.cancelled);
  });

  testWidgets('the close button and the system back gesture both cancel', (tester) async {
    final a = await open(tester);
    await tester.tap(find.byKey(const ValueKey('akwelo-close')));
    expect(await settle(tester, a), VerifyResult.cancelled);
    final b = await open(tester);
    await tester.binding.handlePopRoute();
    expect(await settle(tester, b), VerifyResult.cancelled);
  });

  testWidgets('a message is trusted only while the page is on the Akwelo origin', (tester) async {
    final result = await open(tester);
    web.controller!.current = 'https://flow.akwelo.com.evil.com/verify/selfie';
    web.controller!.post('AkweloBridge', _submitted);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget); // still open
    web.controller!.current = null;
    web.controller!.post('AkweloBridge', 'not json');
    web.controller!.post('AkweloBridge', _submitted);
    expect((await settle(tester, result)).status, VerifyStatus.submitted);
  });

  testWidgets('never leaves the origin; a tapped link opens in the browser', (tester) async {
    final result = await open(tester);
    final nav = web.delegate!.onNavigationRequest!;
    expect(
        await nav(const NavigationRequest(url: 'https://flow.akwelo.com/verify/selfie', isMainFrame: true)),
        NavigationDecision.navigate);
    expect(await nav(const NavigationRequest(url: 'https://akwelo.com/privacy', isMainFrame: true)),
        NavigationDecision.prevent);
    expect(await nav(const NavigationRequest(url: 'https://ads.example/frame', isMainFrame: false)),
        NavigationDecision.prevent);
    expect(await nav(const NavigationRequest(url: 'intent://evil#Intent;end', isMainFrame: true)),
        NavigationDecision.prevent);
    await tester.pump();
    expect(launcher.opened, ['https://akwelo.com/privacy']);
    await tester.tap(find.byKey(const ValueKey('akwelo-close')));
    await settle(tester, result);
  });

  testWidgets('a page that cannot load, or dies, is an error and not a blank screen', (tester) async {
    final offline = await open(tester);
    web.delegate!.onWebResourceError!(const WebResourceError(
      errorCode: -2,
      description: 'net::ERR_INTERNET_DISCONNECTED',
      isForMainFrame: true,
      url: 'https://flow.akwelo.com/verify/selfie',
    ));
    final r1 = await settle(tester, offline);
    expect((r1.status, r1.error), (VerifyStatus.error, 'page_load_failed'));

    final crashed = await open(tester);
    web.delegate!.onWebResourceError!(const WebResourceError(
      errorCode: 2,
      description: '',
      errorType: WebResourceErrorType.webContentProcessTerminated,
      isForMainFrame: true,
    ));
    expect((await settle(tester, crashed)).error, 'webview_crashed');

    final http = await open(tester);
    web.delegate!.onHttpError!(HttpResponseError(
      request: WebResourceRequest(uri: Uri.parse('https://flow.akwelo.com/favicon.ico')),
      response: const WebResourceResponse(uri: null, statusCode: 404),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget); // a missing icon is not fatal
    web.delegate!.onHttpError!(HttpResponseError(
      request: WebResourceRequest(uri: Uri.parse('https://flow.akwelo.com/verify/selfie')),
      response: const WebResourceResponse(uri: null, statusCode: 503),
    ));
    final r3 = await settle(tester, http);
    expect(r3.error, 'page_load_failed');
    expect(r3.errorMessage, contains('503'));
  });

  testWidgets('only the camera is granted', (tester) async {
    final result = await open(tester);
    final cam = _Permission({WebViewPermissionResourceType.camera});
    final mic = _Permission({WebViewPermissionResourceType.camera, WebViewPermissionResourceType.microphone});
    web.controller!.onPermission!(cam);
    web.controller!.onPermission!(mic);
    expect(cam.answers, ['grant']);
    expect(mic.answers, ['deny']);
    await tester.tap(find.byKey(const ValueKey('akwelo-close')));
    await settle(tester, result);
  });
}

class _Permission extends PlatformWebViewPermissionRequest {
  _Permission(Set<WebViewPermissionResourceType> types) : super(types: types);

  final List<String> answers = [];

  @override
  Future<void> grant() async => answers.add('grant');

  @override
  Future<void> deny() async => answers.add('deny');
}

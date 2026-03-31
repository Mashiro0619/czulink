import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';

final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

const _prefUsernameKey = 'username';
const _prefPasswordKey = 'password';
const _prefIspOptionKey = 'ispOption';
const _prefAutoExitOnSuccessKey = 'autoExitOnSuccess';

const _jsStatusAlreadyOn = 'ALREADY_ON';
const _jsStatusSubmitted = 'SUBMITTED';
const _jsStatusNotReady = 'NOT_READY';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

String _buildLoginInjectionScript({
  required String usernameJson,
  required String passwordJson,
  required String ispValueJson,
}) {
  return '''(function() {
  var username = $usernameJson;
  var password = $passwordJson;
  var ispValue = $ispValueJson;
  var workerKey = '__czulinkAutofillTimer';
  var maxAttempts = 12;
  var attempt = 0;

  function notify(status) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('loginStatus', status);
    }
  }

  function toArray(list) {
    return Array.prototype.slice.call(list || []);
  }

  function unique(list) {
    var result = [];
    for (var i = 0; i < list.length; i += 1) {
      if (list[i] && result.indexOf(list[i]) === -1) {
        result.push(list[i]);
      }
    }
    return result;
  }

  function queryAll(selector) {
    try {
      return toArray(document.querySelectorAll(selector));
    } catch (_) {
      return [];
    }
  }

  function findTargets(names, selectors) {
    var elements = [];
    for (var i = 0; i < names.length; i += 1) {
      elements = elements.concat(toArray(document.getElementsByName(names[i])));
    }
    for (var j = 0; j < selectors.length; j += 1) {
      elements = elements.concat(queryAll(selectors[j]));
    }
    return unique(elements);
  }

  function readForm() {
    return {
      userEls: findTargets(['DDDDD'], ['input#DDDDD']),
      passEls: findTargets(['upass'], ['input#upass']),
      ispEls: findTargets(['ISP_select'], ['select#ISP_select']),
      logoutEls: findTargets(['logout'], ['#logout']),
      submitEls: findTargets(
        ['0MKKey', 'Login'],
        ['input[type="submit"]', 'button[type="submit"]'],
      ),
    };
  }

  function isVisible(el) {
    if (!el || el.type === 'hidden') {
      return false;
    }
    if (window.getComputedStyle) {
      var style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden') {
        return false;
      }
    }
    if (!el.getBoundingClientRect) {
      return true;
    }
    var rect = el.getBoundingClientRect();
    return rect.width > 0 || rect.height > 0;
  }

  function pickActive(elements) {
    var fallback = null;
    for (var i = 0; i < elements.length; i += 1) {
      var el = elements[i];
      if (!el || el.disabled) {
        continue;
      }
      if (!fallback) {
        fallback = el;
      }
      if (isVisible(el)) {
        return el;
      }
    }
    return fallback;
  }

  function dispatchEventCompat(el, eventName) {
    if (!el) {
      return;
    }
    var event;
    if (typeof Event === 'function') {
      event = new Event(eventName, {bubbles: true});
    } else {
      event = document.createEvent('HTMLEvents');
      event.initEvent(eventName, true, false);
    }
    el.dispatchEvent(event);
  }

  function setValue(el, value) {
    if (!el || el.disabled) {
      return false;
    }
    try {
      var prototype =
          el.tagName === 'SELECT'
              ? window.HTMLSelectElement && window.HTMLSelectElement.prototype
              : el.tagName === 'TEXTAREA'
                  ? window.HTMLTextAreaElement &&
                      window.HTMLTextAreaElement.prototype
                  : window.HTMLInputElement &&
                      window.HTMLInputElement.prototype;
      var descriptor = prototype
          ? Object.getOwnPropertyDescriptor(prototype, 'value')
          : null;
      if (descriptor && descriptor.set) {
        descriptor.set.call(el, value);
      } else {
        el.value = value;
      }
    } catch (_) {
      el.value = value;
    }
    if (el.setAttribute) {
      el.setAttribute('value', value);
    }
    if (el.focus) {
      el.focus();
    }
    dispatchEventCompat(el, 'input');
    dispatchEventCompat(el, 'change');
    dispatchEventCompat(el, 'keyup');
    dispatchEventCompat(el, 'blur');
    return true;
  }

  function fillAll(elements, value) {
    var wrote = false;
    for (var i = 0; i < elements.length; i += 1) {
      wrote = setValue(elements[i], value) || wrote;
    }
    return wrote;
  }

  function fillForm(form) {
    fillAll(form.userEls, username);
    fillAll(form.passEls, password);
    if (form.ispEls.length) {
      fillAll(form.ispEls, ispValue);
    }
  }

  function hasExpectedValue(elements, value) {
    var active = pickActive(elements);
    if (active && active.value === value) {
      return true;
    }
    for (var i = 0; i < elements.length; i += 1) {
      if (elements[i] && elements[i].value === value) {
        return true;
      }
    }
    return false;
  }

  function isReadyToSubmit(form) {
    return (
      hasExpectedValue(form.userEls, username) &&
      hasExpectedValue(form.passEls, password) &&
      (!form.ispEls.length || hasExpectedValue(form.ispEls, ispValue))
    );
  }

  function isLoggedIn(elements) {
    for (var i = 0; i < elements.length; i += 1) {
      if (isVisible(elements[i])) {
        return true;
      }
    }
    return false;
  }

  function submitLogin(form) {
    if (typeof window.ee === 'function') {
      window.ee(1);
      return true;
    }
    var submitEl = pickActive(form.submitEls);
    if (submitEl && typeof submitEl.click === 'function') {
      submitEl.click();
      return true;
    }
    var activeUserEl = pickActive(form.userEls);
    var activeForm = activeUserEl && activeUserEl.form;
    if (activeForm && typeof activeForm.submit === 'function') {
      activeForm.submit();
      return true;
    }
    return false;
  }

  function clearWorker() {
    if (window[workerKey]) {
      clearTimeout(window[workerKey]);
      window[workerKey] = null;
    }
  }

  function finish(status) {
    clearWorker();
    notify(status);
  }

  function scheduleNext() {
    clearWorker();
    window[workerKey] = setTimeout(runAttempt, 220);
  }

  function runAttempt() {
    var form = readForm();

    if (isLoggedIn(form.logoutEls)) {
      finish('ALREADY_ON');
      return;
    }

    fillForm(form);

    window[workerKey] = setTimeout(function() {
      var verifiedForm = readForm();
      fillForm(verifiedForm);

      if (isReadyToSubmit(verifiedForm) && submitLogin(verifiedForm)) {
        finish('SUBMITTED');
        return;
      }

      attempt += 1;
      if (attempt >= maxAttempts) {
        finish('NOT_READY');
        return;
      }

      scheduleNext();
    }, 140);
  }

  clearWorker();
  runAttempt();
  return 'PENDING';
})();''';
}

enum IspOption { campus, cmcc, cucc, ctcc }

extension IspOptionExtension on IspOption {
  String get label {
    switch (this) {
      case IspOption.campus:
        return '校园网';
      case IspOption.cmcc:
        return '移动';
      case IspOption.cucc:
        return '联通';
      case IspOption.ctcc:
        return '电信';
    }
  }

  String get value {
    switch (this) {
      case IspOption.campus:
        return '';
      case IspOption.cmcc:
        return '@cmcc';
      case IspOption.cucc:
        return '@unicom';
      case IspOption.ctcc:
        return '@telecom';
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '校园网自动登录',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const CampusLoginPage(),
    );
  }
}

class CampusLoginPage extends StatefulWidget {
  const CampusLoginPage({super.key});

  @override
  State<CampusLoginPage> createState() => _CampusLoginPageState();
}

class _CampusLoginPageState extends State<CampusLoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  IspOption _selectedIsp = IspOption.campus;
  bool _passwordHidden = true;
  bool _isLoading = false;
  bool _hasSavedCredentials = false;
  bool _showWebView = false;
  bool _autoExitOnSuccess = false;
  InAppWebViewController? _webViewController;
  final WebUri _loginUri = WebUri('http://172.19.0.1/');
  final String _githubUrl = 'https://github.com/Mashiro0619/czulink';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_prefUsernameKey);
    final password = prefs.getString(_prefPasswordKey);
    final ispName = prefs.getString(_prefIspOptionKey);
    final autoExit = prefs.getBool(_prefAutoExitOnSuccessKey) ?? false;
    if (username != null && password != null) {
      setState(() {
        _usernameController.text = username;
        _passwordController.text = password;
        _autoExitOnSuccess = autoExit;
        _selectedIsp = IspOption.values.firstWhere(
          (option) => option.name == ispName,
          orElse: () => IspOption.campus,
        );
        _hasSavedCredentials = true;
        _showWebView = true;
        _isLoading = true;
      });
    } else {
      setState(() {
        _autoExitOnSuccess = autoExit;
      });
    }
  }

  Future<void> _saveAndConnect() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showMessage('请输入学号和密码');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUsernameKey, username);
    await prefs.setString(_prefPasswordKey, password);
    await prefs.setString(_prefIspOptionKey, _selectedIsp.name);
    await prefs.setBool(_prefAutoExitOnSuccessKey, _autoExitOnSuccess);

    setState(() {
      _hasSavedCredentials = true;
      _showWebView = true;
      _isLoading = true;
    });

    _startLoginFlow();
  }

  Future<void> _resetCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重置账号信息'),
          content: const Text('确定要删除保存的账号并返回登录页面吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('重置'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUsernameKey);
    await prefs.remove(_prefPasswordKey);
    await prefs.remove(_prefIspOptionKey);
    await prefs.remove(_prefAutoExitOnSuccessKey);

    setState(() {
      _usernameController.clear();
      _passwordController.clear();
      _selectedIsp = IspOption.campus;
      _autoExitOnSuccess = false;
      _hasSavedCredentials = false;
      _showWebView = false;
      _isLoading = false;
    });
  }

  Future<void> _startLoginFlow() async {
    if (_webViewController != null) {
      await _webViewController!.loadUrl(urlRequest: URLRequest(url: _loginUri));
    }
  }

  Future<void> _openGitHub() async {
    await launchUrlString(_githubUrl, mode: LaunchMode.externalApplication);
  }

  Future<void> _exitApp() async {
    if (!_autoExitOnSuccess) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 300));
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      exit(0);
    } else {
      SystemNavigator.pop();
    }
  }

  void _showMessage(String message) {
    _scaffoldMessengerKey.currentState?.clearSnackBars();
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleJsStatus(String status) {
    switch (status) {
      case _jsStatusAlreadyOn:
        setState(() {
          _isLoading = false;
        });
        _showMessage('已检测到已登录状态。');
        _exitApp();
        break;
      case _jsStatusSubmitted:
        _showMessage('已提交登录请求。');
        _exitApp();
        break;
      case _jsStatusNotReady:
        _showMessage('页面加载完成，但尚未找到登录表单。');
        break;
      default:
        _showMessage('登录状态：$status');
    }
  }

  Future<void> _injectLoginJs() async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }

    final usernameJson = jsonEncode(_usernameController.text);
    final passwordJson = jsonEncode(_passwordController.text);
    final ispValueJson = jsonEncode(_selectedIsp.value);
    final js = _buildLoginInjectionScript(
      usernameJson: usernameJson,
      passwordJson: passwordJson,
      ispValueJson: ispValueJson,
    );

    try {
      final result = await controller.evaluateJavascript(source: js);
      if (result is String &&
          {
            _jsStatusAlreadyOn,
            _jsStatusSubmitted,
            _jsStatusNotReady,
          }.contains(result)) {
        _handleJsStatus(result);
      }
    } catch (_) {
      _showMessage('自动注入 JS 时出现错误。');
    }
  }

  Widget _buildWebViewBody(ThemeData theme) {
    return Column(
      children: [
        if (_isLoading)
          LinearProgressIndicator(
            minHeight: 4,
            color: theme.colorScheme.primary,
          ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: _loginUri),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  cacheEnabled: true,
                  useHybridComposition: true,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'loginStatus',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        _handleJsStatus(args.first.toString());
                      }
                      return null;
                    },
                  );
                  if (_hasSavedCredentials) {
                    _startLoginFlow();
                  }
                },
                onLoadStop: (controller, uri) async {
                  if (_hasSavedCredentials) {
                    await _injectLoginJs();
                  }
                },
                onReceivedError: (controller, request, error) {
                  _showMessage('加载页面出错: ${error.description}');
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('请输入校园网账号', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '学号/账号',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _passwordHidden,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: '密码',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordHidden
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _passwordHidden = !_passwordHidden;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<IspOption>(
                  segments: IspOption.values
                      .map(
                        (option) => ButtonSegment(
                          value: option,
                          label: Text(option.label),
                        ),
                      )
                      .toList(),
                  selected: {_selectedIsp},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedIsp = newSelection.first;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('登录成功后自动退出软件'),
                  value: _autoExitOnSuccess,
                  onChanged: (value) {
                    setState(() {
                      _autoExitOnSuccess = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saveAndConnect,
                  child: const Text('保存并连接'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园网自动登录'),
        actions: [
          IconButton(
            icon: Icon(MdiIcons.github),
            onPressed: _openGitHub,
            tooltip: 'GitHub 仓库',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _resetCredentials,
            tooltip: '重置账号',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _showWebView ? _buildWebViewBody(theme) : _buildLoginForm(theme),
      ),
    );
  }
}

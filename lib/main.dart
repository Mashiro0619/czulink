import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
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
  InAppWebViewController? _webViewController;
  final WebUri _loginUri = WebUri('http://172.19.0.1/');

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
    final username = prefs.getString('username');
    final password = prefs.getString('password');
    final ispName = prefs.getString('ispOption');
    if (username != null && password != null) {
      setState(() {
        _usernameController.text = username;
        _passwordController.text = password;
        _selectedIsp = IspOption.values.firstWhere(
          (option) => option.name == ispName,
          orElse: () => IspOption.campus,
        );
        _hasSavedCredentials = true;
        _showWebView = true;
        _isLoading = true;
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
    await prefs.setString('username', username);
    await prefs.setString('password', password);
    await prefs.setString('ispOption', _selectedIsp.name);

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
    await prefs.remove('username');
    await prefs.remove('password');
    await prefs.remove('ispOption');

    setState(() {
      _usernameController.clear();
      _passwordController.clear();
      _selectedIsp = IspOption.campus;
      _hasSavedCredentials = false;
      _showWebView = false;
      _isLoading = false;
    });
  }

  Future<void> _startLoginFlow() async {
    if (_webViewController != null) {
      await _webViewController!.loadUrl(
        urlRequest: URLRequest(url: _loginUri),
      );
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
      case 'ALREADY_ON':
        setState(() {
          _isLoading = false;
        });
        _showMessage('已检测到已登录状态。');
        break;
      case 'SUBMITTED':
        _showMessage('已提交登录请求。');
        break;
      case 'NOT_READY':
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
    final js = '''(function() {
  const userEl = document.getElementsByName('DDDDD')[0];
  const passEl = document.getElementsByName('upass')[0];
  const ispEl = document.getElementsByName('ISP_select')[0];
  const logoutEl = document.getElementsByName('logout')[0];

  if (logoutEl && logoutEl.offsetParent !== null) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('loginStatus', 'ALREADY_ON');
    }
    return 'ALREADY_ON';
  }
  if (userEl && passEl) {
    userEl.value = $usernameJson;
    passEl.value = $passwordJson;
    if (ispEl) {
      ispEl.value = $ispValueJson;
    }
    if(typeof window.ee === 'function') {
      window.ee(1);
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('loginStatus', 'SUBMITTED');
      }
      return 'SUBMITTED';
    }
  }
  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
    window.flutter_inappwebview.callHandler('loginStatus', 'NOT_READY');
  }
  return 'NOT_READY';
})();''';

    try {
      final result = await controller.evaluateJavascript(source: js);
      if (result is String) {
        _handleJsStatus(result);
      }
    } catch (_) {
      _showMessage('自动注入 JS 时出现错误。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园网自动登录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _resetCredentials,
            tooltip: '重置账号',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _showWebView
            ? Column(
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
                          initialUrlRequest:
                              URLRequest(url: _loginUri),
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
              )
            : Center(
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
                          Text(
                            '请输入校园网账号',
                            style: theme.textTheme.titleLarge,
                          ),
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
              ),
      ),
    );
  }
}

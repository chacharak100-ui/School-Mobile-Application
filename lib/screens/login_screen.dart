import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animate_do/animate_do.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import 'student/dashboard.dart';
import 'admin/dashboard.dart';
import 'staff/dashboard.dart';
import 'parent/dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _ScreenPhase { welcome, selectSchool, login }

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  _ScreenPhase _phase = _ScreenPhase.welcome;

  // ─── Login Controllers ───
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isFetchingSchools = true; // Internal loading state for school list

  // ─── School Search ───
  final _schoolSearchController = TextEditingController();
  List<Map<String, dynamic>> _filteredSchools = [];

  // ─── Animations ───
  late AnimationController _particleController;
  late Animation<double> _floatAnimation;

  // ─── BIOMETRIC AUTH ───
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricType = 'Biometric';

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _particleController, curve: Curves.easeInOut),
    );
    _initBiometrics();
    _initPhase();
  }

  Future<void> _initBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      if (canCheck && isDeviceSupported && availableBiometrics.isNotEmpty) {
        _biometricAvailable = true;
        _biometricType = availableBiometrics.contains(BiometricType.face)
            ? 'Face ID'
            : 'Fingerprint';

        final storedUser = await _secureStorage.read(key: 'bio_username');
        final currentDomain = (await SharedPreferences.getInstance())
            .getString('school_domain');

        if (storedUser != null && storedUser.isNotEmpty && currentDomain != null) {
          _biometricEnabled = true;
          _usernameController.text = storedUser;
        }
      }
    } catch (e) {
      print('[Biometric] Init error: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _authenticateWithBiometrics() async {
    if (!_biometricAvailable || !_biometricEnabled) return;

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access $_biometricType login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated && mounted) {
        HapticFeedback.mediumImpact();
        final username = await _secureStorage.read(key: 'bio_username') ?? '';
        final password = await _secureStorage.read(key: 'bio_password') ?? '';

        if (username.isNotEmpty && password.isNotEmpty) {
          _usernameController.text = username;
          _passwordController.text = password;
          await _handleLogin(isBiometric: true);
        }
      }
    } on PlatformException catch (e) {
      print('[Biometric] Auth error: ${e.message}');
    }
  }

  Future<void> _toggleBiometric(bool enable) async {
    try {
      if (enable) {
        await _secureStorage.write(
            key: 'bio_username', value: _usernameController.text.trim());
        await _secureStorage.write(
            key: 'bio_password', value: _passwordController.text.trim());
        _biometricEnabled = true;
      } else {
        await _secureStorage.delete(key: 'bio_username');
        await _secureStorage.delete(key: 'bio_password');
        _biometricEnabled = false;
      }
      if (mounted) setState(() {});
    } catch (e) {
      print('[Biometric] Toggle error: $e');
    }
  }

  /// CORE LOGIC: Decide whether to show Welcome or Login based on Local Storage
  Future<void> _initPhase() async {
    final prefs = await SharedPreferences.getInstance();
    final storedDomain = prefs.getString('school_domain');

    // Start fetching schools immediately in background
    setState(() => _isFetchingSchools = true);
    
    try {
      await AppConfig.fetchSchoolListFromMainServer();
    } catch (e) {
      print('[LoginScreen] Failed to fetch schools: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingSchools = false);
        _filteredSchools = List.from(AppConfig.getAllSchools());
      }
    }

    if (storedDomain != null && storedDomain.isNotEmpty) {
      // ✅ SCHOOL ALREADY SELECTED: Go straight to Login
      if (mounted) {
        setState(() {
          _phase = _ScreenPhase.login;
        });
        
        // Auto-login if biometric is enabled
        if (_biometricEnabled) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) _authenticateWithBiometrics();
        }
      }
    } else {
      // ✅ NO SCHOOL SELECTED: Show Welcome Screen
      if (mounted) {
        setState(() {
          _phase = _ScreenPhase.welcome;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _schoolSearchController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  void _goToSelectSchool() {
    setState(() => _phase = _ScreenPhase.selectSchool);
  }

  Future<void> _selectSchool(Map<String, dynamic> school) async {
    final domain = school['domain']?.toString() ?? '';
    final name = school['name']?.toString() ?? 'Unknown School';
    final logo = school['logo']?.toString() ?? ''; 

    if (domain.isEmpty) {
      _showSnackBar('Invalid school configuration (No Domain).', Colors.red);
      return;
    }

    // Check Mobile App Permission
    bool hasMobileApp = school['have_mobile_app'] ?? true;
    bool loginEnabled = school['login_enabled'] ?? true;
    String status = school['status'] ?? 'Active';

    if (!hasMobileApp) {
      _showLicenseErrorDialog(
        'Mobile Access Disabled',
        'This school does not permit mobile app access.',
        subText: 'Please use the Web Portal at $domain',
      );
      return;
    }

    if (!loginEnabled || status != 'Active') {
      _showLicenseErrorDialog(
        'Access Restricted',
        'This school portal is currently unavailable or login is disabled.',
        subText: 'Status: $status',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await AppConfig.setBaseUrl(domain, name, logo);
      
      await Future.delayed(const Duration(milliseconds: 800));

      if (mounted) {
        setState(() {
          _isLoading = false;
          _phase = _ScreenPhase.login; 
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Failed to configure school: $e', Colors.red);
      }
    }
  }

  /// LOGOUT / CHANGE SCHOOL LOGIC
  Future<void> _resetToWelcome() async {
    await AppConfig.clearDomain();
    await _secureStorage.delete(key: 'bio_username');
    await _secureStorage.delete(key: 'bio_password');
    setState(() {
      _phase = _ScreenPhase.welcome;
      _biometricEnabled = false;
      _usernameController.clear();
      _passwordController.clear();
    });
  }

  Future<void> _sendFCMTokenToBackend(String userIdentifier) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        final url = Uri.parse(AppConfig.getUrl('api/auth/save_fcm_token'));
        await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': userIdentifier, 'fcm_token': token}),
        );
      }
    } catch (e) {
      print("Error saving FCM token: $e");
    }
  }

  void _showLicenseErrorDialog(String title, String message, {String? subText}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.4),
            ),
            if (subText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Text(
                  subText,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin({bool isBiometric = false}) async {
    final identifier = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter username and password', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Get FCM Token
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) { print('[FCM] Error: $e'); }

      // 2. Prepare Request
      final url = Uri.parse(AppConfig.getUrl('api/auth/login'));
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': identifier,
          'password': password,
          'fcm_token': fcmToken,
        }),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        String role = data['role'] ?? 'student';
        Map<String, dynamic> payloadData = data['data'] ?? {};

        String token = data['token'] ?? '';
        
        // 3. Determine the Correct Username/ID for Storage
        String sessionIdentifier = identifier; 
        
        if (role == 'staff') {
          sessionIdentifier = payloadData['staff_id'] ?? identifier;
        } else if (role == 'student') {
          sessionIdentifier = payloadData['std_id'] ?? identifier;
        } else if (role == 'parent') {
          sessionIdentifier = identifier; 
        }

        print('[Login] Stored Identifier: $sessionIdentifier for Role: $role');

        // 4. Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await prefs.setString('username', sessionIdentifier);
        await prefs.setString('role', role);

        // 5. Navigate
        _navigateBasedOnRole(role, sessionIdentifier);

        // Optional: Prompt for Biometric if not already enabled and login was manual
        if (!isBiometric && _biometricAvailable && !_biometricEnabled) {
           // We delay this slightly so navigation happens first, 
           // or you can choose to prompt before navigation. 
           // For now, we'll let them log in cleanly.
        }

      } else {
        // Handle Specific Errors
        String msg = data['message'] ?? 'Login Failed';
        String type = data['error_type'] ?? 'unknown';

        if (type == 'role_blocked') {
          _showLicenseErrorDialog('Access Denied', msg, subText: 'Your school has disabled login for ${data['role'] ?? 'this role'} in the mobile app.');
        } else if (type == 'app_disabled') {
          _showLicenseErrorDialog('App Disabled', msg, subText: 'Mobile app access is blocked by administration.');
        } else if (type == 'expired') {
          _showLicenseErrorDialog('Licence Expired', msg, subText: 'Please contact your school administrator.');
        } else if (type == 'no_licence') {
          _showLicenseErrorDialog('No Licence', msg, subText: 'This school is not registered on the platform.');
        } else {
          _showSnackBar(msg, Colors.red);
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Connection error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateBasedOnRole(String role, String username) {
    Widget dashboard;
    switch (role.toLowerCase()) {
      case 'admin':
      case 'clerk':
      case 'head':
        dashboard = AdminDashboard(username: username);
        break;
      case 'staff':
        dashboard = StaffDashboard(username: username);
        break;
      case 'parent':
        dashboard = ParentDashboard(username: username);
        break;
      case 'student':
      default:
        dashboard = StudentDashboard(username: username);
        break;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => dashboard));
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _filterSchools(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSchools = List.from(AppConfig.getAllSchools());
      } else {
        _filteredSchools = AppConfig.getAllSchools().where((s) {
          String name = s['name'] ?? '';
          String domain = s['domain'] ?? '';
          return name.toLowerCase().contains(query.toLowerCase()) ||
              domain.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Widget _buildSafeImage(String? url, {double size = 50}) {
    if (url == null || url.isEmpty) {
      return Icon(Icons.school, color: Color(0xFF3B82F6), size: size * 0.6);
    }

    String finalUrl = url;
    if (finalUrl.startsWith('http://')) {
      finalUrl = finalUrl.replaceFirst('http://', 'https://');
    } else if (!finalUrl.startsWith('https://')) {
      if (finalUrl.startsWith('/')) {
        finalUrl = AppConfig.mainServerUrl.replaceFirst('http://', 'https://') + finalUrl;
      } else {
        finalUrl = AppConfig.mainServerUrl.replaceFirst('http://', 'https://') + '/' + finalUrl;
      }
    }

    return Image.network(
      finalUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Icon(Icons.school, color: Color(0xFF3B82F6), size: size * 0.6);
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: size * 0.4,
            height: size * 0.4,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFF8FAFC)],
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _buildCurrentPhase(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPhase() {
    switch (_phase) {
      case _ScreenPhase.welcome:
        return _buildWelcomePhase();
      case _ScreenPhase.selectSchool:
        return _buildSelectSchoolPhase();
      case _ScreenPhase.login:
        return _buildLoginPhase();
    }
  }

  Widget _buildWelcomePhase() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    FadeInDown(
                      duration: const Duration(milliseconds: 800),
                      child: Center(
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B82F6).withOpacity(0.3),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    FadeInUp(
                      duration: const Duration(milliseconds: 900),
                      child: const Text(
                        "WELCOME TO",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeInUp(
                      duration: const Duration(milliseconds: 1000),
                      child: const Text(
                        "MIZORA SCHOOL MANAGEMENT\nSYSTEM",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    FadeInUp(
                      duration: const Duration(milliseconds: 1300),
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _goToSelectSchool,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: const Color(0xFF3B82F6).withOpacity(0.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Select Your School",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectSchoolPhase() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _isFetchingSchools = true);
            await AppConfig.fetchSchoolListFromMainServer();
            setState(() {
              _filteredSchools = List.from(AppConfig.getAllSchools());
              _isFetchingSchools = false;
            });
          },
          color: const Color(0xFF3B82F6),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => setState(() => _phase = _ScreenPhase.welcome),
                          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF64748B)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FadeInDown(
                        child: const Text(
                          "Select Your School",
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FadeInDown(
                        child: Text(
                          "Choose your institution to continue",
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeInUp(
                        child: _buildInputField(
                          controller: _schoolSearchController,
                          hint: "Search school by name...",
                          icon: Icons.search_rounded,
                          isPassword: false,
                          onChanged: _filterSchools,
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_isFetchingSchools)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Column(
                              children: [
                                CircularProgressIndicator(color: Color(0xFF3B82F6)),
                                SizedBox(height: 16),
                                Text("Loading Schools...", style: TextStyle(color: Colors.grey[600]))
                              ],
                            ),
                          ),
                        )
                      else if (_filteredSchools.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_off, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  "No schools found or connection failed.",
                                  style: TextStyle(color: Colors.grey[600], fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() => _isFetchingSchools = true);
                                    AppConfig.fetchSchoolListFromMainServer().then((_) {
                                      setState(() {
                                        _filteredSchools = List.from(AppConfig.getAllSchools());
                                        _isFetchingSchools = false;
                                      });
                                    });
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text("Retry Connection"),
                                )
                              ],
                            ),
                          ),
                        )
                      else
                        ..._filteredSchools.map((school) => FadeInUp(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: InkWell(
                                  onTap: () => _selectSchool(school),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.shade100,
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: _buildSafeImage(school['logo'], size: 50),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                school['name'],
                                                style: const TextStyle(
                                                  color: Color(0xFF1E293B), 
                                                  fontWeight: FontWeight.bold, 
                                                  fontSize: 15
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(Icons.link, size: 12, color: Colors.grey[500]),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      school['domain'],
                                                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (school['status'] != 'Active' || !(school['login_enabled'] ?? true))
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.red.shade200),
                                            ),
                                            child: Text(
                                              "Restricted",
                                              style: TextStyle(color: Colors.red.shade700, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          )
                                        else
                                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginPhase() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    FadeInDown(
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: _resetToWelcome,
                            icon: const Icon(Icons.home_rounded, size: 16, color: Color(0xFF3B82F6)),
                            label: const Text(
                              "Change School",
                              style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.link_rounded, size: 12, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    AppConfig.domainName,
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    FadeInDown(
                      duration: const Duration(milliseconds: 800),
                      child: GestureDetector(
                        onTap: _showInfoSheet,
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 80,
                                width: 80,
                                child: _buildSafeImage(AppConfig.currentClientLogo, size: 80),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppConfig.currentClientName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF1E293B),
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.info_outline_rounded, size: 13, color: Colors.grey[400]),
                                const SizedBox(width: 4),
                                Text(
                                  "Tap for instructions",
                                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    FadeInUp(
                      duration: const Duration(milliseconds: 900),
                      child: Text(
                        "Welcome back! Please login to continue.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 14, letterSpacing: 0.3),
                      ),
                    ),
                    const SizedBox(height: 32),
                    FadeInUp(
                      duration: const Duration(milliseconds: 1000),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade200,
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              "Sign In",
                              style: TextStyle(color: Colors.grey[800], fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 24),
                            _buildInputField(
                              controller: _usernameController,
                              hint: "Username, Email or CNIC",
                              icon: Icons.person_outline_rounded,
                              isPassword: false,
                            ),
                            const SizedBox(height: 14),
                            _buildInputField(
                              controller: _passwordController,
                              hint: "Password",
                              icon: Icons.lock_outline_rounded,
                              isPassword: true,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _showForgotPasswordLink,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF3B82F6),
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text("Forgot Password?", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : () => _handleLogin(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: const Color(0xFF3B82F6).withOpacity(0.4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                      )
                                    : const Text(
                                        "Login",
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                      ),
                              ),
                            ),

                            if (_biometricAvailable && _biometricEnabled) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading ? null : _authenticateWithBiometrics,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF3B82F6),
                                    side: const BorderSide(color: Color(0xFF3B82F6)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  icon: Icon(
                                    _biometricType == 'Face ID' ? Icons.face_retouching_natural : Icons.fingerprint_rounded,
                                    size: 24,
                                  ),
                                  label: Text(
                                    "Sign in with $_biometricType",
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.center,
                                child: TextButton(
                                  onPressed: () async {
                                    await _toggleBiometric(false);
                                    if (mounted) {
                                      _showSnackBar('$_biometricType login disabled', Colors.grey);
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    "Disable $_biometricType Login",
                                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isPassword,
    void Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        style: const TextStyle(color: Color(0xFF1E293B), fontSize: 14),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.grey[500],
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                    HapticFeedback.lightImpact();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  void _showInfoSheet() {
    final endpoint = AppConfig.getUrl('api/auth/login');
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text("Login Instructions", style: TextStyle(color: Color(0xFF1E293B), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _instructionRow("1", "Enter your registered username"),
              const SizedBox(height: 12),
              _instructionRow("2", "Enter your password"),
              const SizedBox(height: 12),
              _instructionRow("3", "Tap Login to access dashboard"),
              const SizedBox(height: 24),
              const Text("API Endpoint", style: TextStyle(color: Color(0xFF1E293B), fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, color: Color(0xFF3B82F6), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        endpoint,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instructionRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: TextStyle(color: Colors.grey[700], fontSize: 14, height: 1.4)),
        ),
      ],
    );
  }

  // --- NEW SIMPLIFIED FORGOT PASSWORD LOGIC ---

  void _showForgotPasswordLink() {
    // Construct the URL using AppConfig
    final resetUrl = AppConfig.getUrl('/auth/login'); 
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: Color(0xFF3B82F6)),
            SizedBox(width: 10),
            Text(
              'Reset Password',
              style: TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To reset your password, please visit the web portal.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.chrome_reader_mode, color: Colors.blue.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Open in Chrome / Browser',
                      style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              resetUrl,
              style: TextStyle(color: Colors.grey[500], fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _launchResetUrl(resetUrl);
            },
            child: const Text('Open Link'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchResetUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        // Launch in external application (Chrome/Safari)
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('Could not open link', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error opening link: $e', Colors.red);
    }
  }
}
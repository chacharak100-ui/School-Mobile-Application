import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AppConfig {
  // ─── MAIN SERVER CONFIGURATION ───
  static String mainServerUrl = 'https://aksoftware.info';

  // ─── CURRENT SCHOOL PORTAL CONFIGURATION (Dynamic) ───
  static String baseUrl = ''; 
  static String domainName = '';
  
  // Store Logo and Name for the Login Screen Header
  static String currentClientLogo = '';
  static String currentClientName = 'School Portal';

  // ─── NEW: GLOBAL MOBILE APP STATUS ───
  static String globalAppStatus = 'Active'; // 'Active' or 'Maintenance'
  static String globalMaintenanceMessage = '';
  static String globalAndroidLink = '';
  static String globalIosLink = '';

  // Cache for schools fetched from main server
  static List<Map<String, dynamic>> _dynamicSchools = [];
  static bool _isFetching = false;

  // ───────────────────────────────────────────────
  // Initialize from local storage on app startup
  // ───────────────────────────────────────────────
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Restore Last Used Domain
    final storedDomain = prefs.getString('school_domain');
    if (storedDomain != null && storedDomain.isNotEmpty) {
      baseUrl = storedDomain;
      domainName = _extractDomainName(storedDomain);
      currentClientName = prefs.getString('domain_name') ?? 'School Portal';
      currentClientLogo = prefs.getString('school_logo') ?? '';
    }

    // 2. Restore Global App Status from Local Storage (Fast Load)
    globalAppStatus = prefs.getString('global_app_status') ?? 'Active';
    globalMaintenanceMessage = prefs.getString('global_maintenance_msg') ?? '';
    globalAndroidLink = prefs.getString('global_android_link') ?? '';
    globalIosLink = prefs.getString('global_ios_link') ?? '';

    // 3. Fetch Fresh Status & School List from Main Server (Background)
    fetchGlobalAppStatus();
    fetchSchoolListFromMainServer();
  }

  // ───────────────────────────────────────────────
  // Fetch Global App Status (Maintenance Check)
  // ───────────────────────────────────────────────
  static Future<void> fetchGlobalAppStatus() async {
    try {
      final url = Uri.parse('$mainServerUrl/api/app-status');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          globalAppStatus = data['app_status'] ?? 'Active';
          globalMaintenanceMessage = data['maintenance_message'] ?? '';
          globalAndroidLink = data['android_app_link'] ?? '';
          globalIosLink = data['ios_app_link'] ?? '';

          // Save to local storage for next launch
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('global_app_status', globalAppStatus);
          await prefs.setString('global_maintenance_msg', globalMaintenanceMessage);
          await prefs.setString('global_android_link', globalAndroidLink);
          await prefs.setString('global_ios_link', globalIosLink);
        }
      }
    } catch (e) {
      print("Error fetching global app status: $e");
    }
  }

  // ───────────────────────────────────────────────
  // Fetch Schools from Main Server
  // ───────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchSchoolListFromMainServer() async {
    if (_isFetching) return _dynamicSchools;
    _isFetching = true;

    try {
      final url = Uri.parse('$mainServerUrl/api/clients/active-list');
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic>? rawList = data['schools'];

        if (rawList != null && rawList.isNotEmpty) {
          _dynamicSchools = rawList.map((item) {
            final map = item is Map ? item : {};
            bool intToBool(dynamic val) {
              if (val == null) return false;
              if (val is bool) return val;
              if (val is int) return val == 1;
              if (val is String) return val.toLowerCase() == 'true' || val == '1';
              return false;
            }
            
            return {
              'id': map['id']?.toString() ?? '', 
              'name': map['name']?.toString() ?? 'Unknown School',
              'domain': map['domain']?.toString() ?? '', 
              'logo': map['logo'], 
              'address': map['address']?.toString() ?? 'Online Campus',
              'login_enabled': intToBool(map['login_enabled']), 
              'have_mobile_app': intToBool(map['have_mobile_app']), 
              'status': map['status'] ?? 'Active',
            };
          }).toList();
        } else {
          _dynamicSchools = [];
        }
      }
    } catch (e) {
      print("Error fetching schools: $e");
    } finally {
      _isFetching = false;
    }
    
    return _dynamicSchools;
  }

  static List<Map<String, dynamic>> getAllSchools() {
    return _dynamicSchools;
  }

  static void clearSchoolCache() {
    _dynamicSchools = [];
  }

  // ───────────────────────────────────────────────
  // Set & persist a new school domain
  // ───────────────────────────────────────────────
  static Future<void> setBaseUrl(String url, String name, String logo) async {
    String normalized = url.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    
    baseUrl = normalized;
    domainName = _extractDomainName(normalized);
    currentClientName = name;
    currentClientLogo = logo ?? '';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('school_domain', normalized);
    await prefs.setString('domain_name', name);
    await prefs.setString('school_logo', logo ?? '');
  }

  // ───────────────────────────────────────────────
  // Clear stored domain (Logout / Change School)
  // ───────────────────────────────────────────────
  static Future<void> clearDomain() async {
    baseUrl = '';
    domainName = '';
    currentClientName = 'School Portal';
    currentClientLogo = '';
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('school_domain');
    await prefs.remove('domain_name');
    await prefs.remove('school_logo');
  }

  static String getCurrentBaseUrl() {
    return baseUrl;
  }

  static String getUrl(String endpoint) {
    if (baseUrl.isEmpty) return '$mainServerUrl/$endpoint';
    String cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    String cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return '$cleanBase$cleanEndpoint';
  }

  static String _extractDomainName(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return url.replaceAll(RegExp(r'^https?://'), '').split('/').first;
    }
  }

  // ─── HELPER TO CHECK MAINTENANCE ───
  static bool isAppInMaintenance() {
    return globalAppStatus.toLowerCase() == 'maintenance';
  }
}
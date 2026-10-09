import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:animate_do/animate_do.dart';
import '../../config/app_config.dart';
import '../login_screen.dart';

// Import screens
import 'profile.dart';
import 'attendance.dart';
import 'my-class.dart';
import 'timetable.dart'; // Ensure this file exists
import 'password.dart';

class StaffDashboard extends StatefulWidget {
  final String username;
  const StaffDashboard({super.key, required this.username});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> with TickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _staffData;
  Map<String, dynamic>? _permissions;
  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? _classAssignment;
  String? _errorMessage;

  // We still keep username for display/local logic if needed, but auth is via JWT
  late String _activeUsername;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _activeUsername = widget.username;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _fetchStaffData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchStaffData() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String? jwtToken = prefs.getString('jwt_token');
      final storedUsername = prefs.getString('username') ?? '';

      if (jwtToken == null || jwtToken.isEmpty) {
        _handleLogout();
        return;
      }

      // 1. Fetch Dashboard Data using JWT
      // Backend extracts user from Token, so no username param needed in URL
      final url = Uri.parse(AppConfig.getUrl('/api/staff/my-class'))
          .replace(queryParameters: {'username': storedUsername});


      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _staffData = data['staff'];
          _permissions = data['permissions'];
          _todayAttendance = data['today_attendance'];
          _isLoading = false;
          _errorMessage = null;
        });

        // 2. Check Class Assignment
        _checkClassAssignment(jwtToken);
        _animController.forward();
      } else {
        setState(() {
          _errorMessage = data['message'] ?? "Failed to load data";
          _isLoading = false;
        });
        if (response.statusCode == 401 || response.statusCode == 403) {
          _handleLogout();
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Network Error: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _checkClassAssignment(String? jwtToken) async {
    if (jwtToken == null) return;
    try {
      // Backend extracts user from Token
      final url = Uri.parse(AppConfig.getUrl('/api/staff/my-class'));

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _classAssignment = data['assignment'];
          });
        }
      }
    } catch (e) {
      debugPrint("Class check error: $e");
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final secureStorage = FlutterSecureStorage();
    await secureStorage.deleteAll();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String? get _photoUrl {
    if (_staffData == null) return null;
    final photo = _staffData!['photo_url'];
    if (photo != null && photo.toString().isNotEmpty && photo != 'None') {
      // Ensure photo URL is absolute if necessary, or rely on AppConfig
      return AppConfig.getUrl(photo);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Error")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _fetchStaffData, child: const Text("Retry")),
            ],
          ),
        ),
      );
    }

    if (_staffData == null) return const Scaffold(body: Center(child: Text("No Data")));

    final staff = _staffData!;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          staff['school_name'] ?? 'Staff Portal',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {},
          ),
          GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                child: _photoUrl == null ? const Icon(Icons.person, size: 16, color: Color(0xFF1A3A4F)) : null,
              ),
            ),
          ),
        ],
      ),
      drawer: _buildModernDrawer(staff),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          onRefresh: _fetchStaffData,
          color: const Color(0xFF1A3A4F),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildSliverHeader(staff),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      
                      // Quick Stats Row
                      _buildQuickStatsRow(),
                      
                      const SizedBox(height: 24),
                      
                      // Attendance Status Card
                      _buildAttendanceStatusCard(),
                      
                      const SizedBox(height: 24),
                      
                      // Class Assignment Info
                      _buildInfoGroup(
                        title: 'Class Assignment',
                        icon: Icons.class_,
                        color: const Color(0xFF6C5CE7),
                        items: [
                          ('Class', _classAssignment?['class_name'] ?? 'Not Assigned'),
                          ('Section', _classAssignment?['section'] ?? '-'),
                          ('Subject', _classAssignment?['subject'] ?? '-'),
                          ('Session', _staffData!['session'] ?? '2025-2026'),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Personal Details
                      _buildInfoGroup(
                        title: 'Employment Details',
                        icon: Icons.badge_outlined,
                        color: const Color(0xFF00B894),
                        items: [
                          ('Staff ID', _staffData!['staff_id']),
                          ('Designation', _staffData!['designation'] ?? 'Teacher'),
                          ('Department', _staffData!['department'] ?? 'Academic'),
                          ('Joining Date', _staffData!['joining_date'] ?? '-'),
                        ],
                      ),
                      
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliverHeader(Map<String, dynamic> staff) {
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A3A4F), Color(0xFF2D5F7C), Color(0xFF4A90D9)],
          ),
          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Hero(
                tag: 'staff-avatar-large',
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 3),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)],
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white,
                    backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                    child: _photoUrl == null ? const Icon(Icons.person, size: 50, color: Color(0xFF2D5F7C)) : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                staff['name'] ?? 'Staff Member',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Text(
                  "${staff['designation'] ?? 'Teacher'} • ${staff['department'] ?? 'Academic'}",
                  style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard(
          icon: Icons.fingerprint, 
          label: 'Attendance', 
          value: 'View', 
          color: const Color(0xFF00B894), 
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen()))
        )),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(
          icon: Icons.calendar_today, 
          label: 'Timetable', 
          value: 'View', 
          color: const Color(0xFF6C5CE7), 
          // Pass username if required by timetable constructor, otherwise remove
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StaffTimetableScreen(username: _activeUsername)))
        )),
      ],
    );
  }

  Widget _buildStatCard({required IconData icon, required String label, required String value, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(16), 
          boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))]
        ),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 22)),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildAttendanceStatusCard() {
    final att = _todayAttendance;
    final status = att?['status'] ?? 'Not Marked';
    final isInSchool = att?['current_status'] == 'In School';
    
    Color cardColor = isInSchool ? const Color(0xFF00B894) : (status == 'Absent' ? Colors.red : Colors.orange);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cardColor, cardColor.withOpacity(0.7)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: cardColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(isInSchool ? Icons.check_circle : Icons.warning_amber_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isInSchool ? "You are Present" : "Today's Status: $status",
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  att?['entry_time'] != null ? "Entry: ${att?['entry_time']}" : "Mark your attendance now",
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                ),
              ],
            ),
          ),
          if (!isInSchool && status == 'Not Marked')
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen())),
              icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
            )
        ],
      ),
    );
  }

  Widget _buildInfoGroup({required String title, required IconData icon, required Color color, required List<(String, dynamic)> items}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(color: color.withOpacity(0.06), border: Border(bottom: BorderSide(color: color.withOpacity(0.1)))),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
                const SizedBox(width: 12),
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.withOpacity(0.9))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final (label, value) = entry.value;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 400 + (index * 80)),
                    curve: Curves.easeOut,
                    builder: (context, anim, child) {
                      return Opacity(opacity: anim, child: Transform.translate(offset: Offset(20 * (1 - anim), 0), child: child));
                    },
                    child: _buildInfoTile(label, value, isLast: index == items.length - 1),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, dynamic value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 7), decoration: BoxDecoration(color: Colors.grey[400], shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500, letterSpacing: 0.3)),
            const SizedBox(height: 2),
            Text(value?.toString() ?? 'N/A', style: const TextStyle(fontSize: 14, color: Color(0xFF2D3E50), fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildModernDrawer(Map<String, dynamic> staff) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              staff['name'] ?? 'Staff Member',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
            ),
            accountEmail: Text(
              "ID: ${staff['staff_id']} • ${staff['designation']}",
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.grey[200],
              backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
              child: _photoUrl == null ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDrawerItem(Icons.dashboard_outlined, 'Dashboard', () => Navigator.pop(context)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Divider(height: 1)),
                
                _buildDrawerItem(Icons.person_outline, 'My Profile', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(username: _activeUsername)));
                }),
                _buildDrawerItem(Icons.fingerprint, 'My Attendance', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen()));
                }),
                _buildDrawerItem(Icons.calendar_today_outlined, 'Timetable', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StaffTimetableScreen(username: _activeUsername)));
                }),
                
                const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Divider(height: 1)),
                
                _buildDrawerItem(Icons.people_alt_outlined, 'My Class', () {
                  Navigator.pop(context);
                  if (_classAssignment != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ClassDashboardScreen()));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No class assigned")));
                  }
                }),
                _buildDrawerItem(Icons.lock_reset, 'Reset Password', () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffResetPasswordScreen()));
                }),
          
                const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Divider()),
                
                _buildDrawerItem(Icons.exit_to_app, 'Logout', _handleLogout, color: Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.black87, size: 22),
      title: Text(title, style: TextStyle(color: color ?? Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      minLeadingWidth: 20,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: Colors.grey[100],
    );
  }
}
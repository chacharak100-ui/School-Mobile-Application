import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import '../../config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// Ensure these imports match your actual file structure
import '../login_screen.dart';
import 'fees.dart';
import 'attendance.dart';
import 'acadamic.dart';
import 'reset_password.dart';
import 'leave.dart';
import 'complain.dart';
import 'vault.dart';
import 'scan_attendance.dart';
import 'assignments.dart';
import 'timetable.dart';
import 'idcard.dart';
import 'exam_schedule.dart'; // Ensure this file exists

class StudentDashboard extends StatefulWidget {
  final String? username;

  const StudentDashboard({super.key, this.username});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> with TickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _studentData;
  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? _schoolData;
  String _schoolName = 'School Portal';
  String _errorMessage = '';
  
  // Exam Schedule State
  bool _showExamButton = false;
  String _examTitle = "Exams";

  // Animations
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  
  // Timer for Exit Window
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    
    // Initialize Data
    _initializeDashboard();
    
    // Timer for UI updates (Exit window check)
    _timer = Timer.periodic(const Duration(minutes: 1), (t) {
      if(mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // --- HELPER: Get Unified Identifier ---
  Future<String?> _getIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    // Priority: Stored Username -> Stored Std_ID -> Widget Argument
    return prefs.getString('username') ?? prefs.getString('std_id') ?? widget.username;
  }

  Future<void> _initializeDashboard() async {
    final identifier = await _getIdentifier();

    if (identifier == null || identifier.isEmpty) {
      setState(() {
        _errorMessage = 'Session expired. Please log in again.';
        _isLoading = false;
      });
      return;
    }

    // Fetch Data in Parallel
    await Future.wait([
      _fetchStudentData(identifier),
      _fetchTodayAttendance(identifier),
      _checkExamSchedule(identifier),
    ]);
  }

  Future<void> _fetchStudentData(String identifier) async {
    try {
      final url = Uri.parse(AppConfig.getUrl('/api/student/profile'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': identifier}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _studentData = data['student'];
            _schoolData = data['school'];
            if (data['school'] != null && data['school']['school_name'] != null) {
              _schoolName = data['school']['school_name'];
            }
            _isLoading = false;
          });
          _animController.forward();
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to load profile.';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server Error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Connection error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchTodayAttendance(String identifier) async {
    try {
      final url = Uri.parse(AppConfig.getUrl('/api/student/today-attendance'))
          .replace(queryParameters: {'username': identifier});
      
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _todayAttendance = data['attendance'];
          });
        }
      }
    } catch (_) {
      // Silently fail for attendance check
    }
  }

  Future<void> _checkExamSchedule(String identifier) async {
    try {
      final url = Uri.parse(await AppConfig.getUrl('/api/student/exam-schedule'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': identifier}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            _showExamButton = data['show_button'];
            if (_showExamButton && data['exam_name'] != "No Exam") {
              _examTitle = data['exam_name'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Exam Check Error: $e");
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  String? get _photoUrl {
    if (_studentData == null) return null;
    final photo = _studentData!['photo'];
    if (photo != null && photo.toString().isNotEmpty && photo != 'None') {
      return AppConfig.getUrl('api/student/view_photo/$photo');
    }
    return null;
  }

  // --- HELPER: Parse Time from String (HH:mm:ss) ---
  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null) return null;
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return null;
    }
  }

  bool _isSchoolOpenForEntry() {
    if (_schoolData == null) return true;
    final startStr = _schoolData!['school_start_time'];
    final endStr = _schoolData!['school_end_time'];
    final startTime = _parseTime(startStr);
    final endTime = _parseTime(endStr);
    if (startTime == null || endTime == null) return true;
    final now = TimeOfDay.fromDateTime(_now);
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    final nowMinutes = now.hour * 60 + now.minute;
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }

  bool _isExitWindowOpen() {
    if (_schoolData == null) return false;
    final endStr = _schoolData!['school_end_time'];
    final endTime = _parseTime(endStr);
    if (endTime == null) return false;
    final exitStart = TimeOfDay(hour: endTime.hour - 2, minute: endTime.minute);
    final exitEnd = TimeOfDay(hour: endTime.hour + 1, minute: endTime.minute);
    final now = TimeOfDay.fromDateTime(_now);
    final startMinutes = exitStart.hour * 60 + exitStart.minute;
    final endMinutes = exitEnd.hour * 60 + exitEnd.minute;
    final nowMinutes = now.hour * 60 + now.minute;
    return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _schoolName,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {},
          ),
          if (_studentData != null)
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
                  child: _photoUrl == null ? const Icon(Icons.person, size: 16, color: Color(0xFF2D5F7C)) : null,
                ),
              ),
            ),
        ],
      ),
      drawer: _buildModernDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D5F7C)))
          : _errorMessage.isNotEmpty
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _initializeDashboard,
                  color: const Color(0xFF2D5F7C),
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      _buildSliverHeader(),
                      SliverToBoxAdapter(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                const SizedBox(height: 24),
                                _buildSmartAttendanceCard(),
                                const SizedBox(height: 24),
                                _buildQuickStatsRow(),
                                const SizedBox(height: 24),
                                _buildInfoGroup(
                                  title: 'Academic Information',
                                  icon: Icons.school_outlined,
                                  color: const Color(0xFF4A90D9),
                                  items: [
                                    ('Current Class', _studentData!['current_class']),
                                    ('Section', _studentData!['section']),
                                    ('Shift', _studentData!['shift']),
                                    ('Session', _studentData!['session']),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildInfoGroup(
                                  title: 'Personal Details',
                                  icon: Icons.person_outline,
                                  color: const Color(0xFF50C878),
                                  items: [
                                    ('Student ID', _studentData!['std_id']),
                                    ('Father Name', _studentData!['father_name']),
                                    ('Blood Group', _studentData!['blood_group']),
                                  ],
                                ),
                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSmartAttendanceCard() {
    final att = _todayAttendance;
    if (att != null && att['current_status'] == 'In School') {
      final entryTime = att['entry_time'] ?? 'N/A';
      final isExitOpen = _isExitWindowOpen();
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF50C878).withOpacity(0.3)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF50C878).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_circle, color: Color(0xFF50C878), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        att['status'] == 'Leave' ? "On Leave (But In School)" : "You are Present",
                        style: const TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text("Entered at $entryTime", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isExitOpen)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanAttendanceScreen())),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text("Mark Exit Now"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE67E50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text("Exit window closed", style: TextStyle(color: Colors.grey, fontSize: 13))),
              ),
          ],
        ),
      );
    }
    if (att != null && att['current_status'] == 'Left') return const SizedBox.shrink();
    if (att != null && (att['status'] == 'Absent' || att['status'] == 'Leave')) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withOpacity(0.2))),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.red[400], size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Status: ${att['status']}", style: const TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.bold)),
                  Text("No attendance action required.", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (att == null && _isSchoolOpenForEntry()) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF2D5F7C), Color(0xFF4A90D9)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF2D5F7C).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Attendance Not Marked", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text("Scan QR to mark present", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanAttendanceScreen())),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text("Scan Now"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2D5F7C),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (att == null && !_isSchoolOpenForEntry()) {
       return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(Icons.lock_clock, color: Colors.grey[600], size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("School Closed", style: TextStyle(color: Colors.grey[800], fontSize: 16, fontWeight: FontWeight.bold)),
                  Text("Attendance scanning is currently disabled.", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSliverHeader() {
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
                tag: 'student-avatar-large',
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
                _studentData!['name'] ?? 'N/A',
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
                  "Class ${_studentData!['current_class'] ?? 'N/A'} • Sec ${_studentData!['section'] ?? 'N/A'}",
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
        Expanded(child: _buildStatCard(icon: Icons.assignment_rounded, label: 'Results', value: 'View', color: const Color(0xFF50C878), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentAcademicScreen(username: _getIdentifierSync()))))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(icon: Icons.payment_rounded, label: 'Fees', value: 'View', color: const Color(0xFFE67E50), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentFeeScreen(username: _getIdentifierSync()))))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(icon: Icons.support_agent_rounded, label: 'Help', value: 'Support', color: const Color(0xFF4A90D9), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentComplaintsScreen(username: _getIdentifierSync()))))),
      ],
    );
  }

  // Helper to get identifier synchronously for onTap callbacks (since it's already loaded in prefs)
  String _getIdentifierSync() {
     // Note: In a real app, you might want to store this in a variable after init
     // For now, we assume widget.username or a cached value is safe, 
     // but since we can't await in onTap, we pass a placeholder or rely on the screen fetching it itself.
     // Ideally, screens should fetch their own ID from prefs.
     return widget.username ?? ""; 
  }

  Widget _buildStatCard({required IconData icon, required String label, required String value, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))]),
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

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(_errorMessage, style: TextStyle(color: Colors.red[700], fontSize: 16, height: 1.5), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: _initializeDashboard, icon: const Icon(Icons.refresh), label: const Text('Retry'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D5F7C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
      ),
    );
  }

  // --- WHITE THEME DRAWER WITH PROFILE HEADER ---
  Widget _buildModernDrawer() {
    // Use a future builder or just pass empty if not loaded, but usually drawer is opened after load
    final name = _studentData?['name'] ?? 'Student Name';
    final id = _studentData?['std_id'] ?? '---';

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // Compact Profile Header
          UserAccountsDrawerHeader(
            accountName: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
            ),
            accountEmail: Text(
              "ID: $id",
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.grey[200],
              backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
              child: _photoUrl == null ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC), // Light grey header background
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDrawerItem(Icons.dashboard_outlined, 'Dashboard', () => Navigator.pop(context)),
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(height: 1),
                ),
                
                // Attendance Section
                _buildDrawerItem(Icons.fingerprint, 'Attendance', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentAttendanceScreen(username: widget.username ?? ""))); 
                }),
                
                // Timetable Section
                _buildDrawerItem(Icons.calendar_today_outlined, 'Timetable', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentTimetableScreen(username: widget.username ?? ""))); 
                }),

                // --- CONDITIONAL EXAM SCHEDULE BUTTON ---
                if (_showExamButton)
                  _buildDrawerItem(
                    Icons.event_note, 
                    'Exam Schedule', 
                    () { 
                      Navigator.pop(context); 
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamScheduleScreen())); 
                    },
                    isNew: true, // Adds a visual indicator
                  ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(height: 1),
                ),

                // Academic & Fees
                _buildDrawerItem(Icons.assignment_outlined, 'Exams & Results', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentAcademicScreen(username: widget.username ?? ""))); 
                }),
                _buildDrawerItem(Icons.payment_outlined, 'Fee Ledger', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentFeeScreen(username: widget.username ?? ""))); 
                }),
                _buildDrawerItem(Icons.book_outlined, 'Assignments', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentAssignmentsScreen(username: widget.username ?? ""))); 
                }),
                
                // Support & Tools
                _buildDrawerItem(Icons.badge_outlined, 'ID Card', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentIdCardScreen(username: widget.username ?? ""))); 
                }),
                _buildDrawerItem(Icons.report_problem_outlined, 'Complaints', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentComplaintsScreen(username: widget.username ?? ""))); 
                }),
                _buildDrawerItem(Icons.event_busy_outlined, 'Leaves', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentLeaveScreen(username: widget.username ?? ""))); 
                }),
                _buildDrawerItem(Icons.vpn_key_outlined, 'My Vault', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentVaultScreen(username: widget.username ?? ""))); 
                }),
                _buildDrawerItem(Icons.lock_outline, 'Reset Password', () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ResetPasswordScreen(username: widget.username ?? ""))); 
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

  // Updated Helper to support 'isNew' badge
  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {Color? color, bool isNew = false}) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: color ?? Colors.black87, size: 22),
          if (isNew)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(title, style: TextStyle(color: color ?? Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
          if (isNew)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: const Text("NEW", style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      minLeadingWidth: 20,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      hoverColor: Colors.grey[100],
    );
  }
}
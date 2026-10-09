import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import '../login_screen.dart'; // Import for logout navigation

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  List<dynamic> _history = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAttendanceData();
  }

  Future<void> _fetchAttendanceData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jwtToken = prefs.getString('jwt_token');
      final storedUsername = prefs.getString('username') ?? '';

      if (jwtToken == null || jwtToken.isEmpty) {
        _handleLogout();
        return;
      }

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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _stats = data['stats'];
            _history = data['history'] ?? [];
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = data['message'] ?? "Failed to load attendance";
            _isLoading = false;
          });
          if (response.statusCode == 401 || response.statusCode == 403) {
            _handleLogout();
          }
        }
      } else {
        setState(() {
          _errorMessage = "Server Error: ${response.statusCode}";
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

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("My Attendance", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF1A3A4F),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3A4F)))
          : _errorMessage != null
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _fetchAttendanceData,
                  color: const Color(0xFF1A3A4F),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- 1. CURRENT MONTH PERFORMANCE CARD ---
                        _buildPerformanceCard(),
                        
                        const SizedBox(height: 24),

                        // --- 2. LIFETIME OVERVIEW ---
                        const Text(
                          "LIFETIME STATISTICS",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(child: _buildStatIconCard("${_stats!['life_present']}", "Present", Icons.check_circle, Colors.green)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildStatIconCard("${_stats!['life_leave']}", "Leave", Icons.event_busy, Colors.orange)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildStatIconCard("${_stats!['life_absent']}", "Absent", Icons.cancel, Colors.red)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        
                        // Total & Ratio Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade100),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSummaryItem("${_stats!['life_total']}", "Total Days", Colors.black87),
                              Container(width: 1, height: 30, color: Colors.grey.shade200),
                              _buildSummaryItem("${_stats!['life_ratio']}%", "Avg. Ratio", const Color(0xFF1A3A4F)),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- 3. RECENT HISTORY TIMELINE ---
                        Row(
                          children: [
                            const Icon(Icons.history, size: 18, color: Color(0xFF1A3A4F)),
                            const SizedBox(width: 8),
                            const Text(
                              "RECENT HISTORY",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A3A4F), letterSpacing: 1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        _history.isEmpty 
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  children: [
                                    Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                                    const SizedBox(height: 10),
                                    Text("No attendance records found", style: TextStyle(color: Colors.grey.shade500)),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _history.length,
                              itemBuilder: (context, index) {
                                return _buildTimelineItem(_history[index], index == _history.length - 1);
                              },
                            ),
                        
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildPerformanceCard() {
    final s = _stats!;
    final mRatio = (s['m_ratio'] ?? 0).toDouble();
    
    Color ratioColor = Colors.green;
    String ratioStatus = "EXCELLENT";
    if (mRatio < 50) {
      ratioColor = Colors.red;
      ratioStatus = "NEEDS IMPROVEMENT";
    } else if (mRatio < 75) {
      ratioColor = Colors.orange;
      ratioStatus = "GOOD PROGRESS";
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${s['current_month']} Performance",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  Text("Current Month Metrics", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ratioColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ratioStatus,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: ratioColor),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Big Percentage
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${mRatio.toStringAsFixed(1)}%",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: ratioColor),
              ),
              const SizedBox(width: 8),
              Text(
                "Attendance Rate",
                style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Mini Stats Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMiniStat("${s['m_present']}", "Present", Colors.green),
                _buildDivider(),
                _buildMiniStat("${s['m_leave']}", "Leave", Colors.orange),
                _buildDivider(),
                _buildMiniStat("${s['m_absent']}", "Absent", Colors.red),
                _buildDivider(),
                _buildMiniStat("${s['m_total']}", "Days", Colors.black87),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: mRatio / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(ratioColor),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatIconCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildMiniStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(height: 20, width: 1, color: Colors.grey.shade200);
  }

  Widget _buildTimelineItem(Map<String, dynamic> att, bool isLast) {
    final dateStr = att['date'] ?? '--';
    final status = att['status'] ?? 'Unknown';
    
    // Parse Date
    List<String> dateParts = dateStr.split('-');
    String day = dateParts.length > 2 ? dateParts[2] : '??';
    String month = dateParts.length > 1 ? dateParts[1] : 'MON';

    Color markerColor = Colors.grey;
    Color badgeBg = Colors.grey.shade100;
    Color badgeText = Colors.grey.shade700;
    IconData statusIcon = Icons.help;

    if (status == 'Present') {
      markerColor = Colors.green;
      badgeBg = Colors.green.shade50;
      badgeText = Colors.green.shade700;
      statusIcon = Icons.check;
    } else if (status == 'Absent') {
      markerColor = Colors.red;
      badgeBg = Colors.red.shade50;
      badgeText = Colors.red.shade700;
      statusIcon = Icons.close;
    } else if (status == 'Leave') {
      markerColor = Colors.orange;
      badgeBg = Colors.orange.shade50;
      badgeText = Colors.orange.shade700;
      statusIcon = Icons.event_busy;
    }

    return Stack(
      children: [
        // Timeline Line
        Positioned(
          left: 10,
          top: 0,
          bottom: isLast ? 20 : 0,
          child: Container(width: 2, color: Colors.grey.shade200),
        ),
        
        Padding(
          padding: const EdgeInsets.only(bottom: 16, left: 30),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // Day Box
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(day, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                          Text(month, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                        Text("Verified Entry", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
                
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeBg.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: badgeText),
                      const SizedBox(width: 4),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Timeline Marker Dot
        Positioned(
          left: 4,
          top: 15,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: markerColor.withOpacity(0.3), blurRadius: 4)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchAttendanceData, 
            child: const Text("Retry"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3A4F)),
          ),
        ],
      ),
    );
  }
}
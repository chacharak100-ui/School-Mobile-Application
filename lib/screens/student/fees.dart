import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class StudentFeeScreen extends StatefulWidget {
  final String username;
  const StudentFeeScreen({super.key, required this.username});

  @override
  State<StudentFeeScreen> createState() => _StudentFeeScreenState();
}

class _StudentFeeScreenState extends State<StudentFeeScreen> {
  bool isLoading = true;
  String schoolName = 'School Management System'; // Default fallback
  Map<String, dynamic>? currentMonthStatus;
  List<dynamic> feeHistory = [];
  double totalArrears = 0.0;

  String? selectedMonth;
  String? selectedYear;
  String? selectedFeeType;
  String? selectedStatus;

  final List<String> months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final List<String> years = ['2024', '2025', '2026', '2027'];
  final List<String> feeTypes = ['Tuition Fee', 'Admission Fee', 'Exam Fee', 'Transport Fee', 'Library Fee', 'Other'];
  final List<String> statuses = ['Paid', 'Pending', 'Partial', 'Unpaid'];

  @override
  void initState() {
    super.initState();
    fetchFeeData();
  }

  Future<void> fetchFeeData() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('username') ?? prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('api/student/fees-history'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'std_id': stdId,
          'month': selectedMonth,
          'year': selectedYear,
          'fee_type': selectedFeeType,
          'status': selectedStatus,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          schoolName = data['school_name'] ?? 'School Management System';
          currentMonthStatus = data['current_month_status'];
          totalArrears = (data['total_arrears'] ?? 0.0).toDouble();
          feeHistory = data['history'];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Fee Fetch Exception: $e');
      setState(() => isLoading = false);
    }
  }

  void _resetFilters() {
    setState(() {
      selectedMonth = null;
      selectedYear = null;
      selectedFeeType = null;
      selectedStatus = null;
    });
    fetchFeeData();
  }

  void _showFeeReceiptModal(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Fee Payment Receipt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Column(
                      children: [
                        const Icon(Icons.receipt_long, size: 48, color: Color.fromRGBO(110, 115, 225, 1)),
                        const SizedBox(height: 8),
                        Text(schoolName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Text('Official Fee Voucher Receipt', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const Divider(height: 24),
                      ],
                    ),
                  ),
                  _receiptRow('Fee Type:', '${item['fee_type']}'),
                  _receiptRow('Billing Month:', '${item['month']} ${item['year']}'),
                  _receiptRow('Challan No:', '${item['challan_no']}'),
                  _receiptRow('Transaction ID:', '${item['trx_id'] ?? 'N/A'}'),
                  _receiptRow('Payment Status:', '${item['status']}'),
                  _receiptRow('Payment Method:', '${item['payment_method'] ?? 'N/A'}'),
                  _receiptRow('Bank Name:', '${item['bank_name'] ?? 'N/A'}'),
                  _receiptRow('Payment Date:', '${item['payment_date'] ?? item['created_at'] ?? 'N/A'}'),
                  const Divider(height: 24),
                  _receiptRow('Total Payable:', 'Rs. ${item['payable_amount']}', isBold: true),
                  _receiptRow('Amount Paid:', 'Rs. ${item['paid_amount']}', isBold: true, color: Colors.green),
                  _receiptRow('Remaining Balance:', 'Rs. ${item['balance']}', isBold: true, color: Colors.redAccent),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color.fromRGBO(110, 115, 225, 1)),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _receiptRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fee Management & Ledger'),
        backgroundColor: const Color.fromRGBO(110, 115, 225, 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: fetchFeeData,
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            tooltip: 'Clear Filters',
            onPressed: _resetFilters,
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchFeeData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildFilterSection(),
                  const SizedBox(height: 16),
                  if (totalArrears > 0) ...[
                    _buildArrearsBanner(),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    'Current Month Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 8),
                  _buildCurrentMonthCard(currentMonthStatus),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Payment History Ledger',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text('${feeHistory.length} Records', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  feeHistory.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('No payment records match criteria.')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: feeHistory.length,
                          itemBuilder: (context, index) {
                            return _buildFeeHistoryCard(feeHistory[index]);
                          },
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterSection() {
    return ExpansionTile(
      title: const Text('Advanced Multi-Filters', style: TextStyle(fontWeight: FontWeight.w600)),
      leading: const Icon(Icons.filter_list, color: Color.fromRGBO(110, 115, 225, 1)),
      backgroundColor: Colors.grey.shade50,
      collapsedBackgroundColor: Colors.grey.shade100,
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: selectedMonth,
                decoration: const InputDecoration(labelText: 'Filter by Month', border: OutlineInputBorder()),
                items: months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) => setState(() => selectedMonth = val),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedYear,
                decoration: const InputDecoration(labelText: 'Filter by Year', border: OutlineInputBorder()),
                items: years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                onChanged: (val) => setState(() => selectedYear = val),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedFeeType,
                decoration: const InputDecoration(labelText: 'Filter by Fee Type', border: OutlineInputBorder()),
                items: feeTypes.map((ft) => DropdownMenuItem(value: ft, child: Text(ft))).toList(),
                onChanged: (val) => setState(() => selectedFeeType = val),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedStatus,
                decoration: const InputDecoration(labelText: 'Filter by Status', border: OutlineInputBorder()),
                items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() => selectedStatus = val),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color.fromRGBO(110, 115, 225, 1)),
                icon: const Icon(Icons.search, color: Colors.white),
                label: const Text('Apply Filters', style: TextStyle(color: Colors.white)),
                onPressed: fetchFeeData,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildArrearsBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Outstanding Arrears Detected', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                Text('Total Due Arrears: Rs. $totalArrears', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentMonthCard(Map<String, dynamic>? data) {
    if (data == null) return const SizedBox.shrink();

    bool isPaid = data['status'] == 'Paid';
    Color statusColor = isPaid ? Colors.green : (data['status'] == 'Partial' ? Colors.orange : Colors.red);
    IconData statusIcon = isPaid ? Icons.check_circle : Icons.warning;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: [Colors.white, isPaid ? Colors.green.shade50 : Colors.red.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.indigo, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${data['fee_type']} (${data['month']} ${data['year']})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Chip(
                  avatar: Icon(statusIcon, color: Colors.white, size: 16),
                  label: Text(data['status'], style: const TextStyle(color: Colors.white)),
                  backgroundColor: statusColor,
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _amountColumn('Payable', 'Rs. ${data['payable_amount']}'),
                _amountColumn('Paid', 'Rs. ${data['paid_amount']}'),
                _amountColumn('Balance', 'Rs. ${data['balance']}'),
              ],
            ),
            const SizedBox(height: 10),
            Text('Challan No: ${data['challan_no']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (data['trx_id'] != null)
              Text('Transaction ID: ${data['trx_id']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeeHistoryCard(Map<String, dynamic> item) {
    bool isPaid = item['status'] == 'Paid';
    Color badgeColor = isPaid ? Colors.green : (item['status'] == 'Partial' ? Colors.orange : Colors.red);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showFeeReceiptModal(item),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${item['fee_type']} - ${item['month']} ${item['year']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item['status'],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Challan: ${item['challan_no']}'),
                  Text('Method: ${item['payment_method'] ?? 'N/A'}'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Payable: Rs. ${item['payable_amount']}'),
                  Text('Balance: Rs. ${item['balance']}', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              if (item['trx_id'] != null && item['trx_id'].toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Trx ID: ${item['trx_id']}', style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
              ],
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('Tap to view receipt ➔', style: TextStyle(fontSize: 11, color: Colors.indigo, fontStyle: FontStyle.italic)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
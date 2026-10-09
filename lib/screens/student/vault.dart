import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
// REMOVED: import 'dart:io'; // Not supported on Web

import '../../config/app_config.dart';

class StudentVaultScreen extends StatefulWidget {
  final String username;
  const StudentVaultScreen({super.key, required this.username});

  @override
  State<StudentVaultScreen> createState() => _StudentVaultScreenState();
}

class _StudentVaultScreenState extends State<StudentVaultScreen> {
  bool _isUnlocked = false;
  bool _isLoading = true;
  bool _hasVaultPass = true;
  List<dynamic> _vaultItems = [];

  final TextEditingController _passController = TextEditingController();
  final TextEditingController _setupPassController = TextEditingController();
  final TextEditingController _confirmSetupPassController = TextEditingController();

  // New item form controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _itemPassController = TextEditingController();
  
  // FIXED: Use PlatformFile instead of dart:io File
  PlatformFile? _selectedPlatformFile; 

  // Real-time security criteria states
  bool _hasMinLength = false;
  bool _hasLetter = false;
  bool _hasNumber = false;
  bool _passwordsMatch = true;

  @override
  void initState() {
    super.initState();
    _setupPassController.addListener(_validateVaultPasswordRealTime);
    _confirmSetupPassController.addListener(_validateVaultPasswordRealTime);
    _checkVaultSecurityStatus();
  }

  void _validateVaultPasswordRealTime() {
    final val = _setupPassController.text;
    final confirmVal = _confirmSetupPassController.text;
    setState(() {
      _hasMinLength = val.length >= 8;
      _hasLetter = RegExp(r'[A-Za-z]').hasMatch(val);
      _hasNumber = RegExp(r'[0-9]').hasMatch(val);
      _passwordsMatch = val == confirmVal;
    });
  }

  Future<void> _checkVaultSecurityStatus() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('api/student/vault/verify-security'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'std_id': stdId, 'username': widget.username, 'vault_password': ''}),
      );

      final data = jsonDecode(response.body);
      if (data['has_vault_pass'] == false) {
        setState(() {
          _hasVaultPass = false;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyPassword() async {
    if (_passController.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('api/student/vault/verify-security'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'std_id': stdId,
          'username': widget.username,
          'vault_password': _passController.text.trim(),
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _isUnlocked = true;
          _isLoading = false;
        });
        _fetchVaultItems();
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Incorrect password'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error checking security.'), backgroundColor: Colors.red));
    }
  }

  Future<void> _setupVaultPassword() async {
    if (!_hasMinLength || !_hasLetter || !_hasNumber || !_passwordsMatch) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please satisfy all strict password requirements.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('api/student/vault/setup-security'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'std_id': stdId,
          'username': widget.username,
          'vault_password': _setupPassController.text.trim(),
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _hasVaultPass = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vault security secured successfully!'), backgroundColor: Colors.green));
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchVaultItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('api/student/vault/items?std_id=$stdId&username=${widget.username}'));
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _vaultItems = data['items'] ?? []);
      }
    } catch (_) {}
  }

  // FIXED: Updated pick file logic for Web & Mobile compatibility
  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xls', 'xlsx', 'png', 'jpg', 'jpeg'],
    );

    if (result != null && result.files.isNotEmpty) {
      final pickedFile = result.files.single;
      
      // Check size (bytes)
      if (pickedFile.size > 5 * 1024 * 1024) { // 5 MB
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File size exceeds 5 MB limit.'), backgroundColor: Colors.red),
        );
        return;
      }

      setState(() => _selectedPlatformFile = pickedFile);
    }
  }

  // FIXED: Updated add item logic to handle Web bytes vs Mobile path
  Future<void> _addItem() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title is required.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true); // Show loading during upload

    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;
      
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse(AppConfig.getUrl('api/student/vault/items')),
      );
      
      request.fields['std_id'] = stdId;
      request.fields['username'] = widget.username;
      request.fields['title'] = _titleController.text.trim();
      request.fields['account_email'] = _emailController.text.trim();
      request.fields['account_password'] = _itemPassController.text.trim();

      if (_selectedPlatformFile != null) {
        if (kIsWeb) {
          // For Web: Use bytes
          request.files.add(http.MultipartFile.fromBytes(
            'file',
            _selectedPlatformFile!.bytes!,
            filename: _selectedPlatformFile!.name,
          ));
        } else {
          // For Mobile/Desktop: Use path
          request.files.add(await http.MultipartFile.fromPath(
            'file',
            _selectedPlatformFile!.path!,
          ));
        }
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      final responseData = jsonDecode(response.body);

      setState(() => _isLoading = false);

      if (response.statusCode == 201 && responseData['success'] == true) {
        _titleController.clear();
        _emailController.clear();
        _itemPassController.clear();
        setState(() => _selectedPlatformFile = null);
        Navigator.pop(context);
        _fetchVaultItems();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item stored securely in vault!'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(responseData['message'] ?? 'Failed to save vault item.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save vault item due to connection error.'), backgroundColor: Colors.red));
    }
  }

  void _showAddItemModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Add Vault Credential / File', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const SizedBox(height: 16),
                    TextField(controller: _titleController, decoration: InputDecoration(labelText: 'Title / Account Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 12),
                    TextField(controller: _emailController, decoration: InputDecoration(labelText: 'Username or Email', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 12),
                    TextField(controller: _itemPassController, decoration: InputDecoration(labelText: 'Secret Password / PIN', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: Text(_selectedPlatformFile == null ? 'Attach File (PDF, Excel, Image < 5MB)' : 'Attached: ${_selectedPlatformFile!.name}'),
                      onPressed: () async {
                        await _pickFile();
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color.fromRGBO(110, 115, 225, 1), padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _isLoading ? null : _addItem,
                      child: _isLoading 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save to Secure Vault', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color.fromRGBO(110, 115, 225, 1);

    if (_isLoading && _vaultItems.isEmpty && !_isUnlocked && _hasVaultPass) {
       // Only show global loader if we are fetching initial status
       return Scaffold(appBar: AppBar(title: const Text('Secure Vault'), backgroundColor: primaryColor), body: const Center(child: CircularProgressIndicator()));
    }

    // 1. Setup Vault Password View if not configured yet
    if (!_hasVaultPass) {
      return Scaffold(
        appBar: AppBar(title: const Text('Secure Vault Setup'), backgroundColor: primaryColor),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.security, size: 64, color: primaryColor),
                      const SizedBox(height: 16),
                      const Text('Setup Master Vault PIN', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Protect your sensitive documents and credentials with an encrypted scrypt master key.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 20),
                      TextField(controller: _setupPassController, obscureText: true, decoration: InputDecoration(labelText: 'New Master Password', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                      const SizedBox(height: 12),
                      TextField(controller: _confirmSetupPassController, obscureText: true, decoration: InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                      const SizedBox(height: 16),
                      _buildPasswordCriteriaBox(),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: primaryColor, padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: _setupVaultPassword,
                        child: const Text('Create Master Vault', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

    // 2. Strict Lock Screen Prompt before showing data
    if (!_isUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Secure Vault Locked'), backgroundColor: primaryColor),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_rounded, size: 64, color: primaryColor),
                      const SizedBox(height: 16),
                      const Text('Vault Locked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Enter your master vault password to access protected student data.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 24),
                      TextField(controller: _passController, obscureText: true, decoration: InputDecoration(labelText: 'Vault Password', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: primaryColor, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: _verifyPassword,
                        child: const Text('Unlock Vault', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

    // 3. Unlocked Secure Vault Data Screen
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Secure Vault'),
        backgroundColor: primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock Vault',
            onPressed: () => setState(() => _isUnlocked = false),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Item', style: TextStyle(color: Colors.white)),
        onPressed: _showAddItemModal,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchVaultItems,
        child: _vaultItems.isEmpty
            ? const Center(child: Text('Your secure vault is empty.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _vaultItems.length,
                itemBuilder: (context, index) {
                  final item = _vaultItems[index];
                  final hasFile = item['image_path'] != null && item['image_path'].toString().isNotEmpty;
                  
                  // Clean single synchronous declaration for fileUrl string
                  final fileStr = hasFile ? AppConfig.getUrl('api/student/vault/file/${item['image_path']}'): '';
                  final isImage = hasFile && (
                    fileStr.endsWith('.png') || 
                    fileStr.endsWith('.jpg') || 
                    fileStr.endsWith('.jpeg')
                  );
                  
               
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
                              Text(item['created_at'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                          const Divider(height: 16),
                          if (item['account_email'] != null && item['account_email'].toString().isNotEmpty)
                            Text('Account/Email: ${item['account_email']}', style: const TextStyle(fontSize: 13)),
                          if (item['account_password'] != null && item['account_password'].toString().isNotEmpty)
                            Text('Password: ${item['account_password']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          if (hasFile) ...[
                            const SizedBox(height: 12),
                            isImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      fileStr,
                                      height: 160,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => const Text('Unable to load image file', style: TextStyle(color: Colors.red, fontSize: 12)),
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.insert_drive_file, color: Colors.blue),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text('Attached Document: ${item['image_path']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                        ),
                                      ],
                                    ),
                                  ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildPasswordCriteriaBox() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Security Requirements:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          _buildReqRow('Minimum 8 characters', _hasMinLength),
          _buildReqRow('At least 1 letter', _hasLetter),
          _buildReqRow('At least 1 number', _hasNumber),
        ],
      ),
    );
  }

  Widget _buildReqRow(String text, bool met) {
    return Row(
      children: [
        Icon(met ? Icons.check_circle : Icons.cancel_outlined, size: 14, color: met ? Colors.green : Colors.grey),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 11, color: met ? Colors.green.shade700 : Colors.grey)),
      ],
    );
  }
}
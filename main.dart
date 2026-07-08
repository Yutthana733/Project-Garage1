import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart'; // ✅ เพิ่มใหม่
import 'dashboard.dart';
import 'garage_dashboard.dart';
import 'register.dart';
import 'api_service.dart';
import 'forgot_password_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode =
      FocusNode(); // ✅ เพิ่มใหม่: ใช้ย้าย focus ตอนกด Enter ที่ช่องอีเมล

  // เก็บข้อมูลแบบเข้ารหัส (Keychain บน iOS / Keystore บน Android)
  // ไม่ใช่ SharedPreferences ธรรมดา เพื่อความปลอดภัยของรหัสผ่าน
  final _secureStorage = const FlutterSecureStorage();

  static const _kSavedEmail = 'saved_email';
  static const _kSavedPassword = 'saved_password';
  static const _kRememberMe = 'remember_me';

  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscurePassword = true; // ✅ เพิ่มใหม่: ควบคุมการโชว์/ซ่อนรหัสผ่าน

  // ✅ เพิ่มใหม่: ตัวจัดการ Google Sign-In
  // serverClientId ต้องเป็น "Web application" Client ID จาก Google Cloud Console
  // (ตัวเดียวกับ GOOGLE_CLIENT_ID ที่ตั้งไว้ฝั่ง backend)
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    serverClientId: 'ใส่-WEB-CLIENT-ID.apps.googleusercontent.com',
  );

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final remembered = await _secureStorage.read(key: _kRememberMe);
    if (remembered == 'true') {
      final savedEmail = await _secureStorage.read(key: _kSavedEmail);
      final savedPassword = await _secureStorage.read(key: _kSavedPassword);
      if (!mounted) return;
      setState(() {
        _emailController.text = savedEmail ?? '';
        _passwordController.text = savedPassword ?? '';
        _rememberMe = true;
      });
    }
  }

  Future<void> _saveOrClearCredentials() async {
    if (_rememberMe) {
      await _secureStorage.write(
        key: _kSavedEmail,
        value: _emailController.text.trim(),
      );
      await _secureStorage.write(
        key: _kSavedPassword,
        value: _passwordController.text,
      );
      await _secureStorage.write(key: _kRememberMe, value: 'true');
    } else {
      await _secureStorage.delete(key: _kSavedEmail);
      await _secureStorage.delete(key: _kSavedPassword);
      await _secureStorage.delete(key: _kRememberMe);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose(); // ✅ เพิ่มใหม่
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await ApiService.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      // บันทึก/ลบข้อมูลที่จำไว้ ตามสถานะติ๊ก "จำฉันไว้"
      await _saveOrClearCredentials();

      final userType = result.data?['user']?['userType'] ?? 'customer';

      if (userType == 'repair') {
        // ✅ อู่ซ่อม → ไปหน้า GarageDashboard
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => GarageDashboard(
              userData: result.data!['user'],
            ), // ✅ เพิ่ม userData
          ),
        );
      } else {
        // ✅ ลูกค้า → ไปหน้า HomePage
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                HomePage(userData: result.data!['user']), // ✅ เพิ่ม userData
          ),
        );
      }
    } else {
      // ❌ แสดง error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ✅ เพิ่มใหม่: จัดการ Login ด้วย Google
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      // signOut() ก่อน เพื่อบังคับให้ขึ้นหน้าต่างเลือกบัญชีทุกครั้ง
      // (ถ้าไม่ทำ บางทีจะ login ด้วยบัญชีล่าสุดโดยอัตโนมัติเงียบๆ)
      await _googleSignIn.signOut();

      final account = await _googleSignIn
          .signIn(); // เด้งหน้าต่างให้เลือกบัญชี Google (เลือกได้หลายบัญชีถ้าเครื่อง login ไว้หลายบัญชี)
      if (account == null) {
        // ผู้ใช้กดยกเลิกตอนเลือกบัญชี
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('ไม่สามารถขอ idToken จาก Google ได้');
      }

      final result = await ApiService.googleLogin(idToken: idToken);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result.success) {
        final userType = result.data?['user']?['userType'] ?? 'customer';

        if (userType == 'repair') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  GarageDashboard(userData: result.data!['user']),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HomePage(userData: result.data!['user']),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เข้าสู่ระบบด้วย Google ไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),

      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),

              Column(
                children: const [
                  Icon(Icons.home_work_outlined, size: 80, color: Colors.blue),
                  SizedBox(height: 10),
                  Text(
                    'อู่ที่ไว้วางใจ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'ค้นหาอู่ซ่อมรถ\nใกล้คุณ',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),

                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text(
                          'เข้าสู่ระบบ',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Text('อีเมล'),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction
                            .next, // ✅ ปุ่ม Enter บนคีย์บอร์ดจะกลายเป็น "ถัดไป"
                        onFieldSubmitted: (_) {
                          // ✅ กด Enter ที่ช่องอีเมล → ย้าย focus ไปช่องรหัสผ่านต่อ
                          FocusScope.of(
                            context,
                          ).requestFocus(_passwordFocusNode);
                        },
                        decoration: InputDecoration(
                          hintText: 'example@email.com',
                          prefixIcon: const Icon(Icons.email_outlined),
                          filled: true,
                          fillColor: const Color(0xFFF5F6FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'กรุณากรอกอีเมล';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      const Text('รหัสผ่าน'),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode, // ✅ เพิ่มใหม่
                        obscureText: _obscurePassword, // ✅ ควบคุมด้วย state
                        textInputAction: TextInputAction
                            .done, // ✅ ปุ่ม Enter บนคีย์บอร์ดจะกลายเป็น "เสร็จสิ้น"
                        onFieldSubmitted: (_) {
                          // ✅ กด Enter ที่ช่องรหัสผ่าน → เข้าสู่ระบบทันที เหมือนกดปุ่ม
                          if (!_isLoading) _handleLogin();
                        },
                        // ✅ บอก browser ว่านี่คือช่องรหัสผ่านใหม่ ไม่ต้อง
                        // เสนอรหัสผ่านที่เคยจำไว้ก่อนหน้า (กัน Chrome autofill
                        // เข้ามาแทรกตอนไม่ได้ติ๊ก "จำฉันไว้")
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline),
                          filled: true,
                          fillColor: const Color(0xFFF5F6FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          // ✅ เพิ่มใหม่: ปุ่มลูกตา ดู/ซ่อนรหัสผ่าน
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(
                                () => _obscurePassword = !_obscurePassword,
                              );
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรุณากรอกรหัสผ่าน';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 10),

                      // ✅ แถวใหม่: "จำฉันไว้" (ซ้าย) + "ลืมรหัสผ่าน?" (ขวา) กดได้จริง
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () =>
                                setState(() => _rememberMe = !_rememberMe),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) => setState(
                                      () => _rememberMe = value ?? false,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'จำฉันไว้',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ForgotPasswordPage(),
                                ),
                              );
                            },
                            child: const Text(
                              'ลืมรหัสผ่าน?',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ✅ ปุ่มเข้าสู่ระบบเรียก _handleLogin จริงๆ
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'เข้าสู่ระบบ',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: const [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text('หรือ'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ✅ เพิ่มใหม่: ปุ่ม Login ด้วย Google
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleGoogleSignIn,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.grey.shade400),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                          label: const Text(
                            'เข้าสู่ระบบด้วย Google',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('ยังไม่มีบัญชี? '),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RegisterPage(),
                                ),
                              );
                            },
                            child: const Text(
                              'สมัครสมาชิก',
                              style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
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
}

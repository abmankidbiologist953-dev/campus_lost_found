// main.dart
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

import 'campus_auth.dart';
import 'campus_database.dart';
import 'database_factory_stub.dart'
    if (dart.library.js_interop) 'database_factory_web.dart'
    as web_database;
import 'firebase_options.dart';

const _loginGreen = Color(0xFF176B3A);
const _loginDeepGreen = Color(0xFF124A2F);
const _loginPaleGreen = Color(0xFFEAF4EC);
const _loginBorderGreen = Color(0xFFD8E7DC);
const _loginText = Color(0xFF1F3528);
const _loginMuted = Color(0xFF68796E);
bool _firebaseInitialized = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _firebaseInitialized = true;
  }
  if (kIsWeb) {
    web_database.configureWebDatabaseFactory();
  } else if ((defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux)) {
    sqflite_ffi.sqfliteFfiInit();
    sqflite_ffi.databaseFactory = sqflite_ffi.databaseFactoryFfi;
  }
  runApp(const LostFoundApp());
}

class LostFoundApp extends StatelessWidget {
  final CampusAuthGateway? authGateway;

  const LostFoundApp({super.key, this.authGateway});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KASU campus Lost & Found',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        scaffoldBackgroundColor: const Color(0XFFF1F8F2),
        useMaterial3: true,
      ),
      home: LoginPage(authGateway: authGateway),
    );
  }
}

class LoginPage extends StatefulWidget {
  final CampusAuthGateway? authGateway;

  const LoginPage({super.key, this.authGateway});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final matricController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool isCreatingAccount = false;
  bool obscurePassword = true;
  bool isSubmitting = false;
  bool studentStatusConfirmed = false;
  bool showStudentStatusError = false;

  CampusAuthGateway get authGateway =>
      widget.authGateway ??
      (_firebaseInitialized
          ? FirebaseCampusAuthGateway()
          : LocalCampusAuthGateway());

  void _setAccountMode(bool creatingAccount) {
    if (isCreatingAccount == creatingAccount) {
      return;
    }
    setState(() {
      isCreatingAccount = creatingAccount;
      studentStatusConfirmed = false;
      showStudentStatusError = false;
      formKey.currentState?.reset();
      passwordController.clear();
      confirmPasswordController.clear();
      emailController.clear();
      matricController.clear();
    });
  }

  Widget _accountModeButton({
    required String label,
    required bool createsAccount,
  }) {
    final selected = isCreatingAccount == createsAccount;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          key: ValueKey(
            createsAccount ? 'create-account-mode' : 'sign-in-mode',
          ),
          borderRadius: BorderRadius.circular(10),
          onTap: isSubmitting ? null : () => _setAccountMode(createsAccount),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? _loginGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _loginMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> login() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isSubmitting = true;
    });
    try {
      final matricNumber = await authGateway.signIn(
        identifier:
            (authGateway.usesEmailForSignIn
                    ? emailController.text
                    : matricController.text)
                .trim(),
        password: passwordController.text,
      );
      await CampusDatabase.ensureStudentProfile(matricNumber);
      if (!mounted) {
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(matricNumber: matricNumber),
        ),
      );
    } on DatabaseException catch (error, stackTrace) {
      _showStorageError('prepare your student profile', error, stackTrace);
    } on StateError catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showStorageError(String message, Object error, StackTrace stackTrace) {
    debugPrint('$message: $error\n$stackTrace');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> createAccount() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    if (!studentStatusConfirmed) {
      setState(() {
        showStudentStatusError = true;
      });
      return;
    }

    final matricNumber = matricController.text.trim().toUpperCase();
    setState(() {
      isSubmitting = true;
    });
    try {
      await authGateway.signUp(
        password: passwordController.text,
        matricNumber: matricNumber,
        email: emailController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      await CampusDatabase.ensureStudentProfile(matricNumber);
      if (!mounted) {
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(matricNumber: matricNumber),
        ),
      );
    } on StateError catch (error) {
      _showMessage(error.message.toString());
    } on DatabaseException catch (error, stackTrace) {
      _showStorageError('prepare your student profile', error, stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  InputDecoration _fieldDecoration(
    String hint,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    const borderRadius = BorderRadius.all(Radius.circular(14));
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF819087), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF64816D), size: 19),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      enabledBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: _loginBorderGreen),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: _loginGreen, width: 1.4),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Color(0xFFE78383)),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Color(0xFFE78383), width: 1.4),
      ),
    );
  }

  Widget _labeledField({required String label, required Widget field}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF345541),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
  }

  Widget _buildMatricField() {
    return _labeledField(
      label: 'Matriculation number',
      field: TextFormField(
        controller: matricController,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(color: _loginText, fontSize: 14),
        decoration: _fieldDecoration(
          'Enter your KASU matric number',
          Icons.badge_outlined,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Please enter your matric number';
          }
          if (value.trim().length < 5) {
            return 'Enter a valid matric number';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildEmailField() {
    return _labeledField(
      label: 'Email address',
      field: TextFormField(
        controller: emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        style: const TextStyle(color: _loginText, fontSize: 14),
        decoration: _fieldDecoration(
          'Enter your email address',
          Icons.email_outlined,
        ),
        validator: (value) {
          final email = value?.trim() ?? '';
          if (email.isEmpty) {
            return 'Please enter your email address';
          }
          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
            return 'Enter a valid email address';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildLoginIdentifierField() {
    return authGateway.usesEmailForSignIn
        ? _buildEmailField()
        : _buildMatricField();
  }

  Widget _buildPasswordField() {
    return _labeledField(
      label: 'Password',
      field: TextFormField(
        controller: passwordController,
        obscureText: obscurePassword,
        style: const TextStyle(color: _loginText, fontSize: 14),
        decoration: _fieldDecoration(
          'Enter your password',
          Icons.lock_outline_rounded,
          suffixIcon: IconButton(
            tooltip: obscurePassword ? 'Show password' : 'Hide password',
            onPressed: () {
              setState(() {
                obscurePassword = !obscurePassword;
              });
            },
            color: const Color(0xFF64816D),
            icon: Icon(
              obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 19,
            ),
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter your password';
          }
          if (isCreatingAccount && value.length < 8) {
            return 'Use at least 8 characters';
          }
          if (isCreatingAccount &&
              (!RegExp(r'[A-Za-z]').hasMatch(value) ||
                  !RegExp(r'[0-9]').hasMatch(value))) {
            return 'Include at least one letter and one number';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildConfirmPasswordField() {
    return _labeledField(
      label: 'Confirm password',
      field: TextFormField(
        controller: confirmPasswordController,
        obscureText: true,
        style: const TextStyle(color: _loginText, fontSize: 14),
        decoration: _fieldDecoration(
          'Re-enter your password',
          Icons.lock_reset_outlined,
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please confirm your password';
          }
          if (value != passwordController.text) {
            return 'Passwords do not match';
          }
          return null;
        },
      ),
    );
  }

  @override
  void dispose() {
    matricController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _loginPaleGreen,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.88, -0.86),
                radius: 1.24,
                colors: [Color(0xFFE2F0E5), Color(0xFFF5F9F5)],
              ),
            ),
          ),
          const CustomPaint(painter: _LoginBackdropPainter()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final compact = viewport.maxWidth < 440;
                final cardPadding = compact ? 16.0 : 24.0;
                final pageHorizontalPadding = compact ? 32.0 : 56.0;
                final cardContentWidth =
                    (viewport.maxWidth - pageHorizontalPadding).clamp(
                      0.0,
                      620.0,
                    ) -
                    cardPadding * 2;
                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 16 : 28,
                      vertical: 12,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Container(
                        padding: EdgeInsets.all(cardPadding),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFFB7D5BF)
                                .withValues(alpha: 0.25),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF173B27)
                                  .withValues(alpha: 0.10),
                              blurRadius: 44,
                              offset: const Offset(0, 24),
                            ),
                            BoxShadow(
                              color: _loginGreen.withValues(alpha: 0.06),
                              blurRadius: 40,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.96),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFB7D5BF),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _loginGreen.withValues(
                                          alpha: 0.12,
                                        ),
                                        blurRadius: 20,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/images/kasu_logo.png',
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(
                                                Icons.account_balance_rounded,
                                                color: Color(0xFF176B3A),
                                                size: 42,
                                              ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'KADUNA STATE UNIVERSITY',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _loginDeepGreen,
                                  fontSize: 11,
                                  letterSpacing: 1.8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: _loginPaleGreen,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _loginBorderGreen),
                                ),
                                child: Row(
                                  children: [
                                    _accountModeButton(
                                      label: 'Sign In',
                                      createsAccount: false,
                                    ),
                                    _accountModeButton(
                                      label: 'Create Account',
                                      createsAccount: true,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isCreatingAccount
                                    ? 'Create Account'
                                    : 'Sign In',
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  color: _loginText,
                                  fontSize: compact ? 26 : 30,
                                  letterSpacing: -0.7,
                                  height: 1.12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isCreatingAccount
                                    ? 'Join your campus community and keep your belongings connected.'
                                    : authGateway.usesEmailForSignIn
                                    ? 'Sign in with your email address and password.'
                                    : 'Sign in with your KASU matriculation number and password.',
                                style: const TextStyle(
                                  color: _loginMuted,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (isCreatingAccount)
                                _buildMatricField()
                              else
                                _buildLoginIdentifierField(),
                              if (isCreatingAccount) ...[
                                const SizedBox(height: 10),
                                _buildEmailField(),
                              ],
                              const SizedBox(height: 10),
                              if (isCreatingAccount && cardContentWidth >= 410)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildPasswordField()),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: _buildConfirmPasswordField(),
                                    ),
                                  ],
                                )
                              else ...[
                                _buildPasswordField(),
                                if (isCreatingAccount) ...[
                                  const SizedBox(height: 10),
                                  _buildConfirmPasswordField(),
                                ],
                              ],
                              if (isCreatingAccount) ...[
                                const SizedBox(height: 14),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: studentStatusConfirmed,
                                        onChanged: isSubmitting
                                            ? null
                                            : (value) {
                                                setState(() {
                                                  studentStatusConfirmed =
                                                      value ?? false;
                                                  showStudentStatusError =
                                                      false;
                                                });
                                              },
                                        activeColor: _loginGreen,
                                        checkColor: Colors.white,
                                        side: const BorderSide(
                                          color: Color(0xFF8DA895),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    const Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(top: 3),
                                        child: Text(
                                          'I confirm I am a current KASU student.',
                                          style: TextStyle(
                                            color: Color(0xFF526B59),
                                            fontSize: 12,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (showStudentStatusError) ...[
                                  const SizedBox(height: 5),
                                  const Padding(
                                    padding: EdgeInsets.only(left: 33),
                                    child: Text(
                                      'Please confirm your student status to continue.',
                                      style: TextStyle(
                                        color: Color(0xFFFF9C9C),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                              if (!isCreatingAccount) ...[
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: _loginGreen,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.push<void>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ForgotPasswordPage(
                                                authGateway: authGateway,
                                              ),
                                        ),
                                      );
                                    },
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                              ] else
                                const SizedBox(height: 14),
                              SizedBox(
                                height: 48,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _loginGreen,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: const Color(
                                      0xFF9AB9A2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: isSubmitting
                                      ? null
                                      : isCreatingAccount
                                      ? createAccount
                                      : login,
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 21,
                                          height: 21,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              isCreatingAccount
                                                  ? 'Create Account'
                                                  : 'Sign In',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(width: 9),
                                            const Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 19,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Center(
                                child: Text(
                                  'KADUNA STATE UNIVERSITY  •  STUDENT COMMUNITY',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF718178),
                                    fontSize: 9,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackdropPainter extends CustomPainter {
  const _LoginBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width;
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var index = -2; index < 7; index++) {
      final startX = unit * (index * 0.23);
      final path = Path()
        ..moveTo(startX, 0)
        ..lineTo(startX + unit * 0.28, 0)
        ..lineTo(startX + unit * 0.58, size.height * 0.43)
        ..lineTo(startX + unit * 0.82, size.height * 0.43);
      glowPaint
        ..strokeWidth = index.isEven ? 1.4 : 0.7
        ..color =
            (index.isEven ? const Color(0xFF4D9A65) : const Color(0xFFA8C8AE))
                .withValues(alpha: index.isEven ? 0.13 : 0.065);
      canvas.drawPath(path, glowPaint);
    }

    for (var index = 0; index < 5; index++) {
      final path = Path()
        ..moveTo(size.width * (0.32 + index * 0.12), size.height)
        ..lineTo(size.width * (0.62 + index * 0.08), size.height * 0.69)
        ..lineTo(size.width * (0.87 + index * 0.03), size.height * 0.69)
        ..lineTo(size.width, size.height * (0.56 + index * 0.055));
      glowPaint
        ..strokeWidth = index == 1 ? 1.5 : 0.8
        ..color = const Color(0xFF5DAA70)
            .withValues(alpha: index == 1 ? 0.14 : 0.065);
      canvas.drawPath(path, glowPaint);
    }

    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF79AA83).withValues(alpha: 0.12);
    final upperCorner = Path()
      ..moveTo(size.width * 0.04, size.height * 0.23)
      ..lineTo(size.width * 0.15, size.height * 0.1)
      ..lineTo(size.width * 0.22, size.height * 0.1)
      ..lineTo(size.width * 0.1, size.height * 0.28)
      ..close();
    final lowerCorner = Path()
      ..moveTo(size.width * 0.78, size.height * 0.89)
      ..lineTo(size.width * 0.93, size.height * 0.72)
      ..lineTo(size.width * 0.97, size.height * 0.72)
      ..lineTo(size.width * 0.86, size.height * 0.89)
      ..close();
    canvas
      ..drawPath(upperCorner, cornerPaint)
      ..drawPath(lowerCorner, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _LoginBackdropPainter oldDelegate) => false;
}

class ForgotPasswordPage extends StatefulWidget {
  final CampusAuthGateway? authGateway;

  const ForgotPasswordPage({super.key, this.authGateway});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  bool isSending = false;
  String? statusMessage;

  CampusAuthGateway get authGateway =>
      widget.authGateway ??
      (_firebaseInitialized
          ? FirebaseCampusAuthGateway()
          : LocalCampusAuthGateway());

  Future<void> sendResetLink() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isSending = true;
      statusMessage = null;
    });
    try {
      await authGateway.sendPasswordResetEmail(
        email: emailController.text.trim(),
      );
      if (mounted) {
        setState(() {
          statusMessage =
              'If an account exists for this email, a password reset link '
              'has been sent.';
        });
      }
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          statusMessage = error.message.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isSending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: Color(0xFF176B3A),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Reset your password',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Enter the email address linked to your account. We'll send "
                    'you a link to reset your password.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: formKey,
                    child: TextFormField(
                      key: const ValueKey('reset-email-field'),
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) {
                          return 'Please enter your email address';
                        }
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(email)) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                  ),
                  if (statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(statusMessage!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSending ? null : sendResetLink,
                      child: isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send reset link'),
                    ),
                  ),
                  TextButton(
                    onPressed: isSending ? null : () => Navigator.pop(context),
                    child: const Text('Back to login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String matricNumber;

  const HomePage({super.key, required this.matricNumber});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<CampusItem> items = [];
  final TextEditingController searchController = TextEditingController();
  Timer? expiryTimer;
  Uint8List? profilePhoto;
  bool isLoading = true;

  String selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadProfilePhoto();
    expiryTimer = Timer.periodic(const Duration(hours: 1), (_) => _loadItems());
  }

  Future<void> _loadProfilePhoto() async {
    try {
      final photo = await CampusDatabase.loadProfilePhoto(widget.matricNumber);
      if (mounted) {
        setState(() {
          profilePhoto = photo;
        });
      }
    } on DatabaseException catch (error, stackTrace) {
      if (mounted) {
        _showStorageError('load your profile picture', error, stackTrace);
      }
    }
  }

  Future<void> _saveProfilePhoto(Uint8List? photo) async {
    await CampusDatabase.saveProfilePhoto(widget.matricNumber, photo);
    if (mounted) {
      setState(() {
        profilePhoto = photo;
      });
    }
  }

  Future<void> openProfile() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(
          matricNumber: widget.matricNumber,
          initialPhoto: profilePhoto,
          onPhotoChanged: _saveProfilePhoto,
        ),
      ),
    );
    if (mounted) {
      _loadProfilePhoto();
    }
  }

  Future<void> _loadItems() async {
    try {
      final loadedItems = await CampusDatabase.loadItems();
      if (mounted) {
        setState(() {
          items
            ..clear()
            ..addAll(loadedItems);
          isLoading = false;
        });
      }
    } on DatabaseException catch (error, stackTrace) {
      debugPrint('Could not load reports: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load reports. Please try again.'),
          ),
        );
      }
    }
  }

  void _showStorageError(String action, Object error, StackTrace stackTrace) {
    debugPrint('Could not $action: $error\n$stackTrace');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not $action. Please try again.')),
    );
  }

  List<CampusItem> get filteredItems {
    return items.where((item) {
      final search = searchController.text.toLowerCase();

      final matchesSearch =
          item.title.toLowerCase().contains(search) ||
          item.description.toLowerCase().contains(search) ||
          item.location.toLowerCase().contains(search) ||
          item.category.toLowerCase().contains(search) ||
          item.contact.toLowerCase().contains(search);

      bool matchesFilter;

      if (selectedFilter == 'All') {
        matchesFilter = true;
      } else if (selectedFilter == 'Returned') {
        matchesFilter = item.returned;
      } else {
        matchesFilter = item.type == selectedFilter && !item.returned;
      }

      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> addItem() async {
    final result = await Navigator.push<CampusItem>(
      context,
      MaterialPageRoute(builder: (context) => const ItemFormPage()),
    );

    if (!mounted) {
      return;
    }

    if (result != null) {
      try {
        await CampusDatabase.saveItem(result);
        if (mounted) {
          setState(() {
            items.insert(0, result);
          });
        }
      } on DatabaseException catch (error, stackTrace) {
        if (mounted) {
          _showStorageError('save the report', error, stackTrace);
        }
      }
    }
  }

  Future<void> editItem(CampusItem item) async {
    final result = await Navigator.push<CampusItem>(
      context,
      MaterialPageRoute(builder: (context) => ItemFormPage(item: item)),
    );

    if (!mounted) {
      return;
    }

    if (result != null) {
      try {
        await CampusDatabase.saveItem(result);
        if (mounted) {
          setState(() {
            final index = items.indexWhere((element) => element.id == item.id);
            if (index != -1) {
              items[index] = result;
            }
          });
        }
      } on DatabaseException catch (error, stackTrace) {
        if (mounted) {
          _showStorageError('save the changes', error, stackTrace);
        }
      }
    }
  }

  Future<void> deleteItem(CampusItem item) async {
    try {
      await CampusDatabase.deleteItem(item.id);
    } on DatabaseException catch (error, stackTrace) {
      if (mounted) {
        _showStorageError('delete the report', error, stackTrace);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      items.removeWhere((element) => element.id == item.id);
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Item deleted')));
  }

  Future<void> toggleReturned(CampusItem item) async {
    final returned = !item.returned;
    try {
      await CampusDatabase.setItemReturned(item.id, returned);
    } on DatabaseException catch (error, stackTrace) {
      if (mounted) {
        _showStorageError('update the report', error, stackTrace);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      item.returned = returned;
    });
  }

  @override
  void dispose() {
    expiryTimer?.cancel();
    searchController.dispose();
    super.dispose();
  }

  IconData _iconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'electronics':
        return Icons.devices_outlined;
      case 'books':
        return Icons.menu_book_outlined;
      case 'bags':
        return Icons.backpack_outlined;
      case 'clothing':
        return Icons.checkroom_outlined;
      case 'keys':
        return Icons.key_outlined;
      case 'id cards':
        return Icons.badge_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  Color _statusColor(CampusItem item) {
    if (item.returned) {
      return const Color(0xFF17865A);
    }
    return item.type == 'Lost'
        ? const Color(0xFFD66A55)
        : const Color(0xFF3478C8);
  }

  Widget _buildItemCard(CampusItem item) {
    final statusColor = _statusColor(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9EEF4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B19324D),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      statusColor.withValues(alpha: 0.18),
                      statusColor.withValues(alpha: 0.07),
                    ],
                  ),
                ),
                child: Icon(
                  item.returned
                      ? Icons.check_circle_outline
                      : _iconForCategory(item.category),
                  color: statusColor,
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF172B45),
                              fontSize: 16,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Report options',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onSelected: (value) {
                            if (value == 'edit') {
                              editItem(item);
                            } else if (value == 'delete') {
                              deleteItem(item);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit report'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete report'),
                            ),
                          ],
                          icon: const Icon(
                            Icons.more_horiz,
                            color: Color(0xFF8190A3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.11),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.returned ? 'Returned' : item.type,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.category,
                      style: const TextStyle(
                        color: Color(0xFF7C8A9C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            item.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF526176),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _ItemDetail(
                icon: Icons.location_on_outlined,
                text: item.location,
              ),
              _ItemDetail(
                icon: Icons.calendar_today_outlined,
                text: '${item.date.day}/${item.date.month}/${item.date.year}',
              ),
              _ItemDetail(icon: Icons.phone_outlined, text: item.contact),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => toggleReturned(item),
              icon: Icon(
                item.returned ? Icons.undo_rounded : Icons.check_circle_outline,
                size: 18,
              ),
              label: Text(item.returned ? 'Undo returned' : 'Mark as returned'),
              style: OutlinedButton.styleFrom(
                foregroundColor: statusColor,
                side: BorderSide(color: statusColor.withValues(alpha: 0.28)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = filteredItems;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: const Color(0xFFE7ECF2))),
          ),
          child: Row(
            children: ['All', 'Lost', 'Found', 'Returned'].map((filter) {
              final selected = selectedFilter == filter;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() {
                        selectedFilter = filter;
                      });
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Text(
                            filter,
                            style: TextStyle(
                              color: selected
                                  ? const Color(0xFF00923F)
                                  : const Color(0xFF66758A),
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF00923F)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                padding: const EdgeInsets.fromLTRB(21, 20, 21, 24),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFEAF5EC), Color(0xFFDCEFE1)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -56,
                      top: -68,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF00923F)
                              .withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00923F),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.travel_explore_rounded,
                                color: Colors.white,
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 11),
                            const Expanded(
                              child: Text(
                                'CAMPUS LOST & FOUND',
                                style: TextStyle(
                                  color: Color(0xFF315B40),
                                  fontSize: 11,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: 'Profile and picture',
                              child: GestureDetector(
                                onTap: openProfile,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF00923F)
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: ProfileAvatar(
                                    photo: profilePhoto,
                                    radius: 19,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Find what was lost.',
                          style: TextStyle(
                            color: Color(0xFF00923F),
                            fontSize: 26,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Together, we can bring belongings home.',
                          style: TextStyle(
                            color: Color(0xFF52745D),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 19, 20, 0),
                child: TextField(
                  controller: searchController,
                  onChanged: (value) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: 'Search items, categories, or places',
                    hintStyle: const TextStyle(
                      color: Color(0xFF9AA7B7),
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF00923F),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 17),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: const BorderSide(color: Color(0xFFE8EDF3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: const BorderSide(
                        color: Color(0xFF00923F),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(20, 16, 20, 23),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F7F1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4F0E3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.volunteer_activism_outlined,
                        color: Color(0xFF17865A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lost or found something?',
                            style: TextStyle(
                              color: Color(0xFF1E4435),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Let the campus community know.',
                            style: TextStyle(
                              color: Color(0xFF668275),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: addItem,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF17865A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Report Item',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 21, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent reports',
                        style: TextStyle(
                          color: Color(0xFF172B45),
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${visibleItems.length} ${visibleItems.length == 1 ? 'item' : 'items'}',
                      style: const TextStyle(
                        color: Color(0xFF8290A2),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF00923F)),
                  ),
                )
              else if (visibleItems.isEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 34,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE9EEF4)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.search_off_rounded,
                        color: Color(0xFF9AA9BB),
                        size: 38,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        searchController.text.isEmpty
                            ? 'No reports in this category yet'
                            : 'No matching reports found',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF526176),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Try another filter or search term.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8997A8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: visibleItems.map(_buildItemCard).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemDetail extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ItemDetail({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF8290A2)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Color(0xFF718095), fontSize: 11),
        ),
      ],
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  final Uint8List? photo;
  final double radius;

  const ProfileAvatar({super.key, required this.photo, this.radius = 54});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: photo == null
          ? Icon(Icons.person, size: radius * 1.15)
          : ClipOval(
              child: Image.memory(
                photo!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(Icons.person, size: radius * 1.15);
                },
              ),
            ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  final String matricNumber;
  final Uint8List? initialPhoto;
  final Future<void> Function(Uint8List? photo) onPhotoChanged;

  const ProfilePage({
    super.key,
    required this.matricNumber,
    required this.initialPhoto,
    required this.onPhotoChanged,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Uint8List? photo = widget.initialPhoto;
  bool isSaving = false;

  Future<void> choosePhoto() async {
    setState(() {
      isSaving = true;
    });

    try {
      final selection = await FilePicker.pickFiles(type: FileType.image);
      if (selection.isEmpty) {
        return;
      }

      final selectedFile = selection.single;
      final fileSize = await selectedFile.length();
      if (fileSize != null && fileSize > CampusDatabase.maxProfilePhotoBytes) {
        _showMessage('Choose a picture smaller than 5 MB.');
        return;
      }

      final bytes = await selectedFile.readAsBytes();
      if (bytes.isEmpty) {
        _showMessage('Could not read the selected picture. Try another file.');
        return;
      }
      if (bytes.lengthInBytes > CampusDatabase.maxProfilePhotoBytes) {
        _showMessage('Choose a picture smaller than 5 MB.');
        return;
      }

      await widget.onPhotoChanged(bytes);
      if (mounted) {
        setState(() {
          photo = bytes;
        });
        _showMessage('Profile picture updated.');
      }
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Could not select profile picture: $error\n$stackTrace');
      _showMessage('Could not open the picture picker. Please try again.');
    } on DatabaseException catch (error, stackTrace) {
      debugPrint('Could not save profile picture: $error\n$stackTrace');
      _showMessage('Could not save your picture. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> removePhoto() async {
    setState(() {
      isSaving = true;
    });
    try {
      await widget.onPhotoChanged(null);
      if (mounted) {
        setState(() {
          photo = null;
        });
        _showMessage('Profile picture removed.');
      }
    } on DatabaseException catch (error, stackTrace) {
      debugPrint('Could not remove profile picture: $error\n$stackTrace');
      _showMessage('Could not remove your picture. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Profile')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProfileAvatar(photo: photo),
              const SizedBox(height: 20),
              Text(
                widget.matricNumber,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Your campus account profile'),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: isSaving ? null : choosePhoto,
                icon: const Icon(Icons.upload_outlined),
                label: Text(
                  photo == null ? 'Upload picture' : 'Change picture',
                ),
              ),
              if (photo != null)
                TextButton.icon(
                  onPressed: isSaving ? null : removePhoto,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove picture'),
                ),
              if (isSaving) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
              const SizedBox(height: 16),
              Text(
                'Choose an image up to 5 MB. Your picture is saved with this '
                'account on this device.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ItemFormPage extends StatefulWidget {
  final CampusItem? item;

  const ItemFormPage({super.key, this.item});

  @override
  State<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends State<ItemFormPage> {
  final formKey = GlobalKey<FormState>();

  late TextEditingController titleController;
  late TextEditingController descriptionController;
  late TextEditingController locationController;
  late TextEditingController contactController;

  String category = 'Electronics';
  String type = 'Lost';
  DateTime selectedDate = DateTime.now();

  final List<String> categories = [
    'Electronics',
    'Books',
    'Bags',
    'Clothing',
    'Keys',
    'ID Cards',
    'Other',
  ];

  @override
  void initState() {
    super.initState();

    final item = widget.item;

    titleController = TextEditingController(text: item?.title ?? '');
    descriptionController = TextEditingController(
      text: item?.description ?? '',
    );
    locationController = TextEditingController(text: item?.location ?? '');
    contactController = TextEditingController(text: item?.contact ?? '');

    if (item != null) {
      category = item.category;
      type = item.type;
      selectedDate = item.date;
    }
  }

  Future<void> chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date != null) {
      setState(() {
        selectedDate = date;
      });
    }
  }

  void saveItem() {
    if (!formKey.currentState!.validate()) {
      return;
    }

    final oldItem = widget.item;

    final item = CampusItem(
      id: oldItem?.id ?? DateTime.now().microsecondsSinceEpoch,
      title: titleController.text.trim(),
      description: descriptionController.text.trim(),
      category: category,
      location: locationController.text.trim(),
      contact: contactController.text.trim(),
      date: selectedDate,
      createdAt: oldItem?.createdAt ?? DateTime.now(),
      type: type,
      returned: oldItem?.returned ?? false,
    );

    Navigator.pop(context, item);
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();
    contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? 'Report an Item' : 'Edit Item'),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(
                labelText: 'Report Type',
                border: OutlineInputBorder(),
              ),
              items: ['Lost', 'Found'].map((value) {
                return DropdownMenuItem(value: value, child: Text(value));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    type = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Item Name',
                hintText: 'Example: Black school bag',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter the item name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: categories.map((value) {
                return DropdownMenuItem(value: value, child: Text(value));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    category = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Describe the item',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a description';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Campus Location',
                hintText: 'Example: University Library',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter the location';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: contactController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact Number',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a contact number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: chooseDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                'Date: ${selectedDate.day}/'
                '${selectedDate.month}/${selectedDate.year}',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Reports are automatically removed after 7 days.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: saveItem,
              icon: const Icon(Icons.save),
              label: Text(
                widget.item == null ? 'Submit Report' : 'Save Changes',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../core/utils/error_handler.dart';

class OTPScreen extends ConsumerStatefulWidget {
  final String verificationId;
  final String phoneNumber;

  const OTPScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
  });

  @override
  ConsumerState<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends ConsumerState<OTPScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  void _verifyOTP() async {
    if (!_formKey.currentState!.validate()) return;

    final otp = _otpCtrl.text.trim();

    setState(() => _isLoading = true);
    final auth = ref.read(authServiceProvider.notifier);

    try {
      await auth.verifyOTP(widget.verificationId, otp);
      if (!mounted) return;
      setState(() => _isLoading = false);
      // The AuthWrapper will automatically redirect the user to Home or ProfileSetup
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserFriendlyMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Phone'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Code sent to ${widget.phoneNumber}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 32),
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _otpCtrl,
                    decoration: const InputDecoration(
                      labelText: '6-digit OTP',
                      prefixIcon: Icon(Icons.password),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      letterSpacing: 8,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    validator: (val) => val == null || val.length < 6
                        ? 'Please enter a 6-digit OTP'
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOTP,
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.onPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Verify & Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

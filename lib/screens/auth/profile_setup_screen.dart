import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../../services/auth_service.dart';
import '../../core/utils/error_handler.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String _completePhoneNumber = '';
  final _aboutCtrl = TextEditingController(
    text: "Hey there! I am using ConnectCall.",
  );
  bool _isLoading = false;
  bool _needsPhoneNumber = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        _nameCtrl.text = user.displayName!;
      }
      if (user.phoneNumber == null || user.phoneNumber!.isEmpty) {
        _needsPhoneNumber = true;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  void _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final about = _aboutCtrl.text.trim();
    final phone = _completePhoneNumber;

    if (_needsPhoneNumber && phone.isEmpty) {
      // IntlPhoneField should validate, but just in case
      return;
    }

    setState(() => _isLoading = true);
    final auth = ref.read(authServiceProvider.notifier);

    String? finalPhone = _needsPhoneNumber ? phone : null;

    try {
      await auth.setupProfile(name, about, phoneNumber: finalPhone);
      if (!mounted) return;
      setState(() => _isLoading = false);
      // If successful, the AuthWrapper will automatically redirect to HomeScreen
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
        title: const Text('Profile Info'),
        automaticallyImplyLeading: false, // User must fill this out
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Please provide your name and an optional profile status',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Type your name here',
                          prefixIcon: Icon(Icons.person),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (val) => val == null || val.isEmpty
                            ? 'Please enter your name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      if (_needsPhoneNumber) ...[
                        IntlPhoneField(
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            border: OutlineInputBorder(),
                          ),
                          initialCountryCode: 'IN',
                          onChanged: (phone) {
                            _completePhoneNumber = phone.completeNumber;
                          },
                          validator: (phone) {
                            if (phone == null || phone.number.length != 10) {
                              return 'Please enter exactly 10 digits';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _aboutCtrl,
                        decoration: const InputDecoration(
                          labelText: 'About',
                          prefixIcon: Icon(Icons.info_outline),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.onPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Next'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

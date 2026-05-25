import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscureKey = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = _urlCtrl.text.trim();
      final key = _keyCtrl.text.trim();
      final auth = context.read<AuthProvider>();
      await auth.save(url, key);
      final ok = await auth.apiService!.checkHealth();
      if (!ok && mounted) {
        await auth.clear();
        setState(() => _error = 'Could not reach server. Check URL and try again.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 2),
                      ),
                      child: const Icon(Icons.dns_rounded, color: AppColors.primary, size: 36),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Drilex VPS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Connect to your server',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: AppColors.textDim),
                    ),
                    const SizedBox(height: 36),
                    TextFormField(
                      controller: _urlCtrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        hintText: 'https://your-server.com',
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'URL is required';
                        final u = Uri.tryParse(v.trim());
                        if (u == null || !u.hasScheme) return 'Enter a valid URL';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _keyCtrl,
                      obscureText: _obscureKey,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: 'Bearer token',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          ),
                          onPressed: () => setState(() => _obscureKey = !_obscureKey),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'API key is required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: AppColors.danger, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _connect,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.link_rounded, size: 18),
                        label: Text(_loading ? 'Connecting...' : 'Connect'),
                      ),
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
}

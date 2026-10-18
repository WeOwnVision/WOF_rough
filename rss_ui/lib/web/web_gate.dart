import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';
import '../widgets/state_views.dart';
import 'pages/web_onboarding_page.dart';
import 'web_shell.dart';
import 'widgets/web_ui.dart';

/// Web girişi: oturum yoksa giriş ekranı; ilgi alanları seçilmemişse
/// [WebOnboardingPage]; ikisi de tamamsa [WebShell].
class WebGate extends StatefulWidget {
  const WebGate({super.key});

  @override
  State<WebGate> createState() => _WebGateState();
}

class _WebGateState extends State<WebGate> {
  final _state = AppState.instance;

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        if (_state.user != null) {
          // Sunucu `onboarding_completed: false` döndürdüyse 3 adımlı
          // onboarding (seç → tadına bak → akışın hazır) tamamlanır.
          return _state.showOnboarding
              ? const WebOnboardingPage()
              : const WebShell();
        }
        if (_state.sessionLoading) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: LoadingView(message: 'Signing you in…'),
          );
        }
        return _LoginScreen(state: _state);
      },
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.state});

  final AppState state;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _username = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _username.text.trim();
    if (name.isEmpty || widget.state.loggingIn) return;
    widget.state.login(name);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final error = state.sessionError;
    final offline =
        error != null &&
        (error.kind == ApiErrorKind.unavailable ||
            error.kind == ApiErrorKind.network);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.4),
            radius: 1.2,
            colors: [
              AppColors.accentDeep.withValues(alpha: 0.18),
              AppColors.background,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: PanelCard(
                padding: const EdgeInsets.fromLTRB(36, 40, 36, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const WofLogo(fontSize: 34),
                    const SizedBox(height: 6),
                    Text(
                      'World of Feeds',
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Welcome',
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pick a username to start. New names get an account '
                      'automatically.',
                      style: GoogleFonts.inter(
                        color: AppColors.textBody,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _username,
                      autofocus: true,
                      enabled: !state.loggingIn,
                      onSubmitted: (_) => _submit(),
                      maxLength: 50,
                      cursorColor: AppColors.accentLight,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Username',
                        counterText: '',
                        hintStyle: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 15,
                        ),
                        prefixIcon: const Icon(
                          Icons.person_outline_rounded,
                          color: AppColors.iconMuted,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceAlt,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.accent),
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            offline
                                ? Icons.cloud_off_rounded
                                : Icons.error_outline_rounded,
                            size: 18,
                            color: AppColors.dislike,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              error.userMessage,
                              style: GoogleFonts.inter(
                                color: AppColors.dislike,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: state.loggingIn
                          ? const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.accentLight,
                                ),
                              ),
                            )
                          : WebButton(
                              label: offline ? 'Try again' : 'Continue',
                              icon: Icons.arrow_forward_rounded,
                              onTap: _submit,
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

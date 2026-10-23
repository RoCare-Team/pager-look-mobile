import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/api/auth_api.dart';
import 'onboarding_shared.dart';

/// Step 1 of enterprise onboarding — port of `pages/auth/BusinessBasicInfo.jsx`.
///
/// Guests create the admin account and company in one go
/// (`POST /auth/enterprise/register`). A signed-in enterprise user editing from
/// the review step instead saves through `PATCH /enterprise/onboarding/basic-info`.
class BusinessBasicInfoScreen extends ConsumerStatefulWidget {
  const BusinessBasicInfoScreen({super.key});

  @override
  ConsumerState<BusinessBasicInfoScreen> createState() => _BusinessBasicInfoScreenState();
}

class _BusinessBasicInfoScreenState extends ConsumerState<BusinessBasicInfoScreen> {
  final _formKey = GlobalKey<FormState>();

  // Account
  final _loginEmail = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  // Company
  String? _companyType;
  String? _industry;
  String? _companySize;
  final _brn = TextEditingController();
  final _taxId = TextEditingController();
  final _companyName = TextEditingController();
  final _workEmail = TextEditingController();

  // Contact & address
  final _contactName = TextEditingController();
  final _phone = TextEditingController();
  final _pincode = TextEditingController();
  final _locality = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _country = TextEditingController(text: 'India');

  bool _touched = false;
  bool _saving = false;
  bool _loading = false;
  Object? _loadError;
  bool _pincodeLoading = false;
  Timer? _pincodeTimer;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated && auth.isEnterprise) _loadOnboarding();
  }

  @override
  void dispose() {
    _pincodeTimer?.cancel();
    for (final c in [
      _loginEmail,
      _password,
      _confirmPassword,
      _brn,
      _taxId,
      _companyName,
      _workEmail,
      _contactName,
      _phone,
      _pincode,
      _locality,
      _city,
      _state,
      _country,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOnboarding() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = asMap(await ref.read(enterpriseApiProvider).fetchOnboarding());
      if (!mounted) return;
      _applyOnboarding(data);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e;
      });
    }
  }

  void _applyOnboarding(Map<String, dynamic> data) {
    final c = asMap(data['company']);
    final onboarding = asMap(data['onboarding']);
    final b = asMap(onboarding['basicInfo']);
    final r = asMap(onboarding['registration']);
    if (c.isEmpty && b.isEmpty) return;

    String first(List<Object?> values, [String fallback = '']) {
      for (final v in values) {
        final s = strOrNull(v);
        if (s != null) return s;
      }
      return fallback;
    }

    final type = first([b['companyType'], c['companyType']]);
    final industry = first([b['industry'], c['industry']]);
    final size = first([b['companySize'], c['companySize']]);
    _companyType = companyTypeOptions.containsKey(type) ? type : null;
    _industry = industry.isEmpty ? null : industry;
    _companySize = size.isEmpty ? null : size;
    _brn.text = first([r['brn'], c['brn']]);
    _taxId.text = first([r['taxId'], c['taxId']]);
    _companyName.text = first([b['companyName'], b['companyLegalName'], c['companyLegalName'], c['name']]);
    final email = first([b['workEmail'], c['workEmail']]);
    _workEmail.text = email;
    _loginEmail.text = email;
    _contactName.text = first([b['contactName'], c['contactName']]);
    _phone.text = first([b['phone'], c['phone']]);
    _pincode.text = first([b['pincode'], c['pincode']]);
    _locality.text = first([b['locality'], c['locality']]);
    _city.text = first([b['city'], c['city']]);
    _state.text = first([b['state'], c['state']]);
    _country.text = first([b['country'], c['country']], 'India');
  }

  // ── Pincode auto-fill ─────────────────────────────────────────────────────

  void _onPincodeChanged(String value) {
    setState(() {});
    _pincodeTimer?.cancel();
    final pin = value.replaceAll(RegExp(r'\D'), '');
    if (pin.length != 6) return;
    _pincodeTimer = Timer(const Duration(milliseconds: 450), () => _lookupPincode(pin));
  }

  Future<void> _lookupPincode(String pin) async {
    setState(() => _pincodeLoading = true);
    try {
      final result = await lookupIndianPincode(pin);
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _city.text = result.city;
          _locality.text = result.locality;
          _state.text = result.state;
          _country.text = result.country;
        });
        showToast('${result.locality}, ${result.city} — address filled automatically', type: ToastType.success);
      } else {
        showToast('Pincode not found. Please enter city and locality manually.', type: ToastType.error);
      }
    } catch (_) {
      if (mounted) showToast('Could not look up pincode. Enter address manually.', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _pincodeLoading = false);
    }
  }

  // ── Validation (same rules as the web) ────────────────────────────────────

  bool _needsAccount() {
    final auth = ref.read(authProvider);
    return !auth.isAuthenticated || !auth.isEnterprise;
  }

  CompanyTypeConfig get _typeConfig => companyTypeConfig(_companyType);

  bool get _brnValid => _companyType != null && isValidBRN(_brn.text, _companyType);

  bool get _gstValid {
    if (_companyType == null) return false;
    final tax = _taxId.text.trim();
    return _typeConfig.gstRequired ? tax.isNotEmpty && isValidGSTIN(tax) : tax.isEmpty || isValidGSTIN(tax);
  }

  bool _isValid(bool needsAccount) {
    final accountValid = !needsAccount ||
        (isValidEmail(_loginEmail.text) &&
            _password.text.length >= 8 &&
            _password.text == _confirmPassword.text);
    return accountValid &&
        _companyType != null &&
        _brnValid &&
        _gstValid &&
        _companyName.text.trim().isNotEmpty &&
        _industry != null &&
        _companySize != null &&
        isValidEmail(_workEmail.text) &&
        _contactName.text.trim().isNotEmpty &&
        isValidRegistrationPhone(_phone.text) &&
        isValidIndianPincode(_pincode.text) &&
        _locality.text.trim().isNotEmpty &&
        _city.text.trim().isNotEmpty &&
        _country.text.trim().isNotEmpty;
  }

  String? _required(String? v, String message) => (v == null || v.trim().isEmpty) ? message : null;

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final needsAccount = _needsAccount();
    setState(() => _touched = true);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || !_isValid(needsAccount)) {
      showToast('Please fill all required fields correctly', type: ToastType.error);
      return;
    }

    setState(() => _saving = true);
    final enterpriseApi = ref.read(enterpriseApiProvider);
    final registrationPayload = <String, dynamic>{
      'brn': _brn.text.trim().toUpperCase(),
      if (_taxId.text.trim().isNotEmpty) 'taxId': _taxId.text.trim().toUpperCase(),
    };

    try {
      if (needsAccount) {
        final data = asMap(await ref.read(authApiProvider).registerEnterprise(
              buildEnterpriseRegisterPayload(
                email: _loginEmail.text,
                password: _password.text,
                confirmPassword: _confirmPassword.text,
                companyLegalName: _companyName.text,
                companyType: _companyType,
                industry: _industry!,
                companySize: _companySize!,
                workEmail: _workEmail.text,
                contactName: _contactName.text,
                phone: _phone.text,
                country: _country.text,
                city: _city.text,
                state: _state.text,
                pincode: _pincode.text,
                locality: _locality.text,
                brn: _brn.text,
                taxId: _taxId.text,
              ),
            ));
        if (strOrNull(data['accessToken']) != null) {
          await ref.read(authProvider).loginEnterprise(data);
        }
        await enterpriseApi.updateRegistration(registrationPayload);
        showToast('Account created successfully', type: ToastType.success);
        if (!mounted) return;
        context.go(strOrNull(data['homeRoute']) ?? '/enterprise/verify');
        return;
      }

      await enterpriseApi.updateBasicInfo({
        'companyName': _companyName.text.trim(),
        'companyType': _companyType,
        'industry': _industry,
        'companySize': _companySize,
        'workEmail': _workEmail.text.trim(),
        'contactName': _contactName.text.trim(),
        'phone': _phone.text.trim(),
        'pincode': _pincode.text,
        'locality': _locality.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'country': _country.text.trim(),
      });
      await enterpriseApi.updateRegistration(registrationPayload);
      ref.invalidate(enterpriseOnboardingProvider);
      showToast('Company details saved successfully', type: ToastType.success);
      if (!mounted) return;
      context.go('/enterprise/verify');
    } catch (e) {
      showErrorToast(e, 'Registration failed');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/enterprise/login');
    }
  }

  void _syncWorkEmail() {
    if (_workEmail.text.isEmpty && _loginEmail.text.isNotEmpty) {
      setState(() => _workEmail.text = _loginEmail.text);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final needsAccount = !auth.isAuthenticated || !auth.isEnterprise;

    Widget body;
    if (_loading) {
      body = const LoadingView(label: 'Loading onboarding...');
    } else if (_loadError != null) {
      body = ErrorView(error: _loadError, onRetry: _loadOnboarding);
    } else {
      body = BusyOverlay(
        busy: _saving,
        label: 'Saving...',
        child: Form(
          key: _formKey,
          child: StickyActionLayout(
            body: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OnboardingStepper(currentStep: 1),
                  const SizedBox(height: 16),
                  const Text(
                    'Tell us about your company to set up your employer account.',
                    style: TextStyle(fontSize: 14, color: AppColors.inkMuted, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  if (needsAccount) ...[
                    _accountSection(),
                    const SizedBox(height: 16),
                  ],
                  _companySection(),
                  const SizedBox(height: 16),
                  _addressSection(),
                  const SizedBox(height: 16),
                  const Text.rich(
                    TextSpan(
                      text: 'Fields marked with ',
                      children: [
                        TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                        TextSpan(text: ' are required.'),
                      ],
                    ),
                    style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                  ),
                  if (needsAccount) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already registered?', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                        TextButton(
                          onPressed: _saving ? null : () => context.go('/enterprise/login'),
                          child: const Text('Sign in', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              AppButton(
                label: 'Back',
                variant: AppButtonVariant.outline,
                onPressed: _saving ? null : _back,
              ),
              AppButton(label: 'Continue', loading: _saving, onPressed: _saving ? null : _submit),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Basic Info'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : _back,
        ),
      ),
      body: body,
    );
  }

  Widget _accountSection() {
    final passwordsMatch = _password.text == _confirmPassword.text;
    return OnboardingSection(
      title: 'Account Credentials',
      subtitle: 'Create your admin login for the PagerLook employer portal.',
      children: [
        Focus(
          onFocusChange: (focused) {
            if (!focused) _syncWorkEmail();
          },
          child: AppTextField(
            controller: _loginEmail,
            label: 'Admin Email',
            hint: 'admin@company.com',
            requiredMark: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            validator: (v) => emailValidator(v),
          ),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _password,
          label: 'Password',
          hint: 'Min. 8 characters',
          requiredMark: true,
          obscure: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() {}),
          validator: (v) => (v ?? '').length < 8 ? 'Password must be at least 8 characters' : null,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _confirmPassword,
          label: 'Confirm Password',
          hint: 'Re-enter password',
          requiredMark: true,
          obscure: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if ((v ?? '').isEmpty) return 'Please confirm your password';
            if (v != _password.text) return 'Passwords do not match.';
            return null;
          },
        ),
        if (_touched && !passwordsMatch && _confirmPassword.text.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Passwords do not match.', style: TextStyle(fontSize: 13, color: AppColors.danger)),
          ),
      ],
    );
  }

  Widget _companySection() {
    final config = _typeConfig;
    final regLabel = config.registration.label;
    return OnboardingSection(
      title: 'Company Details',
      subtitle: 'Start by selecting your business type — registration fields will appear automatically.',
      children: [
        AppDropdown<String>(
          label: 'Company Type',
          hint: 'Select business entity type',
          requiredMark: true,
          options: companyTypeOptions,
          value: _companyType,
          onChanged: (v) => setState(() {
            _companyType = v;
            _brn.clear();
            _taxId.clear();
          }),
          validator: (v) => v == null ? 'Company type is required' : null,
        ),
        if (_companyType != null) ...[
          const SizedBox(height: 16),
          AppTextField(
            key: ValueKey('brn-$_companyType'),
            controller: _brn,
            label: regLabel,
            hint: config.registration.placeholder,
            helper: config.registration.hint,
            requiredMark: true,
            prefixIcon: Icons.work_outline,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [MappingInputFormatter((v) => formatRegistrationInput(v, _companyType))],
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isEmpty) return 'Registration number is required';
              if (!isValidBRN(value, _companyType)) return 'Invalid $regLabel format';
              return null;
            },
          ),
          ValidHint(_brn.text.trim().isNotEmpty && _brnValid ? 'Valid registration number format' : ''),
          const SizedBox(height: 8),
          AppTextField(
            key: ValueKey('gst-$_companyType'),
            controller: _taxId,
            label: config.gstRequired ? 'GSTIN (Tax Identification)' : 'GSTIN (Optional)',
            hint: 'e.g. 27AABCU9603R1ZM',
            helper: config.gstRequired ? gstinHint : 'Leave blank if not registered for GST',
            requiredMark: config.gstRequired,
            prefixIcon: Icons.credit_card,
            maxLength: 15,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [MappingInputFormatter(formatGSTINInput)],
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isNotEmpty && !isValidGSTIN(value)) return 'Invalid GSTIN — must be 15 characters';
              if (config.gstRequired && value.isEmpty) return 'GSTIN is required';
              return null;
            },
          ),
          ValidHint(_taxId.text.length == 15 && isValidGSTIN(_taxId.text) ? 'Valid GSTIN format' : ''),
        ],
        const SizedBox(height: 16),
        AppTextField(
          controller: _companyName,
          label: 'Company Legal Name',
          hint: 'e.g. Acme Technologies Pvt. Ltd.',
          requiredMark: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: (v) => _required(v, 'Company legal name is required'),
        ),
        const SizedBox(height: 16),
        AppDropdown<String>(
          label: 'Industry',
          hint: 'Select industry',
          requiredMark: true,
          options: industryOptions,
          value: _industry,
          onChanged: (v) => setState(() => _industry = v),
          validator: (v) => v == null ? 'Industry is required' : null,
        ),
        const SizedBox(height: 16),
        AppDropdown<String>(
          label: 'Company Size',
          hint: 'Select company size',
          requiredMark: true,
          options: companySizeOptions,
          value: _companySize,
          onChanged: (v) => setState(() => _companySize = v),
          validator: (v) => v == null ? 'Company size is required' : null,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _workEmail,
          label: 'Official Work Email',
          hint: 'hr@company.com',
          requiredMark: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          validator: (v) => emailValidator(v),
        ),
      ],
    );
  }

  Widget _addressSection() {
    return OnboardingSection(
      title: 'Contact & Address',
      subtitle: 'Enter your 6-digit pincode — city and locality will fill automatically.',
      children: [
        AppTextField(
          controller: _contactName,
          label: 'Authorized Contact Person',
          hint: 'Full name',
          requiredMark: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          validator: (v) => _required(v, 'Contact person is required'),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _phone,
          label: 'Phone Number',
          hint: '+91 98765 43210',
          requiredMark: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]'))],
          validator: (v) => isValidRegistrationPhone(v ?? '') ? null : 'Enter a valid phone number',
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _pincode,
          label: 'Pincode',
          hint: 'e.g. 400001',
          helper: '6-digit Indian pincode',
          requiredMark: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [MappingInputFormatter(formatPincodeInput)],
          onChanged: _onPincodeChanged,
          suffix: _pincodeLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
          validator: (v) => isValidIndianPincode(v ?? '') ? null : 'Enter a valid 6-digit pincode',
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _locality,
          label: 'Locality / Area',
          hint: 'Auto-filled from pincode',
          requiredMark: true,
          textCapitalization: TextCapitalization.words,
          validator: (v) => _required(v, 'Locality is required'),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _city,
          label: 'City / District',
          hint: 'Auto-filled from pincode',
          requiredMark: true,
          textCapitalization: TextCapitalization.words,
          validator: (v) => _required(v, 'City is required'),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _state,
          label: 'State',
          hint: 'Auto-filled from pincode',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _country,
          label: 'Country',
          hint: 'e.g. India',
          requiredMark: true,
          textCapitalization: TextCapitalization.words,
          validator: (v) => _required(v, 'Country is required'),
        ),
      ],
    );
  }
}

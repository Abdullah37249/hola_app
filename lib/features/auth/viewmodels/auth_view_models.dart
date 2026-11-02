import '../../../core/mvvm/view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../core/l10n/l10n.dart';

/// 0–4 password strength: length, mixed case, digits, symbols.
int passwordStrength(String p) {
  if (p.isEmpty) return 0;
  var s = p.length >= 8 ? 1 : 0;
  if (p.length >= 12) s++;
  if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
  if (RegExp(r'\d').hasMatch(p)) s++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
  return s.clamp(p.length >= 8 ? 1 : 0, 4);
}

String strengthHint(int s) => switch (s) {
  0 => tr('At least 8 characters'),
  1 => tr('Weak: add numbers or symbols'),
  2 => tr('Fair: mix upper and lower case'),
  3 => tr('Good'),
  _ => tr('Strong password'),
};

class SignInViewModel extends ViewModel {
  SignInViewModel(this._auth);
  final AuthRepository _auth;

  bool obscure = true;
  void toggleObscure() {
    obscure = !obscure;
    notify();
  }

  /// Returns the signed-in account, or throws a [DomainError].
  Future<Account> signIn(String email, String password) {
    if (email.trim().isEmpty || password.isEmpty) throw DomainError(tr('Enter your email and password.'), field: email.trim().isEmpty ? 'email' : 'password');
    return _auth.signIn(email, password);
  }
}

class SignUpViewModel extends ViewModel {
  SignUpViewModel(this._auth);
  final AuthRepository _auth;

  Role? role;
  String password = '';
  bool terms = false, obscure = true;

  int get strength => passwordStrength(password);

  void pickRole(Role r) {
    role = r;
    notify();
  }

  void setPassword(String v) {
    password = v;
    notify();
  }

  void toggleTerms() {
    terms = !terms;
    notify();
  }

  void toggleObscure() {
    obscure = !obscure;
    notify();
  }

  Future<Account> submit({required String name, required String email, required String phone, required String city}) {
    if (role == null) throw DomainError(tr('Choose how you will use HOLA.'));
    if (!terms) throw DomainError(tr('Please accept the terms to continue.'), field: 'terms');
    return _auth.signUp(role: role!, name: name, email: email, phone: phone, password: password, city: city);
  }
}

class ResetPasswordViewModel extends ViewModel {
  ResetPasswordViewModel(this._auth);
  final AuthRepository _auth;

  String password = '';
  bool obscure = true;
  int get strength => passwordStrength(password);

  void setPassword(String v) {
    password = v;
    notify();
  }

  void toggleObscure() {
    obscure = !obscure;
    notify();
  }

  Future<void> reset({required String email, required String phone}) {
    if (email.trim().isEmpty || phone.trim().isEmpty) throw DomainError(tr('Enter the email and phone number on your account.'), field: email.trim().isEmpty ? 'email' : 'phone');
    return _auth.resetPassword(email: email, phone: phone, newPassword: password);
  }
}

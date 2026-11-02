import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/mvvm/view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../auth/viewmodels/auth_view_models.dart' show passwordStrength;
import '../../../core/l10n/l10n.dart';

/// The signed-in account, plus where they work (for owners and staff).
class AccountViewModel extends RepoViewModel {
  AccountViewModel(this._auth, this._salons) : super(_auth);
  final AuthRepository _auth;
  final SalonRepository _salons;

  Account? get account => _auth.current;

  /// "Owner · Maison Noor", "Sales officer · Lahore", "Customer".
  String get line {
    final a = account;
    if (a == null) return '';
    final salon = a.salonId == null ? null : _salons.salon(a.salonId!);
    final title = a.role == Role.salonOwner || a.role == Role.salonStaff ? (_salons.staffProfile(a.id)?.title ?? a.role.label) : a.role.label;
    final where = salon?.name ?? (a.city.isEmpty ? null : a.city);
    return where == null ? title : '$title · $where';
  }
}

class EditProfileViewModel extends ViewModel {
  EditProfileViewModel(this._auth);
  final AuthRepository _auth;
  Account get account => _auth.current!;
  Future<void> save({required String name, required String phone, required String city}) => _auth.updateProfile(name: name, phone: phone, city: city);
}

class ChangePasswordViewModel extends ViewModel {
  ChangePasswordViewModel(this._auth);
  final AuthRepository _auth;
  String next = '';
  bool obscure = true;
  int get strength => passwordStrength(next);

  void setNext(String v) {
    next = v;
    notify();
  }

  void toggleObscure() {
    obscure = !obscure;
    notify();
  }

  Future<void> change(String current, String confirm) {
    if (current.isEmpty) throw DomainError(tr('Enter your current password.'), field: 'current');
    if (next != confirm) throw DomainError(tr("The new passwords don't match."), field: 'confirm');
    if (next == current) throw DomainError(tr('Choose a password different from the current one.'), field: 'password');
    return _auth.changePassword(current, next);
  }
}

class DeleteAccountViewModel extends ViewModel {
  DeleteAccountViewModel(this._auth);
  final AuthRepository _auth;
  Account? get account => _auth.current;
  Future<void> delete(String password) {
    if (password.isEmpty) throw DomainError(tr('Enter your password to confirm.'), field: 'password');
    return _auth.deleteAccount(password);
  }
}

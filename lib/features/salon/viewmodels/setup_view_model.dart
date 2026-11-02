import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/view_model.dart';
import '../../../domain/repositories/repositories.dart';

/// First-run salon set-up wizard: about → location → review → create.
class SetupViewModel extends ViewModel {
  SetupViewModel(this._salons, this._auth);
  final SalonRepository _salons;
  final AuthRepository _auth;

  static List<String> get steps => [tr('Your salon'), tr('Location'), tr('Review')];
  int step = 0;

  String name = '', phone = '', about = '';
  String branchName = '', address = '', area = '', city = '';

  String get ownerName => _auth.current?.firstName ?? '';
  String get ownerPhone => _auth.current?.phone ?? '';
  String get ownerCity => _auth.current?.city ?? '';
  /// Palette the new salon will get (matches the repository's choice).
  int get salonCount => _salons.allSalons().length;

  /// What is missing on the current step (null = can continue).
  /// What still blocks this step, tied to its field so the form can show it there.
  DomainError? get missing => switch (step) {
        0 => name.trim().length < 2
            ? DomainError(tr('Enter your salon name.'), field: 'name')
            : phone.replaceAll(RegExp(r'[^0-9]'), '').length < 10
                ? DomainError(tr('Enter the salon phone number.'), field: 'phone')
                : null,
        1 => address.trim().length < 2
            ? DomainError(tr('Enter the street address.'), field: 'address')
            : area.trim().length < 2
                ? DomainError(tr('Enter the area.'), field: 'area')
                : city.trim().length < 2
                    ? DomainError(tr('Enter the city.'), field: 'city')
                    : null,
        _ => null,
      };

  void next() {
    if (step < steps.length - 1) step++;
    notify();
  }

  void back() {
    if (step > 0) step--;
    notify();
  }

  void update(void Function() f) {
    f();
    notify();
  }

  Future<void> create() => _salons.createSalon(name: name, phone: phone, about: about, branchName: branchName, address: address, area: area, city: city);

  Future<void> signOut() => _auth.signOut();
}

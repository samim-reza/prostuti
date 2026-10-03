/// Rough password strength, 0 (empty/very weak) … 4 (strong).
///
/// +1 for ≥ 8 characters, +1 for ≥ 12, +1 for mixed letter case (or letters
/// mixed with digits), +1 for a digit **and** a symbol.
int passwordStrength(String password) {
  if (password.isEmpty) return 0;
  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  final lower = RegExp('[a-z]').hasMatch(password);
  final upper = RegExp('[A-Z]').hasMatch(password);
  final digit = RegExp(r'\d').hasMatch(password);
  final symbol = RegExp('[^A-Za-z0-9]').hasMatch(password);
  if ((lower && upper) || ((lower || upper) && digit)) score++;
  if (digit && symbol) score++;
  return score;
}

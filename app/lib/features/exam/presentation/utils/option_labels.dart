/// Option labels as printed on BCS answer sheets: ক খ গ ঘ for Bangla
/// questions, A B C D for English ones. Falls back to numbers beyond the
/// alphabet.
const bnOptionLabels = ['ক', 'খ', 'গ', 'ঘ', 'ঙ', 'চ'];
const enOptionLabels = ['A', 'B', 'C', 'D', 'E', 'F'];

String optionLabel(int index, {required String language}) {
  final labels = language == 'en' ? enOptionLabels : bnOptionLabels;
  if (index >= 0 && index < labels.length) return labels[index];
  return '${index + 1}';
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/config/remote_config.dart';
import 'package:prostuti/core/utils/json.dart';
import 'package:url_launcher/url_launcher.dart';

/// Support address from remote config (falls back to the built-in one).
final supportEmailProvider = Provider<String>((ref) {
  final config = ref.watch(remoteConfigProvider).value;
  final email = config?.support.str('email').trim() ?? '';
  return email.isEmpty ? AppConstants.supportEmail : email;
});

/// App version info (read once per session).
final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

/// `mailto:` URI with properly percent-encoded subject/body (spaces as %20,
/// not '+', so every mail client shows them correctly).
Uri mailtoUri(String to, {String? subject, String? body}) {
  final query = [
    if (subject != null) 'subject=${Uri.encodeComponent(subject)}',
    if (body != null) 'body=${Uri.encodeComponent(body)}',
  ].join('&');
  return Uri.parse('mailto:$to${query.isEmpty ? '' : '?$query'}');
}

/// Opens the mail app; returns false when no mail client is available.
Future<bool> launchEmail(String to, {String? subject, String? body}) async {
  try {
    return await launchUrl(mailtoUri(to, subject: subject, body: body));
  } on Object {
    return false;
  }
}

/// Opens an external link in the browser; returns false on failure.
Future<bool> launchExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

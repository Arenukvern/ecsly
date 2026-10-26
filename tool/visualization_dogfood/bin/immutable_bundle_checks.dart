import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:oka_web/oka_web.dart';

Future<void> qualifyImmutableBundle(
  Uri origin,
  WebBundleSnapshot snapshot,
  Directory output,
  List<Map<String, Object?>> checks,
) async {
  final client = HttpClient();
  try {
    final uri = origin.resolveUri(snapshot.assetUri('main.dart.js'));
    final response = await (await client.getUrl(uri)).close();
    final bytes = await response.fold<List<int>>([], (b, c) => b..addAll(c));
    final hash = sha256.convert(bytes).toString();
    final policy = response.headers.value(HttpHeaders.cacheControlHeader);
    if (response.statusCode != 200 ||
        hash != snapshot.manifest.files['main.dart.js']!.sha256 ||
        policy != 'private, max-age=31536000, immutable') {
      throw StateError('Immutable asset bytes/cache policy mismatch');
    }
    final wrong = origin.resolve('/bundles/wrong/main.dart.js');
    final refused = await (await client.getUrl(wrong)).close();
    await refused.drain<void>();
    if (refused.statusCode != 404)
      throw StateError('Wrong bundle identity served');
    await File('${output.path}/immutable-bundle.json').writeAsString(
      jsonEncode({
        'digest': snapshot.digest,
        'snapshotBytes': snapshot.byteLength,
        'assetUri': uri.toString(),
        'status': response.statusCode,
        'cacheControl': policy,
        'bodySha256': hash,
        'wrongIdentityStatus': refused.statusCode,
        'limit': 'Immutable output snapshot and asset route; entry-page URLs, compiler inputs and browser cache hits are separate.',
      }),
    );
    checks.add({
      'action': 'immutable digest-addressed asset',
      'effect':
          'exact bytes and immutable policy observed; wrong identity refused',
    });
  } finally {
    client.close(force: true);
  }
}

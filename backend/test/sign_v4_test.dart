import 'package:test/test.dart';
import 'package:vote_job/vote_job.dart';

void main() {
  // Cas « get-vanilla » de la suite de tests officielle AWS Signature V4.
  test('signe une requête comme la suite de tests AWS (get-vanilla)', () {
    final headers = signV4(
      method: 'GET',
      uri: Uri.parse('https://example.amazonaws.com/'),
      headers: {'Host': 'example.amazonaws.com'},
      payload: const [],
      accessKeyId: 'AKIDEXAMPLE',
      secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
      region: 'us-east-1',
      service: 'service',
      now: DateTime.utc(2015, 8, 30, 12, 36),
      signContentSha256: false,
    );

    expect(headers['x-amz-date'], '20150830T123600Z');
    expect(
      headers['authorization'],
      'AWS4-HMAC-SHA256 '
      'Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, '
      'SignedHeaders=host;x-amz-date, '
      'Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
    );
  });
}

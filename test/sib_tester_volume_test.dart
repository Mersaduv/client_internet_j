import 'package:flutter_test/flutter_test.dart';
import 'package:jahan_bit/services/sib_volume_client.dart';

void main() {
  test('reads the tester creditinfo page and the subscriber name', () {
    const creditHtml = '''
<br>Result<br><table>
<tr><td>StatusCode</td><td>200</td></tr>
</table>
<pre>[{"ServiceStatus":"Active","ServiceName":"160GB-1Month-5Mb-FRH","STrA":"171,798,691,840","STrU":"0","STrR":"171,798,691,840"}]</pre>
''';
    const nameHtml = '''
<pre>[{"username":"jb.admin","name":"admin","family":"jahanbit"}]</pre>
''';
    final credit = sibCreditRecord(SibVolumeClient.sibDecodePayload(creditHtml));
    expect(credit?['ServiceName'], '160GB-1Month-5Mb-FRH');
    expect(sibPersonName(SibVolumeClient.sibDecodePayload(nameHtml)), 'admin jahanbit');
  });
}

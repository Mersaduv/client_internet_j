import 'package:flutter_test/flutter_test.dart';
import 'package:jahan_bit/services/deltasib_auth_service.dart';
import 'package:jahan_bit/services/sib_customer_service.dart';

void main() {
  test('parses token from the working test.login.php HTML', () {
    const html = '''
<tr><td>StatusCode</td><td>200</td></tr>
<tr><td>Result</td><td>{"token":"abc.def.ghi","SessionTimeout":"600"}</td></tr>
''';
    final session = DeltaSibAuthService.parseLoginPage(html);
    expect(session, isNotNull);
    expect(session!.token, 'abc.def.ghi');
    expect(session.sessionTimeoutSeconds, 600);
  });

  test('extracts Result cell from creditinfo HTML', () {
    const html =
        '<tr><td>Result</td><td><font color=blue>{"ServiceName":"10G","STrR":"100"}</font></td></tr>';
    expect(
      SibCustomerService.extractResultCell(html),
      '{"ServiceName":"10G","STrR":"100"}',
    );
  });

  test('extracts JSON from the DeltaSIB test page HTML', () {
    const html = '''
<h2>API Request Test</h2>
<form method="post" action="/test/webservice/api/restfull/test.user.creditinfo.php">
<input type="text" name="token" value="eyJ.secret">
</form>
<br>Result<br><table border=1 cellspacing=0 cellpadding=0>
<tr><td>StatusCode</td><td><font color=blue>200</font></td></tr>
</table><table border=1 cellspacing=0 cellpadding=0 title='pp'>
<tr><td><font color=blue><pre lang="xml">[{"ServiceStatus":"Active","ServiceName":"100GB-5Mb-1Month-FRH","STrA":"107,374,182,400"}]</pre></font></td></tr>
</table>
''';
    final extracted = SibCustomerService.extractResultCell(html);
    expect(extracted, contains('"ServiceName":"100GB-5Mb-1Month-FRH"'));
    expect(extracted, isNot(contains('<pre')));
    expect(extracted, isNot(contains('<form')));
  });

  test('Api_Key is sha512 of the password', () {
    // echo -n 123 | sha512
    expect(
      DeltaSibAuthService.apiKeyForPassword('123'),
      '3c9909afec25354d551dae21590bb26e38d53f2173b8d3dc3eee4c047e7ab1c1eb8b85103e3be7ba613b31bb5c9c36214dc9f14a42fd7a2fdb84856bca5c44c2',
    );
  });
}

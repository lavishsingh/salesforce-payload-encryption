// Manually test JWT Bearer token exchange to diagnose auth failure
Long nowEpoch = DateTime.now().getTime() / 1000;
Long expEpoch = nowEpoch + 180;

// Build JWT header
String header = '{"alg":"RS256","typ":"JWT"}';
String headerB64 = EncodingUtil.base64Encode(Blob.valueOf(header))
    .replace('+', '-').replace('/', '_').replace('=', '');

// Build JWT body with all required claims
String body = '{"iss":"3MVG97L7PWbPq6UwiLonoksFd0T_dwKA6.4v_tRKrUhval_r0H.hQWY3a4WEFwY3SA4Ege4ve.2f6I08TUxYa",' +
              '"sub":"ambush.s.857df7b99af5@agentforce.com",' +
              '"aud":"https://login.salesforce.com",' +
              '"exp":' + expEpoch + ',' +
              '"iat":' + nowEpoch + '}';
String bodyB64 = EncodingUtil.base64Encode(Blob.valueOf(body))
    .replace('+', '-').replace('/', '_').replace('=', '');

// Sign with OrgA_Signing_Cert
String signingInput = headerB64 + '.' + bodyB64;
Blob signature = Crypto.signWithCertificate('RSA-SHA256', Blob.valueOf(signingInput), 'OrgA_Signing_Cert');
String sigB64 = EncodingUtil.base64Encode(signature)
    .replace('+', '-').replace('/', '_').replace('=', '');

String jwt = signingInput + '.' + sigB64;
System.debug('JWT built successfully, length: ' + jwt.length());

// Call Salesforce token endpoint
HttpRequest req = new HttpRequest();
req.setEndpoint('https://login.salesforce.com/services/oauth2/token');
req.setMethod('POST');
req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
req.setBody('grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=' + jwt);
req.setTimeout(30000);

Http http = new Http();
HttpResponse res = http.send(req);
System.debug('Token endpoint status: ' + res.getStatusCode());
System.debug('Token endpoint body: ' + res.getBody());

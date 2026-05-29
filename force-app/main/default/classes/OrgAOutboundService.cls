public class OrgAOutboundService {

    public static void sendAccountAndContact(Account acc, Contact con) {
        String orgBBaseUrl   = IntegrationConfigService.get('OrgB_Base_URL');
        String orgBPath      = IntegrationConfigService.get('OrgB_Inbound_Path');
        String tokenEndpoint = IntegrationConfigService.get('Token_Endpoint');
        String consumerKey   = IntegrationConfigService.get('OrgB_Consumer_Key');
        String subject       = IntegrationConfigService.get('OrgB_Subject');
        String signingCert   = IntegrationConfigService.get('OrgB_Signing_Cert');

        // Step 1: Build the payload JSON
        Map<String, Object> payload = new Map<String, Object>{
            'account' => new Map<String, Object>{
                'Name'     => acc.Name,
                'Phone'    => acc.Phone,
                'Website'  => acc.Website,
                'Industry' => acc.Industry
            },
            'contact' => new Map<String, Object>{
                'FirstName' => con.FirstName,
                'LastName'  => con.LastName,
                'Email'     => con.Email,
                'Phone'     => con.Phone,
                'Title'     => con.Title
            }
        };
        String plainPayload = JSON.serialize(payload);

        // Step 2: Encrypt
        OrgAEncryptionService.EncryptedEnvelope envelope =
            OrgAEncryptionService.encryptPayload(plainPayload);

        // Step 3: Get access token via JWT Bearer Token Flow
        String accessToken = getOrgBAccessToken(tokenEndpoint, consumerKey, subject, signingCert);

        // Step 4: POST encrypted envelope to Org B REST endpoint
        HttpRequest req = new HttpRequest();
        req.setEndpoint(orgBBaseUrl + orgBPath);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setBody(JSON.serialize(envelope));
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            throw new OrgAOutboundException('Failed to reach Org B: ' + e.getMessage());
        }

        // Org B returns 202 Accepted (async Platform Event processing)
        if (res.getStatusCode() >= 300) {
            throw new OrgAOutboundException(
                'Org B returned HTTP ' + res.getStatusCode() + ' — ' + res.getBody()
            );
        }

        System.debug('OrgAOutboundService — Org B accepted request with HTTP ' + res.getStatusCode());
    }

    private static String getOrgBAccessToken(
        String tokenEndpoint, String consumerKey, String subject, String signingCert
    ) {
        Long nowEpoch = DateTime.now().getTime() / 1000;
        Long expEpoch = nowEpoch + 180;

        String header = '{"alg":"RS256","typ":"JWT"}';
        String headerB64 = EncodingUtil.base64Encode(Blob.valueOf(header))
            .replace('+', '-').replace('/', '_').replace('=', '');

        String body = '{"iss":"' + consumerKey + '",' +
                      '"sub":"' + subject + '",' +
                      '"aud":"https://login.salesforce.com",' +
                      '"exp":' + expEpoch + ',' +
                      '"iat":' + nowEpoch + '}';
        String bodyB64 = EncodingUtil.base64Encode(Blob.valueOf(body))
            .replace('+', '-').replace('/', '_').replace('=', '');

        String signingInput = headerB64 + '.' + bodyB64;
        Blob signature = Crypto.signWithCertificate('RSA-SHA256', Blob.valueOf(signingInput), signingCert);
        String sigB64 = EncodingUtil.base64Encode(signature)
            .replace('+', '-').replace('/', '_').replace('=', '');

        String jwt = signingInput + '.' + sigB64;

        HttpRequest tokenReq = new HttpRequest();
        tokenReq.setEndpoint(tokenEndpoint);
        tokenReq.setMethod('POST');
        tokenReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        tokenReq.setBody(
            'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=' + jwt
        );
        tokenReq.setTimeout(30000);

        HttpResponse tokenRes = new Http().send(tokenReq);
        if (tokenRes.getStatusCode() != 200) {
            throw new OrgAOutboundException(
                'JWT token exchange failed: HTTP ' + tokenRes.getStatusCode() +
                ' — ' + tokenRes.getBody()
            );
        }

        Map<String, Object> tokenData =
            (Map<String, Object>) JSON.deserializeUntyped(tokenRes.getBody());
        return (String) tokenData.get('access_token');
    }

    public class OrgAOutboundException extends Exception {}
}

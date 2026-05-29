public class SessionKeyDecryptionService {

    public static String decryptSessionKey(String encryptedSessionKeyBase64) {

        String requestBody = JSON.serialize(new Map<String, String>{
            'encryptedSessionKey' => encryptedSessionKeyBase64
        });

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + IntegrationConfigService.get('Python_Decrypt_NC') + '/decrypt');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(requestBody);
        req.setTimeout(30000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            throw new SessionKeyDecryptionException(
                'HTTP callout to Python /decrypt failed: ' + e.getMessage()
            );
        }

        if (res.getStatusCode() != 200) {
            throw new SessionKeyDecryptionException(
                'Python /decrypt returned HTTP ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String sessionKey = (String) responseMap.get('sessionKey');

        if (String.isBlank(sessionKey)) {
            throw new SessionKeyDecryptionException('Python /decrypt returned a blank session key');
        }

        return sessionKey;
    }

    public class SessionKeyDecryptionException extends Exception {}
}

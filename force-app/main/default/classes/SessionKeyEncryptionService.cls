public class SessionKeyEncryptionService {

    // Python /encrypt endpoint path
    private static final String ENCRYPT_PATH = '/encrypt';

    /**
     * Sends plain AES session key (Base64) to Python middleware.
     * Python RSA-encrypts it using Org B public key and returns encrypted key.
     *
     * @param plainSessionKeyB64 - Base64 encoded plain AES session key
     * @return Base64 encoded RSA-encrypted session key
     */
    public static String encryptSessionKey(String plainSessionKeyB64) {

        // Step 1: Build request body
        Map<String, String> requestBody = new Map<String, String>{
            'sessionKey' => plainSessionKeyB64
        };
        String requestJson = JSON.serialize(requestBody);

        // Step 2: Call Python /encrypt via Named Credential
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Python_Encrypt_API' + ENCRYPT_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(requestJson);
        req.setTimeout(30000);

        // Step 3: Send request
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (Exception e) {
            throw new SessionKeyEncryptionException(
                'Failed to reach Python middleware: ' + e.getMessage()
            );
        }

        // Step 4: Check HTTP status
        if (res.getStatusCode() != 200) {
            throw new SessionKeyEncryptionException(
                'Python /encrypt returned HTTP ' + res.getStatusCode() +
                ' — ' + res.getBody()
            );
        }

        // Step 5: Parse response and return encrypted session key
        Map<String, Object> responseMap =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        if (!responseMap.containsKey('encryptedSessionKey')) {
            throw new SessionKeyEncryptionException(
                'Python /encrypt response missing encryptedSessionKey field'
            );
        }

        return (String) responseMap.get('encryptedSessionKey');
    }

    public class SessionKeyEncryptionException extends Exception {}
}

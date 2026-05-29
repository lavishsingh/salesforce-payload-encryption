@RestResource(urlMapping='/secure/inbound/*')
global class SecureInboundAPI {

    @HttpPost
    global static void doPost() {
        RestRequest  req  = RestContext.request;
        RestResponse resp = RestContext.response;

        try {
            Map<String, Object> envelope = (Map<String, Object>)
                JSON.deserializeUntyped(req.requestBody.toString());

            String encryptedPayload    = (String) envelope.get('encryptedPayload');
            String encryptedSessionKey = (String) envelope.get('encryptedSessionKey');
            String signature           = (String) envelope.get('signature');

            if (String.isBlank(encryptedPayload) ||
                String.isBlank(encryptedSessionKey) ||
                String.isBlank(signature)) {
                resp.statusCode   = 400;
                resp.responseBody = Blob.valueOf(
                    JSON.serialize(new Map<String, String>{
                        'error' => 'Missing required envelope fields: encryptedPayload, encryptedSessionKey, signature'
                    })
                );
                return;
            }

            Encrypted_Payload__e event = new Encrypted_Payload__e(
                Encrypted_Payload__c     = encryptedPayload,
                Encrypted_Session_Key__c = encryptedSessionKey,
                Signature__c             = signature
            );
            EventBus.publish(event);

            resp.statusCode   = 202;
            resp.responseBody = Blob.valueOf(
                JSON.serialize(new Map<String, String>{
                    'status'  => 'accepted',
                    'message' => 'Payload queued for async decryption and sync'
                })
            );

        } catch (Exception e) {
            resp.statusCode   = 500;
            resp.responseBody = Blob.valueOf(
                JSON.serialize(new Map<String, String>{'error' => e.getMessage()})
            );
        }
    }
}

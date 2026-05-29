public class OrgBDecryptionService {

    public static String decrypt(
        String encryptedPayloadBase64,
        String encryptedSessionKeyBase64,
        String signatureBase64
    ) {
        // Step 1: RSA-decrypt the AES session key via Python middleware
        String plainSessionKeyBase64 = SessionKeyDecryptionService.decryptSessionKey(
            encryptedSessionKeyBase64
        );
        Blob sessionKeyBlob = EncodingUtil.base64Decode(plainSessionKeyBase64);

        // Step 2: Verify RSA-SHA256 signature with Org A public key stored in custom metadata
        Encryption_Key__mdt keyRecord = [
            SELECT Public_Key_PEM__c
            FROM   Encryption_Key__mdt
            WHERE  DeveloperName = 'OrgA_Signing_Public_Key'
            LIMIT  1
        ];

        String base64Key = keyRecord.Public_Key_PEM__c
            .replace('-----BEGIN PUBLIC KEY-----', '')
            .replace('-----END PUBLIC KEY-----', '')
            .replace('-----BEGIN CERTIFICATE-----', '')
            .replace('-----END CERTIFICATE-----', '')
            .replaceAll('\\s+', '');
        Blob orgAPubKeyBlob = EncodingUtil.base64Decode(base64Key);

        Blob signatureBlob = EncodingUtil.base64Decode(signatureBase64);
        Boolean isValid = Crypto.verify('RSA-SHA256', sessionKeyBlob, signatureBlob, orgAPubKeyBlob);

        if (!isValid) {
            throw new SignatureVerificationException(
                'RSA-SHA256 signature verification failed — payload rejected'
            );
        }

        // Step 3: AES-256 decrypt the payload (Org A prepends IV via encryptWithManagedIV)
        Blob encryptedPayloadBlob = EncodingUtil.base64Decode(encryptedPayloadBase64);
        Blob decryptedBlob = Crypto.decryptWithManagedIV('AES256', sessionKeyBlob, encryptedPayloadBlob);

        return decryptedBlob.toString();
    }

    public class SignatureVerificationException extends Exception {}
}

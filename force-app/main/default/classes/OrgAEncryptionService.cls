public class OrgAEncryptionService {

    // Certificate used for RSA signing — must match OrgA_Signing_Cert in Certificate and Key Management
    private static final String SIGNING_CERT = 'OrgA_Signing_Cert';

    // Algorithm used for RSA signature
    private static final String SIGN_ALGORITHM = 'RSA-SHA256';

    /**
     * Wrapper class representing the complete encrypted envelope
     * sent from Org A to Org B.
     */
    public class EncryptedEnvelope {
        public String encryptedPayload;     // AES-256 encrypted payload (Base64)
        public String encryptedSessionKey;  // RSA encrypted AES session key (Base64)
        public String signature;            // RSA-SHA256 signature of plain session key (Base64)
    }

    /**
     * Encrypts a plain text payload and returns a complete envelope.
     *
     * @param plainPayload - JSON string of the payload to encrypt
     * @return EncryptedEnvelope containing encryptedPayload, encryptedSessionKey, signature
     */
    public static EncryptedEnvelope encryptPayload(String plainPayload) {

        // Step 1: Generate a fresh AES-256 session key (32 random bytes)
        Blob sessionKey = Crypto.generateAesKey(256);

        // Step 2: AES-256 encrypt the payload using the session key
        // encryptWithManagedIV handles IV generation and prepends it to the ciphertext
        Blob encryptedPayloadBlob = Crypto.encryptWithManagedIV(
            'AES256',
            sessionKey,
            Blob.valueOf(plainPayload)
        );

        // Step 3: RSA sign the plain session key using OrgA_Signing_Cert (HSM)
        // signWithCertificate uses the certificate stored in Certificate and Key Management
        // This allows Org B to verify the envelope came from Org A
        Blob signature = Crypto.signWithCertificate(
            SIGN_ALGORITHM,
            sessionKey,
            SIGNING_CERT
        );

        // Step 4: Base64 encode the plain session key to send to Python for RSA encryption
        String plainSessionKeyB64 = EncodingUtil.base64Encode(sessionKey);

        // Step 5: Call Python middleware to RSA encrypt the session key with Org B public key
        String encryptedSessionKeyB64 = SessionKeyEncryptionService.encryptSessionKey(
            plainSessionKeyB64
        );

        // Step 6: Assemble and return the complete envelope
        EncryptedEnvelope envelope = new EncryptedEnvelope();
        envelope.encryptedPayload    = EncodingUtil.base64Encode(encryptedPayloadBlob);
        envelope.encryptedSessionKey = encryptedSessionKeyB64;
        envelope.signature           = EncodingUtil.base64Encode(signature);

        return envelope;
    }
}

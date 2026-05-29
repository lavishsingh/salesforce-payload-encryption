# salesforce-payload-encryption

End-to-end encrypted cross-org data sync between two Salesforce orgs using AES-256 payload encryption, RSA session key exchange via a Python middleware, JWT Bearer Token authentication, and an async Platform Event architecture.

---

## Overview

This project implements a secure pipeline that sends Account and Contact records from **Org A** to **Org B** with the following guarantees:

| Guarantee | Mechanism |
|---|---|
| Payload confidentiality | AES-256 (`encryptWithManagedIV`) — only the session key holder can read the payload |
| Session key confidentiality | RSA-OAEP-SHA256 — only Org B's private key can unwrap the AES key |
| Origin integrity | RSA-SHA256 signature (`signWithCertificate`) — proves payload came from Org A |
| Transport security | HTTPS/TLS on every hop |
| Authentication (Org A → Org B) | JWT Bearer Token Flow (RS256, 3-minute expiry) |
| Async decoupling | Platform Event + Queueable — Org B returns 202 immediately, decrypts async |

---

## Architecture

```
ORG A                         PYTHON MIDDLEWARE              ORG B
─────                         ────────────────              ─────
OrgAOutboundService           PythonAnywhere                SecureInboundAPI
  │                           Flask app                       │  returns 202
  ├─ OrgAEncryptionService                                   │
  │   ① generateAesKey(256)   POST /encrypt                  Encrypted_Payload__e
  │   ② encryptWithManagedIV  ──────────────────────►        (Platform Event)
  │   ③ signWithCertificate   ◄──────────────────────              │
  │   ④ base64(sessionKey)    encryptedSessionKey            EncryptedPayloadTrigger
  │                                                                │
  ├─ SessionKeyEncryptionService                            DecryptAndSyncQueueable
  │   calls /encrypt                                              │
  │                                                         OrgBDecryptionService
  └─ JWT Bearer Token Flow    POST /decrypt                       │
      POST to Org B ─────────────────────────────►          ① /decrypt → plainKey
      Authorization: Bearer   ◄─────────────────────        ② Crypto.verify (RSA-SHA256)
                                                             ③ decryptWithManagedIV
                                                             ④ upsert Account + Contact
```

---

## Repository Structure

```
force-app/main/default/
├── classes/
│   ├── OrgAEncryptionService.cls        # AES encrypt, RSA sign (Org A)
│   ├── OrgAOutboundService.cls          # Orchestrator: JWT + POST to Org B (Org A)
│   ├── SessionKeyEncryptionService.cls  # Calls Python /encrypt (Org A)
│   ├── IntegrationConfigService.cls     # Cached metadata reader (both orgs)
│   ├── SecureInboundAPI.cls             # REST endpoint, publishes platform event (Org B)
│   ├── OrgBDecryptionService.cls        # RSA-decrypt key, verify sig, AES-decrypt (Org B)
│   ├── SessionKeyDecryptionService.cls  # Calls Python /decrypt (Org B)
│   └── DecryptAndSyncQueueable.cls      # Async: decrypt + upsert Account/Contact (Org B)
├── triggers/
│   └── EncryptedPayloadTrigger.trigger  # Fires on Encrypted_Payload__e, enqueues job (Org B)
├── objects/
│   ├── Encrypted_Payload__e/            # Platform Event (LongTextArea fields for RSA payloads)
│   └── Encryption_Key__mdt/             # Custom Metadata Type for all config
├── customMetadata/                      # Metadata records (sensitive values are placeholders)
├── namedCredentials/                    # Named Credentials for Python middleware + Org B
└── remoteSiteSettings/                  # Allowlisted external URLs
```

The Python middleware lives in a separate repo: [sf-encryption-middleware](https://github.com/lavishsingh/sf-encryption-middleware)

---

## Prerequisites

- Salesforce CLI (`sf`) v2+
- Two Salesforce orgs (Developer Edition or scratch orgs)
- A PythonAnywhere account (free tier works)
- Python 3.9+ with `cryptography` and `flask` packages
- Node.js (for the `sf` CLI)

---

## Setup Guide

### 1 — Python Middleware (PythonAnywhere)

Clone [sf-encryption-middleware](https://github.com/lavishsingh/sf-encryption-middleware) and deploy it to PythonAnywhere.

**Generate an RSA key pair for Org B:**
```bash
# Generate private key
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out orgb_private_key.pem

# Extract certificate (self-signed, used as Org B's "public key" for encryption)
openssl req -new -x509 -key orgb_private_key.pem -out orgb_cert.pem -days 730 \
  -subj "/CN=OrgB_Encryption_Cert"
```

In your PythonAnywhere WSGI file set:
```python
import os
os.environ['ORG_B_PUBLIC_KEY'] = """-----BEGIN CERTIFICATE-----
<paste orgb_cert.pem content here>
-----END CERTIFICATE-----"""

os.environ['ORG_B_PRIVATE_KEY'] = """-----BEGIN PRIVATE KEY-----
<paste orgb_private_key.pem content here>
-----END PRIVATE KEY-----"""
```

Test both endpoints:
```bash
curl -X POST https://YOUR-USERNAME.pythonanywhere.com/encrypt \
  -H "Content-Type: application/json" \
  -d '{"sessionKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}'

curl -X POST https://YOUR-USERNAME.pythonanywhere.com/decrypt \
  -H "Content-Type: application/json" \
  -d '{"encryptedSessionKey":"<value from above>"}'
```

---

### 2 — Org A Setup

**a. Create a self-signed certificate** in Setup → Certificate and Key Management → Create Self-Signed Certificate. Name it exactly `OrgA_Signing_Cert`.

**b. Create a Connected App** in Org B (Setup → App Manager → New Connected App):
- Enable OAuth, select `Manage user data via APIs (api)` scope
- Enable JWT Bearer Token Flow, upload `OrgA_Signing_Cert` certificate
- Note the **Consumer Key**

**c. Pre-authorize the integration user** in Org B:
Setup → Connected Apps OAuth Usage → Manage Profiles → add the integration user's profile.

**d. Update Custom Metadata records** in Org A (Setup → Custom Metadata Types → Encryption_Key → Manage Records):

| DeveloperName | Key_Value__c |
|---|---|
| `Token_Endpoint` | `https://login.salesforce.com/services/oauth2/token` |
| `OrgB_Base_URL` | `https://YOUR-ORG-B-DOMAIN.my.salesforce.com` |
| `OrgB_Inbound_Path` | `/services/apexrest/secure/inbound/` |
| `OrgB_Consumer_Key` | Your Connected App Consumer Key |
| `OrgB_Subject` | The Org B username to impersonate |
| `OrgB_Signing_Cert` | `OrgA_Signing_Cert` |

**e. Update Named Credential** `Python_Encrypt_API` endpoint to `https://YOUR-USERNAME.pythonanywhere.com`.

**f. Add Remote Site Settings** for Org B's instance URL and `https://login.salesforce.com`.

**g. Deploy Org A components:**
```bash
sf project deploy start --target-org <OrgA-alias> \
  --source-dir force-app/main/default/classes/OrgAEncryptionService.cls \
  --source-dir force-app/main/default/classes/OrgAOutboundService.cls \
  --source-dir force-app/main/default/classes/SessionKeyEncryptionService.cls \
  --source-dir force-app/main/default/classes/IntegrationConfigService.cls \
  --source-dir force-app/main/default/customMetadata \
  --source-dir force-app/main/default/namedCredentials/Python_Encrypt_API.namedCredential-meta.xml \
  --source-dir force-app/main/default/objects/Encryption_Key__mdt
```

---

### 3 — Org B Setup

**a. Create the `Encrypted_Payload__e` Platform Event** by deploying the object definition.

**b. Update Custom Metadata records** in Org B:

| DeveloperName | Field | Value |
|---|---|---|
| `Python_Decrypt_NC` | `Key_Value__c` | `Python_Decrypt_API` (Named Credential API name) |
| `OrgA_Signing_Public_Key` | `Public_Key_PEM__c` | SPKI public key extracted from `OrgA_Signing_Cert` |

**To extract the SPKI public key from Org A's signing certificate:**

Export `OrgA_Signing_Cert` from Org A (Setup → Certificate and Key Management → Download Certificate), then run:
```bash
# Using Node.js
node -e "
const crypto = require('crypto');
const fs = require('fs');
const cert = new crypto.X509Certificate(fs.readFileSync('OrgA_Signing_Cert.crt'));
console.log(cert.publicKey.export({ type: 'spki', format: 'pem' }));
"
```

> **Important:** Salesforce `Crypto.verify` requires the **SPKI public key** (`-----BEGIN PUBLIC KEY-----`), NOT the full X.509 certificate. Passing the certificate DER bytes throws `System.SecurityException: Invalid Crypto Key`.

**c. Update Named Credential** `Python_Decrypt_API` endpoint to `https://YOUR-USERNAME.pythonanywhere.com`.

**d. Deploy Org B components:**
```bash
sf project deploy start --target-org <OrgB-alias> \
  --source-dir force-app/main/default/classes/SecureInboundAPI.cls \
  --source-dir force-app/main/default/classes/OrgBDecryptionService.cls \
  --source-dir force-app/main/default/classes/SessionKeyDecryptionService.cls \
  --source-dir force-app/main/default/classes/DecryptAndSyncQueueable.cls \
  --source-dir force-app/main/default/classes/IntegrationConfigService.cls \
  --source-dir force-app/main/default/triggers/EncryptedPayloadTrigger.trigger \
  --source-dir force-app/main/default/objects/Encrypted_Payload__e \
  --source-dir force-app/main/default/objects/Encryption_Key__mdt \
  --source-dir force-app/main/default/customMetadata/Encryption_Key.Python_Decrypt_NC.md-meta.xml \
  --source-dir force-app/main/default/customMetadata/Encryption_Key.OrgA_Signing_Public_Key.md-meta.xml
```

---

## Running an End-to-End Test

```apex
// Run in Org A — Anonymous Apex
Account testAcc = new Account(
    Name = 'Test Corp',
    Phone = '+1-555-0001',
    Website = 'https://test.example.com',
    Industry = 'Technology'
);
Contact testCon = new Contact(
    FirstName = 'Test',
    LastName = 'User',
    Email = 'test.user@test.example.com',
    Phone = '+1-555-0002',
    Title = 'Engineer'
);
OrgAOutboundService.sendAccountAndContact(testAcc, testCon);
```

Org B should return HTTP 202. Check the async job in Org B:
```apex
// Run in Org B — Anonymous Apex
List<AsyncApexJob> jobs = [
    SELECT Id, Status, ExtendedStatus, CreatedDate
    FROM AsyncApexJob
    WHERE JobType = 'Queueable'
    ORDER BY CreatedDate DESC
    LIMIT 3
];
for (AsyncApexJob j : jobs) {
    System.debug(j.Id + ' | ' + j.Status + ' | ' + j.ExtendedStatus);
}
```

Verify records in Org B:
```apex
System.debug([SELECT Id, Name, Phone FROM Account WHERE Name = 'Test Corp']);
System.debug([SELECT Id, Name, Email FROM Contact WHERE Email = 'test.user@test.example.com']);
```

---

## Encryption Flow — Step by Step

```
Org A
  1. Crypto.generateAesKey(256)              → 32-byte session key
  2. Crypto.encryptWithManagedIV(            → base64(IV + AES-ciphertext)
       'AES256', sessionKey, payloadBlob)
  3. Crypto.signWithCertificate(             → base64(RSA-SHA256 signature)
       'RSA-SHA256', sessionKey,               (signs raw 32-byte key blob)
       'OrgA_Signing_Cert')
  4. POST /encrypt {sessionKey: base64(key)} → Python RSA-OAEP encrypts with Org B cert
                                             ← {encryptedSessionKey: base64(RSA-ciphertext)}
  5. POST Org B REST endpoint:
     {
       encryptedPayload:    base64(IV+ciphertext),
       encryptedSessionKey: base64(RSA-ciphertext),
       signature:           base64(RSA-SHA256 of raw key)
     }
     Authorization: Bearer <JWT>

Org B
  6. SecureInboundAPI publishes Encrypted_Payload__e → returns 202
  7. Trigger enqueues DecryptAndSyncQueueable
  8. POST /decrypt {encryptedSessionKey}     → Python RSA-OAEP decrypts with Org B private key
                                             ← {sessionKey: base64(32 bytes)}
  9. EncodingUtil.base64Decode(sessionKey)   → 32-byte sessionKeyBlob
 10. Crypto.verify('RSA-SHA256',             → validates origin (true = came from Org A)
       sessionKeyBlob, signatureBlob,
       spkiPublicKeyBlob)
 11. Crypto.decryptWithManagedIV(            → plain JSON string
       'AES256', sessionKeyBlob,
       encryptedPayloadBlob)
 12. JSON.deserializeUntyped → upsert Account (by Name), upsert Contact (by Email)
```

---

## Common Issues

| Error | Cause | Fix |
|---|---|---|
| `Invalid Crypto Key` in async job | `Crypto.verify` received X.509 cert DER instead of SPKI DER | Extract public key with `openssl x509 -pubkey -noout` or Node.js `X509Certificate.publicKey.export({type:'spki'})` and store the `-----BEGIN PUBLIC KEY-----` PEM |
| `Python /decrypt returned HTTP 500: Invalid private key` | WSGI env var has a typo in the base64 key | Check for case errors in the pasted PEM — a single wrong character corrupts the key |
| `SignatureVerificationException` | Wrong public key stored for `OrgA_Signing_Public_Key`, or the signing cert in Org A changed | Re-export the cert and re-extract the SPKI public key |
| `JWT token exchange failed: HTTP 400` | Consumer Key, Subject, or Signing Cert name mismatch | Verify all three `Encryption_Key__mdt` values match the Connected App configuration in Org B |
| `Failed to reach Org B` | Missing Remote Site Setting or wrong `OrgB_Base_URL` | Add the Org B domain to Remote Site Settings in Org A |

---

## Security Notes

- The AES session key is ephemeral — generated fresh for every payload, never stored
- Org A's RSA private key never leaves Salesforce (managed by Certificate and Key Management HSM)
- Org B's RSA private key never leaves PythonAnywhere (set via environment variable, not in code)
- The Python middleware does not log or store any keys or payloads
- All `Encryption_Key__mdt` records use `<protected>false</protected>` — change to `true` in production to restrict visibility to the deploying namespace only

---

## Related Repository

**Python RSA Middleware:** [github.com/lavishsingh/sf-encryption-middleware](https://github.com/lavishsingh/sf-encryption-middleware)

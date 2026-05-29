public class DecryptAndSyncQueueable implements Queueable, Database.AllowsCallouts {

    private final String encryptedPayload;
    private final String encryptedSessionKey;
    private final String signature;

    public DecryptAndSyncQueueable(
        String encryptedPayload,
        String encryptedSessionKey,
        String signature
    ) {
        this.encryptedPayload    = encryptedPayload;
        this.encryptedSessionKey = encryptedSessionKey;
        this.signature           = signature;
    }

    public void execute(QueueableContext ctx) {
        // Decrypt: Python /decrypt → session key → signature verify → AES-256 decrypt
        String decryptedJson = OrgBDecryptionService.decrypt(
            encryptedPayload, encryptedSessionKey, signature
        );

        // Payload keys are lowercase: 'account' and 'contact'
        Map<String, Object> payload     = (Map<String, Object>) JSON.deserializeUntyped(decryptedJson);
        Map<String, Object> accountData = (Map<String, Object>) payload.get('account');
        Map<String, Object> contactData = (Map<String, Object>) payload.get('contact');

        if (accountData == null || contactData == null) {
            System.debug('DecryptAndSyncQueueable — Decrypted payload missing account or contact node');
            return;
        }

        // Upsert Account by Name
        String accountName = (String) accountData.get('Name');
        if (String.isBlank(accountName)) {
            System.debug('DecryptAndSyncQueueable — Account Name is blank in decrypted payload');
            return;
        }

        Account acc;
        List<Account> existingAccounts = [SELECT Id FROM Account WHERE Name = :accountName LIMIT 1];
        if (!existingAccounts.isEmpty()) {
            acc = existingAccounts[0];
        } else {
            acc = new Account();
        }
        acc.Name = accountName;
        if (accountData.containsKey('Phone'))    acc.Phone    = (String) accountData.get('Phone');
        if (accountData.containsKey('Website'))  acc.Website  = (String) accountData.get('Website');
        if (accountData.containsKey('Industry')) acc.Industry = (String) accountData.get('Industry');
        upsert acc;

        // Upsert Contact by Email
        String contactEmail = (String) contactData.get('Email');
        if (String.isBlank(contactEmail)) {
            System.debug('DecryptAndSyncQueueable — Contact Email is blank in decrypted payload');
            return;
        }

        Contact con;
        List<Contact> existingContacts = [SELECT Id FROM Contact WHERE Email = :contactEmail LIMIT 1];
        if (!existingContacts.isEmpty()) {
            con = existingContacts[0];
        } else {
            con = new Contact();
        }
        con.AccountId = acc.Id;
        con.LastName  = (String) contactData.get('LastName');
        if (contactData.containsKey('FirstName')) con.FirstName = (String) contactData.get('FirstName');
        con.Email = contactEmail;
        if (contactData.containsKey('Phone')) con.Phone = (String) contactData.get('Phone');
        if (contactData.containsKey('Title')) con.Title = (String) contactData.get('Title');
        upsert con;

        System.debug('DecryptAndSyncQueueable — Upserted Account ' + acc.Id + ' and Contact ' + con.Id);
    }
}

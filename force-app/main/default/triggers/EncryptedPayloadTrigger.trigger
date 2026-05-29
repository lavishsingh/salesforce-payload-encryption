trigger EncryptedPayloadTrigger on Encrypted_Payload__e (after insert) {
    for (Encrypted_Payload__e event : Trigger.new) {
        System.enqueueJob(new DecryptAndSyncQueueable(
            event.Encrypted_Payload__c,
            event.Encrypted_Session_Key__c,
            event.Signature__c
        ));
    }
}

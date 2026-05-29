public class IntegrationConfigService {

    @TestVisible
    private static Map<String, Encryption_Key__mdt> cache;

    private static Map<String, Encryption_Key__mdt> getCache() {
        if (cache == null) {
            cache = new Map<String, Encryption_Key__mdt>();
            for (Encryption_Key__mdt rec : [
                SELECT DeveloperName, Key_Value__c, Description__c
                FROM Encryption_Key__mdt
                WHERE Is_Active__c = true
            ]) {
                cache.put(rec.DeveloperName, rec);
            }
        }
        return cache;
    }

    public static String get(String developerName) {
        Encryption_Key__mdt rec = getCache().get(developerName);
        if (rec == null || String.isBlank(rec.Key_Value__c)) {
            throw new ConfigException('Encryption_Key__mdt record not found or empty: ' + developerName);
        }
        return rec.Key_Value__c;
    }

    public class ConfigException extends Exception {}
}

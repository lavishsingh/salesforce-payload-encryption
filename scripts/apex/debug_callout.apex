// Debug what authorization header gets sent to Org B
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:OrgB_JWT_Legacy/services/apexrest/secure/inbound/');
req.setMethod('GET');
req.setTimeout(30000);

System.debug('About to make callout via OrgB_JWT_Legacy');
Http http = new Http();
HttpResponse res;
try {
    res = http.send(req);
    System.debug('Response status: ' + res.getStatusCode());
    System.debug('Response body: ' + res.getBody());
} catch(Exception e) {
    System.debug('Exception: ' + e.getMessage());
    System.debug('Exception type: ' + e.getTypeName());
}

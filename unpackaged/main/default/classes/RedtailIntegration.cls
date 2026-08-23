public with sharing class RedtailIntegration {

    private static final String AMP_JOINER = '&';
    private static final String WILDCARD = '*';
    private static final String API_SEPARATOR = ':';

    @InvocableMethod(Label='Redtail Contact Search' Description='Searches Redtail for Contact Information')
    public static List<List<RedtailIntegration_Contact>> searchRedtail(List<Request> requests) {

        
        List<RedtailIntegration_Contact> contacts = new List<RedtailIntegration_Contact>();

        try {

            // Create the endpoint
            String endpoint = Redtail.CONTACT_ENDPOINT + 'search?';

            // Add the Parameters
            List<String> params = new List<String>();

            if(requests[0].lastName != WILDCARD) {
                params.add('last_name=' + requests[0].lastName);
            }

            if(requests[0].firstName != WILDCARD) {
                params.add('first_name=' + requests[0].firstName);
            }

            if(requests[0].taxId != WILDCARD) {
                params.add('tax_id=' + requests[0].taxId);
            }

            endpoint += String.join(params, AMP_JOINER);

            // Make the Callout
            HttpResponse response = new Http().send(prepareRequest(requests[0].apiKey, 
                                                                    requests[0].username, 
                                                                    requests[0].password, 
                                                                    endpoint));

            if(response.getStatusCode() == 200) {
            
                // Get the Response        
                Response parsedResponse = (Response)JSON.deserialize(response.getBody(), Response.class);
                
                // Compile the list of Contacts
                for (ContactRecord contactInfo : parsedResponse.contacts) {
                    RedtailIntegration_Contact thisContact = new RedtailIntegration_Contact();
                    thisContact.first_name = contactInfo.first_name;
                    thisContact.last_name = contactInfo.last_name;
                    thisContact.dob = contactInfo.dob != null ? Date.valueOf(contactInfo.dob) : null;
                    thisContact.tax_id = contactInfo.tax_id;
                    thisContact.id = contactInfo.id;
                    contacts.add(thisContact);
                }
            }
            else {
                System.debug('Error in Contact Search : ' + response.getStatusCode() + ' ' + response.getStatus());
            }
        }
        catch(Exception e) {
            System.debug(e.getStackTraceString());
            System.debug(e.getMessage());
        }
        return new List<List<RedtailIntegration_Contact>> { contacts };
    }

    private static HttpRequest prepareRequest(String apiKey, String username, String password, String endpoint) {
        
        // Make the Callout
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Redtail_Production' + endpoint);
        request.setMethod('GET');

        // Authentication String
        String authenticationString = apiKey + API_SEPARATOR + username + API_SEPARATOR + password;

        request.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(authenticationString)));
        return request;
    }

    // Request variables for the flow
    public class Request {
        @InvocableVariable(Required=true)
        public String apiKey;
        @InvocableVariable(Required=true)
        public String username;
        @InvocableVariable(Required=true)
        public String password;
        @InvocableVariable(Required=true)
        public String lastName;
        @InvocableVariable(Required=true)
        public String firstName;
        @InvocableVariable(Required=true)
        public String taxId;
    }

    // Response to the flow
    public class Response {
        @AuraEnabled public List<ContactRecord> contacts;
    }

    public class ContactRecord {
        @AuraEnabled public String first_name;
        @AuraEnabled public String last_name;
        @AuraEnabled public String tax_id;
        @AuraEnabled public String dob;
        @AuraEnabled public String id;
    }
}
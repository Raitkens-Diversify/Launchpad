public with sharing class RedtailIntegrationGetContact {

    private static final String EMPLOYED_STATUS = 'Employed';
    private static final String EMPTY_STRING = '';
    private static final String API_SEPARATOR = ':';

    @InvocableMethod(Label='Redtail Contact Get Contact' Description='Get Contact Information from Redtail')
    public static List<List<RedtailIntegration_ContactFull>> getContact(List<Request> requests) {

        List<RedtailIntegration_ContactFull> contacts = new List<RedtailIntegration_ContactFull>();

        try {

            // Set the Endpoint
            String endpoint = Redtail.CONTACT_ENDPOINT + requests[0].contactId;

            // Get the Response
            HttpResponse response = new Http().send(prepareRequest(requests[0].apiKey, 
                                                                    requests[0].username, 
                                                                    requests[0].password, 
                                                                    endpoint));

            if(response.getStatusCode() == 200) {

                String responseBody = response.getBody();
                // Update numberValue to number
                responseBody = responseBody.replaceAll(Redtail.REDTAIL_NUMBER, Redtail.SF_NUMBER);
                                                            
                // Get the Contact info from Redtail
                Redtail.ContactWrapper contact = (Redtail.ContactWrapper)JSON.deserialize(responseBody, Redtail.ContactWrapper.class);
                
                Redtail.ContactData contactData = contact.contact;

                RedtailIntegration_ContactFull contactFull = prepareFullContact(contactData);

                contacts.add(contactFull);
            }
            else if(response.getStatusCode() == 404) {
                System.debug('Contact not found : ' + response.getStatusCode() + ' ' + response.getStatus());
            }
            else {
                System.debug('Error in Get Contact By Id : ' + response.getStatusCode() + ' ' + response.getStatus());
            }
        }
        catch(Exception e) {
            System.debug(e.getMessage());
            System.debug(e.getStackTraceString());
        }

        // Return the Contact data
        return new List<List<RedtailIntegration_ContactFull>> { contacts };
    }

    private static HttpRequest prepareRequest(String apiKey, String username, String password, String endpoint) {
        
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Redtail_Production' + endpoint);
        request.setHeader('include','addresses,phones,emails');
        request.setMethod('GET');

        // Authentication String
        String authenticationString = apiKey + API_SEPARATOR + username + API_SEPARATOR + password;

        request.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(authenticationString)));
        return request;
    }

    private static RedtailIntegration_ContactFull prepareFullContact(Redtail.ContactData contactData) {
        // Prepare the Full Contact to return
        System.debug('contactData: ' + contactData);
        RedtailIntegration_ContactFull contactFull = new RedtailIntegration_ContactFull();
        contactFull.firstName = contactData.first_name;
        contactFull.middleName = contactData.middle_name;
        contactFull.lastName = contactData.last_name;

        Boolean foundPhysicalAddress = false;
        Boolean foundMailingAddress = false;

        if(contactData.addresses != null) {
            for(Redtail.Address address : contactData.addresses) {
                if(address.address_type == 1) {

                    // Physical Address if type is 1
                    contactFull.physicalStreet = getPhysicalAddress(address.street_address, address.secondary_address);
                    contactFull.physicalCity = address.city;
                    contactFull.physicalState = address.state;
                    contactFull.physicalZip = address.zip;
                    
                    foundPhysicalAddress = true;
                }
                else if(address.address_type == 3) {
                    // Mailing Address if type is 3
                    contactFull.mailingStreet = getPhysicalAddress(address.street_address, address.secondary_address);
                    contactFull.mailingCity = address.city;
                    contactFull.mailingState = address.state;
                    contactFull.mailingZip = address.zip;

                    foundMailingAddress = true;
                }

                // If both addresses found, stop the loop
                if(foundPhysicalAddress && foundMailingAddress) {
                    break;
                }
            }
        }

        contactFull.taxId = contactData.tax_id;

        // Get the Primary Email Address
        if(contactData.emails != null) {
            for(Redtail.Email emailAddress : contactData.emails) {
                if(emailAddress.is_primary == true) {
                    contactFull.emailAddress = emailAddress.address;
                    break;
                }
            }
        }

        // Get the Primary Phone
        if(contactData.phones != null) {
            for(Redtail.Phone phone : contactData.phones) {
                if(phone.is_primary == true) {
                    contactFull.phoneNumber = phone.numberValue;
                    break;
                }
            }
        }

        contactFull.dob = contactData.dob != null ? Date.valueOf(contactData.dob) : null;
        contactFull.employmentStatus = contactData.job_title != null ? EMPLOYED_STATUS : null;
        contactFull.employer = contactData.employer;
        contactFull.occupation = contactData.job_title;

        return contactFull;
    }

    @TestVisible
    private static String getPhysicalAddress(String streetAddress, String secondaryAddress) {
        String address = streetAddress;

        if(address == null) {
            address = secondaryAddress;
        }
        else if(String.isNotEmpty(secondaryAddress)) {
            address += ' ' + secondaryAddress;
        }

        return address;
    }

    public class Request {
        @InvocableVariable(Required=true)
        public String apiKey;
        @InvocableVariable(Required=true)
        public String username;
        @InvocableVariable(Required=true)
        public String password;
        @InvocableVariable(Required=true)
        public String contactId;
    }
}
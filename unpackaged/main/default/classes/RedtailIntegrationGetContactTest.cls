@isTest
private class RedtailIntegrationGetContactTest {

    @isTest
    static void testGetContact() {
        
        Redtail.ContactWrapper contactWrapper = getContactWrapper();

        // Create JSON data
        String contactRecordJSON = JSON.serialize(contactWrapper);

        contactRecordJSON = contactRecordJSON.replaceAll('numberValue', 'number');

        // Create the Mocks
        RedtailIntegrationMockCallout.MockResponse contactsRecordResponse = new RedtailIntegrationMockCallout.MockResponse(contactRecordJSON, 'Success', 200);

        Test.setMock(HttpCalloutMock.class, new RedtailIntegrationMockCallout(new List<RedtailIntegrationMockCallout.MockResponse>{contactsRecordResponse}));

        // Create a Request
        RedtailIntegrationGetContact.Request request = new RedtailIntegrationGetContact.Request();
        request.apiKey = '';
        request.password = '3535345';
        request.username = '324234';
        request.contactId = '34535';

        List<RedtailIntegrationGetContact.Request> requests = new List<RedtailIntegrationGetContact.Request>();
        requests.add(request);

        List<List<RedtailIntegration_ContactFull>> contacts;

        Test.startTest();

            // Get the Contacts
            contacts = RedtailIntegrationGetContact.getContact(requests);

        Test.stopTest();

        Assert.areEqual(1, contacts.size(), 'There should be one contact');
        Assert.areEqual(1, contacts[0].size(), 'There should be one contact');

        // Make sure the values are set correctly
        RedtailIntegration_ContactFull fullContact = contacts[0][0];
        Assert.areEqual('Margaret', fullContact.firstName, 'The values should match.');
        Assert.areEqual('Smith', fullContact.lastName, 'The values should match.');
        Assert.areEqual('1234 Main St.', fullContact.physicalStreet, 'The values should match.');
        Assert.areEqual('Sacramento', fullContact.physicalCity, 'The values should match.');
        Assert.areEqual('CA', fullContact.physicalState, 'The values should match.');
        Assert.areEqual('99320', fullContact.physicalZip, 'The values should match.');
        Assert.areEqual('123 Main St.', fullContact.mailingStreet, 'The values should match.');
        Assert.areEqual('Lafayette', fullContact.mailingCity, 'The values should match.');
        Assert.areEqual('LA', fullContact.mailingState, 'The values should match.');
        Assert.areEqual('70508', fullContact.mailingZip, 'The values should match.');
        Assert.areEqual('123-45-6789', fullContact.taxId, 'The values should match.');
        Assert.areEqual('minvestor21@yahoo.com', fullContact.emailAddress, 'The values should match.');
        Assert.areEqual('5559815634', fullContact.phoneNumber, 'The values should match.');
        Assert.areEqual(Date.newInstance(1983,04,12), fullContact.dob, 'The values should match.');
        Assert.areEqual('Employed', fullContact.employmentStatus, 'The values should match.');
        Assert.areEqual('Investor & Investor', fullContact.employer, 'The values should match.');
        Assert.areEqual('Investor', fullContact.occupation, 'The values should match.');
    }

    @isTest
    static void testGetContactEmpty() {
        
        Redtail.ContactWrapper contactWrapper = new Redtail.ContactWrapper();

        // Create JSON data
        String contactRecordJSON = JSON.serialize(contactWrapper);

        contactRecordJSON = contactRecordJSON.replaceAll('numberValue', 'number');

        // Create the Mocks
        RedtailIntegrationMockCallout.MockResponse contactsRecordResponse = new RedtailIntegrationMockCallout.MockResponse(contactRecordJSON, 'Success', 404);

        Test.setMock(HttpCalloutMock.class, new RedtailIntegrationMockCallout(new List<RedtailIntegrationMockCallout.MockResponse>{contactsRecordResponse}));

        // Create a Request
        RedtailIntegrationGetContact.Request request = new RedtailIntegrationGetContact.Request();
        request.apiKey = '';
        request.password = '3535345';
        request.username = '324234';
        request.contactId = '34535';

        List<RedtailIntegrationGetContact.Request> requests = new List<RedtailIntegrationGetContact.Request>();
        requests.add(request);

        List<List<RedtailIntegration_ContactFull>> contacts;

        Test.startTest();

            // Get the Contacts
            contacts = RedtailIntegrationGetContact.getContact(requests);

        Test.stopTest();

        Assert.areEqual(0, contacts[0].size(), 'There should be no contacts returned.');
    }

    @IsTest
    static void testGetPhyscialAddressFull() {
        String streetAddress = '111 Main St.';
        String secondaryAddress = '1234';

        String address;

        Test.startTest();

            address = RedtailIntegrationGetContact.getPhysicalAddress(streetAddress, secondaryAddress);

        Test.stopTest();

        // The address should contain the Street Address and Secondary Address
        Assert.areEqual('111 Main St. 1234', address);
    }

    @IsTest
    static void testGetPhyscialAddressStreetOnly() {
        String streetAddress = '111 Main St.';
        String secondaryAddress = null;

        String address;

        Test.startTest();

            address = RedtailIntegrationGetContact.getPhysicalAddress(streetAddress, secondaryAddress);

        Test.stopTest();

        // The address should contain the Street Address
        Assert.areEqual('111 Main St.', address);
    }

    @IsTest
    static void testGetPhyscialAddressSecondaryOnly() {
        String streetAddress = null;
        String secondaryAddress = '1234';

        String address;

        Test.startTest();

            address = RedtailIntegrationGetContact.getPhysicalAddress(streetAddress, secondaryAddress);

        Test.stopTest();

        // The address should contain the Secondary Address
        Assert.areEqual('1234', address);
    }

    private static Redtail.ContactWrapper getContactWrapper() {
        Redtail.ContactWrapper contactWrapper = new Redtail.ContactWrapper();
        contactWrapper.contact = new Redtail.ContactData();

        contactWrapper.contact.id = '2';
        contactWrapper.contact.first_name = 'Margaret';
        contactWrapper.contact.middle_name = '';
        contactWrapper.contact.last_name = 'Smith';
        contactWrapper.contact.full_name = 'Margaret Smith';
        contactWrapper.contact.dob = '1983-04-12';
        contactWrapper.contact.employer = 'Investor & Investor';
        contactWrapper.contact.employer_id = 65340;
        contactWrapper.contact.designation = '';
        contactWrapper.contact.tax_id = '123-45-6789';
        contactWrapper.contact.job_title = 'Investor';

        contactWrapper.contact.important_information = new Redtail.ImportantInformation();
        contactWrapper.contact.important_information.id = 1;
        contactWrapper.contact.important_information.content = '<b>She prefers to be called Mary.</b><br><b><i>Do not call after 7:00PM</i></b><br><br>';
        contactWrapper.contact.important_information.created_at = '2015-01-07T01:33:43.000Z';
        contactWrapper.contact.important_information.updated_at = '2015-01-07T02:42:39.000Z';

        contactWrapper.contact.addresses = new List<Redtail.Address>();
        Redtail.Address address = new Redtail.Address();
        address.id = 2;
        address.addressable_id = 1;
        address.addressable_type = 'Crm::Contact';
        address.street_address = '1234 Main St.';
        address.secondary_address = '';
        address.city = 'Sacramento';
        address.state = 'CA';
        address.zip = '99320';
        address.country = 'US';
        address.address_type = 1;
        address.description = '';
        address.is_primary = true;
        address.is_preferred = false;
        address.deleted = false;
        address.created_at = '2015-01-07T03:44:59.000Z';
        address.updated_at = '2015-01-07T03:48:04.000Z';
        contactWrapper.contact.addresses.add(address);
        address = new Redtail.Address();
        address.id = 2;
        address.addressable_id = 1;
        address.addressable_type = 'Crm::Contact';
        address.street_address = '123 Main St.';
        address.secondary_address = '';
        address.city = 'Lafayette';
        address.state = 'LA';
        address.zip = '70508';
        address.country = 'US';
        address.address_type = 3;
        address.description = '';
        address.is_primary = true;
        address.is_preferred = false;
        address.deleted = false;
        address.created_at = '2015-01-07T03:44:59.000Z';
        address.updated_at = '2015-01-07T03:48:04.000Z';
        contactWrapper.contact.addresses.add(address);

        contactWrapper.contact.phones = new List<Redtail.Phone>();
        Redtail.Phone phone = new Redtail.Phone();
        phone.id = 5;
        phone.numberValue = '5559815634';
        phone.extension = '';
        phone.is_primary = true;
        phone.phone_type = 1;
        phone.phone_type_description = 'Home';
        phone.description = '';
        phone.deleted = false;
        phone.created_at = '2015-01-07T03:40:32.000Z';
        phone.updated_at = '2015-01-07T03:40:32.000Z';
        contactWrapper.contact.phones.add(phone);

        contactWrapper.contact.emails = new List<Redtail.Email>();
        Redtail.Email email = new Redtail.Email();
        email.id = 5;
        email.emailable_id = 1;
        email.emailable_type = 'Crm::Contact';
        email.address = 'minvestor21@yahoo.com';
        email.email_type = 3;
        email.email_type_description = 'Other';
        email.custom_type_title = 'Personal Email';
        email.description = '';
        email.is_primary = true;
        email.is_preferred = false;
        email.deleted = false;
        email.created_at = '2015-01-07T03:42:22.000Z';
        email.updated_at = '2015-01-07T03:42:22.000Z';
        contactWrapper.contact.emails.add(email);

        return contactWrapper;
    }
}
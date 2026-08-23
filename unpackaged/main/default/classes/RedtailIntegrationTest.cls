@isTest
private class RedtailIntegrationTest {

    @isTest
    static void testSearchRedtail() {
        RedtailIntegration.Response response = new RedtailIntegration.Response();
        response.contacts = new List<RedtailIntegration.ContactRecord>();

        // Setup the Contact Record
        RedtailIntegration.ContactRecord contactRecord = new RedtailIntegration.ContactRecord();
        contactRecord.first_name = 'Michael';
        contactRecord.last_name = 'Kenner';
        contactRecord.tax_id = '1234567890';
        contactRecord.dob = '2010-02-02';
        contactRecord.id = '1';

        response.contacts.add(contactRecord);

        String contactRecordsJSON = JSON.serialize(response);

        // Create the Mocks
        RedtailIntegrationMockCallout.MockResponse contactsRecordResponse = new RedtailIntegrationMockCallout.MockResponse(contactRecordsJSON, 'Success', 200);

        Test.setMock(HttpCalloutMock.class, new RedtailIntegrationMockCallout(new List<RedtailIntegrationMockCallout.MockResponse>{contactsRecordResponse}));

        // Create the Request
        RedtailIntegration.Request request = new RedtailIntegration.Request();
        request.apiKey = '';
        request.firstname = 'Michael';
        request.lastName = 'Kenner';
        request.taxId = '1234567890';
        request.password = '3535345';
        request.username = '324234';

        List<RedtailIntegration.Request> requests = new List<RedtailIntegration.Request>();
        requests.add(request);

        List<List<RedtailIntegration_Contact>> contacts;

        Test.startTest();

            // Search for the records
            contacts = RedtailIntegration.searchRedtail(requests);

        Test.stopTest();

        // Test that the values are set correctly
        Assert.areEqual(1, contacts.size(), 'There should be 1 contact.');
        Assert.areEqual('Michael', contacts[0][0].first_name, 'The values should match.');
        Assert.areEqual('Kenner', contacts[0][0].last_name, 'The values should match.');
        Assert.areEqual('1234567890', contacts[0][0].tax_id, 'The values should match.');
        Assert.areEqual(Date.newInstance(2010, 02, 02), contacts[0][0].dob, 'The values should match.');
        Assert.areEqual('1', contacts[0][0].id, 'The values should match.');
    }

    @isTest
    static void testSearchRedtailNoContacts() {
        // Mock an empty response
        RedtailIntegration.Response response = new RedtailIntegration.Response();
        response.contacts = new List<RedtailIntegration.ContactRecord>();
        String emptyContactsJSON = JSON.serialize(response);

        // Setup mock response
        RedtailIntegrationMockCallout.MockResponse mockResponse = new RedtailIntegrationMockCallout.MockResponse(emptyContactsJSON, 'Success', 200);
        Test.setMock(HttpCalloutMock.class, new RedtailIntegrationMockCallout(new List<RedtailIntegrationMockCallout.MockResponse>{mockResponse}));

        // Create the Request
        RedtailIntegration.Request request = new RedtailIntegration.Request();
        request.apiKey = '';
        request.firstName = 'Nonexistent';
        request.lastName = 'User';
        request.taxId = '0000000000';
        request.password = 'password';
        request.username = 'username';

        List<RedtailIntegration.Request> requests = new List<RedtailIntegration.Request>();
        requests.add(request);

        List<List<RedtailIntegration_Contact>> contacts;

        Test.startTest();

            contacts = RedtailIntegration.searchRedtail(requests);

        Test.stopTest();

        // Assert that no contacts are returned
        Assert.areEqual(0, contacts[0].size(), 'There should be no contacts.');
    }

    @isTest
    static void testSearchRedtailPartialInformation() {
        // Setup the Contact Record
        RedtailIntegration.ContactRecord contactRecord = new RedtailIntegration.ContactRecord();
        contactRecord.first_name = 'John';
        contactRecord.last_name = 'Doe';
        contactRecord.tax_id = '9876543210';
        contactRecord.dob = '1990-01-01';
        contactRecord.id = '2';

        RedtailIntegration.Response response = new RedtailIntegration.Response();
        response.contacts = new List<RedtailIntegration.ContactRecord>{contactRecord};
        String contactRecordsJSON = JSON.serialize(response);

        // Setup mock response
        RedtailIntegrationMockCallout.MockResponse mockResponse = new RedtailIntegrationMockCallout.MockResponse(contactRecordsJSON, 'Success', 200);
        Test.setMock(HttpCalloutMock.class, new RedtailIntegrationMockCallout(new List<RedtailIntegrationMockCallout.MockResponse>{mockResponse}));

        // Create the Request
        RedtailIntegration.Request request = new RedtailIntegration.Request();
        request.apiKey = '';
        request.firstName = '*'; // Wildcard
        request.lastName = 'Doe';
        request.taxId = '*'; // Wildcard
        request.password = 'password';
        request.username = 'username';

        List<RedtailIntegration.Request> requests = new List<RedtailIntegration.Request>();
        requests.add(request);

        List<List<RedtailIntegration_Contact>> contacts;

        Test.startTest();

            contacts = RedtailIntegration.searchRedtail(requests);

        Test.stopTest();

        // Test that the values are set correctly
        Assert.areEqual(1, contacts.size(), 'There should be 1 contact.');
        Assert.areEqual('John', contacts[0][0].first_name, 'The values should match.');
        Assert.areEqual('Doe', contacts[0][0].last_name, 'The values should match.');
        Assert.areEqual('9876543210', contacts[0][0].tax_id, 'The values should match.');
        Assert.areEqual(Date.newInstance(1990, 01, 01), contacts[0][0].dob, 'The values should match.');
        Assert.areEqual('2', contacts[0][0].id, 'The values should match.');
    }

    @isTest
    static void testSearchRedtailErrorResponse() {
        // Setup mock response with an error
        RedtailIntegrationMockCallout.MockResponse mockResponse = new RedtailIntegrationMockCallout.MockResponse('', 'Error', 500);
        Test.setMock(HttpCalloutMock.class, new RedtailIntegrationMockCallout(new List<RedtailIntegrationMockCallout.MockResponse>{mockResponse}));

        // Create the Request
        RedtailIntegration.Request request = new RedtailIntegration.Request();
        request.apiKey = '';
        request.firstName = 'Michael';
        request.lastName = 'Kenner';
        request.taxId = '1234567890';
        request.password = 'password';
        request.username = 'username';

        List<RedtailIntegration.Request> requests = new List<RedtailIntegration.Request>();
        requests.add(request);

        List<List<RedtailIntegration_Contact>> contacts;

        Test.startTest();

            contacts = RedtailIntegration.searchRedtail(requests);

        Test.stopTest();

        // Assert that no contacts are returned
        Assert.areEqual(0, contacts[0].size(), 'There should be no contacts due to error.');
    }
}
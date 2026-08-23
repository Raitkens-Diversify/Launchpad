@isTest
public with sharing class RedtailIntegrationMockCallout implements HttpCalloutMock {
    List<MockResponse> responses;

    Integer currentResponse = 0;

    public RedtailIntegrationMockCallout(List<MockResponse> responses) {
        this.responses = responses;
    }
    
    public HTTPResponse respond(HTTPRequest req) {

        currentResponse += 1;

        MockResponse response = responses[currentResponse - 1];
        
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody(response.body);
        res.setStatusCode(response.statusCode);
        res.setStatus(response.status);
        return res;
    }

    public class MockResponse {
        String body;
        String status;
        Integer statusCode;

        public MockResponse(String body, String status, Integer statusCode) {
            this.body = body;
            this.status = status;
            this.statusCode = statusCode;
        }
    }
}
public class ZoomContactNotification {

    // 1. Define the input variables the Flow will send to Apex
    public class FlowInput {
        @InvocableVariable(label='Zoom Contact Email' description='The email address of the Zoom user/contact' required=true)
        public String contactEmail;

        @InvocableVariable(label='Message Text' description='The notification message to send' required=true)
        public String messageText;
    }

    // 2. The method that Flow actually calls
    @InvocableMethod(label='Send Zoom Message to Contact' description='Sends a direct message to a Zoom contact via OAuth 2.0')
    public static void sendMessagesFromFlow(List<FlowInput> requests) {
        
        // Convert the list of Flow inputs into a JSON string. 
        // We do this because @future methods cannot accept complex Objects or Lists of Objects.
        String jsonRequests = JSON.serialize(requests);
        
        // Hand off to the asynchronous callout method
        sendAsyncZoomMessage(jsonRequests);
    }

    // 3. The asynchronous method that makes the API callout to Zoom
    @future(callout=true)
    private static void sendAsyncZoomMessage(String jsonRequests) {
        
        // Convert the JSON string back into our list of inputs
        List<FlowInput> requests = (List<FlowInput>) JSON.deserialize(jsonRequests, List<FlowInput>.class);
        
        Http http = new Http();
        
        // Loop through each request from the Flow and send the message
        for (FlowInput req : requests) {
            try {
                HttpRequest request = new HttpRequest();
                
                // Using the Named Credential
                request.setEndpoint('callout:Zoom/v2/chat/users/me/messages');
                request.setMethod('POST');
                request.setHeader('Content-Type', 'application/json');
                
                // Construct the JSON payload for a direct contact
                Map<String, Object> payload = new Map<String, Object>();
                payload.put('to_contact', req.contactEmail); 
                payload.put('message', req.messageText);
                
                request.setBody(JSON.serialize(payload));
                
                // Send the callout
                HttpResponse response = http.send(request);
                
                // Log any failures for debugging
                if (response.getStatusCode() != 201 && response.getStatusCode() != 200) {
                    System.debug('Failed to send Zoom message to ' + req.contactEmail + 
                                 '. Status: ' + response.getStatusCode() + 
                                 ' Body: ' + response.getBody());
                } else {
                    System.debug('Message successfully sent to ' + req.contactEmail);
                }
            } catch (Exception e) {
                System.debug('Apex Callout Error: ' + e.getMessage());
            }
        }
    }
}
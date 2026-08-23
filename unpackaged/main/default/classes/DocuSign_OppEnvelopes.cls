public class DocuSign_OppEnvelopes{
    
    @AuraEnabled
    @Future(callout=true)
    public static void sendOppEnvelopes(String oppId){
        
        Opportunity opp = [SELECT Id, AccountId, OwnerId, Owner.Name, Owner.Email FROM Opportunity WHERE Id =: oppId];
        
        List<DocuSign_Document__c> docsForPrimaryOwnerOnly = [SELECT Id, Name, Template_Type__c, Template_Type__r.Name, Template_Type__r.dfsle__DocuSignId__c FROM DocuSign_Document__c WHERE Opportunity__c = :oppId AND
                                                              Send_to_Primary_Owner__c = true AND Send_to_Joint_Owner__c = false];
        List<DocuSign_Document__c> docsForJointOwnerOnly = [SELECT Id, Name, Template_Type__c, Template_Type__r.Name, Template_Type__r.dfsle__DocuSignId__c FROM DocuSign_Document__c WHERE Opportunity__c = :oppId AND
                                                            Send_to_Primary_Owner__c = false AND Send_to_Joint_Owner__c	= true];
        List<DocuSign_Document__c> docsForBothOwners = [SELECT Id, Name, Template_Type__c, Template_Type__r.Name, Template_Type__r.dfsle__DocuSignId__c FROM DocuSign_Document__c WHERE Opportunity__c = :oppId AND
                                                        Send_to_Primary_Owner__c = true AND Send_to_Joint_Owner__c = true];
        
        //Get the clients by AccountContactRelation(s)
        List<AccountContactRelation> clients = [SELECT ContactId, Contact.Name, Contact.Email, Account.Name, FinServ__Primary__c
                                                FROM AccountContactRelation WHERE AccountId = :opp.AccountId
                                                AND Roles INCLUDES ('Client') Order by FinServ__Primary__c desc LIMIT 2];
        
        dfsle.Recipient primaryRecipient;
        dfsle.Recipient jointRecipient;
        dfsle.Recipient ownerRecipient;
        //use the Recipient.fromSource method to create the Recipients
        if(!clients.isEmpty()){
            primaryRecipient = dfsle.Recipient.fromSource(
                clients[0].Contact.Name, // Recipient name
                clients[0].Contact.Email, // Recipient email
                null, //Optional phone number
                'Primary Owner', //Role Name. Specify the exact role name from template
                new dfsle.Entity(clients[0].ContactId)); //source object for the Recipient
        }
        
        if(!clients.isEmpty() && clients.size() == 2){
            jointRecipient = dfsle.Recipient.fromSource(
                clients[1].Contact.Name, // Recipient name
                clients[1].Contact.Email, // Recipient email
                null, //Optional phone number
                'Joint Owner', //Role Name. Specify the exact role name from template
                new dfsle.Entity(clients[1].ContactId)); //source object for the Recipient
            
        }
        
        ownerRecipient = dfsle.Recipient.fromSource(
            opp.Owner.Name, // Recipient name
            opp.Owner.Email,
            null, //Optional phone number
            'Advisor', //Role Name. Specify the exact role name from template
            new dfsle.Entity(opp.OwnerId)); //source object for the Recipient        
        
        //Custom Fields
        dfsle.CustomField oppCustomField = new dfsle.CustomField(
            'text', //type of field, either text or list
            '##SFOpportunity', //name of the Custom Field
            oppId, //value of the Custom Field
            null, //list items for list type
            true, //required 
            true //show
        );
        dfsle.CustomField accCustomField = new dfsle.CustomField(
            'text', //type of field, either text or list
            '##SFAccount', //name of the Custom Field
            opp.AccountId, //value of the Custom Field
            null, //list items for list type
            true, //required 
            true //show
        );
        dfsle.CustomField primaryACRCustomField = new dfsle.CustomField(
            'text', //type of field, either text or list
            '##SFAccountContactRelation', //name of the Custom Field
            clients.size()> 0 ? clients[0].Id : null, //value of the Custom Field
            null, //list items for list type
            false, //required 
            true //show
        );
        
        // Build a list of envelopes to send
        List<dfsle.Envelope> envelopes = new List<dfsle.Envelope>();
                
        if(!docsForBothOwners.isEmpty() && primaryRecipient != null && jointRecipient != null){
            dfsle.Envelope ev1 = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(opp.AccountId));
            List<dfsle.Document> docs = new List<dfsle.Document>();
            for(DocuSign_Document__c doc : docsForBothOwners){
                dfsle.UUID myTemplateId = dfsle.UUID.parse(doc.Template_Type__r.dfsle__DocuSignId__c);
                dfsle.Document myDocument = dfsle.Document.fromTemplate(
                    myTemplateId,
                    doc.Template_Type__r.Name);                 
                docs.add(myDocument);
            }

            addManualDocs(docs);
            //add document to the Envelope
            ev1 = ev1.withDocuments(docs);
            ev1 = ev1.withCustomFields(new List<dfsle.CustomField> {oppCustomField, accCustomField});
            ev1 = ev1.withRecipients(new List<dfsle.Recipient> { primaryRecipient, jointRecipient, ownerRecipient});
            envelopes.add(ev1);
        }
        
        if(!docsForPrimaryOwnerOnly.isEmpty() && primaryRecipient != null){
            dfsle.Envelope ev2 = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(opp.AccountId));
            List<dfsle.Document> docs = new List<dfsle.Document>();
            for(DocuSign_Document__c doc : docsForPrimaryOwnerOnly){
                dfsle.UUID myTemplateId = dfsle.UUID.parse(doc.Template_Type__r.dfsle__DocuSignId__c);
                dfsle.Document myDocument = dfsle.Document.fromTemplate(
                    myTemplateId,
                    doc.Template_Type__r.Name);                 
                docs.add(myDocument);
            }

            addManualDocs(docs);

            //add document to the Envelope
            ev2 = ev2.withDocuments(docs);
            ev2 = ev2.withCustomFields(new List<dfsle.CustomField> {oppCustomField, accCustomField});
            ev2 = ev2.withRecipients(new List<dfsle.Recipient> {primaryRecipient, ownerRecipient.withRoutingOrder(3)});
            envelopes.add(ev2);
        }
        
        if(!docsForJointOwnerOnly.isEmpty() && jointRecipient != null){
            dfsle.Envelope ev3 = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(opp.AccountId));
            List<dfsle.Document> docs = new List<dfsle.Document>();
            for(DocuSign_Document__c doc : docsForJointOwnerOnly){
                dfsle.UUID myTemplateId = dfsle.UUID.parse(doc.Template_Type__r.dfsle__DocuSignId__c);
                dfsle.Document myDocument = dfsle.Document.fromTemplate(
                    myTemplateId,
                    doc.Template_Type__r.Name);                 
                docs.add(myDocument);
            }

            addManualDocs(docs);
            //add document to the Envelope
            ev3 = ev3.withDocuments(docs);
            ev3 = ev3.withRecipients(new List<dfsle.Recipient> {jointRecipient.withRoutingOrder(2), ownerRecipient.withRoutingOrder(3)});
            ev3 = ev3.withCustomFields(new List<dfsle.CustomField> {oppCustomField, accCustomField, primaryACRCustomField});
            envelopes.add(ev3);
        }
        
        List<dfsle.Envelope> savedEnvelopes = new List<dfsle.Envelope>();
        List<dfsle.Envelope> sentEnvelopes = new List<dfsle.Envelope>();
        
        if(!envelopes.isEmpty()){
            for (dfsle.Envelope envelope : dfsle.EnvelopeService.sendEnvelopes(envelopes)) {
                if (envelope.error == null) {
                    // Envelope sent successfully
                    sentEnvelopes.add(envelope);
                    
                } else {
                    // Handle send error
                    System.debug('Envelope error: ' + envelope.error);
                } 
            }
        }
        //Save sent envelopes
        if(!sentEnvelopes.isEmpty()){
            savedEnvelopes = dfsle.EnvelopeService.saveSentEnvelopes(sentEnvelopes);
        }
    }
    
    public static void addManualDocs(List<dfsle.Document> docs) {
        if(!Test.isRunningTest()) {
        	dfsle.Envelope manualEnvelope = dfsle.EnvelopeService.getEnvelope('a2G8X00000G8kz2UAB');

            docs.addAll(manualEnvelope.documents);
        }
    }
}
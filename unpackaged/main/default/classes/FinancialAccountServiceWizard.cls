public with sharing class FinancialAccountServiceWizard {
    public class ServiceRequest {
        public String serviceType; // e.g., 'Additional Funding', 'TPMM', 'Account Closure', 'Manage DMS', 'Change Management'
        public String subServiceType; // e.g., 'Raise Cash', 'Future Deposits' (for DMS)
        
        public Id financialAccountId;
        public Id householdId;
        public Id primaryOwnerId;
        public Id personContactId;
        public String financialAccountName;
        public String currentManagedPlatform;
        public String advisorTeam;
        public Id recordTypeId;
        public String flowInterviewGuid;
        
        // TPMM & TMS Inputs
        public List<Id> uploadedDocumentIds = new List<Id>();
        
        // Account Closure Inputs
        public String closureReason;
        public Date closureEndDate;
        public Date dateOfDeath;
        public String closureExplanation;
        public String closureAdditionalInfo;
        
        // Order Ticket / DMS Inputs
        public Decimal requestAmount;
        public String methodToAllocate;
        public String additionalDetails;
        public String addOrRemove;
        public Date firstWithdrawalDate;
        public Date expectedEndDate;
        public String frequency;
        
        // Change Management Inputs
        public String newManagementStyle;
        
        // Bond Ladder / STCM Flags
        public Boolean isBondLadder = false;
        public Boolean isSTCM = false;
    }
    public static void processServiceRequests(List<ServiceRequest> requests) {
        List<Case> casesToInsert = new List<Case>();
        Map<Integer, ServiceRequest> requestMap = new Map<Integer, ServiceRequest>();
        
        // 1. Prepare Cases
        for (Integer i = 0; i < requests.size(); i++) {
            ServiceRequest req = requests[i];
            Case newCase = buildBaseCase(req);
            
            switch on req.serviceType {
                when 'Additional Funding' {
                    newCase = applyAdditionalFundingRules(newCase, req);
                }
                when 'Third Party Money Movement' {
                    newCase = applyTPMMRules(newCase, req);
                }
                when 'Account Closure' {
                    newCase = applyAccountClosureRules(newCase, req);
                }
                when 'Manage DMS Instructions' {
                    newCase = applyDMSInstructionRules(newCase, req);
                }
                when 'Change Management Style' {
                    newCase = applyChangeManagementRules(newCase, req);
                }
            }
            
            casesToInsert.add(newCase);
            requestMap.put(i, req);
        }
        
        if (!casesToInsert.isEmpty()) {
            insert casesToInsert;
        }
        
        // 2. Process Related Records (Order Tickets, CDLs, Account Updates)
        List<ContentDocumentLink> cdlsToInsert = new List<ContentDocumentLink>();
        List<Order_Ticket__c> ticketsToInsert = new List<Order_Ticket__c>();
        Map<Id, Account> accountsToUpdate = new Map<Id, Account>();
        List<Financial_Account__c> finAccountsToUpdate = new List<Financial_Account__c>();
        
        for (Integer i = 0; i < casesToInsert.size(); i++) {
            Case insertedCase = casesToInsert[i];
            ServiceRequest req = requestMap.get(i);
            
            // Link Uploaded Documents
            if (req.uploadedDocumentIds != null && !req.uploadedDocumentIds.isEmpty()) {
                for (Id docId : req.uploadedDocumentIds) {
                    cdlsToInsert.add(new ContentDocumentLink(
                        ContentDocumentId = docId,
                        LinkedEntityId = insertedCase.Id,
                        ShareType = 'V'
                    ));
                }
            }
            
            // Handle Account Closure (Death)
            if (req.serviceType == 'Account Closure' && req.closureReason == 'Death') {
                accountsToUpdate.put(req.primaryOwnerId, new Account(
                    Id = req.primaryOwnerId,
                    Date_of_Death__c = req.dateOfDeath
                    
                ));
            }
            
            // Handle Order Tickets for DMS
            if (req.serviceType == 'Manage DMS Instructions') {
                ticketsToInsert.add(buildOrderTicket(insertedCase.Id, req));
            }
            
            // Handle Financial Account updates for Change Management Style
            if (req.serviceType == 'Change Management Style' && String.isNotBlank(req.newManagementStyle)) {
                finAccountsToUpdate.add(new Financial_Account__c(
                    Id = req.financialAccountId,
                    Managed_Account_Platform__c = req.newManagementStyle
                ));
            }
        }
        
        if (!cdlsToInsert.isEmpty()) insert cdlsToInsert;
        if (!ticketsToInsert.isEmpty()) insert ticketsToInsert;
        if (!accountsToUpdate.isEmpty()) update accountsToUpdate.values();
        if (!finAccountsToUpdate.isEmpty()) update finAccountsToUpdate;
    }
    
    private static Case buildBaseCase(ServiceRequest req) {
        return new Case(
            Origin = 'Wizard',
            Status = 'New',
            RecordTypeId = req.recordTypeId,
            Wizard_Financial_Account__c = req.financialAccountId,
            FinServ__Household__c = req.householdId,
            AccountId = req.householdId,
            ContactId = req.personContactId,
            Financial_Advisor_Team__c = req.advisorTeam,
            Incomplete_Record__c = false,
            Flow_Interview_ID__c = req.flowInterviewGuid
        );
    }
    
    private static Case applyAdditionalFundingRules(Case c, ServiceRequest req) {
        c.Subject = 'Additional Funding';
        c.Type = 'Additional Funding';
        c.Description = 'This Financial Account was recently serviced (Additional Funding).';
        return c;
    }
    
    private static Case applyTPMMRules(Case c, ServiceRequest req) {
        c.Subject = 'Third Party Money Movement';
        c.Type = 'Third Party Money Movement';
        c.Description = 'This Financial Account was recently serviced (Third Party Money Movement). Please review the documentation attached to this Case. Further documentation can also be found on the Household.';
        c.Needs_Principal_Review__c = true;
        return c;
    }
    
    private static Case applyAccountClosureRules(Case c, ServiceRequest req) {
        c.Subject = 'Account Closure - ' + req.closureReason;
        c.Type = 'Account Closure';
        c.Description = 'Please review all documentation and ensure that all necessary changes are made for this Account Closure.';
        c.Account_Closure_Reason__c = req.closureReason;
        c.Account_Closure_End_Date__c = req.closureEndDate;
        c.Account_Closure_Additional_Information__c = req.closureAdditionalInfo;
        c.Account_Closure_Explanation__c = req.closureExplanation;
        return c;
    }
    
    private static Case applyDMSInstructionRules(Case c, ServiceRequest req) {
        c.Management_Style__c = 'DMS';
        c.Order_Tickets__c = true;
        
        switch on req.subServiceType {
            when 'Update Trade Instructions' {
                c.Subject = 'Update Trade Instructions for ' + req.financialAccountName;
                c.Type = 'Update DMS Instructions';
                c.Description = 'Update Trade Instructions.';
                
                if (req.isBondLadder) c.Bond_Ladder__c = true;
                if (req.isSTCM) c.STCM__c = true;
            }
            when 'Raise Cash' {
                c.Subject = 'Raise Cash for ' + req.financialAccountName;
                c.Type = 'DMS - Raise Cash';
                c.Description = 'Raise Cash';
            }
            when 'Instructions for Future Deposit' {
                c.Subject = 'Instructions for Future Deposit for ' + req.financialAccountName;
                c.Type = 'DMS - Instructions for Future Deposit';
                c.Description = 'Instructions for Future Deposit';
            }
            when 'Add/Remove Systematic Withdrawals' {
                c.Subject = 'Add/Remove Systematic Withdrawals for ' + req.financialAccountName;
                c.Type = 'DMS - Add/Remove Systematic Withdrawals';
                c.Description = 'Add/Remove Systematic Withdrawals';
            }
            when 'Other' {
                c.Subject = 'DMS Request for ' + req.financialAccountName;
                c.Type = 'DMS - Other';
                c.Description = 'Other DMS Request';
            }
        }
        return c;
    }
    
    private static Case applyChangeManagementRules(Case c, ServiceRequest req) {
        c.Previous_Management_Style__c = req.currentManagedPlatform;
        c.Management_Style__c = req.newManagementStyle;
        c.Type = 'Change Management Style';
        c.Subject = 'Change Management Style';
        c.Description = 'Change Management Style to ' + req.newManagementStyle + '.';
        
        if (req.newManagementStyle.contains('DMS')) {
            c.Order_Tickets__c = true;
        }
        return c;
    }
    
    private static Order_Ticket__c buildOrderTicket(Id caseId, ServiceRequest req) {
        Order_Ticket__c ticket = new Order_Ticket__c(
            Case__c = caseId,
            Wizard_Financial_Account__c = req.financialAccountId,
            Flow_Interview_ID__c = req.flowInterviewGuid,
            Incomplete_Record__c = false
        );
        
        switch on req.subServiceType {
            when 'Raise Cash' {
                ticket.Type_of_Request__c = 'Raise Cash';
                ticket.Amount__c = req.requestAmount;
                ticket.Method_of_Cash_Raise__c = req.methodToAllocate;
                ticket.Additional_Details__c = req.additionalDetails;
            }
            when 'Instructions for Future Deposit' {
                ticket.Type_of_Request__c = 'Instructions for Future Deposit';
                ticket.Amount__c = req.requestAmount;
                ticket.Method_to_Allocate__c = req.methodToAllocate;
                ticket.Additional_Details__c = req.additionalDetails;
            }
            when 'Add/Remove Systematic Withdrawals' {
                ticket.Type_of_Request__c = (req.addOrRemove == 'Add') ? 'Add Systematic Withdrawal' : 'Remove Systematic Withdrawal';
                ticket.Amount__c = req.requestAmount;
                ticket.Frequency__c = req.frequency;
                ticket.Date_of_First_Withdrawal__c = req.firstWithdrawalDate;
                ticket.End_Date__c = req.expectedEndDate;
                ticket.Additional_Details__c = req.additionalDetails;
            }
            when 'Other' {
                ticket.Type_of_Request__c = 'Other';
                ticket.Additional_Details__c = req.additionalDetails;
            }
        }
        return ticket;
    }
}
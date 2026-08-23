public class EmailTemplateHelper {

    @AuraEnabled
    public static string getEmailTemplateText(String emailTemplateName, String caseId, String userId){
        EmailTemplate et = [SELECT Id, Body, Subject FROM EmailTemplate WHERE DeveloperName =: emailTemplateName];
        String checkDeposits;
        String finAccts;
        String taxWithholdings;
        String relatedProducts;
        String emailTemplateText = et.Body;
        Case c = [SELECT Id, Amount__c, Reimbursement_Reason__c, 
                  Financial_Advisor_Team__r.Primary_Financial_Advisor__r.FirstName, 
                  Financial_Advisor_Team__r.Primary_Financial_Advisor__r.LastName,
                  FinServ__FinancialAccount__r.Account_Number_Last_4__c,
                  Contact.FirstName, Contact.LastName, Name_of_Charity__c,
                  Recurring_Transfer_Frequency__c, Money_Movement_Direction__c, Money_Type__c,
                  To_Account__r.Account_Number_Last_4__c, TIN__c, 
                  Reason_for_the_Trade__c, FinServ__FinancialAccount__r.FinServ__FinancialAccountNumber__c, 
                  FinServ__FinancialAccount__r.Name, Instruction__r.Recurring_Amount__c, Cancel_Effective_Date__c,
                  Instruction__r.Direction__c, Instruction__r.Method__c, Federal_Withholding__c,
                  State_Withholding__c, FinServ__Household__r.Name,
                  Previous_Management_Style__c, Management_Style__c, Outside_Manager__r.Name, Custodian__c,
                  Financial_Advisor_Team__r.Primary_Financial_Advisor__r.Calendly__CalendlyLink__c, Type, Transfer_From_Account_Name__c, Transfer_From_Account_Number__c,
                  Transfer_From_Account_Type__c FROM Case WHERE Id =: caseId];
        User u = [SELECT Id, Phone FROM User WHERE Id =: userId];
        List<Check_Log__c> cl = [SELECT Id, Amount__c, (SELECT Amount__c, Financial_Account__r.Name FROM Check_Deposits__r) FROM Check_Log__c WHERE Case__c =: caseId LIMIT 1];
        List<Financial_Account_Related_Product__c> rpList = [SELECT Id, Amount__c, Product__r.Name FROM Financial_Account_Related_Product__c WHERE Case__c =: caseId];
        if(c.Type == 'Client Terminated Services'){
            List<FinServ__FinancialAccount__c> finAcctsList = [SELECT Name FROM FinServ__FinancialAccount__c WHERE FinServ__Household__c =: c.Finserv__Household__c];
            if(!finAcctsList.isEmpty()){
                for(FinServ__FinancialAccount__c finAcct : finAcctsList){
                    finAccts = finAccts + '/n' + finAcct.Name;
                }
            }
        }
        if(!rpList.isEmpty()){
            for(Financial_Account_Related_Product__c farp : rpList){
                relatedProducts = relatedProducts + '/n' + farp.Product__r.Name + ' - $' + farp.Amount__c;
            }
        }
        if(!cl.isEmpty()){
            for(Check_Deposit__c cd : cl[0].Check_Deposits__r){
                checkDeposits = checkDeposits + '/n'+ cd.Financial_Account__r.Name + ' - $' + cd.Amount__c; 
            }
        }
        
        if(c.Federal_Withholding__c != null || c.State_Withholding__c != null){
            taxWithholdings = 'Federal Withholding: ' + c.Federal_Withholding__c + '% \nState Withholding: ' + c.State_Withholding__c + '%';
            emailTemplateText = (taxWithholdings != null? 
                                 emailTemplateText.replace('[!Case.TaxWithholdings]', taxWithholdings): emailTemplateText);
        }
        emailTemplateText = (c.Amount__c != null? 
                             emailTemplateText.replace('[!Case.Amount__c]', c.Amount__c.toPlainString()): emailTemplateText);
        emailTemplateText = (c.Reimbursement_Reason__c != null? 
                             emailTemplateText.replace('[!Case.Reimbursement_Reason__c]', c.Reimbursement_Reason__c): emailTemplateText);
        emailTemplateText = (c.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.FirstName != null? 
                             emailTemplateText.replace('[!Case.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.FirstName]', c.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.FirstName): emailTemplateText);
        emailTemplateText = (c.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.LastName != null? 
                             emailTemplateText.replace('[!Case.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.LastName]', c.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.LastName): emailTemplateText);
        emailTemplateText = (c.FinServ__FinancialAccount__r.Account_Number_Last_4__c != null? 
                             emailTemplateText.replace('[!Case.FinServ__FinancialAccount__r.Account_Number_Last_4__c]', c.FinServ__FinancialAccount__r.Account_Number_Last_4__c): emailTemplateText);
        emailTemplateText = (c.Contact.FirstName != null? 
                             emailTemplateText.replace('[!Case.Contact.FirstName]', c.Contact.FirstName): emailTemplateText);
        emailTemplateText = (c.Contact.LastName != null? 
                             emailTemplateText.replace('[!Case.Contact.LastName]', c.Contact.LastName): emailTemplateText);
        emailTemplateText = (c.Name_of_Charity__c != null? 
                             emailTemplateText.replace('[!Case.Name_of_Charity__c]', c.Name_of_Charity__c): emailTemplateText);
        emailTemplateText = (c.Recurring_Transfer_Frequency__c != null? 
                             emailTemplateText.replace('[!Case.Recurring_Transfer_Frequency__c]', c.Recurring_Transfer_Frequency__c): emailTemplateText);
        emailTemplateText = (c.To_Account__r.Account_Number_Last_4__c != null? 
                             emailTemplateText.replace('[!Case.To_Account__r.Account_Number_Last_4__c]', c.To_Account__r.Account_Number_Last_4__c): emailTemplateText);
        emailTemplateText = (c.Money_Movement_Direction__c != null? 
                             emailTemplateText.replace('[!Case.Money_Movement_Direction__c]', c.Money_Movement_Direction__c): emailTemplateText);
        emailTemplateText = (c.Money_Type__c != null? 
                             emailTemplateText.replace('[!Case.Money_Type__c]', c.Money_Type__c): emailTemplateText);
        emailTemplateText = (c.TIN__c != null? 
                             emailTemplateText.replace('[!Case.TIN__c]', c.TIN__c): emailTemplateText);
        emailTemplateText = (c.Reason_for_the_Trade__c != null? 
                             emailTemplateText.replace('[!Case.Reason_for_the_Trade__c]', c.Reason_for_the_Trade__c): emailTemplateText);
        emailTemplateText = (c.FinServ__FinancialAccount__r.FinServ__FinancialAccountNumber__c != null? 
                             emailTemplateText.replace('[!Case.FinServ__FinancialAccount__r.FinServ__FinancialAccountNumber__c]', c.FinServ__FinancialAccount__r.FinServ__FinancialAccountNumber__c): emailTemplateText);
        emailTemplateText = (c.FinServ__FinancialAccount__r.Name != null? 
                             emailTemplateText.replace('[!Case.FinServ__FinancialAccount__r.Name]', c.FinServ__FinancialAccount__r.Name): emailTemplateText);
        emailTemplateText = (c.Instruction__r.Recurring_Amount__c != null? 
                             emailTemplateText.replace('[!Case.Instruction__r.Recurring_Amount__c]', c.Instruction__r.Recurring_Amount__c.toPlainString()): emailTemplateText);
        emailTemplateText = (c.Cancel_Effective_Date__c != null? 
                             emailTemplateText.replace('[!Case.Cancel_Effective_Date__c]', c.Cancel_Effective_Date__c.format()): emailTemplateText);
        emailTemplateText = (c.Instruction__r.Direction__c != null? 
                             emailTemplateText.replace('[!Case.Instruction__r.Direction__c]', c.Instruction__r.Direction__c): emailTemplateText);
        emailTemplateText = (c.Instruction__r.Method__c != null? 
                             emailTemplateText.replace('[!Case.Instruction__r.Method__c]', c.Instruction__r.Method__c): emailTemplateText);
        
        
        emailTemplateText = (c.FinServ__Household__r.Name != null? 
                             emailTemplateText.replace('[!Case.FinServ__Household__r.Name]', c.FinServ__Household__r.Name): emailTemplateText);
        emailTemplateText = (c.Previous_Management_Style__c != null? 
                             emailTemplateText.replace('[!Case.Previous_Management_Style__c]', c.Previous_Management_Style__c): emailTemplateText);
        emailTemplateText = (c.Management_Style__c != null? 
                             emailTemplateText.replace('[!Case.Management_Style__c]', c.Management_Style__c): emailTemplateText);
        emailTemplateText = (c.Outside_Manager__r.Name != null? 
                             emailTemplateText.replace('[!Case.Outside_Manager__r.Name]', ', ' + c.Outside_Manager__r.Name): emailTemplateText);
        emailTemplateText = (c.Custodian__c != null? 
                             emailTemplateText.replace('[!Case.Custodian__c]', c.Custodian__c): emailTemplateText);
        emailTemplateText = (checkDeposits != null? 
                             emailTemplateText.replace('[!Case.Check_Deposit_Table]', checkDeposits): emailTemplateText);
        emailTemplateText = (finAccts != null? 
                             emailTemplateText.replace('[!Case.FinAccts]', finAccts): emailTemplateText);
        emailTemplateText = (relatedProducts != null? 
                             emailTemplateText.replace('[!Case.relatedProducts]', relatedProducts): emailTemplateText);
        emailTemplateText = (c.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.Calendly__CalendlyLink__c != null? 
                             emailTemplateText.replace('[!Case.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.Calendly__CalendlyLink__c]', c.Financial_Advisor_Team__r.Primary_Financial_Advisor__r.Calendly__CalendlyLink__c): emailTemplateText);
        emailTemplateText = (u.Phone != null? 
                             emailTemplateText.replace('[!User.Phone]', u.Phone): emailTemplateText);
        emailTemplateText = (c.Transfer_From_Account_Name__c != null? 
                             emailTemplateText.replace('[!Case.Transfer_From_Account_Name__c]', c.Transfer_From_Account_Name__c): emailTemplateText);
        emailTemplateText = (c.Transfer_From_Account_Number__c != null? 
                             emailTemplateText.replace('[!Case.Transfer_From_Account_Number__c]', c.Transfer_From_Account_Number__c): emailTemplateText);
        emailTemplateText = (c.Transfer_From_Account_Type__c != null? 
                             emailTemplateText.replace('[!Case.Transfer_From_Account_Type__c]', c.Transfer_From_Account_Type__c): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        //emailTemplateText = (c. != null? emailTemplateText.replace('[!Case.]', c.): emailTemplateText);
        
        
        System.debug('emailTemplateText: ' + emailTemplateText);
        return emailTemplateText;
    }
}
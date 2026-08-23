public without sharing class RedtailIntegration_ContactFull {
    @InvocableVariable @AuraEnabled public String firstName;
    @InvocableVariable @AuraEnabled public String middleName;
    @InvocableVariable @AuraEnabled public String lastName;
    @InvocableVariable @AuraEnabled public String physicalStreet;
    @InvocableVariable @AuraEnabled public String physicalCity;
    @InvocableVariable @AuraEnabled public String physicalState;
    @InvocableVariable @AuraEnabled public String physicalZip;
    @InvocableVariable @AuraEnabled public String mailingStreet;
    @InvocableVariable @AuraEnabled public String mailingCity;
    @InvocableVariable @AuraEnabled public String mailingState;
    @InvocableVariable @AuraEnabled public String mailingZip;
    @InvocableVariable @AuraEnabled public String taxId;
    @InvocableVariable @AuraEnabled public String emailAddress;
    @InvocableVariable @AuraEnabled public String phoneNumber;
    @InvocableVariable @AuraEnabled public Date dob;
    @InvocableVariable @AuraEnabled public String employmentStatus;
    @InvocableVariable @AuraEnabled public String employer;
    @InvocableVariable @AuraEnabled public String occupation;
}
// Maps wizard member-form field keys (Envelope_Field__mdt Field_API__c values, which are Account
// person-account API names) to the Case field pair that records a proposed change: the value at
// the time the review case was opened (original) and the requested value (proposed). Consumed by
// WizardEnvelopeStateService.saveProposedCase. All target Case fields are Text.
public class AccountCaseFieldMapping {
    
    public class CaseFieldMapping {
        public String originalCaseField;
        public String proposedCaseField;
        
        public CaseFieldMapping(String originalCaseField, String proposedCaseField) {
            this.originalCaseField = originalCaseField;
            this.proposedCaseField = proposedCaseField;
        }
    }
    
    public static final Map<String, CaseFieldMapping> ACCOUNT_TO_CASE_FIELD_MAPPING =
        new Map<String, CaseFieldMapping>{
            'FirstName' =>
                new CaseFieldMapping('Original_First_Name__c', 'Proposed_First_Name__c'),
                'MiddleName' =>
                new CaseFieldMapping('Original_Middle_Name__c', 'Proposed_Middle_Name__c'),
                'LastName' =>
                new CaseFieldMapping('Original_Last_Name__c', 'Proposed_Last_Name__c'),
                'PersonBirthdate' =>
                new CaseFieldMapping('Original_Date_of_Birth__c', 'Proposed_Date_of_Birth__c'),
                'PersonEmail' =>
                new CaseFieldMapping('Original_Email_Address__c', 'Proposed_Email_Address__c'),
                'PersonMobilePhone' =>
                new CaseFieldMapping('Original_Phone_Number__c', 'Proposed_Phone_Number__c'),
                'Tax_ID__c' =>
                new CaseFieldMapping('Original_Tax_ID__c', 'Proposed_Tax_ID__c'),
                'BillingStreet' =>
                new CaseFieldMapping('Original_Physical_Street__c', 'Proposed_Physical_Street__c'),
                'BillingCity' =>
                new CaseFieldMapping('Original_Physical_City__c', 'Proposed_Physical_City__c'),
                'BillingStateCode' =>
                new CaseFieldMapping('Original_Physical_State__c', 'Proposed_Physical_State__c'),
                'BillingPostalCode' =>
                new CaseFieldMapping('Original_Physical_Zipcode__c', 'Proposed_Physical_Zipcode__c'),
                'Mailing_Different_than_Permanent__c' =>
                new CaseFieldMapping('Original_Mailing_different_than_Permanen__c', 'Proposed_Mailing_different_than_Permanen__c'),
                'PersonMailingStreet' =>
                new CaseFieldMapping('Original_Mailing_Street__c', 'Proposed_Mailing_Street__c'),
                'PersonMailingCity' =>
                new CaseFieldMapping('Original_Mailing_City__c', 'Proposed_Mailing_City__c'),
                'PersonMailingStateCode' =>
                new CaseFieldMapping('Original_Mailing_State__c', 'Proposed_Mailing_State__c'),
                'PersonMailingPostalCode' =>
                new CaseFieldMapping('Original_Mailing_Zip_Code__c', 'Proposed_Mailing_Zip_Code__c'),
                'Employment_Status__c' =>
                new CaseFieldMapping('Original_Employment_Status__c', 'Proposed_Employment_Status__c'),
                'Employer__c' =>
                new CaseFieldMapping('Original_Current_Employer__c', 'Proposed_Current_Employer__c'),
                'Occupation__c' =>
                new CaseFieldMapping('Original_Occupation__c', 'Proposed_Occupation__c'),
                'Name_of_Business__c' =>
                new CaseFieldMapping('Original_Name_of_Business__c', 'Proposed_Name_of_Business__c'),
                'Employer_Street__c' =>
                new CaseFieldMapping('Original_Employer_Street__c', 'Proposed_Employer_Street__c'),
                'Employer_City__c' =>
                new CaseFieldMapping('Original_Employer_City__c', 'Proposed_Employer_City__c'),
                'Employer_State__c' =>
                new CaseFieldMapping('Original_Employer_State__c', 'Proposed_Employer_State__c'),
                'Employer_Zip_Postal_Code__c' =>
                new CaseFieldMapping('Original_Employer_Zip_Code__c', 'Proposed_Employer_Zip_Code__c'),
                'Employed_by_Sec_Industry_Regulator__c' =>
                new CaseFieldMapping('Original_Employed_associated_securities__c', 'Proposed_Employed_associated_securities__c'),
                'Employing_Entity__c' =>
                new CaseFieldMapping('Original_Name_of_the_Employing_Entity__c', 'Proposed_Name_of_the_Employing_Entity__c'),
                'Relationship_to_Employed_Family_Member__c' =>
                new CaseFieldMapping('Original_Relationship_to_the_employed_fa__c', 'Proposed_Relationship_to_the_employed_fa__c'),
                'Approximate_Annual_Income_All_Sources__c' =>
                new CaseFieldMapping('Original_Approximate_Annual_Income__c', 'Proposed_Approximate_Annual_Income__c'),
                'Approximate_Liquid_Net_Worth__c' =>
                new CaseFieldMapping('Original_Approximate_Liquid_Assets__c', 'Proposed_Approximate_Liquid_Assets__c'),
                'Approximate_Net_Worth__c' =>
                new CaseFieldMapping('Original_Approximate_Net_Worth__c', 'Proposed_Approximate_Net_Worth__c'),
                'Investment_Objectives__c' =>
                new CaseFieldMapping('Original_Investment_Objectives__c', 'Proposed_Investment_Objectives__c'),
                'Risk_Tolerance__c' =>
                new CaseFieldMapping('Original_Risk_Tolerance__c', 'Proposed_Risk_Tolerance__c'),
                'Time_Horizon__c' =>
                new CaseFieldMapping('Original_Time_Horizon__c', 'Proposed_Time_Horizon__c'),
                'Liquidity_Needs__c' =>
                new CaseFieldMapping('Original_Liquidity_Needs__c', 'Proposed_Liquidity_Needs__c'),
                'Traditional_Securities_Experience__c' =>
                new CaseFieldMapping('Original_Traditional_Securities_Experien__c', 'Proposed_Traditional_Securities_Experien__c'),
                'Alternative_Investments_Experience__c' =>
                new CaseFieldMapping('Original_Alternative_Investments_Experie__c', 'Proposed_Alternative_Investments_Experie__c'),
                'Derivatives_Complex_Products_Experience__c' =>
                new CaseFieldMapping('Original_Derivatives_Complex_Products__c', 'Proposed_Derivatives_Complex_Products__c'),
                'Insurance_Based_Products_Experience__c' =>
                new CaseFieldMapping('Original_Insurance_Based_Products_Experi__c', 'Proposed_Insurance_Based_Products_Experi__c'),
                'Real_Assets_Experience__c' =>
                new CaseFieldMapping('Original_Real_Assets_Experience__c', 'Proposed_Real_Assets_Experience__c'),
                'Other_Experience__c' =>
                new CaseFieldMapping('Original_Other_Experience__c', 'Proposed_Other_Experience__c'),
                'Other_Experience_Type__c' =>
                new CaseFieldMapping('Original_Other_Experience_Type__c', 'Proposed_Other_Experience_Type__c'),
                'Entity_Jurisdiction__c' =>
                new CaseFieldMapping('Original_Entity_Jurisdiction__c', 'Proposed_Entity_Jurisdiction__c'),
                
                'Entity_Type__c' =>
                new CaseFieldMapping('Original_Entity_Type__c', 'Proposed_Entity_Type__c'),
                
                'Formation_Date__c' =>
                new CaseFieldMapping('Original_Formation_Date__c', 'Proposed_Formation_Date__c'),

                'Mailing_Same_as_Physical__c' =>
                new CaseFieldMapping('Original_Mailing_Same_as_Physical__c', 'Proposed_Mailing_Same_as_Physical__c'),
                
                'Name' =>
                new CaseFieldMapping('Original_Name__c', 'Proposed_Name__c'),
                
                'Name_of_Company_and_Symbol__c' =>
                new CaseFieldMapping('Original_Name_of_Company_and_Symbol__c', 'Proposed_Name_of_Company_and_Symbol__c'),
                
                'Name_of_Country__c' =>
                new CaseFieldMapping('Original_Name_of_Country__c', 'Proposed_Name_of_Country__c'),
                
                'Officer__c' =>
                new CaseFieldMapping('Original_Officer__c', 'Proposed_Officer__c'),
                
                'Percentage_of_Ownership__c' =>
                new CaseFieldMapping('Original_Percentage_of_Ownership__c', 'Proposed_Percentage_of_Ownership__c'),
                
                'Senior_Military_Governmental_Political__c' =>
                new CaseFieldMapping(
                    'Original_Senior_Military_Governmental_Po__c',
                    'Proposed_Senior_Military_Governmental_Po__c'
                ),
                
                'ShippingCity' =>
                new CaseFieldMapping('Original_Shipping_City__c', 'Proposed_Shipping_City__c'),
                
                'ShippingPostalCode' =>
                new CaseFieldMapping('Original_Shipping_Postal_Code__c', 'Proposed_Shipping_Postal_Code__c'),
                
                'ShippingStateCode' =>
                new CaseFieldMapping('Original_Shipping_State_Code__c', 'Proposed_Shipping_State_Code__c'),
                
                'ShippingStreet' =>
                new CaseFieldMapping('Original_Shipping_Street__c', 'Proposed_Shipping_Street__c'),
                
                'TIN_or_SSN__c' =>
                new CaseFieldMapping('Original_TIN_or_SSN__c', 'Proposed_TIN_or_SSN__c')
                };
                    }
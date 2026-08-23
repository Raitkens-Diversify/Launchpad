@isTest
private class efs_Order_TicketTest
{
    static testMethod void mytestmethod()
    {
        test.startTest();
        insertObject('Order_Ticket__c');
        test.stopTest();
    }
    private static SObject getNewSobject(String customName) 
    {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        Schema.SObjectType sType = gd.get(customName);
        return sType.newSobject();
    }
    private static Id insertObject(String ObjectAPIName)
    {
        Map<String, Schema.DescribeFieldResult> mandatoryFieldsMap = new Map<String, Schema.DescribeFieldResult>();
        SObject customObj = getNewSobject(ObjectAPIName);
        Map<String, Schema.SObjectType> globalDescription = Schema.getGlobalDescribe();
        Schema.DescribeSObjectResult sObjResult = globalDescription.get(ObjectAPIName).getDescribe();
        Map<String, Schema.SObjectField> mapFieldList = sObjResult.fields.getMap();
        for(Schema.SObjectField field : mapFieldList.values())
        {
            Schema.DescribeFieldResult fieldResult = field.getDescribe();
            if(fieldResult.isCreateable() && !fieldResult.isDefaultedOnCreate() )
            {
                if(String.valueOf(fieldResult.getType()).equals('REFERENCE'))
                {
                    if(!fieldResult.isNillable())
                    {
                        if(!String.valueOf(fieldResult.getName()).equals('OwnerId') && !String.valueOf(fieldResult.getName()).equals('CreatedById')
                            && !String.valueOf(fieldResult.getName()).equals('LastModifiedById'))
                        {
                            mandatoryFieldsMap.put(String.valueOf(fieldResult.getName()), fieldResult);
                        }
                    }
                }
                else
                {
                    mandatoryFieldsMap.put(String.valueOf(fieldResult.getName()), fieldResult);
                }
            }
        }
        if(mapFieldList.containsKey('Country')) {
            mandatoryFieldsMap.remove('Country');
            customObj.put('Country', '');
        }
        if(mapFieldList.containsKey('State')) {
            mandatoryFieldsMap.remove('State');
            customObj.put('State', '');
        }
        if(mapFieldList.containsKey('BillingCountry')) {
            mandatoryFieldsMap.remove('BillingCountry');
            customObj.put('BillingCountry', '');
        }
        if(mapFieldList.containsKey('BillingState')) {
           mandatoryFieldsMap.remove('BillingState');
            customObj.put('BillingState', '');
        }
        if(mapFieldList.containsKey('MailingCountry')) {
            mandatoryFieldsMap.remove('MailingCountry');
            customObj.put('MailingCountry', '');
        }
        if(mapFieldList.containsKey('MailingState')) {
            mandatoryFieldsMap.remove('MailingState');
            customObj.put('MailingState', '');
        }
        if(mapFieldList.containsKey('OtherCountry')) {
            mandatoryFieldsMap.remove('OtherCountry');
           customObj.put('OtherCountry', '');
        }
        if(mapFieldList.containsKey('OtherState')) {
           mandatoryFieldsMap.remove('OtherState');
            customObj.put('OtherState', '');
        }
        if(mapFieldList.containsKey('PersonMailingCountry')) {
            mandatoryFieldsMap.remove('PersonMailingCountry');
            customObj.put('PersonMailingCountry', '');
        }
        if(mapFieldList.containsKey('PersonMailingState')) {
            mandatoryFieldsMap.remove('PersonMailingState');
            customObj.put('PersonMailingState', '');
        }
        if(mapFieldList.containsKey('PersonOtherCountry')) {
            mandatoryFieldsMap.remove('PersonOtherCountry');
           customObj.put('PersonOtherCountry', '');
        }
        if(mapFieldList.containsKey('PersonOtherState')) {
            mandatoryFieldsMap.remove('PersonOtherState');
            customObj.put('PersonOtherState', '');
        }
        if(mapFieldList.containsKey('ShippingCountry')) {
            mandatoryFieldsMap.remove('ShippingCountry');
           customObj.put('ShippingCountry', '');
        }
        if(mapFieldList.containsKey('ShippingState')) {
            mandatoryFieldsMap.remove('ShippingState');
            customObj.put('ShippingState', '');
        }
        //Removing Name field when Org is enabled with Person Accounts
        if(ObjectAPIName == 'Account' && mapFieldList.containsKey('isPersonAccount') && mandatoryFieldsMap.containsKey('Name')) {
            mandatoryFieldsMap.remove('Name');
        }
        for(String str: mandatoryFieldsMap.keySet())
        {
            String fieldType = String.valueOf(mandatoryFieldsMap.get(str).getType()).toLowerCase();
            if(fieldType.contains('checkbox') || fieldType.contains('boolean'))
            {
                customObj.put(str, true);
            }
            else if(fieldType.contains('integer') || fieldType.contains('double') || fieldType.contains('percent') || 
                fieldType.contains('currency') || fieldType.contains('number'))
            {
                customObj.put(str, 1);
            }
            else if(fieldType.contains('phone'))
            {
                customObj.put(str, '1234567890');
            }
            else if(fieldType.contains('date'))
            {
                customObj.put(str, Date.Today());
            }
            else if(fieldType.contains('time'))
            {
                customObj.put(str, Time.newInstance(1, 2, 3, 4));
            }
            else if(fieldType.contains('email'))
            {
                customObj.put(str, 'test@test.com');
            }
            else if(fieldType.contains('reference'))
            {
                String referenceFieldObject = String.valueOf(mandatoryFieldsMap.get(str).getReferenceTo()[0]);
                customObj.put(str, insertObject(referenceFieldObject));
            }
            else if(fieldType.contains('picklist'))
            {               
                if(!mandatoryFieldsMap.get(str).isNillable())
                {
                    String temp = (mandatoryFieldsMap.get(str).getPicklistValues()[0]).getValue();
                    customObj.put(str, temp);
                }
            }
            else
            {
                customObj.put(str, 'T');
            }
        }
        insert customObj;
        update customObj;
        return customObj.Id;
    }
}
public with sharing class GroupMembersController {

    public class MemberWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountId;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public String role;
        @AuraEnabled public String taxId;
        @AuraEnabled public String age;
        @AuraEnabled public String birthdate;
        @AuraEnabled public String mobile;
        @AuraEnabled public String email;
        @AuraEnabled public String emailMailto;
        @AuraEnabled public Integer events;
        @AuraEnabled public Integer tasks;
        @AuraEnabled public Integer calls;
        @AuraEnabled public Integer emails;
        @AuraEnabled public Boolean isPersonAccount;
        @AuraEnabled public String dateFormation;

    }

    @AuraEnabled(cacheable=true)
    public static List<MemberWrapper> getGroupMembers(Id accountId) {
        List<MemberWrapper> memberList = new List<MemberWrapper>();
        if (accountId == null) return memberList;

        List<Account_Account_Relationship__c> relations = [
            SELECT Id, Related_Account__c, Role__c,
                   Related_Account__r.Name, Related_Account__r.IsPersonAccount,
                   Related_Account__r.Tax_Id__c,
                   Related_Account__r.PersonBirthdate,
                   Related_Account__r.PersonMobilePhone,
                   Related_Account__r.PersonEmail,
            	   Related_Account__r.Date_of_Formation__c,
                   Related_Account__r.recordType.Name
            FROM Account_Account_Relationship__c
            WHERE Account__c = :accountId
            AND Active__c = true
        ];

        if (relations.isEmpty()) return memberList;

        Set<Id> relatedAccountIds = new Set<Id>();
        for (Account_Account_Relationship__c relation : relations) {
            if (relation.Related_Account__c != null) relatedAccountIds.add(relation.Related_Account__c);
        }

        if (relatedAccountIds.isEmpty()) return memberList;

        Map<Id, Integer> taskCountMap = new Map<Id, Integer>();
        Map<Id, Integer> callCountMap = new Map<Id, Integer>();
        Map<Id, Integer> emailCountMap = new Map<Id, Integer>();
        Map<Id, Integer> eventCountMap = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT AccountId, TaskSubtype, COUNT(Id) total
            FROM Task
            WHERE AccountId IN :relatedAccountIds
            GROUP BY AccountId, TaskSubtype
        ]) {
            Id relatedAccountId = (Id) ar.get('AccountId');
            String taskSubtype = (String) ar.get('TaskSubtype');
            Integer total = (Integer) ar.get('total');

            if (taskSubtype == 'Call') callCountMap.put(relatedAccountId, total);
            else if (taskSubtype == 'Email') emailCountMap.put(relatedAccountId, total);
            else taskCountMap.put(relatedAccountId, total);
        }

        for (AggregateResult ar : [
            SELECT AccountId, COUNT(Id) total
            FROM Event
            WHERE AccountId IN :relatedAccountIds
            GROUP BY AccountId
        ]) {
            eventCountMap.put((Id) ar.get('AccountId'), (Integer) ar.get('total'));
        }

        for (Account_Account_Relationship__c relation : relations) {
            Id relatedAccountId = relation.Related_Account__c;
            if (relatedAccountId == null) continue;

            Account target = relation.Related_Account__r;
            MemberWrapper member = new MemberWrapper();

            member.id = relation.Id;
            member.accountId = relatedAccountId;
            member.name = target.Name;
            member.role = relation.Role__c;
           // member.isPrimary = target.PrimaryGroup__pc != null && target.PrimaryGroup__pc.equalsIgnoreCase('Yes');
            member.taxId = target.Tax_ID__c != null ? target.Tax_ID__c : '';
            member.mobile = target.PersonMobilePhone != null ? target.PersonMobilePhone : '';
            member.email = target.PersonEmail != null ? target.PersonEmail : '';
            member.emailMailto = target.PersonEmail != null ? 'mailto:' + target.PersonEmail : '';
            member.isPersonAccount = target.recordType.Name != null ? target.recordType.Name == 'Person Account' : false;
            member.dateFormation = target.Date_of_Formation__c != null ? DateTime.newInstance(target.Date_of_Formation__c.year(), target.Date_of_Formation__c.month(), target.Date_of_Formation__c.day()).format('MMM dd, yyyy'):'';
            if (target.PersonBirthdate != null) {
                Date dob = target.PersonBirthdate;
                member.birthdate = DateTime.newInstance(dob.year(), dob.month(), dob.day()).format('MMM dd, yyyy');
                Decimal ageYears = Decimal.valueOf(dob.daysBetween(Date.today())) / 365.2425;
                member.age = String.valueOf(ageYears.setScale(1));
            } else {
                member.birthdate = '';
                member.age = '';
            }

            member.events = eventCountMap.containsKey(relatedAccountId) ? eventCountMap.get(relatedAccountId) : 0;
            member.tasks = taskCountMap.containsKey(relatedAccountId) ? taskCountMap.get(relatedAccountId) : 0;
            member.calls = callCountMap.containsKey(relatedAccountId) ? callCountMap.get(relatedAccountId) : 0;
            member.emails = emailCountMap.containsKey(relatedAccountId) ? emailCountMap.get(relatedAccountId) : 0;

            memberList.add(member);
        }

        return memberList;
    }
}
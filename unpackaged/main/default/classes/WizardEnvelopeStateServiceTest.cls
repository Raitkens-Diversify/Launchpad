@IsTest
private class WizardEnvelopeStateServiceTest {
    @testSetup
    static void setup() { 
        
        Envelope__c envelope = new Envelope__c();
        envelope.name ='Test';
        insert envelope;
        
        // Create Household Members (replace with your object if needed)
        List<Account> members = new List<Account>{
            new Account(Name = 'Member 1'),
                new Account(Name = 'Member 2')
                };
                    insert members;
        
        // Create Financial Accounts
        List<Financial_Account__c> financialAccounts =
            new List<Financial_Account__c>{
                new Financial_Account__c(Name = 'FA 1'),
                    new Financial_Account__c(Name = 'FA 2')
                    };
                        insert financialAccounts;
        
        // Create Services
        List<Service__c> services = new List<Service__c>{
            new Service__c(Name = 'Service 1'),
                new Service__c(Name = 'Service 2')
                };
                    insert services;
        
        // ---------------------------------------------------------
        // ADDITIONAL DATA FOR getHouseholdMembersAndAccounts()
        // ---------------------------------------------------------
        
        // Household
        Account household = new Account(
            Name = 'Test Household'
        );
        insert household;
        
        // If using Person Accounts, create them here instead.
        // Otherwise create Contacts for the members.
        
        List<Contact> contacts = new List<Contact>{
            new Contact(
                LastName = 'One',
                AccountId = members[0].Id
            ),
                new Contact(
                    LastName = 'Two',
                    AccountId = members[1].Id
                )
                };
                    insert contacts;
        
        List<AccountContactRelation> relations = new List<AccountContactRelation>();
        
        for(Contact con : contacts){
            relations.add(new AccountContactRelation(
                AccountId = household.Id,
                ContactId = con.Id,
                IsActive = true
            ));
        }
        
        insert relations;
        
        // Link Financial Accounts to Household
        for(Financial_Account__c fa : financialAccounts){
            fa.Household__c = household.Id;
        }
        update financialAccounts;
        
        // Link Services to Household
        for(Service__c ser : services){
            ser.Household__c = household.Id;
        }
        update services;
    }
    @IsTest
    static void savesSmallJsonToField() {
        String json = '{"name":"Test Envelope","data":{"household":{"name":"Smith"}}}';
        
        WizardEnvelopeStateService.EnvelopeState result = WizardEnvelopeStateService.saveEnvelopeState(
            null,
            json,
            'Test Envelope',
            'Smith Household',
            'household',
            'In Progress',
            2,
            false
        );
        
        System.assertNotEquals(null, result.envelopeId, 'Envelope Id should be returned.');
        
        Envelope__c saved = [
            SELECT Envelope_JSON__c, State_Storage__c, State_File_DocumentId__c,
            Household__r.Name, Current_Step__c, Status__c,
            Missing_Items_Count__c, Missing_Items_Has_Plus__c
            FROM Envelope__c
            WHERE Id = :result.envelopeId
        ];
        
        System.assertEquals('Field', saved.State_Storage__c, 'Expected field storage for small JSON.');
        System.assertNotEquals(null, saved.Envelope_JSON__c, 'Envelope JSON should be stored in field.');
        System.assertEquals(null, saved.State_File_DocumentId__c, 'File pointer should be empty for field storage.');
        System.assertEquals('household', saved.Current_Step__c);
        System.assertEquals('In Progress', saved.Status__c);
        System.assertEquals(2, saved.Missing_Items_Count__c.intValue(),
            'The wizard-computed missing-inputs total should be stored for the list column.');
        System.assertEquals(false, saved.Missing_Items_Has_Plus__c,
            'The lower-bound marker should follow the count that was sent.');
        
        WizardEnvelopeStateService.EnvelopeState loaded =
            WizardEnvelopeStateService.loadEnvelopeState(result.envelopeId);
        System.assert(loaded.envelopeJson.contains('Test Envelope'), 'Loaded JSON should match saved JSON.');
    }
    
    // A save that could not compute the total (a form schema it needed had not loaded) sends null,
    // and must leave the stored number alone: the list showing the last real count is right far more
    // often than it showing a zero the envelope never earned.
    @IsTest
    static void nullMissingItemsCountKeepsTheStoredTotal() {
        String json = '{"name":"Test Envelope"}';

        WizardEnvelopeStateService.EnvelopeState first = WizardEnvelopeStateService.saveEnvelopeState(
            null,
            json,
            'Test Envelope',
            'Smith Household',
            'household',
            'In Progress',
            3,
            true
        );

        WizardEnvelopeStateService.saveEnvelopeState(
            first.envelopeId,
            json,
            'Test Envelope',
            'Smith Household',
            'household',
            'In Progress',
            null,
            null
        );

        Envelope__c saved = [
            SELECT Missing_Items_Count__c, Missing_Items_Has_Plus__c
            FROM Envelope__c
            WHERE Id = :first.envelopeId
        ];
        System.assertEquals(3, saved.Missing_Items_Count__c.intValue(),
            'A null count should leave the previously stored total in place.');
        System.assertEquals(true, saved.Missing_Items_Has_Plus__c,
            'A null count should leave the lower-bound marker in place too.');
    }

    @IsTest
    static void savesLargeJsonToFile() {
        List<String> chunks = new List<String>();
        // Build a payload comfortably larger than the service's 120k threshold.
        for (Integer i = 0; i < 13000; i++) {
            chunks.add('xxxxxxxxxx'); // 10 chars
        }
        String largePayload = String.join(chunks, '');
        String json = '{"data":"' + largePayload + '"}';
        
        WizardEnvelopeStateService.EnvelopeState result = WizardEnvelopeStateService.saveEnvelopeState(
            null,
            json,
            'Large Envelope',
            'Large Household',
            'accounts',
            'In Progress',
            2,
            false
        );
        
        Envelope__c saved = [
            SELECT Envelope_JSON__c, State_Storage__c, State_File_DocumentId__c
            FROM Envelope__c
            WHERE Id = :result.envelopeId
        ];
        
        System.assertEquals('File', saved.State_Storage__c, 'Expected file storage for large JSON.');
        System.assertEquals(null, saved.Envelope_JSON__c, 'Envelope JSON field should be cleared for file storage.');
        System.assertNotEquals(null, saved.State_File_DocumentId__c, 'File pointer should be set.');
        
        ContentVersion version = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :saved.State_File_DocumentId__c
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];
        System.assertNotEquals(null, version.VersionData, 'Stored file content should exist.');
        
        WizardEnvelopeStateService.EnvelopeState loaded =
            WizardEnvelopeStateService.loadEnvelopeState(result.envelopeId);
        System.assert(loaded.envelopeJson != null && loaded.envelopeJson.length() > 120000,
                      'Loaded JSON should be the large payload.');
    }
    // testSaveWizardViewPreference removed: saveWizardViewPreference was retired as dead code (it has
    // no callers), so the test that exercised it no longer compiles. Restore both together if the
    // method is ever needed again.
    @isTest
    static void testGetWizardViewPreference() {
        // Get current test user
        User u = [SELECT Id, Wizard_View_Preference__c FROM User WHERE Id = :UserInfo.getUserId()];
        
        // Set initial value
        u.Wizard_View_Preference__c = 'Paged';
        update u;
        
        Test.startTest();
        WizardEnvelopeStateService.UserPreferenceWrapper result = WizardEnvelopeStateService.getUserPreferences();
        Test.stopTest();
        
        System.assertEquals('Paged', result.wizardViewPreference, 'Preference should be Paged');
    }
    
    
    
    @IsTest
    static void testRemoveFinancialAccounts() {
        
        List<Financial_Account__c> accounts =
            [SELECT Id FROM Financial_Account__c];
        
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        
        Test.startTest();
        WizardEnvelopeStateService.removeFinancialAccounts(
            new List<Id>{ accounts[0].Id, accounts[1].Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT Count() FROM Financial_Account__c
             WHERE Id IN :accounts]
        );
        
        System.assertEquals(
            0,
            [SELECT Count() FROM Envelope_Content__c
             WHERE Wizard_Financial_Account__c IN :accounts]
        );
    }
    
    @IsTest
    static void testRemoveServices() {
        
        List<Service__c> services = [SELECT Id FROM Service__c];
        
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        
        Test.startTest();
        WizardEnvelopeStateService.removeServices(
            new List<Id>{ services[0].Id, services[1].Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT Count() FROM Service__c
             WHERE Id IN :services]
        );
    }
    @isTest
    static void testReadDoesNotLinkHouseholdRecordsToEnvelope() {
        
        Envelope__c env = [
            SELECT Id
            FROM Envelope__c
            LIMIT 1
        ];
        
        Account household = [
            SELECT Id
            FROM Account
            WHERE Name = 'Test Household'
            LIMIT 1
        ];
        
        Integer beforeCount = [
            SELECT Count()
            FROM Envelope_Content__c
            WHERE Envelope__c = :env.Id
        ];
        
        Test.startTest();
        
        WizardEnvelopeStateService.getHouseholdMembersAndAccounts(
            household.Id,
            env.Id
        );
        WizardEnvelopeStateService.getHouseholdMembersAndAccounts(
            household.Id,
            env.Id
        );
        
        Test.stopTest();
        
        Integer afterCount = [
            SELECT Count()
            FROM Envelope_Content__c
            WHERE Envelope__c = :env.Id
        ];
        
        // Reading an envelope must not change what it contains. Records join an envelope by being
        // added to it, never by being read — otherwise opening one envelope would graft another's
        // drafts into it, and a removed record would return on the next load.
        System.assertEquals(beforeCount, afterCount,
                            'Reading the household should not link its records to the envelope.');
    }
    @IsTest
    static void testRemoveHouseholdMembers() {
        
        List<Account> members = [SELECT Id FROM Account where Name = 'Member 1' OR Name = 'Member 2'];
        delete  [SELECT Id FROM contact];
        delete  [SELECT Id FROM AccountContactRelation];
        
        
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        
        Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ members[0].Id, members[1].Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT Count() FROM Account WHERE Id IN :members]
        );
        
        System.assertEquals(
            0,
            [SELECT Count() FROM Envelope_Content__c
             WHERE Account__c IN :members]
        );
    }
    
    // -------------------------------------------------------------------------
    // Removal: unlink from the envelope, delete only when nothing else uses the record
    // -------------------------------------------------------------------------
    
    private static Id fiduciaryRecordTypeId() {
        return Schema.SObjectType.Account_Account_Relationship__c
            .getRecordTypeInfosByDeveloperName()
            .get('Fiduciary_Legal')
            .getRecordTypeId();
    }
    
    private static Envelope__c makeSecondEnvelope() {
        Envelope__c other = new Envelope__c(Name = 'Second Envelope');
        insert other;
        return other;
    }
    
    // The reported case: a person created in one envelope and picked as a related party in another.
    // Removing them from the second envelope must not take them out of the first.
    @IsTest
    static void testRemoveMember_KeptWhenAnotherEnvelopeStillHoldsIt() {
        Envelope__c envA = [SELECT Id FROM Envelope__c LIMIT 1];
        Envelope__c envB = makeSecondEnvelope();
        Account trust = new Account(Name = 'Family Trust');
        Account person = new Account(Name = 'Shared Person');
        insert new List<Account>{ trust, person };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = envA.Id, Account__c = person.Id),
                    new Envelope_Content__c(Envelope__c = envB.Id, Account__c = person.Id),
                    new Envelope_Content__c(Envelope__c = envB.Id, Account__c = trust.Id)
                    };
                        insert new Account_Account_Relationship__c(
                            Account__c = trust.Id,
                            Related_Account__c = person.Id,
                            Roles__c = 'Trustee;Grantor',
                            RecordTypeId = fiduciaryRecordTypeId(),
                            Active__c = true
                        );
        
        Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ person.Id },
            envB.Id
        );
        Test.stopTest();
        
        System.assertEquals(1,
                            [SELECT Count() FROM Account WHERE Id = :person.Id],
                            'The person is used by another envelope, so the Account must survive.');
        System.assertEquals(1,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Envelope__c = :envA.Id AND Account__c = :person.Id],
                            'The other envelope keeps its link.');
        System.assertEquals(0,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Envelope__c = :envB.Id AND Account__c = :person.Id],
                            'Only this envelope is unlinked.');
        System.assertEquals(0,
                            [SELECT Count() FROM Account_Account_Relationship__c
                             WHERE Related_Account__c = :person.Id],
                            'Both roles lived on one relationship, so one record is removed.');
    }
    
    // Nothing else references the record, so it is deleted along with everything created for it.
    @IsTest
    static void testRemoveMember_DeletedWithItsDocumentsWhenUnused() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Account household = [
            SELECT Id FROM Account WHERE Name = 'Test Household' LIMIT 1
        ];
        Account person = new Account(Name = 'Only Here');
        insert person;
        insert new Envelope_Content__c(
            Envelope__c = env.Id,
            Account__c = person.Id
        );
        // The household-membership link every member carries; it must not keep the record alive.
        insert new Account_Account_Relationship__c(
            Account__c = household.Id,
            Related_Account__c = person.Id,
            Association_Type__c = 'Member',
            Active__c = true
        );
        Required_Documents__c doc = new Required_Documents__c(
            Name = 'Only Here - client profile',
            Person__c = person.Id
        );
        insert doc;
        insert new Signee__c(
            Required_Document__c = doc.Id,
            Account__c = person.Id
        );
        insert new Envelope_Content__c(
            Envelope__c = env.Id,
            Required_Document__c = doc.Id
        );
        
        Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ person.Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(0,
                            [SELECT Count() FROM Account WHERE Id = :person.Id],
                            'An unused record should be deleted; the household link alone does not keep it.');
        System.assertEquals(0,
                            [SELECT Count() FROM Required_Documents__c WHERE Id = :doc.Id],
                            'Its Required Document should go with it, not be orphaned.');
        System.assertEquals(0,
                            [SELECT Count() FROM Signee__c WHERE Required_Document__c = :doc.Id],
                            'Its Signee rows should go with it.');
        System.assertEquals(0,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Required_Document__c = :doc.Id],
                            'The document envelope link should go with it.');
        System.assertEquals(0,
                            [SELECT Count() FROM Account_Account_Relationship__c
                             WHERE Related_Account__c = :person.Id],
                            'The household-membership relationship should not be left orphaned.');
    }
    
    // A person who owns a Financial Account is still in use even with no envelope links left.
    @IsTest
    static void testRemoveMember_KeptWhenItHoldsAFinancialAccountRole() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Financial_Account__c account = [
            SELECT Id FROM Financial_Account__c LIMIT 1
        ];
        Account person = new Account(Name = 'Account Owner');
        insert person;
        insert new Envelope_Content__c(
            Envelope__c = env.Id,
            Account__c = person.Id
        );
        insert new Financial_Account_Role__c(
            Financial_Account__c = account.Id,
            Account__c = person.Id,
            Role__c = 'Primary Owner'
        );
        
        Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ person.Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(1,
                            [SELECT Count() FROM Account WHERE Id = :person.Id],
                            'An account owner is still in use and must not be deleted.');
        System.assertEquals(1,
                            [SELECT Count() FROM Financial_Account_Role__c
                             WHERE Account__c = :person.Id],
                            'Its ownership role should be untouched.');
    }
    
    // A record's own children must not keep it alive, or nothing would ever be deletable: every
    // entity carries its own related parties and every Financial Account its own owner roles.
    @IsTest
    static void testRemoveEntity_OwnChildrenDoNotKeepItAlive() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Account trust = new Account(Name = 'Lone Trust');
        Account party = new Account(Name = 'Its Trustee');
        insert new List<Account>{ trust, party };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = env.Id, Account__c = trust.Id),
                    new Envelope_Content__c(Envelope__c = env.Id, Account__c = party.Id)
                    };
                        // The trust's own related party — a row where the trust is the entity, not the referent.
                        insert new Account_Account_Relationship__c(
                            Account__c = trust.Id,
                            Related_Account__c = party.Id,
                            Roles__c = 'Trustee',
                            RecordTypeId = fiduciaryRecordTypeId(),
                            Active__c = true
                        );
        
        Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ trust.Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(0,
                            [SELECT Count() FROM Account WHERE Id = :trust.Id],
                            'The trust\'s own parties are its children and must not block its deletion.');
        System.assertEquals(0,
                            [SELECT Count() FROM Account WHERE Id = :party.Id],
                            'The party was here only for the role it held on the trust, so it leaves with it.');
        System.assertEquals(0,
                            [SELECT Count() FROM Account_Account_Relationship__c
                             WHERE Account__c = :trust.Id],
                            'Its relationships should not be left orphaned.');
    }
    
    // Removing an entity takes with it the parties whose only reason to be in the envelope was the
    // role they held on it — the same end state as clearing them one by one in the interview.
    @IsTest
    static void testRemoveMember_StrandedPartyLeavesWithTheEntity() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Account trust = new Account(Name = 'Solo Trust');
        Account party = new Account(Name = 'Solo Trustee');
        insert new List<Account>{ trust, party };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = env.Id, Account__c = trust.Id),
                    new Envelope_Content__c(Envelope__c = env.Id, Account__c = party.Id)
                    };
                        insert new Account_Account_Relationship__c(
                            Account__c = trust.Id,
                            Related_Account__c = party.Id,
                            Roles__c = 'Trustee',
                            RecordTypeId = fiduciaryRecordTypeId(),
                            Active__c = true
                        );
        
        Test.startTest();
        List<Id> alsoRemoved = WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ trust.Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(0,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Envelope__c = :env.Id AND Account__c = :party.Id],
                            'The party should be taken out of the envelope with the entity it served.');
        System.assertEquals(0,
                            [SELECT Count() FROM Account WHERE Id = :party.Id],
                            'Nothing else references the party, so it is deleted rather than left behind.');
        // The outline drops rows on this list rather than working out which ones went, so a party
        // missing from it keeps rendering for a record that no longer exists.
        System.assertEquals(
            new List<Id>{ party.Id },
            alsoRemoved,
            'The party taken out with the entity must be reported to the caller.');
    }
    
    // The party is only removed when no other member of this envelope still uses it. A person holding
    // a role on a second entity keeps their place; only the removed entity's own relation goes.
    @IsTest
    static void testRemoveMember_PartyKeptWhenAnotherEntityInEnvelopeUsesIt() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Account trustA = new Account(Name = 'Trust One');
        Account trustB = new Account(Name = 'Trust Two');
        Account party = new Account(Name = 'Shared Trustee');
        insert new List<Account>{ trustA, trustB, party };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = env.Id, Account__c = trustA.Id),
                    new Envelope_Content__c(Envelope__c = env.Id, Account__c = trustB.Id),
                    new Envelope_Content__c(Envelope__c = env.Id, Account__c = party.Id)
                    };
                        insert new List<Account_Account_Relationship__c>{
                            new Account_Account_Relationship__c(
                                Account__c = trustA.Id,
                                Related_Account__c = party.Id,
                                Roles__c = 'Trustee',
                                RecordTypeId = fiduciaryRecordTypeId(),
                                Active__c = true
                            ),
                                new Account_Account_Relationship__c(
                                    Account__c = trustB.Id,
                                    Related_Account__c = party.Id,
                                    Roles__c = 'Trustee',
                                    RecordTypeId = fiduciaryRecordTypeId(),
                                    Active__c = true
                                )
                                };
                                    
                                    Test.startTest();
        List<Id> alsoRemoved = WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ trustA.Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(1,
                            [SELECT Count() FROM Account WHERE Id = :party.Id],
                            'Another member of this envelope still uses the party, so it must survive.');
        System.assertEquals(1,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Envelope__c = :env.Id AND Account__c = :party.Id],
                            'It keeps its envelope link while it is still a party.');
        System.assertEquals(1,
                            [SELECT Count() FROM Account_Account_Relationship__c
                             WHERE Account__c = :trustB.Id AND Related_Account__c = :party.Id],
                            'Only the removed entity\'s relation goes; the other one is untouched.');
        // Reporting a kept party would have the outline drop a row that is still needed.
        System.assertEquals(0,
                            alsoRemoved.size(),
                            'A party that keeps its place must not be reported as removed.');
    }
    
    // A record the caller asks to remove may already be gone — deleted in another session, or named by
    // an outline row that went stale when an earlier removal took it. Nothing references what is not
    // there, so it reads as unused and would be deleted a second time; that throws ENTITY_IS_DELETED
    // and fails the whole removal.
    @IsTest
    static void testRemoveMember_AlreadyDeletedRecordIsANoOp() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Account person = new Account(Name = 'Already Gone');
        insert person;
        Id personId = person.Id;
        insert new Envelope_Content__c(
            Envelope__c = env.Id,
            Account__c = personId
        );
        delete person;
        
        Test.startTest();
        List<Id> alsoRemoved = WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ personId },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(0,
                            alsoRemoved.size(),
                            'A record that is already gone takes nothing with it.');
        System.assertEquals(0,
                            [SELECT Count() FROM Account WHERE Id = :personId],
                            'It stays deleted, and the second removal completes without throwing.');
    }
    
    // The Trusted Contact an individual client names is a related party like any other: person to
    // person, and removed with the client when nothing else holds it.
    @IsTest
    static void testRemoveMember_TrustedContactLeavesWithTheClient() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Account client = new Account(Name = 'Individual Client');
        Account contact = new Account(Name = 'Their Trusted Contact');
        insert new List<Account>{ client, contact };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = env.Id, Account__c = client.Id),
                    new Envelope_Content__c(Envelope__c = env.Id, Account__c = contact.Id)
                    };
                        insert new Account_Account_Relationship__c(
                            Account__c = client.Id,
                            Related_Account__c = contact.Id,
                            Roles__c = 'Trusted Contact',
                            RecordTypeId = fiduciaryRecordTypeId(),
                            Active__c = true
                        );
        
        Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ client.Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(0,
                            [SELECT Count() FROM Account WHERE Id = :contact.Id],
                            'The trusted contact leaves with the client it was named by.');
        System.assertEquals(0,
                            [SELECT Count() FROM Account_Account_Relationship__c
                             WHERE Account__c = :client.Id],
                            'The relationship between the two person accounts should be gone.');
    }
    
    // A stranded party that owns one of this envelope's Financial Accounts is still needed here, so
    // it keeps its place even though the role that first put it here is gone.
    @IsTest
    static void testRemoveMember_PartyKeptWhenItOwnsAnAccountInThisEnvelope() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Financial_Account__c account = [
            SELECT Id FROM Financial_Account__c LIMIT 1
        ];
        Account business = new Account(Name = 'Owning Business');
        Account party = new Account(Name = 'Authorized Owner');
        insert new List<Account>{ business, party };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = env.Id, Account__c = business.Id),
                    new Envelope_Content__c(Envelope__c = env.Id, Account__c = party.Id),
                    new Envelope_Content__c(
                        Envelope__c = env.Id,
                        Wizard_Financial_Account__c = account.Id
                    )
                    };
                        insert new Account_Account_Relationship__c(
                            Account__c = business.Id,
                            Related_Account__c = party.Id,
                            Roles__c = 'Authorized Person',
                            RecordTypeId = fiduciaryRecordTypeId(),
                            Active__c = true
                        );
        insert new Financial_Account_Role__c(
            Financial_Account__c = account.Id,
            Account__c = party.Id,
            Role__c = 'Primary Owner'
        );
        
        Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ business.Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(1,
                            [SELECT Count() FROM Account WHERE Id = :party.Id],
                            'An owner of this envelope\'s account is still needed here.');
        System.assertEquals(1,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Envelope__c = :env.Id AND Account__c = :party.Id],
                            'It keeps its envelope link on the strength of the ownership role.');
    }
    
    // A stranded party held by another envelope leaves this one but is never deleted.
    @IsTest
    static void testRemoveMember_StrandedPartyUnlinkedButKeptForAnotherEnvelope() {
        Envelope__c envA = [SELECT Id FROM Envelope__c LIMIT 1];
        Envelope__c envB = makeSecondEnvelope();
        Account trust = new Account(Name = 'Trust Being Removed');
        Account party = new Account(Name = 'Party Elsewhere Too');
        insert new List<Account>{ trust, party };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = envA.Id, Account__c = trust.Id),
                    new Envelope_Content__c(Envelope__c = envA.Id, Account__c = party.Id),
                    new Envelope_Content__c(Envelope__c = envB.Id, Account__c = party.Id)
                    };
                        insert new Account_Account_Relationship__c(
                            Account__c = trust.Id,
                            Related_Account__c = party.Id,
                            Roles__c = 'Trustee',
                            RecordTypeId = fiduciaryRecordTypeId(),
                            Active__c = true
                        );
        
        Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ trust.Id },
            envA.Id
        );
        Test.stopTest();
        
        System.assertEquals(1,
                            [SELECT Count() FROM Account WHERE Id = :party.Id],
                            'Another envelope holds the party, so the record must survive.');
        System.assertEquals(0,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Envelope__c = :envA.Id AND Account__c = :party.Id],
                            'It still leaves the envelope whose entity it served.');
        System.assertEquals(1,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Envelope__c = :envB.Id AND Account__c = :party.Id],
                            'The other envelope keeps its link.');
    }
    
    // The relationship map owns any row carrying a Reciprocal Role, so a party holding one is never
    // deleted by a removal here. The mapped row is on a pair outside this envelope, which is where the
    // map's own relationships live; the cleanup never narrows on record type when it asks what is
    // still in use, so any such row counts.
    @IsTest
    static void testRemoveMember_StrandedPartyKeptWhenTheRelationshipMapOwnsIt() {
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        Account trust = new Account(Name = 'Trust With Mapped Party');
        Account party = new Account(Name = 'Mapped Party');
        Account mappedPeer = new Account(Name = 'Peer Outside The Envelope');
        insert new List<Account>{ trust, party, mappedPeer };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = env.Id, Account__c = trust.Id),
                    new Envelope_Content__c(Envelope__c = env.Id, Account__c = party.Id)
                    };
                        Reciprocal_Role__c mappedRole = new Reciprocal_Role__c(Role__c = 'Friend');
        insert mappedRole;
        insert new List<Account_Account_Relationship__c>{
            new Account_Account_Relationship__c(
                Account__c = trust.Id,
                Related_Account__c = party.Id,
                Roles__c = 'Trustee',
                RecordTypeId = fiduciaryRecordTypeId(),
                Active__c = true
            ),
                new Account_Account_Relationship__c(
                    Account__c = mappedPeer.Id,
                    Related_Account__c = party.Id,
                    Reciprocal_Role__c = mappedRole.Id,
                    RecordTypeId = fiduciaryRecordTypeId(),
                    Active__c = true
                )
                };
                    
                    Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ trust.Id },
            env.Id
        );
        Test.stopTest();
        
        System.assertEquals(1,
                            [SELECT Count() FROM Account WHERE Id = :party.Id],
                            'A party the relationship map still points at must not be deleted.');
        System.assertEquals(1,
                            [SELECT Count() FROM Account_Account_Relationship__c
                             WHERE Related_Account__c = :party.Id AND Reciprocal_Role__c != NULL],
                            'The mapped relationship should be left exactly as it was.');
        System.assertEquals(0,
                            [SELECT Count() FROM Envelope_Content__c
                             WHERE Envelope__c = :env.Id AND Account__c = :party.Id],
                            'It is still unlinked from the envelope whose entity it served.');
    }
    
    // Relationship cleanup is scoped to this envelope's entities, so a role held on an entity that
    // only another envelope uses survives.
    @IsTest
    static void testRemoveMember_LeavesRolesOnEntitiesOutsideThisEnvelope() {
        Envelope__c envA = [SELECT Id FROM Envelope__c LIMIT 1];
        Envelope__c envB = makeSecondEnvelope();
        Account trustA = new Account(Name = 'Trust A');
        Account trustB = new Account(Name = 'Trust B');
        Account person = new Account(Name = 'Dual Role Person');
        insert new List<Account>{ trustA, trustB, person };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = envA.Id, Account__c = trustA.Id),
                    new Envelope_Content__c(Envelope__c = envA.Id, Account__c = person.Id),
                    new Envelope_Content__c(Envelope__c = envB.Id, Account__c = trustB.Id),
                    new Envelope_Content__c(Envelope__c = envB.Id, Account__c = person.Id)
                    };
                        insert new List<Account_Account_Relationship__c>{
                            new Account_Account_Relationship__c(
                                Account__c = trustA.Id,
                                Related_Account__c = person.Id,
                                Roles__c = 'Trustee',
                                RecordTypeId = fiduciaryRecordTypeId(),
                                Active__c = true
                            ),
                                new Account_Account_Relationship__c(
                                    Account__c = trustB.Id,
                                    Related_Account__c = person.Id,
                                    Roles__c = 'Grantor',
                                    RecordTypeId = fiduciaryRecordTypeId(),
                                    Active__c = true
                                )
                                };
                                    
                                    Test.startTest();
        WizardEnvelopeStateService.removeHouseholdMembers(
            new List<Id>{ person.Id },
            envB.Id
        );
        Test.stopTest();
        
        System.assertEquals(1,
                            [SELECT Count() FROM Account_Account_Relationship__c
                             WHERE Account__c = :trustA.Id AND Related_Account__c = :person.Id],
                            'A role on an entity outside this envelope must be left alone.');
        System.assertEquals(0,
                            [SELECT Count() FROM Account_Account_Relationship__c
                             WHERE Account__c = :trustB.Id AND Related_Account__c = :person.Id],
                            'The role on this envelope\'s entity should be removed.');
        System.assertEquals(1,
                            [SELECT Count() FROM Account WHERE Id = :person.Id],
                            'The person is still used by the other envelope.');
    }
    
    @isTest
    static void testGetHouseholdMembersAndAccounts_ExcludesUnsubmittedUnlinkedRecords() {
        // The household roster from @testSetup is entirely unsubmitted and linked to no envelope, so
        // none of it belongs to this envelope's outline: those records are another envelope's drafts.
        Account household = [
            SELECT Id
            FROM Account
            WHERE Name='Test Household'
            LIMIT 1
        ];
        
        Envelope__c env = [
            SELECT Id
            FROM Envelope__c
            LIMIT 1
        ];
        
        Test.startTest();
        
        WizardEnvelopeStateService.HouseholdMembersAndAccountsWrapper wrapper =
            WizardEnvelopeStateService.getHouseholdMembersAndAccounts(
                household.Id,
                env.Id
            );
        
        Test.stopTest();
        
        System.assertNotEquals(null, wrapper);
        System.assertEquals(0, wrapper.clients.size(),
                            'An unsubmitted household member this envelope does not hold should not be returned.');
        System.assertEquals(0, wrapper.accounts.size(),
                            'An unsubmitted Financial Account this envelope does not hold should not be returned.');
        System.assertEquals(0, wrapper.services.size(),
                            'An unsubmitted Service this envelope does not hold should not be returned.');
        System.assertEquals(0, [
            SELECT COUNT()
            FROM Envelope_Content__c
            WHERE Envelope__c = :env.Id
        ], 'Reading the household should not link any of it to the envelope.');
    }
    
    @isTest
    static void testGetHouseholdMembersAndAccounts_IncludesSubmittedHouseholdRecords() {
        // A submitted record is part of the household's settled state, so every envelope shows it —
        // without needing a link of its own.
        Account household = [SELECT Id FROM Account WHERE Name = 'Test Household' LIMIT 1];
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        
        List<Account> members = [SELECT Id, Submitted__c FROM Account WHERE Name = 'Member 1'];
        members[0].Submitted__c = true;
        update members;
        
        Financial_Account__c finAccount = [SELECT Id, Submitted__c FROM Financial_Account__c WHERE Name = 'FA 1' LIMIT 1];
        finAccount.Submitted__c = true;
        update finAccount;
        
        Test.startTest();
        WizardEnvelopeStateService.HouseholdMembersAndAccountsWrapper wrapper =
            WizardEnvelopeStateService.getHouseholdMembersAndAccounts(household.Id, env.Id);
        Test.stopTest();
        
        
        System.assertEquals(1, wrapper.accounts.size(),
                            'The submitted Financial Account should be returned.');
        System.assertEquals(0, [
            SELECT COUNT()
            FROM Envelope_Content__c
            WHERE Envelope__c = :env.Id
        ], 'A submitted record is shown without being linked to the envelope.');
    }
    
    @isTest
    static void testGetHouseholdMembersAndAccounts_PersonMemberViaAAR() {
        // New wizard-created person members are linked to the household via
        // Account_Account_Relationship__c instead of AccountContactRelation; the
        // read path must surface them as clients. The envelope link is what puts the
        // member in scope, and saveEntity creates it when the member is added.
        Account household = [SELECT Id FROM Account WHERE Name = 'Test Household' LIMIT 1];
        Envelope__c env = [SELECT Id FROM Envelope__c LIMIT 1];
        
        Account person = new Account(
            FirstName = 'Aar',
            LastName = 'Client',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount').getRecordTypeId()
        );
        insert person;
        insert new Account_Account_Relationship__c(
            Account__c = household.Id,
            Related_Account__c = person.Id,
            Association_Type__c = 'Member',
            Active__c = true
        );
        insert new Envelope_Content__c(Envelope__c = env.Id, Account__c = person.Id);
        
        Test.startTest();
        WizardEnvelopeStateService.HouseholdMembersAndAccountsWrapper wrapper =
            WizardEnvelopeStateService.getHouseholdMembersAndAccounts(household.Id, env.Id);
        Test.stopTest();
        
        Boolean found = false;
        for (WizardEnvelopeStateService.MemberData client : wrapper.clients) {
            if (client.id == String.valueOf(person.Id)) {
                found = true;
            }
        }
        System.assert(found,
                      'A person member linked via Account_Account_Relationship__c should be returned as a client.');
    }
    @isTest
    static void testSaveAccountInfo() {
        
        // Create Financial Account
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Test Account'
            // Add any required fields here
        );
        insert fa;
        
        Map<String, Object> data = new Map<String, Object>();
        data.put('Id', fa.Id);
        data.put('Name', 'Updated Account');
        
        Test.startTest();
        WizardEnvelopeStateService.saveAccountInfo(data);
        Test.stopTest();
        
        Financial_Account__c updatedFA = [
            SELECT Id, Name
            FROM Financial_Account__c
            WHERE Id = :fa.Id
        ];
        
        System.assertEquals('Updated Account', updatedFA.Name);
    }
    
    // ---------------------------------------------------------
    // saveAccountCaseInfo — the Case half of a mixed account interview
    // ---------------------------------------------------------
    
    // Note the addressing: 'Id' carries the FINANCIAL ACCOUNT id, not the Case id. The wizard Case is
    // resolved from it by (account, Wizard origin, Account Opening type).
    private static Map<String, Object> caseData(Id faId, String description) {
        return new Map<String, Object>{ 'Id' => faId, 'Description' => description };
            }
    
    private static Case wizardCaseFor(Id faId) {
        return [
            SELECT Id, Subject, Origin, Type, Description, Submitted__c,
            FinServ__Household__c, Wizard_Financial_Account__c
            FROM Case
            WHERE Wizard_Financial_Account__c = :faId
            LIMIT 1
        ];
    }
    
    // An account that existed on the household before the envelope has no wizard Case, so answering
    // a Case-targeted question opens one — and links it to the envelope like the create path does.
    @IsTest
    static void saveAccountCaseInfoOpensAndLinksACaseForAnAccountWithoutOne() {
        Account household = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Pre-existing Account',
            Household__c = household.Id
        );
        insert fa;
        Envelope__c envelope = new Envelope__c(
            Name = 'Case Info Envelope', Status__c = 'In Progress');
        insert envelope;
        
        Test.startTest();
        WizardEnvelopeStateService.saveAccountCaseInfo(
            caseData(fa.Id, 'An answer'), envelope.Id);
        Test.stopTest();
        
        Case opened = wizardCaseFor(fa.Id);
        Assert.areEqual('New Financial Account', opened.Subject);
        Assert.areEqual('Wizard', opened.Origin);
        Assert.areEqual('Account Opening', opened.Type);
        Assert.areEqual('An answer', opened.Description);
        Assert.isFalse(opened.Submitted__c);
        Assert.areEqual(1,
                        [SELECT COUNT() FROM Envelope_Content__c WHERE Case__c = :opened.Id],
                        'A case opened on demand still joins the envelope.');
    }
    
    @IsTest
    static void saveAccountCaseInfoUpdatesTheExistingCase() {
        Financial_Account__c fa = new Financial_Account__c(Name = 'Account With Case');
        insert fa;
        insert new Case(
            Subject = 'New Financial Account',
            Origin = 'Wizard',
            Type = 'Account Opening',
            Wizard_Financial_Account__c = fa.Id,
            Description = 'First answer'
        );
        
        Test.startTest();
        WizardEnvelopeStateService.saveAccountCaseInfo(
            caseData(fa.Id, 'Second answer'), null);
        Test.stopTest();
        
        Assert.areEqual(1, [SELECT COUNT() FROM Case WHERE Wizard_Financial_Account__c = :fa.Id],
                        'The existing case is updated, not duplicated.');
        Assert.areEqual('Second answer', wizardCaseFor(fa.Id).Description);
    }
    
    // Creation is gated on the payload carrying a filled answer, so neither an id-only payload nor a
    // draft whose answers have all been cleared conjures an empty Case.
    @IsTest
    static void saveAccountCaseInfoDoesNotOpenACaseWithoutAnswers() {
        Financial_Account__c fa = new Financial_Account__c(Name = 'Untouched Account');
        insert fa;
        
        Test.startTest();
        WizardEnvelopeStateService.saveAccountCaseInfo(
            new Map<String, Object>{ 'Id' => fa.Id }, null);
        WizardEnvelopeStateService.saveAccountCaseInfo(caseData(fa.Id, null), null);
        Test.stopTest();
        
        Assert.areEqual(0, [SELECT COUNT() FROM Case WHERE Wizard_Financial_Account__c = :fa.Id],
                        'Neither an id-only nor an all-blank payload opens a case.');
    }
    
    @IsTest
    static void saveAccountCaseInfoRequiresAnId() {
        try {
            WizardEnvelopeStateService.saveAccountCaseInfo(
                new Map<String, Object>{ 'Description' => 'orphan' }, null);
            Assert.fail('A payload without an Id must throw.');
        } catch (AuraHandledException expected) {
        }
    }
    
    // ---------------------------------------------------------
    // getHouseholdMembersAndAccounts — the envelope's Account Action Items
    // ---------------------------------------------------------
    
    private static Case wizardCase(String caseType, Id faId) {
        return new Case(
            Subject = caseType,
            Type = caseType,
            Origin = 'Wizard',
            Wizard_Financial_Account__c = faId
        );
    }
    
    // Action items are read from the envelope's own Envelope_Content__c links — deliberately not the
    // "linked OR submitted" rule the household's own records use, because an action item belongs to
    // the one envelope that raised it. The account-opening case is a Financial Account's own
    // interview, not an outline row, so it never appears here either.
    @IsTest
    static void householdReadReturnsThisEnvelopesActionCasesOnly() {
        Account household = [SELECT Id FROM Account WHERE Name = 'Test Household' LIMIT 1];
        Financial_Account__c fa = new Financial_Account__c(
            Name = 'Serviced Account',
            Household__c = household.Id,
            Submitted__c = true
        );
        insert fa;
        
        Envelope__c envelope = new Envelope__c(Name = 'Action Envelope', Status__c = 'In Progress');
        Envelope__c other = new Envelope__c(Name = 'Other Envelope', Status__c = 'In Progress');
        insert new List<Envelope__c>{ envelope, other };
            
            Case action = wizardCase('Additional Funding', fa.Id);
        Case opening = wizardCase('Account Opening', fa.Id);
        Case elsewhere = wizardCase('Account Closure', fa.Id);
        insert new List<Case>{ action, opening, elsewhere };
            insert new List<Envelope_Content__c>{
                new Envelope_Content__c(Envelope__c = envelope.Id, Case__c = action.Id),
                    new Envelope_Content__c(Envelope__c = envelope.Id, Case__c = opening.Id),
                    new Envelope_Content__c(Envelope__c = other.Id, Case__c = elsewhere.Id)
                    };
                        
                        Test.startTest();
        WizardEnvelopeStateService.HouseholdMembersAndAccountsWrapper wrapper =
            WizardEnvelopeStateService.getHouseholdMembersAndAccounts(household.Id, envelope.Id);
        Test.stopTest();
        
        Assert.areEqual(1, wrapper.actionCases.size(),
                        'Only this envelope\'s action cases are returned, and never the opening case.');
        WizardEnvelopeStateService.ActionCaseData returned = wrapper.actionCases[0];
        Assert.areEqual(action.Id, returned.id);
        Assert.areEqual('Additional Funding', returned.caseType);
        Assert.areEqual(fa.Id, returned.financialAccountId);
        Assert.areEqual('Serviced Account', returned.financialAccountName);
        Assert.isFalse(returned.submitted);
    }
    
    // Additional Funding cases opened before that branch was completed carry no account lookup, and
    // reading through a null relationship throws.
    @IsTest
    static void householdReadToleratesAnActionCaseWithNoAccount() {
        Account household = [SELECT Id FROM Account WHERE Name = 'Test Household' LIMIT 1];
        Envelope__c envelope = new Envelope__c(Name = 'Orphan Envelope', Status__c = 'In Progress');
        insert envelope;
        
        Case orphan = wizardCase('Additional Funding', null);
        insert orphan;
        insert new Envelope_Content__c(Envelope__c = envelope.Id, Case__c = orphan.Id);
        
        Test.startTest();
        WizardEnvelopeStateService.HouseholdMembersAndAccountsWrapper wrapper =
            WizardEnvelopeStateService.getHouseholdMembersAndAccounts(household.Id, envelope.Id);
        Test.stopTest();
        
        Assert.areEqual(1, wrapper.actionCases.size());
        Assert.isNull(wrapper.actionCases[0].financialAccountId);
        Assert.isNull(wrapper.actionCases[0].financialAccountName,
                      'A missing account resolves to a null name rather than throwing.');
    }
    
    // ---------------------------------------------------------
    // saveProposedCase
    // ---------------------------------------------------------
    
    static Map<String, Object> proposedCaseOriginals() {
        return new Map<String, Object>{
            'FirstName' => 'Janet',
                'LastName' => 'Prior',
                'BillingCity' => 'Old Town',
                'BillingStateCode' => 'UT',
                'Investment_Objectives__c' => new List<Object>{ 'Growth', 'Income' }
        };
            }
    
    @IsTest
    static void saveProposedCaseCreatesReviewCase() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        
        Test.startTest();
        WizardEnvelopeStateService.saveProposedCase(
            proposedCaseOriginals(),
            new Map<String, Object>{
                'FirstName' => 'Janette',
                    'BillingCity' => 'New Town',
                    'BillingStateCode' => 'AZ',
                    'Investment_Objectives__c' => new List<Object>{ 'Growth', 'Speculation' },
                        'BillingStreet' => 'x'.repeat(300)
                        },
            member.Id
        );
        Test.stopTest();
        
        Case created = [
            SELECT Status, Origin, Subject, DoNotCalc__c, RecordType.DeveloperName,
            Original_First_Name__c, Proposed_First_Name__c,
            Original_Last_Name__c, Proposed_Last_Name__c,
            Original_Physical_City__c, Proposed_Physical_City__c,
            Original_Physical_State__c, Proposed_Physical_State__c,
            Original_Investment_Objectives__c, Proposed_Investment_Objectives__c,
            Proposed_Physical_Street__c
            FROM Case
            WHERE AccountId = :member.Id
        ];
        System.assertEquals('Account_Servicing_Principal_Review', created.RecordType.DeveloperName);
        System.assertEquals('New', created.Status);
        System.assertEquals('Wizard', created.Origin);
        System.assertEquals('Person Account Requested Changes', created.Subject);
        System.assertEquals(true, created.DoNotCalc__c);
        System.assertEquals('Janet', created.Original_First_Name__c);
        System.assertEquals('Janette', created.Proposed_First_Name__c);
        System.assertEquals('Prior', created.Original_Last_Name__c);
        System.assertEquals(null, created.Proposed_Last_Name__c,
                            'Fields absent from the proposal should stay empty.');
        System.assertEquals('Old Town', created.Original_Physical_City__c);
        System.assertEquals('New Town', created.Proposed_Physical_City__c);
        System.assertEquals('UT', created.Original_Physical_State__c);
        System.assertEquals('AZ', created.Proposed_Physical_State__c);
        System.assertEquals('Growth; Income', created.Original_Investment_Objectives__c,
                            'Multi-select list values should be joined into text.');
        System.assertEquals('Growth; Speculation', created.Proposed_Investment_Objectives__c);
        System.assert(created.Proposed_Physical_Street__c.length() <= 100,
                      'Values longer than the Case field should be clipped, not fail the save.');
    }
    
    @IsTest
    static void saveProposedCaseReusesOpenCase() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        WizardEnvelopeStateService.saveProposedCase(
            proposedCaseOriginals(),
            new Map<String, Object>{ 'FirstName' => 'Janette' },
            member.Id
        );
        
        Test.startTest();
        WizardEnvelopeStateService.saveProposedCase(
            new Map<String, Object>{ 'FirstName' => 'Drifted Since' },
            new Map<String, Object>{ 'LastName' => 'Newer' },
            member.Id
        );
        Test.stopTest();
        
        List<Case> cases = [
            SELECT Original_First_Name__c, Proposed_First_Name__c, Proposed_Last_Name__c
            FROM Case
            WHERE AccountId = :member.Id
        ];
        System.assertEquals(1, cases.size(), 'Repeated edits should accumulate on the one open case.');
        System.assertEquals('Janet', cases[0].Original_First_Name__c,
                            'The original snapshot should not change while the case is open.');
        System.assertEquals('Janette', cases[0].Proposed_First_Name__c);
        System.assertEquals('Newer', cases[0].Proposed_Last_Name__c);
    }
    
    @IsTest
    static void saveProposedCaseOpensNewCaseWhenPriorClosed() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        WizardEnvelopeStateService.saveProposedCase(
            proposedCaseOriginals(),
            new Map<String, Object>{ 'FirstName' => 'Janette' },
            member.Id
        );
        Case existing = [SELECT Id FROM Case WHERE AccountId = :member.Id];
        existing.Status = [SELECT MasterLabel FROM CaseStatus WHERE IsClosed = true LIMIT 1].MasterLabel;
        update existing;
        
        Test.startTest();
        WizardEnvelopeStateService.saveProposedCase(
            proposedCaseOriginals(),
            new Map<String, Object>{ 'FirstName' => 'Janot' },
            member.Id
        );
        Test.stopTest();
        
        System.assertEquals(2, [SELECT COUNT() FROM Case WHERE AccountId = :member.Id],
                            'A closed review case should not be reopened; a fresh one is created.');
    }
    
    @IsTest
    static void saveProposedCaseIgnoresEmptyInput() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        
        Test.startTest();
        WizardEnvelopeStateService.saveProposedCase(proposedCaseOriginals(), new Map<String, Object>(), member.Id);
        WizardEnvelopeStateService.saveProposedCase(proposedCaseOriginals(), null, member.Id);
        WizardEnvelopeStateService.saveProposedCase(
            proposedCaseOriginals(), new Map<String, Object>{ 'FirstName' => 'X' }, null);
        Test.stopTest();
        
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE AccountId = :member.Id],
                            'No case should be created without a real proposal and account.');
    }
    
    @IsTest
    static void saveAccountInfoCoercesClientStrings() {
        Financial_Account__c fa = new Financial_Account__c(Name = 'Coercion FA');
        insert fa;
        
        // lightning-input emits numbers as strings; the put loop must coerce, not throw
        // "Illegal assignment from String to Decimal" (the Source of Funds autosave 500).
        Test.startTest();
        WizardEnvelopeStateService.saveAccountInfo(new Map<String, Object>{
            'Id' => fa.Id,
                'Source_of_Funds_Amount__c' => '1000',
                'Year_1_Percent__c' => '50'
                });
        Test.stopTest();
        
        Financial_Account__c updated = [
            SELECT Source_of_Funds_Amount__c, Year_1_Percent__c
            FROM Financial_Account__c WHERE Id = :fa.Id
        ];
        System.assertEquals(1000, updated.Source_of_Funds_Amount__c,
                            'A string-typed currency value from the client should save.');
        System.assertEquals(50, updated.Year_1_Percent__c,
                            'A string-typed percent value from the client should save.');
    }
    
    // ---------------------------------------------------------
    // saveServiceInfo
    // ---------------------------------------------------------
    
    @IsTest
    static void saveServiceInfoWritesFieldsWithCoercion() {
        Service__c svc = new Service__c(Name = 'Test Service');
        insert svc;
        
        Test.startTest();
        WizardEnvelopeStateService.saveServiceInfo(new Map<String, Object>{
            'Id' => svc.Id,
                'Start_Date__c' => '2026-08-01',
                'Hourly_Rate__c' => 250
                });
        Test.stopTest();
        
        Service__c updated = [SELECT Start_Date__c, Hourly_Rate__c FROM Service__c WHERE Id = :svc.Id];
        System.assertEquals(Date.newInstance(2026, 8, 1), updated.Start_Date__c,
                            'ISO date strings from the client should coerce to Date.');
        System.assertEquals(250, updated.Hourly_Rate__c);
    }
    
    @IsTest
    static void saveServiceInfoRequiresId() {
        Boolean threw = false;
        try {
            WizardEnvelopeStateService.saveServiceInfo(new Map<String, Object>{ 'Name' => 'x' });
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'A payload without an Id should be rejected.');
    }
    
    // ---------------------------------------------------------
    // Format validation (WizardFieldValidator backstop)
    // ---------------------------------------------------------
    
    @IsTest
    static void saveAccountInfoRejectsOutOfRangePercent() {
        Financial_Account__c fa = new Financial_Account__c(Name = 'Bounded FA');
        insert fa;
        
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            new Envelope_Field__mdt(
                Object__c = 'Financial_Account__c',
                Field_API__c = 'Year_1_Percent__c',
                Label__c = 'Year 1 %',
                Pattern_Error__c = 'Enter a percentage between 0 and 100.',
                Min__c = '0',
                Max__c = '100'
            )
                };
                    
                    Test.startTest();
        try {
            WizardEnvelopeStateService.saveAccountInfo(new Map<String, Object>{
                'Id' => fa.Id, 'Year_1_Percent__c' => 150 });
            System.assert(false, 'An out-of-range percent should block the update.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Year 1 %'), e.getMessage());
        }
        
        WizardEnvelopeStateService.saveAccountInfo(new Map<String, Object>{
            'Id' => fa.Id, 'Year_1_Percent__c' => 50 });
        Test.stopTest();
        
        System.assertEquals(50,
                            [SELECT Year_1_Percent__c FROM Financial_Account__c WHERE Id = :fa.Id].Year_1_Percent__c,
                            'An in-range percent should save.');
    }
    
    @IsTest
    static void saveProposedCaseRejectsMalformedProposedValue() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            new Envelope_Field__mdt(
                Object__c = 'Account',
                Field_API__c = 'Tax_ID__c',
                Label__c = 'Tax ID',
                Pattern__c = '^\\d{3}-\\d{2}-\\d{4}$',
                Pattern_Error__c = 'Enter a Social Security Number as XXX-XX-XXXX.'
            )
                };
                    
                    Test.startTest();
        try {
            WizardEnvelopeStateService.saveProposedCase(
                proposedCaseOriginals(),
                new Map<String, Object>{ 'Tax_ID__c' => 'garbage' },
                member.Id
            );
            System.assert(false, 'A malformed proposed Tax ID should block the change request.');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Tax ID'), e.getMessage());
        }
        Test.stopTest();
        
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE AccountId = :member.Id],
                            'No review case should be created for an invalid proposal.');
    }
    
    @IsTest
    static void saveProposedCaseNeverValidatesOriginals() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        
        WizardFieldValidator.ruleRowsOverride = new List<Envelope_Field__mdt>{
            new Envelope_Field__mdt(
                Object__c = 'Account',
                Field_API__c = 'Tax_ID__c',
                Label__c = 'Tax ID',
                Pattern__c = '^\\d{3}-\\d{2}-\\d{4}$',
                Pattern_Error__c = 'Enter a Social Security Number as XXX-XX-XXXX.'
            )
                };
                    
                    // Originals carry a legacy nonconforming Tax ID; only the proposal is validated.
                    Map<String, Object> originals = proposedCaseOriginals();
        originals.put('Tax_ID__c', '35423242');
        
        Test.startTest();
        WizardEnvelopeStateService.saveProposedCase(
            originals,
            new Map<String, Object>{ 'FirstName' => 'Janette' },
            member.Id
        );
        Test.stopTest();
        
        System.assertEquals(1, [SELECT COUNT() FROM Case WHERE AccountId = :member.Id],
                            'Legacy bad data in the original snapshot must never block a valid proposal.');
    }

    // ---------------------------------------------------------
    // Member action items: saveProposedCaseFields / getProposedCaseValues
    // ---------------------------------------------------------

    // A member action item's review case, as EnvelopeActionCaseController raises it: the original
    // snapshot is already taken and the Type marks it as an action item rather than an inline
    // proposed-change case.
    static Case insertMemberActionCase(Id memberId) {
        Case actionCase = new Case(
            AccountId = memberId,
            Type = 'Edit Individual',
            Origin = 'Wizard',
            Status = 'New',
            RecordTypeId = WizardEnvelopeStateService.principalReviewRecordTypeId()
        );
        WizardEnvelopeStateService.seedOriginalValues(actionCase, proposedCaseOriginals());
        insert actionCase;
        return actionCase;
    }

    @IsTest
    static void seedOriginalValuesWritesOnlyTheOriginalHalf() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];

        Test.startTest();
        Case actionCase = insertMemberActionCase(member.Id);
        Test.stopTest();

        Case created = [
            SELECT Original_First_Name__c, Proposed_First_Name__c,
            Original_Investment_Objectives__c, Proposed_Investment_Objectives__c
            FROM Case WHERE Id = :actionCase.Id
        ];
        System.assertEquals('Janet', created.Original_First_Name__c);
        System.assertEquals('Growth; Income', created.Original_Investment_Objectives__c,
                            'Multi-select list values should be joined into text.');
        System.assertEquals(null, created.Proposed_First_Name__c,
                            'Seeding the baseline must not populate the proposed half.');
        System.assertEquals(null, created.Proposed_Investment_Objectives__c);
    }

    @IsTest
    static void saveProposedCaseFieldsLeavesTheSnapshotFrozen() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);

        Test.startTest();
        WizardEnvelopeStateService.saveProposedCaseFields(
            actionCase.Id,
            member.Id,
            new Map<String, Object>{
                'FirstName' => 'Janette',
                    'BillingCity' => 'New Town'
                    }
        );
        Test.stopTest();

        Case updated = [
            SELECT Original_First_Name__c, Proposed_First_Name__c,
            Original_Physical_City__c, Proposed_Physical_City__c,
            Original_Last_Name__c, Proposed_Last_Name__c
            FROM Case WHERE Id = :actionCase.Id
        ];
        System.assertEquals('Janet', updated.Original_First_Name__c,
                            'The baseline must not move when a proposal is recorded.');
        System.assertEquals('Janette', updated.Proposed_First_Name__c);
        System.assertEquals('Old Town', updated.Original_Physical_City__c);
        System.assertEquals('New Town', updated.Proposed_Physical_City__c);
        System.assertEquals('Prior', updated.Original_Last_Name__c);
        System.assertEquals(null, updated.Proposed_Last_Name__c,
                            'Fields absent from the proposal should stay empty.');
        System.assertEquals(1, [SELECT COUNT() FROM Case WHERE AccountId = :member.Id],
                            'Recording a proposal must not open a second case.');
    }

    @IsTest
    static void saveProposedCaseFieldsIgnoresValuesMatchingTheSnapshot() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);

        // The interview opens prefilled with the member's current values, so an untouched form
        // resends the whole snapshot. None of it is a change.
        Test.startTest();
        WizardEnvelopeStateService.saveProposedCaseFields(
            actionCase.Id,
            member.Id,
            proposedCaseOriginals()
        );
        Test.stopTest();

        Case updated = [
            SELECT Proposed_First_Name__c, Proposed_Last_Name__c, Proposed_Physical_City__c,
            Proposed_Physical_State__c, Proposed_Investment_Objectives__c,
            Original_First_Name__c
            FROM Case WHERE Id = :actionCase.Id
        ];
        System.assertEquals(null, updated.Proposed_First_Name__c,
                            'A value matching the snapshot is not a proposed change.');
        System.assertEquals(null, updated.Proposed_Last_Name__c);
        System.assertEquals(null, updated.Proposed_Physical_City__c);
        System.assertEquals(null, updated.Proposed_Physical_State__c);
        System.assertEquals(null, updated.Proposed_Investment_Objectives__c,
                            'A multi-select resent unchanged is not a proposed change either.');
        System.assertEquals('Janet', updated.Original_First_Name__c,
                            'The baseline is untouched by a no-op save.');
    }

    @IsTest
    static void saveProposedCaseFieldsClearsAValueEditedBackToTheOriginal() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);
        WizardEnvelopeStateService.saveProposedCaseFields(
            actionCase.Id,
            member.Id,
            new Map<String, Object>{ 'FirstName' => 'Janette' }
        );
        System.assertEquals('Janette',
                            [SELECT Proposed_First_Name__c FROM Case WHERE Id = :actionCase.Id]
                            .Proposed_First_Name__c,
                            'The edit should be proposed first.');

        Test.startTest();
        WizardEnvelopeStateService.saveProposedCaseFields(
            actionCase.Id,
            member.Id,
            new Map<String, Object>{ 'FirstName' => 'Janet' }
        );
        Test.stopTest();

        Case updated = [
            SELECT Original_First_Name__c, Proposed_First_Name__c
            FROM Case WHERE Id = :actionCase.Id
        ];
        System.assertEquals(null, updated.Proposed_First_Name__c,
                            'Undoing an edit should clear the proposal, not re-state the original.');
        System.assertEquals('Janet', updated.Original_First_Name__c);
    }

    @IsTest
    static void saveProposedCaseFieldsProposesAValueOverAnEmptyOriginal() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);

        // Occupation__c is absent from the snapshot fixture, so its original is empty. Filling an
        // empty field is a change like any other.
        Test.startTest();
        WizardEnvelopeStateService.saveProposedCaseFields(
            actionCase.Id,
            member.Id,
            new Map<String, Object>{ 'Occupation__c' => 'Engineer' }
        );
        Test.stopTest();

        Case updated = [
            SELECT Original_Occupation__c, Proposed_Occupation__c
            FROM Case WHERE Id = :actionCase.Id
        ];
        System.assertEquals(null, updated.Original_Occupation__c);
        System.assertEquals('Engineer', updated.Proposed_Occupation__c);
    }

    @IsTest
    static void saveProposedCaseIgnoresMemberActionCases() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);

        // The inline proposed-change path must not adopt an action item's case: it is the same
        // record type on the same member, but it carries its own snapshot and its own review.
        Test.startTest();
        WizardEnvelopeStateService.saveProposedCase(
            new Map<String, Object>{ 'FirstName' => 'Inline Original' },
            new Map<String, Object>{ 'FirstName' => 'Inline Proposed' },
            member.Id
        );
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Case WHERE AccountId = :member.Id],
                            'The inline path should open its own case, not reuse the action item.');
        Case untouched = [
            SELECT Original_First_Name__c, Proposed_First_Name__c
            FROM Case WHERE Id = :actionCase.Id
        ];
        System.assertEquals('Janet', untouched.Original_First_Name__c);
        System.assertEquals(null, untouched.Proposed_First_Name__c,
                            'The action item must be left exactly as it was.');
    }

    @IsTest
    static void getProposedCaseValuesPrefersProposedThenOriginal() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);
        WizardEnvelopeStateService.saveProposedCaseFields(
            actionCase.Id,
            member.Id,
            new Map<String, Object>{ 'FirstName' => 'Janette' }
        );

        Test.startTest();
        Map<Id, Map<String, Object>> values =
            WizardEnvelopeStateService.getProposedCaseValues(new List<Id>{ actionCase.Id });
        Test.stopTest();

        Map<String, Object> caseValues = values.get(actionCase.Id);
        System.assertNotEquals(null, caseValues, 'The case should be present in the result.');
        System.assertEquals('Janette', caseValues.get('FirstName'),
                            'An edited field should read back as its proposed value.');
        System.assertEquals('Prior', caseValues.get('LastName'),
                            'An untouched field should fall back to the original snapshot.');
        System.assertEquals('Old Town', caseValues.get('BillingCity'));
        System.assertEquals(false, caseValues.containsKey('Occupation__c'),
                            'A field with neither half set should be absent, not null.');
    }

    // The interview reading these back is the member's Account form, so it expects the shapes an
    // Account read returns — a list for a multi-select, not the joined text the case stores. A raw
    // string reaches a dual listbox as an unusable value and the field renders empty.
    @IsTest
    static void getProposedCaseValuesTypesMultiSelectsAsLists() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);

        Test.startTest();
        Map<Id, Map<String, Object>> values =
            WizardEnvelopeStateService.getProposedCaseValues(new List<Id>{ actionCase.Id });
        Test.stopTest();

        Object objectives = values.get(actionCase.Id).get('Investment_Objectives__c');
        System.assert(objectives instanceof List<String>,
                      'A multi-select must read back as a list, not the joined text.');
        System.assertEquals(new List<String>{ 'Growth', 'Income' }, (List<String>) objectives,
                            'The joined text splits back into its selected values, untrimmed spaces removed.');
    }

    // A numeric field reaches the snapshot as a Decimal ('500000.00') while the interview sends it as
    // typed ('500000'). Comparing those as text would propose an untouched number on every save.
    // The baseline is written in whichever form the org's own field type produces, so this holds
    // whether the source field is numeric or text.
    @IsTest
    static void saveProposedCaseFieldsComparesNumbersNumerically() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Schema.SObjectField sourceField = Account.SObjectType.getDescribe()
            .fields.getMap().get('approximate_net_worth__c');
        Boolean isNumeric = sourceField != null && new Set<Schema.DisplayType>{
            Schema.DisplayType.CURRENCY, Schema.DisplayType.DOUBLE,
            Schema.DisplayType.PERCENT, Schema.DisplayType.INTEGER
        }.contains(sourceField.getDescribe().getType());

        Case actionCase = new Case(
            AccountId = member.Id,
            Type = 'Edit Individual',
            Origin = 'Wizard',
            Status = 'New',
            RecordTypeId = WizardEnvelopeStateService.principalReviewRecordTypeId(),
            Original_Approximate_Net_Worth__c = isNumeric ? '500000.00' : '500000'
        );
        insert actionCase;

        // Typed separately: a ternary cannot mix Integer and String, and the point of the test is
        // that the interview sends the value in the shape its own field type implies.
        Object sentValue = '500000';
        if (isNumeric) {
            sentValue = 500000;
        }

        Test.startTest();
        WizardEnvelopeStateService.saveProposedCaseFields(
            actionCase.Id,
            member.Id,
            new Map<String, Object>{ 'Approximate_Net_Worth__c' => sentValue }
        );
        Test.stopTest();

        System.assertEquals(null,
                            [SELECT Proposed_Approximate_Net_Worth__c FROM Case WHERE Id = :actionCase.Id]
                            .Proposed_Approximate_Net_Worth__c,
                            'The same value written at a different scale is not a change.');
    }

    @IsTest
    static void getProposedCaseValuesHandlesEmptyInput() {
        Test.startTest();
        Map<Id, Map<String, Object>> values =
            WizardEnvelopeStateService.getProposedCaseValues(new List<Id>());
        Test.stopTest();

        System.assertEquals(0, values.size(), 'No ids should read no records.');
    }

    // The baseline read is what lets the interview mark the fields a request changes, so it has to
    // keep reporting the snapshot after an edit — reading back the proposal instead would leave
    // every edited field looking untouched.
    @IsTest
    static void getOriginalCaseValuesReturnsTheFrozenSnapshot() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);
        WizardEnvelopeStateService.saveProposedCaseFields(
            actionCase.Id,
            member.Id,
            new Map<String, Object>{ 'FirstName' => 'Janette' }
        );

        Test.startTest();
        Map<Id, Map<String, Object>> values =
            WizardEnvelopeStateService.getOriginalCaseValues(new List<Id>{ actionCase.Id });
        Test.stopTest();

        Map<String, Object> caseValues = values.get(actionCase.Id);
        System.assertNotEquals(null, caseValues, 'The case should be present in the result.');
        System.assertEquals('Janet', caseValues.get('FirstName'),
                            'An edited field still reads back as the value it started from.');
        System.assertEquals('Prior', caseValues.get('LastName'));
        System.assertEquals('Old Town', caseValues.get('BillingCity'));
        System.assertEquals(new List<String>{ 'Growth', 'Income' },
                            (List<String>) caseValues.get('Investment_Objectives__c'),
                            'A multi-select baseline reads back typed, like the prefill read.');
    }

    // An absent key means the field is not part of the review pairs; a null one means it was blank
    // on the member. Only the second is a field the interview can mark as changed, so a blank
    // baseline has to survive the read rather than being dropped.
    @IsTest
    static void getOriginalCaseValuesKeepsBlankBaselines() {
        Account member = [SELECT Id FROM Account WHERE Name = 'Member 1' LIMIT 1];
        Case actionCase = insertMemberActionCase(member.Id);

        Test.startTest();
        Map<Id, Map<String, Object>> values =
            WizardEnvelopeStateService.getOriginalCaseValues(new List<Id>{ actionCase.Id });
        Test.stopTest();

        // Occupation__c is absent from the snapshot fixture, so its baseline is empty.
        Map<String, Object> caseValues = values.get(actionCase.Id);
        System.assert(caseValues.containsKey('Occupation__c'),
                      'A mapped field with an empty baseline is still tracked.');
        System.assertEquals(null, caseValues.get('Occupation__c'));
    }

    @IsTest
    static void getOriginalCaseValuesHandlesEmptyInput() {
        Test.startTest();
        Map<Id, Map<String, Object>> values =
            WizardEnvelopeStateService.getOriginalCaseValues(new List<Id>());
        Test.stopTest();

        System.assertEquals(0, values.size(), 'No ids should read no records.');
    }

    @IsTest
    static void testSubmitEnvelope() {
        
        // Create Envelope
        Envelope__c envelope = new Envelope__c(
            Status__c = 'In Progress'
        );
        insert envelope;
        
        // Create Account
        Account account = new Account(
            Name = 'Test Account',
            Submitted__c = false
        );
        insert account;
        
        // Create Case
        Case testCase = new Case(
            Subject = 'Test Case',
            Status = 'New',
            AccountId = account.Id,
            Submitted__c = false
        );
        insert testCase;
        
        // Create Financial Account
        Financial_Account__c financialAccount = new Financial_Account__c(
            Name = 'Test Financial Account',
            Submitted__c = false
        );
        insert financialAccount;
        
        // Create Service
        Service__c service = new Service__c(
            Name = 'Test Service',
            Submitted__c = false
        );
        insert service;
        
        // Create Envelope Content records
        List<Envelope_Content__c> envelopeContents = new List<Envelope_Content__c>();
        
        envelopeContents.add(new Envelope_Content__c(
            Envelope__c = envelope.Id,
            Account__c = account.Id
        ));
        
        envelopeContents.add(new Envelope_Content__c(
            Envelope__c = envelope.Id,
            Case__c = testCase.Id
        ));
        
        envelopeContents.add(new Envelope_Content__c(
            Envelope__c = envelope.Id,
            Wizard_Financial_Account__c = financialAccount.Id
        ));
        
        envelopeContents.add(new Envelope_Content__c(
            Envelope__c = envelope.Id,
            Service__c = service.Id
        ));
        
        insert envelopeContents;
        
        Test.startTest();
        
        WizardEnvelopeStateService.submitEnvelope(envelope.Id);
        
        Test.stopTest();
        
        // Verify Envelope
        Envelope__c updatedEnvelope = [
            SELECT Id, Status__c
            FROM Envelope__c
            WHERE Id = :envelope.Id
        ];
        
        System.assertEquals(
            'Complete',
            updatedEnvelope.Status__c,
            'Envelope should be marked as Complete.'
        );
        
        // Verify Account
        Account updatedAccount = [
            SELECT Id, Submitted__c
            FROM Account
            WHERE Id = :account.Id
        ];
        
        System.assertEquals(
            true,
            updatedAccount.Submitted__c,
            'Account should be marked as Submitted.'
        );
        
        // Verify Case
        Case updatedCase = [
            SELECT Id, Submitted__c
            FROM Case
            WHERE Id = :testCase.Id
        ];
        
        System.assertEquals(
            true,
            updatedCase.Submitted__c,
            'Case should be marked as Submitted.'
        );
        
        // Verify Financial Account
        Financial_Account__c updatedFinancialAccount = [
            SELECT Id, Submitted__c
            FROM Financial_Account__c
            WHERE Id = :financialAccount.Id
        ];
        
        System.assertEquals(
            true,
            updatedFinancialAccount.Submitted__c,
            'Financial Account should be marked as Submitted.'
        );
        
        // Verify Service
        Service__c updatedService = [
            SELECT Id, Submitted__c
            FROM Service__c
            WHERE Id = :service.Id
        ];
        
        System.assertEquals(
            true,
            updatedService.Submitted__c,
            'Service should be marked as Submitted.'
        );
    }
    
}
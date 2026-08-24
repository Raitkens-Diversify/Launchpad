/**
 * Tests for BranchOpportunitySyncService — the two-way mirror between a Branch
 * (Advisor_Group__c) and its Primary Branch Opportunity.
 *
 * The Branch stage-validation flow gates every stage at/after Sales Accepted with the
 * full qualification field set, and it runs on the FIRST update after create — which is
 * exactly when the sync first writes an Opportunity. Test data therefore fills all gate
 * fields, and — mirroring production, where the New Branch Opportunity flow copies the
 * fields at create — the AG and Opp start with IDENTICAL synced values (a full mirror
 * also copies nulls, so a pair that starts different would "sync" the difference on the
 * first write).
 */
@isTest
private class BranchOpportunitySyncServiceTest {

    private static Id branchRtId = Schema.SObjectType.Opportunity
        .getRecordTypeInfosByDeveloperName().get('Branch').getRecordTypeId();

    /** AG pre-filled with every shared qualification field the stage gate requires. */
    private static Advisor_Group__c makeGroup(String name) {
        return new Advisor_Group__c(
            Name = name,
            Lead_Source__c = 'Referral - Internal', // maps to Opportunity.LeadSource
            Affiliation_Type__c = '1099',
            Affiliation__c = 'DAS',
            Cultural_Fit__c = 'Good fit',
            Current_Affiliation__c = 'Investment Advisor',
            Current_Custodian__c = 'Fidelity',
            Disclosures__c = 'No',
            How_You_Manage_Assets__c = 'Rep as PM',
            IAPD_BrokerCheck__c = 'https://brokercheck.finra.org/test',
            Main_Growth_Levers__c = 'Referrals',
            Number_of_Advisors__c = 5,
            Number_of_Staff__c = 10,
            Office_Team_Structure__c = 'Solo advisor plus staff',
            Pain_Points__c = 'Technology',
            Potential_Service__c = 'RIA 1099',
            Required_to_Make_a_Move__c = 'Better economics',
            Specialties__c = 'Planning'
        );
    }

    /** Branch Opp whose synced fields exactly mirror makeGroup (as the creator flow does). */
    private static Opportunity makeOpp(String name, Advisor_Group__c ag) {
        return new Opportunity(
            Name = name,
            RecordTypeId = branchRtId,
            StageName = 'Diligence',
            CloseDate = Date.today().addMonths(6),
            Advisor_Group__c = ag.Id,
            LeadSource = ag.Lead_Source__c, // mirrors the mapped pair, as the creator flow does
            Affiliation_Type__c = ag.Affiliation_Type__c,
            Affiliation__c = ag.Affiliation__c,
            Cultural_Fit__c = ag.Cultural_Fit__c,
            Current_Affiliation__c = ag.Current_Affiliation__c,
            Current_Custodian__c = ag.Current_Custodian__c,
            Disclosures__c = ag.Disclosures__c,
            How_You_Manage_Assets__c = ag.How_You_Manage_Assets__c,
            IAPD_BrokerCheck__c = ag.IAPD_BrokerCheck__c,
            Main_Growth_Levers__c = ag.Main_Growth_Levers__c,
            Number_of_Advisors__c = ag.Number_of_Advisors__c,
            Number_of_Staff__c = ag.Number_of_Staff__c,
            Office_Team_Structure__c = ag.Office_Team_Structure__c,
            Pain_Points__c = ag.Pain_Points__c,
            Potential_Service__c = ag.Potential_Service__c,
            Required_to_Make_a_Move__c = ag.Required_to_Make_a_Move__c,
            Specialties__c = ag.Specialties__c
        );
    }

    /** Links ag -> opp as primary without touching any synced field. */
    private static void linkPrimary(Advisor_Group__c ag, Id oppId) {
        ag.Primary_Branch_Opportunity__c = oppId;
        update ag;
    }

    @isTest
    static void agChangesSyncToOpenPrimaryOpp() {
        Advisor_Group__c ag = makeGroup('Sync AG');
        insert ag;
        Opportunity opp = makeOpp('Sync Opp', ag);
        insert opp;
        linkPrimary(ag, opp.Id);

        Test.startTest();
        ag.Notes__c = 'Updated during nurture';
        ag.Number_of_Advisors__c = 7;
        ag.Total_AUM__c = 125000000;
        ag.Potential_Service__c = 'RIA W2'; // restricted-picklist path, Branch-RT-valid value
        update ag;
        Test.stopTest();

        Opportunity result = [
            SELECT Notes__c, Number_of_Advisors__c, Total_AUM__c, Potential_Service__c
            FROM Opportunity WHERE Id = :opp.Id
        ];
        Assert.areEqual('Updated during nurture', result.Notes__c, 'AG -> Opp Notes');
        Assert.areEqual(7, result.Number_of_Advisors__c, 'AG -> Opp Number of Advisors');
        Assert.areEqual(125000000, result.Total_AUM__c, 'AG -> Opp Total AUM');
        Assert.areEqual('RIA W2', result.Potential_Service__c, 'AG -> Opp restricted picklist');
    }

    @isTest
    static void oppChangesSyncBackToAdvisorGroup() {
        Advisor_Group__c ag = makeGroup('Writeback AG');
        insert ag;
        Opportunity opp = makeOpp('Writeback Opp', ag);
        insert opp;
        linkPrimary(ag, opp.Id);

        Test.startTest();
        opp.Notes__c = 'Deal desk update';
        opp.Total_AUA__c = 90000000;
        update opp;
        Test.stopTest();

        Advisor_Group__c result = [
            SELECT Notes__c, Total_AUA__c FROM Advisor_Group__c WHERE Id = :ag.Id
        ];
        Assert.areEqual('Deal desk update', result.Notes__c, 'Opp -> AG Notes');
        Assert.areEqual(90000000, result.Total_AUA__c, 'Opp -> AG Total AUA');
    }

    @isTest
    static void closedPrimaryOppFreezesBothDirections() {
        Advisor_Group__c ag = makeGroup('Frozen AG');
        insert ag;
        // Inserted already closed: the service only checks IsClosed, not how it closed.
        Opportunity opp = makeOpp('Closed Opp', ag);
        opp.StageName = 'Closed Lost';
        opp.Loss_Reason__c = 'Timing/Not Ready';
        insert opp;
        linkPrimary(ag, opp.Id);

        Test.startTest();
        ag.Notes__c = 'Post-close AG edit';
        update ag;
        opp.Total_AUM__c = 55555555;
        update opp;
        Test.stopTest();

        Opportunity oppResult = [SELECT Notes__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.isNull(oppResult.Notes__c, 'AG edit must not reach a closed primary Opp');
        Advisor_Group__c agResult = [
            SELECT Notes__c, Total_AUM__c, Primary_Branch_Opportunity__c
            FROM Advisor_Group__c WHERE Id = :ag.Id
        ];
        Assert.isNull(agResult.Total_AUM__c, 'Closed Opp edit must not write back to the AG');
        Assert.areEqual(opp.Id, agResult.Primary_Branch_Opportunity__c,
            'The link stays as a historical pointer after close');
    }

    @isTest
    static void nonPrimaryOppNeverWritesToAdvisorGroup() {
        Advisor_Group__c ag = makeGroup('Multi-Opp AG');
        insert ag;
        Opportunity primary = makeOpp('Primary Opp', ag);
        Opportunity additional = makeOpp('Additional Opp', ag);
        insert new List<Opportunity>{ primary, additional };
        linkPrimary(ag, primary.Id);

        Test.startTest();
        additional.Notes__c = 'Second deal chatter';
        additional.Total_AUM__c = 42;
        update additional;
        Test.stopTest();

        Advisor_Group__c result = [
            SELECT Notes__c, Total_AUM__c FROM Advisor_Group__c WHERE Id = :ag.Id
        ];
        Assert.isNull(result.Notes__c, 'Non-primary Opp must not write back');
        Assert.isNull(result.Total_AUM__c, 'Non-primary Opp must not write back');
    }

    @isTest
    static void bothDirectionsWorkInOneTransaction() {
        // The echo guard must skip only the service's own trigger firing — a genuine
        // edit of the same record later in the SAME transaction must still sync.
        Advisor_Group__c ag = makeGroup('Round-trip AG');
        insert ag;
        Opportunity opp = makeOpp('Round-trip Opp', ag);
        insert opp;
        linkPrimary(ag, opp.Id);

        Test.startTest();
        ag.Notes__c = 'AG first';
        update ag;                                            // AG -> Opp (echo on opp)
        update new Opportunity(Id = opp.Id, Fee_AUM__c = 75000000); // genuine Opp edit, same txn
        Test.stopTest();

        Advisor_Group__c agResult = [SELECT Fee_AUM__c FROM Advisor_Group__c WHERE Id = :ag.Id];
        Assert.areEqual(75000000, agResult.Fee_AUM__c,
            'A genuine Opp edit after an AG -> Opp sync in the same transaction must still write back');
        Assert.areEqual('AG first',
            [SELECT Notes__c FROM Opportunity WHERE Id = :opp.Id].Notes__c,
            'The earlier AG -> Opp sync must have landed too');
    }

    @isTest
    static void mappedPairSyncsAcrossDifferentFieldNames() {
        // Lead_Source__c (Branch) <-> LeadSource (Opportunity) via the CMDT pair columns.
        Advisor_Group__c ag = makeGroup('Mapped-pair AG');
        insert ag;
        Opportunity opp = makeOpp('Mapped-pair Opp', ag);
        insert opp;
        linkPrimary(ag, opp.Id);

        Test.startTest();
        ag.Lead_Source__c = 'Referral - External';
        update ag;                                            // AG -> Opp across names
        Assert.areEqual('Referral - External',
            [SELECT LeadSource FROM Opportunity WHERE Id = :opp.Id].LeadSource,
            'AG -> Opp must map Lead_Source__c onto LeadSource');
        update new Opportunity(Id = opp.Id, LeadSource = 'Trade Show'); // Opp -> AG back
        Test.stopTest();

        Assert.areEqual('Trade Show',
            [SELECT Lead_Source__c FROM Advisor_Group__c WHERE Id = :ag.Id].Lead_Source__c,
            'Opp -> AG must map LeadSource back onto Lead_Source__c');
    }

    @isTest
    static void blockedStatusFreezesBothDirections() {
        // Active / Disqualified / Inactive AGs never sync, even with an open linked opp.
        List<String> blocked = new List<String>{ 'Active', 'Disqualified', 'Inactive' };
        List<Advisor_Group__c> groups = new List<Advisor_Group__c>();
        for (String status : blocked) {
            Advisor_Group__c ag = makeGroup(status + ' AG');
            ag.Status__c = status;
            groups.add(ag);
        }
        insert groups;
        List<Opportunity> opps = new List<Opportunity>();
        for (Advisor_Group__c ag : groups) {
            opps.add(makeOpp('Opp for ' + ag.Name, ag));
        }
        insert opps;
        for (Integer i = 0; i < groups.size(); i++) {
            groups[i].Primary_Branch_Opportunity__c = opps[i].Id;
        }
        update groups;

        Test.startTest();
        for (Advisor_Group__c ag : groups) {
            ag.Notes__c = 'AG edit while ' + ag.Status__c;
        }
        update groups; // AG -> Opp must not fire
        for (Opportunity opp : opps) {
            opp.Total_AUA__c = 12345;
        }
        update opps;   // Opp -> AG must not fire
        Test.stopTest();

        for (Opportunity opp : [SELECT Notes__c FROM Opportunity WHERE Id IN :opps]) {
            Assert.isNull(opp.Notes__c, 'Blocked-status AG edit must not reach the Opp');
        }
        for (Advisor_Group__c ag : [SELECT Status__c, Total_AUA__c FROM Advisor_Group__c WHERE Id IN :groups]) {
            Assert.isNull(ag.Total_AUA__c,
                'Opp edit must not write back to a ' + ag.Status__c + ' AG');
        }
    }

    @isTest
    static void funnelStatusStillSyncs() {
        // A funnel-stage status must keep the mirror live (guards the blocked-list shape).
        Advisor_Group__c ag = makeGroup('Funnel AG');
        ag.Status__c = 'Sales Qualified Lead';
        insert ag;
        Opportunity opp = makeOpp('Funnel Opp', ag);
        insert opp;
        linkPrimary(ag, opp.Id);

        Test.startTest();
        ag.Notes__c = 'Funnel edit';
        update ag;
        Test.stopTest();

        Assert.areEqual('Funnel edit',
            [SELECT Notes__c FROM Opportunity WHERE Id = :opp.Id].Notes__c,
            'Funnel-status AGs must keep syncing');
    }

    @isTest
    static void unlinkedAdvisorGroupDoesNothing() {
        Advisor_Group__c ag = makeGroup('Unlinked AG');
        insert ag;

        Test.startTest();
        ag.Notes__c = 'No primary yet';
        update ag; // must not throw
        Test.stopTest();

        Assert.areEqual('No primary yet',
            [SELECT Notes__c FROM Advisor_Group__c WHERE Id = :ag.Id].Notes__c);
    }

    @isTest
    static void bulkSyncStaysWithinLimits() {
        List<Advisor_Group__c> groups = new List<Advisor_Group__c>();
        for (Integer i = 0; i < 200; i++) {
            groups.add(makeGroup('Bulk AG ' + i));
        }
        insert groups;
        List<Opportunity> opps = new List<Opportunity>();
        for (Advisor_Group__c ag : groups) {
            opps.add(makeOpp('Bulk Opp for ' + ag.Name, ag));
        }
        insert opps;
        for (Integer i = 0; i < 200; i++) {
            groups[i].Primary_Branch_Opportunity__c = opps[i].Id;
        }
        update groups;

        Test.startTest();
        for (Integer i = 0; i < 200; i++) {
            groups[i].Number_of_Advisors__c = 20 + i;
        }
        update groups; // one bulk update -> one sync pass, no recursion blowup
        Test.stopTest();

        Integer matched = 0;
        Map<Id, Advisor_Group__c> groupsById = new Map<Id, Advisor_Group__c>(groups);
        for (Opportunity opp : [
            SELECT Advisor_Group__c, Number_of_Advisors__c FROM Opportunity WHERE Id IN :opps
        ]) {
            if (opp.Number_of_Advisors__c ==
                groupsById.get(opp.Advisor_Group__c).Number_of_Advisors__c) {
                matched++;
            }
        }
        Assert.areEqual(200, matched, 'Every AG change must reach its own primary Opp');
    }
}
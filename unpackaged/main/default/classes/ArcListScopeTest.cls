@IsTest
private class ArcListScopeTest {
  @IsTest
  static void activeTeamIdsCountOnlyActiveMemberships() {
    // Financial_Advisor_Team_TriggerHandler.updateRepCode needs a team
    // literally named 'Default Team' to exist -- see ArcRecordSearchControllerTest.
    insert new Financial_Advisor_Team__c(Name = 'Default Team');

    Financial_Advisor_Team__c active = new Financial_Advisor_Team__c(Name = 'Active Team');
    Financial_Advisor_Team__c former = new Financial_Advisor_Team__c(Name = 'Former Team');
    insert new List<Financial_Advisor_Team__c>{ active, former };

    insert new List<Financial_Advisor_Team_Member__c>{
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = active.Id,
        User__c = UserInfo.getUserId(),
        Role__c = 'Financial Advisor',
        Active__c = true
      ),
      new Financial_Advisor_Team_Member__c(
        Financial_Advisor_Team__c = former.Id,
        User__c = UserInfo.getUserId(),
        Role__c = 'Financial Advisor',
        Active__c = false
      )
    };

    Test.startTest();
    Set<Id> teamIds = ArcListScope.activeTeamIds();
    Set<Id> teamUserIds = ArcListScope.activeTeamUserIds();
    Test.stopTest();

    Assert.areEqual(new Set<Id>{ active.Id }, teamIds, 'inactive membership does not count');
    Assert.isTrue(teamUserIds.contains(UserInfo.getUserId()), 'I am on my own team roster');
  }

  @IsTest
  static void clauseForShapesTheRulePerObject() {
    Map<String, Object> binds = new Map<String, Object>();

    String accountClause = ArcListScope.clauseFor('Account', binds);
    Assert.isTrue(accountClause.contains('OwnerId = :scopeUserId'));
    Assert.isTrue(
      accountClause.contains('Financial_Advisor_Team__pc IN :scopeTeamIds'),
      'Account also checks the Person Account mirror'
    );
    Assert.areEqual(UserInfo.getUserId(), binds.get(ArcListScope.USER_BIND));
    Assert.isNotNull(binds.get(ArcListScope.TEAM_BIND));

    Assert.areEqual(
      '(OwnerId = :scopeUserId OR Financial_Advisor_Team__c IN :scopeTeamIds)',
      ArcListScope.clauseFor('Task', binds),
      'Task uses the same two halves as every other object'
    );
    Assert.isFalse(binds.containsKey(ArcListScope.TEAM_USER_BIND), 'no teammate bind is needed');
    Assert.isTrue(
      ArcListScope.clauseFor('Service__c', binds).contains('Household__r.Financial_Advisor_Team__c'),
      'a service reads its team from its household'
    );
    Assert.isTrue(
      ArcListScope.clauseFor('Check_Deposit__c', binds).contains('Check__r.Financial_Advisor_Team__c'),
      'a deposit reads its team from its check log'
    );
    String holdingClause = ArcListScope.clauseFor('Financial_Account_Related_Product__c', binds);
    Assert.isTrue(
      holdingClause.contains('Wizard_Financial_Account__r.Financial_Advisor_Team__c'),
      'a holding reads its team from its ARC financial account'
    );
    Assert.isTrue(
      holdingClause.contains('Case__r.Financial_Advisor_Team__c'),
      '...or from the case it was raised from'
    );
    Assert.isFalse(
      holdingClause.contains('(Financial_Advisor_Team__c IN'),
      'its own team field is a text formula and is never compared to ids'
    );
    Assert.isTrue(ArcListScope.isScoped('Case'));
    Assert.isFalse(
      ArcListScope.isScoped('Product__c'),
      'the catalog is not scoped, which is why its related lists are'
    );
    Assert.areEqual(
      '(OwnerId = :scopeUserId OR Financial_Advisor_Team__c IN :scopeTeamIds)',
      ArcListScope.clauseFor('Case', binds)
    );
    Assert.areEqual(
      '(OwnerId = :scopeUserId OR Financial_Advisor_Team__c IN :scopeTeamIds)',
      ArcListScope.clauseFor('Check_Log__c', binds)
    );
    Assert.isNull(ArcListScope.clauseFor('Product__c', binds), 'the product catalog is not scoped');
    Assert.isNull(
      ArcListScope.clauseFor('Compliance_Exception__c', binds),
      'no owner/team shape: left to sharing'
    );
    Assert.isNull(ArcListScope.clauseFor('No_Such_Object__x', binds));
    Assert.isNull(ArcListScope.clauseFor(null, binds));
  }

  @IsTest
  static void literalClauseForInlinesIdsAndNeverEmitsAnEmptyInList() {
    String clause = ArcListScope.literalClauseFor('Task');

    Assert.isTrue(clause.contains('\'' + UserInfo.getUserId() + '\''), 'the user id is inlined');
    Assert.isTrue(
      clause.contains('IN (\'000000000000000AAA\')'),
      'a user on no team gets a never-matching id, not an invalid empty IN ()'
    );
    Assert.isFalse(clause.contains(':scope'), 'no bind placeholder survives');
    Assert.isNull(ArcListScope.literalClauseFor('Product__c'));
  }
}
/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 *
 * Repository for Financial_Advisor_Team_Member__c reads.
 */
public virtual without sharing class FscRelFaTeamMemberRepository {
  public virtual List<Financial_Advisor_Team_Member__c> selectActiveByUserId(Id userId) {
    if (userId == null) {
      return new List<Financial_Advisor_Team_Member__c>();
    }

    return [
      SELECT Id, User__c, Financial_Advisor_Team__c, Primary__c, Active__c
      FROM Financial_Advisor_Team_Member__c
      WHERE User__c = :userId AND Active__c = TRUE
      ORDER BY Primary__c DESC, CreatedDate ASC
    ];
  }

  public virtual Set<Id> selectActiveTeamIdsByUserId(Id userId) {
    Set<Id> teamIds = new Set<Id>();

    for (Financial_Advisor_Team_Member__c member : selectActiveByUserId(userId)) {
      if (member.Financial_Advisor_Team__c != null) {
        teamIds.add(member.Financial_Advisor_Team__c);
      }
    }

    return teamIds;
  }

  public virtual Boolean isActiveMember(Id userId, Id teamId) {
    if (userId == null || teamId == null) {
      return false;
    }

    return ![
        SELECT Id
        FROM Financial_Advisor_Team_Member__c
        WHERE
          User__c = :userId
          AND Financial_Advisor_Team__c = :teamId
          AND Active__c = TRUE
        LIMIT 1
      ]
      .isEmpty();
  }
}
/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 *
 * Enforces reciprocal role visibility by creator and FA team membership.
 */
public without sharing class FscRelReciprocalRoleAccessService {
  private final Id currentUserId;
  private final FscRelFaTeamMemberRepository teamMemberRepository;
  private Set<Id> activeTeamIdsForCurrentUser;

  public FscRelReciprocalRoleAccessService() {
    this(new FscRelFaTeamMemberRepository());
  }

  @TestVisible
  private FscRelReciprocalRoleAccessService(
    FscRelFaTeamMemberRepository teamMemberRepository
  ) {
    this.teamMemberRepository = teamMemberRepository;
    this.currentUserId = UserInfo.getUserId();
  }

  public Id selectPrimaryTeamIdForCurrentUser() {
    return selectPrimaryTeamIdForUser(currentUserId);
  }

  public Id selectPrimaryTeamIdForUser(Id userId) {
    if (userId == null) {
      return null;
    }

    for (Financial_Advisor_Team_Member__c member : teamMemberRepository.selectActiveByUserId(
      userId
    )) {
      if (member.Financial_Advisor_Team__c != null) {
        return member.Financial_Advisor_Team__c;
      }
    }

    return null;
  }

  public Set<Id> getAccessibleTeamIds() {
    if (activeTeamIdsForCurrentUser == null) {
      activeTeamIdsForCurrentUser = teamMemberRepository.selectActiveTeamIdsByUserId(
        currentUserId
      );
    }

    return new Set<Id>(activeTeamIdsForCurrentUser);
  }

  public Boolean canAccessRole(Reciprocal_Role__c role) {
    if (role == null) {
      return false;
    }

    if (role.CreatedById == currentUserId) {
      return true;
    }

    if (role.Financial_Advisor_Team__c != null) {
      return teamMemberRepository.isActiveMember(
        currentUserId,
        role.Financial_Advisor_Team__c
      );
    }

    return sharesActiveTeamWithUser(role.CreatedById, currentUserId);
  }

  private Boolean sharesActiveTeamWithUser(Id creatorUserId, Id viewerUserId) {
    if (creatorUserId == null || viewerUserId == null) {
      return false;
    }

    Set<Id> creatorTeamIds = teamMemberRepository.selectActiveTeamIdsByUserId(
      creatorUserId
    );
    if (creatorTeamIds.isEmpty()) {
      return false;
    }

    Set<Id> viewerTeamIds = teamMemberRepository.selectActiveTeamIdsByUserId(
      viewerUserId
    );
    creatorTeamIds.retainAll(viewerTeamIds);
    return !creatorTeamIds.isEmpty();
  }
}
/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-01
 *
 * Data transfer objects for the FSC Relationship Tree feature.
 */
public class FscRelHouseholdModels {
  public class TreeMember {
    @AuraEnabled
    public String relationId;
    @AuraEnabled
    public String accountId;
    @AuraEnabled
    public String contactId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public List<String> roles;
    @AuraEnabled
    public Boolean isPrimaryMember;
    @AuraEnabled
    public Boolean isPrimaryGroup;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String recordTypeLabel;
    @AuraEnabled
    public String accountType;

    public TreeMember() {
      this.roles = new List<String>();
      this.isPrimaryMember = false;
      this.isPrimaryGroup = false;
      this.isActive = false;
    }
  }

  public class TreeAccount {
    @AuraEnabled
    public String relationId;
    @AuraEnabled
    public String accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public List<String> roles;
    @AuraEnabled
    public String associationType;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String recordTypeLabel;
    @AuraEnabled
    public String accountType;
    @AuraEnabled
    public String contactId;
    @AuraEnabled
    public Boolean isPersonAccount;
    @AuraEnabled
    public List<String> classifications;

    public TreeAccount() {
      this.roles = new List<String>();
      this.classifications = new List<String>();
      this.isPersonAccount = false;
    }
  }

  public class RelationshipTreeData {
    @AuraEnabled
    public String rootAccountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String recordTypeLabel;
    @AuraEnabled
    public List<TreeMember> members;
    @AuraEnabled
    public List<TreeAccount> relatedAccounts;
    @AuraEnabled
    public List<TreeAccount> clientAccounts;
    @AuraEnabled
    public List<TreeAccount> classifiedAccounts;
    @AuraEnabled
    public List<TreeAccount> leadProspectAccounts;
    @AuraEnabled
    public List<TreeAccount> householdLinkedAccounts;

    public RelationshipTreeData() {
      this.members = new List<TreeMember>();
      this.relatedAccounts = new List<TreeAccount>();
      this.clientAccounts = new List<TreeAccount>();
      this.classifiedAccounts = new List<TreeAccount>();
      this.leadProspectAccounts = new List<TreeAccount>();
      this.householdLinkedAccounts = new List<TreeAccount>();
    }
  }

  public class TreeAccountResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String accountId;
    @AuraEnabled
    public String relationId;

    public TreeAccountResult(Boolean success, String message, String accountId) {
      this.success = success;
      this.message = message;
      this.accountId = accountId;
    }

    public TreeAccountResult() {
      this(false, '', null);
    }
  }

  public class RootAccountResolveResult {
    @AuraEnabled
    public Id rootAccountId;
    @AuraEnabled
    public Boolean isPersonAccount;

    public RootAccountResolveResult() {
      this.isPersonAccount = false;
    }
  }

  public class DeleteResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer deletedCount;

    public DeleteResult(Boolean success, String message, Integer deletedCount) {
      this.success = success;
      this.message = message;
      this.deletedCount = deletedCount;
    }

    public DeleteResult() {
      this(false, '', 0);
    }
  }

  public class LookupOption {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String subtitle;
    @AuraEnabled
    public String iconName;

    public LookupOption() {
    }
  }

  public class RecordTypeInfo {
    @AuraEnabled
    public String recordTypeId;
    @AuraEnabled
    public Boolean isPersonType;
    @AuraEnabled
    public String developerName;

    public RecordTypeInfo() {
      this.isPersonType = false;
    }
  }

  public class CreateRecordTypeOption {
    @AuraEnabled
    public String recordTypeId;
    @AuraEnabled
    public String developerName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean isPersonType;

    public CreateRecordTypeOption() {
      this.isPersonType = false;
    }
  }

  public class PicklistOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public PicklistOption(String label, String value) {
      this.label = label;
      this.value = value;
    }

    public PicklistOption() {
    }
  }

  public class ReciprocalRoleDuplicateCheckResult {
    @AuraEnabled
    public Boolean blockSave;
    @AuraEnabled
    public Boolean requiresConfirmation;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String existingInverseRole;
    @AuraEnabled
    public String existingRole;

    public ReciprocalRoleDuplicateCheckResult() {
      this.blockSave = false;
      this.requiresConfirmation = false;
    }
  }

  public class ReciprocalRoleCreateResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String reciprocalRoleId;
    @AuraEnabled
    public String roleLabel;

    public ReciprocalRoleCreateResult(
      Boolean success,
      String message,
      String reciprocalRoleId,
      String roleLabel
    ) {
      this.success = success;
      this.message = message;
      this.reciprocalRoleId = reciprocalRoleId;
      this.roleLabel = roleLabel;
    }

    public ReciprocalRoleCreateResult() {
      this(false, '', null, '');
    }
  }

  public class RecordTypeOption {
    @AuraEnabled
    public String developerName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String reciprocalRoleRecordTypeDeveloperName;

    public RecordTypeOption(
      String developerName,
      String label,
      String reciprocalRoleRecordTypeDeveloperName
    ) {
      this.developerName = developerName;
      this.label = label;
      this.reciprocalRoleRecordTypeDeveloperName = reciprocalRoleRecordTypeDeveloperName;
    }

    public RecordTypeOption() {
    }
  }

  public class TreeMemberAccountRelationship {
    @AuraEnabled
    public String relationId;
    @AuraEnabled
    public String memberAccountId;
    @AuraEnabled
    public String relatedAccountId;
    @AuraEnabled
    public String relatedAccountName;
    @AuraEnabled
    public String reciprocalRoleId;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String inverseReciprocalRoleId;
    @AuraEnabled
    public String inverseRole;
    @AuraEnabled
    public String recordTypeDeveloperName;
    @AuraEnabled
    public String relatedAccountRecordTypeDeveloperName;
    @AuraEnabled
    public Boolean isActive;

    public TreeMemberAccountRelationship() {
      this.isActive = false;
    }
  }

  public class TreeMemberAccountRelationshipInput {
    @AuraEnabled
    public String rowKey;
    @AuraEnabled
    public String relationId;
    @AuraEnabled
    public String relatedAccountId;
    @AuraEnabled
    public String reciprocalRoleId;
    @AuraEnabled
    public String inverseReciprocalRoleId;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String inverseRole;
    @AuraEnabled
    public Boolean isActive;

    public TreeMemberAccountRelationshipInput() {
      this.isActive = false;
    }
  }

  public class TreeMemberAccountRelationshipRowResult {
    @AuraEnabled
    public String rowKey;
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public List<String> messages;
    @AuraEnabled
    public String relationId;
    @AuraEnabled
    public String relatedAccountId;

    public TreeMemberAccountRelationshipRowResult(String rowKey) {
      this.rowKey = rowKey;
      this.success = true;
      this.messages = new List<String>();
    }

    public TreeMemberAccountRelationshipRowResult() {
      this('');
    }
  }

  public class MemberAccountRelationshipsSaveResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer successCount;
    @AuraEnabled
    public List<TreeMemberAccountRelationshipRowResult> rowResults;

    public MemberAccountRelationshipsSaveResult(
      Boolean success,
      String message,
      Integer successCount
    ) {
      this.success = success;
      this.message = message;
      this.successCount = successCount;
      this.rowResults = new List<TreeMemberAccountRelationshipRowResult>();
    }

    public MemberAccountRelationshipsSaveResult() {
      this(false, '', 0);
    }
  }
}
/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-13
 *
 * Shared constants for Arc Experience Cloud record detail and related controllers.
 */
public class ARCConstants {
  public static final String OBJECT_ACCOUNT = 'Account';
  public static final String OBJECT_CASE = 'Case';
  public static final String OBJECT_SERVICE = 'Service__c';
  public static final String OBJECT_FINANCIAL_ACCOUNT = 'Financial_Account__c';

  public static final String FIELD_SUBMITTED = 'Submitted__c';
  public static final String FIELD_NAME = 'Name';
  public static final String FIELD_RECORD_TYPE_ID = 'RecordTypeId';
  public static final String FIELD_ID = 'Id';
  public static final String PERSON_FIELD_PREFIX = 'Person';

  public static final String DEFAULT_ACCOUNT_SCHEMA_TYPE = 'Client - Individual';
  public static final String SCHEMA_STANDARD_CASE = 'Standard Case';
  public static final String SCHEMA_ISA_SERVICE_AGREEMENT = 'ISA - Service Agreement';
  public static final String SCHEMA_ISA_FIN_ACCT = 'ISA - Fin Acct';
  public static final String SCHEMA_ISA_DPI = 'ISA - DPI';
  public static final String SCHEMA_MANAGE_DMS_INSTRUCTIONS = 'Manage DMS Instructions';

  public static final String MEMBER_TYPE_CLIENT = 'client';
  public static final String MEMBER_TYPE_BUSINESS = 'business';
  public static final String MEMBER_TYPE_TRUST = 'trust';
  public static final String MEMBER_TYPE_RETIREMENT_PLAN = 'retirementplan';

  public static final Integer MAX_RELATED_OBJECTS_PER_PRIMARY = 40;
  public static final Integer PRIMARY_LOOKUP_FIELDS_PER_QUERY = 50;
  public static final Integer RELATED_OBJECT_VALUES_QUERY_CHUNK_SIZE = 10;
  public static final Integer SOQL_QUERY_HEADROOM_BUFFER = 1;

  public static final String LOOKUP_CACHE_KEY_SEPARATOR = '|';

  public enum RelatedTableScope {
    MINE,
    TEAM
  }

  public static final String ERROR_RECORD_ID_REQUIRED = 'Record Id is required';
  public static final String ERROR_RECORD_NOT_FOUND = 'Record not found.';
  public static final String ERROR_SUBMITTED_RECORD = 'This record has been submitted and can no longer be edited.';
  public static final String ERROR_NO_EDITABLE_FIELDS = 'There are no editable fields to update in this section.';
  public static final String ERROR_UNSUPPORTED_ACCOUNT_SCHEMA = 'Cannot save: unsupported account schema type.';
  public static final String ERROR_OBJECT_NOT_FOUND = 'Object not found: ';
  public static final String ERROR_NO_UPDATE_PERMISSION = 'You do not have permission to update this record.';
  public static final String ERROR_CASE_SCHEMA_UNRESOLVED = 'Schema type could not be resolved for this case type.';
  public static final String ERROR_ACCOUNT_SCHEMA_UNRESOLVED =
    'Schema type could not be resolved for this account record type.';
  public static final String ERROR_SCHEMA_UNRESOLVED_FOR_OBJECT = 'Schema type could not be resolved for ';
  public static final String ERROR_TOO_MANY_RELATED_OBJECTS = 'This form references too many related object types (';
  public static final String ERROR_QUERY_LIMIT_EXCEEDED = 'Unable to load related record values: query limit would be exceeded.';
  public static final String ERROR_NO_RELATED_RECORD_LINKED = 'No ';
  public static final String ERROR_RELATED_RECORD_LINKED_MIDDLE = ' record is linked to this ';
  public static final String ERROR_RELATED_RECORD_LINKED_SUFFIX = '.';
  public static final String ERROR_FIELDS_NOT_SAVED_PREFIX = 'These fields could not be saved: ';
  public static final String ERROR_GENERIC_SAVE = 'Something went wrong while saving your changes. Please try again.';
  public static final String ERROR_RELATED_LOOKUP_FIELD_REQUIRED =
    'Related record lookup field API name is required when use related record is enabled.';
  public static final String ERROR_INVALID_RELATED_LOOKUP_FIELD =
    'Invalid related record lookup field: ';

  // Mirrors envelopeFormSchema.js MDT_TYPE_TO_RECORD_TYPES / WizardEnvelopeStateService.addMemberByRecordType.
  public static final Map<String, String> RECORD_TYPE_TO_SCHEMA_TYPE = new Map<String, String>{
    'PersonAccount' => 'Client - Individual',
    'Individual' => 'Client - Individual',
    'Business' => 'Client - Business',
    //'IndustriesBusiness' => 'Client - Business',
    'Trust' => 'Client - Trust',
    //'IndustriesInstitution' => 'Client - Trust',
    'Retirement_Plan' => 'Client - Retirement Plan'
  };

  // Member type token EnvelopeHouseholdMemberController.saveEntity expects under RecordTypeId.
  public static final Map<String, String> SCHEMA_TYPE_TO_MEMBER_TYPE = new Map<String, String>{
    'Client - Individual' => MEMBER_TYPE_CLIENT,
    'Client - Business' => MEMBER_TYPE_BUSINESS,
    'Client - Trust' => MEMBER_TYPE_TRUST,
    'Client - Retirement Plan' => MEMBER_TYPE_RETIREMENT_PLAN
  };

  public static final Map<String, String> CASE_TYPE_TO_SCHEMA_TYPE = new Map<String, String>{
    'Third Party Money Movement' => 'Third Party Money Movement',
    'Account Closure' => 'Account Closure',
    'Update DMS Instructions' => SCHEMA_MANAGE_DMS_INSTRUCTIONS,
    'Change Management Style' => 'Change Management Style',
    'Additional Funding' => 'Additional Funding',
    'Financial Planning' => SCHEMA_STANDARD_CASE,
    'Edit Individual' => 'Client - Individual',
    'Edit Business' => 'Client - Business',
    'Edit Trust' => 'Client - Trust',
    'Edit Retirement Plan' => 'Client - Retirement Plan'
  };

  // ArcRecordDetail always loads Case metadata with SCHEMA_STANDARD_CASE (not Case.Type).
  public static final Map<String, String> CASE_RECORD_TYPE_TO_SCHEMA_TYPE = new Map<String, String>{
    'Account_Opening' => SCHEMA_STANDARD_CASE,
    'Account_Servicing' => SCHEMA_STANDARD_CASE,
    'Account_Servicing_Principal_Review' => SCHEMA_STANDARD_CASE,
    'Advertising_Review' => SCHEMA_STANDARD_CASE,
    'Source_of_Funds' => SCHEMA_STANDARD_CASE,
    'Systems' => SCHEMA_STANDARD_CASE,
    'Operations_Request' => SCHEMA_STANDARD_CASE,
    'Ad_Hoc' => SCHEMA_STANDARD_CASE,
    'Email_to_Case' => SCHEMA_STANDARD_CASE,
    'Advisor_Group_Review' => SCHEMA_STANDARD_CASE,
    'Transition' => SCHEMA_STANDARD_CASE
  };

  public static final Map<Boolean, String> FINANCIAL_ACCOUNT_DPI_TO_SCHEMA_TYPE = new Map<Boolean, String>{
    true => SCHEMA_ISA_DPI,
    false => SCHEMA_ISA_FIN_ACCT
  };

  public static final Set<String> PERSON_ACCOUNT_BASE_FIELDS = new Set<String>{
    'FirstName',
    'LastName',
    'Salutation',
    'MiddleName',
    'Suffix'
  };
}
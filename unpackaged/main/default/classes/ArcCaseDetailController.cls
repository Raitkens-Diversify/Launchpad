/**
 * Loads a Case's own summary fields, its related Tasks, its
 * type-specific field sections, its Household's summary, and other Cases
 * sharing that Household — for the Experience Cloud Case detail page
 * (c:arcCaseDetail).
 *
 * Case itself carries 250+ custom fields (money-movement, rollover, gift,
 * account-closure, DMS, registration-change...) because a single Case
 * object backs every envelope wizard type. Which handful actually apply to
 * a given Case is already solved by the Envelope_Field__mdt schema system
 * (see FieldDetailController / ArcRecordDetailController's
 * CASE_TYPE_TO_SCHEMA_TYPE) — getCaseFieldSections reuses that same
 * metadata (read-only) instead of hand-picking a subset of fields here.
 */
public with sharing class ArcCaseDetailController {
  public class CaseDetailResult {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String status;
    // Drives the status path: the Status picklist is scoped per record type, so the
    // client needs the record type to ask for the right set of steps.
    @AuraEnabled
    public Id recordTypeId;
    // Named so the page can show the cards a record type's Lightning page shows
    // (the Advertising Item card belongs to Advertising Review and nothing else).
    @AuraEnabled
    public String recordTypeName;
    @AuraEnabled
    public Id advertisingItemId;
    @AuraEnabled
    public String advertisingItemName;
    @AuraEnabled
    public String priority;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public Id ownerId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String householdName;
    @AuraEnabled
    public Id householdId;
    @AuraEnabled
    public String financialAdvisorTeamName;
    @AuraEnabled
    public Id financialAdvisorTeamId;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public Datetime closedDate;
    @AuraEnabled
    public String milestoneStatus;
    @AuraEnabled
    public String milestone;
    /** Case Overall Status — the same value the Work table's column shows. */
    @AuraEnabled
    public String overallStatus;
    @AuraEnabled
    public Integer completedMainTrackTasks;
    @AuraEnabled
    public Integer totalMainTrackTasks;
    @AuraEnabled
    public Datetime pitstopStart;
    @AuraEnabled
    public Integer pitstopTotalMinutes;
    @AuraEnabled
    public CaseProgress progress;
    @AuraEnabled
    public HouseholdSummary household;
  }

  public class HouseholdSummary {
    @AuraEnabled
    public String billingAddress;
    @AuraEnabled
    public String liquidityNeeds;
    @AuraEnabled
    public String approximateNetWorth;
    @AuraEnabled
    public String riskTolerance;
    @AuraEnabled
    public String approximateAnnualIncome;
    @AuraEnabled
    public String investmentObjective;
    @AuraEnabled
    public String approximateHighestTaxBracket;
    @AuraEnabled
    public String advisoryFee;
  }

  public class TaskInfo {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Datetime completedDate;
    @AuraEnabled
    public Boolean branchPitStop;
    @AuraEnabled
    public Boolean homeOfficePitStop;
    @AuraEnabled
    public Boolean isClosed;
  }

  public class RelatedCaseInfo {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public Datetime createdDate;
  }

  public class HouseholdCasesResult {
    @AuraEnabled
    public List<RelatedCaseInfo> openCases;
    @AuraEnabled
    public List<RelatedCaseInfo> closedCases;
  }

  public class FieldValue {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  public class SectionView {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public List<FieldValue> fields;
  }

  // Mirrors ArcRecordDetailController.CASE_TYPE_TO_SCHEMA_TYPE — the same
  // envelope-wizard schema types the interview forms use, reused here to
  // decide which Envelope_Field__mdt-defined field sections apply to this
  // Case's Type. Kept as its own copy rather than exposing the private map
  // on that class; both need to stay in sync if a new wizard type is added.
  private static final Map<String, String> CASE_TYPE_TO_SCHEMA_TYPE = new Map<String, String>{
    'Account Closure' => 'Account Closure',
    'Update DMS Instructions' => 'Manage DMS Instructions',
    'Change Management Style' => 'Change Management Style',
    'Additional Funding' => 'Additional Funding',
    'Edit Individual' => 'Client - Individual',
    'Edit Business' => 'Client - Business',
    'Edit Trust' => 'Client - Trust',
    'Edit Retirement Plan' => 'Client - Retirement Plan'
  };

  @AuraEnabled(cacheable=true)
  public static CaseDetailResult getCaseDetail(Id caseId) {
    if (caseId == null) {
      throw new AuraHandledException('Case Id is required.');
    }

    // Household__c (the plain custom field), not the older FinServ__Household__c
    // managed-package field both still present on Case -- FinServ__ (Financial
    // Services Cloud) fields are only visible to internal/FSC-licensed users;
    // a Community/Experience Cloud license user's schema simply doesn't have
    // that relationship at all, throwing "No such relation" the moment this
    // query tries to traverse it. Household__c isn't namespace-restricted and
    // is the field this org's own automation actually keeps populated.
    List<Case> matches = [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Status,
        RecordTypeId,
        RecordType.Name,
        Advertising_Item__c,
        Advertising_Item__r.Name,
        Priority,
        Type,
        Description,
        Owner.Name,
        OwnerId,
        Account.Name,
        AccountId,
        Household__r.Name,
        Household__r.BillingStreet,
        Household__r.BillingCity,
        Household__r.BillingState,
        Household__r.BillingPostalCode,
        Household__r.Liquidity_Needs__c,
        Household__r.Approximate_Net_Worth__c,
        Household__r.Risk_Tolerance__c,
        Household__r.Approximate_Annual_Income_All_Sources__c,
        Household__r.Investment_Objective_Ranked__c,
        Household__r.Approximate_Highest_Tax_Bracket__c,
        Household__r.Advisory_Fee__c,
        Household__c,
        Financial_Advisor_Team__r.Name,
        Financial_Advisor_Team__c,
        CreatedDate,
        ClosedDate,
        MilestoneStatus,
        Milestone__c,
        Current_Task_Status__c,
        Completed_Main_Track_Tasks__c,
        Total_Main_Track_Tasks__c,
        Pitstop_Start__c,
        Pitstop_Total_Minutes__c
      FROM Case
      WHERE Id = :caseId
      WITH USER_MODE
      LIMIT 1
    ];

    if (matches.isEmpty()) {
      throw new AuraHandledException('Case not found.');
    }

    Case record = matches[0];

    CaseDetailResult result = new CaseDetailResult();
    result.id = record.Id;
    result.caseNumber = record.CaseNumber;
    result.subject = record.Subject;
    result.status = record.Status;
    result.recordTypeId = record.RecordTypeId;
    result.recordTypeName = record.RecordType != null
      ? record.RecordType.Name
      : null;
    result.advertisingItemId = record.Advertising_Item__c;
    result.advertisingItemName = record.Advertising_Item__r != null
      ? record.Advertising_Item__r.Name
      : null;
    result.priority = record.Priority;
    result.type = record.Type;
    result.description = record.Description;
    result.ownerName = record.Owner != null ? record.Owner.Name : null;
    result.ownerId = record.OwnerId;
    result.accountName = record.Account != null ? record.Account.Name : null;
    result.accountId = record.AccountId;
    result.householdId = record.Household__c;
    result.financialAdvisorTeamName = record.Financial_Advisor_Team__r != null
      ? record.Financial_Advisor_Team__r.Name
      : null;
    result.financialAdvisorTeamId = record.Financial_Advisor_Team__c;
    result.createdDate = record.CreatedDate;
    result.closedDate = record.ClosedDate;
    result.milestoneStatus = record.MilestoneStatus;
    result.milestone = record.Milestone__c;
    result.overallStatus = record.Current_Task_Status__c;
    result.completedMainTrackTasks = toInt(
      record.Completed_Main_Track_Tasks__c
    );
    result.totalMainTrackTasks = toInt(record.Total_Main_Track_Tasks__c);
    result.pitstopStart = record.Pitstop_Start__c;
    result.pitstopTotalMinutes = toInt(record.Pitstop_Total_Minutes__c);
    result.progress = buildProgress(record);

    Account household = record.Household__r;
    if (household != null) {
      result.householdName = household.Name;
      result.household = buildHouseholdSummary(household);
    }

    return result;
  }

  @AuraEnabled(cacheable=true)
  public static List<TaskInfo> getCaseTasks(Id caseId) {
    List<TaskInfo> results = new List<TaskInfo>();

    if (caseId == null) {
      return results;
    }

    for (Task record : [
      SELECT
        Id,
        Subject,
        Status,
        Owner.Name,
        ActivityDate,
        CompletedDateTime,
        IsClosed,
        Branch_Pit_Stop__c,
        Home_Office_Pit_Stop__c
      FROM Task
      WHERE WhatId = :caseId
      WITH USER_MODE
      ORDER BY ActivityDate ASC NULLS LAST, CreatedDate ASC
      LIMIT 200
    ]) {
      TaskInfo info = new TaskInfo();
      info.id = record.Id;
      info.subject = record.Subject;
      info.status = record.Status;
      info.ownerName = record.Owner != null ? record.Owner.Name : null;
      info.dueDate = record.ActivityDate;
      info.completedDate = record.CompletedDateTime;
      info.branchPitStop = record.Branch_Pit_Stop__c == true;
      info.homeOfficePitStop = record.Home_Office_Pit_Stop__c == true;
      info.isClosed = record.IsClosed == true;
      results.add(info);
    }

    return results;
  }

  /**
   * The remaining envelope-schema-defined fields for this Case's Type,
   * grouped into the same named sections the wizard interview uses —
   * read-only. Returns an empty list (not an error) when the Type isn't one
   * of the mapped wizard schema types, so the page degrades gracefully
   * instead of the whole component failing like the wizard's own load()
   * does for an unmapped Type.
   */
  @AuraEnabled(cacheable=true)
  public static List<SectionView> getCaseFieldSections(Id caseId) {
    List<SectionView> sections = new List<SectionView>();

    if (caseId == null) {
      return sections;
    }

    List<Case> matches = [
      SELECT Type
      FROM Case
      WHERE Id = :caseId
      WITH USER_MODE
      LIMIT 1
    ];
    if (matches.isEmpty()) {
      return sections;
    }

    String schemaType = CASE_TYPE_TO_SCHEMA_TYPE.get(matches[0].Type);
    if (String.isBlank(schemaType)) {
      // Only Account Servicing types have a wizard schema. Everything else — an
      // Account Opening case, for one — would otherwise show no fields at all,
      // so its own populated fields stand in. The Lightning page shows these
      // grouped by its page layout, which Apex cannot read; one section is the
      // honest approximation rather than an invented grouping.
      return sections;
    }

    List<FieldDetailController.FormSection> formSections = FieldDetailController.getFormSchema(
      'Case',
      schemaType
    );

    if (formSections.isEmpty()) {
      return sections;
    }

    Map<Id, Map<String, Object>> valuesByRecord = FieldDetailController.getRecordValuesForType(
      'Case',
      schemaType,
      new List<Id>{ caseId }
    );
    Map<String, Object> values = valuesByRecord.containsKey(caseId)
      ? valuesByRecord.get(caseId)
      : new Map<String, Object>();

    for (FieldDetailController.FormSection formSection : formSections) {
      SectionView sectionView = new SectionView();
      sectionView.name = formSection.name;
      sectionView.fields = new List<FieldValue>();

      for (FieldDetailController.FieldMetadata field : formSection.fields) {
        Object rawValue = values.get(field.fieldPath);
        if (rawValue == null) {
          continue;
        }

        FieldValue fieldValue = new FieldValue();
        fieldValue.label = field.label;
        fieldValue.value = String.valueOf(rawValue);
        sectionView.fields.add(fieldValue);
      }

      if (!sectionView.fields.isEmpty()) {
        sections.add(sectionView);
      }
    }

    return sections;
  }

  @AuraEnabled(cacheable=true)
  public static HouseholdCasesResult getRelatedHouseholdCases(Id caseId) {
    HouseholdCasesResult result = new HouseholdCasesResult();
    result.openCases = new List<RelatedCaseInfo>();
    result.closedCases = new List<RelatedCaseInfo>();

    if (caseId == null) {
      return result;
    }

    // Household__c, not FinServ__Household__c -- see getCaseDetail's comment.
    List<Case> matches = [
      SELECT Household__c
      FROM Case
      WHERE Id = :caseId
      WITH USER_MODE
      LIMIT 1
    ];

    if (matches.isEmpty() || matches[0].Household__c == null) {
      return result;
    }

    Id householdId = matches[0].Household__c;

    for (Case record : [
      SELECT Id, CaseNumber, Subject, Status, IsClosed, Owner.Name, CreatedDate
      FROM Case
      WHERE Household__c = :householdId AND Id != :caseId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 20
    ]) {
      RelatedCaseInfo info = toRelatedCaseInfo(record);

      if (record.IsClosed) {
        result.closedCases.add(info);
      } else {
        result.openCases.add(info);
      }
    }

    return result;
  }

  @TestVisible
  private static RelatedCaseInfo toRelatedCaseInfo(Case record) {
    RelatedCaseInfo info = new RelatedCaseInfo();
    info.id = record.Id;
    info.caseNumber = record.CaseNumber;
    info.subject = record.Subject;
    info.status = record.Status;
    info.ownerName = record.Owner != null ? record.Owner.Name : null;
    info.createdDate = record.CreatedDate;
    return info;
  }

  @TestVisible
  private static HouseholdSummary buildHouseholdSummary(Account household) {
    HouseholdSummary summary = new HouseholdSummary();
    summary.billingAddress = formatAddress(household);
    summary.liquidityNeeds = household.Liquidity_Needs__c;
    summary.approximateNetWorth = formatCurrency(
      household.Approximate_Net_Worth__c
    );
    summary.riskTolerance = household.Risk_Tolerance__c;
    summary.approximateAnnualIncome = formatCurrency(
      household.Approximate_Annual_Income_All_Sources__c
    );
    summary.investmentObjective = household.Investment_Objective_Ranked__c;
    summary.approximateHighestTaxBracket = household.Approximate_Highest_Tax_Bracket__c;
    summary.advisoryFee = formatPercent(household.Advisory_Fee__c);
    return summary;
  }

  @TestVisible
  private static String formatAddress(Account household) {
    List<String> parts = new List<String>();

    if (String.isNotBlank(household.BillingStreet)) {
      parts.add(household.BillingStreet);
    }

    List<String> cityState = new List<String>();
    if (String.isNotBlank(household.BillingCity)) {
      cityState.add(household.BillingCity);
    }
    if (String.isNotBlank(household.BillingState)) {
      cityState.add(household.BillingState);
    }

    String cityStateZip = String.join(cityState, ', ');
    if (String.isNotBlank(household.BillingPostalCode)) {
      cityStateZip = String.isNotBlank(cityStateZip)
        ? cityStateZip + ' ' + household.BillingPostalCode
        : household.BillingPostalCode;
    }
    if (String.isNotBlank(cityStateZip)) {
      parts.add(cityStateZip);
    }

    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  @TestVisible
  private static String formatCurrency(Decimal amount) {
    return amount == null ? null : '$' + amount.format();
  }

  @TestVisible
  private static String formatPercent(Decimal percent) {
    return percent == null ? null : percent.format() + '%';
  }

  /**
   * How far a case has run and whether it is moving.
   *
   * Two separate questions, which is why they are two fields:
   *
   * - How far: the main-track tasks completed against the total. That is the
   *   ratio the donut draws, and the org already maintains both counts on the
   *   Case, so nothing is recomputed here from the task rows.
   * - Whether it is moving: a case sitting in a pit stop is waiting on someone
   *   else, so it is not on track however many tasks it has finished. Pit stop
   *   is read from the open tasks rather than from Pitstop_Start__c, because
   *   that timestamp records when the current pit stop began and stays set;
   *   the tasks say whether one is still open, and which kind.
   */
  public class CaseProgress {
    @AuraEnabled
    public Integer completed;
    @AuraEnabled
    public Integer total;
    /** 0-100, floored at 0 and capped at 100 for a case with stale counts. */
    @AuraEnabled
    public Integer percent;
    @AuraEnabled
    public Boolean isInPitStop;
    /** 'Branch', 'Home office', or null when no pit stop is open. */
    @AuraEnabled
    public String pitStopKind;
    /** What the status pill reads: On track / Branch pit stop / … */
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer openBranchPitStopTasks;
    @AuraEnabled
    public Integer openHomeOfficePitStopTasks;
    @AuraEnabled
    public Integer openMainTrackTasks;
    /** Task counts by status, ordered highest first, for the donut. */
    @AuraEnabled
    public List<StatusSlice> statusSlices;
  }

  public class StatusSlice {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer count;
  }

  private static Integer toInt(Decimal value) {
    return value == null ? 0 : value.intValue();
  }

  private static CaseProgress buildProgress(Case record) {
    CaseProgress progress = new CaseProgress();

    progress.openBranchPitStopTasks = 0;
    progress.openHomeOfficePitStopTasks = 0;
    progress.openMainTrackTasks = 0;

    Integer mainTrackTotal = 0;
    Integer mainTrackDone = 0;
    // Insertion-ordered so equal counts keep a stable slice order.
    Map<String, Integer> countByStatus = new Map<String, Integer>();

    // Open and closed together: the completed count is half the ratio the
    // donut draws, so a query filtered to open tasks cannot answer it.
    for (Task item : [
      SELECT Id, Status, IsClosed, Branch_Pit_Stop__c, Home_Office_Pit_Stop__c
      FROM Task
      WHERE WhatId = :record.Id
      WITH USER_MODE
      LIMIT 500
    ]) {
      String status = String.isBlank(item.Status) ? 'Not Started' : item.Status;
      countByStatus.put(
        status,
        (countByStatus.containsKey(status) ? countByStatus.get(status) : 0) + 1
      );

      Boolean isPitStop =
        item.Home_Office_Pit_Stop__c == true ||
        item.Branch_Pit_Stop__c == true;

      if (!isPitStop) {
        mainTrackTotal++;
        if (item.IsClosed == true) {
          mainTrackDone++;
        }
      }

      if (item.IsClosed == true) {
        continue;
      }

      if (item.Home_Office_Pit_Stop__c == true) {
        progress.openHomeOfficePitStopTasks++;
      } else if (item.Branch_Pit_Stop__c == true) {
        progress.openBranchPitStopTasks++;
      } else {
        progress.openMainTrackTasks++;
      }
    }

    /*
     * The Case carries Completed_/Total_Main_Track_Tasks__c rollups, and those
     * win when they are populated — they are the org's own numbers and may
     * count tasks this query's LIMIT did not reach. They are empty across every
     * case in this org today, though, so the task rows are the fallback rather
     * than the other way round: a donut that reads 0 of 0 on every case is no
     * donut at all.
     */
    Integer rollupTotal = toInt(record.Total_Main_Track_Tasks__c);
    progress.total = rollupTotal > 0 ? rollupTotal : mainTrackTotal;
    progress.completed = rollupTotal > 0
      ? toInt(record.Completed_Main_Track_Tasks__c)
      : mainTrackDone;

    progress.percent = progress.total <= 0
      ? 0
      : Math.min(100, Math.max(0, (progress.completed * 100) / progress.total));

    // Home office outranks branch: it is the one the advisor cannot clear.
    if (progress.openHomeOfficePitStopTasks > 0) {
      progress.pitStopKind = 'Home office';
    } else if (progress.openBranchPitStopTasks > 0) {
      progress.pitStopKind = 'Branch';
    }

    progress.statusSlices = new List<StatusSlice>();
    for (String status : countByStatus.keySet()) {
      StatusSlice slice = new StatusSlice();
      slice.label = status;
      slice.count = countByStatus.get(status);
      progress.statusSlices.add(slice);
    }

    // The pill is a health signal, not a status echo: either the case is parked
    // in a named pit stop or it is moving. The current task's own status is
    // already on the page twice, so repeating it here only hid "On track".
    progress.isInPitStop = progress.pitStopKind != null;
    progress.label = progress.isInPitStop
      ? progress.pitStopKind + ' pit stop'
      : 'On track';

    return progress;
  }

  /**
   * The Case's own populated fields as a single "Case Information" section,
   * labelled from describe and ordered by label. Blank fields are dropped: the
   * Case layout spans every case type, so rendering them all would bury the
   * handful that carry data under hundreds of empty rows.
   *
   * Audit and system fields are excluded, as are the fields the page header
   * already shows, so the section does not repeat what is directly above it.
   */
  private static SectionView buildCaseInformationSection(Id caseId) {
    SectionView section = new SectionView();
    section.name = 'Case Information';
    section.fields = new List<FieldValue>();

    // Audit and system fields, plus the fields the page header already shows, so
    // the section does not repeat what sits directly above it.
    Set<String> skip = new Set<String>{
      'id',
      'isdeleted',
      'createdbyid',
      'createddate',
      'lastmodifiedbyid',
      'lastmodifieddate',
      'systemmodstamp',
      'lastvieweddate',
      'lastreferenceddate',
      'masterrecordid',
      'connectionreceivedid',
      'connectionsentid',
      'recordtypeid',
      'casenumber',
      'status',
      'priority',
      'ownerid',
      'accountid',
      'subject',
      'description',
      // Plain Text(18) fields that happen to hold a raw Task/User Id (set by
      // trigger logic, never a real Lookup -- Schema.DisplayType.REFERENCE
      // above doesn't catch these, only true relationship fields) with no
      // reader-facing purpose: internal bookkeeping for automation, not
      // meant to be read.
      'next_task__c',
      'original_owner__c',
      'previous_task__c'
    };

    // The select list is built from describe rather than the SOQL FIELDS
    // function, which Apex rejects for an unbounded set. Compound address and
    // location values are left out: they stringify to an object rather than
    // anything readable, and their components are queryable individually.
    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
    Map<String, String> labelByApiName = new Map<String, String>();
    List<String> selectable = new List<String>();
    for (String key : fieldMap.keySet()) {
      if (skip.contains(key)) {
        continue;
      }
      Schema.DescribeFieldResult describe = fieldMap.get(key).getDescribe();
      if (!describe.isAccessible()) {
        continue;
      }
      Schema.DisplayType fieldType = describe.getType();
      // Compound address and location values stringify to an object rather than
      // anything readable. Ids and lookups are worse: a reader gets a raw
      // 18-character key where they expected a name, and the names worth showing
      // (account, owner, advisor team) are already resolved in the header.
      if (
        fieldType == Schema.DisplayType.ADDRESS ||
        fieldType == Schema.DisplayType.LOCATION ||
        fieldType == Schema.DisplayType.BASE64 ||
        fieldType == Schema.DisplayType.ID ||
        fieldType == Schema.DisplayType.REFERENCE
      ) {
        continue;
      }
      selectable.add(describe.getName());
      labelByApiName.put(describe.getName(), describe.getLabel());
    }
    if (selectable.isEmpty()) {
      return section;
    }

    List<Case> records = Database.query(
      'SELECT ' +
        String.join(selectable, ', ') +
        ' FROM Case WHERE Id = :caseId WITH USER_MODE LIMIT 1'
    );
    if (records.isEmpty()) {
      return section;
    }
    Case record = records[0];

    Map<String, String> valueByLabel = new Map<String, String>();
    for (String apiName : selectable) {
      Object raw = record.get(apiName);
      if (raw == null || String.valueOf(raw) == '') {
        continue;
      }
      // An unchecked checkbox is not a value a reader needs: it stringifies to
      // 'false' rather than blank, and on a Case layout spanning every case type
      // that alone was most of the section. A checked one reads as Yes, the way
      // the platform renders a checkbox in a read-only layout.
      if (raw instanceof Boolean) {
        if (!(Boolean) raw) {
          continue;
        }
        valueByLabel.put(labelByApiName.get(apiName), 'Yes');
        continue;
      }
      valueByLabel.put(labelByApiName.get(apiName), String.valueOf(raw));
    }

    List<String> labels = new List<String>(valueByLabel.keySet());
    labels.sort();
    for (String label : labels) {
      FieldValue fv = new FieldValue();
      fv.label = label;
      fv.value = valueByLabel.get(label);
      section.fields.add(fv);
    }
    return section;
  }

  /**
   * API names of the Case fields that carry a value, for the client to hand to
   * lightning-record-form. Names rather than label/value pairs on purpose: the
   * form then renders each field the way the platform does — real labels,
   * formatted currencies and dates, lookups as links, and an inline-edit pencil
   * on the ones the user can change. Building the markup here would give up all
   * of that.
   *
   * Audit and system fields are excluded, as are the fields the page header and
   * the Description/System sections already show. Ids and lookups are excluded
   * too: their stored value is an 18-character key, and the names worth showing
   * are resolved elsewhere on the page. An unchecked checkbox is dropped — on a
   * Case layout spanning every case type those alone outnumbered the real values.
   */
  @AuraEnabled(cacheable=true)
  public static List<String> getCaseInformationFieldNames(Id caseId) {
    List<String> result = new List<String>();
    if (caseId == null) {
      return result;
    }

    Set<String> skip = new Set<String>{
      'id',
      'isdeleted',
      'createdbyid',
      'createddate',
      'lastmodifiedbyid',
      'lastmodifieddate',
      'systemmodstamp',
      'lastvieweddate',
      'lastreferenceddate',
      'masterrecordid',
      'connectionreceivedid',
      'connectionsentid',
      'recordtypeid',
      'casenumber',
      'status',
      'priority',
      'ownerid',
      'accountid',
      'subject',
      'description',
      // Plain Text(18) fields that happen to hold a raw Task/User Id (set by
      // trigger logic, never a real Lookup -- Schema.DisplayType.REFERENCE
      // above doesn't catch these, only true relationship fields) with no
      // reader-facing purpose: internal bookkeeping for automation, not
      // meant to be read.
      'next_task__c',
      'original_owner__c',
      'previous_task__c'
    };

    Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
    List<String> selectable = new List<String>();
    Map<String, String> labelByApiName = new Map<String, String>();
    for (String key : fieldMap.keySet()) {
      if (skip.contains(key)) {
        continue;
      }
      Schema.DescribeFieldResult describe = fieldMap.get(key).getDescribe();
      if (!describe.isAccessible()) {
        continue;
      }
      Schema.DisplayType fieldType = describe.getType();
      if (
        fieldType == Schema.DisplayType.ADDRESS ||
        fieldType == Schema.DisplayType.LOCATION ||
        fieldType == Schema.DisplayType.BASE64 ||
        fieldType == Schema.DisplayType.ID ||
        fieldType == Schema.DisplayType.REFERENCE
      ) {
        continue;
      }
      // Anything longer than a text field belongs in its own section, not a
      // two-column grid — this is what was dumping
      // No_Template_Found_Completed_Fields__c's semicolon-delimited internals
      // across the page. The long text that does matter is Description, which
      // has a section of its own.
      if (describe.getLength() > 255) {
        continue;
      }
      // Text fields that store a record key rather than something readable —
      // Current Task Id, Flow Interview ID. They are plain text so their type
      // does not give them away, but their label does, and an 18-character key
      // is never what a reader came for.
      String label = describe.getLabel();
      if (label != null && (label.endsWith(' Id') || label.endsWith(' ID'))) {
        continue;
      }
      selectable.add(describe.getName());
      labelByApiName.put(describe.getName(), describe.getLabel());
    }
    if (selectable.isEmpty()) {
      return result;
    }

    List<Case> records = Database.query(
      'SELECT ' +
        String.join(selectable, ', ') +
        ' FROM Case WHERE Id = :caseId WITH USER_MODE LIMIT 1'
    );
    if (records.isEmpty()) {
      return result;
    }
    Case record = records[0];

    // Ordered by label so the section reads alphabetically rather than in
    // describe order, which is not stable.
    Map<String, String> apiNameByLabel = new Map<String, String>();
    for (String apiName : selectable) {
      Object raw = record.get(apiName);
      if (raw == null || String.valueOf(raw) == '') {
        continue;
      }
      if (raw instanceof Boolean && !(Boolean) raw) {
        continue;
      }
      apiNameByLabel.put(labelByApiName.get(apiName), apiName);
    }

    List<String> labels = new List<String>(apiNameByLabel.keySet());
    labels.sort();
    for (String label : labels) {
      result.add(apiNameByLabel.get(label));
    }
    return result;
  }
}
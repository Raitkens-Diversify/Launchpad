/**
 * Tests for UserPreferenceRepository, UserPreferenceModels, UserPreferenceService and
 * UserPreferenceController.
 *
 * Every User_Preference__c row is created for the running user because the controller
 * resolves UserInfo.getUserId(); the service and repository are exercised with the same Id
 * so all four layers share one data model. Service/controller validation failures surface
 * as AuraHandledException; in a test context getMessage() on those returns the generic
 * "Script-thrown exception", so only the type is asserted unless setMessage was called.
 */
@IsTest
private class UserPreferenceTest {
  private static final String APP_NAME = 'arcSuperWidget';
  private static final String OTHER_APP = 'arcOtherWidget';
  private static final String RECORD_KEY = 'recordA';
  private static final String LIST_VIEWS = UserPreferenceModels.LIST_VIEWS_SECTION_KEY;

  private static Id userId() {
    return UserInfo.getUserId();
  }

  private static User_Preference__c insertPreference(String applicationName, String state) {
    User_Preference__c preference = new User_Preference__c(
      User__c = userId(),
      Application_Name__c = applicationName,
      State__c = state
    );
    insert preference;
    return preference;
  }

  private static User_Preference__c queryPreference(Id preferenceId) {
    return [
      SELECT Id, User__c, Application_Name__c, State__c
      FROM User_Preference__c
      WHERE Id = :preferenceId
    ];
  }

  private static Integer countPreferences() {
    return [SELECT COUNT() FROM User_Preference__c];
  }

  private static Map<String, Object> parseState(Id preferenceId) {
    return (Map<String, Object>) JSON.deserializeUntyped(queryPreference(preferenceId).State__c);
  }

  private static Map<String, Object> parseObject(String jsonText) {
    return (Map<String, Object>) JSON.deserializeUntyped(jsonText);
  }

  private static List<Object> parseList(String jsonText) {
    return (List<Object>) JSON.deserializeUntyped(jsonText);
  }

  private static Map<String, Object> section(Map<String, Object> state, String key) {
    return (Map<String, Object>) state.get(key);
  }

  // ---------------------------------------------------------------------------
  // UserPreferenceRepository
  // ---------------------------------------------------------------------------

  @IsTest
  static void repository_selectByUserAndApp_returnsNullForBlankInputs() {
    UserPreferenceRepository repository = new UserPreferenceRepository();

    Assert.isNull(repository.selectByUserAndApp(null, APP_NAME), 'null user');
    Assert.isNull(repository.selectByUserAndApp(userId(), ''), 'blank application');
    Assert.isNull(repository.selectByUserAndApp(userId(), null), 'null application');
    Assert.isNull(repository.selectByUserAndAppForUpdate(null, APP_NAME), 'null user (for update)');
    Assert.isNull(repository.selectByUserAndAppForUpdate(userId(), '  '), 'blank application (for update)');
  }

  @IsTest
  static void repository_selectByUserAndApp_findsOnlyTheMatchingUserAndApplication() {
    User_Preference__c mine = insertPreference(APP_NAME, '{"version":1}');
    insertPreference(OTHER_APP, '{"version":2}');
    UserPreferenceRepository repository = new UserPreferenceRepository();

    User_Preference__c found = repository.selectByUserAndApp(userId(), APP_NAME);
    Assert.isNotNull(found, 'row for the running user and application');
    Assert.areEqual(mine.Id, found.Id);
    Assert.areEqual(userId(), found.User__c);
    Assert.areEqual(APP_NAME, found.Application_Name__c);
    Assert.areEqual('{"version":1}', found.State__c);
    Assert.isNull(repository.selectByUserAndApp(userId(), 'missingApp'), 'unknown application');

    User_Preference__c locked = repository.selectByUserAndAppForUpdate(userId(), APP_NAME);
    Assert.isNotNull(locked, 'FOR UPDATE variant finds the same row');
    Assert.areEqual(mine.Id, locked.Id);
    Assert.areEqual('{"version":1}', locked.State__c);
    Assert.isNull(repository.selectByUserAndAppForUpdate(userId(), 'missingApp'), 'unknown application (for update)');
  }

  @IsTest
  static void repository_upsertPreference_insertsThenUpdates() {
    UserPreferenceRepository repository = new UserPreferenceRepository();
    User_Preference__c preference = new User_Preference__c(
      User__c = userId(),
      Application_Name__c = APP_NAME,
      State__c = '{"version":1}'
    );

    User_Preference__c inserted = repository.upsertPreference(preference);

    Assert.isNotNull(inserted.Id, 'insert assigns an Id');
    Assert.areEqual(1, countPreferences());

    inserted.State__c = '{"version":2}';
    User_Preference__c updated = repository.upsertPreference(inserted);

    Assert.areEqual(inserted.Id, updated.Id, 'update keeps the Id');
    Assert.areEqual(1, countPreferences(), 'update does not create a second row');
    Assert.areEqual('{"version":2}', queryPreference(inserted.Id).State__c);
  }

  @IsTest
  static void repository_upsertPreference_throwsForNullRecord() {
    try {
      new UserPreferenceRepository().upsertPreference(null);
      Assert.fail('null preference should be rejected');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'AuraHandledException thrown');
    }
    Assert.areEqual(0, countPreferences());
  }

  @IsTest
  static void repository_upsertPreference_wrapsDmlFailuresWithTheRealMessage() {
    // Application_Name__c is required, so this insert fails inside the repository.
    try {
      new UserPreferenceRepository().upsertPreference(new User_Preference__c(User__c = userId()));
      Assert.fail('missing required field should be rejected');
    } catch (AuraHandledException expected) {
      Assert.isTrue(
        expected.getMessage().contains('upsertPreference failed'),
        'wrapped message is surfaced via setMessage: ' + expected.getMessage()
      );
      Assert.isTrue(
        expected.getMessage().contains('DmlException'),
        'original exception type is included: ' + expected.getMessage()
      );
    }
    Assert.areEqual(0, countPreferences());
  }

  // ---------------------------------------------------------------------------
  // UserPreferenceModels
  // ---------------------------------------------------------------------------

  @IsTest
  static void models_constantsDescribeTheStateContract() {
    Assert.areEqual(1, UserPreferenceModels.STATE_VERSION);
    Assert.areEqual(131072, UserPreferenceModels.MAX_STATE_LENGTH);
    Assert.areEqual('version', UserPreferenceModels.VERSION_KEY);
    Assert.areEqual('updatedAt', UserPreferenceModels.UPDATED_AT_KEY);
    Assert.areEqual('contexts', UserPreferenceModels.CONTEXTS_SECTION_KEY);
    Assert.areEqual('listViews', UserPreferenceModels.LIST_VIEWS_SECTION_KEY);
    Assert.areEqual('global', UserPreferenceModels.GLOBAL_CONTEXT_KEY);
  }

  @IsTest
  static void models_preferenceResultDefaultsAndNormalizesBlanks() {
    UserPreferenceModels.PreferenceResult empty = new UserPreferenceModels.PreferenceResult();
    Assert.isNull(empty.preferenceId);
    Assert.areEqual('[]', empty.viewsJson);
    Assert.areEqual('', empty.lastSelectedViewId);

    UserPreferenceModels.PreferenceResult twoArg = new UserPreferenceModels.PreferenceResult(
      userId(),
      null
    );
    Assert.areEqual(userId(), twoArg.preferenceId);
    Assert.areEqual('[]', twoArg.viewsJson, 'null views default to an empty array');
    Assert.areEqual('', twoArg.lastSelectedViewId, 'two-arg constructor has no selected view');

    UserPreferenceModels.PreferenceResult threeArg = new UserPreferenceModels.PreferenceResult(
      userId(),
      '[{"id":"v1"}]',
      'v1'
    );
    Assert.areEqual('[{"id":"v1"}]', threeArg.viewsJson);
    Assert.areEqual('v1', threeArg.lastSelectedViewId);

    UserPreferenceModels.PreferenceResult blanks = new UserPreferenceModels.PreferenceResult(
      null,
      '  ',
      '  '
    );
    Assert.areEqual('[]', blanks.viewsJson, 'blank views normalize to []');
    Assert.areEqual('', blanks.lastSelectedViewId, 'blank selection normalizes to empty');

    blanks.preferenceId = userId();
    blanks.viewsJson = '[1]';
    blanks.lastSelectedViewId = 'x';
    Assert.areEqual(userId(), blanks.preferenceId);
    Assert.areEqual('[1]', blanks.viewsJson);
    Assert.areEqual('x', blanks.lastSelectedViewId);
  }

  @IsTest
  static void models_stateEntryResultDefaultsAndNormalizesBlanks() {
    UserPreferenceModels.StateEntryResult empty = new UserPreferenceModels.StateEntryResult();
    Assert.isNull(empty.preferenceId);
    Assert.areEqual('{}', empty.entryJson);

    UserPreferenceModels.StateEntryResult blank = new UserPreferenceModels.StateEntryResult(
      userId(),
      ' '
    );
    Assert.areEqual(userId(), blank.preferenceId);
    Assert.areEqual('{}', blank.entryJson, 'blank entry normalizes to {}');

    UserPreferenceModels.StateEntryResult filled = new UserPreferenceModels.StateEntryResult(
      userId(),
      '{"a":1}'
    );
    Assert.areEqual('{"a":1}', filled.entryJson);

    filled.preferenceId = null;
    filled.entryJson = '{"b":2}';
    Assert.isNull(filled.preferenceId);
    Assert.areEqual('{"b":2}', filled.entryJson);
  }

  // ---------------------------------------------------------------------------
  // UserPreferenceService - saved views
  // ---------------------------------------------------------------------------

  @IsTest
  static void service_getSavedViews_returnsEmptyResultWhenNoPreferenceOrBlankState() {
    UserPreferenceService service = new UserPreferenceService(new UserPreferenceRepository());

    UserPreferenceModels.PreferenceResult none = service.getSavedViews(userId(), APP_NAME, null);
    Assert.isNull(none.preferenceId, 'no row yet');
    Assert.areEqual('[]', none.viewsJson);
    Assert.areEqual('', none.lastSelectedViewId);

    insertPreference(APP_NAME, null);
    UserPreferenceModels.PreferenceResult blank = service.getSavedViews(userId(), APP_NAME, RECORD_KEY);
    Assert.isNull(blank.preferenceId, 'a row with blank state is treated as absent');
    Assert.areEqual('[]', blank.viewsJson);
    Assert.areEqual('', blank.lastSelectedViewId);
  }

  @IsTest
  static void service_getSavedViews_resolvesGlobalAndRecordContexts() {
    String state = JSON.serialize(
      new Map<String, Object>{
        'version' => 1,
        'contexts' => new Map<String, Object>{
          'global' => new Map<String, Object>{
            'views' => new List<Object>{ new Map<String, Object>{ 'id' => 'v1' } },
            'lastSelectedViewId' => 'v1'
          },
          RECORD_KEY => new Map<String, Object>{
            'views' => new List<Object>{
              new Map<String, Object>{ 'id' => 'v2' },
              new Map<String, Object>{ 'id' => 'v3' }
            }
          }
        }
      }
    );
    User_Preference__c preference = insertPreference(APP_NAME, state);
    UserPreferenceService service = new UserPreferenceService();

    UserPreferenceModels.PreferenceResult globalResult = service.getSavedViews(userId(), APP_NAME, '');
    Assert.areEqual(preference.Id, globalResult.preferenceId);
    List<Object> globalViews = parseList(globalResult.viewsJson);
    Assert.areEqual(1, globalViews.size());
    Assert.areEqual('v1', ((Map<String, Object>) globalViews[0]).get('id'));
    Assert.areEqual('v1', globalResult.lastSelectedViewId);

    UserPreferenceModels.PreferenceResult recordResult = service.getSavedViews(userId(), APP_NAME, RECORD_KEY);
    Assert.areEqual(preference.Id, recordResult.preferenceId);
    Assert.areEqual(2, parseList(recordResult.viewsJson).size());
    Assert.areEqual('', recordResult.lastSelectedViewId, 'no selection stored for the record context');

    UserPreferenceModels.PreferenceResult unknown = service.getSavedViews(userId(), APP_NAME, 'recordZ');
    Assert.areEqual('[]', unknown.viewsJson, 'unknown context has no views');
    Assert.areEqual('', unknown.lastSelectedViewId);
  }

  @IsTest
  static void service_getSavedViews_toleratesMalformedStateShapes() {
    User_Preference__c preference = insertPreference(
      APP_NAME,
      '{"contexts":{"global":"oops","' + RECORD_KEY + '":{"views":"notalist","lastSelectedViewId":5}}}'
    );
    UserPreferenceService service = new UserPreferenceService();

    UserPreferenceModels.PreferenceResult globalResult = service.getSavedViews(userId(), APP_NAME, null);
    Assert.areEqual('[]', globalResult.viewsJson, 'context that is not an object yields no views');
    Assert.areEqual('', globalResult.lastSelectedViewId);

    UserPreferenceModels.PreferenceResult recordResult = service.getSavedViews(userId(), APP_NAME, RECORD_KEY);
    Assert.areEqual('[]', recordResult.viewsJson, 'views that are not a list yield no views');
    Assert.areEqual('', recordResult.lastSelectedViewId, 'non-string selection is ignored');

    preference.State__c = '{"listViews":{}}';
    update preference;
    UserPreferenceModels.PreferenceResult noContexts = service.getSavedViews(userId(), APP_NAME, null);
    Assert.areEqual(preference.Id, noContexts.preferenceId);
    Assert.areEqual('[]', noContexts.viewsJson, 'missing contexts section is treated as empty');

    preference.State__c = 'this is not json';
    update preference;
    UserPreferenceModels.PreferenceResult corrupt = service.getSavedViews(userId(), APP_NAME, null);
    Assert.areEqual(preference.Id, corrupt.preferenceId, 'the row still exists');
    Assert.areEqual('[]', corrupt.viewsJson, 'corrupt state is replaced by an empty state');
    Assert.areEqual('', corrupt.lastSelectedViewId);
  }

  @IsTest
  static void service_getSavedViews_throwsWhenApplicationNameBlank() {
    try {
      new UserPreferenceService().getSavedViews(userId(), ' ', null);
      Assert.fail('blank application name should be rejected');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'AuraHandledException thrown');
    }
  }

  @IsTest
  static void service_saveSavedViews_insertsNewRowForGlobalContext() {
    UserPreferenceService service = new UserPreferenceService();
    String viewsJson = '[{"id":"v1","label":"Mine"}]';

    Test.startTest();
    UserPreferenceModels.PreferenceResult result = service.saveSavedViews(
      userId(),
      APP_NAME,
      null,
      viewsJson,
      'v1'
    );
    Test.stopTest();

    Assert.isNotNull(result.preferenceId, 'a row was created');
    Assert.areEqual(viewsJson, result.viewsJson);
    Assert.areEqual('v1', result.lastSelectedViewId);
    Assert.areEqual(1, countPreferences());

    User_Preference__c row = queryPreference(result.preferenceId);
    Assert.areEqual(userId(), row.User__c);
    Assert.areEqual(APP_NAME, row.Application_Name__c);

    Map<String, Object> state = parseState(result.preferenceId);
    Assert.areEqual(1, state.get('version'));
    Assert.isTrue(String.isNotBlank((String) state.get('updatedAt')), 'updatedAt stamped');
    Map<String, Object> globalContext = section(section(state, 'contexts'), 'global');
    Assert.areEqual(1, ((List<Object>) globalContext.get('views')).size());
    Assert.areEqual('v1', globalContext.get('lastSelectedViewId'));

    UserPreferenceModels.PreferenceResult reloaded = service.getSavedViews(userId(), APP_NAME, null);
    Assert.areEqual(result.preferenceId, reloaded.preferenceId);
    Assert.areEqual('v1', ((Map<String, Object>) parseList(reloaded.viewsJson)[0]).get('id'));
    Assert.areEqual('v1', reloaded.lastSelectedViewId);
  }

  @IsTest
  static void service_saveSavedViews_updatesExistingRowAndPreservesOtherSections() {
    User_Preference__c preference = insertPreference(
      APP_NAME,
      '{"version":1,"listViews":{"t1":{"tableId":"t1"}},"contexts":{"' + RECORD_KEY + '":{"views":[{"id":"x"}],"lastSelectedViewId":"x"}}}'
    );
    UserPreferenceService service = new UserPreferenceService();

    Test.startTest();
    UserPreferenceModels.PreferenceResult result = service.saveSavedViews(
      userId(),
      APP_NAME,
      null,
      '[{"id":"g1"}]',
      ''
    );
    Test.stopTest();

    Assert.areEqual(preference.Id, result.preferenceId, 'existing row is reused');
    Assert.areEqual('', result.lastSelectedViewId, 'blank selection stays blank');
    Assert.areEqual(1, countPreferences(), 'no duplicate row');

    Map<String, Object> state = parseState(preference.Id);
    Assert.isTrue(section(state, 'listViews').containsKey('t1'), 'unrelated section preserved');
    Map<String, Object> contexts = section(state, 'contexts');
    Assert.areEqual('x', section(contexts, RECORD_KEY).get('lastSelectedViewId'), 'other context preserved');
    Map<String, Object> globalContext = section(contexts, 'global');
    Assert.areEqual('g1', ((Map<String, Object>) ((List<Object>) globalContext.get('views'))[0]).get('id'));
    Assert.isFalse(globalContext.containsKey('lastSelectedViewId'), 'blank selection is not stored');

    UserPreferenceModels.PreferenceResult recordViews = service.getSavedViews(userId(), APP_NAME, RECORD_KEY);
    Assert.areEqual('x', recordViews.lastSelectedViewId, 'record context still readable');
  }

  @IsTest
  static void service_saveSavedViews_rejectsInvalidInputs() {
    UserPreferenceService service = new UserPreferenceService();

    try {
      service.saveSavedViews(userId(), '', null, '[]', null);
      Assert.fail('blank application name');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank application rejected');
    }

    try {
      service.saveSavedViews(userId(), APP_NAME, null, '  ', null);
      Assert.fail('blank views payload');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank payload rejected');
    }

    try {
      service.saveSavedViews(userId(), APP_NAME, null, '{"id":"v1"}', null);
      Assert.fail('views payload that is not an array');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'non-array payload rejected');
    }

    try {
      service.saveSavedViews(userId(), APP_NAME, null, '[not json', null);
      Assert.fail('invalid JSON views payload');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'invalid JSON rejected');
    }

    Assert.areEqual(0, countPreferences(), 'nothing persisted on validation failure');
  }

  @IsTest
  static void service_saveSavedViews_rejectsOversizedState() {
    String oversized = '["' + 'a'.repeat(UserPreferenceModels.MAX_STATE_LENGTH) + '"]';

    try {
      new UserPreferenceService().saveSavedViews(userId(), APP_NAME, null, oversized, null);
      Assert.fail('state larger than MAX_STATE_LENGTH should be rejected');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'oversized state rejected');
    }

    Assert.areEqual(0, countPreferences());
  }

  // ---------------------------------------------------------------------------
  // UserPreferenceService - state entries
  // ---------------------------------------------------------------------------

  @IsTest
  static void service_getStateEntry_returnsEmptyObjectWhenMissing() {
    UserPreferenceService service = new UserPreferenceService();

    UserPreferenceModels.StateEntryResult none = service.getStateEntry(userId(), APP_NAME, LIST_VIEWS, 't1');
    Assert.isNull(none.preferenceId);
    Assert.areEqual('{}', none.entryJson);

    User_Preference__c preference = insertPreference(
      APP_NAME,
      '{"version":1,"listViews":{"t1":{"tableId":"t1","columns":["a"]}}}'
    );

    UserPreferenceModels.StateEntryResult missingEntry = service.getStateEntry(userId(), APP_NAME, LIST_VIEWS, 't9');
    Assert.areEqual(preference.Id, missingEntry.preferenceId);
    Assert.areEqual('{}', missingEntry.entryJson, 'unknown entry');

    UserPreferenceModels.StateEntryResult missingSection = service.getStateEntry(userId(), APP_NAME, 'widgets', 't1');
    Assert.areEqual('{}', missingSection.entryJson, 'unknown section');

    preference.State__c = '{"listViews":"bad"}';
    update preference;
    UserPreferenceModels.StateEntryResult badSection = service.getStateEntry(userId(), APP_NAME, LIST_VIEWS, 't1');
    Assert.areEqual('{}', badSection.entryJson, 'section that is not an object is treated as empty');

    preference.State__c = null;
    update preference;
    UserPreferenceModels.StateEntryResult blankState = service.getStateEntry(userId(), APP_NAME, LIST_VIEWS, 't1');
    Assert.isNull(blankState.preferenceId, 'blank state is treated as absent');
    Assert.areEqual('{}', blankState.entryJson);
  }

  @IsTest
  static void service_getStateEntry_returnsEntryAndNormalizesKey() {
    User_Preference__c preference = insertPreference(
      APP_NAME,
      '{"version":1,"listViews":{"t1":{"tableId":"t1","columns":["a","b"]}}}'
    );
    UserPreferenceService service = new UserPreferenceService();

    UserPreferenceModels.StateEntryResult exact = service.getStateEntry(userId(), APP_NAME, LIST_VIEWS, 't1');
    Assert.areEqual(preference.Id, exact.preferenceId);
    Map<String, Object> entry = parseObject(exact.entryJson);
    Assert.areEqual('t1', entry.get('tableId'));
    Assert.areEqual(2, ((List<Object>) entry.get('columns')).size());

    UserPreferenceModels.StateEntryResult slashes = service.getStateEntry(userId(), APP_NAME, LIST_VIEWS, ' t1/// ');
    Assert.areEqual('t1', parseObject(slashes.entryJson).get('tableId'), 'trailing slashes and whitespace are stripped');

    UserPreferenceModels.StateEntryResult viaListView = service.getListViewPreference(userId(), APP_NAME, 't1');
    Assert.areEqual(exact.entryJson, viaListView.entryJson, 'list-view helper reads the listViews section');
  }

  @IsTest
  static void service_getStateEntry_rejectsBlankKeys() {
    UserPreferenceService service = new UserPreferenceService();

    try {
      service.getStateEntry(userId(), '', LIST_VIEWS, 't1');
      Assert.fail('blank application');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank application rejected');
    }

    try {
      service.getStateEntry(userId(), APP_NAME, ' ', 't1');
      Assert.fail('blank section key');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank section rejected');
    }

    try {
      service.getStateEntry(userId(), APP_NAME, LIST_VIEWS, null);
      Assert.fail('blank entry key');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank entry rejected');
    }
  }

  @IsTest
  static void service_saveStateEntry_insertsRowAndStampsEntryIdField() {
    UserPreferenceService service = new UserPreferenceService();

    Test.startTest();
    UserPreferenceModels.StateEntryResult result = service.saveListViewPreference(
      userId(),
      APP_NAME,
      't1/',
      '{"columns":["a","b"]}'
    );
    Test.stopTest();

    Assert.isNotNull(result.preferenceId, 'a row was created');
    Map<String, Object> entry = parseObject(result.entryJson);
    Assert.areEqual('t1', entry.get('tableId'), 'entry id field is stamped with the normalized key');
    Assert.areEqual(2, ((List<Object>) entry.get('columns')).size());

    Map<String, Object> state = parseState(result.preferenceId);
    Assert.areEqual(1, state.get('version'));
    Assert.isTrue(String.isNotBlank((String) state.get('updatedAt')));
    Assert.isTrue(state.containsKey('contexts'), 'new state carries the contexts section');
    Assert.areEqual('t1', section(section(state, LIST_VIEWS), 't1').get('tableId'));

    UserPreferenceModels.StateEntryResult reloaded = service.getListViewPreference(userId(), APP_NAME, 't1');
    Assert.areEqual(result.preferenceId, reloaded.preferenceId);
    Assert.areEqual('t1', parseObject(reloaded.entryJson).get('tableId'));
  }

  @IsTest
  static void service_saveStateEntry_updatesExistingSectionPreservingSiblings() {
    User_Preference__c preference = insertPreference(
      APP_NAME,
      '{"version":1,"contexts":{"global":{"views":[]}},"listViews":{"t1":{"tableId":"t1","columns":["a"]},"t2":{"tableId":"t2"}}}'
    );
    UserPreferenceService service = new UserPreferenceService();

    Test.startTest();
    UserPreferenceModels.StateEntryResult result = service.saveStateEntry(
      userId(),
      APP_NAME,
      LIST_VIEWS,
      't1',
      '{"columns":["z"]}'
    );
    Test.stopTest();

    Assert.areEqual(preference.Id, result.preferenceId, 'existing row reused');
    Map<String, Object> entry = parseObject(result.entryJson);
    Assert.isFalse(entry.containsKey('tableId'), 'the five-argument overload stamps no id field');
    Assert.areEqual('z', ((List<Object>) entry.get('columns'))[0]);
    Assert.areEqual(1, countPreferences());

    Map<String, Object> state = parseState(preference.Id);
    Map<String, Object> listViews = section(state, LIST_VIEWS);
    Assert.areEqual('z', ((List<Object>) section(listViews, 't1').get('columns'))[0], 't1 replaced');
    Assert.areEqual('t2', section(listViews, 't2').get('tableId'), 'sibling entry preserved');
    Assert.isTrue(section(state, 'contexts').containsKey('global'), 'unrelated section preserved');
  }

  @IsTest
  static void service_saveStateEntry_replacesSectionThatIsNotAnObject() {
    User_Preference__c preference = insertPreference(APP_NAME, '{"contexts":{},"listViews":"bad"}');

    UserPreferenceModels.StateEntryResult result = new UserPreferenceService().saveListViewPreference(
      userId(),
      APP_NAME,
      't1',
      '{"tableId":"t1","columns":[]}'
    );

    Assert.areEqual(preference.Id, result.preferenceId);
    Map<String, Object> listViews = section(parseState(preference.Id), LIST_VIEWS);
    Assert.areEqual('t1', section(listViews, 't1').get('tableId'), 'corrupt section replaced by an object');
  }

  @IsTest
  static void service_saveStateEntry_acceptsMatchingIdWithTrailingSlash() {
    UserPreferenceModels.StateEntryResult result = new UserPreferenceService().saveListViewPreference(
      userId(),
      APP_NAME,
      't1/',
      '{"tableId":"t1"}'
    );

    Assert.isNotNull(result.preferenceId);
    Assert.areEqual('t1', parseObject(result.entryJson).get('tableId'), 'payload id matching the normalized key is accepted');
  }

  @IsTest
  static void service_saveStateEntry_rejectsInvalidInputs() {
    UserPreferenceService service = new UserPreferenceService();

    try {
      service.saveStateEntry(userId(), null, LIST_VIEWS, 't1', '{}');
      Assert.fail('blank application');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank application rejected');
    }

    try {
      service.saveStateEntry(userId(), APP_NAME, '', 't1', '{}');
      Assert.fail('blank section key');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank section rejected');
    }

    try {
      service.saveStateEntry(userId(), APP_NAME, LIST_VIEWS, ' ', '{}');
      Assert.fail('blank entry key');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank entry rejected');
    }

    try {
      service.saveStateEntry(userId(), APP_NAME, LIST_VIEWS, 't1', '');
      Assert.fail('blank entry payload');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'blank payload rejected');
    }

    try {
      service.saveStateEntry(userId(), APP_NAME, LIST_VIEWS, 't1', '[1,2]');
      Assert.fail('entry payload that is not an object');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'non-object payload rejected');
    }

    try {
      service.saveStateEntry(userId(), APP_NAME, LIST_VIEWS, 't1', '{bad json');
      Assert.fail('invalid JSON entry payload');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'invalid JSON rejected');
    }

    try {
      service.saveListViewPreference(userId(), APP_NAME, 't1', '{"tableId":"t2"}');
      Assert.fail('payload id that differs from the entry key');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'mismatched id rejected');
    }

    Assert.areEqual(0, countPreferences(), 'nothing persisted on validation failure');
  }

  @IsTest
  static void service_saveStateEntry_rejectsOversizedState() {
    String oversized = '{"blob":"' + 'a'.repeat(UserPreferenceModels.MAX_STATE_LENGTH) + '"}';

    try {
      new UserPreferenceService().saveStateEntry(userId(), APP_NAME, 'widgets', 'w1', oversized);
      Assert.fail('state larger than MAX_STATE_LENGTH should be rejected');
    } catch (AuraHandledException expected) {
      Assert.isTrue(true, 'oversized state rejected');
    }

    Assert.areEqual(0, countPreferences());
  }

  // ---------------------------------------------------------------------------
  // UserPreferenceController
  // ---------------------------------------------------------------------------

  @IsTest
  static void controller_savedViewsRoundTripForRunningUser() {
    UserPreferenceModels.PreferenceResult empty = UserPreferenceController.getSavedViews(APP_NAME, null);
    Assert.isNull(empty.preferenceId);
    Assert.areEqual('[]', empty.viewsJson);

    Test.startTest();
    UserPreferenceModels.PreferenceResult saved = UserPreferenceController.saveSavedViews(
      APP_NAME,
      RECORD_KEY,
      '[{"id":"v1"}]',
      'v1'
    );
    Test.stopTest();

    Assert.isNotNull(saved.preferenceId);
    Assert.areEqual('[{"id":"v1"}]', saved.viewsJson);
    Assert.areEqual('v1', saved.lastSelectedViewId);
    Assert.areEqual(UserInfo.getUserId(), queryPreference(saved.preferenceId).User__c, 'row belongs to the running user');

    UserPreferenceModels.PreferenceResult fetched = UserPreferenceController.getSavedViews(APP_NAME, RECORD_KEY);
    Assert.areEqual(saved.preferenceId, fetched.preferenceId);
    Assert.areEqual(1, parseList(fetched.viewsJson).size());
    Assert.areEqual('v1', fetched.lastSelectedViewId);

    UserPreferenceModels.PreferenceResult globalViews = UserPreferenceController.getSavedViews(APP_NAME, null);
    Assert.areEqual('[]', globalViews.viewsJson, 'record context does not leak into global');
  }

  @IsTest
  static void controller_stateEntryRoundTripForRunningUser() {
    UserPreferenceModels.StateEntryResult empty = UserPreferenceController.getStateEntry(APP_NAME, 'widgets', 'w1');
    Assert.isNull(empty.preferenceId);
    Assert.areEqual('{}', empty.entryJson);

    Test.startTest();
    UserPreferenceModels.StateEntryResult saved = UserPreferenceController.saveStateEntry(
      APP_NAME,
      'widgets',
      'w1',
      '{"collapsed":true}'
    );
    Test.stopTest();

    Assert.isNotNull(saved.preferenceId);
    Assert.areEqual(true, parseObject(saved.entryJson).get('collapsed'));

    UserPreferenceModels.StateEntryResult fetched = UserPreferenceController.getStateEntry(APP_NAME, 'widgets', 'w1');
    Assert.areEqual(saved.preferenceId, fetched.preferenceId);
    Assert.areEqual(true, parseObject(fetched.entryJson).get('collapsed'));
  }

  @IsTest
  static void controller_listViewPreferenceRoundTripForRunningUser() {
    UserPreferenceModels.StateEntryResult empty = UserPreferenceController.getListViewPreference(APP_NAME, 't1');
    Assert.isNull(empty.preferenceId);
    Assert.areEqual('{}', empty.entryJson);

    Test.startTest();
    UserPreferenceModels.StateEntryResult saved = UserPreferenceController.saveListViewPreference(
      APP_NAME,
      't1',
      '{"columns":["a"]}'
    );
    Test.stopTest();

    Assert.isNotNull(saved.preferenceId);
    Assert.areEqual('t1', parseObject(saved.entryJson).get('tableId'), 'tableId stamped on the entry');

    UserPreferenceModels.StateEntryResult fetched = UserPreferenceController.getListViewPreference(APP_NAME, 't1');
    Assert.areEqual(saved.preferenceId, fetched.preferenceId);
    Assert.areEqual('t1', parseObject(fetched.entryJson).get('tableId'));
    Assert.areEqual(1, countPreferences(), 'one row per user and application');
  }
}
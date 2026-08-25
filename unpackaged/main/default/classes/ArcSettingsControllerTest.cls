/**
 * Author: Claude
 *
 * Covers ArcSettingsController. The fixture is the running user — the class
 * only ever reads and writes UserInfo.getUserId(), so no User is inserted and
 * no org data is assumed. Each test starts from whatever User_Preference__c
 * rows the running user has for this application name, which is none, because
 * the name is namespaced to this screen.
 */
@IsTest
private class ArcSettingsControllerTest {
  private static final String APPLICATION_NAME = 'arcSettings.notifications';

  @IsTest
  static void loadReturnsEmptyObjectWhenNothingSaved() {
    Test.startTest();
    String result = ArcSettingsController.loadNotificationPreferences();
    Test.stopTest();

    Assert.areEqual(
      '{}',
      result,
      'A user with no saved row reads an empty map'
    );
  }

  @IsTest
  static void saveThenLoadRoundTripsTheChoices() {
    String state = JSON.serialize(
      new Map<String, String>{
        'new-messages' => 'email',
        'account-activity' => 'none'
      }
    );

    Test.startTest();
    ArcSettingsController.saveNotificationPreferences(state);
    String reloaded = ArcSettingsController.loadNotificationPreferences();
    Test.stopTest();

    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      reloaded
    );
    Assert.areEqual(2, parsed.size(), 'Both choices survive the round trip');
    Assert.areEqual(
      'email',
      parsed.get('new-messages'),
      'Channel is stored per key'
    );
    Assert.areEqual(
      'none',
      parsed.get('account-activity'),
      'Channel is stored per key'
    );
  }

  @IsTest
  static void saveUpdatesTheExistingRowRatherThanAddingOne() {
    ArcSettingsController.saveNotificationPreferences(
      JSON.serialize(new Map<String, String>{ 'new-messages' => 'email' })
    );

    Test.startTest();
    ArcSettingsController.saveNotificationPreferences(
      JSON.serialize(new Map<String, String>{ 'new-messages' => 'all' })
    );
    Test.stopTest();

    List<User_Preference__c> rows = [
      SELECT Id, State__c
      FROM User_Preference__c
      WHERE
        User__c = :UserInfo.getUserId()
        AND Application_Name__c = :APPLICATION_NAME
    ];

    Assert.areEqual(
      1,
      rows.size(),
      'A second save reuses the row instead of adding one'
    );
    Assert.isTrue(
      rows[0].State__c.contains('all'),
      'The row carries the newer choice'
    );
  }

  @IsTest
  static void saveDropsChannelsOutsideTheAllowlist() {
    String state = JSON.serialize(
      new Map<String, String>{
        'new-messages' => 'sms',
        'account-activity' => 'in-app'
      }
    );

    Test.startTest();
    String cleaned = ArcSettingsController.saveNotificationPreferences(state);
    Test.stopTest();

    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      cleaned
    );
    Assert.areEqual(1, parsed.size(), 'Only the allowlisted channel is kept');
    Assert.isNull(parsed.get('new-messages'), 'An unknown channel is dropped');
    Assert.areEqual(
      'in-app',
      parsed.get('account-activity'),
      'A known channel is kept'
    );
  }

  @IsTest
  static void saveDropsNonStringValues() {
    Test.startTest();
    String cleaned = ArcSettingsController.saveNotificationPreferences(
      '{"new-messages": 42, "account-activity": "all"}'
    );
    Test.stopTest();

    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
      cleaned
    );
    Assert.areEqual(1, parsed.size(), 'A non-string channel is dropped');
    Assert.areEqual(
      'all',
      parsed.get('account-activity'),
      'The valid entry survives'
    );
  }

  @IsTest
  static void saveTreatsBlankStateAsAnEmptyMap() {
    Test.startTest();
    String cleaned = ArcSettingsController.saveNotificationPreferences('');
    Test.stopTest();

    Assert.areEqual('{}', cleaned, 'Blank input stores an empty map');
  }

  @IsTest
  static void saveRejectsStateThatIsNotJson() {
    Boolean threw = false;

    Test.startTest();
    try {
      ArcSettingsController.saveNotificationPreferences('not json');
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    Assert.isTrue(threw, 'Unparseable state is refused rather than stored');
  }

  @IsTest
  static void saveRejectsAnOversizedPayload() {
    Map<String, String> tooMany = new Map<String, String>();
    for (Integer i = 0; i < 51; i++) {
      tooMany.put('key-' + i, 'all');
    }

    Boolean threw = false;

    Test.startTest();
    try {
      ArcSettingsController.saveNotificationPreferences(
        JSON.serialize(tooMany)
      );
    } catch (Exception error) {
      threw = true;
    }
    Test.stopTest();

    Assert.isTrue(threw, 'A payload past the cap is refused');
  }
}
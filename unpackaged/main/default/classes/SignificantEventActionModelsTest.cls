/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class SignificantEventActionModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    SignificantEventActionModels.CreateContext createContext = new SignificantEventActionModels.CreateContext();
    SignificantEventActionModels.SignificantEventFormData formData = new SignificantEventActionModels.SignificantEventFormData();
    SignificantEventActionModels.LinkedAccountOption linkedAccountOption = new SignificantEventActionModels.LinkedAccountOption();
    SignificantEventActionModels.SuggestedContactGroup suggestedContactGroup = new SignificantEventActionModels.SuggestedContactGroup();
    SignificantEventActionModels.SaveRequest saveRequest = new SignificantEventActionModels.SaveRequest();
    SignificantEventActionModels.SignificantEventRow significantEventRow = new SignificantEventActionModels.SignificantEventRow();
    SignificantEventActionModels.LinkedContactRow linkedContactRow = new SignificantEventActionModels.LinkedContactRow();

    System.assertEquals(false, createContext.isHouseholdLaunch);
    System.assertEquals(false, createContext.isEditMode);
    System.assertNotEquals(null, createContext.defaultSelectedAccounts);
    System.assertEquals(false, formData.approximateDate);
    System.assertNotEquals(null, formData.selectedAccounts);
    System.assertEquals(false, linkedAccountOption.isHouseholdRelated);
    System.assertNotEquals(null, suggestedContactGroup.contacts);
    System.assertEquals(false, saveRequest.approximateDate);
    System.assertNotEquals(null, saveRequest.linkedAccountIds);
    System.assertEquals(false, significantEventRow.approximateDate);
    System.assertEquals(false, linkedContactRow.approximateDate);

    SignificantEventActionModels.SaveResult saveResult = new SignificantEventActionModels.SaveResult();
    System.assertEquals(false, saveResult.success);
    System.assertEquals('', saveResult.message);
  }

  @IsTest
  static void parameterizedConstructors_assignProvidedValues() {
    SignificantEventActionModels.LinkedAccountOption linkedAccountOption = new SignificantEventActionModels.LinkedAccountOption(
      '001000000000001AAA',
      'Test Account',
      true
    );
    SignificantEventActionModels.SuggestedContactGroup suggestedContactGroup = new SignificantEventActionModels.SuggestedContactGroup(
      'Clients',
      new List<SignificantEventActionModels.LinkedAccountOption>{ linkedAccountOption }
    );
    SignificantEventActionModels.SaveResult saveResult = new SignificantEventActionModels.SaveResult(
      true,
      'Saved',
      'a0X000000000001AAA'
    );
    SignificantEventActionModels.SignificantEventRow significantEventRow = new SignificantEventActionModels.SignificantEventRow(
      'a0X000000000001AAA',
      'Birthday',
      'Birthday'
    );
    SignificantEventActionModels.LinkedContactRow linkedContactRow = new SignificantEventActionModels.LinkedContactRow(
      'a0Y000000000001AAA',
      '001000000000001AAA'
    );

    System.assertEquals('001000000000001AAA', linkedAccountOption.accountId);
    System.assertEquals('Test Account', linkedAccountOption.name);
    System.assertEquals(true, linkedAccountOption.isHouseholdRelated);
    System.assertEquals('Clients', suggestedContactGroup.category);
    System.assertEquals(1, suggestedContactGroup.contacts.size());
    System.assertEquals(true, saveResult.success);
    System.assertEquals('Saved', saveResult.message);
    System.assertEquals('a0X000000000001AAA', saveResult.significantEventId);
    System.assertEquals('Birthday', significantEventRow.eventName);
    System.assertEquals('Birthday', significantEventRow.eventType);
    System.assertEquals('a0Y000000000001AAA', linkedContactRow.participantId);
    System.assertEquals('001000000000001AAA', linkedContactRow.accountId);
  }

  @IsTest
  static void suggestedContactGroup_nullContacts_initializesEmptyList() {
    SignificantEventActionModels.SuggestedContactGroup suggestedContactGroup = new SignificantEventActionModels.SuggestedContactGroup(
      'Network',
      null
    );

    System.assertEquals('Network', suggestedContactGroup.category);
    System.assertNotEquals(null, suggestedContactGroup.contacts);
    System.assertEquals(0, suggestedContactGroup.contacts.size());
  }
}
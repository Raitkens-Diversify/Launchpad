/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-21
 */
@IsTest
private class FscRelRelationshipTreeModelsTest {
  @IsTest
  static void defaultConstructors_initializeDtoDefaults() {
    FscRelRelationshipTreeModels.ScopedAccountSummary scopedAccountSummary = new FscRelRelationshipTreeModels.ScopedAccountSummary();
    FscRelRelationshipTreeModels.GroupedAccountContacts groupedAccountContacts = new FscRelRelationshipTreeModels.GroupedAccountContacts();

    System.assertEquals(false, scopedAccountSummary.isHouseholdRelated);
    System.assertNotEquals(null, groupedAccountContacts.contacts);
  }
}
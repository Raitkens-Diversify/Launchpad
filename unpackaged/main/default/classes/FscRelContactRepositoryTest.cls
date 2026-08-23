/**
 * Author: Hoang Long Vu To
 * Date: 2026-07-22
 */
@IsTest
private class FscRelContactRepositoryTest {
  @TestSetup
  static void setup() {
    FscDataTestDataFactory.createTreeScenario();
  }

  @IsTest
  static void selectById_returnsContactWhenFound() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelContactRepository repository = new FscRelContactRepository();

    Test.startTest();
    Contact contact = repository.selectById(
      scenario.linkedPersonAccount.PersonContactId
    );
    Contact missingContact = repository.selectById(null);
    Test.stopTest();

    System.assertNotEquals(null, contact);
    System.assertEquals(scenario.linkedPersonAccount.PersonContactId, contact.Id);
    System.assertEquals(null, missingContact);
  }

  @IsTest
  static void selectNameById_returnsContactName() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelContactRepository repository = new FscRelContactRepository();

    Test.startTest();
    String contactName = repository.selectNameById(
      scenario.linkedPersonAccount.PersonContactId
    );
    Test.stopTest();

    System.assertNotEquals(null, contactName);
  }

  @IsTest
  static void searchContactsByName_returnsMatchesAndGuardsShortTerms() {
    FscDataTestDataFactory.TreeScenario scenario = FscDataTestDataFactory.loadTreeScenario();
    FscRelContactRepository repository = new FscRelContactRepository();

    Test.startTest();
    List<Contact> shortTermResults = repository.searchContactsByName('F', 8);
    List<Contact> results = repository.searchContactsByName('FscData', 8);
    List<Contact> defaultLimitResults = repository.searchContactsByName('FscData', null);
    Test.stopTest();

    System.assertEquals(true, shortTermResults.isEmpty());
    System.assert(!results.isEmpty());
    System.assert(
      results[0].Id == scenario.linkedPersonAccount.PersonContactId ||
      results[0].Id == scenario.secondPersonAccount.PersonContactId
    );
    System.assert(!defaultLimitResults.isEmpty());
  }

  @IsTest
  static void searchContactsByName_matchesAccentInsensitiveNames() {
    Contact accentedContact = new Contact(
      FirstName = 'José',
      LastName = 'García'
    );
    insert accentedContact;
    FscRelContactRepository repository = new FscRelContactRepository();

    Test.startTest();
    List<Contact> unaccentedResults = repository.searchContactsByName(
      'jose garcia',
      8
    );
    Test.stopTest();

    System.assert(!unaccentedResults.isEmpty());
    System.assertEquals(accentedContact.Id, unaccentedResults[0].Id);
  }
}
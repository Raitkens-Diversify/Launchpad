/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-20
 */
@IsTest
private class FscRelNameSearchUtilsTest {
  @IsTest
  static void tokenizeSearchTerm_splitsOnWhitespaceAndTrims() {
    List<String> tokens = FscRelNameSearchUtils.tokenizeSearchTerm(
      '  abigail   f   holland  '
    );

    System.assertEquals(3, tokens.size());
    System.assertEquals('abigail', tokens[0]);
    System.assertEquals('f', tokens[1]);
    System.assertEquals('holland', tokens[2]);
    System.assertEquals(true, FscRelNameSearchUtils.tokenizeSearchTerm(null).isEmpty());
    System.assertEquals(true, FscRelNameSearchUtils.tokenizeSearchTerm('   ').isEmpty());
  }

  @IsTest
  static void buildPersonNameTokenWhereClause_matchesAcrossNameParts() {
    String whereClause = FscRelNameSearchUtils.buildPersonNameTokenWhereClause(
      new List<String>{ 'abigail', 'f', 'holland' }
    );

    System.assert(whereClause.contains('FirstName LIKE \'%abigail%\''));
    System.assert(whereClause.contains('MiddleName = \'f\''));
    System.assert(whereClause.contains('LastName LIKE \'%holland%\''));
    System.assert(whereClause.contains(' AND '));
  }

  @IsTest
  static void buildNameTokenWhereClause_usesNameOnly() {
    String whereClause = FscRelNameSearchUtils.buildNameTokenWhereClause(
      new List<String>{ 'vendor' }
    );

    System.assert(whereClause.contains('Name LIKE \'%vendor%\''));
    System.assertEquals(false, whereClause.contains('FirstName'));
  }

  @IsTest
  static void buildPersonNameTokenWhereClause_usesStrictMatchingForSingleCharacterTokens() {
    String whereClause = FscRelNameSearchUtils.buildPersonNameTokenWhereClause(
      new List<String>{ 'Carl', 'T' }
    );

    System.assert(whereClause.contains('FirstName LIKE \'%Carl%\''));
    System.assert(whereClause.contains('MiddleName = \'T\''));
    System.assert(whereClause.contains('LastName LIKE \'T%\''));
    System.assert(whereClause.contains('Name LIKE \'% T %\''));
    System.assertEquals(false, whereClause.contains('LastName LIKE \'%T%\''));
    System.assertEquals(false, whereClause.contains('FirstName LIKE \'%T%\''));
  }

  @IsTest
  static void resolveSearchQueryLimit_expandsWhenShortTokensPresent() {
    System.assertEquals(
      50,
      FscRelNameSearchUtils.resolveSearchQueryLimit(
        new List<String>{ 'Carl', 'T' },
        8
      )
    );
    System.assertEquals(
      8,
      FscRelNameSearchUtils.resolveSearchQueryLimit(
        new List<String>{ 'Carl' },
        8
      )
    );
  }

  @IsTest
  static void rankAccountsByNameTokens_prioritizesExactWordMatches() {
    Account exactMatch = new Account(Name = 'Carl T Primary');
    Account partialMatch = new Account(Name = 'Anthony CARLOS');
    List<Account> rankedAccounts = FscRelNameSearchUtils.rankAccountsByNameTokens(
      new List<Account>{ partialMatch, exactMatch },
      new List<String>{ 'Carl', 'T' },
      1
    );

    System.assertEquals(1, rankedAccounts.size());
    System.assertEquals(exactMatch.Name, rankedAccounts[0].Name);
  }

  @IsTest
  static void stripAccents_removesCommonLatinDiacritics() {
    System.assertEquals('Jose Garcia', FscRelNameSearchUtils.stripAccents('José García'));
    System.assertEquals('nino', FscRelNameSearchUtils.stripAccents('niño'));
    System.assertEquals('resume', FscRelNameSearchUtils.stripAccents('résumé'));
  }

  @IsTest
  static void buildTokenAccentVariants_includesStrippedAndAccentedForms() {
    List<String> joseVariants = FscRelNameSearchUtils.buildTokenAccentVariants('jose');
    List<String> garciaVariants = FscRelNameSearchUtils.buildTokenAccentVariants('garcia');

    System.assert(joseVariants.contains('jose'));
    System.assert(joseVariants.contains('josé'));
    System.assert(garciaVariants.contains('garcia'));
    System.assert(garciaVariants.contains('garcía'));
  }

  @IsTest
  static void buildPersonNameTokenWhereClause_matchesAccentInsensitiveTokens() {
    String whereClause = FscRelNameSearchUtils.buildPersonNameTokenWhereClause(
      new List<String>{ 'jose', 'garcia' }
    );

    System.assert(whereClause.contains('FirstName LIKE \'%josé%\''));
    System.assert(whereClause.contains('LastName LIKE \'%garcía%\''));
  }

  @IsTest
  static void rankAccountsByNameTokens_matchesAccentInsensitiveTokens() {
    Account accentedMatch = new Account(Name = 'José García');
    Account unrelatedMatch = new Account(Name = 'John Smith');
    List<Account> rankedAccounts = FscRelNameSearchUtils.rankAccountsByNameTokens(
      new List<Account>{ unrelatedMatch, accentedMatch },
      new List<String>{ 'jose', 'garcia' },
      1
    );

    System.assertEquals(1, rankedAccounts.size());
    System.assertEquals(accentedMatch.Name, rankedAccounts[0].Name);
  }
}
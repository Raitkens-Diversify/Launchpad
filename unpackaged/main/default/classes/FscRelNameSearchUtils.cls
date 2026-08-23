/**
 * Author: Hoang Long Vu To
 * Date: 2026-08-20
 *
 * Tokenized name search helpers for FSC Relationship lookup components.
 */
public with sharing class FscRelNameSearchUtils {
  private static final Integer SHORT_TOKEN_MAX_LENGTH = 1;

  private static final Map<String, List<String>> LETTER_TO_ACCENT_VARIANTS = new Map<String, List<String>>{
    'a' => new List<String>{ 'á', 'à', 'â', 'ä', 'ã', 'å' },
    'c' => new List<String>{ 'ç' },
    'e' => new List<String>{ 'é', 'è', 'ê', 'ë' },
    'i' => new List<String>{ 'í', 'ì', 'î', 'ï' },
    'n' => new List<String>{ 'ñ' },
    'o' => new List<String>{ 'ó', 'ò', 'ô', 'ö', 'õ' },
    'u' => new List<String>{ 'ú', 'ù', 'û', 'ü' },
    'y' => new List<String>{ 'ý', 'ÿ' }
  };

  private static final Map<String, String> ACCENTED_TO_BASE = buildAccentedToBaseMap();

  private static Map<String, String> buildAccentedToBaseMap() {
    Map<String, String> accentedToBase = new Map<String, String>();

    for (String baseLetter : LETTER_TO_ACCENT_VARIANTS.keySet()) {
      for (String accentedLetter : LETTER_TO_ACCENT_VARIANTS.get(baseLetter)) {
        accentedToBase.put(accentedLetter, baseLetter);
        accentedToBase.put(accentedLetter.toUpperCase(), baseLetter.toUpperCase());
      }
    }

    return accentedToBase;
  }

  public static List<String> tokenizeSearchTerm(String searchTerm) {
    List<String> tokens = new List<String>();

    if (String.isBlank(searchTerm)) {
      return tokens;
    }

    for (String part : searchTerm.trim().split('\\s+')) {
      if (String.isNotBlank(part)) {
        tokens.add(part.trim());
      }
    }

    return tokens;
  }

  public static String toLikePattern(String value) {
    return '%' + String.escapeSingleQuotes(value) + '%';
  }

  public static String stripAccents(String value) {
    if (String.isBlank(value)) {
      return value;
    }

    String normalized = value;

    for (String accentedLetter : ACCENTED_TO_BASE.keySet()) {
      normalized = normalized.replace(
        accentedLetter,
        ACCENTED_TO_BASE.get(accentedLetter)
      );
    }

    return normalized;
  }

  public static List<String> buildTokenAccentVariants(String token) {
    Set<String> variants = new Set<String>();

    if (String.isBlank(token)) {
      return new List<String>();
    }

    String trimmedToken = token.trim();
    variants.add(trimmedToken);

    String strippedToken = stripAccents(trimmedToken);
    if (String.isNotBlank(strippedToken)) {
      variants.add(strippedToken);
    }

    String lowerToken = trimmedToken.toLowerCase();

    for (Integer index = 0; index < lowerToken.length(); index++) {
      String character = lowerToken.substring(index, index + 1);
      List<String> accentOptions = LETTER_TO_ACCENT_VARIANTS.get(character);

      if (accentOptions != null) {
        for (String accentedCharacter : accentOptions) {
          variants.add(
            trimmedToken.substring(0, index) +
              accentedCharacter +
              trimmedToken.substring(index + 1)
          );
        }
      }

      String baseCharacter = ACCENTED_TO_BASE.get(character);

      if (baseCharacter != null) {
        variants.add(
          trimmedToken.substring(0, index) +
            baseCharacter +
            trimmedToken.substring(index + 1)
        );
      }
    }

    return new List<String>(variants);
  }

  public static Boolean hasShortToken(List<String> tokens) {
    if (tokens == null) {
      return false;
    }

    for (String token : tokens) {
      if (String.isNotBlank(token) && token.length() <= SHORT_TOKEN_MAX_LENGTH) {
        return true;
      }
    }

    return false;
  }

  public static Integer resolveSearchQueryLimit(
    List<String> tokens,
    Integer resultLimit
  ) {
    Integer safeResultLimit = resultLimit == null || resultLimit < 1 ? 8 : resultLimit;

    if (hasShortToken(tokens) || (tokens != null && tokens.size() > 1)) {
      return Math.min(Math.max(safeResultLimit * 6, 50), 200);
    }

    return safeResultLimit;
  }

  public static List<Account> rankAccountsByNameTokens(
    List<Account> accounts,
    List<String> tokens,
    Integer limitSize
  ) {
    Integer safeLimit = limitSize == null || limitSize < 1 ? 8 : limitSize;

    if (accounts == null || accounts.isEmpty() || tokens == null || tokens.isEmpty()) {
      return accounts == null ? new List<Account>() : accounts;
    }

    List<RankedAccount> rankedAccounts = new List<RankedAccount>();

    for (Account account : accounts) {
      Integer score = scoreNameAgainstTokens(account.Name, tokens);
      rankedAccounts.add(new RankedAccount(account, score));
    }

    rankedAccounts.sort();

    List<Account> rankedResults = new List<Account>();
    for (RankedAccount rankedAccount : rankedAccounts) {
      if (rankedResults.size() >= safeLimit) {
        break;
      }

      rankedResults.add(rankedAccount.account);
    }

    return rankedResults;
  }

  public static List<Contact> rankContactsByNameTokens(
    List<Contact> contacts,
    List<String> tokens,
    Integer limitSize
  ) {
    Integer safeLimit = limitSize == null || limitSize < 1 ? 8 : limitSize;

    if (contacts == null || contacts.isEmpty() || tokens == null || tokens.isEmpty()) {
      return contacts == null ? new List<Contact>() : contacts;
    }

    List<RankedContact> rankedContacts = new List<RankedContact>();

    for (Contact contact : contacts) {
      Integer score = scoreNameAgainstTokens(contact.Name, tokens);
      rankedContacts.add(new RankedContact(contact, score));
    }

    rankedContacts.sort();

    List<Contact> rankedResults = new List<Contact>();
    for (RankedContact rankedContact : rankedContacts) {
      if (rankedResults.size() >= safeLimit) {
        break;
      }

      rankedResults.add(rankedContact.contact);
    }

    return rankedResults;
  }

  public static String buildPersonNameTokenWhereClause(List<String> tokens) {
    return buildTokenWhereClause(
      tokens,
      new List<String>{ 'Name', 'FirstName', 'MiddleName', 'LastName' }
    );
  }

  public static String buildNameTokenWhereClause(List<String> tokens) {
    return buildTokenWhereClause(tokens, new List<String>{ 'Name' });
  }

  public static String buildContactNameTokenWhereClause(List<String> tokens) {
    return buildTokenWhereClause(
      tokens,
      new List<String>{ 'Name', 'FirstName', 'MiddleName', 'LastName' }
    );
  }

  private static String buildTokenWhereClause(
    List<String> tokens,
    List<String> fieldNames
  ) {
    if (tokens == null || tokens.isEmpty()) {
      return 'Id = null';
    }

    List<String> tokenGroups = new List<String>();

    for (String token : tokens) {
      tokenGroups.add('(' + buildSingleTokenConditions(token, fieldNames) + ')');
    }

    return String.join(tokenGroups, ' AND ');
  }

  private static String buildSingleTokenConditions(
    String token,
    List<String> fieldNames
  ) {
    if (String.isBlank(token)) {
      return 'Id = null';
    }

    if (token.length() <= SHORT_TOKEN_MAX_LENGTH && fieldNames.contains('MiddleName')) {
      return buildShortTokenConditions(token);
    }

    List<String> tokenVariants = buildTokenAccentVariants(token);
    List<String> fieldMatches = new List<String>();

    for (String fieldName : fieldNames) {
      for (String variant : tokenVariants) {
        fieldMatches.add(
          fieldName + ' LIKE \'' + toLikePattern(variant) + '\''
        );
      }
    }

    return String.join(fieldMatches, ' OR ');
  }

  private static String buildShortTokenConditions(String token) {
    List<String> tokenVariants = buildTokenAccentVariants(token);
    List<String> conditions = new List<String>();

    for (String variant : tokenVariants) {
      String escapedToken = String.escapeSingleQuotes(variant);
      String prefixPattern = '\'' + escapedToken + '%\'';
      conditions.addAll(
        new List<String>{
          'MiddleName = \'' + escapedToken + '\'',
          'MiddleName = \'' + escapedToken + '.\'',
          'FirstName LIKE ' + prefixPattern,
          'LastName LIKE ' + prefixPattern,
          'Name LIKE \'% ' + escapedToken + ' %\'',
          'Name LIKE \'% ' + escapedToken + '.\'',
          'Name LIKE \'% ' + escapedToken + '\'',
          'Name LIKE \'' + escapedToken + ' %\''
        }
      );
    }

    return String.join(conditions, ' OR ');
  }

  private static Integer scoreNameAgainstTokens(String name, List<String> tokens) {
    if (String.isBlank(name) || tokens == null || tokens.isEmpty()) {
      return 0;
    }

    String normalizedName = name.trim().toLowerCase();
    List<String> nameWords = normalizedName.split('\\s+');
    Integer score = 0;

    for (String token : tokens) {
      if (String.isBlank(token)) {
        continue;
      }

      score += scoreTokenAgainstName(token.trim().toLowerCase(), normalizedName, nameWords);
    }

    return score;
  }

  private static Integer scoreTokenAgainstName(
    String token,
    String normalizedName,
    List<String> nameWords
  ) {
    String normalizedToken = stripAccents(token).toLowerCase();
    String accentInsensitiveName = stripAccents(normalizedName).toLowerCase();

    for (String word : nameWords) {
      String normalizedWord = stripAccents(word.replace('.', '')).toLowerCase();

      if (normalizedWord == normalizedToken) {
        return 100;
      }
    }

    for (String word : nameWords) {
      String normalizedWord = stripAccents(word.replace('.', '')).toLowerCase();

      if (normalizedWord.startsWith(normalizedToken)) {
        return 80;
      }
    }

    if (
      accentInsensitiveName.contains(' ' + normalizedToken + ' ') ||
      accentInsensitiveName.endsWith(' ' + normalizedToken) ||
      accentInsensitiveName.startsWith(normalizedToken + ' ')
    ) {
      return 70;
    }

    if (accentInsensitiveName.contains(normalizedToken)) {
      return 20;
    }

    return 0;
  }

  private class RankedAccount implements Comparable {
    public Account account;
    public Integer score;

    public RankedAccount(Account account, Integer score) {
      this.account = account;
      this.score = score == null ? 0 : score;
    }

    public Integer compareTo(Object other) {
      RankedAccount otherRankedAccount = (RankedAccount) other;

      if (otherRankedAccount.score != this.score) {
        return otherRankedAccount.score > this.score ? 1 : -1;
      }

      String thisName = this.account?.Name == null ? '' : this.account.Name;
      String otherName = otherRankedAccount.account?.Name == null
        ? ''
        : otherRankedAccount.account.Name;

      return thisName.toLowerCase().compareTo(otherName.toLowerCase());
    }
  }

  private class RankedContact implements Comparable {
    public Contact contact;
    public Integer score;

    public RankedContact(Contact contact, Integer score) {
      this.contact = contact;
      this.score = score == null ? 0 : score;
    }

    public Integer compareTo(Object other) {
      RankedContact otherRankedContact = (RankedContact) other;

      if (otherRankedContact.score != this.score) {
        return otherRankedContact.score > this.score ? 1 : -1;
      }

      String thisName = this.contact?.Name == null ? '' : this.contact.Name;
      String otherName = otherRankedContact.contact?.Name == null
        ? ''
        : otherRankedContact.contact.Name;

      return thisName.toLowerCase().compareTo(otherName.toLowerCase());
    }
  }
}
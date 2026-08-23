/**
 * Author: Hoang Long Vu To
 * Date: 2026-06-15
 *
 * Repository for Contact reads used by contact relationship modals.
 */
public with sharing class FscRelContactRepository {
  public Contact selectById(Id contactId) {
    if (contactId == null) {
      return null;
    }

    List<Contact> contacts = [
      SELECT Id, Name, Email, Phone
      FROM Contact
      WHERE Id = :contactId
      LIMIT 1
    ];

    return contacts.isEmpty() ? null : contacts[0];
  }

  public String selectNameById(Id contactId) {
    Contact contact = selectById(contactId);
    return contact == null ? null : contact.Name;
  }

  public List<Contact> searchContactsByName(String searchTerm, Integer rowLimit) {
    Integer resolvedLimit = rowLimit == null || rowLimit < 1 ? 8 : rowLimit;
    String normalizedTerm = String.isBlank(searchTerm) ? '' : searchTerm.trim();

    if (normalizedTerm.length() < 2) {
      return new List<Contact>();
    }

    List<String> tokens = FscRelNameSearchUtils.tokenizeSearchTerm(normalizedTerm);

    if (tokens.isEmpty()) {
      return new List<Contact>();
    }

    Integer queryLimit = FscRelNameSearchUtils.resolveSearchQueryLimit(
      tokens,
      resolvedLimit
    );
    String nameWhereClause = FscRelNameSearchUtils.buildContactNameTokenWhereClause(
      tokens
    );
    List<Contact> contacts = Database.query(
      'SELECT Id, Name, Email, Phone FROM Contact WHERE (' +
        nameWhereClause +
        ') ORDER BY Name LIMIT ' +
        queryLimit
    );

    if (queryLimit > resolvedLimit) {
      contacts = FscRelNameSearchUtils.rankContactsByNameTokens(
        contacts,
        tokens,
        resolvedLimit
      );
    }

    return contacts;
  }
}
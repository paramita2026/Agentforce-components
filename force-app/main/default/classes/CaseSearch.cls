public with sharing class CaseSearch{
    @AuraEnabled(cacheable=false)
    public static List<Case> searchCase(String caseNumber) {
        try {
            List<Case> cases = new List<Case>();

            if (String.isNotBlank(caseNumber)) {
                String query = 'SELECT Id, CaseNumber, Subject, Status'
                             + ' FROM Case'
                             + ' WHERE CaseNumber LIKE \'' + String.escapeSingleQuotes(caseNumber.trim()) + '%\''
                             + ' ORDER BY CaseNumber ASC'
                             + ' LIMIT 100';

                cases = Database.query(query);
            }

            return cases;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error searching cases: ' + e.getMessage());
        }
    }
}


/**
 * KS_ReferToPartnerController
 *
 * @AuraEnabled controller for the ks_referToPartner LWC.
 * Provides account discovery and referral submission.
 *
 * Account qualification rules are stored in KS_ReferPartnerFlowConfig__mdt:
 *   - CountryCode__c        ISO-2 country code (null = Default fallback record)
 *   - UseCommonFlag__c      if true, also include accounts with KS_CommonForDACH__c = true
 *   - RequiresStateFilter__c  if true, apply in-memory Brazil state filter
 *   - StateFilterFieldApiName__c  field on Account holding applicable state codes
 */
public with sharing class KS_ReferToPartnerController {

    // ─── Wire types ───────────────────────────────────────────────────────────

    public class AccountQueryResult {
        @AuraEnabled public List<AccountWrapper> preferredAccounts;
        @AuraEnabled public List<AccountWrapper> otherAccounts;

        public AccountQueryResult() {
            preferredAccounts = new List<AccountWrapper>();
            otherAccounts     = new List<AccountWrapper>();
        }
    }

    public class AccountWrapper {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String city;
        @AuraEnabled public String country;
        @AuraEnabled public String website;   // resolved: KS_PartnerShopUrl__c ?: Website
        @AuraEnabled public String phone;
        @AuraEnabled public String email;

        public AccountWrapper(Account acc) {
            this.id      = acc.Id;
            this.name    = acc.Name;
            this.city    = acc.BillingCity;
            this.country = acc.BillingCountry;
            this.website = String.isNotBlank(acc.KS_PartnerShopUrl__c) ? acc.KS_PartnerShopUrl__c : acc.Website;
            this.phone   = acc.Phone;
            this.email   = acc.KS_Email__c;
        }
    }

    // ─── @AuraEnabled methods ─────────────────────────────────────────────────

    /**
     * Returns two buckets of qualified accounts for a lead:
     *   preferredAccounts — same country (per FlowConfig) or DACH common flag
     *   otherAccounts     — all other countries (Brazil excluded from otherAccounts)
     */
    @AuraEnabled(cacheable=true)
    public static AccountQueryResult getQualifiedAccounts(Id leadId) {
        Lead lead = queryLead(leadId);

        // Guard: bounced or missing email
        if (String.isBlank(lead.Email)) {
            throw new AuraHandledException('This lead has no email address.');
        }
        if (lead.HasOptedOutOfEmail) {
            throw new AuraHandledException('This lead has opted out of email communications.');
        }

        String leadCountry = lead.Country;
        KS_ReferPartnerFlowConfig__mdt config = loadFlowConfig(leadCountry);

        // Build and execute the primary (preferred) account query
        List<Account> allQualified = executeAccountQuery(config, leadCountry);

        AccountQueryResult result = new AccountQueryResult();

        if (config.RequiresStateFilter__c && String.isNotBlank(config.StateFilterFieldApiName__c)) {
            // Brazil: in-memory state filter
            String leadState = lead.State;
            for (Account acc : allQualified) {
                String applicableStates = (String) acc.get(config.StateFilterFieldApiName__c);
                if (String.isNotBlank(applicableStates) && String.isNotBlank(leadState)
                    && applicableStates.containsIgnoreCase(leadState)) {
                    result.preferredAccounts.add(new AccountWrapper(acc));
                } else {
                    // Brazil accounts that don't match state go to otherAccounts
                    // (Brazil accounts excluded from cross-country other list — handled below)
                }
            }
        } else {
            for (Account acc : allQualified) {
                result.preferredAccounts.add(new AccountWrapper(acc));
            }
        }

        // Other accounts: non-Brazil, non-primary-country accounts
        if (String.isNotBlank(leadCountry) && leadCountry.toUpperCase() != 'BR') {
            List<Account> others = [
                SELECT Id, Name, BillingCity, BillingCountry, KS_Email__c, Phone,
                       Website, KS_PartnerShopUrl__c
                FROM Account
                WHERE KS_ReferToPartner__c = true
                  AND BillingCountry != :leadCountry
                  AND BillingCountry != 'BR'
                  AND BillingCountry != 'Brazil'
                WITH SECURITY_ENFORCED
                ORDER BY Name
                LIMIT 200
            ];
            for (Account acc : others) {
                result.otherAccounts.add(new AccountWrapper(acc));
            }
        }

        return result;
    }

    /**
     * Creates KS_BusinessRelation__c records, updates the Lead, then sends the initial email.
     */
    @AuraEnabled
    public static void submitReferral(Id leadId, List<Id> accountIds, String comments) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new AuraHandledException('At least one account must be selected.');
        }

        Lead lead = queryLead(leadId);

        if (String.isBlank(lead.Email)) {
            throw new AuraHandledException('This lead has no email address.');
        }

        // Create relationship records
        List<KS_BusinessRelation__c> relations = new List<KS_BusinessRelation__c>();
        for (Id accId : accountIds) {
            relations.add(new KS_BusinessRelation__c(
                KS_Lead__c    = leadId,
                KS_Account__c = accId,
                KS_Status__c  = 'Referred'
            ));
        }
        insert relations;

        // Update lead with referred account IDs and date
        String referredIdsCsv = String.join(new List<Id>(accountIds), ',');
        update new Lead(
            Id                         = leadId,
            KS_Referred_Account_Ids__c = referredIdsCsv,
            KS_Referred_Date__c        = Date.today()
        );

        // Send initial email
        new KS_ReferToPartnerEmailService().sendInitialEmail(leadId, accountIds, comments);
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static Lead queryLead(Id leadId) {
        List<Lead> leads = [
            SELECT Id, Email, Country, State, HasOptedOutOfEmail,
                   KS_Referred_Account_Ids__c, KS_Language__c, KS_Client__c
            FROM Lead
            WHERE Id = :leadId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            throw new AuraHandledException('Lead not found: ' + leadId);
        }
        return leads[0];
    }

    private static KS_ReferPartnerFlowConfig__mdt loadFlowConfig(String countryCode) {
        List<KS_ReferPartnerFlowConfig__mdt> configs = [
            SELECT CountryCode__c, UseCommonFlag__c,
                   RequiresStateFilter__c, StateFilterFieldApiName__c
            FROM KS_ReferPartnerFlowConfig__mdt
            WHERE CountryCode__c = :countryCode
               OR CountryCode__c = null
            ORDER BY CountryCode__c NULLS LAST
            LIMIT 2
        ];

        if (configs.isEmpty()) {
            // Return a safe default if no records exist
            return new KS_ReferPartnerFlowConfig__mdt(
                CountryCode__c = null,
                UseCommonFlag__c = false,
                RequiresStateFilter__c = false,
                StateFilterFieldApiName__c = null
            );
        }

        // Prefer exact country match over the null/default record
        for (KS_ReferPartnerFlowConfig__mdt cfg : configs) {
            if (cfg.CountryCode__c == countryCode) {
                return cfg;
            }
        }
        return configs[0]; // Default record (CountryCode__c = null)
    }

    private static List<Account> executeAccountQuery(KS_ReferPartnerFlowConfig__mdt config, String leadCountry) {
        // Base condition: accounts flagged for referral in this country
        String whereClause = 'KS_ReferToPartner__c = true AND BillingCountry = :leadCountry';

        if (config.UseCommonFlag__c) {
            // DACH: include accounts shared across DE/AT/CH
            whereClause = '(KS_ReferToPartner__c = true AND BillingCountry = :leadCountry)'
                        + ' OR KS_CommonForDACH__c = true';
        }

        // If state filter required (Brazil), also retrieve the state field
        String extraFields = '';
        if (config.RequiresStateFilter__c && String.isNotBlank(config.StateFilterFieldApiName__c)) {
            extraFields = ', ' + config.StateFilterFieldApiName__c;
        }

        String soql = 'SELECT Id, Name, BillingCity, BillingCountry, BillingStreet, '
                    + 'BillingPostalCode, KS_Email__c, Phone, Website, KS_PartnerShopUrl__c'
                    + extraFields
                    + ' FROM Account WHERE ' + whereClause
                    + ' ORDER BY Name LIMIT 200';

        return Database.query(soql);
    }
}

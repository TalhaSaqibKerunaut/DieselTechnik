/**
 * KS_ReferToPartnerEmailService
 *
 * Core email service for Refer To Partner V2. Handles both initial referral
 * emails and reminder emails. Fully metadata-driven — no hardcoded strings.
 *
 * Dependencies:
 *   KS_ReferPartnerContent__mdt  — translated email bodies per lang/type
 *   KS_OrgWideEmailMap__mdt      — maps KS_Client__c value to OWA address
 *   KS_ReferToPartnerSettings__c — hierarchy custom setting holding AES-256 key
 *   EmailTemplate (SOQL)         — shell templates DeveloperNames via Custom Labels
 *
 * Token convention in BodyHtml__c:
 *   {Salutation}       Lead.KS_EmailSalutation__c
 *   {LeadName}         Lead.FirstName + ' ' + Lead.LastName
 *   {AccountInfo}      HTML block per account (name, address, URL, phone, email)
 *   {Comment}          User comment (initial only)
 *   {LeadOwnerName}    Lead.Owner.Name
 *   {FeedbackButtons}  3 encrypted feedback links (reminder only)
 *
 * Shell template token:
 *   {EmailContent}     Replaced with the fully assembled BodyHtml__c content
 */
public with sharing class KS_ReferToPartnerEmailService {

    // ─── Public entry points ─────────────────────────────────────────────────

    public void sendInitialEmail(Id leadId, List<Id> accountIds, String comments) {
        Lead lead = queryLead(leadId);
        List<Account> accounts = queryAccounts(accountIds);

        KS_ReferPartnerContent__mdt content = loadContent(lead.KS_Language__c, 'Initial');
        String shellHtml = getShellHtml(System.Label.KS_RTP_InitialShellTemplate);

        String accountInfoHtml = buildAccountInfoHtmlBlock(accounts);
        Map<String, String> tokens = new Map<String, String>{
            '{Salutation}'    => safeStr(lead.KS_EmailSalutation__c),
            '{LeadName}'      => safeStr(lead.FirstName) + ' ' + safeStr(lead.LastName),
            '{AccountInfo}'   => accountInfoHtml,
            '{Comment}'       => String.isNotBlank(comments)
                                    ? '<p>' + escHtml(comments).replace('\n', '<br />') + '</p>'
                                    : '',
            '{LeadOwnerName}' => safeStr(lead.Owner.Name),
            '{FeedbackButtons}' => ''
        };

        String body = assembleEmail(shellHtml, content.BodyHtml__c, tokens);
        String subject = content.Subject__c;

        Id owaId = getOrgWideEmailId(lead.KS_Client__c);
        send(lead.Email, subject, body, owaId);
    }

    public void sendReminderEmail(Id leadId, List<Id> accountIds) {
        Lead lead = queryLead(leadId);
        List<Account> accounts = queryAccounts(accountIds);

        KS_ReferPartnerContent__mdt content = loadContent(lead.KS_Language__c, 'Reminder');
        String shellHtml = getShellHtml(System.Label.KS_RTP_ReminderShellTemplate);

        String accountInfoHtml = buildAccountInfoHtmlBlock(accounts);
        String feedbackHtml = buildFeedbackButtonsHtml(leadId, accountIds, content);

        Map<String, String> tokens = new Map<String, String>{
            '{Salutation}'      => safeStr(lead.KS_EmailSalutation__c),
            '{LeadName}'        => safeStr(lead.FirstName) + ' ' + safeStr(lead.LastName),
            '{AccountInfo}'     => accountInfoHtml,
            '{Comment}'         => '',
            '{LeadOwnerName}'   => safeStr(lead.Owner.Name),
            '{FeedbackButtons}' => feedbackHtml
        };

        String body = assembleEmail(shellHtml, content.BodyHtml__c, tokens);
        String subject = content.Subject__c;

        Id owaId = getOrgWideEmailId(lead.KS_Client__c);
        send(lead.Email, subject, body, owaId);
    }

    // ─── Private: data loading ────────────────────────────────────────────────

    private Lead queryLead(Id leadId) {
        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Email,
                   KS_EmailSalutation__c, KS_Language__c, KS_Client__c,
                   KS_Referred_Account_Ids__c,
                   Owner.Name
            FROM Lead
            WHERE Id = :leadId
            WITH USER_MODE
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            throw new KS_RTPException('Lead not found: ' + leadId);
        }
        return leads[0];
    }

    private List<Account> queryAccounts(List<Id> accountIds) {
        return [
            SELECT Id, Name,
                   BillingStreet, BillingPostalCode, BillingCity, BillingCountry,
                   KS_Email__c, Phone, Website, KS_PartnerShopUrl__c
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ];
    }

    // ─── Private: content resolution ─────────────────────────────────────────

    @TestVisible
    private KS_ReferPartnerContent__mdt loadContent(String langCode, String type) {
        String code = normaliseLanguageCode(langCode);

        // CMT SOQL does not support OR — run two queries: exact match then default fallback
        List<KS_ReferPartnerContent__mdt> exact = [
            SELECT LanguageCode__c, Type__c, Subject__c, BodyHtml__c, IsDefault__c,
                   FeedbackLabelBuyDT__c, FeedbackLabelOtherBrand__c, FeedbackLabelDidNotBuy__c
            FROM KS_ReferPartnerContent__mdt
            WHERE Type__c = :type AND LanguageCode__c = :code
            LIMIT 1
        ];
        if (!exact.isEmpty()) {
            return exact[0];
        }

        List<KS_ReferPartnerContent__mdt> defaultRec = [
            SELECT LanguageCode__c, Type__c, Subject__c, BodyHtml__c, IsDefault__c,
                   FeedbackLabelBuyDT__c, FeedbackLabelOtherBrand__c, FeedbackLabelDidNotBuy__c
            FROM KS_ReferPartnerContent__mdt
            WHERE Type__c = :type AND IsDefault__c = true
            LIMIT 1
        ];
        if (!defaultRec.isEmpty()) {
            return defaultRec[0];
        }

        throw new KS_RTPException('No email content found for type=' + type + ', lang=' + code);
    }

    @TestVisible
    private String getShellHtml(String templateDeveloperName) {
        List<EmailTemplate> templates = [
            SELECT HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :templateDeveloperName
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new KS_RTPException('Shell email template not found: ' + templateDeveloperName);
        }
        return templates[0].HtmlValue;
    }

    // ─── Private: HTML assembly ───────────────────────────────────────────────

    @TestVisible
    private String assembleEmail(String shellHtml, String contentHtml, Map<String, String> tokens) {
        // First inject the content body into the shell
        String assembled = shellHtml.replace('{EmailContent}', contentHtml != null ? contentHtml : '');
        // Then replace all tokens
        for (String token : tokens.keySet()) {
            assembled = assembled.replace(token, tokens.get(token) != null ? tokens.get(token) : '');
        }
        return assembled;
    }

    @TestVisible
    private String buildAccountInfoHtmlBlock(List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return '';
        }
        String block = '';
        for (Account acc : accounts) {
            block += buildSingleAccountHtml(acc);
        }
        return block;
    }

    private String buildSingleAccountHtml(Account acc) {
        // Resolve URL: prefer KS_PartnerShopUrl__c, fall back to Website
        String url = String.isNotBlank(acc.KS_PartnerShopUrl__c) ? acc.KS_PartnerShopUrl__c : acc.Website;

        String addressLine = buildAddressLine(acc);

        String html = '<p><strong>' + escHtml(acc.Name) + '</strong><br />';
        if (String.isNotBlank(addressLine)) {
            html += escHtml(addressLine) + '<br />';
        }
        if (String.isNotBlank(url)) {
            html += '<a href="' + escHtml(url) + '" rel="noopener noreferrer">' + escHtml(url) + '</a><br />';
        }
        if (String.isNotBlank(acc.Phone)) {
            html += escHtml(acc.Phone) + '<br />';
        }
        if (String.isNotBlank(acc.KS_Email__c)) {
            html += '<a href="mailto:' + escHtml(acc.KS_Email__c) + '">' + escHtml(acc.KS_Email__c) + '</a>';
        }
        html += '</p>';
        return html;
    }

    private String buildAddressLine(Account acc) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(acc.BillingStreet))     { parts.add(acc.BillingStreet); }
        if (String.isNotBlank(acc.BillingPostalCode)) { parts.add(acc.BillingPostalCode); }
        if (String.isNotBlank(acc.BillingCity))       { parts.add(acc.BillingCity); }
        if (String.isNotBlank(acc.BillingCountry))    { parts.add(acc.BillingCountry); }
        return String.join(parts, ', ');
    }

    // ─── Private: feedback buttons (reminder only) ────────────────────────────

    @TestVisible
    private String buildFeedbackButtonsHtml(Id leadId, List<Id> accountIds, KS_ReferPartnerContent__mdt content) {
        String pageBaseUrl = URL.getOrgDomainUrl().toExternalForm() + '/apex/KS_ReferToParterHandler';

        String accountIdsCsv = String.join(new List<Id>(accountIds), ',');

        String encLeadId      = encrypt(String.valueOf(leadId));
        String encAccountIds  = encrypt(accountIdsCsv);

        String baseLinkParams = '?leadId=' + EncodingUtil.urlEncode(encLeadId, 'UTF-8')
                              + '&accountIds=' + EncodingUtil.urlEncode(encAccountIds, 'UTF-8');

        String labelBuy   = safeStr(content.FeedbackLabelBuyDT__c);
        String labelOther = safeStr(content.FeedbackLabelOtherBrand__c);
        String labelNot   = safeStr(content.FeedbackLabelDidNotBuy__c);

        String html = '<p>';
        html += buildFeedbackLink(pageBaseUrl + baseLinkParams + '&feedback=1', labelBuy);
        html += '<br />';
        html += buildFeedbackLink(pageBaseUrl + baseLinkParams + '&feedback=2', labelOther);
        html += '<br />';
        html += buildFeedbackLink(pageBaseUrl + baseLinkParams + '&feedback=3', labelNot);
        html += '</p>';
        return html;
    }

    private String buildFeedbackLink(String url, String label) {
        return '<a href="' + url + '" style="display:inline-block;padding:8px 16px;'
             + 'background-color:#003366;color:#ffffff;text-decoration:none;border-radius:4px;">'
             + escHtml(label) + '</a>';
    }

    // ─── Private: encryption ─────────────────────────────────────────────────

    @TestVisible
    private String encrypt(String plaintext) {
        KS_ReferToPartnerSettings__c settings = KS_ReferToPartnerSettings__c.getInstance();
        if (settings == null || String.isBlank(settings.EncryptionKey__c)) {
            throw new KS_RTPException('KS_ReferToPartnerSettings__c.EncryptionKey__c is not configured.');
        }
        Blob key       = Blob.valueOf(settings.EncryptionKey__c);
        Blob plainBlob = Blob.valueOf(plaintext);
        Blob encrypted = Crypto.encryptWithManagedIV('AES256', key, plainBlob);
        return EncodingUtil.base64Encode(encrypted);
    }

    // ─── Private: OWA resolution ─────────────────────────────────────────────

    @TestVisible
    private Id getOrgWideEmailId(String client) {
        // KS_OrgWideEmailMap__mdt stores an email address; look up OWA by that address
        String emailAddress = null;
        if (String.isNotBlank(client)) {
            List<KS_OrgWideEmailMap__mdt> maps = [
                SELECT KS_Email__c
                FROM KS_OrgWideEmailMap__mdt
                WHERE MasterLabel = :client
                LIMIT 1
            ];
            if (!maps.isEmpty() && String.isNotBlank(maps[0].KS_Email__c)) {
                emailAddress = maps[0].KS_Email__c;
            }
        }
        if (emailAddress == null) {
            emailAddress = System.Label.KS_DefaultSenderEmail;
        }
        List<OrgWideEmailAddress> owas = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE Address = :emailAddress
            LIMIT 1
        ];
        return owas.isEmpty() ? null : owas[0].Id;
    }

    // ─── Private: email dispatch ─────────────────────────────────────────────

    private void send(String toAddress, String subject, String htmlBody, Id owaId) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toAddress });
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(true);
        if (owaId != null) {
            mail.setOrgWideEmailAddressId(owaId);
        }
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }

    // ─── Private: utilities ───────────────────────────────────────────────────

    private String safeStr(String value) {
        return value != null ? value : '';
    }

    private String escHtml(String value) {
        if (value == null) { return ''; }
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;');
    }

    @TestVisible
    private String normaliseLanguageCode(String langCode) {
        if (String.isBlank(langCode)) { return 'EN'; }
        // Salesforce locale codes use underscores (e.g. pt_BR); our CMT uses PTBR, RU, AR etc.
        Map<String, String> localeMap = new Map<String, String>{
            'pt_br' => 'PTBR',
            'pt'    => 'PTBR',
            'de'    => 'DE',
            'es'    => 'ES',
            'fr'    => 'FR',
            'it'    => 'IT',
            'ru'    => 'RU',
            'ar'    => 'AR',
            'en'    => 'EN',
            'en_us' => 'EN',
            'en_gb' => 'EN'
        };
        String lower = langCode.toLowerCase();
        return localeMap.containsKey(lower) ? localeMap.get(lower) : 'EN';
    }

    // ─── Inner exception ──────────────────────────────────────────────────────

    public class KS_RTPException extends Exception {}
}

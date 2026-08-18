/**
 * KS_ReferToPartnerReminderV2
 *
 * @InvocableMethod wrapper for the Refer To Partner V2 reminder email.
 * Called by the reminder flow (or a new V2 reminder flow) as a Flow action.
 *
 * All email logic is delegated to KS_ReferToPartnerEmailService.
 * This class contains zero hardcoded strings or template names.
 *
 * Input expects:
 *   leadRecord.Id                    — the Lead whose reminder to send
 *   leadRecord.KS_Referred_Account_Ids__c — comma-separated Account IDs
 */
public class KS_ReferToPartnerReminderV2 {

    public class Input {
        @InvocableVariable(required=true label='Lead Record')
        public Lead leadRecord;
    }

    @InvocableMethod(
        label='RTP V2: Send Reminder Email'
        description='Sends a Refer To Partner reminder email using the V2 metadata-driven service.'
    )
    public static void sendReminderEmail(List<Input> params) {
        KS_ReferToPartnerEmailService service = new KS_ReferToPartnerEmailService();

        for (Input param : params) {
            Lead lead = param.leadRecord;
            if (lead == null || lead.Id == null) {
                continue;
            }

            // Parse account IDs from comma-separated field
            List<Id> accountIds = parseAccountIds(lead.KS_Referred_Account_Ids__c);
            if (accountIds.isEmpty()) {
                continue;
            }

            service.sendReminderEmail(lead.Id, accountIds);
        }
    }

    private static List<Id> parseAccountIds(String csvIds) {
        List<Id> result = new List<Id>();
        if (String.isBlank(csvIds)) {
            return result;
        }
        for (String part : csvIds.split(',')) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                try {
                    result.add((Id) trimmed);
                } catch (Exception e) {
                    // Skip malformed IDs silently; log if monitoring is added
                }
            }
        }
        return result;
    }
}

# Refer To Partner — Implementation Log

**Branch**: `ReferToEmailV2`  
**Ticket**: DT-536  
**Started**: 2026-08-18

---

## Feature Overview

Refer To Partner lets users click a button on a Lead record, select one or more qualified partner accounts, and send a branded email to the lead with the partner's contact details. The lead can then click a feedback link in the email to indicate whether they purchased from that partner. A reminder email is sent automatically if no feedback is received.

**Components involved**: Lead button, screen UI, email to lead, notification to lead owner, feedback VF page, reminder automation.

---

## Old Implementation (Pre-Refactor)

### What Was There

| Component | Type | Notes |
|---|---|---|
| `KS_Refer_To_Partner` | Quick Action (Flow) | Invokes V1 flow |
| `X03_Refer_To_Partner_V1` | Flow (ACTIVE, v100) | Main screen flow |
| `X03_b_Reminder_of_Refer_to_Partner` | Flow (ACTIVE, v2) | Triggers reminder Apex |
| `X03_Refer_to_Partner` | Flow (INACTIVE/DRAFT) | Old draft, never activated |
| `KS_ReferToPartnerReminder` | Apex `@InvocableMethod` | Reminder email sender |
| `KS_ReferToPartnerHandler` | Apex (VF controller) | Feedback page logic |
| `KS_ReferToParterHandler` | VF Page | Feedback confirmation (**typo** in name) |
| 16 Email Templates | EmailTemplate | 8 initial + 8 reminder, one per language |
| `KS_OrgWideEmailMap__mdt` | Custom Metadata | Client → OWA email mapping (populated) |
| `KS_ReferPartnerEmailTemplate__mdt` | Custom Metadata | Schema existed but **zero records** |
| `KS_ReferPartnerFlowConfig__mdt` | Custom Metadata | Schema existed but **zero records** |

### How the Initial Email Worked (V1 Flow)

1. Flow queries accounts filtered by `KS_QualifiedRefertoPartner__c = true` + country logic
2. User selects accounts in data table
3. A `CASE` formula maps `Lead.KS_Language__c` → email template Name (8 languages hardcoded)
4. A long SUBSTITUTE formula builds `#AccountInformation` from account fields including `Website`
5. `emailSimple` action sends the email

### How the Reminder Email Worked

1. `X03_b_Reminder_of_Refer_to_Partner` flow calls `KS_ReferToPartnerReminder` Apex
2. Apex builds HTML in code: hardcoded account fields, hardcoded 24 multilingual strings (8 languages × 3 feedback labels)
3. Hardcoded 8 email template DeveloperNames (including timestamps!) queried via `WHERE DeveloperName IN (...)`
4. Replaces `[Salutation]`, `[LeadName]`, `[LeadOwner]`, `[ReferredPartners]` in template HTML

### Problems Identified

| # | Problem | Impact |
|---|---|---|
| P1 | `KS_PartnerShopUrl__c` not shown in email (immediate requirement) | Missing feature |
| P2 | 24 multilingual strings hardcoded in Apex | Code change needed per language |
| P3 | 8 template DeveloperNames hardcoded in Apex (with timestamps) | Brittle, breaks if template renamed |
| P4 | Language→template CASE formula hardcoded in Flow | Code change to add a language |
| P5 | Email composition split: initial in Flow formula, reminder in Apex | Inconsistent, no shared logic |
| P6 | Reminder email has no Website/URL; initial email has Website but not `KS_PartnerShopUrl__c` | Inconsistency |
| P7 | `KS_ReferPartnerEmailTemplate__mdt` + `KS_ReferPartnerFlowConfig__mdt` exist but empty | Someone started refactoring, never finished |
| P8 | AES-256 encryption key hardcoded as plain string in Apex | Security risk |
| P9 | VF page name typo `KS_ReferToParterHandler` (missing 't') | Technical debt |
| P10 | `X03_Refer_to_Partner` (old draft flow) exists causing confusion | Noise |

### Account Filter Logic (V1 Flow)

Three paths based on Lead country:

- **Default**: `KS_QualifiedRefertoPartner__c = true AND BillingCountryCode = Lead.CountryCode`
- **DACH** (DE/AT/CH): `(BillingCountryCode = Lead.CountryCode) OR (KS_CommonForDACH__c = true)`
- **Brazil**: `BillingCountryCode = BR AND KS_ApplicableStatesBrazil1__c includes Lead.StateCode` (requires StateCode to be filled)

Also shows "Other accounts" section: qualified accounts from countries other than the lead's (excluding Brazil).

OWE is determined by `Lead.KS_Client__c` matched against `KS_OrgWideEmailMap__mdt.MasterLabel`.

---

## New Implementation (Greenfield / V2)

### Strategy

Build a complete parallel implementation. **Old implementation is untouched and stays live** throughout development and testing. Cutover happens only after UAT sign-off by swapping the quick action and updating the reminder flow.

### Architecture

```
Lead Record
    │
    ▼
KS_Refer_To_Partner_V2 (Quick Action, LWC type)
    │
    ▼
ks_referToPartner (LWC — replaces Screen Flow)
    │
    ├── getQualifiedAccounts(leadId)   →  KS_ReferToPartnerController
    └── submitReferral(leadId, ...)    →  KS_ReferToPartnerController
                                               │
                                               ▼
                                    KS_ReferToPartnerEmailService
                                    ├── loadContent(lang, type)     → KS_ReferPartnerContent__mdt
                                    ├── buildAccountInfoHtml(acc)   → KS_PartnerShopUrl__c ?: Website
                                    ├── getShellHtml(type)          → EmailTemplate (shell wrapper)
                                    ├── getOrgWideEmailId(client)   → KS_OrgWideEmailMap__mdt
                                    └── encrypt(input)              → KS_ReferToPartnerSettings__c

Reminder Flow → KS_ReferToPartnerReminderV2 (@InvocableMethod)
             → same KS_ReferToPartnerEmailService
```

### Key Design Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | 2 shell email templates instead of 16 | Single design source; content in metadata |
| D2 | All translated content in `KS_ReferPartnerContent__mdt` | Adding a language = metadata record only, zero code |
| D3 | `KS_ReferPartnerFlowConfig__mdt` drives account query logic | Country-specific rules are data, not code |
| D4 | AES key in `KS_ReferToPartnerSettings__c` Custom Setting | Removes hardcoded secret; initial value = existing key so old VF page still works |
| D5 | Old VF page + `KS_ReferToPartnerHandler` untouched | Works correctly; risk not justified |
| D6 | LWC replaces Screen Flow | Better UX, testable, extensible |
| D7 | Two-section account display (Preferred + Other) | Mirrors existing UX; country-matched partners shown first |
| D8 | OWE resolved by `Lead.KS_Client__c` | Matches existing `KS_OrgWideEmailMap__mdt` structure |
| D9 | Shell templates extracted from "Refer To Partner EN" | Existing design/branding preserved; radical redesign expected later |
| D10 | `KS_ReferPartnerFlowConfig__mdt` populated in Phase 0 | Account query driven by data from day one |

### Email Token Standard (new, unified)

Old implementations used two different conventions (`#Placeholder` in initial, `[Placeholder]` in reminder). New standard uses `{Token}`:

| Token | Replaced with |
|---|---|
| `{Salutation}` | `Lead.KS_EmailSalutation__c` |
| `{LeadName}` | `Lead.FirstName + ' ' + Lead.LastName` |
| `{AccountInfo}` | HTML block: account name, address, URL, phone, email |
| `{Comment}` | User-entered comments from LWC (initial only) |
| `{LeadOwnerName}` | `Lead.Owner.FirstName + ' ' + Lead.Owner.LastName` |
| `{FeedbackButtons}` | 3 encrypted feedback links (reminder only) |
| `{EmailContent}` | Used in shell template; replaced with assembled `BodyHtml__c` |

### `KS_PartnerShopUrl__c` Logic

In `buildAccountInfoHtml()`:
```
URL displayed = KS_PartnerShopUrl__c != null ? KS_PartnerShopUrl__c : Website
```
Applied consistently in both Initial and Reminder emails.

---

## New Components

### Metadata / Config

| File/Record | Purpose |
|---|---|
| `KS_ReferToPartnerSettings__c` | Hierarchy Custom Setting — stores `EncryptionKey__c` |
| `KS_ReferPartnerContent__mdt` | New CMT type — translated email bodies (16 records: 8 lang × 2 types) |
| `KS_ReferPartnerFlowConfig__mdt` records (5) | Account filter rules per country group |
| Custom Labels × 2 | Shell template DeveloperNames — no hardcoding in Apex |

### `KS_ReferPartnerFlowConfig__mdt` Records

| Record | CountryCode | RequiresStateFilter | StateFilterField | UseCommonFlag |
|---|---|---|---|---|
| Brazil | BR | ✓ | `KS_ApplicableStatesBrazil1__c` | ☐ |
| Germany | DE | ☐ | — | ✓ |
| Austria | AT | ☐ | — | ✓ |
| Switzerland | CH | ☐ | — | ✓ |
| Default | — | ☐ | — | ☐ |

`UseCommonFlag__c = true` → adds `OR KS_CommonForDACH__c = true` to account SOQL.

### Apex Classes (new, parallel)

| Class | Type | Purpose |
|---|---|---|
| `KS_ReferToPartnerEmailService` | `with sharing` | Core email assembly + send service |
| `KS_ReferToPartnerController` | `with sharing`, `@AuraEnabled` | LWC backend — account query + referral submission |
| `KS_ReferToPartnerReminderV2` | `@InvocableMethod` | Thin wrapper; delegates to EmailService |
| `KS_ReferToPartnerEmailService_Test` | Test | Service coverage |
| `KS_ReferToPartnerController_Test` | Test | Controller coverage — all account filter paths |

### LWC

| Component | Purpose |
|---|---|
| `ks_referToPartner` | Quick Action modal: two-section datatable + comments + submit |

### Quick Action

| Action | Type | Target |
|---|---|---|
| `Lead.KS_Refer_To_Partner_V2` | LightningWebComponent | `ks_referToPartner` |

---

## Implementation Progress

| Phase | Item | Status |
|---|---|---|
| 0 | `KS_ReferToPartnerSettings__c` Custom Setting | ✅ Done |
| 0 | `KS_ReferPartnerContent__mdt` object + fields | 🔄 In progress |
| 0 | `KS_ReferPartnerFlowConfig__mdt` records (5) | ⬜ Pending |
| 0 | Content records (16) | ⬜ Pending |
| 0 | Custom Labels (2) + shell email templates (2) | ⬜ Pending |
| 1 | `KS_ReferToPartnerEmailService` | ⬜ Pending |
| 1 | `KS_ReferToPartnerController` | ⬜ Pending |
| 1 | `KS_ReferToPartnerReminderV2` | ⬜ Pending |
| 1 | Test classes | ⬜ Pending |
| 2 | `ks_referToPartner` LWC | ⬜ Pending |
| 2 | `Lead.KS_Refer_To_Partner_V2` Quick Action | ⬜ Pending |
| 3 | Cutover (UAT sign-off required) | ⬜ Pending |

---

## Notes & Learnings

- `KS_ReferPartnerEmailTemplate__mdt` and `KS_ReferPartnerFlowConfig__mdt` were already created in the org but had zero records — someone had started this refactoring and stopped. The new implementation completes that intent.
- Old email templates use different placeholder conventions (`#Placeholder` vs `[Placeholder]`). New unified convention is `{Token}`.
- The AES-256 key must remain in sync between the new service (reads from Custom Setting) and the old VF page `KS_ReferToPartnerHandler` (still hardcoded) until that class is migrated. Initial Custom Setting value = `0123456789ABCDEF0123456789ABCDEF`.
- Shell email templates are temporary — a radical redesign of the templates is expected. The metadata-driven content architecture means template redesign requires zero code changes.
- `KS_ReferToParterHandler` VF page has a typo in the name (missing 't'). Not fixing now — out of scope and requires updating button/action references.

---

## Cutover Checklist (Phase 3)

- [ ] All test classes pass ≥90% coverage
- [ ] Jest tests pass (LWC)
- [ ] Manual end-to-end tested in DT_Dev: initial email (all 3 country paths), reminder, feedback link
- [ ] `KS_PartnerShopUrl__c` priority logic verified (with/without field populated)
- [ ] Language fallback to EN verified
- [ ] Feedback links decrypt correctly in VF page
- [ ] Old quick action still works (parallel operation confirmed)
- [ ] UAT sign-off received
- [ ] Swap quick action on Lead Lightning page (App Builder)
- [ ] Update `X03_b_Reminder_of_Refer_to_Partner` to call `KS_ReferToPartnerReminderV2`
- [ ] Monitor logs for 48h after cutover

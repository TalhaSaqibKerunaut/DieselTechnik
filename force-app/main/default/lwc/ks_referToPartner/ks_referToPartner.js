import { LightningElement, api, wire, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQualifiedAccounts from '@salesforce/apex/KS_ReferToPartnerController.getQualifiedAccounts';
import submitReferral from '@salesforce/apex/KS_ReferToPartnerController.submitReferral';

const COLUMNS = [
    { label: 'Name',    fieldName: 'name',    type: 'text',  sortable: true },
    { label: 'City',    fieldName: 'city',    type: 'text',  sortable: true },
    { label: 'Country', fieldName: 'country', type: 'text',  sortable: true },
    {
        label: 'Website', fieldName: 'website', type: 'url',
        typeAttributes: { label: { fieldName: 'website' }, target: '_blank' },
        sortable: false
    },
    { label: 'Phone',   fieldName: 'phone',   type: 'phone', sortable: false },
];

export default class Ks_referToPartner extends LightningElement {
    @api recordId;

    @track preferredAccounts = [];
    @track otherAccounts = [];
    @track selectedIds = [];
    @track comments = '';
    @track showOtherAccounts = false;
    @track isLoading = true;
    @track errorMessage = null;
    @track isSubmitting = false;

    columns = COLUMNS;

    // ─── Wire: load accounts ─────────────────────────────────────────────────

    @wire(getQualifiedAccounts, { leadId: '$recordId' })
    wiredAccounts({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.preferredAccounts = data.preferredAccounts || [];
            this.otherAccounts = data.otherAccounts || [];
            this.errorMessage = null;
        } else if (error) {
            this.errorMessage = this._extractErrorMessage(error);
        }
    }

    // ─── Getters ─────────────────────────────────────────────────────────────

    get hasPreferredAccounts() {
        return this.preferredAccounts && this.preferredAccounts.length > 0;
    }

    get hasOtherAccounts() {
        return this.otherAccounts && this.otherAccounts.length > 0;
    }

    get otherAccountsCount() {
        return this.otherAccounts ? this.otherAccounts.length : 0;
    }

    get otherSectionIcon() {
        return this.showOtherAccounts ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get hasSelections() {
        return this.selectedIds && this.selectedIds.length > 0;
    }

    get selectedCount() {
        return this.selectedIds ? this.selectedIds.length : 0;
    }

    get isSubmitDisabled() {
        return this.isSubmitting || !this.hasSelections;
    }

    // ─── Handlers ────────────────────────────────────────────────────────────

    handleRowSelection(event) {
        // Merge selections from both datatables
        const selectedRows = event.detail.selectedRows;
        const tableData = event.target.data;
        const tableIds = tableData.map(row => row.id);

        // Remove all IDs belonging to this table, then add back the new selection
        const otherTableIds = this.selectedIds.filter(id => !tableIds.includes(id));
        const newSelectedIds = selectedRows.map(row => row.id);
        this.selectedIds = [...otherTableIds, ...newSelectedIds];
    }

    handleCommentChange(event) {
        this.comments = event.detail.value;
    }

    toggleOtherAccounts() {
        this.showOtherAccounts = !this.showOtherAccounts;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSubmit() {
        if (!this.hasSelections) {
            return;
        }
        this.isSubmitting = true;
        try {
            await submitReferral({
                leadId:     this.recordId,
                accountIds: this.selectedIds,
                comments:   this.comments || ''
            });
            this.dispatchEvent(new ShowToastEvent({
                title:   'Referral sent',
                message: `Referral email sent to ${this.selectedCount} partner(s).`,
                variant: 'success'
            }));
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title:   'Error sending referral',
                message: this._extractErrorMessage(error),
                variant: 'error',
                mode:    'sticky'
            }));
        } finally {
            this.isSubmitting = false;
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    _extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unexpected error occurred. Please try again.';
    }
}

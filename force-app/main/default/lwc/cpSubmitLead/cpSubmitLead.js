import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveProjects from '@salesforce/apex/CpSubmitLeadController.getActiveProjects';
import submitLead from '@salesforce/apex/CpSubmitLeadController.submitLead';

const UNIT_OPTIONS = [
    { label: '1 BHK', value: '1BHK' },
    { label: '2 BHK', value: '2BHK' },
    { label: '3 BHK', value: '3BHK' },
    { label: '4 BHK', value: '4BHK' },
    { label: 'Shop', value: 'Shop' },
    { label: 'Office', value: 'Office' }
];

export default class CpSubmitLead extends NavigationMixin(LightningElement) {
    firstName = '';
    lastName = '';
    phone = '';
    email = '';
    projectId = '';
    unitPreferences = [];
    notes = '';
    submitting = false;

    unitOptions = UNIT_OPTIONS;

    @wire(getActiveProjects)
    wiredProjects;

    get projectOptions() {
        return (this.wiredProjects?.data ?? []).map((o) => ({ label: o.label, value: o.value }));
    }

    handleField(event) {
        const name = event.target.dataset.field;
        this[name] = event.target.value;
    }

    handleUnitsChange(event) {
        this.unitPreferences = event.detail.value;
    }

    async handleSubmit() {
        const allValid = [...this.template.querySelectorAll('lightning-input,lightning-combobox,lightning-textarea')]
            .reduce((ok, el) => el.reportValidity() && ok, true);
        if (!allValid) return;

        this.submitting = true;
        try {
            const leadId = await submitLead({
                firstName: this.firstName,
                lastName: this.lastName,
                phone: this.phone,
                email: this.email,
                projectId: this.projectId || null,
                unitPreferences: this.unitPreferences,
                notes: this.notes
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Lead submitted', message: 'Thank you — your lead is in our system.', variant: 'success'
            }));
            this.resetForm();
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: leadId, objectApiName: 'Lead', actionName: 'view' }
            });
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Submission failed',
                message: e?.body?.message || 'Unable to submit the lead. Please try again.',
                variant: 'error'
            }));
        } finally {
            this.submitting = false;
        }
    }

    resetForm() {
        this.firstName = '';
        this.lastName = '';
        this.phone = '';
        this.email = '';
        this.projectId = '';
        this.unitPreferences = [];
        this.notes = '';
    }
}

import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyLeads from '@salesforce/apex/CpLeadListController.getMyLeads';

const COLUMNS = [
    { label: 'Name', fieldName: 'name', type: 'text' },
    { label: 'Phone', fieldName: 'phone', type: 'phone' },
    { label: 'Email', fieldName: 'email', type: 'email' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Project', fieldName: 'projectName', type: 'text' },
    { label: 'Created', fieldName: 'createdDate', type: 'date' }
];

export default class CpLeadList extends NavigationMixin(LightningElement) {
    columns = COLUMNS;

    @wire(getMyLeads)
    wiredData;

    get rows() { return this.wiredData?.data ?? []; }
    get error() { return this.wiredData?.error; }
    get isLoading() { return !this.wiredData?.data && !this.error; }
    get isEmpty() { return this.wiredData?.data && this.wiredData.data.length === 0; }

    handleRowAction(event) {
        const row = event.detail.row;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: row.id, objectApiName: 'Lead', actionName: 'view' }
        });
    }
}

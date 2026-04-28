import { LightningElement, wire } from 'lwc';
import getMySiteVisits from '@salesforce/apex/CpSiteVisitsController.getMySiteVisits';

const COLUMNS = [
    { label: 'Visit', fieldName: 'name', type: 'text' },
    { label: 'Project', fieldName: 'projectName', type: 'text' },
    { label: 'Scheduled', fieldName: 'scheduledDateTime', type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Outcome', fieldName: 'outcome', type: 'text' }
];

export default class CpSiteVisits extends LightningElement {
    columns = COLUMNS;

    @wire(getMySiteVisits)
    wiredData;

    get rows() { return this.wiredData?.data ?? []; }
    get error() { return this.wiredData?.error; }
    get isLoading() { return !this.wiredData?.data && !this.error; }
    get isEmpty() { return this.wiredData?.data && this.wiredData.data.length === 0; }
}

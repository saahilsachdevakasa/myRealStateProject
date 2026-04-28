import { LightningElement, wire } from 'lwc';
import getMyCommissions from '@salesforce/apex/CpCommissionsController.getMyCommissions';

const COLUMNS = [
    { label: 'Ledger #', fieldName: 'name', type: 'text' },
    { label: 'Booking', fieldName: 'bookingName', type: 'text' },
    { label: 'Milestone', fieldName: 'milestone', type: 'text' },
    { label: 'Date', fieldName: 'milestoneDate', type: 'date' },
    { label: 'Basis', fieldName: 'basis', type: 'currency',
      typeAttributes: { currencyCode: 'INR', maximumFractionDigits: 0 } },
    { label: 'Rate %', fieldName: 'ratePct', type: 'percent',
      typeAttributes: { maximumFractionDigits: 2 } },
    { label: 'Gross', fieldName: 'gross', type: 'currency',
      typeAttributes: { currencyCode: 'INR', maximumFractionDigits: 0 } },
    { label: 'Net', fieldName: 'net', type: 'currency',
      typeAttributes: { currencyCode: 'INR', maximumFractionDigits: 0 } },
    { label: 'Status', fieldName: 'status', type: 'text' }
];

export default class CpCommissions extends LightningElement {
    columns = COLUMNS;

    @wire(getMyCommissions)
    wiredData;

    get summary() { return this.wiredData?.data; }
    get error() { return this.wiredData?.error; }
    get isLoading() { return !this.summary && !this.error; }
    get isEmpty() { return this.summary && this.summary.entries.length === 0; }
    get rows() { return this.summary?.entries ?? []; }

    get totalGross() { return this.fmt(this.summary?.totalGross); }
    get totalNet() { return this.fmt(this.summary?.totalNet); }
    get totalAccrued() { return this.fmt(this.summary?.totalAccrued); }
    get totalPaid() { return this.fmt(this.summary?.totalPaid); }

    fmt(value) {
        if (value == null) return '₹0';
        return '₹' + Number(value).toLocaleString('en-IN', { maximumFractionDigits: 0 });
    }
}

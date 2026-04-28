import { LightningElement, wire } from 'lwc';
import getMyPayouts from '@salesforce/apex/CpPayoutsController.getMyPayouts';

const COLUMNS = [
    { label: 'Payout #', fieldName: 'name', type: 'text' },
    { label: 'Month', fieldName: 'payoutMonth', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Gross', fieldName: 'gross', type: 'currency',
      typeAttributes: { currencyCode: 'INR', maximumFractionDigits: 0 } },
    { label: 'GST', fieldName: 'gst', type: 'currency',
      typeAttributes: { currencyCode: 'INR', maximumFractionDigits: 0 } },
    { label: 'TDS', fieldName: 'tds', type: 'currency',
      typeAttributes: { currencyCode: 'INR', maximumFractionDigits: 0 } },
    { label: 'Net', fieldName: 'net', type: 'currency',
      typeAttributes: { currencyCode: 'INR', maximumFractionDigits: 0 } },
    { label: 'UTR', fieldName: 'paymentUTR', type: 'text' }
];

export default class CpPayouts extends LightningElement {
    columns = COLUMNS;

    @wire(getMyPayouts)
    wiredData;

    get rows() { return this.wiredData?.data ?? []; }
    get error() { return this.wiredData?.error; }
    get isLoading() { return !this.wiredData?.data && !this.error; }
    get isEmpty() { return this.wiredData?.data && this.wiredData.data.length === 0; }
}

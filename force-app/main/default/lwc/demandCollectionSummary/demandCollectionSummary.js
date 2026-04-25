import { LightningElement, api, wire } from 'lwc';
import getCollectionData from '@salesforce/apex/DemandCollectionController.getCollectionData';

export default class DemandCollectionSummary extends LightningElement {
    @api recordId;

    @wire(getCollectionData, { bookingId: '$recordId' })
    wiredData;

    get data() { return this.wiredData && this.wiredData.data; }
    get error() { return this.wiredData && this.wiredData.error; }
    get isLoading() { return !this.data && !this.error; }

    get isEmpty() {
        return this.data && this.data.demandCount === 0;
    }

    get totalDemanded() { return this.fmt(this.data && this.data.totalNetPayable); }
    get totalReceived() { return this.fmt(this.data && this.data.totalReceived); }
    get outstanding() { return this.fmt(this.data && this.data.totalOutstanding); }

    get progressPct() {
        const d = this.data;
        if (!d || !d.totalNetPayable || d.totalNetPayable === 0) return 0;
        const pct = (d.totalReceived / d.totalNetPayable) * 100;
        return Math.min(100, Math.round(pct));
    }

    get progressStyle() {
        return 'width: ' + this.progressPct + '%;';
    }

    get progressLabel() {
        return this.progressPct + '% collected';
    }

    get countSummary() {
        if (!this.data) return '';
        return this.data.paidCount + ' of ' + this.data.demandCount + ' demands fully paid';
    }

    fmt(value) {
        if (value == null) return '—';
        return '₹' + Number(value).toLocaleString('en-IN', { maximumFractionDigits: 0 });
    }
}

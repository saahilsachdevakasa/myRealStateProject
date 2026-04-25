import { LightningElement, api, wire } from 'lwc';
import getPaymentTimeline from '@salesforce/apex/PaymentTimelineController.getPaymentTimeline';

const STATUS_VARIANT = {
    'Pending': 'inverse',
    'Demand Raised': 'info',
    'Paid': 'success',
    'Overdue': 'error',
    'Partial': 'warning',
    'Raised': 'info'
};

export default class PaymentTimeline extends LightningElement {
    @api recordId;

    @wire(getPaymentTimeline, { bookingId: '$recordId' })
    wiredData;

    get rows() {
        const data = this.wiredData && this.wiredData.data;
        if (!data) return [];
        return data.map((m) => ({
            ...m,
            statusVariant: STATUS_VARIANT[m.status] || 'inverse',
            demandVariant: STATUS_VARIANT[m.demandStatus] || 'inverse',
            scheduledDisplay: this.fmtCurrency(m.scheduledAmount),
            receivedDisplay: this.fmtCurrency(m.amountReceived),
            netPayableDisplay: this.fmtCurrency(m.netPayable),
            expectedDisplay: this.fmtDate(m.expectedDate),
            hasDemand: !!m.demandId
        }));
    }

    get error() {
        return this.wiredData && this.wiredData.error;
    }

    get isLoading() {
        return !this.wiredData || (!this.wiredData.data && !this.wiredData.error);
    }

    get isEmpty() {
        return this.wiredData && this.wiredData.data && this.wiredData.data.length === 0;
    }

    get totalScheduled() {
        return this.fmtCurrency(this.sum('scheduledAmount'));
    }

    get totalReceived() {
        return this.fmtCurrency(this.sum('amountReceived'));
    }

    get outstanding() {
        const sched = this.sum('scheduledAmount');
        const recv = this.sum('amountReceived');
        return this.fmtCurrency(sched - recv);
    }

    sum(field) {
        const data = this.wiredData && this.wiredData.data;
        if (!data) return 0;
        return data.reduce((acc, m) => acc + (m[field] || 0), 0);
    }

    fmtCurrency(value) {
        if (value == null) return '—';
        return '₹' + Number(value).toLocaleString('en-IN', { maximumFractionDigits: 0 });
    }

    fmtDate(value) {
        if (!value) return '—';
        return new Date(value).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
    }
}

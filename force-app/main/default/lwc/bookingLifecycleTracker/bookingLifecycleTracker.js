import { LightningElement, api, wire } from 'lwc';
import getLifecycleData from '@salesforce/apex/BookingLifecycleController.getLifecycleData';

const PATH_STAGES = [
    'Confirmed',
    'Agreement Pending',
    'Agreement Signed',
    'Registered',
    'Possession Ready',
    'Possessed'
];

export default class BookingLifecycleTracker extends LightningElement {
    @api recordId;

    @wire(getLifecycleData, { bookingId: '$recordId' })
    wiredData;

    get data() {
        return this.wiredData && this.wiredData.data;
    }

    get error() {
        return this.wiredData && this.wiredData.error;
    }

    get isLoading() {
        return !this.data && !this.error;
    }

    get currentStatus() {
        return this.data ? this.data.currentStatus : 'Confirmed';
    }

    get pathSteps() {
        return PATH_STAGES.map((s) => ({ label: s, value: s }));
    }

    get milestoneDates() {
        const d = this.data;
        if (!d) return [];
        return [
            { label: 'Booking Date', dateDisplay: this.formatDate(d.bookingDate) },
            { label: 'Agreement Signed', dateDisplay: this.formatDate(d.agreementSignedDate) },
            { label: 'Registration Date', dateDisplay: this.formatDate(d.registrationDate) },
            { label: 'Possession Offered', dateDisplay: this.formatDate(d.possessionOfferedDate) },
            { label: 'Keys Handed Over', dateDisplay: this.formatDate(d.handedOverDate) }
        ];
    }

    formatDate(value) {
        if (!value) return '—';
        const date = new Date(value);
        return date.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
    }
}

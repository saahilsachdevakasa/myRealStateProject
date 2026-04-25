import { LightningElement, api, wire } from 'lwc';
import getBuyerData from '@salesforce/apex/BuyerProfileController.getBuyerData';

const KYC_VARIANT = {
    'Verified': 'success',
    'Pending': 'warning',
    'Rejected': 'error'
};

export default class BuyerProfileCard extends LightningElement {
    @api recordId;

    @wire(getBuyerData, { accountId: '$recordId' })
    wiredData;

    get data() { return this.wiredData && this.wiredData.data; }
    get error() { return this.wiredData && this.wiredData.error; }
    get isLoading() { return !this.data && !this.error; }

    get maskedPan() {
        const pan = this.data && this.data.pan;
        if (!pan || pan.length < 4) return '—';
        return 'XXXXXX' + pan.slice(-4);
    }

    get kycVariant() {
        const status = this.data && this.data.kycStatus;
        return KYC_VARIANT[status] || 'inverse';
    }

    get kycLabel() {
        return (this.data && this.data.kycStatus) || 'Unknown';
    }

    get isNri() {
        return this.data && this.data.nriStatus;
    }

    get bookingsLine() {
        if (!this.data) return '';
        const count = this.data.bookingCount || 0;
        const investment = this.fmtCurrency(this.data.totalInvestment);
        return count + ' booking' + (count === 1 ? '' : 's') + ' · ' + investment;
    }

    get dobDisplay() {
        if (!this.data || !this.data.dob) return '—';
        return new Date(this.data.dob).toLocaleDateString('en-IN', {
            day: '2-digit', month: 'short', year: 'numeric'
        });
    }

    fmtCurrency(value) {
        if (value == null) return '₹0';
        return '₹' + Number(value).toLocaleString('en-IN', { maximumFractionDigits: 0 });
    }
}

import { LightningElement, wire } from 'lwc';
import getDashboardData from '@salesforce/apex/CpDashboardController.getDashboardData';

export default class CpDashboard extends LightningElement {
    @wire(getDashboardData)
    wiredData;

    get data() { return this.wiredData?.data; }
    get error() { return this.wiredData?.error; }
    get isLoading() { return !this.data && !this.error; }

    get leadCount() { return this.data?.leadCount ?? 0; }
    get activeBookings() { return this.data?.activeBookings ?? 0; }
    get ytdCommission() { return this.fmtCurrency(this.data?.ytdCommission); }
    get pendingPayouts() { return this.fmtCurrency(this.data?.pendingPayouts); }

    fmtCurrency(value) {
        if (value == null) return '₹0';
        return '₹' + Number(value).toLocaleString('en-IN', { maximumFractionDigits: 0 });
    }
}

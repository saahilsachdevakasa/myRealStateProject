import { LightningElement, api, wire } from 'lwc';
import getUnitData from '@salesforce/apex/UnitStatusCardController.getUnitData';

const STATUS_THEME = {
    'Available': { variant: 'success', label: 'Available' },
    'Blocked': { variant: 'warning', label: 'Blocked' },
    'Booked': { variant: 'inverse', label: 'Booked' },
    'Cancelled': { variant: 'error', label: 'Cancelled' }
};

export default class UnitStatusCard extends LightningElement {
    @api recordId;

    countdownText = '';
    intervalId;

    @wire(getUnitData, { unitId: '$recordId' })
    wiredData;

    connectedCallback() {
        this.intervalId = setInterval(() => this.tick(), 30000);
    }

    disconnectedCallback() {
        if (this.intervalId) clearInterval(this.intervalId);
    }

    tick() {
        if (!this.data || !this.data.blockedUntil) return;
        this.countdownText = this.computeCountdown(this.data.blockedUntil);
    }

    get data() {
        return this.wiredData && this.wiredData.data;
    }

    get error() {
        return this.wiredData && this.wiredData.error;
    }

    get isLoading() {
        return !this.data && !this.error;
    }

    get statusVariant() {
        const t = this.data && STATUS_THEME[this.data.status];
        return t ? t.variant : 'inverse';
    }

    get statusLabel() {
        return this.data ? this.data.status : '';
    }

    get countdownDisplay() {
        if (this.countdownText) return this.countdownText;
        if (this.data && this.data.blockedUntil) return this.computeCountdown(this.data.blockedUntil);
        return '';
    }

    get isBlocked() {
        return this.data && this.data.status === 'Blocked';
    }

    get isBooked() {
        return this.data && this.data.status === 'Booked';
    }

    get unitTitle() {
        return this.data ? this.data.unitCode : '';
    }

    get areaCarpet() { return this.fmtNum(this.data && this.data.carpetArea); }
    get areaBuiltUp() { return this.fmtNum(this.data && this.data.builtUpArea); }
    get areaSba() { return this.fmtNum(this.data && this.data.superBuiltUpArea); }
    get bsp() { return this.fmtCurrency(this.data && this.data.bspPerSqft); }
    get basePrice() { return this.fmtCurrency(this.data && this.data.basePrice); }

    get badges() {
        const d = this.data;
        if (!d) return [];
        const b = [];
        if (d.facing) b.push({ key: 'facing', label: d.facing + ' facing' });
        if (d.cornerUnit) b.push({ key: 'corner', label: 'Corner Unit' });
        if (d.parkFacing) b.push({ key: 'park', label: 'Park Facing' });
        return b;
    }

    computeCountdown(target) {
        const now = new Date();
        const end = new Date(target);
        const diffMs = end.getTime() - now.getTime();
        if (diffMs <= 0) return 'Block expired';
        const totalMin = Math.floor(diffMs / 60000);
        const hours = Math.floor(totalMin / 60);
        const minutes = totalMin % 60;
        return hours + 'h ' + minutes + 'm remaining';
    }

    fmtNum(value) {
        if (value == null) return '—';
        return Number(value).toLocaleString('en-IN') + ' sq.ft';
    }

    fmtCurrency(value) {
        if (value == null) return '—';
        return '₹' + Number(value).toLocaleString('en-IN', { maximumFractionDigits: 0 });
    }
}

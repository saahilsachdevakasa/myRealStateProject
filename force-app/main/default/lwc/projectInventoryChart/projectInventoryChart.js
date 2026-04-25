import { LightningElement, api, wire } from 'lwc';
import getInventoryData from '@salesforce/apex/ProjectInventoryController.getInventoryData';

const COLORS = {
    available: '#04844b',
    blocked: '#fe9339',
    booked: '#1589ee',
    cancelled: '#c23934'
};

export default class ProjectInventoryChart extends LightningElement {
    @api recordId;

    @wire(getInventoryData, { projectId: '$recordId' })
    wiredData;

    get data() { return this.wiredData?.data; }
    get error() { return this.wiredData?.error; }
    get isLoading() { return !this.data && !this.error; }

    get isEmpty() {
        return this.data && this.data.totalUnits === 0;
    }

    get sellThroughDisplay() {
        if (!this.data) return '0%';
        return this.data.sellThroughPct + '%';
    }

    get segments() {
        const d = this.data;
        if (!d || d.totalUnits === 0) return [];
        const total = d.totalUnits;
        let cumulative = 0;
        const segs = [];
        const order = [
            { key: 'booked', label: 'Booked', count: d.booked, color: COLORS.booked },
            { key: 'blocked', label: 'Blocked', count: d.blocked, color: COLORS.blocked },
            { key: 'available', label: 'Available', count: d.available, color: COLORS.available },
            { key: 'cancelled', label: 'Cancelled', count: d.cancelled, color: COLORS.cancelled }
        ];
        for (const seg of order) {
            const pct = (seg.count / total) * 100;
            if (pct === 0) continue;
            // r=15.91549430918954 makes circumference exactly 100
            const dash = pct + ' ' + (100 - pct);
            const offset = 25 - cumulative; // offset 25 puts start at 12 o'clock
            cumulative += pct;
            segs.push({
                key: seg.key,
                color: seg.color,
                dasharray: dash,
                offset: offset,
                style: 'stroke: ' + seg.color + '; stroke-dasharray: ' + dash + '; stroke-dashoffset: ' + offset + ';'
            });
        }
        return segs;
    }

    get legend() {
        const d = this.data;
        if (!d) return [];
        return [
            { key: 'booked', label: 'Booked', count: d.booked, color: COLORS.booked, dotStyle: 'background-color:' + COLORS.booked },
            { key: 'blocked', label: 'Blocked', count: d.blocked, color: COLORS.blocked, dotStyle: 'background-color:' + COLORS.blocked },
            { key: 'available', label: 'Available', count: d.available, color: COLORS.available, dotStyle: 'background-color:' + COLORS.available },
            { key: 'cancelled', label: 'Cancelled', count: d.cancelled, color: COLORS.cancelled, dotStyle: 'background-color:' + COLORS.cancelled }
        ].filter((row) => row.count > 0);
    }
}

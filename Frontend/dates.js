'use strict';

// Date-only values never pass through Date.parse or a timezone conversion.
function validISODate(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) return false;
    const [y, m, d] = value.split('-').map(Number);
    const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
    return y >= 1 && m >= 1 && m <= 12 && d >= 1 && d <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
}

function displayDate(value) {
    const iso = String(value || '').slice(0, 10);
    if (!validISODate(iso)) return '';
    const [y, m, d] = iso.split('-');
    return `${d}/${m}/${y}`;
}

function parseDisplayDate(value) {
    const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value || '');
    if (!match) return '';
    const iso = `${match[3]}-${match[2]}-${match[1]}`;
    return validISODate(iso) ? iso : '';
}

function displayDateTime(value) {
    const text = String(value || '');
    return validISODate(text.slice(0, 10)) ? `${displayDate(text)} ${text.slice(11, 16)}` : text;
}

function todayISO() {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function enhanceDateInputs(root = document) {
    root.querySelectorAll('input[type="date"]:not([data-date-picker])').forEach(iso => {
        const wrapper = document.createElement('span');
        wrapper.className = 'date-entry';
        iso.before(wrapper);
        const text = document.createElement('input');
        text.type = 'text';
        text.id = `${iso.id}-display`;
        text.placeholder = 'dd/MM/yyyy';
        text.inputMode = 'numeric';
        text.setAttribute('aria-label', `${iso.closest('.form-group')?.querySelector('label')?.textContent || 'Ngày'} (dd/MM/yyyy)`);
        text.value = displayDate(iso.value);
        const label = document.querySelector(`label[for="${iso.id}"]`);
        if (label) label.htmlFor = text.id;
        const picker = document.createElement('button');
        picker.type = 'button';
        picker.className = 'date-picker-button';
        picker.textContent = '📅';
        picker.setAttribute('aria-label', 'Mở lịch chọn ngày');
        picker.setAttribute('aria-expanded', 'false');
        const calendar = document.createElement('div');
        calendar.className = 'date-calendar';
        calendar.id = `${iso.id}-calendar`;
        calendar.setAttribute('role', 'dialog');
        calendar.setAttribute('aria-label', 'Lịch chọn ngày');
        picker.setAttribute('aria-controls', calendar.id);
        const close = () => {
            calendar.hidden = true;
            calendar.style.display = 'none';
            picker.setAttribute('aria-expanded', 'false');
        };
        close();
        iso.type = 'hidden';
        iso.hidden = true;
        iso.style.display = 'none';
        iso.setAttribute('aria-hidden', 'true');
        wrapper.append(iso, text, picker, calendar);
        const refresh = () => {
            text.required = iso.hasAttribute('required');
            text.value = displayDate(iso.value);
        };
        const validate = () => {
            const value = parseDisplayDate(text.value);
            const bad = text.value && (!value || (iso.min && value < iso.min) || (iso.max && value > iso.max));
            text.setCustomValidity(bad ? 'Nhập ngày hợp lệ theo dd/MM/yyyy trong khoảng cho phép.' : '');
            iso.value = bad ? '' : value;
        };
        text.addEventListener('input', validate);
        // Keep invalid text visible so the user can correct it, rather than clearing it on blur.
        text.addEventListener('change', () => { validate(); if (iso.value) iso.dispatchEvent(new Event('change', { bubbles: true })); });
        let year, month;
        const render = () => {
            const date = new Date(0);
            date.setUTCFullYear(year, month - 1, 1);
            const offset = (date.getUTCDay() + 6) % 7;
            let day = 1;
            const prefix = `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-`;
            const buttons = [];
            while (validISODate(prefix + String(day).padStart(2, '0'))) {
                const value = prefix + String(day).padStart(2, '0');
                const disabled = (iso.min && value < iso.min) || (iso.max && value > iso.max);
                buttons.push(`<button type="button" data-calendar-date="${value}" ${disabled ? 'disabled' : ''} ${iso.value === value ? 'aria-current="date"' : ''}>${day++}</button>`);
            }
            const minYear = Math.max(1, Number(iso.min?.slice(0,4)) || year - 120);
            const maxYear = Math.min(9999, Number(iso.max?.slice(0,4)) || year + 20);
            const years = [];
            for (let y = Math.max(year,maxYear); y >= Math.min(year,minYear); y--) years.push(`<option value="${y}" ${y === year ? 'selected' : ''}>${y}</option>`);
            calendar.innerHTML = `<div class="date-calendar-nav">
                <button type="button" data-calendar-prev aria-label="Tháng trước">‹</button>
                <select data-calendar-month aria-label="Tháng">${Array.from({length:12},(_,i) => `<option value="${i+1}" ${i+1 === month ? 'selected' : ''}>Tháng ${i+1}</option>`).join('')}</select>
                <select data-calendar-year aria-label="Năm">${years.join('')}</select>
                <button type="button" data-calendar-next aria-label="Tháng sau">›</button>
            </div><div class="date-calendar-grid">${['T2','T3','T4','T5','T6','T7','CN'].map(d => `<span>${d}</span>`).join('')}
                ${'<span></span>'.repeat(offset)}${buttons.join('')}</div>`;
            calendar.querySelector('[data-calendar-prev]').onclick = () => { if (--month === 0) {month=12;year--;} render(); };
            calendar.querySelector('[data-calendar-next]').onclick = () => { if (++month === 13) {month=1;year++;} render(); };
            calendar.querySelector('[data-calendar-month]').onchange = e => {month=Number(e.target.value);render();};
            calendar.querySelector('[data-calendar-year]').onchange = e => {year=Number(e.target.value);render();};
            calendar.querySelectorAll('[data-calendar-date]').forEach(button => button.onclick = () => {
                if (button.disabled) return;
                iso.value = button.dataset.calendarDate;
                text.value = displayDate(iso.value);
                validate();
                iso.dispatchEvent(new Event('change', {bubbles:true}));
                close();
                text.focus();
            });
        };
        picker.addEventListener('click', () => {
            if (!calendar.hidden) { close(); return; }
            const initial = validISODate(iso.value) ? iso.value : iso.max || iso.min || todayISO();
            [year,month] = initial.split('-').map(Number);
            render();
            calendar.hidden = false;
            calendar.style.display = 'block';
            picker.setAttribute('aria-expanded', 'true');
        });
        document.addEventListener('pointerdown', e => { if (!wrapper.contains(e.target)) close(); });
        wrapper.addEventListener('keydown', e => { if (e.key === 'Escape') {close();picker.focus();} });
        iso.addEventListener('change', refresh);
        new MutationObserver(refresh).observe(iso, { attributes: true, attributeFilter: ['required', 'min', 'max'] });
        refresh();
    });
}

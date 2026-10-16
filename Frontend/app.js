/**
 * SkyGo Frontend Logic - Role 3: Frontend (Client & Admin)
 * Includes: Auth modals, Booking stepper, Seat map, PNR, Check-in, Admin dashboard
 */

'use strict';

// ============================================================
// CONSTANTS & STATE
// ============================================================

const API_BASE_URL = 'http://localhost:8080/api';
const STORAGE_USER_KEY = 'skygo_currentUser';
const STORAGE_BOOKINGS_KEY = 'skygo_bookings';

const passengerState = { adults: 1, children: 0, infants: 0 };

let currentView = 'client';  // 'client' | 'admin'
let currentUser = null;       // null = guest, object = logged-in user
let bookingState = {};         // active booking context
let adminFlights = [];         // admin table data
let appliedVoucher = null;     // active discount voucher
let activeCheckinRecord = null;// checkin passenger record
let activeCheckinSeat = null;  // checkin selected seat

const MOCK_PNR_DB = {};

// ============================================================
// INIT
// ============================================================

document.addEventListener('DOMContentLoaded', () => {
    initPassengerSelector();
    initTripTypeToggle();
    initSearchForm();
    initPNRForm();
    initCheckinForm();
    initModals();
    initViewSwitcher();
    initAdminDashboard();
    initHamburger();
    initPasswordToggles();
    initUserMenu();
    initVoucher();
    initProfileModal();
    initCheckinSeatmapModal();
    setMinDepartDate();
    restoreUserSession();
});

// ============================================================
// 1. PASSENGER SELECTOR
// ============================================================

function initPassengerSelector() {
    const selector = document.getElementById('passenger-selector');
    const popover = document.getElementById('passenger-popover');
    const closeBtn = document.getElementById('btn-close-passengers');

    selector.addEventListener('click', (e) => {
        e.stopPropagation();
        popover.classList.toggle('show');
    });

    closeBtn.addEventListener('click', () => popover.classList.remove('show'));

    document.addEventListener('click', (e) => {
        if (!popover.contains(e.target) && !selector.contains(e.target)) {
            popover.classList.remove('show');
        }
    });

    document.querySelectorAll('.btn-counter').forEach(btn => {
        btn.addEventListener('click', (e) => {
            updatePassengerCount(e.currentTarget.dataset.type, e.currentTarget.dataset.action);
        });
    });
}

function updatePassengerCount(type, action) {
    const total = passengerState.adults + passengerState.children + passengerState.infants;

    if (action === 'increase') {
        if (total < 9) passengerState[type]++;
    } else if (action === 'decrease') {
        if (type === 'adults' && passengerState.adults > 1) passengerState.adults--;
        else if (type !== 'adults' && passengerState[type] > 0) passengerState[type]--;
    }

    if (passengerState.infants > passengerState.adults) {
        passengerState.infants = passengerState.adults;
    }

    const countEl = document.getElementById(`count-${type}`);
    if (countEl) countEl.textContent = passengerState[type];
    updatePassengerSummary();
}

function updatePassengerSummary() {
    let s = `${passengerState.adults} Người lớn`;
    if (passengerState.children > 0) s += `, ${passengerState.children} Trẻ em`;
    if (passengerState.infants > 0) s += `, ${passengerState.infants} Em bé`;
    const el = document.getElementById('passenger-summary');
    if (el) el.textContent = s;
}

// ============================================================
// 2. TRIP TYPE TOGGLE
// ============================================================

function initTripTypeToggle() {
    const radios = document.querySelectorAll('input[name="trip"]');
    const returnGroup = document.getElementById('return-date-group');
    const returnInput = document.getElementById('return-date');

    radios.forEach(radio => {
        radio.addEventListener('change', (e) => {
            const isOneWay = e.target.value === 'oneway';
            returnGroup.style.display = isOneWay ? 'none' : 'flex';
            if (isOneWay) {
                returnInput.removeAttribute('required');
                returnInput.value = '';
            } else {
                returnInput.setAttribute('required', 'true');
            }
        });
    });
}

// ============================================================
// ============================================================
// 3. FLIGHT SEARCH & ROUNDTRIP
// ============================================================

let currentSearch = {
    isRoundtrip: false,
    origin: '',
    destination: '',
    departDate: '',
    returnDate: '',
    selectedOutbound: null,
};

function initSearchForm() {
    const form = document.getElementById('flight-search-form');
    form.addEventListener('submit', async (e) => {
        e.preventDefault();

        const tripRadio = document.querySelector('input[name="trip"]:checked');
        const isRoundtrip = tripRadio?.value === 'roundtrip';
        const origin = document.getElementById('origin').value;
        const destination = document.getElementById('destination').value;
        const departDate = document.getElementById('depart-date').value;
        const returnDate = document.getElementById('return-date').value;

        if (origin === destination) {
            showToast('error', 'Lỗi Tìm Kiếm', 'Điểm đi và điểm đến không được trùng nhau.');
            return;
        }

        if (isRoundtrip && !returnDate) {
            showToast('warning', 'Thiếu ngày về', 'Vui lòng chọn ngày về cho chuyến bay khứ hồi.');
            return;
        }

        if (isRoundtrip && returnDate < departDate) {
            showToast('error', 'Ngày về không hợp lệ', 'Ngày về không thể trước ngày đi.');
            return;
        }

        currentSearch = {
            isRoundtrip,
            origin,
            destination,
            departDate,
            returnDate,
            selectedOutbound: null,
        };

        const btn = document.getElementById('btn-search-flights');
        btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Đang tìm...';
        btn.disabled = true;

        const queryParams = new URLSearchParams({
            origin, destination, departDate,
            adults: passengerState.adults,
            children: passengerState.children,
            infants: passengerState.infants
        });

        try {
            const res = await fetch(`${API_BASE_URL}/flights/search?${queryParams}`);
            if (!res.ok) {
                const errData = await res.json().catch(() => ({}));
                throw new Error(errData.message || 'Lỗi server');
            }
            const data = await res.json();
            if (data && data.length > 0) {
                renderOutboundFlightResults(data);
            } else {
                renderNoFlightsFound();
            }
        } catch (err) {
            console.error('Lỗi tìm chuyến bay:', err);
            showToast('error', 'Lỗi tìm chuyến bay', err.message || 'Không thể kết nối đến máy chủ Backend.');
            renderNoFlightsFound();
        } finally {
            btn.innerHTML = '<i class="fa-solid fa-magnifying-glass"></i> Tìm chuyến bay';
            btn.disabled = false;
        }
    });
}

function renderFlightResults(flights) {
    renderOutboundFlightResults(flights);
}

function renderOutboundFlightResults(flights) {
    const section = document.getElementById('results-section');
    const list = document.getElementById('flight-results-list');
    const count = document.getElementById('results-count');

    const titlePrefix = currentSearch.isRoundtrip ? 'Bước 1: Chọn Chuyến Đi' : 'Danh Sách Chuyến Bay';
    count.innerHTML = `<strong>${titlePrefix}</strong> &bull; ${flights.length} chuyến phù hợp`;

    list.innerHTML = flights.map(f => `
        <div class="flight-card">
            <div class="flight-info">
                <div class="flight-airline">
                    <strong>${f.airline || 'SkyGo Airways'}</strong>
                    <div>${f.flightNumber}</div>
                    <span class="badge badge-selling" style="font-size:11px;margin-top:4px;">Chiều đi</span>
                </div>
                <div class="flight-time">
                    <div class="time">${f.departureTime}</div>
                    <div class="airport">${f.origin}</div>
                </div>
                <div class="flight-arrow">
                    <hr style="flex:1;border:none;border-top:1.5px dashed #cbd5e1">
                    <i class="fa-solid fa-plane"></i>
                    <hr style="flex:1;border:none;border-top:1.5px dashed #cbd5e1">
                </div>
                <div class="flight-time">
                    <div class="time">${f.arrivalTime}</div>
                    <div class="airport">${f.destination}</div>
                </div>
                <div class="flight-duration">
                    <i class="fa-regular fa-clock"></i> ${f.duration || '2h 00m'}
                </div>
            </div>
            <div class="flight-price-col">
                <div class="flight-price">${Number(f.price).toLocaleString('vi-VN')} VND</div>
                <div class="flight-price-label">/ người lớn</div>
                <button class="btn btn-primary btn-sm" style="margin-top:10px;"
                    onclick="handleSelectOutboundFlight(${JSON.stringify(f).replace(/"/g, '&quot;')})">
                    ${currentSearch.isRoundtrip ? 'Chọn chiều đi <i class="fa-solid fa-arrow-right"></i>' : 'Chọn chuyến bay <i class="fa-solid fa-arrow-right"></i>'}
                </button>
            </div>
        </div>
    `).join('');

    section.classList.remove('hidden');
    section.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function handleSelectOutboundFlight(flight) {
    if (!currentSearch.isRoundtrip) {
        openBookingModal(flight, null);
        return;
    }

    currentSearch.selectedOutbound = flight;
    showToast('info', 'Đã chọn chiều đi', `Chuyến ${flight.flightNumber}. Hãy chọn tiếp chuyến về.`);

    // Render return flight options
    renderReturnFlightResults();
}

async function renderReturnFlightResults() {
    const list = document.getElementById('flight-results-list');
    const count = document.getElementById('results-count');
    const out = currentSearch.selectedOutbound;

    count.innerHTML = `<strong>Bước 2: Chọn Chuyến Bay Chiều Về</strong> &bull; Đang tìm...`;
    list.innerHTML = `<div style="text-align:center;padding:48px 0;"><i class="fa-solid fa-spinner fa-spin" style="font-size:32px;color:var(--primary);"></i><p style="margin-top:12px;color:var(--text-muted);">Đang tải danh sách chuyến bay chiều về...</p></div>`;

    const returnParams = new URLSearchParams({
        origin: currentSearch.destination,
        destination: currentSearch.origin,
        departDate: currentSearch.returnDate,
        adults: passengerState.adults,
        children: passengerState.children,
        infants: passengerState.infants
    });

    let returnOptions = [];
    try {
        const res = await fetch(`${API_BASE_URL}/flights/search?${returnParams}`);
        if (res.ok) {
            const data = await res.json();
            if (Array.isArray(data)) returnOptions = data;
        }
    } catch (err) {
        console.error('Error fetching return flights:', err);
    }

    count.innerHTML = `<strong>Bước 2: Chọn Chuyến Bay Chiều Về</strong> &bull; ${returnOptions.length} chuyến bay`;

    let html = `
        <div style="background:#f1f5f9;padding:12px 18px;border-radius:10px;margin-bottom:16px;display:flex;justify-content:space-between;align-items:center;">
            <div>
                <i class="fa-solid fa-circle-check" style="color:var(--success);margin-right:6px;"></i>
                <strong>Đã chọn chiều đi:</strong> ${out.flightNumber} (${out.origin} → ${out.destination}) lúc ${out.departureTime || out.departTime}
            </div>
            <button class="btn btn-outline btn-sm" onclick="document.getElementById('flight-search-form').dispatchEvent(new Event('submit'))">
                <i class="fa-solid fa-rotate-left"></i> Đổi chiều đi
            </button>
        </div>
    `;

    if (returnOptions.length === 0) {
        html += `
            <div style="text-align:center;padding:32px;background:#fff;border-radius:12px;border:1px dashed #cbd5e1;">
                <i class="fa-solid fa-plane-slash" style="font-size:36px;color:var(--text-light);margin-bottom:8px;display:block;"></i>
                <p style="font-weight:600;color:var(--text-muted);">Không tìm thấy chuyến bay chiều về cho ngày này.</p>
            </div>
        `;
    } else {
        html += returnOptions.map(f => `
            <div class="flight-card" style="border-left: 4px solid var(--accent);">
                <div class="flight-info">
                    <div class="flight-airline">
                        <strong>${f.airline || 'SkyGo Airways'}</strong>
                        <div>${f.flightNumber}</div>
                        <span class="badge badge-checkin" style="font-size:11px;margin-top:4px;">Chiều về</span>
                    </div>
                    <div class="flight-time">
                        <div class="time">${f.departureTime || f.departTime}</div>
                        <div class="airport">${f.origin}</div>
                    </div>
                    <div class="flight-arrow">
                        <hr style="flex:1;border:none;border-top:1.5px dashed #cbd5e1">
                        <i class="fa-solid fa-plane" style="transform:rotate(180deg);"></i>
                        <hr style="flex:1;border:none;border-top:1.5px dashed #cbd5e1">
                    </div>
                    <div class="flight-time">
                        <div class="time">${f.arrivalTime || f.arriveTime}</div>
                        <div class="airport">${f.destination}</div>
                    </div>
                    <div class="flight-duration">
                        <i class="fa-regular fa-clock"></i> ${f.duration || '2h 00m'}
                    </div>
                </div>
                <div class="flight-price-col">
                    <div class="flight-price">${Number(f.price).toLocaleString('vi-VN')} VND</div>
                    <div class="flight-price-label">/ người lớn</div>
                    <button class="btn btn-accent btn-sm" style="margin-top:10px;"
                        onclick="handleSelectReturnFlight(${JSON.stringify(f).replace(/"/g, '&quot;')})">
                        Chọn chiều về &amp; Đặt vé <i class="fa-solid fa-arrow-right"></i>
                    </button>
                </div>
            </div>
        `).join('');
    }

    list.innerHTML = html;
    document.getElementById('results-section').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function handleSelectReturnFlight(returnFlight) {
    openBookingModal(currentSearch.selectedOutbound, returnFlight);
}

function renderNoFlightsFound() {
    const section = document.getElementById('results-section');
    const list = document.getElementById('flight-results-list');
    const count = document.getElementById('results-count');
    count.textContent = '0 chuyến bay';
    list.innerHTML = `
        <div style="text-align:center;padding:48px 0;">
            <i class="fa-solid fa-plane-slash" style="font-size:56px;color:var(--text-light);margin-bottom:16px;display:block;"></i>
            <p style="font-size:17px;color:var(--text-muted);font-weight:600;">Không tìm thấy chuyến bay phù hợp</p>
            <p style="font-size:13px;color:var(--text-light);margin-top:6px;">Vui lòng thử lại ngày khác hoặc đổi lộ trình.</p>
        </div>
    `;
    section.classList.remove('hidden');
}

function setMinDepartDate() {
    const today = new Date().toISOString().split('T')[0];
    const d = document.getElementById('depart-date');
    const r = document.getElementById('return-date');
    if (d) d.min = today;
    if (r) r.min = today;
}

// ============================================================
// 4. BOOKING STEPPER MODAL
// ============================================================

function openBookingModal(flight, returnFlight = null) {
    appliedVoucher = null;
    const vMsg = document.getElementById('voucher-message');
    if (vMsg) vMsg.innerHTML = '';
    const vInput = document.getElementById('voucher-input');
    if (vInput) vInput.value = '';

    bookingState = {
        flight,
        returnFlight,
        isRoundtrip: !!returnFlight,
        passengers: {
            adults: passengerState.adults,
            children: passengerState.children,
            infants: passengerState.infants,
        },
        selectedSeats: [],
        extras: { baggage: false, meal: false, priority: false },
        totalPassengers: passengerState.adults + passengerState.children,
    };

    // Set summary text in header
    const summary = document.getElementById('booking-flight-summary');
    if (returnFlight) {
        summary.innerHTML = `
            <div><i class="fa-solid fa-plane"></i> Đi: ${flight.origin} &rarr; ${flight.destination} (${flight.flightNumber})</div>
            <div><i class="fa-solid fa-plane-arrival"></i> Về: ${returnFlight.origin} &rarr; ${returnFlight.destination} (${returnFlight.flightNumber})</div>
        `;
    } else {
        summary.innerHTML = `
            <i class="fa-solid fa-plane"></i>
            ${flight.origin} &rarr; ${flight.destination} &bull;
            ${flight.flightNumber} &bull;
            ${Number(flight.price).toLocaleString('vi-VN')} VND
        `;
    }

    // Build Step 1 passenger forms
    buildPassengerForms();

    // Reset to step 1
    goToStep(1);

    document.getElementById('bookingModal').classList.add('show');
    document.body.style.overflow = 'hidden';
}

function closeBookingModal() {
    document.getElementById('bookingModal').classList.remove('show');
    document.body.style.overflow = '';
}

function buildPassengerForms() {
    const container = document.getElementById('passenger-forms-container');
    const forms = [];
    const { adults, children, infants } = bookingState.passengers;

    for (let i = 0; i < adults; i++) {
        forms.push(buildOnePassengerForm(i + 1, 'Người lớn', 'adult', i));
    }
    for (let i = 0; i < children; i++) {
        forms.push(buildOnePassengerForm(adults + i + 1, 'Trẻ em', 'child', adults + i));
    }
    for (let i = 0; i < infants; i++) {
        forms.push(buildOnePassengerForm(adults + children + i + 1, 'Em bé', 'infant', adults + children + i));
    }

    container.innerHTML = forms.join('');
}

function buildOnePassengerForm(num, typeLabel, type, idx) {
    return `
        <div class="passenger-form-block">
            <h5>
                <i class="fa-solid fa-user"></i>
                Hành khách ${num}
                <span class="pax-badge">${typeLabel}</span>
            </h5>
            <div class="pax-form-grid">
                <div class="form-group">
                    <label>Họ</label>
                    <input type="text" id="pax-${idx}-lastname" placeholder="VD: NGUYEN" style="text-transform:uppercase;" required>
                </div>
                <div class="form-group">
                    <label>Tên đệm và tên</label>
                    <input type="text" id="pax-${idx}-firstname" placeholder="VD: VAN A" style="text-transform:uppercase;" required>
                </div>
                ${type !== 'infant' ? `
                <div class="form-group">
                    <label>Ngày sinh</label>
                    <input type="date" id="pax-${idx}-dob">
                </div>
                <div class="form-group">
                    <label>CCCD / Hộ chiếu</label>
                    <input type="text" id="pax-${idx}-id" placeholder="Số CCCD hoặc hộ chiếu">
                </div>
                ` : `
                <div class="form-group">
                    <label>Ngày sinh</label>
                    <input type="date" id="pax-${idx}-dob">
                </div>
                <div class="form-group">
                    <label>Giới tính</label>
                    <select id="pax-${idx}-gender">
                        <option value="M">Nam</option>
                        <option value="F">Nữ</option>
                    </select>
                </div>
                `}
            </div>
        </div>
    `;
}

function validatePassengerForms() {
    const total = bookingState.passengers.adults + bookingState.passengers.children + bookingState.passengers.infants;
    for (let i = 0; i < total; i++) {
        const last = document.getElementById(`pax-${i}-lastname`);
        const first = document.getElementById(`pax-${i}-firstname`);
        if (!last || !first || !last.value.trim() || !first.value.trim()) {
            showToast('error', 'Thiếu thông tin', `Vui lòng điền họ tên đầy đủ cho hành khách ${i + 1}.`);
            return false;
        }
    }
    return true;
}

function collectPassengerData() {
    const passengers = [];
    const total = bookingState.passengers.adults + bookingState.passengers.children + bookingState.passengers.infants;
    for (let i = 0; i < total; i++) {
        passengers.push({
            lastName: (document.getElementById(`pax-${i}-lastname`)?.value || '').toUpperCase().trim(),
            firstName: (document.getElementById(`pax-${i}-firstname`)?.value || '').toUpperCase().trim(),
        });
    }
    bookingState.passengerData = passengers;
    return passengers;
}

// -------- Stepper Navigation --------

function goToStep(stepNum) {
    // Update step circles
    document.querySelectorAll('.step').forEach(s => {
        const n = parseInt(s.dataset.step);
        s.classList.remove('active', 'completed');
        if (n === stepNum) s.classList.add('active');
        else if (n < stepNum) s.classList.add('completed');
    });

    // Update step lines
    document.querySelectorAll('.step-line').forEach((line, idx) => {
        line.classList.toggle('completed', idx + 1 < stepNum);
    });

    // Show correct panel
    document.querySelectorAll('.step-panel').forEach((panel, idx) => {
        panel.classList.toggle('active', idx + 1 === stepNum);
    });

    bookingState.currentStep = stepNum;

    // Step-specific setup
    if (stepNum === 2) buildSeatMap();
    if (stepNum === 3) buildFareSummary();
    if (stepNum === 4) buildBoardingPass();
}

// Step 1 → 2
document.addEventListener('click', (e) => {
    if (e.target.id === 'step1-next' || e.target.closest('#step1-next')) {
        if (validatePassengerForms()) {
            collectPassengerData();
            goToStep(2);
        }
    }
    if (e.target.id === 'step2-back' || e.target.closest('#step2-back')) goToStep(1);
    if (e.target.id === 'step2-next' || e.target.closest('#step2-next')) {
        if (bookingState.selectedSeats.length < bookingState.totalPassengers) {
            showToast('warning', 'Chưa chọn ghế', `Vui lòng chọn ${bookingState.totalPassengers} ghế trước khi tiếp tục.`);
            return;
        }
        goToStep(3);
    }
    if (e.target.id === 'step3-back' || e.target.closest('#step3-back')) goToStep(2);
    if (e.target.id === 'step3-pay' || e.target.closest('#step3-pay')) processPayment();
    if (e.target.id === 'close-booking' || e.target.closest('#close-booking')) closeBookingModal();
    if (e.target.id === 'btn-close-booking-done' || e.target.closest('#btn-close-booking-done')) closeBookingModal();
    if (e.target.id === 'btn-print-boarding' || e.target.closest('#btn-print-boarding')) window.print();
});

// -------- Seat Map --------

const TAKEN_SEATS = ['1A', '1B', '2C', '3D', '4A', '4F', '5B', '5C', '6E', '7A', '8D', '9B', '10F', '11C', '12B', '13A', '15D', '16E'];

function buildSeatMap() {
    const map = document.getElementById('seat-map');
    if (!map) return;

    const rows = 18;
    const cols = ['A', 'B', 'C', 'D', 'E', 'F'];
    let html = '';

    // Column header
    html += `<div class="seat-row">
        <div class="row-number"></div>
        ${cols.slice(0, 3).map(c => `<div style="width:34px;text-align:center;font-size:10px;font-weight:600;color:var(--text-muted);">${c}</div>`).join('')}
        <div class="aisle"></div>
        ${cols.slice(3).map(c => `<div style="width:34px;text-align:center;font-size:10px;font-weight:600;color:var(--text-muted);">${c}</div>`).join('')}
    </div>`;

    for (let r = 1; r <= rows; r++) {
        html += `<div class="seat-row"><div class="row-number">${r}</div>`;
        cols.forEach((col, ci) => {
            const seatId = `${r}${col}`;
            const isTaken = TAKEN_SEATS.includes(seatId);
            const isSelected = bookingState.selectedSeats.includes(seatId);

            let cls = 'seat';
            if (isTaken) cls += ' taken';
            if (isSelected) cls += ' selected';

            html += `<div class="${cls}" data-seat="${seatId}">${seatId}</div>`;

            if (ci === 2) html += `<div class="aisle"></div>`;
        });
        html += `</div>`;
    }

    map.innerHTML = html;

    // Seat click events
    map.querySelectorAll('.seat:not(.taken)').forEach(seat => {
        seat.addEventListener('click', () => toggleSeat(seat));
    });
}

function toggleSeat(el) {
    const seatId = el.dataset.seat;
    const idx = bookingState.selectedSeats.indexOf(seatId);
    const maxSeats = bookingState.totalPassengers;

    if (idx >= 0) {
        bookingState.selectedSeats.splice(idx, 1);
        el.classList.remove('selected');
    } else {
        if (bookingState.selectedSeats.length >= maxSeats) {
            showToast('info', 'Giới hạn ghế', `Bạn chỉ có thể chọn tối đa ${maxSeats} ghế.`);
            return;
        }
        bookingState.selectedSeats.push(seatId);
        el.classList.add('selected');
    }
}

// -------- Extras --------

document.addEventListener('change', (e) => {
    if (e.target.id === 'extra-baggage') bookingState.extras.baggage = e.target.checked;
    if (e.target.id === 'extra-meal') bookingState.extras.meal = e.target.checked;
    if (e.target.id === 'extra-priority') bookingState.extras.priority = e.target.checked;

    // Highlight selected extras
    ['baggage', 'meal', 'priority'].forEach(key => {
        const label = document.getElementById(`extra-${key}-label`);
        if (label) label.style.borderColor = bookingState.extras[key] ? 'var(--accent)' : '';
    });
});

// -------- Payment Method Switch --------

document.addEventListener('change', (e) => {
    if (e.target.name === 'payment') {
        ['vietqr', 'domestic', 'visa'].forEach(m => {
            const el = document.getElementById(`payment-${m}`);
            if (el) el.classList.toggle('hidden', m !== e.target.value);
        });
    }
});

// -------- Fare Summary --------

function buildFareSummary() {
    const { flight, returnFlight, passengers, extras, totalPassengers } = bookingState;
    const outboundBasePrice = flight.price || 0;
    const returnBasePrice = returnFlight ? (returnFlight.price || 0) : 0;
    const legPrice = outboundBasePrice + returnBasePrice;

    // Adult 100%, Child 75%, Infant 10%
    const adultFare = passengers.adults * legPrice;
    const childFare = passengers.children * Math.round(legPrice * 0.75);
    const infantFare = passengers.infants * Math.round(legPrice * 0.10);

    const subtotal = adultFare + childFare + infantFare;

    const extraCost = (extras.baggage ? 250000 : 0)
        + (extras.meal ? 150000 : 0)
        + (extras.priority ? 100000 : 0);

    const extras_total = extraCost * totalPassengers;
    const tax = Math.round((subtotal + extras_total) * 0.1);

    let discount = 0;
    if (appliedVoucher) {
        if (appliedVoucher.type === 'percent') {
            discount = Math.round(subtotal * (appliedVoucher.value / 100));
        } else if (appliedVoucher.type === 'fixed') {
            discount = appliedVoucher.value;
        }
    }

    const total = Math.max(0, subtotal + tax + extras_total - discount);
    bookingState.totalAmount = total;
    bookingState.subtotal = subtotal;
    bookingState.tax = tax;
    bookingState.discount = discount;

    const fareEl = document.getElementById('fare-summary');
    fareEl.innerHTML = `
        <h5>Tóm Tắt Chi Phí</h5>
        <div class="fare-row">
            <span>Người lớn (${passengers.adults}x)</span>
            <span>${adultFare.toLocaleString('vi-VN')} VND</span>
        </div>
        ${passengers.children > 0 ? `
        <div class="fare-row">
            <span>Trẻ em 75% (${passengers.children}x)</span>
            <span>${childFare.toLocaleString('vi-VN')} VND</span>
        </div>` : ''}
        ${passengers.infants > 0 ? `
        <div class="fare-row">
            <span>Em bé 10% (${passengers.infants}x)</span>
            <span>${infantFare.toLocaleString('vi-VN')} VND</span>
        </div>` : ''}
        ${returnFlight ? `<div class="fare-row" style="font-size:12px;color:var(--primary);font-weight:600;"><span>Đã gồm vé chiều về (${returnFlight.flightNumber})</span><span>✓</span></div>` : ''}
        ${extras.baggage ? `<div class="fare-row"><span>Hành lý 20kg x${totalPassengers}</span><span>${(250000 * totalPassengers).toLocaleString('vi-VN')} VND</span></div>` : ''}
        ${extras.meal ? `<div class="fare-row"><span>Bữa ăn x${totalPassengers}</span><span>${(150000 * totalPassengers).toLocaleString('vi-VN')} VND</span></div>` : ''}
        ${extras.priority ? `<div class="fare-row"><span>Ưu tiên thủ tục x${totalPassengers}</span><span>${(100000 * totalPassengers).toLocaleString('vi-VN')} VND</span></div>` : ''}
        <div class="fare-row"><span>Thuế &amp; phí (10%)</span><span>${tax.toLocaleString('vi-VN')} VND</span></div>
        ${discount > 0 ? `
        <div class="fare-row" style="color:var(--success);font-weight:700;">
            <span><i class="fa-solid fa-tag"></i> Giảm giá (${appliedVoucher.code})</span>
            <span>-${discount.toLocaleString('vi-VN')} VND</span>
        </div>` : ''}
        <div class="fare-row total">
            <span>Tổng cộng</span>
            <span>${total.toLocaleString('vi-VN')} VND</span>
        </div>
    `;

    generateQRMock();
}

function generateQRMock() {
    const grid = document.getElementById('payment-qr-grid');
    if (!grid) return;
    grid.style.width = '160px';
    grid.style.height = '160px';
}

async function processPayment() {
    const btn = document.getElementById('step3-pay');
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Đang xử lý...';
    btn.disabled = true;

    const { flight, returnFlight, passengerData, selectedSeats, extras, totalAmount } = bookingState;
    const mainPax = passengerData?.[0] || { lastName: 'KHACH', firstName: 'HANG' };
    const fullName = `${mainPax.lastName} / ${mainPax.firstName}`.trim();
    const seat = selectedSeats[0] || '15A';
    const localPnr = generatePNR();
    const gate = 'B' + Math.floor(Math.random() * 20 + 1);

    const bookingPayload = {
        flightNumber: flight.flightNumber,
        returnFlightNumber: returnFlight ? returnFlight.flightNumber : null,
        origin: flight.origin,
        destination: flight.destination,
        departDate: flight.departDate || currentSearch.departDate || new Date().toISOString().split('T')[0],
        returnDate: returnFlight ? (returnFlight.departDate || currentSearch.returnDate) : null,
        departTime: flight.departureTime || flight.departTime || '08:00',
        arrivalTime: flight.arrivalTime || flight.arriveTime || '10:00',
        passengerName: fullName,
        passengers: passengerData,
        selectedSeats: selectedSeats,
        extras,
        seat,
        gate,
        totalAmount: totalAmount || flight.price,
        userEmail: currentUser ? currentUser.email : null
    };

    let pnr = localPnr;
    let savedBookingData = null;

    try {
        const res = await fetch(`${API_BASE_URL}/bookings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(bookingPayload)
        });
        if (res.ok) {
            savedBookingData = await res.json();
            if (savedBookingData?.pnr) pnr = savedBookingData.pnr;
        }
    } catch (err) {
        console.warn('Booking API offline or failed, saving to local cache:', err);
    }

    bookingState.generatedPNR = pnr;
    bookingState.generatedGate = gate;

    const newBooking = {
        ...(savedBookingData || {}),
        pnr,
        passengerName: fullName,
        flightNumber: flight.flightNumber,
        route: `${flight.origin} → ${flight.destination}${returnFlight ? ` (Khứ hồi: ${returnFlight.origin} → ${returnFlight.destination})` : ''}`,
        origin: flight.origin,
        destination: flight.destination,
        departTime: flight.departureTime || flight.departTime || '08:00',
        arrivalTime: flight.arrivalTime || flight.arriveTime || '10:00',
        departDate: flight.departDate || currentSearch.departDate || new Date().toISOString().split('T')[0],
        status: savedBookingData?.status || 'CONFIRMED',
        seat,
        gate,
        totalAmount: bookingState.totalAmount,
        userEmail: currentUser ? currentUser.email : null,
        createdAt: new Date().toISOString()
    };

    saveBookingToStorage(newBooking);

    btn.innerHTML = '<i class="fa-solid fa-lock"></i> Xác Nhận Thanh Toán';
    btn.disabled = false;

    goToStep(4);
    showToast('success', 'Đặt vé thành công!', `Mã đặt chỗ của bạn: ${pnr}. Đã lưu vào Đặt chỗ của tôi.`);
}

// -------- Boarding Pass --------

function buildBoardingPass() {
    const { flight, passengerData, selectedSeats } = bookingState;
    const pnr = generatePNR();
    const mainPax = passengerData?.[0] || { lastName: 'NGUYEN', firstName: 'VAN A' };
    const fullName = `${mainPax.lastName} / ${mainPax.firstName}`;
    const seat = selectedSeats[0] || '15A';
    const gate = 'B' + Math.floor(Math.random() * 20 + 1);

    bookingState.generatedPNR = pnr;

    document.getElementById('boarding-pass').innerHTML = `
        <div class="bp-top">
            <div class="bp-airline">
                <div class="bp-airline-name">
                    <i class="fa-solid fa-plane-departure"></i>
                    SkyGo Airways
                </div>
                <div class="bp-pnr-badge">${pnr}</div>
            </div>
            <div class="bp-route">
                <div class="bp-city">
                    <div class="bp-city-code">${flight.origin}</div>
                    <div class="bp-city-name">${cityName(flight.origin)}</div>
                </div>
                <div class="bp-route-arrow">
                    <hr><i class="fa-solid fa-plane"></i><hr>
                </div>
                <div class="bp-city">
                    <div class="bp-city-code">${flight.destination}</div>
                    <div class="bp-city-name">${cityName(flight.destination)}</div>
                </div>
            </div>
            <div class="bp-details">
                <div class="bp-field">
                    <label>Hành Khách</label>
                    <span>${fullName}</span>
                </div>
                <div class="bp-field">
                    <label>Chuyến Bay</label>
                    <span>${flight.flightNumber}</span>
                </div>
                <div class="bp-field">
                    <label>Ngày</label>
                    <span>${formatDate(new Date())}</span>
                </div>
                <div class="bp-field">
                    <label>Giờ Cất Cánh</label>
                    <span>${flight.departureTime}</span>
                </div>
            </div>
        </div>
        <div class="bp-tear">
            <div class="bp-tear-circle"></div>
            <hr class="bp-tear-line">
            <div class="bp-tear-circle"></div>
        </div>
        <div class="bp-bottom">
            <div class="bp-qr">
                <div class="bp-qr-inner"></div>
            </div>
            <div class="bp-stub-details">
                <div class="bp-stub-flight">${flight.flightNumber}</div>
                <div class="bp-stub-info">${flight.origin} &rarr; ${flight.destination} &bull; ${flight.departureTime}</div>
                <div class="bp-stub-info">Cửa: ${gate} &bull; Hành khách: ${fullName}</div>
                <div class="bp-stub-seat">GHẾ ${seat}</div>
            </div>
        </div>
    `;
}

function generatePNR() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    let pnr = 'SG';
    for (let i = 0; i < 4; i++) pnr += Math.floor(Math.random() * 10);
    return pnr;
}

function cityName(code) {
    const map = { SGN: 'Hồ Chí Minh', HAN: 'Hà Nội', DAD: 'Đà Nẵng', PQC: 'Phú Quốc', CXR: 'Nha Trang' };
    return map[code] || code;
}

function formatDate(d) {
    return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
}

// ============================================================
// 5. PNR LOOKUP & BOOKINGS STORAGE
// ============================================================

function getStoredBookings() {
    try {
        return JSON.parse(localStorage.getItem(STORAGE_BOOKINGS_KEY) || '[]');
    } catch {
        return [];
    }
}

function saveBookingToStorage(booking) {
    try {
        const bookings = getStoredBookings();
        const idx = bookings.findIndex(b => b.pnr === booking.pnr);
        if (idx >= 0) bookings[idx] = booking;
        else bookings.unshift(booking);
        localStorage.setItem(STORAGE_BOOKINGS_KEY, JSON.stringify(bookings));
    } catch (e) {
        console.error(e);
    }
}

function cancelBooking(pnr) {
    if (!confirm(`Bạn có chắc chắn muốn hủy đặt chỗ cho mã PNR ${pnr}?`)) return;
    const bookings = getStoredBookings();
    const item = bookings.find(b => b.pnr === pnr);
    if (item) {
        item.status = 'CANCELLED';
        saveBookingToStorage(item);
        showToast('info', 'Đã hủy vé', `Mã đặt chỗ ${pnr} đã được chuyển sang trạng thái ĐÃ HỦY.`);
        renderMyBookings();
        displayPNRResult(item, true, item.passengerName);
    }
}

function printTicketFromPNR(pnr) {
    const bookings = getStoredBookings();
    const b = bookings.find(item => item.pnr === pnr);
    if (!b) {
        showToast('error', 'Lỗi', 'Không tìm thấy thông tin vé để in.');
        return;
    }
    bookingState = {
        flight: {
            origin: b.origin || 'SGN',
            destination: b.destination || 'HAN',
            flightNumber: b.flightNumber || 'SG-101',
            departureTime: b.departTime || '08:00',
        },
        passengerData: [{
            lastName: b.passengerName.split('/')[0]?.trim() || 'NGUYEN',
            firstName: b.passengerName.split('/')[1]?.trim() || 'VAN A'
        }],
        selectedSeats: [b.seat || '12A'],
        totalPassengers: 1,
    };
    buildBoardingPass();
    openBookingModal(bookingState.flight);
    goToStep(4);
    setTimeout(() => window.print(), 300);
}

function initPNRForm() {
    const form = document.getElementById('pnr-form');
    form.addEventListener('submit', async (e) => {
        e.preventDefault();

        const pnr = document.getElementById('pnr-code-input').value.trim().toUpperCase();
        const lastName = document.getElementById('pnr-lastname-input').value.trim().toUpperCase();
        const btn = document.getElementById('btn-pnr-search');

        if (!pnr || !lastName) { showToast('error', 'Thiếu thông tin', 'Vui lòng nhập mã PNR và Họ hành khách.'); return; }

        btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i>';
        btn.disabled = true;

        try {
            const res = await fetch(`${API_BASE_URL}/pnr/lookup?code=${pnr}&lastName=${encodeURIComponent(lastName)}`);
            if (!res.ok) {
                const errData = await res.json().catch(() => ({}));
                throw new Error(errData.message || 'Không tìm thấy thông tin');
            }
            const data = await res.json();
            displayPNRResult(data, true, lastName);
        } catch {
            // Mock & LocalStorage lookup
            setTimeout(() => {
                const bookings = getStoredBookings();
                const record = bookings.find(b => b.pnr === pnr);
                if (record && record.passengerName.toUpperCase().includes(lastName)) {
                    displayPNRResult(record, true, lastName);
                } else if (record && !record.passengerName.toUpperCase().includes(lastName)) {
                    displayPNRResult({ message: 'Họ hành khách không khớp với mã PNR đã nhập. Vui lòng kiểm tra lại.' }, false);
                } else {
                    displayPNRResult({ message: `Không tìm thấy đặt chỗ với mã PNR "${pnr}". Vui lòng kiểm tra lại.` }, false);
                }
            }, 600);
        } finally {
            btn.innerHTML = '<i class="fa-solid fa-search"></i> Tra cứu';
            btn.disabled = false;
        }
    });
}

function displayPNRResult(data, isSuccess, lastName) {
    const display = document.getElementById('pnr-result-display');
    display.classList.remove('hidden', 'error', 'success');

    if (isSuccess) {
        display.classList.add('success');
        const isCancelled = data.status === 'CANCELLED';
        display.innerHTML = `
            <div class="pnr-result-header">
                <div class="pnr-badge">${data.pnr}</div>
                <div class="${isCancelled ? 'badge badge-departed' : 'status-confirmed'}">
                    <i class="fa-solid ${isCancelled ? 'fa-ban' : 'fa-circle-check'}"></i> ${data.status}
                </div>
            </div>
            <div class="pnr-detail-card">
                <div>
                    <div class="pnr-field-label">Hành Khách</div>
                    <div class="pnr-field-value">${data.passengerName}</div>
                </div>
                <div>
                    <div class="pnr-field-label">Chuyến Bay</div>
                    <div class="pnr-field-value">${data.flightNumber}</div>
                </div>
                <div>
                    <div class="pnr-field-label">Lộ Trình</div>
                    <div class="pnr-field-value">${data.route}</div>
                </div>
                <div>
                    <div class="pnr-field-label">Ngày Khởi Hành</div>
                    <div class="pnr-field-value">${data.departDate}</div>
                </div>
                <div>
                    <div class="pnr-field-label">Giờ Cất Cánh</div>
                    <div class="pnr-field-value">${data.departTime || '--'}</div>
                </div>
                <div>
                    <div class="pnr-field-label">Ghế</div>
                    <div class="pnr-field-value">${data.seat || 'Chưa chọn'}</div>
                </div>
            </div>
            <div style="margin-top:16px;display:flex;gap:10px;justify-content:flex-end;align-items:center;">
                <button class="btn btn-outline btn-sm" onclick="printTicketFromPNR('${data.pnr}')">
                    <i class="fa-solid fa-print"></i> In Thẻ Lên Máy Bay
                </button>
                ${!isCancelled ? `
                <button class="btn-cancel-ticket" onclick="cancelBooking('${data.pnr}')">
                    <i class="fa-solid fa-ban"></i> Hủy Đặt Chỗ
                </button>` : `<span style="font-size:13px;color:var(--text-muted);font-style:italic;">(Vé này đã bị hủy)</span>`}
            </div>
        `;
    } else {
        display.classList.add('error');
        display.innerHTML = `
            <div style="display:flex;align-items:flex-start;gap:12px;">
                <i class="fa-solid fa-triangle-exclamation" style="font-size:22px;margin-top:2px;"></i>
                <div>
                    <strong>Không tìm thấy thông tin</strong>
                    <p style="margin-top:6px;font-size:14px;">${data.message}</p>
                </div>
            </div>
        `;
    }
}

// ============================================================
// 6. CHECK-IN (With Seat Map & Validation)
// ============================================================

function initCheckinForm() {
    const form = document.getElementById('checkin-form');
    form.addEventListener('submit', async (e) => {
        e.preventDefault();

        const pnr = document.getElementById('checkin-pnr-input').value.trim().toUpperCase();
        const lastName = document.getElementById('checkin-lastname-input')?.value.trim().toUpperCase() || '';
        const btn = document.getElementById('btn-checkin-submit');

        if (!pnr) { showToast('error', 'Thiếu thông tin', 'Vui lòng nhập mã PNR.'); return; }

        btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Đang xử lý...';
        btn.disabled = true;

        try {
            const res = await fetch(`${API_BASE_URL}/checkin`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ pnr, lastName })
            });
            if (!res.ok) {
                const errData = await res.json().catch(() => ({}));
                throw new Error(errData.message || 'Check-in thất bại.');
            }
            const data = await res.json();
            openCheckinSeatSelection(pnr, data);
        } catch {
            setTimeout(() => {
                const bookings = getStoredBookings();
                const record = bookings.find(b => b.pnr === pnr);

                if (!record) {
                    displayCheckinError(`Mã PNR "${pnr}" không tồn tại trong hệ thống.`);
                    return;
                }

                if (lastName && !record.passengerName.toUpperCase().includes(lastName)) {
                    displayCheckinError(`Họ hành khách "${lastName}" không khớp với mã PNR ${pnr}.`);
                    return;
                }

                if (record.status === 'CANCELLED') {
                    displayCheckinError(`Mã vé ${pnr} đã bị hủy, không thể thực hiện check-in.`);
                    return;
                }

                openCheckinSeatSelection(pnr, record);
            }, 600);
        } finally {
            btn.innerHTML = '<i class="fa-solid fa-circle-check"></i> Thực hiện Check-in';
            btn.disabled = false;
        }
    });
}

function openCheckinSeatSelection(pnr, record) {
    activeCheckinRecord = record;
    activeCheckinSeat = record.seat || '12A';

    const summary = document.getElementById('checkin-seatmap-summary');
    if (summary) {
        summary.innerHTML = `
            <div><strong>Hành khách:</strong> ${record.passengerName} &bull; <strong>Chuyến bay:</strong> ${record.flightNumber} (${record.route})</div>
            <div style="margin-top:4px;color:var(--primary);font-weight:600;"><i class="fa-solid fa-clock"></i> Khung giờ check-in hợp lệ (24h - 1h trước giờ bay). Ghế hiện tại: <strong>${record.seat || 'Chưa chọn'}</strong></div>
        `;
    }

    buildCheckinSeatMap(activeCheckinSeat);
    openModal('modal-checkin-seatmap');
}

function buildCheckinSeatMap(currentSeat) {
    const map = document.getElementById('checkin-seat-map');
    if (!map) return;
    const rows = 18;
    const cols = ['A', 'B', 'C', 'D', 'E', 'F'];
    let html = '';

    html += `<div class="seat-row">
        <div class="row-number"></div>
        ${cols.slice(0, 3).map(c => `<div style="width:34px;text-align:center;font-size:10px;font-weight:600;color:var(--text-muted);">${c}</div>`).join('')}
        <div class="aisle"></div>
        ${cols.slice(3).map(c => `<div style="width:34px;text-align:center;font-size:10px;font-weight:600;color:var(--text-muted);">${c}</div>`).join('')}
    </div>`;

    for (let r = 1; r <= rows; r++) {
        html += `<div class="seat-row"><div class="row-number">${r}</div>`;
        cols.forEach((col, ci) => {
            const seatId = `${r}${col}`;
            const isTaken = TAKEN_SEATS.includes(seatId) && seatId !== currentSeat;
            const isSelected = seatId === activeCheckinSeat;

            let cls = 'seat';
            if (isTaken) cls += ' taken';
            if (isSelected) cls += ' selected';

            html += `<div class="${cls}" data-checkin-seat="${seatId}">${seatId}</div>`;
            if (ci === 2) html += `<div class="aisle"></div>`;
        });
        html += `</div>`;
    }

    map.innerHTML = html;

    map.querySelectorAll('.seat:not(.taken)').forEach(seat => {
        seat.addEventListener('click', () => {
            map.querySelectorAll('.seat.selected').forEach(s => s.classList.remove('selected'));
            seat.classList.add('selected');
            activeCheckinSeat = seat.dataset.checkinSeat;
        });
    });
}

function initCheckinSeatmapModal() {
    document.getElementById('close-checkin-seatmap')?.addEventListener('click', () => closeModal('modal-checkin-seatmap'));
    document.getElementById('btn-cancel-checkin-seat')?.addEventListener('click', () => closeModal('modal-checkin-seatmap'));

    document.getElementById('btn-confirm-checkin-seat')?.addEventListener('click', () => {
        if (!activeCheckinRecord) return;
        activeCheckinRecord.seat = activeCheckinSeat;
        activeCheckinRecord.status = 'CHECKED_IN';
        saveBookingToStorage(activeCheckinRecord);
        closeModal('modal-checkin-seatmap');
        displayCheckinSuccess(activeCheckinRecord.pnr, activeCheckinRecord);
        showToast('success', 'Hoàn tất check-in', `Ghế ngồi đã chọn: ${activeCheckinSeat}. Boarding pass sẵn sàng!`);
    });
}

function displayCheckinSuccess(pnr, data) {
    const display = document.getElementById('checkin-result-display');
    display.classList.remove('hidden', 'error', 'success');
    display.classList.add('success');

    display.innerHTML = `
        <div style="margin-bottom:16px;display:flex;align-items:center;gap:12px;">
            <i class="fa-solid fa-circle-check" style="font-size:28px;color:var(--success);"></i>
            <div>
                <strong style="font-size:16px;color:#166534;">Check-in Thành Công!</strong>
                <p style="font-size:13px;margin-top:2px;color:var(--text-muted);">Boarding pass đã được tạo. Vui lòng bấm In Vé hoặc lưu lại để lên máy bay.</p>
            </div>
        </div>
        <div class="boarding-pass" style="max-width:100%;">
            <div class="bp-top">
                <div class="bp-airline">
                    <div class="bp-airline-name">
                        <i class="fa-solid fa-plane-departure"></i> SkyGo Airways
                    </div>
                    <div class="bp-pnr-badge">${pnr}</div>
                </div>
                <div class="bp-route">
                    <div class="bp-city">
                        <div class="bp-city-code">${data.origin || 'SGN'}</div>
                        <div class="bp-city-name">${cityName(data.origin || 'SGN')}</div>
                    </div>
                    <div class="bp-route-arrow">
                        <hr><i class="fa-solid fa-plane"></i><hr>
                    </div>
                    <div class="bp-city">
                        <div class="bp-city-code">${data.destination || 'HAN'}</div>
                        <div class="bp-city-name">${cityName(data.destination || 'HAN')}</div>
                    </div>
                </div>
                <div class="bp-details">
                    <div class="bp-field">
                        <label>Hành Khách</label>
                        <span>${data.passengerName || 'NGUYEN / VAN A'}</span>
                    </div>
                    <div class="bp-field">
                        <label>Chuyến Bay</label>
                        <span>${data.flightNumber || 'SG-101'}</span>
                    </div>
                    <div class="bp-field">
                        <label>Ngày</label>
                        <span>${data.departDate || formatDate(new Date())}</span>
                    </div>
                    <div class="bp-field">
                        <label>Giờ Cất Cánh</label>
                        <span>${data.departTime || '08:00'}</span>
                    </div>
                </div>
            </div>
            <div class="bp-tear">
                <div class="bp-tear-circle"></div>
                <hr class="bp-tear-line">
                <div class="bp-tear-circle"></div>
            </div>
            <div class="bp-bottom">
                <div class="bp-qr"><div class="bp-qr-inner"></div></div>
                <div class="bp-stub-details">
                    <div class="bp-stub-flight">${data.flightNumber || 'SG-101'}</div>
                    <div class="bp-stub-info">${data.origin || 'SGN'} &rarr; ${data.destination || 'HAN'} &bull; ${data.departTime || '08:00'}</div>
                    <div class="bp-stub-info">Cửa: ${data.gate || 'B12'}</div>
                    <div class="bp-stub-seat">GHẾ ${data.seat || '12A'}</div>
                </div>
            </div>
        </div>
        <div style="margin-top:16px;text-align:right;">
            <button class="btn btn-outline" onclick="window.print()">
                <i class="fa-solid fa-print"></i> In Thẻ Lên Máy Bay
            </button>
        </div>
    `;
}

function displayCheckinError(message) {
    const display = document.getElementById('checkin-result-display');
    display.classList.remove('hidden', 'error', 'success');
    display.classList.add('error');
    display.innerHTML = `
        <div style="display:flex;align-items:flex-start;gap:12px;">
            <i class="fa-solid fa-circle-xmark" style="font-size:22px;margin-top:2px;"></i>
            <div>
                <strong>Check-in thất bại</strong>
                <p style="margin-top:6px;font-size:14px;">${message}</p>
            </div>
        </div>
    `;
}

// ============================================================
// 7. AUTH MODALS (Validation & Session Persistence)
// ============================================================

function initModals() {
    // --- Login Modal ---
    const openLoginEl = document.getElementById('btn-login-modal');
    const closeLogin = document.getElementById('close-login');
    const loginForm = document.getElementById('login-form');

    openLoginEl?.addEventListener('click', () => openModal('modal-login'));
    closeLogin?.addEventListener('click', () => closeModal('modal-login'));

    loginForm?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const email = document.getElementById('login-email').value.trim();
        const password = document.getElementById('login-password').value;
        const btn = document.getElementById('btn-login-submit');

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            showToast('error', 'Email không hợp lệ', 'Vui lòng nhập đúng định dạng email (vd: name@domain.com).');
            return;
        }

        btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Đang kiểm tra...';
        btn.disabled = true;

        try {
            const res = await fetch(`${API_BASE_URL}/auth/login`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password })
            });
            const data = await res.json();
            if (res.ok) {
                handleLoginSuccess({ name: data.fullName || email.split('@')[0], email, role: data.role || 'user' });
            } else {
                showToast('error', 'Đăng nhập thất bại', data.message || 'Email hoặc mật khẩu không đúng.');
            }
        } catch {
            const mockName = email.split('@')[0].replace(/[._]/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
            const role = email.toLowerCase() === 'admin@skygo.com' ? 'admin' : 'user';
            handleLoginSuccess({ name: mockName, email, role });
        } finally {
            btn.innerHTML = '<i class="fa-solid fa-right-to-bracket"></i> Đăng Nhập';
            btn.disabled = false;
        }
    });

    // Switch between Login ↔ Register
    document.getElementById('switch-to-register')?.addEventListener('click', (e) => {
        e.preventDefault(); closeModal('modal-login'); openModal('modal-register');
    });

    document.getElementById('switch-to-login')?.addEventListener('click', (e) => {
        e.preventDefault(); closeModal('modal-register'); openModal('modal-login');
    });

    // --- Register Modal ---
    const openRegBtn = document.getElementById('btn-register-modal');
    const closeReg = document.getElementById('close-register');
    const regForm = document.getElementById('register-form');

    openRegBtn?.addEventListener('click', () => openModal('modal-register'));
    closeReg?.addEventListener('click', () => closeModal('modal-register'));

    regForm?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const fullname = document.getElementById('reg-fullname').value.trim();
        const email = document.getElementById('reg-email').value.trim();
        const phone = document.getElementById('reg-phone')?.value.trim() || '';
        const password = document.getElementById('reg-password').value;
        const confirmPassword = document.getElementById('reg-confirm-password')?.value;

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            showToast('error', 'Email không hợp lệ', 'Vui lòng nhập đúng định dạng email (vd: name@domain.com).');
            return;
        }

        if (password.length < 6) {
            showToast('error', 'Mật khẩu quá ngắn', 'Mật khẩu phải có ít nhất 6 ký tự.');
            return;
        }

        if (password !== confirmPassword) {
            showToast('error', 'Mật khẩu không khớp', 'Mật khẩu và xác nhận mật khẩu không trùng khớp.');
            return;
        }

        try {
            await fetch(`${API_BASE_URL}/auth/register`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ fullName: fullname, email, password, phone })
            });
        } catch { /* use mock */ }

        closeModal('modal-register');
        regForm.reset();
        showToast('success', 'Đăng ký thành công!', `Chào mừng ${fullname}! Bạn có thể đăng nhập ngay.`);
    });

    // --- Notification Modal ---
    document.getElementById('close-notification')?.addEventListener('click', () => closeModal('modal-notification'));
    document.getElementById('btn-notif-ok')?.addEventListener('click', () => closeModal('modal-notification'));

    // --- Add Flight Modal ---
    const closeAddFlight = document.getElementById('close-add-flight');
    const addFlightForm = document.getElementById('add-flight-form');

    document.getElementById('btn-add-flight')?.addEventListener('click', () => openModal('modal-add-flight'));
    closeAddFlight?.addEventListener('click', () => closeModal('modal-add-flight'));

    addFlightForm?.addEventListener('submit', (e) => {
        e.preventDefault();
        const newFlight = {
            flightNumber: document.getElementById('af-number').value.trim().toUpperCase(),
            origin: document.getElementById('af-origin').value,
            destination: document.getElementById('af-destination').value,
            departTime: document.getElementById('af-depart-time').value,
            arriveTime: document.getElementById('af-arrive-time').value,
            aircraft: document.getElementById('af-aircraft').value,
            price: Number(document.getElementById('af-price').value),
            status: document.getElementById('af-status').value,
            booked: 0,
            total: Number(document.getElementById('af-aircraft').value === 'A321' ? 180 : 150),
        };

        if (!newFlight.flightNumber || !newFlight.departTime || !newFlight.arriveTime) {
            showToast('error', 'Thiếu thông tin', 'Vui lòng điền đầy đủ thông tin chuyến bay.');
            return;
        }

        adminFlights.unshift(newFlight);
        renderAdminFlightsTable(adminFlights);
        updateAdminMetrics();
        closeModal('modal-add-flight');
        addFlightForm.reset();
        showToast('success', 'Thêm chuyến bay', `Chuyến bay ${newFlight.flightNumber} đã được thêm thành công.`);
    });

    // --- Edit Flight Modal ---
    document.getElementById('close-edit-flight')?.addEventListener('click', () => closeModal('modal-edit-flight'));
    document.getElementById('edit-flight-form')?.addEventListener('submit', (e) => {
        e.preventDefault();
        const origNo = document.getElementById('ef-original-number').value;
        const flight = adminFlights.find(f => f.flightNumber === origNo);
        if (!flight) return;

        flight.flightNumber = document.getElementById('ef-number').value.trim().toUpperCase();
        flight.origin = document.getElementById('ef-origin').value;
        flight.destination = document.getElementById('ef-destination').value;
        flight.departTime = document.getElementById('ef-depart-time').value;
        flight.arriveTime = document.getElementById('ef-arrive-time').value;
        flight.price = Number(document.getElementById('ef-price').value);
        flight.status = document.getElementById('ef-status').value;
        flight.aircraft = document.getElementById('ef-aircraft').value;
        flight.total = flight.aircraft === 'A321' ? 180 : 150;

        renderAdminFlightsTable(adminFlights);
        updateAdminMetrics();
        closeModal('modal-edit-flight');
        showToast('success', 'Cập nhật thành công', `Chuyến bay ${flight.flightNumber} đã được cập nhật.`);
    });

    // Close modals on backdrop click
    document.querySelectorAll('.modal').forEach(modal => {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) closeModal(modal.id);
        });
    });

    // Close modals on Escape
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            document.querySelectorAll('.modal.show').forEach(m => closeModal(m.id));
        }
    });
}

function openModal(id) {
    document.getElementById(id)?.classList.add('show');
    document.body.style.overflow = 'hidden';
}

function closeModal(id) {
    document.getElementById(id)?.classList.remove('show');
    if (!document.querySelector('.modal.show')) {
        document.body.style.overflow = '';
    }
}

function handleLoginSuccess(user, notify = true) {
    currentUser = user;
    localStorage.setItem(STORAGE_USER_KEY, JSON.stringify(user));
    closeModal('modal-login');

    document.getElementById('auth-buttons-guest').classList.add('hidden');
    document.getElementById('auth-buttons-user').classList.remove('hidden');
    document.getElementById('user-display-name').textContent = user.name.split(' ').slice(-1)[0];

    const adminLink = document.getElementById('nav-admin');
    if (adminLink) adminLink.style.display = user.role === 'admin' ? '' : 'none';

    if (notify) {
        showToast('success', 'Đăng nhập thành công!', `Chào mừng trở lại, ${user.name}!`);
    }
}

function restoreUserSession() {
    try {
        const stored = localStorage.getItem(STORAGE_USER_KEY);
        if (stored) {
            currentUser = JSON.parse(stored);
            handleLoginSuccess(currentUser, false);
        }
    } catch (e) {
        console.error('Session restore failed:', e);
    }
}

// ============================================================
// 8. VIEW SWITCHER (Client ↔ Admin)
// ============================================================

function initViewSwitcher() {
    const adminLink = document.getElementById('nav-admin');
    if (adminLink) adminLink.style.display = 'none';

    document.querySelectorAll('.nav-link').forEach(link => {
        link.addEventListener('click', (e) => {
            const view = link.dataset.view;
            if (!view) return;

            if (view === 'admin') {
                e.preventDefault();
                if (!currentUser || currentUser.role !== 'admin') {
                    showToast('warning', 'Không có quyền truy cập', 'Bạn cần đăng nhập bằng tài khoản admin.');
                    openModal('modal-login');
                    return;
                }
                switchView('admin');
            } else {
                switchView('client');
                const href = link.getAttribute('href');
                if (href && href.startsWith('#')) {
                    const target = document.querySelector(href);
                    if (target) setTimeout(() => target.scrollIntoView({ behavior: 'smooth' }), 50);
                }
            }

            document.querySelectorAll('.nav-link').forEach(l => l.classList.remove('active'));
            link.classList.add('active');

            document.getElementById('main-nav')?.classList.remove('open');
            document.getElementById('hamburger-btn')?.classList.remove('open');
        });
    });

    document.getElementById('logo-home-link')?.addEventListener('click', (e) => {
        e.preventDefault();
        switchView('client');
        document.getElementById('nav-booking')?.classList.add('active');
    });
}

function switchView(view) {
    currentView = view;
    const clientView = document.getElementById('client-view');
    const adminView = document.getElementById('admin-view');

    if (view === 'admin') {
        clientView.classList.add('hidden');
        adminView.classList.remove('hidden');
        renderAdminFlightsTable(adminFlights);
        updateAdminMetrics();
    } else {
        adminView.classList.add('hidden');
        clientView.classList.remove('hidden');
    }
}

// ============================================================
// 9. ADMIN DASHBOARD & DYNAMIC METRICS
// ============================================================

function initAdminDashboard() {
    adminFlights = [
        { flightNumber: 'SG-101', origin: 'SGN', destination: 'HAN', departTime: '08:00', arriveTime: '10:00', price: 1450000, booked: 128, total: 150, status: 'checkin', aircraft: 'A320' },
        { flightNumber: 'SG-103', origin: 'SGN', destination: 'HAN', departTime: '11:30', arriveTime: '13:30', price: 1690000, booked: 94, total: 150, status: 'selling', aircraft: 'A320' },
        { flightNumber: 'SG-105', origin: 'SGN', destination: 'HAN', departTime: '17:00', arriveTime: '19:00', price: 2150000, booked: 41, total: 180, status: 'selling', aircraft: 'A321' },
        { flightNumber: 'SG-202', origin: 'HAN', destination: 'SGN', departTime: '07:30', arriveTime: '09:30', price: 1380000, booked: 162, total: 162, status: 'boarding', aircraft: 'B737' },
        { flightNumber: 'SG-204', origin: 'HAN', destination: 'SGN', departTime: '14:00', arriveTime: '16:00', price: 1750000, booked: 110, total: 180, status: 'selling', aircraft: 'A321' },
        { flightNumber: 'SG-301', origin: 'SGN', destination: 'DAD', departTime: '09:00', arriveTime: '10:10', price: 980000, booked: 150, total: 150, status: 'departed', aircraft: 'A320' },
        { flightNumber: 'SG-401', origin: 'HAN', destination: 'DAD', departTime: '10:00', arriveTime: '11:10', price: 870000, booked: 77, total: 150, status: 'checkin', aircraft: 'A320' },
        { flightNumber: 'SG-501', origin: 'SGN', destination: 'PQC', departTime: '12:00', arriveTime: '13:00', price: 1120000, booked: 55, total: 150, status: 'selling', aircraft: 'A320' },
        { flightNumber: 'SG-601', origin: 'DAD', destination: 'HAN', departTime: '15:30', arriveTime: '16:40', price: 890000, booked: 133, total: 150, status: 'selling', aircraft: 'A320' },
        { flightNumber: 'SG-701', origin: 'PQC', destination: 'SGN', departTime: '16:00', arriveTime: '17:00', price: 1050000, booked: 98, total: 162, status: 'checkin', aircraft: 'B737' },
    ];

    document.getElementById('admin-flight-search')?.addEventListener('input', filterAdminTable);
    document.getElementById('admin-status-filter')?.addEventListener('change', filterAdminTable);
    updateAdminMetrics();
}

function updateAdminMetrics() {
    const totalBookings = adminFlights.reduce((acc, f) => acc + (f.booked || 0), 0);
    const totalSeats = adminFlights.reduce((acc, f) => acc + (f.total || 150), 0);
    const totalRevenue = adminFlights.reduce((acc, f) => acc + ((f.booked || 0) * (f.price || 1450000)), 0);
    const occupancyRate = totalSeats > 0 ? ((totalBookings / totalSeats) * 100).toFixed(1) : '0';

    const bEl = document.getElementById('metric-bookings');
    const rEl = document.getElementById('metric-revenue');
    const oEl = document.getElementById('metric-occupancy');
    const fEl = document.getElementById('metric-flights');

    if (bEl) bEl.textContent = totalBookings.toLocaleString('vi-VN');
    if (rEl) rEl.textContent = (totalRevenue / 1000000).toFixed(1) + 'M';
    if (oEl) oEl.textContent = `${occupancyRate}%`;
    if (fEl) fEl.textContent = adminFlights.length;
}

function filterAdminTable() {
    const query = (document.getElementById('admin-flight-search')?.value || '').toLowerCase();
    const status = document.getElementById('admin-status-filter')?.value || '';

    const filtered = adminFlights.filter(f => {
        const matchText = !query || f.flightNumber.toLowerCase().includes(query)
            || f.origin.toLowerCase().includes(query)
            || f.destination.toLowerCase().includes(query);
        const matchStatus = !status || f.status === status;
        return matchText && matchStatus;
    });

    renderAdminFlightsTable(filtered);
}

function renderAdminFlightsTable(flights) {
    const tbody = document.getElementById('admin-flights-tbody');
    if (!tbody) return;

    if (flights.length === 0) {
        tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:32px;color:var(--text-muted);">Không có chuyến bay nào phù hợp</td></tr>`;
        return;
    }

    tbody.innerHTML = flights.map(f => {
        const pct = Math.round((f.booked / f.total) * 100);
        const badge = statusBadge(f.status);
        return `
            <tr>
                <td><span class="flight-no">${f.flightNumber}</span></td>
                <td class="route-cell">
                    <i class="fa-solid fa-plane" style="color:var(--accent);margin-right:6px;font-size:12px;"></i>
                    ${f.origin} → ${f.destination}
                </td>
                <td>
                    <i class="fa-regular fa-clock" style="color:var(--text-muted);margin-right:4px;"></i>
                    ${f.departTime}
                </td>
                <td>
                    <span style="font-size:13px;">${f.booked}/${f.total} (${pct}%)</span>
                    <div class="seats-bar">
                        <div class="seats-fill" style="width:${pct}%"></div>
                    </div>
                </td>
                <td>${badge}</td>
                <td>
                    <div class="action-btns">
                        <button class="btn-icon" title="Chi tiết" onclick="adminViewFlight('${f.flightNumber}')">
                            <i class="fa-solid fa-eye"></i>
                        </button>
                        <button class="btn-icon" title="Chỉnh sửa" onclick="adminEditFlight('${f.flightNumber}')">
                            <i class="fa-solid fa-pen-to-square"></i>
                        </button>
                        <button class="btn-icon" title="Xóa" onclick="adminDeleteFlight('${f.flightNumber}')">
                            <i class="fa-solid fa-trash"></i>
                        </button>
                    </div>
                </td>
            </tr>
        `;
    }).join('');
}

function statusBadge(status) {
    const map = {
        selling: ['badge-selling', 'fa-tag', 'Đang Bán'],
        checkin: ['badge-checkin', 'fa-clipboard-check', 'Check-in'],
        boarding: ['badge-boarding', 'fa-door-open', 'Boarding'],
        departed: ['badge-departed', 'fa-plane-departure', 'Đã Bay'],
    };
    const [cls, icon, label] = map[status] || ['', 'fa-circle', status];
    return `<span class="badge ${cls}"><i class="fa-solid ${icon}"></i> ${label}</span>`;
}

function adminViewFlight(flightNo) {
    const f = adminFlights.find(fl => fl.flightNumber === flightNo);
    if (!f) return;
    const pct = Math.round((f.booked / f.total) * 100);
    showNotification(
        `Chi Tiết Chuyến Bay ${f.flightNumber}`,
        `Lộ trình: ${f.origin} → ${f.destination}\n` +
        `Giờ bay: ${f.departTime} - ${f.arriveTime || '10:00'} | Loại tàu bay: ${f.aircraft || 'A320'}\n` +
        `Giá vé: ${Number(f.price || 1450000).toLocaleString('vi-VN')} VND | Tỷ lệ đặt: ${f.booked}/${f.total} (${pct}%)\n` +
        `Trạng thái: ${f.status.toUpperCase()}`,
        'info'
    );
}

function adminEditFlight(flightNo) {
    const flight = adminFlights.find(f => f.flightNumber === flightNo);
    if (!flight) return;

    document.getElementById('ef-original-number').value = flight.flightNumber;
    document.getElementById('ef-number').value = flight.flightNumber;
    document.getElementById('ef-origin').value = flight.origin;
    document.getElementById('ef-destination').value = flight.destination;
    document.getElementById('ef-depart-time').value = flight.departTime || '08:00';
    document.getElementById('ef-arrive-time').value = flight.arriveTime || '10:00';
    document.getElementById('ef-price').value = flight.price || 1450000;
    document.getElementById('ef-aircraft').value = flight.aircraft || (flight.total === 180 ? 'A321' : 'A320');
    document.getElementById('ef-status').value = flight.status || 'selling';

    openModal('modal-edit-flight');
}

function adminDeleteFlight(flightNo) {
    if (confirm(`Bạn có chắc muốn xóa chuyến bay ${flightNo}?`)) {
        adminFlights = adminFlights.filter(f => f.flightNumber !== flightNo);
        renderAdminFlightsTable(adminFlights);
        updateAdminMetrics();
        showToast('success', 'Đã xóa', `Chuyến bay ${flightNo} đã bị xóa.`);
    }
}

// ============================================================
// 10. HAMBURGER MENU
// ============================================================

function initHamburger() {
    const btn = document.getElementById('hamburger-btn');
    const nav = document.getElementById('main-nav');

    btn?.addEventListener('click', (e) => {
        e.stopPropagation();
        btn.classList.toggle('open');
        nav.classList.toggle('open');
    });

    document.addEventListener('click', (e) => {
        if (!nav?.contains(e.target) && !btn?.contains(e.target)) {
            btn?.classList.remove('open');
            nav?.classList.remove('open');
        }
    });
}

// ============================================================
// 11. PASSWORD VISIBILITY TOGGLE
// ============================================================

function initPasswordToggles() {
    document.querySelectorAll('.toggle-password').forEach(btn => {
        btn.addEventListener('click', () => {
            const targetId = btn.dataset.target;
            const input = document.getElementById(targetId);
            if (!input) return;
            const isText = input.type === 'text';
            input.type = isText ? 'password' : 'text';
            btn.querySelector('i').className = isText ? 'fa-solid fa-eye' : 'fa-solid fa-eye-slash';
        });
    });
}

// ============================================================
// 12. USER MENU, PROFILE & MY BOOKINGS
// ============================================================

function initUserMenu() {
    const btn = document.getElementById('user-avatar-btn');
    const dropdown = document.getElementById('user-dropdown');

    btn?.addEventListener('click', (e) => {
        e.stopPropagation();
        dropdown?.classList.toggle('show');
    });

    document.addEventListener('click', (e) => {
        if (!btn?.contains(e.target) && !dropdown?.contains(e.target)) {
            dropdown?.classList.remove('show');
        }
    });

    document.getElementById('user-profile-link')?.addEventListener('click', (e) => {
        e.preventDefault();
        dropdown?.classList.remove('show');
        if (!currentUser) return;
        document.getElementById('prof-fullname').value = currentUser.name || '';
        document.getElementById('prof-email').value = currentUser.email || '';
        document.getElementById('prof-phone').value = currentUser.phone || '';
        document.getElementById('prof-new-password').value = '';
        openModal('modal-profile');
    });

    document.getElementById('user-bookings-link')?.addEventListener('click', (e) => {
        e.preventDefault();
        dropdown?.classList.remove('show');
        renderMyBookings();
        openModal('modal-my-bookings');
    });

    document.getElementById('btn-logout')?.addEventListener('click', (e) => {
        e.preventDefault();
        currentUser = null;
        localStorage.removeItem(STORAGE_USER_KEY);
        document.getElementById('auth-buttons-user').classList.add('hidden');
        document.getElementById('auth-buttons-guest').classList.remove('hidden');
        document.getElementById('nav-admin').style.display = 'none';
        dropdown?.classList.remove('show');
        if (currentView === 'admin') switchView('client');
        showToast('info', 'Đã đăng xuất', 'Hẹn gặp lại bạn trên SkyGo!');
    });
}

function initProfileModal() {
    document.getElementById('close-profile')?.addEventListener('click', () => closeModal('modal-profile'));
    document.getElementById('close-my-bookings')?.addEventListener('click', () => closeModal('modal-my-bookings'));

    document.getElementById('profile-form')?.addEventListener('submit', (e) => {
        e.preventDefault();
        const newName = document.getElementById('prof-fullname').value.trim();
        const newPhone = document.getElementById('prof-phone').value.trim();
        const newPass = document.getElementById('prof-new-password').value;

        if (!newName) {
            showToast('error', 'Lỗi', 'Họ và tên không được để trống.');
            return;
        }

        currentUser.name = newName;
        currentUser.phone = newPhone;
        if (newPass && newPass.length >= 6) {
            currentUser.password = newPass;
        }

        localStorage.setItem(STORAGE_USER_KEY, JSON.stringify(currentUser));
        document.getElementById('user-display-name').textContent = currentUser.name.split(' ').slice(-1)[0];
        closeModal('modal-profile');
        showToast('success', 'Thành công', 'Hồ sơ cá nhân đã được cập nhật.');
    });
}

function renderMyBookings() {
    const listEl = document.getElementById('my-bookings-list');
    if (!listEl) return;
    const allBookings = getStoredBookings();
    const userBookings = currentUser
        ? allBookings.filter(b => !b.userEmail || b.userEmail === currentUser.email)
        : allBookings;

    if (userBookings.length === 0) {
        listEl.innerHTML = `
            <div style="text-align:center;padding:32px;color:var(--text-muted);">
                <i class="fa-solid fa-plane-slash" style="font-size:40px;margin-bottom:12px;display:block;"></i>
                <p>Bạn chưa có đơn đặt chỗ nào.</p>
                <button class="btn btn-primary btn-sm" style="margin-top:12px;" onclick="closeModal('modal-my-bookings')">Đặt vé ngay</button>
            </div>
        `;
        return;
    }

    listEl.innerHTML = userBookings.map(b => `
        <div class="booking-item-card">
            <div class="booking-item-info">
                <div>
                    <span class="booking-pnr-tag">PNR: ${b.pnr}</span>
                    <span class="badge ${b.status === 'CANCELLED' ? 'badge-departed' : 'badge-selling'}" style="margin-left:8px;">
                        ${b.status}
                    </span>
                </div>
                <strong style="font-size:15px;margin-top:4px;">${b.route || (b.origin + ' → ' + b.destination)} (${b.flightNumber})</strong>
                <span style="font-size:13px;color:var(--text-muted);">
                    <i class="fa-regular fa-calendar"></i> ${b.departDate} &bull; <i class="fa-solid fa-chair"></i> Ghế: ${b.seat || 'Chưa chọn'}
                </span>
                <span style="font-size:13px;color:var(--text-muted);">
                    <i class="fa-regular fa-user"></i> Hành khách: ${b.passengerName}
                </span>
            </div>
            <div class="booking-actions">
                <button class="btn btn-outline btn-sm" onclick="printTicketFromPNR('${b.pnr}')" title="In vé">
                    <i class="fa-solid fa-print"></i> In vé
                </button>
                ${b.status !== 'CANCELLED' ? `
                    <button class="btn-cancel-ticket btn-sm" onclick="cancelBooking('${b.pnr}')" title="Hủy vé">
                        <i class="fa-solid fa-ban"></i> Hủy
                    </button>
                ` : ''}
            </div>
        </div>
    `).join('');
}

// ============================================================
// 13. VOUCHER SYSTEM
// ============================================================

function initVoucher() {
    document.getElementById('btn-apply-voucher')?.addEventListener('click', () => {
        const input = document.getElementById('voucher-input');
        const msg = document.getElementById('voucher-message');
        const code = input?.value.trim().toUpperCase();

        if (!code) {
            msg.innerHTML = '<span style="color:var(--error);">Vui lòng nhập mã ưu đãi.</span>';
            return;
        }

        if (code === 'SKYGO10') {
            appliedVoucher = { code, type: 'percent', value: 10, label: 'Giảm 10% tổng tiền vé' };
            msg.innerHTML = '<span style="color:var(--success);font-weight:600;"><i class="fa-solid fa-check"></i> Đã áp dụng mã SKYGO10: Giảm 10%!</span>';
            showToast('success', 'Mã ưu đãi hợp lệ', 'Đã giảm 10% tổng tiền vé!');
        } else if (code === 'BAYNGAY') {
            appliedVoucher = { code, type: 'fixed', value: 100000, label: 'Giảm 100.000 VND' };
            msg.innerHTML = '<span style="color:var(--success);font-weight:600;"><i class="fa-solid fa-check"></i> Đã áp dụng mã BAYNGAY: Giảm 100.000 VND!</span>';
            showToast('success', 'Mã ưu đãi hợp lệ', 'Đã giảm 100.000 VND!');
        } else {
            appliedVoucher = null;
            msg.innerHTML = '<span style="color:var(--error);"><i class="fa-solid fa-xmark"></i> Mã không hợp lệ hoặc đã hết hạn.</span>';
            showToast('error', 'Mã không hợp lệ', 'Mã voucher không tồn tại.');
        }

        buildFareSummary();
    });
}

// ============================================================
// 14. TOAST NOTIFICATIONS & LEGACY HELPERS
// ============================================================

function showToast(type, title, message) {
    const container = document.getElementById('toast-container');
    const icons = {
        success: 'fa-circle-check',
        error: 'fa-circle-xmark',
        warning: 'fa-triangle-exclamation',
        info: 'fa-circle-info',
    };

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `
        <div class="toast-icon"><i class="fa-solid ${icons[type] || icons.info}"></i></div>
        <div class="toast-body">
            <strong>${title}</strong>
            <p>${message}</p>
        </div>
    `;

    container.appendChild(toast);

    setTimeout(() => {
        toast.classList.add('toast-out');
        toast.addEventListener('animationend', () => toast.remove());
    }, 4000);
}

function showNotification(title, message, type = 'info') {
    const modal = document.getElementById('modal-notification');
    const titleEl = document.getElementById('notif-title');
    const msgEl = document.getElementById('notif-message');
    const iconEl = document.getElementById('notif-icon');

    titleEl.textContent = title;
    msgEl.innerText = message;

    const iconMap = {
        error: { icon: 'fa-circle-xmark', color: 'var(--error)' },
        success: { icon: 'fa-circle-check', color: 'var(--success)' },
        info: { icon: 'fa-circle-info', color: 'var(--info)' },
    };

    const { icon, color } = iconMap[type] || iconMap.info;
    iconEl.innerHTML = `<i class="fa-solid ${icon}" style="color:${color};"></i>`;

    openModal('modal-notification');
}

function selectFlight(flightNumber) {
    showNotification('Chọn Chuyến Bay', `Bạn đã chọn chuyến bay ${flightNumber}. Tiếp tục đặt vé...`, 'info');
}

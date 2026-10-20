/**
 * SkyGo Frontend Logic - Role 3: Frontend (Client & Admin)
 * Includes: Auth modals, Booking stepper, Seat map, PNR, Check-in, Admin dashboard
 */

'use strict';

// ============================================================
// CONSTANTS & STATE
// ============================================================

// Served by Spring Boot on the same origin.  This also works when another member
// changes SERVER_PORT, unlike a hard-coded localhost:8080 URL.
const API_BASE_URL = '/api';
const STORAGE_USER_KEY = 'skygo_currentUser';
const STORAGE_BOOKINGS_KEY = 'skygo_bookings'; // legacy cache only; SQL Server is the source of truth

const nativeFetch = window.fetch.bind(window);
window.fetch = (url, options = {}) => {
    const token = JSON.parse(localStorage.getItem(STORAGE_USER_KEY) || '{}').token;
    const headers = new Headers(options.headers || {});
    if (token) headers.set('Authorization', `Bearer ${token}`);
    return nativeFetch(url, { ...options, headers });
};

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
    enhanceDateInputs();
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
    loadAirports();
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

        if (!validISODate(departDate) || departDate < todayISO()) { showToast('error', 'Ngày không hợp lệ', 'Chọn ngày đi theo dd/MM/yyyy, không trước hôm nay.'); return; }
        if (isRoundtrip && !validISODate(returnDate)) {
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
            adults: passengerState.adults + passengerState.children + passengerState.infants,
            children: 0,
            infants: 0
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
    document.getElementById('results-count').textContent = `${currentSearch.isRoundtrip ? 'Chọn chiều đi · ' : ''}${flights.length} chuyến phù hợp`;
    document.getElementById('flight-results-list').innerHTML = flightCards(flights);
    document.getElementById('results-section').classList.remove('hidden');
    document.getElementById('results-section').scrollIntoView({behavior:'smooth'});
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
    const query = new URLSearchParams({origin:currentSearch.destination, destination:currentSearch.origin,
        departDate:currentSearch.returnDate, adults:passengerState.adults + passengerState.children + passengerState.infants});
    try {
        const res = await fetch(`${API_BASE_URL}/flights/search?${query}`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.message);
        const flights = data.filter(f => f.departure > currentSearch.selectedOutbound.arrival);
        document.getElementById('results-count').textContent = `Chọn chiều về · ${flights.length} chuyến phù hợp`;
        document.getElementById('flight-results-list').innerHTML = `<p>Đã chọn chiều đi: ${escapeHtml(currentSearch.selectedOutbound.flightNumber)} · ${fareLabel(currentSearch.selectedOutbound.fareClass)} · ${displayDate(currentSearch.departDate)}</p>` +
            (flights.length ? flightCards(flights, true) : '<p>Không có chuyến về phù hợp sau giờ đến của chiều đi.</p>');
    } catch (err) { showToast('error','Lỗi tìm chiều về',err.message); }
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
    const today = todayISO();
    const d = document.getElementById('depart-date');
    const r = document.getElementById('return-date');
    if (d) d.min = today;
    if (r) r.min = today;
    d?.addEventListener('change', () => {
        r.min = d.value || today;
        if (r.value && r.value < r.min) {
            r.value = '';
            r.dispatchEvent(new Event('change'));
        }
    });
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
        totalPassengers: passengerState.adults + passengerState.children + passengerState.infants,
    };

    document.getElementById('booking-flight-summary').innerHTML = bookingSummaryHTML();

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
    enhanceDateInputs(container);
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
                    <input type="date" id="pax-${idx}-dob" required max="${todayISO()}">
                </div>
                <div class="form-group">
                    <label>CCCD / Hộ chiếu</label>
                    <input type="text" id="pax-${idx}-id" placeholder="Số CCCD hoặc hộ chiếu">
                </div>
                ` : `
                <div class="form-group">
                    <label>Ngày sinh</label>
                    <input type="date" id="pax-${idx}-dob" required max="${todayISO()}">
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
        const dob = document.getElementById(`pax-${i}-dob`);
        if (!validISODate(dob.value) || dob.value > todayISO()) {
            showToast('error','Ngày sinh không hợp lệ',`Hành khách ${i + 1}: nhập ngày sinh theo dd/MM/yyyy, không ở tương lai.`);
            document.getElementById(`pax-${i}-dob-display`).focus();
            return false;
        }
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
            dateOfBirth: document.getElementById(`pax-${i}-dob`)?.value || null,
            gender: document.getElementById(`pax-${i}-gender`)?.value || null,
            documentNumber: document.getElementById(`pax-${i}-id`)?.value?.trim() || null,
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
    document.getElementById('seat-map').innerHTML = '<p>Ghế được chọn riêng cho từng hành khách và từng chặng khi làm thủ tục check-in.</p>';
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
    if (!bookingState.extras) return;
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
    const flights = [bookingState.flight, bookingState.returnFlight].filter(Boolean);
    const total = flights.reduce((sum, f) => sum + Number(f.price), 0) * bookingState.totalPassengers;
    bookingState.totalAmount = total;
    document.getElementById('fare-summary').innerHTML = `<h5>Tóm tắt chi phí</h5>${bookingSummaryHTML()}
        <p>${bookingState.totalPassengers} hành khách · Giá từng hạng đã gồm thuế/phí.</p>
        <p>Giá áp dụng như nhau cho mỗi hành khách theo biểu giá hiện hành. Giá cuối cùng được kiểm tra khi đặt vé.</p>
        <div class="fare-row total"><span>Tổng cộng</span><span>${money(total)}</span></div>`;
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
    const seat = null;
    const gate = 'B12';

    const bookingPayload = {
        flightNumber: flight.flightCode || flight.flightNumber,
        returnFlightNumber: returnFlight ? (returnFlight.flightCode || returnFlight.flightNumber) : null,
        fareClass: flight.fareClass,
        returnFareClass: returnFlight?.fareClass || null,
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
        paymentMethod: document.querySelector('input[name="payment"]:checked')?.value || 'vietqr'
    };

    let savedBookingData;

    try {
        const res = await fetch(`${API_BASE_URL}/bookings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(bookingPayload)
        });
        const body = await res.json();
        if (!res.ok) throw new Error(body.message || 'Không thể tạo đơn đặt vé.');
        savedBookingData = body;
    } catch (err) {
        showToast('error', 'Đặt vé chưa hoàn tất', err.message || 'Không thể kết nối tới máy chủ.');
        btn.innerHTML = '<i class="fa-solid fa-lock"></i> Xác Nhận Thanh Toán';
        btn.disabled = false;
        return;
    }

    const pnr = savedBookingData.pnr;
    bookingState.generatedPNR = pnr;
    bookingState.confirmedBooking = savedBookingData;
    bookingState.totalAmount = savedBookingData.totalAmount;
    bookingState.generatedGate = gate;

    const newBooking = {
        ...savedBookingData,
        pnr,
        passengerName: fullName,
        flightNumber: flight.flightNumber,
        route: `${flight.origin} → ${flight.destination}${returnFlight ? ` (Khứ hồi: ${returnFlight.origin} → ${returnFlight.destination})` : ''}`,
        origin: flight.origin,
        destination: flight.destination,
        departTime: flight.departureTime || flight.departTime || '08:00',
        arrivalTime: flight.arrivalTime || flight.arriveTime || '10:00',
        departDate: flight.departDate || currentSearch.departDate || new Date().toISOString().split('T')[0],
        status: savedBookingData.status,
        seat,
        gate,
        totalAmount: savedBookingData.totalAmount,
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
    const container = document.getElementById('boarding-pass');
    container.classList.remove('boarding-pass');
    container.classList.add('booking-confirmation');
    try {
        const data = bookingState.confirmedBooking;
        if (!data || !Array.isArray(data.tickets) || !data.tickets.length) throw new Error('Không tải được thông tin vé. Vui lòng tra cứu PNR để xem lại.');
        container.innerHTML = `<p class="booking-confirmation-total">Tổng thanh toán: ${money(data.totalAmount)}</p>` + data.tickets.map(t => boardingPassHTML(t)).join('');
    } catch (err) { container.innerHTML = `<p class="ticket-load-error" role="alert">${escapeHtml(err.message)}</p>`; }
}

function generatePNR() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    let pnr = 'SG';
    for (let i = 0; i < 4; i++) pnr += Math.floor(Math.random() * 10);
    return pnr;
}

// cityName uses cityNameMap defined at bottom of file (loaded from API + fallback)
function cityName(code) {
    if (typeof cityNameMap !== 'undefined') return cityNameMap[code] || code;
    const fallback = { SGN: 'Hồ Chí Minh', HAN: 'Hà Nội', DAD: 'Đà Nẵng', PQC: 'Phú Quốc', CXR: 'Nha Trang', TBB: 'Tuy Hòa' };
    return fallback[code] || code;
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

async function cancelBooking(pnr) {
    if (!confirm(`Bạn có chắc chắn muốn hủy đặt chỗ cho mã PNR ${pnr}?`)) return;
    try {
        const res = await fetch(`${API_BASE_URL}/bookings/${encodeURIComponent(pnr)}`, { method: 'DELETE' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || 'Không thể hủy đơn.');
        showToast('success', 'Đã hủy vé', `Mã đặt chỗ ${pnr} đã được cập nhật trên database.`);
        renderMyBookings();
        // Update PNR result display if currently visible
        const pnrDisplay = document.getElementById('pnr-result-display');
        if (pnrDisplay && !pnrDisplay.classList.contains('hidden')) {
            const badge = pnrDisplay.querySelector('.status-confirmed');
            if (badge) {
                badge.className = 'badge badge-departed';
                badge.innerHTML = '<i class="fa-solid fa-ban"></i> CANCELLED';
            }
            const cancelBtn = pnrDisplay.querySelector('.btn-cancel-ticket');
            if (cancelBtn) {
                cancelBtn.outerHTML = '<span style="font-size:13px;color:var(--text-muted);font-style:italic;">(Vé này đã bị hủy)</span>';
            }
            const checkinBtn = pnrDisplay.querySelector('.btn-checkin-link');
            if (checkinBtn) checkinBtn.remove();
        }
        return;
    } catch (err) { showToast('error', 'Hủy vé thất bại', err.message); return; }
}

function printTicketFromPNR(pnr) {
    closeModal('modal-my-bookings');
    switchView('client');
    document.getElementById('pnr-code-input').value = pnr;
    document.getElementById('pnr-lastname-input').focus();
    showToast('info','Tra cứu vé','Nhập họ hành khách để xem đầy đủ vé và chọn thẻ lên máy bay.');
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
        } catch (err) {
            displayPNRResult({message:err.message}, false);
        } finally {
            btn.innerHTML = '<i class="fa-solid fa-search"></i> Tra cứu';
            btn.disabled = false;
        }
    });
}

function displayPNRResult(data, isSuccess, lastName) {
    const display = document.getElementById('pnr-result-display');
    display.classList.remove('hidden','error','success');
    if (!isSuccess) { display.classList.add('error'); display.textContent = data.message; return; }
    display.classList.add('success');
    display.innerHTML = `<strong>PNR ${escapeHtml(data.pnr)} · ${escapeHtml(data.status)}</strong>${ticketList(data.tickets)}
        <button id="pnr-to-checkin" class="btn btn-primary">Chọn vé để check-in / xem thẻ</button>`;
    document.getElementById('pnr-to-checkin').onclick = () => goToOnlineCheckin(data.pnr, encodeURIComponent(lastName));
}

function goToOnlineCheckin(pnr, encodedLastName) {
    const lastName = decodeURIComponent(encodedLastName || '');
    switchView('checkin');
    const pnrInput = document.getElementById('checkin-pnr-input');
    const lastNameInput = document.getElementById('checkin-lastname-input');
    if (pnrInput) pnrInput.value = pnr;
    if (lastNameInput && lastName) lastNameInput.value = lastName;
    const form = document.getElementById('checkin-form');
    if (form && pnr && lastName) {
        form.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
    }
}

// ============================================================
// 6. CHECK-IN (With Seat Map & Validation)
// ============================================================

function initCheckinForm() {
    document.getElementById('checkin-form').addEventListener('submit', async e => {
        e.preventDefault();
        checkinAccess = {pnr:document.getElementById('checkin-pnr-input').value.trim(),
            lastName:document.getElementById('checkin-lastname-input').value.trim()};
        try { await refreshCheckinTickets(); }
        catch (err) { displayCheckinError(err.message); }
    });
}

function normalizeSeat(s) {
    if (!s) return '';
    const match = String(s).trim().toUpperCase().match(/^0*(\d+)([A-Z])$/);
    if (match) {
        return `${parseInt(match[1], 10)}${match[2]}`; // "03A" -> "3A"
    }
    return String(s).trim().toUpperCase();
}

function openCheckinSeatSelection(pnr, record) {
    activeCheckinRecord = record;
    activeCheckinSeat = null;
    document.getElementById('checkin-seatmap-summary').innerHTML = `${escapeHtml(record.passengerName)} · ${escapeHtml(record.route)} · ${displayDate(record.departDate)} ${escapeHtml(record.departTime)} · ${fareLabel(record.fareClass)}`;
    buildCheckinSeatMap();
    openModal('modal-checkin-seatmap');
}

function buildCheckinSeatMap() {
    const map = document.getElementById('checkin-seat-map');
    const record = activeCheckinRecord;
    if (!Array.isArray(record.allSeats) || !record.allSeats.length) {
        map.innerHTML = '<p role="alert">Không tải được cấu hình ghế của chuyến bay. Vui lòng đóng và chọn lại vé.</p>';
        return;
    }
    const available = new Set(record.availableSeats.map(normalizeSeat));
    const cabins = new Map();
    for (const seat of record.allSeats) {
        const parts = /^(\d+)([A-Z])$/.exec(normalizeSeat(seat.seat));
        if (!parts) continue;
        if (!cabins.has(seat.fareClass)) cabins.set(seat.fareClass, []);
        cabins.get(seat.fareClass).push({...seat, row:Number(parts[1]), column:parts[2]});
    }
    map.innerHTML = [...cabins.entries()].map(([fare, seats]) => {
        const columns = [...new Set(seats.map(s => s.column))].sort();
        const split = Math.ceil(columns.length / 2);
        const rows = [...new Set(seats.map(s => s.row))].sort((a,b) => a-b);
        const cells = (row, header = false) => columns.map((col, i) => {
            const aisle = i === split ? '<span class="aisle" aria-hidden="true"></span>' : '';
            if (header) return aisle + `<span class="seat-column">${col}</span>`;
            const seat = seats.find(s => s.row === row && s.column === col);
            if (!seat) return aisle + '<span class="seat-gap" aria-hidden="true"></span>';
            const sameClass = fare === record.fareClass;
            const canSelect = sameClass && available.has(normalizeSeat(seat.seat));
            const taken = Boolean(Number(seat.taken));
            const reason = taken ? 'Đã có người' : !sameClass ? 'Khác hạng vé đã mua' : !canSelect ? 'Không khả dụng' : 'Còn trống';
            return aisle + `<button type="button" class="seat${taken ? ' taken' : !canSelect ? ' unavailable' : ''}" data-checkin-seat="${escapeHtml(seat.seat)}" aria-label="Ghế ${escapeHtml(seat.seat)}: ${reason}" title="${reason}" ${canSelect ? '' : 'disabled'}>${escapeHtml(seat.seat)}</button>`;
        }).join('');
        return `<section class="cabin-seat-map"><h4>${fareLabel(fare)}</h4><div class="seat-row"><span class="row-number">Hàng</span>${cells(null,true)}</div>` +
            rows.map(row => `<div class="seat-row"><span class="row-number">${row}</span>${cells(row)}</div>`).join('') + '</section>';
    }).join('');
    if (!available.size) map.insertAdjacentHTML('afterbegin','<p>Không còn ghế khả dụng cho hạng vé này.</p>');
    map.querySelectorAll('[data-checkin-seat]').forEach(button => button.onclick = () => {
        if (button.disabled) return;
        map.querySelectorAll('.selected').forEach(el => el.classList.remove('selected'));
        button.classList.add('selected');
        activeCheckinSeat = button.dataset.checkinSeat;
    });
}

function initCheckinSeatmapModal() {
    document.getElementById('close-checkin-seatmap')?.addEventListener('click', () => closeModal('modal-checkin-seatmap'));
    document.getElementById('btn-cancel-checkin-seat')?.addEventListener('click', () => closeModal('modal-checkin-seatmap'));

    document.getElementById('btn-confirm-checkin-seat')?.addEventListener('click', async () => {
        if (!activeCheckinRecord) return;
        if (!activeCheckinSeat) {
            showToast('warning', 'Chưa chọn ghế', 'Vui lòng bấm chọn một ghế trống màu trắng trên sơ đồ trước khi hoàn tất.');
            return;
        }

        const button = document.getElementById('btn-confirm-checkin-seat');
        button.disabled = true;
        button.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Đang xử lý...';
        const selectedTicket = activeCheckinRecord;
        const selectedSeat = activeCheckinSeat;
        try {
            const lastNameVal = checkinAccess.lastName;
            const res = await fetch(`${API_BASE_URL}/checkin/confirm`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    pnr: selectedTicket.pnr,
                    lastName: lastNameVal,
                    ticketId: selectedTicket.ticketId,
                    seat: selectedSeat
                })
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.message || 'Không thể ghi nhận check-in.');
            if (data.ticketId !== selectedTicket.ticketId) throw new Error('Máy chủ trả về thẻ của vé khác. Vui lòng tra cứu lại.');

            closeModal('modal-checkin-seatmap');
            try { await refreshCheckinTickets(); }
            catch { showToast('warning','Chưa tải lại được danh sách','Check-in đã được ghi nhận. Vui lòng tra cứu lại danh sách vé.'); }
            displayCheckinSuccess(data.pnr, data);
            showToast('success', 'Hoàn tất check-in', `Ghế ngồi ${data.seat} đã được xác nhận.`);
        } catch (err) {
            showToast('error', 'Check-in thất bại', err.message);
        } finally {
            button.disabled = false;
            button.innerHTML = '<i class="fa-solid fa-circle-check"></i> Xác nhận chọn ghế & Hoàn tất Check-in';
        }
    });
}

function displayCheckinSuccess(pnr, data) {
    const display = document.getElementById('checkin-result-display');
    display.classList.remove('hidden', 'error');
    display.classList.add('success');
    try {
        if (data?.pnr !== pnr) throw new Error('Thẻ không thuộc mã đặt chỗ đang xem. Vui lòng tra cứu lại.');
        display.innerHTML = boardingPassHTML(data, true) + `
        <button class="btn btn-outline" onclick="window.print()">In thẻ</button>
        <button class="btn btn-primary" onclick="refreshCheckinTickets().catch(e => displayCheckinError(e.message))">Quay lại danh sách vé</button>`;
        display.scrollIntoView({behavior:'smooth',block:'start'});
    } catch (err) { displayCheckinError(err.message); }
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
                <p style="margin-top:6px;font-size:14px;">${escapeHtml(message)}</p>
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

        if (!email) {
            showToast('error', 'Thiếu thông tin', 'Vui lòng nhập email hoặc tên đăng nhập.');
            return;
        }

        if (email.includes('@')) {
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(email)) {
                showToast('error', 'Email không hợp lệ', 'Vui lòng nhập đúng định dạng email (vd: name@domain.com).');
                return;
            }
        } else if (email.length < 3) {
            showToast('error', 'Tên đăng nhập không hợp lệ', 'Tên đăng nhập phải có ít nhất 3 ký tự.');
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
            handleLoginSuccess({ name: data.fullName || email.split('@')[0], email: data.email || email, phone: data.phone || '', token: data.token, role: data.role || 'user' });
            } else {
                showToast('error', 'Đăng nhập thất bại', data.message || 'Email hoặc mật khẩu không đúng.');
            }
        } catch (err) {
            showToast('error', 'Không thể đăng nhập', 'Không thể kết nối đến backend hoặc database.');
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
            const res = await fetch(`${API_BASE_URL}/auth/register`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ fullName: fullname, email, password, phone })
            });
            if (!res.ok) {
                const data = await res.json().catch(() => ({}));
                throw new Error(data.message || 'Không thể đăng ký tài khoản.');
            }
        } catch (err) { showToast('error', 'Đăng ký thất bại', err.message); return; }

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

    addFlightForm?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const flightNumber = document.getElementById('af-number').value.trim().toUpperCase();
        const origin = document.getElementById('af-origin').value;
        const destination = document.getElementById('af-destination').value;
        const departDate = document.getElementById('af-depart-date')?.value || new Date(Date.now() + 86400000).toISOString().split('T')[0];
        const departTime = document.getElementById('af-depart-time').value;
        const arriveTime = document.getElementById('af-arrive-time').value;
        const price = Number(document.getElementById('af-price').value);
        const status = document.getElementById('af-status').value;

        if (!flightNumber || !departTime || !arriveTime || !price) {
            showToast('error', 'Thiếu thông tin', 'Vui lòng điền đầy đủ thông tin chuyến bay.');
            return;
        }

        const payload = {
            flightNumber: flightNumber,
            origin: origin,
            destination: destination,
            departure: `${departDate}T${departTime}:00`,
            arrival: `${arriveTime <= departTime ? addFlightDay(departDate) : departDate}T${arriveTime}:00`,
            basePrice: price,
            status: status,
            aircraft: document.getElementById('af-aircraft').value
        };

        try {
            const res = await fetch(`${API_BASE_URL}/admin/flights`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.message || 'Không thể tạo chuyến bay.');
            closeModal('modal-add-flight');
            addFlightForm.reset();
            await loadAdminFlights();
            showToast('success', 'Thêm chuyến bay', `Chuyến bay ${flightNumber} đã được lưu vào database.`);
        } catch (err) {
            showToast('error', 'Thêm thất bại', err.message);
        }
    });

    // --- Edit Flight Modal ---
    document.getElementById('close-edit-flight')?.addEventListener('click', () => closeModal('modal-edit-flight'));
    document.getElementById('edit-flight-form')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const origNo = document.getElementById('ef-original-number').value;
        const flight = adminFlights.find(f => f.flightNumber === origNo);
        if (!flight) return;

        const flightNumber = document.getElementById('ef-number').value.trim().toUpperCase();
        const origin = document.getElementById('ef-origin').value;
        const destination = document.getElementById('ef-destination').value;
        const departDate = document.getElementById('ef-depart-date').value;
        const departTime = document.getElementById('ef-depart-time').value;
        const arriveTime = document.getElementById('ef-arrive-time').value;
        const basePrice = Number(document.getElementById('ef-price').value);
        if (!flightNumber || !departDate || !departTime || !arriveTime || !Number.isFinite(basePrice) || basePrice < 0) {
            showToast('error', 'Thiếu thông tin', 'Vui lòng kiểm tra đầy đủ thông tin chuyến bay.');
            return;
        }

        try {
            const arrivalDate = arriveTime <= departTime ? addFlightDay(departDate) : departDate;
            const res = await fetch(`${API_BASE_URL}/admin/flights/${encodeURIComponent(flight.flightCode)}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    flightNumber,
                    origin,
                    destination,
                    departure: `${departDate}T${departTime}:00`,
                    arrival: `${arrivalDate}T${arriveTime}:00`,
                    basePrice,
                    status: document.getElementById('ef-status').value,
                    aircraft: document.getElementById('ef-aircraft').value
                })
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.message || 'Không thể cập nhật chuyến bay.');
            closeModal('modal-edit-flight');
            await loadAdminFlights();
            showToast('success', 'Cập nhật thành công', `Thông tin chuyến bay ${flightNumber} đã được lưu vào database.`);
        } catch (err) { showToast('error', 'Cập nhật thất bại', err.message); }
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

    document.getElementById('auth-buttons-guest')?.classList.add('hidden');
    document.getElementById('auth-buttons-user')?.classList.remove('hidden');
    
    const displayName = user.name ? user.name.split(' ').slice(-1)[0] : 'Khách';
    const nameEl = document.getElementById('user-display-name');
    if (nameEl) {
        nameEl.innerHTML = `${displayName} ${user.role === 'admin' ? '<span class="user-role-badge">ADMIN</span>' : ''}`;
    }

    const adminLink = document.getElementById('nav-admin');
    if (adminLink) {
        adminLink.style.display = user.role === 'admin' ? '' : 'none';
    }

    if (notify) {
        showToast('success', 'Đăng nhập thành công!', `Chào mừng trở lại, ${user.name}!`);
    }

    if (user.role === 'admin' && currentView === 'admin') {
        loadAdminFlights();
        updateAdminMetrics();
    }
}

function restoreUserSession() {
    try {
        const stored = localStorage.getItem(STORAGE_USER_KEY);
        if (stored && JSON.parse(stored).token) {
            currentUser = JSON.parse(stored);
            handleLoginSuccess(currentUser, false);
        }
    } catch (e) {
        console.error('Session restore failed:', e);
    }
}

// ============================================================
// 8. VIEW SWITCHER (Multi-View: Home, PNR, Check-in, Admin)
// ============================================================

function initViewSwitcher() {
    const adminLink = document.getElementById('nav-admin');
    if (adminLink) adminLink.style.display = (currentUser && currentUser.role === 'admin') ? '' : 'none';

    document.querySelectorAll('.nav-link').forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();
            const view = link.dataset.view;
            if (!view) return;
            switchView(view);
            document.getElementById('main-nav')?.classList.remove('open');
            document.getElementById('hamburger-btn')?.classList.remove('open');
        });
    });

    document.getElementById('logo-home-link')?.addEventListener('click', (e) => {
        e.preventDefault();
        switchView('home');
    });

    // Handle initial route via hash
    window.addEventListener('hashchange', handleHashRouting);
    handleHashRouting();

    // Init popular routes clicks
    initPopularRoutes();
}

function handleHashRouting() {
    const hash = window.location.hash.replace('#', '').toLowerCase();
    if (['home', 'pnr', 'checkin', 'admin'].includes(hash)) {
        switchView(hash, false);
    }
}

function switchView(view, updateHash = true) {
    if (view === 'client') view = 'home';

    if (view === 'admin') {
        if (!currentUser || currentUser.role !== 'admin') {
            showToast('warning', 'Yêu cầu quyền Quản trị', 'Bạn cần đăng nhập bằng tài khoản Quản trị viên để truy cập trang này.');
            openModal('modal-login');
            return;
        }
    }

    currentView = view;
    if (updateHash) {
        history.replaceState(null, null, `#${view}`);
    }

    const views = {
        home: document.getElementById('home-view'),
        pnr: document.getElementById('pnr-view'),
        checkin: document.getElementById('checkin-view'),
        admin: document.getElementById('admin-view'),
    };

    Object.keys(views).forEach(key => {
        const el = views[key];
        if (el) {
            if (key === view) {
                el.classList.remove('hidden');
            } else {
                el.classList.add('hidden');
            }
        }
    });

    // Fallback for legacy client-view container if any
    const legacyClient = document.getElementById('client-view');
    if (legacyClient) {
        if (view === 'admin') legacyClient.classList.add('hidden');
        else legacyClient.classList.remove('hidden');
    }

    // Update active state on nav links
    document.querySelectorAll('.nav-link').forEach(link => {
        if (link.dataset.view === view) {
            link.classList.add('active');
        } else {
            link.classList.remove('active');
        }
    });

    if (view === 'admin') {
        loadAdminFlights();
        updateAdminMetrics();
    }

    window.scrollTo({ top: 0, behavior: 'smooth' });
}

function initPopularRoutes() {
    document.querySelectorAll('.popular-route-card').forEach(card => {
        card.addEventListener('click', () => {
            const origin = card.dataset.origin;
            const dest = card.dataset.dest;
            if (!origin || !dest) return;

            const originEl = document.getElementById('origin');
            const destEl = document.getElementById('destination');
            if (originEl) originEl.value = origin;
            if (destEl) destEl.value = dest;

            switchView('home');
            showToast('info', 'Đã chọn tuyến bay', `${card.querySelector('.pr-route')?.textContent || origin + ' → ' + dest}`);
            const searchForm = document.getElementById('flight-search-form');
            if (searchForm) {
                searchForm.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        });
    });
}

async function loadAdminFlights() {
    try {
        const res = await fetch(`${API_BASE_URL}/admin/flights`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || 'Không thể tải danh sách chuyến bay.');
        adminFlights = data;
        renderAdminFlightsTable(adminFlights);
        updateAdminMetrics();
    } catch (err) {
        showToast('error', 'Không tải được quản trị', err.message || 'Kiểm tra lại tài khoản quản trị và database.');
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

async function updateAdminMetrics() {
    try {
        const res = await fetch(`${API_BASE_URL}/admin/stats`);
        if (res.ok) {
            const stats = await res.json();
            const bEl = document.getElementById('metric-bookings');
            const rEl = document.getElementById('metric-revenue');
            const oEl = document.getElementById('metric-occupancy');
            const fEl = document.getElementById('metric-flights');

            const totalBookings = stats.paidOrders || stats.totalOrders || 0;
            const rev = stats.totalRevenue || 0;
            const usedTickets = stats.usedTickets || 0;
            const totalTickets = stats.totalTickets || 0;
            const occupancy = totalTickets > 0 ? ((usedTickets / totalTickets) * 100).toFixed(1) : '85.4';

            if (bEl) bEl.textContent = Number(totalBookings).toLocaleString('vi-VN');
            if (rEl) rEl.textContent = (Number(rev) / 1000000).toFixed(1) + 'M';
            if (oEl) oEl.textContent = `${occupancy}%`;
            if (fEl) fEl.textContent = stats.activeFlights || adminFlights.length;
            return;
        }
    } catch (e) {
        console.warn('Metric loader using fallback:', e);
    }
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
                    ${displayDateTime(f.departTime)}
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
        `Giờ bay: ${displayDateTime(f.departTime)} - ${displayDateTime(f.arriveTime || '10:00')} | Loại tàu bay: ${f.aircraft || 'A320'}\n` +
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
    document.getElementById('ef-depart-date').value = flight.departDate || flight.departTime?.slice(0, 10) || '';
    document.getElementById('ef-depart-date').dispatchEvent(new Event('change'));
    document.getElementById('ef-depart-time').value = flight.departTime?.slice(-5) || '08:00';
    document.getElementById('ef-arrive-time').value = flight.arriveTime?.slice(-5) || '10:00';
    document.getElementById('ef-price').value = flight.basePrice ?? flight.price ?? 1450000;
    document.getElementById('ef-aircraft').value = flight.aircraft || (flight.total === 180 ? 'A321' : 'A320');
    document.getElementById('ef-status').value = flight.status || 'selling';

    openModal('modal-edit-flight');
}

function addFlightDay(date) {
    const [year, month, day] = date.split('-').map(Number);
    return new Date(Date.UTC(year, month - 1, day + 1)).toISOString().slice(0, 10);
}

async function adminDeleteFlight(flightNo) {
    const flight = adminFlights.find(f => f.flightNumber === flightNo);
    const code = flight?.flightCode || flightNo;
    if (confirm(`Bạn có chắc muốn xóa hoặc hủy chuyến bay ${flightNo}?`)) {
        try {
            const res = await fetch(`${API_BASE_URL}/admin/flights/${encodeURIComponent(code)}`, {
                method: 'DELETE'
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.message || 'Không thể xóa chuyến bay.');
            await loadAdminFlights();
            showToast('success', 'Đã xóa chuyến bay', data.message || `Chuyến bay ${flightNo} đã được xử lý.`);
        } catch (err) {
            adminFlights = adminFlights.filter(f => f.flightNumber !== flightNo);
            renderAdminFlightsTable(adminFlights);
            updateAdminMetrics();
            showToast('warning', 'Đã xóa cục bộ', err.message || `Chuyến bay ${flightNo} đã bị xóa.`);
        }
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
        document.getElementById('auth-buttons-user')?.classList.add('hidden');
        document.getElementById('auth-buttons-guest')?.classList.remove('hidden');
        const adminLink = document.getElementById('nav-admin');
        if (adminLink) adminLink.style.display = 'none';
        dropdown?.classList.remove('show');
        if (currentView === 'admin') switchView('home');
        showToast('info', 'Đã đăng xuất', 'Hẹn gặp lại bạn trên SkyGo!');
    });
}

function initProfileModal() {
    document.getElementById('close-profile')?.addEventListener('click', () => closeModal('modal-profile'));
    document.getElementById('close-my-bookings')?.addEventListener('click', () => closeModal('modal-my-bookings'));

    document.getElementById('profile-form')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        const newName = document.getElementById('prof-fullname').value.trim();
        const newPhone = document.getElementById('prof-phone').value.trim();
        const newPass = document.getElementById('prof-new-password').value;

        if (!newName) {
            showToast('error', 'Lỗi', 'Họ và tên không được để trống.');
            return;
        }

        try {
            const res = await fetch(`${API_BASE_URL}/profile`, {
                method: 'PUT', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ fullName: newName, phone: newPhone, newPassword: newPass || null })
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.message || 'Không thể cập nhật hồ sơ.');
            currentUser = { ...currentUser, name: data.fullName, phone: data.phone };
            localStorage.setItem(STORAGE_USER_KEY, JSON.stringify(currentUser));
            document.getElementById('user-display-name').textContent = currentUser.name.split(' ').slice(-1)[0];
            closeModal('modal-profile');
            showToast('success', 'Thành công', 'Hồ sơ cá nhân đã được cập nhật trong database.');
        } catch (err) { showToast('error', 'Cập nhật thất bại', err.message); }
    });
}

async function renderMyBookings() {
    const listEl = document.getElementById('my-bookings-list');
    if (!listEl) return;
    if (!currentUser) { listEl.innerHTML = '<p style="text-align:center;padding:24px">Vui lòng đăng nhập để xem các đơn đặt chỗ.</p>'; return; }
    listEl.innerHTML = '<p style="text-align:center;padding:24px">Đang tải dữ liệu từ database...</p>';
    let userBookings;
    try {
        const res = await fetch(`${API_BASE_URL}/bookings/my`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || 'Không thể tải lịch sử đặt vé.');
        userBookings = data.map(b => ({ ...b, route: `${b.origin || ''} → ${b.destination || ''}`, departDate: b.tickets?.[0]?.departDate || '', seat: b.seat || 'Chưa chọn' }));
    } catch (err) { listEl.innerHTML = `<p style="text-align:center;padding:24px;color:var(--error)">${err.message}</p>`; return; }

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
                    <i class="fa-regular fa-calendar"></i> ${displayDate(b.departDate)} &bull; <i class="fa-solid fa-chair"></i> Ghế: ${b.seat || 'Chưa chọn'}
                </span>
                <span style="font-size:13px;color:var(--text-muted);">
                    <i class="fa-regular fa-user"></i> Hành khách: ${b.passengerName}
                </span>
            </div>
            ${ticketList(b.tickets || [])}
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

// ============================================================
// 15. AIRPORT LOADER – tải danh sách sân bay từ API
// ============================================================

async function loadAirports() {
    try {
        const res = await fetch(`${API_BASE_URL}/airports`);
        if (!res.ok) return; // fallback to existing hardcoded options
        const airports = await res.json();
        const selectors = ['origin', 'destination', 'af-origin', 'af-destination', 'ef-origin', 'ef-destination'];
        selectors.forEach(id => {
            const el = document.getElementById(id);
            if (!el) return;
            const currentVal = el.value;
            // Keep first placeholder option if any
            const placeholder = el.querySelector('option[value=""]');
            el.innerHTML = '';
            if (placeholder) el.appendChild(placeholder);
            airports.forEach(a => {
                const opt = document.createElement('option');
                opt.value = a.code;
                opt.textContent = `${a.city} (${a.code}) – ${a.name}`;
                if (a.code === currentVal) opt.selected = true;
                el.appendChild(opt);
            });
        });

        // Update cityName map with API data
        airports.forEach(a => {
            cityNameMap[a.code] = a.city;
        });
    } catch(e) {
        console.warn('Airport loader: using fallback', e);
    }
}

const cityNameMap = { SGN: 'Hồ Chí Minh', HAN: 'Hà Nội', DAD: 'Đà Nẵng', PQC: 'Phú Quốc', CXR: 'Nha Trang', TBB: 'Tuy Hòa' };

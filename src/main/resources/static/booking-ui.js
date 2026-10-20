'use strict';

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[c]));
}
const money = value => `${Number(value).toLocaleString('vi-VN')} VND`;
const fareLabel = value => value === 'BUSINESS' ? 'Business (Thương gia)' : 'Economy (Phổ thông)';
let searchOptions = [];
let checkinTickets = [];
let checkinAccess = {};
let checkinSelectionRequest = 0;

function flightCards(flights, inbound = false) {
    searchOptions = flights;
    return flights.map((f, index) => `<div class="flight-card">
        <div class="flight-info"><div><strong>${escapeHtml(f.flightNumber)}</strong>
        <p>${escapeHtml(f.origin)} → ${escapeHtml(f.destination)}</p>
        <p>${displayDate(f.departDate)} · ${escapeHtml(f.departureTime)} – ${escapeHtml(f.arrivalTime)}</p></div></div>
        <div class="flight-price-col"><div>Giá từ ${money(f.price)}</div>
        ${f.fares.map((fare, option) => `<div class="fare-choice">
            <strong>${fareLabel(fare.fareClass)}</strong><br>${money(fare.price)} / hành khách (đã gồm thuế, phí)<br>
            Còn ${Number(fare.seatsAvailable)} chỗ<br>
            <button class="btn btn-primary btn-sm" onclick="chooseFare(${index},${option},${inbound})">Chọn ${inbound ? 'chiều về' : 'chiều đi'} · ${fareLabel(fare.fareClass)}</button>
        </div>`).join('')}</div></div>`).join('');
}

function chooseFare(index, option, inbound) {
    const f = searchOptions[index];
    const selected = {...f, ...f.fares[option]};
    if (inbound) handleSelectReturnFlight(selected);
    else handleSelectOutboundFlight(selected);
}

function ticketList(tickets, selectable = false) {
    const legs = [...new Set(tickets.map(t => t.flightCode))];
    return tickets.map((t, index) => `<div class="ticket-detail">
        <strong>${escapeHtml(t.passengerName)}</strong> · Vé #${Number(t.ticketId)}<br>
        ${legs.length === 2 ? (legs.indexOf(t.flightCode) === 0 ? 'Chiều đi · ' : 'Chiều về · ') : ''}${escapeHtml(t.flightNumber)} (${escapeHtml(t.flightCode)}) · ${escapeHtml(t.route)}<br>
        ${displayDate(t.departDate)} ${escapeHtml(t.departTime)} · ${fareLabel(t.fareClass)} · Ghế: ${escapeHtml(t.seat || 'Chọn khi check-in')}<br>
        ${t.dateOfBirth ? `Ngày sinh: ${displayDate(t.dateOfBirth)} · ` : ''}${money(t.price)}<br>
        Vé: ${escapeHtml(t.ticketStatus)} · ${escapeHtml(t.checkinReason)}
        ${selectable && t.checkinEligible ? `<button class="btn btn-primary btn-sm" onclick="selectCheckinTicket(${index})">Check-in vé này</button>` : ''}
        ${selectable && t.checkedIn ? `<button class="btn btn-outline btn-sm" onclick="showBoardingTicket(${index})">Xem thẻ lên máy bay</button>` : ''}
    </div>`).join('');
}

async function selectCheckinTicket(index) {
    const requestId = ++checkinSelectionRequest;
    activeCheckinRecord = null;
    activeCheckinSeat = null;
    try {
        const res = await fetch(`${API_BASE_URL}/checkin`, {method:'POST', headers:{'Content-Type':'application/json'},
            body: JSON.stringify({...checkinAccess, ticketId:checkinTickets[index].ticketId})});
        const data = await res.json();
        if (!res.ok) throw new Error(data.message);
        if (requestId !== checkinSelectionRequest) return;
        openCheckinSeatSelection(checkinAccess.pnr, data);
    } catch (err) {
        if (requestId !== checkinSelectionRequest) return;
        displayCheckinError(err.message || 'Không tải được ghế của vé đã chọn. Vui lòng tra cứu lại.');
    }
}

async function showBoardingTicket(index) {
    const requestId = ++checkinSelectionRequest;
    const ticketId = checkinTickets[index]?.ticketId;
    try {
        const res = await fetch(`${API_BASE_URL}/checkin`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(checkinAccess)});
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || 'Không tải được thẻ lên máy bay.');
        if (requestId !== checkinSelectionRequest) return;
        const ticket = data.tickets?.find(t => t.ticketId === ticketId);
        if (!ticket) throw new Error('Không tìm thấy vé được chọn trong đặt chỗ.');
        displayCheckinSuccess(data.pnr, ticket);
    } catch (err) { displayCheckinError(err.message || 'Không tải được thẻ lên máy bay. Vui lòng tra cứu lại.'); }
}

async function refreshCheckinTickets() {
    const res = await fetch(`${API_BASE_URL}/checkin`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(checkinAccess)});
    const data = await res.json();
    if (!res.ok) throw new Error(data.message);
    if (!Array.isArray(data.tickets)) throw new Error('Máy chủ chưa trả về danh sách vé. Vui lòng thử lại.');
    checkinTickets = data.tickets;
    const display = document.getElementById('checkin-result-display');
    display.classList.remove('hidden', 'error');
    display.innerHTML = `<strong>PNR ${escapeHtml(data.pnr)} · Chọn hành khách và chặng bay</strong>${ticketList(checkinTickets, true)}`;
}

function boardingPassHTML(ticket, requireCheckin = false) {
    const required = ['pnr', 'ticketId', 'passengerName', 'flightNumber', 'flightCode', 'origin', 'destination', 'departDate', 'departTime', 'fareClass'];
    if (!ticket || required.some(key => !ticket[key]) || !displayDate(ticket.departDate)) {
        throw new Error('Thông tin vé chưa đầy đủ để hiển thị. Vui lòng tải lại đặt chỗ.');
    }
    if (requireCheckin && (!ticket.checkedIn || !ticket.seat || !ticket.qrCode)) {
        throw new Error('Vé chưa có thông tin check-in hoặc thẻ lên máy bay. Vui lòng tra cứu lại.');
    }
    const field = (label, value) => `<div class="bp-field"><label>${label}</label><span>${escapeHtml(value)}</span></div>`;
    return `<article class="boarding-pass" data-ticket-id="${Number(ticket.ticketId)}" aria-label="${requireCheckin ? 'Thẻ lên máy bay' : 'Xác nhận vé'} ${escapeHtml(ticket.passengerName)}">
        <div class="bp-top">
            <div class="bp-airline"><div class="bp-airline-name"><i class="fa-solid fa-plane-departure"></i> SkyGo Airways</div><div class="bp-pnr-badge">${escapeHtml(ticket.pnr)}</div></div>
            <div class="bp-document-type">${requireCheckin ? 'THẺ LÊN MÁY BAY' : 'XÁC NHẬN VÉ'}</div>
            <div class="bp-route">
                <div class="bp-city"><div class="bp-city-code">${escapeHtml(ticket.origin)}</div><div class="bp-city-name">${escapeHtml(cityName(ticket.origin))}</div></div>
                <div class="bp-route-arrow"><hr><i class="fa-solid fa-plane"></i><hr></div>
                <div class="bp-city"><div class="bp-city-code">${escapeHtml(ticket.destination)}</div><div class="bp-city-name">${escapeHtml(cityName(ticket.destination))}</div></div>
            </div>
            <div class="bp-details">
                ${field('Hành khách', ticket.passengerName)}${field('Chuyến bay', ticket.flightNumber)}
                ${field('Ngày bay', displayDate(ticket.departDate))}${field('Giờ cất cánh', ticket.departTime)}
                ${field('Hạng vé', fareLabel(ticket.fareClass))}${field('Mã vé', ticket.ticketId)}
                ${field('Chuyến cụ thể', ticket.flightCode)}${field('Trạng thái', ticket.checkedIn ? 'Đã check-in' : ticket.ticketStatus)}
            </div>
        </div>
        <div class="bp-tear"><div class="bp-tear-circle"></div><hr class="bp-tear-line"><div class="bp-tear-circle"></div></div>
        <div class="bp-bottom"><div class="bp-stub-details">
            <div class="bp-stub-flight">${escapeHtml(ticket.flightNumber)}</div>
            <div class="bp-stub-info">${escapeHtml(ticket.passengerName)} · ${displayDate(ticket.departDate)} ${escapeHtml(ticket.departTime)}</div>
            <div class="bp-stub-seat">${ticket.checkedIn ? `GHẾ ${escapeHtml(ticket.seat)}` : 'Chọn ghế khi check-in'}</div>
        </div>${ticket.checkedIn ? `<div class="bp-code"><span>Mã thẻ lên máy bay</span><code>${escapeHtml(ticket.qrCode)}</code></div>` : ''}</div>
    </article>`;
}

function bookingSummaryHTML() {
    return [bookingState.flight, bookingState.returnFlight].filter(Boolean).map((f, i) =>
        `<div>${i ? 'Chiều về' : 'Chiều đi'}: ${escapeHtml(f.flightNumber)} · ${escapeHtml(f.origin)} → ${escapeHtml(f.destination)} · ${displayDate(f.departDate)} ${escapeHtml(f.departureTime)}<br>${fareLabel(f.fareClass)} · ${money(f.price)} / hành khách</div>`).join('');
}

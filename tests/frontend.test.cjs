// Run with: node tests/frontend.test.cjs (no external packages required).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

module.exports = (async () => {
    const root = path.resolve(__dirname, '..');
    const elements = new Map();
    class Element {
        constructor() {
            this.value = ''; this.innerHTML = ''; this.children = []; this.events = {};
            this.attrs = {}; this.style = {}; this.dataset = {}; this.min = ''; this.max = '';
            this.classList = {add(){}, remove(){}, toggle(){}};
        }
        append(...nodes) { this.children.push(...nodes); }
        before(node) { this.wrapper = node; }
        closest() { return null; }
        setAttribute(key, value) { this.attrs[key] = value; }
        hasAttribute(key) { return Object.hasOwn(this.attrs, key); }
        setCustomValidity(message) { this.validationMessage = message; }
        addEventListener(event, callback) { this.events[event] = callback; }
        dispatchEvent(event) { return this.events[event.type]?.(event); }
        querySelectorAll() { return []; }
        querySelector() { return new Element(); }
        contains() { return false; }
        focus() {}
    }
    const get = id => { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); };
    const context = vm.createContext({
        window: {fetch: async () => {throw Error('Unexpected request');}},
        document: {addEventListener(){}, querySelector(){return null;}, querySelectorAll(){return [];},
            getElementById:get, createElement:() => new Element()},
        localStorage:{getItem:() => null, setItem(){}},
        MutationObserver:class {observe(){}}, Event:class {constructor(type){this.type=type;}},
        Headers:class {}, URLSearchParams, setTimeout(){}, console,
    });
    for (const file of ['dates.js', 'booking-ui.js', 'app.js']) {
        vm.runInContext(fs.readFileSync(path.join(root, 'Frontend', file), 'utf8'), context, {filename:file});
        assert.equal(fs.readFileSync(path.join(root,'Frontend',file),'utf8'), fs.readFileSync(path.join(root,'src/main/resources/static',file),'utf8'));
    }
    const run = code => vm.runInContext(code, context);
    let passed = 0;
    const check = (title, fn) => { fn(); passed++; console.log('PASS '+title); };
    check('date-only conversion preserves 23 November and rejects invalid/leap dates', () => {
        assert.equal(run("parseDisplayDate('23/11/2005')"), '2005-11-23');
        assert.equal(run("displayDate('2005-11-23')"), '23/11/2005');
        for (const date of ['11/23/2005','31/02/2026','29/02/2025','1/2/2026']) assert.equal(run(`parseDisplayDate('${date}')`),'');
        assert.equal(run("parseDisplayDate('29/02/2024')"),'2024-02-29');
        assert.equal(run("displayDate('2005-11-23T00:00:00')"),'23/11/2005');
    });
    check('date entry shows dd/MM/yyyy, stores ISO and accepts calendar selection', () => {
        const iso = new Element(); iso.id = 'test-dob'; iso.value = '2005-11-23'; iso.type = 'date'; iso.attrs.required = '';
        context.inputRoot = {querySelectorAll:() => [iso]};
        run('enhanceDateInputs(inputRoot)');
        assert.equal(iso.type, 'hidden');
        const text = iso.wrapper.children[1];
        const picker = iso.wrapper.children[2];
        const calendar = iso.wrapper.children[3];
        assert.equal(picker.type,'button');
        assert.equal(iso.hidden,true);
        assert.equal(iso.style.display,'none');
        assert.equal(calendar.hidden,true);
        assert.equal(text.value, '23/11/2005');
        assert.equal(text.placeholder,'dd/MM/yyyy');
        text.value='31/02/2026'; text.events.input();
        assert.equal(iso.value,''); assert.ok(text.validationMessage);
        text.value='23/11/2005'; text.events.input();
        assert.equal(iso.value,'2005-11-23'); assert.equal(text.validationMessage,'');
        iso.value='2005-12-24'; iso.dispatchEvent({type:'change'});
        assert.equal(text.value,'24/12/2005'); assert.equal(iso.value,'2005-12-24');
        iso.max='2005-12-24'; text.value='25/12/2005'; text.events.input();
        assert.equal(iso.value,''); assert.ok(text.validationMessage);
    });
    const outbound = {flightCode:'OUT',flightNumber:'SG101',origin:'SGN',destination:'HAN',departDate:'2030-11-23',departureTime:'10:00',arrivalTime:'12:00',price:100,
        fares:[{fareClass:'ECONOMY',price:100,seatsAvailable:10},{fareClass:'BUSINESS',price:300,seatsAvailable:4}]};
    context.fixture = outbound;
    check('one result card contains both fare choices, prices and capacities', () => {
        const html = run('flightCards([fixture])');
        assert.equal((html.match(/class="flight-card"/g)||[]).length,1);
        assert.match(html,/Economy/); assert.match(html,/Business/);
        assert.match(html,/Còn 10 chỗ/); assert.match(html,/Còn 4 chỗ/);
        assert.match(html,/23\/11\/2030/);
    });
    check('roundtrip independently selects outbound Business and inbound Economy', () => {
        run('handleSelectOutboundFlight = f => globalThis.chosenOut=f; handleSelectReturnFlight = f => globalThis.chosenBack=f; chooseFare(0,1,false); chooseFare(0,0,true);');
        assert.equal(context.chosenOut.fareClass,'BUSINESS'); assert.equal(context.chosenOut.price,300);
        assert.equal(context.chosenBack.fareClass,'ECONOMY'); assert.equal(context.chosenBack.price,100);
    });
    check('two-passenger total includes selected fares exactly once without extra tax', () => {
        run('bookingState={flight:chosenOut,returnFlight:chosenBack,totalPassengers:2}; buildFareSummary();');
        assert.equal(run('bookingState.totalAmount'),800);
        assert.match(get('fare-summary').innerHTML,/Business/);
        assert.match(get('fare-summary').innerHTML,/Economy/);
    });
    check('passenger data carries the exact ISO birthday', () => {
        run('bookingState={passengers:{adults:1,children:0,infants:0}};');
        get('pax-0-lastname').value='Nguyen'; get('pax-0-firstname').value='An'; get('pax-0-dob').value='2005-11-23';
        assert.equal(run('collectPassengerData()[0].dateOfBirth'),'2005-11-23');
    });
    check('ticket list keeps two passengers across both legs with per-ticket actions', () => {
        context.ticketsFixture = [1,2,3,4].map((id) => ({ticketId:id, flightCode:id<=2?'OUT':'BACK',flightNumber:'SG101',
            passengerName:id%2?'NGUYEN AN':'TRAN BINH',route:'SGN → HAN',departDate:'2030-11-23',departTime:'10:00',
            fareClass:'BUSINESS',price:300,ticketStatus:'ISSUED',checkinEligible:true,checkinReason:'Có thể check-in'}));
        const html = run('ticketList(ticketsFixture,true)');
        assert.equal((html.match(/class="ticket-detail"/g)||[]).length,4);
        assert.match(html,/NGUYEN AN/); assert.match(html,/TRAN BINH/);
        assert.match(html,/Chiều đi/); assert.match(html,/Chiều về/);
        for (const index of [0,1,2,3]) assert.ok(html.includes(`selectCheckinTicket(${index})`));
        assert.equal(run("escapeHtml('<script>')"),'&lt;script&gt;');
    });
    const requests = [];
    context.fetch = async (url, options) => {
        requests.push({url, body:JSON.parse(options.body)});
        return {ok:true, json:async () => ({pnr:'ABC123',status:'PAID',totalAmount:777,tickets:context.ticketsFixture,availableSeats:['03A']})};
    };
    run("bookingState={flight:chosenOut,returnFlight:chosenBack,totalPassengers:1,passengerData:[{lastName:'NGUYEN',firstName:'AN',dateOfBirth:'2005-11-23'}],selectedSeats:[],extras:{},totalAmount:400}; showToast=()=>{}; goToStep=()=>{};");
    await context.processPayment();
    check('booking payload sends both flight keys and fares; confirmation uses server total', () => {
        assert.equal(requests[0].body.flightNumber,'OUT');
        assert.equal(requests[0].body.fareClass,'BUSINESS');
        assert.equal(requests[0].body.returnFareClass,'ECONOMY');
        assert.equal(requests[0].body.passengers[0].dateOfBirth,'2005-11-23');
        assert.equal(run('bookingState.totalAmount'),777);
    });
    run("checkinTickets=ticketsFixture; checkinAccess={pnr:'ABC123',lastName:'Nguyen'}; openCheckinSeatSelection=(p,r)=>{};");
    await context.selectCheckinTicket(3);
    check('checkin selection sends the chosen ticket with PNR and authorized surname', () => {
        assert.deepEqual(requests[1].body,{pnr:'ABC123',lastName:'Nguyen',ticketId:4});
    });
    context.document.querySelector = () => ({value:'roundtrip'});
    run('initSearchForm();');
    get('origin').value='SGN'; get('destination').value='HAN';
    get('depart-date').value='2030-11-23'; get('return-date').value='2030-11-22';
    const before = requests.length;
    await get('flight-search-form').events.submit({preventDefault(){}});
    check('return date before departure is rejected before any API request', () => assert.equal(requests.length,before));
    get('depart-date').value='2030-02-31';
    await get('flight-search-form').events.submit({preventDefault(){}});
    check('invalid departure date is rejected before any API request', () => assert.equal(requests.length,before));
    get('pax-0-dob').value='2999-11-23';
    run('bookingState={passengers:{adults:1,children:0,infants:0}};');
    check('future date of birth is rejected', () => assert.equal(run('validatePassengerForms()'),false));
    console.log(`${passed} frontend checks passed (DOM stub; no browser rendering).`);
    return passed;
})();

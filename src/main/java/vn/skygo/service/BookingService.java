package vn.skygo.service;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import vn.skygo.api.ApiException;
import vn.skygo.dto.Requests;
import vn.skygo.security.SessionService;
import java.math.BigDecimal;
import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;

@Service
public class BookingService {
    private final JdbcTemplate jdbc; private final SessionService sessions; private final SecureRandom random = new SecureRandom();
    public BookingService(JdbcTemplate jdbc, SessionService sessions) { this.jdbc=jdbc; this.sessions=sessions; }

    @Transactional
    public Map<String,Object> create(HttpServletRequest request, Requests.Booking req) {
        if(req.passengers().size()>9) throw new ApiException(HttpStatus.BAD_REQUEST,"Mỗi đơn chỉ tối đa 9 hành khách.");
        SessionService.Principal principal=sessions.optional(request).orElse(null);
        List<Map<String,Object>> flights=new ArrayList<>(); flights.add(flight(req.flightNumber())); if(req.returnFlightNumber()!=null&&!req.returnFlightNumber().isBlank()) flights.add(flight(req.returnFlightNumber()));
        for(Map<String,Object> flight:flights) { if(!"SCHEDULED".equals(flight.get("TrangThai")) && !"DELAYED".equals(flight.get("TrangThai"))) throw new ApiException(HttpStatus.CONFLICT,"Chuyến bay không còn mở bán."); }
        Requests.Passenger contact=req.passengers().get(0); String contactName=fullName(contact); String pnr=nextPnr(); LocalDateTime now=LocalDateTime.now();
        Long orderId=jdbc.queryForObject("INSERT INTO DON_DAT_VE(MaPNR,NgayDat,HanThanhToan,HoTenLienHe,EmailLienHe,SDTLienHe,TongTien,TrangThai,MaKhachHang) OUTPUT INSERTED.MaDonDatVe VALUES(?,?,?,?,?,?,?,?,?)",Long.class,pnr,Timestamp.valueOf(now),Timestamp.valueOf(now.plusMinutes(15)),contactName,principal==null?"guest@skygo.local":principal.email(),"",BigDecimal.ONE,"PENDING",principal==null?null:principal.customerId());
        BigDecimal total=BigDecimal.ZERO;
        for(Map<String,Object> f:flights) {
            Map<String,Object> fare=fare((String)f.get("MaChuyenBay")); BigDecimal base=(BigDecimal)fare.get("GiaCoBan"), tax=(BigDecimal)fare.get("ThuePhi");
            int available=jdbc.queryForObject("SELECT COUNT(*)-(SELECT COUNT(*) FROM VE_CHUYEN_BAY WHERE MaChuyenBay=? AND HangVe=? AND TrangThai IN ('RESERVED','ISSUED','USED')) FROM GHE_CHUYEN_BAY WHERE MaChuyenBay=? AND HangVe=?",Integer.class,f.get("MaChuyenBay"),fare.get("HangVe"),f.get("MaChuyenBay"),fare.get("HangVe"));
            if(available<req.passengers().size()) throw new ApiException(HttpStatus.CONFLICT,"Không đủ ghế trống cho chuyến bay đã chọn.");
            for(Requests.Passenger passenger:req.passengers()) { Long paxId=jdbc.queryForObject("INSERT INTO HANH_KHACH(HoTen,NgaySinh,GioiTinh,LoaiGiayTo,SoGiayTo,QuocTich) OUTPUT INSERTED.MaHanhKhach VALUES(?,?,?,?,?,?)",Long.class,fullName(passenger),java.sql.Date.valueOf(passenger.dateOfBirth()==null?LocalDate.of(1990,1,1):passenger.dateOfBirth()),gender(passenger.gender()),passenger.documentNumber()==null||passenger.documentNumber().isBlank()?null:"CCCD",emptyToNull(passenger.documentNumber()),"Viet Nam");
                jdbc.update("INSERT INTO VE_CHUYEN_BAY(MaDonDatVe,MaHanhKhach,MaChuyenBay,HangVe,GiaCoBanChot,ThuePhiChot,TrangThai) VALUES(?,?,?,?,?,?,?)",orderId,paxId,f.get("MaChuyenBay"),fare.get("HangVe"),base,tax,"RESERVED"); total=total.add(base).add(tax); }
        }
        jdbc.update("UPDATE DON_DAT_VE SET TongTien=?,TrangThai='PAID' WHERE MaDonDatVe=?",total,orderId);
        jdbc.update("UPDATE VE_CHUYEN_BAY SET TrangThai='ISSUED' WHERE MaDonDatVe=?",orderId);
        String paymentRef="SKY"+orderId+System.currentTimeMillis(); jdbc.update("INSERT INTO GIAO_DICH_TT(MaDonDatVe,SoTien,PhuongThucTT,TrangThaiTT,ThoiGianTao,ThoiGianTT,MaThamChieu) VALUES(?,?,?,?,?,?,?)",orderId,total,paymentMethod(req.paymentMethod()),"SUCCESS",Timestamp.valueOf(now),Timestamp.valueOf(LocalDateTime.now()),paymentRef);
        Map<String,Object> response=new LinkedHashMap<>(); response.put("orderId",orderId);response.put("pnr",pnr);response.put("status","PAID");response.put("totalAmount",total);response.put("passengerName",contactName);response.put("flightNumber",flights.get(0).get("SoHieuChuyen"));response.put("origin",flights.get(0).get("MaSanBayDi"));response.put("destination",flights.get(0).get("MaSanBayDen"));response.put("departDate",((Timestamp)flights.get(0).get("GioCatCanh")).toLocalDateTime().toLocalDate().toString()); response.put("departTime",((Timestamp)flights.get(0).get("GioCatCanh")).toLocalDateTime().toLocalTime().toString());response.put("route",flights.get(0).get("MaSanBayDi")+" → "+flights.get(0).get("MaSanBayDen")); return response;
    }
    public Map<String,Object> lookup(String pnr,String lastName) { List<Map<String,Object>> rows=tickets(pnr,lastName); if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"Không tìm thấy mã PNR hoặc họ hành khách không khớp."); return ticketResponse(rows.get(0)); }
    public List<Map<String,Object>> history(HttpServletRequest request) { SessionService.Principal p=sessions.requireUser(request);if(p.customerId()==null)throw new ApiException(HttpStatus.FORBIDDEN,"Tài khoản này không có lịch sử đặt vé."); return jdbc.queryForList("""
        SELECT d.MaDonDatVe AS orderId,d.MaPNR AS pnr,d.NgayDat AS createdAt,d.TongTien AS totalAmount,d.TrangThai AS status,
               x.HoTen AS passengerName,x.SoHieuChuyen AS flightNumber,x.MaSanBayDi AS origin,x.MaSanBayDen AS destination,
               x.GioCatCanh AS departure,x.SoGhe AS seat
        FROM DON_DAT_VE d OUTER APPLY (
          SELECT TOP 1 h.HoTen,cb.SoHieuChuyen,cb.MaSanBayDi,cb.MaSanBayDen,cb.GioCatCanh,g.SoGhe
          FROM VE_CHUYEN_BAY v JOIN HANH_KHACH h ON h.MaHanhKhach=v.MaHanhKhach JOIN CHUYEN_BAY cb ON cb.MaChuyenBay=v.MaChuyenBay
          LEFT JOIN CHECK_IN ci ON ci.MaVe=v.MaVe AND ci.TrangThai='CHECKED_IN' LEFT JOIN GHE_CHUYEN_BAY g ON g.MaGhe=ci.MaGhe
          WHERE v.MaDonDatVe=d.MaDonDatVe ORDER BY v.MaVe) x
        WHERE d.MaKhachHang=? ORDER BY d.NgayDat DESC,d.MaDonDatVe DESC""",p.customerId()); }
    @Transactional
    public void cancel(HttpServletRequest request,String pnr) { SessionService.Principal p=sessions.requireUser(request); int count=jdbc.update("UPDATE DON_DAT_VE SET TrangThai='CANCELLED' WHERE MaPNR=? AND MaKhachHang=? AND TrangThai IN ('PENDING','PAID')",pnr,p.customerId());if(count==0)throw new ApiException(HttpStatus.NOT_FOUND,"Không tìm thấy đơn có thể hủy.");jdbc.update("UPDATE VE_CHUYEN_BAY SET TrangThai='CANCELLED' WHERE MaDonDatVe=(SELECT MaDonDatVe FROM DON_DAT_VE WHERE MaPNR=?)",pnr); }
    public Map<String,Object> prepareCheckin(Requests.Checkin req) {
        List<Map<String,Object>> rows=tickets(req.pnr(),req.lastName());
        if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"Không tìm thấy mã PNR hoặc họ hành khách không khớp.");
        Map<String,Object> ticket=rows.get(0);
        if(!"ISSUED".equals(ticket.get("TrangThaiVe")))throw new ApiException(HttpStatus.CONFLICT,"Vé chưa thanh toán hoặc đã bị hủy, không thể check-in.");
        LocalDateTime departure=((Timestamp)ticket.get("GioCatCanh")).toLocalDateTime();
        if(LocalDateTime.now().isAfter(departure.plusHours(2)))throw new ApiException(HttpStatus.CONFLICT,"Chuyến bay đã cất cánh, không thể làm thủ tục.");
        Map<String,Object> response=ticketResponse(ticket);
        response.put("unavailableSeats",jdbc.queryForList("SELECT g.SoGhe FROM CHECK_IN ci JOIN GHE_CHUYEN_BAY g ON g.MaGhe=ci.MaGhe WHERE g.MaChuyenBay=? AND ci.TrangThai='CHECKED_IN'",String.class,ticket.get("MaChuyenBay")));
        return response;
    }
    @Transactional
    public Map<String,Object> confirmCheckin(Requests.CheckinConfirm req) {
        List<Map<String,Object>> rows=tickets(req.pnr(),req.lastName());
        if(rows.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"Không tìm thấy mã PNR hoặc họ hành khách không khớp.");
        Map<String,Object> rawTicket=rows.get(0);
        String flightCode = (String)rawTicket.get("MaChuyenBay");
        String seatName = req.seat().toUpperCase().trim();
        Long seatId = jdbc.query("SELECT MaGhe FROM GHE_CHUYEN_BAY WHERE MaChuyenBay=? AND (SoGhe=? OR SoGhe=?)",
                rs -> rs.next() ? rs.getLong(1) : null, flightCode, seatName, seatName.replaceFirst("^0", ""));
        if (seatId == null) throw new ApiException(HttpStatus.BAD_REQUEST,"Ghế không tồn tại trên chuyến bay này.");
        try {
            jdbc.update("INSERT INTO CHECK_IN(MaVe,MaGhe,ThoiGian,TrangThai,MaQR_BP,MaTK) VALUES(?,?,?,?,?,?)",
                    rawTicket.get("MaVe"), seatId, Timestamp.valueOf(LocalDateTime.now()), "CHECKED_IN", "BP-"+UUID.randomUUID(), null);
        } catch(DataIntegrityViolationException ex) {
            throw new ApiException(HttpStatus.CONFLICT, "Ghế này vừa được hành khách khác chọn.");
        }
        jdbc.update("UPDATE VE_CHUYEN_BAY SET TrangThai='USED' WHERE MaVe=?", rawTicket.get("MaVe"));
        Map<String,Object> result = ticketResponse(rawTicket);
        result.put("seat", seatName);
        result.put("status", "CHECKED_IN");
        result.put("gate", "B12");
        return result;
    }
    public Map<String,Object> adminStats() {
        Map<String,Object> stats = new LinkedHashMap<>();
        // Total bookings/orders
        Map<String,Object> bookingRow = jdbc.queryForMap("SELECT COUNT(*) AS totalOrders, SUM(CASE WHEN TrangThai='PAID' THEN 1 ELSE 0 END) AS paidOrders, SUM(CASE WHEN TrangThai='CANCELLED' THEN 1 ELSE 0 END) AS cancelledOrders, ISNULL(SUM(CASE WHEN TrangThai='PAID' THEN TongTien ELSE 0 END),0) AS totalRevenue FROM DON_DAT_VE");
        stats.put("totalOrders", bookingRow.get("totalOrders"));
        stats.put("paidOrders", bookingRow.get("paidOrders"));
        stats.put("cancelledOrders", bookingRow.get("cancelledOrders"));
        stats.put("totalRevenue", bookingRow.get("totalRevenue"));
        // Total flights/seats
        Map<String,Object> flightRow = jdbc.queryForMap("SELECT COUNT(*) AS totalFlights, SUM(CASE WHEN TrangThai='SCHEDULED' THEN 1 ELSE 0 END) AS activeFlights FROM CHUYEN_BAY");
        stats.put("totalFlights", flightRow.get("totalFlights"));
        stats.put("activeFlights", flightRow.get("activeFlights"));
        // Total customers/users
        Map<String,Object> userRow = jdbc.queryForMap("SELECT COUNT(*) AS totalCustomers FROM KHACH_HANG");
        stats.put("totalCustomers", userRow.get("totalCustomers"));
        // Total tickets
        Map<String,Object> ticketRow = jdbc.queryForMap("SELECT COUNT(*) AS totalTickets, SUM(CASE WHEN TrangThai='USED' THEN 1 ELSE 0 END) AS usedTickets FROM VE_CHUYEN_BAY");
        stats.put("totalTickets", ticketRow.get("totalTickets"));
        stats.put("usedTickets", ticketRow.get("usedTickets"));
        return stats;
    }
    private Map<String,Object> flight(String code){List<Map<String,Object>> r=jdbc.queryForList("SELECT MaChuyenBay,SoHieuChuyen,MaSanBayDi,MaSanBayDen,GioCatCanh,TrangThai FROM CHUYEN_BAY WHERE MaChuyenBay=? OR SoHieuChuyen=?",code,code);if(r.isEmpty())throw new ApiException(HttpStatus.NOT_FOUND,"Không tìm thấy chuyến bay.");return r.get(0);}
    private Map<String,Object> fare(String flightCode){List<Map<String,Object>> r=jdbc.queryForList("SELECT TOP 1 HangVe,GiaCoBan,ThuePhi FROM HANG_VE_CHUYEN_BAY WHERE MaChuyenBay=? AND TrangThai=1 ORDER BY CASE HangVe WHEN 'ECONOMY' THEN 0 ELSE 1 END",flightCode);if(r.isEmpty())throw new ApiException(HttpStatus.CONFLICT,"Chuyến bay không còn hạng vé mở bán.");return r.get(0);}
    private List<Map<String,Object>> tickets(String pnr,String lastName){return jdbc.queryForList("SELECT TOP 20 v.MaVe,v.HangVe,v.TrangThai TrangThaiVe,cb.MaChuyenBay,cb.SoHieuChuyen,cb.MaSanBayDi,cb.MaSanBayDen,cb.GioCatCanh,d.MaPNR,d.TrangThai TrangThaiDon,h.HoTen,ci.MaGhe,g.SoGhe FROM DON_DAT_VE d JOIN VE_CHUYEN_BAY v ON v.MaDonDatVe=d.MaDonDatVe JOIN HANH_KHACH h ON h.MaHanhKhach=v.MaHanhKhach JOIN CHUYEN_BAY cb ON cb.MaChuyenBay=v.MaChuyenBay LEFT JOIN CHECK_IN ci ON ci.MaVe=v.MaVe AND ci.TrangThai='CHECKED_IN' LEFT JOIN GHE_CHUYEN_BAY g ON g.MaGhe=ci.MaGhe WHERE d.MaPNR=? AND UPPER(h.HoTen) LIKE ? ORDER BY v.MaVe",pnr.toUpperCase(),"%"+lastName.trim().toUpperCase()+"%");}
    private Map<String,Object> ticketResponse(Map<String,Object> t){Timestamp ts=(Timestamp)t.get("GioCatCanh");LocalDateTime d=ts.toLocalDateTime();Map<String,Object> r=new LinkedHashMap<>();r.put("pnr",t.get("MaPNR"));r.put("status",t.get("TrangThaiDon"));r.put("passengerName",t.get("HoTen"));r.put("flightNumber",t.get("SoHieuChuyen"));r.put("flightCode",t.get("MaChuyenBay"));r.put("fareClass",t.get("HangVe"));r.put("origin",t.get("MaSanBayDi"));r.put("destination",t.get("MaSanBayDen"));r.put("route",t.get("MaSanBayDi")+" → "+t.get("MaSanBayDen"));r.put("departDate",d.toLocalDate().toString());r.put("departTime",d.toLocalTime().toString());r.put("seat",t.get("SoGhe"));r.put("ticketId",t.get("MaVe"));return r;}
    private String nextPnr(){String alphabet="ABCDEFGHJKLMNPQRSTUVWXYZ0123456789";for(int attempt=0;attempt<10;attempt++){StringBuilder b=new StringBuilder(6);for(int i=0;i<6;i++)b.append(alphabet.charAt(random.nextInt(alphabet.length())));String x=b.toString();if(jdbc.queryForObject("SELECT COUNT(*) FROM DON_DAT_VE WHERE MaPNR=?",Integer.class,x)==0)return x;}throw new ApiException(HttpStatus.CONFLICT,"Không thể tạo mã PNR, vui lòng thử lại.");}
    private String fullName(Requests.Passenger p){return (p.lastName().trim()+" "+p.firstName().trim()).toUpperCase();} private String gender(String g){if(g==null)return null;return g.equalsIgnoreCase("F")||g.equalsIgnoreCase("FEMALE")?"FEMALE":g.equalsIgnoreCase("M")||g.equalsIgnoreCase("MALE")?"MALE":"OTHER";} private String emptyToNull(String s){return s==null||s.isBlank()?null:s.trim();} private String paymentMethod(String m){return m==null?"VIETQR":switch(m.toLowerCase()){case "visa"->"VISA";case "domestic"->"ATM";default->"VIETQR";};}
}

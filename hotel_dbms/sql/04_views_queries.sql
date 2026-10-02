-- =====================================================================
--  04_views_queries.sql  -  Views + demonstration queries
-- =====================================================================
USE hotel_db;

-- =====================================================================
--  PART 1 : VIEWS
-- =====================================================================
CREATE OR REPLACE VIEW v_reservation_details AS
SELECT r.reservation_id,
       CONCAT(g.first_name,' ',g.last_name) AS guest_name,
       g.phone, rm.room_number, t.type_name,
       r.check_in_date, r.check_out_date,
       DATEDIFF(r.check_out_date, r.check_in_date) AS nights,
       r.num_guests, r.status, r.total_amount AS room_charges,
       s.full_name AS booked_by
  FROM reservations r
  JOIN guests g     ON g.guest_id = r.guest_id
  JOIN rooms rm     ON rm.room_id = r.room_id
  JOIN room_types t ON t.type_id  = rm.type_id
  JOIN staff s      ON s.staff_id = r.staff_id;

CREATE OR REPLACE VIEW v_current_guests AS
SELECT reservation_id, guest_name, phone, room_number, type_name,
       check_in_date, check_out_date
  FROM v_reservation_details
 WHERE status = 'Checked-In';

CREATE OR REPLACE VIEW v_room_status_today AS
SELECT rm.room_number, t.type_name, rm.floor_no, rm.status AS room_status,
       (SELECT COUNT(*) FROM reservations x
         WHERE x.room_id = rm.room_id AND x.status = 'Booked'
           AND x.check_in_date >= CURDATE()) AS upcoming_bookings
  FROM rooms rm JOIN room_types t ON t.type_id = rm.type_id;

CREATE OR REPLACE VIEW v_bill_summary AS
SELECT r.reservation_id,
       CONCAT(g.first_name,' ',g.last_name) AS guest_name,
       r.status,
       r.total_amount                            AS room_charges,
       IFNULL(sv.srv,0)                          AS service_charges,
       fn_bill_total(r.reservation_id)           AS grand_total,
       fn_amount_paid(r.reservation_id)          AS amount_paid,
       fn_bill_total(r.reservation_id) - fn_amount_paid(r.reservation_id) AS balance_due
  FROM reservations r
  JOIN guests g ON g.guest_id = r.guest_id
  LEFT JOIN (SELECT reservation_id, SUM(quantity*unit_price) AS srv
               FROM reservation_services GROUP BY reservation_id) sv
         ON sv.reservation_id = r.reservation_id
 WHERE r.status <> 'Cancelled';

CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT DATE_FORMAT(payment_date,'%Y-%m') AS month,
       COUNT(*)      AS payments,
       SUM(amount)   AS revenue
  FROM payments
 GROUP BY DATE_FORMAT(payment_date,'%Y-%m');

-- =====================================================================
--  PART 2 : QUERIES
-- =====================================================================

-- Q1  INNER JOIN: all reservations with guest, room and type
SELECT * FROM v_reservation_details ORDER BY check_in_date DESC;

-- Q2  Rooms free for the next 3 nights (procedure)
CALL sp_available_rooms(CURDATE() + INTERVAL 1 DAY, CURDATE() + INTERVAL 4 DAY, NULL);

-- Q3  LEFT JOIN: guests who have never booked
SELECT g.guest_id, g.first_name, g.last_name
  FROM guests g
  LEFT JOIN reservations r ON r.guest_id = g.guest_id
 WHERE r.reservation_id IS NULL;

-- Q4  GROUP BY + HAVING: guests with more than one completed stay
SELECT g.guest_id, CONCAT(g.first_name,' ',g.last_name) AS guest, COUNT(*) AS stays
  FROM guests g JOIN reservations r ON r.guest_id = g.guest_id
 WHERE r.status = 'Checked-Out'
 GROUP BY g.guest_id, guest
HAVING COUNT(*) > 1;

-- Q5  Revenue per room type (payments received)
SELECT t.type_name, COUNT(DISTINCT r.reservation_id) AS stays, SUM(p.amount) AS revenue
  FROM payments p
  JOIN reservations r ON r.reservation_id = p.reservation_id
  JOIN rooms rm       ON rm.room_id = r.room_id
  JOIN room_types t   ON t.type_id = rm.type_id
 GROUP BY t.type_name
 ORDER BY revenue DESC;

-- Q6  Monthly revenue (view)
SELECT * FROM v_monthly_revenue ORDER BY month;

-- Q7  Subquery: reservations costing more than the average room charge
SELECT reservation_id, guest_name, room_charges
  FROM v_reservation_details
 WHERE room_charges > (SELECT AVG(total_amount) FROM reservations WHERE status <> 'Cancelled');

-- Q8  Correlated subquery: each guest's most expensive stay
SELECT r.guest_id, r.reservation_id, r.total_amount
  FROM reservations r
 WHERE r.total_amount = (SELECT MAX(r2.total_amount) FROM reservations r2
                          WHERE r2.guest_id = r.guest_id AND r2.status <> 'Cancelled');

-- Q9  EXISTS: guests who ordered a Spa Session
SELECT DISTINCT g.guest_id, g.first_name, g.last_name
  FROM guests g
 WHERE EXISTS (SELECT 1 FROM reservations r
                 JOIN reservation_services rs ON rs.reservation_id = r.reservation_id
                 JOIN services s ON s.service_id = rs.service_id
                WHERE r.guest_id = g.guest_id AND s.service_name = 'Spa Session');

-- Q10 IN subquery: rooms that have never been booked
SELECT room_number FROM rooms
 WHERE room_id NOT IN (SELECT DISTINCT room_id FROM reservations);

-- Q11 Window function: rank guests by total spend
SELECT guest_name, SUM(grand_total) AS total_spend,
       RANK() OVER (ORDER BY SUM(grand_total) DESC) AS spend_rank
  FROM v_bill_summary
 WHERE status = 'Checked-Out'
 GROUP BY guest_name;

-- Q12 Window function: running revenue total
SELECT DATE(payment_date) AS pay_date, SUM(amount) AS daily_revenue,
       SUM(SUM(amount)) OVER (ORDER BY DATE(payment_date)) AS running_total
  FROM payments
 GROUP BY DATE(payment_date);

-- Q13 CTE: rooms ranked by revenue inside each room type
WITH room_rev AS (
    SELECT rm.room_number, rm.type_id, SUM(r.total_amount) AS revenue
      FROM reservations r JOIN rooms rm ON rm.room_id = r.room_id
     WHERE r.status IN ('Checked-In','Checked-Out')
     GROUP BY rm.room_number, rm.type_id
)
SELECT t.type_name, rr.room_number, rr.revenue,
       DENSE_RANK() OVER (PARTITION BY rr.type_id ORDER BY rr.revenue DESC) AS rank_in_type
  FROM room_rev rr JOIN room_types t ON t.type_id = rr.type_id;

-- Q14 Average rating per room type
SELECT t.type_name, ROUND(AVG(v.rating),2) AS avg_rating, COUNT(*) AS reviews
  FROM reviews v
  JOIN reservations r ON r.reservation_id = v.reservation_id
  JOIN rooms rm       ON rm.room_id = r.room_id
  JOIN room_types t   ON t.type_id = rm.type_id
 GROUP BY t.type_name
 ORDER BY avg_rating DESC;

-- Q15 Most popular services
SELECT s.service_name, SUM(rs.quantity) AS units_sold, SUM(rs.quantity*rs.unit_price) AS income
  FROM reservation_services rs JOIN services s ON s.service_id = rs.service_id
 GROUP BY s.service_name
 ORDER BY income DESC;

-- Q16 Outstanding balances (view)
SELECT * FROM v_bill_summary WHERE balance_due > 0 ORDER BY balance_due DESC;

-- Q17 Currently in-house guests (view)
SELECT * FROM v_current_guests;

-- Q18 Arrivals and departures today (UNION)
SELECT 'Arrival' AS movement, reservation_id, guest_name, room_number
  FROM v_reservation_details WHERE check_in_date = CURDATE() AND status IN ('Booked','Checked-In')
UNION ALL
SELECT 'Departure', reservation_id, guest_name, room_number
  FROM v_reservation_details WHERE check_out_date = CURDATE() AND status = 'Checked-In';

-- Q19 CASE: booking value category
SELECT reservation_id, guest_name, room_charges,
       CASE WHEN room_charges >= 30000 THEN 'Premium'
            WHEN room_charges >= 10000 THEN 'Standard'
            ELSE 'Budget' END AS category
  FROM v_reservation_details WHERE status <> 'Cancelled';

-- Q20 Occupancy by room type today (cursor procedure)
CALL sp_occupancy_by_type(CURDATE());

-- Q21 Bookings made per receptionist
SELECT s.full_name, COUNT(*) AS bookings, SUM(r.total_amount) AS value_booked
  FROM reservations r JOIN staff s ON s.staff_id = r.staff_id
 GROUP BY s.full_name ORDER BY bookings DESC;

-- Q22 Cancellation rate
SELECT ROUND(100 * SUM(status = 'Cancelled') / COUNT(*), 2) AS cancellation_pct FROM reservations;

-- Q23 Audit trail
SELECT * FROM audit_log ORDER BY log_id DESC LIMIT 20;

-- =====================================================================
--  PART 3 : TRIGGER / TRANSACTION DEMOS
--  (each statement marked "FAILS" is EXPECTED to raise an error)
-- =====================================================================

-- D1  Double booking blocked by trg_res_bi                      -> FAILS
-- CALL sp_make_reservation(1, 4, 2, CURDATE()+INTERVAL 1 DAY, CURDATE()+INTERVAL 3 DAY, 2, @id);

-- D2  Too many guests for the room type                         -> FAILS
-- CALL sp_make_reservation(1, 1, 2, CURDATE()+INTERVAL 30 DAY, CURDATE()+INTERVAL 32 DAY, 4, @id);

-- D3  Successful booking, then bill
-- CALL sp_make_reservation(1, 1, 2, CURDATE()+INTERVAL 30 DAY, CURDATE()+INTERVAL 32 DAY, 2, @id);
-- SELECT @id;  CALL sp_generate_bill(@id);

-- D4  Check-out with a balance due                              -> FAILS
-- CALL sp_check_out(11);

-- D5  Over-payment blocked                                      -> FAILS
-- CALL sp_record_payment(14, 999999, 'Cash');

-- D6  Review before check-out                                   -> FAILS
-- INSERT INTO reviews (reservation_id, rating) VALUES (11, 5);

-- D7  Settle bill, then check out (room becomes Available again)
-- SELECT balance_due FROM v_bill_summary WHERE reservation_id = 11;
-- CALL sp_record_payment(11, <balance_due>, 'Card');
-- CALL sp_check_out(11);
-- SELECT room_number, status FROM rooms WHERE room_number = '104';

-- D8  Illegal status change on a closed reservation             -> FAILS
-- UPDATE reservations SET status = 'Booked' WHERE reservation_id = 1;

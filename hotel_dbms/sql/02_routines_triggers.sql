-- =====================================================================
--  02_routines_triggers.sql
--  Stored functions, procedures, triggers and a scheduled event.
--  Run AFTER 01_schema.sql.   (GST is fixed at 12 %.)
-- =====================================================================
USE hotel_db;
DELIMITER $$

-- =====================================================================
--  A. STORED FUNCTIONS
-- =====================================================================

-- A1. TRUE when the room has NO active booking overlapping [p_in, p_out).
--     Two stays overlap when  new_in < old_out  AND  new_out > old_in.
--     p_exclude lets an UPDATE ignore the reservation being edited.
DROP FUNCTION IF EXISTS fn_room_is_free$$
CREATE FUNCTION fn_room_is_free(p_room INT UNSIGNED, p_in DATE, p_out DATE, p_exclude INT UNSIGNED)
RETURNS TINYINT(1)
READS SQL DATA
BEGIN
    DECLARE v_clash INT DEFAULT 0;
    SELECT COUNT(*) INTO v_clash
      FROM reservations
     WHERE room_id = p_room
       AND status IN ('Booked','Checked-In')
       AND reservation_id <> p_exclude
       AND p_in  < check_out_date
       AND p_out > check_in_date;
    RETURN (v_clash = 0);
END$$

-- A2. Grand total of a reservation = (room + services) + 12 % GST
DROP FUNCTION IF EXISTS fn_bill_total$$
CREATE FUNCTION fn_bill_total(p_res INT UNSIGNED)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_room DECIMAL(12,2) DEFAULT 0;
    DECLARE v_srv  DECIMAL(12,2) DEFAULT 0;
    SELECT IFNULL(total_amount,0) INTO v_room
      FROM reservations WHERE reservation_id = p_res;
    SELECT IFNULL(SUM(quantity * unit_price),0) INTO v_srv
      FROM reservation_services WHERE reservation_id = p_res;
    RETURN ROUND((v_room + v_srv) * 1.12, 2);
END$$

-- A3. Total amount paid so far
DROP FUNCTION IF EXISTS fn_amount_paid$$
CREATE FUNCTION fn_amount_paid(p_res INT UNSIGNED)
RETURNS DECIMAL(12,2)
READS SQL DATA
BEGIN
    DECLARE v_paid DECIMAL(12,2) DEFAULT 0;
    SELECT IFNULL(SUM(amount),0) INTO v_paid
      FROM payments WHERE reservation_id = p_res;
    RETURN v_paid;
END$$

-- =====================================================================
--  B. TRIGGERS
-- =====================================================================

-- B1. Validate a new reservation, prevent double booking, price the stay.
DROP TRIGGER IF EXISTS trg_res_bi$$
CREATE TRIGGER trg_res_bi BEFORE INSERT ON reservations
FOR EACH ROW
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_cap   TINYINT UNSIGNED;

    SELECT t.base_price, t.max_occupancy INTO v_price, v_cap
      FROM rooms r JOIN room_types t ON t.type_id = r.type_id
     WHERE r.room_id = NEW.room_id;

    IF NEW.num_guests > v_cap THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Guest count exceeds the maximum occupancy of this room type';
    END IF;

    IF NEW.status IN ('Booked','Checked-In')
       AND NOT fn_room_is_free(NEW.room_id, NEW.check_in_date, NEW.check_out_date, 0) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room is already booked for the selected dates';
    END IF;

    SET NEW.total_amount = DATEDIFF(NEW.check_out_date, NEW.check_in_date) * v_price;
END$$

-- B2. Enforce the status life-cycle and re-check availability on edits.
DROP TRIGGER IF EXISTS trg_res_bu$$
CREATE TRIGGER trg_res_bu BEFORE UPDATE ON reservations
FOR EACH ROW
BEGIN
    DECLARE v_price DECIMAL(10,2);

    IF NEW.status <> OLD.status THEN
        IF OLD.status IN ('Checked-Out','Cancelled') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A closed reservation cannot change status';
        ELSEIF OLD.status = 'Booked' AND NEW.status = 'Checked-Out' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Guest must check in before checking out';
        ELSEIF OLD.status = 'Checked-In' AND NEW.status IN ('Booked','Cancelled') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A checked-in reservation cannot be cancelled or reverted';
        END IF;
    END IF;

    IF NEW.room_id <> OLD.room_id
       OR NEW.check_in_date <> OLD.check_in_date
       OR NEW.check_out_date <> OLD.check_out_date THEN

        IF NEW.status IN ('Booked','Checked-In')
           AND NOT fn_room_is_free(NEW.room_id, NEW.check_in_date, NEW.check_out_date, OLD.reservation_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room is already booked for the selected dates';
        END IF;

        SELECT t.base_price INTO v_price
          FROM rooms r JOIN room_types t ON t.type_id = r.type_id
         WHERE r.room_id = NEW.room_id;
        SET NEW.total_amount = DATEDIFF(NEW.check_out_date, NEW.check_in_date) * v_price;
    END IF;
END$$

-- B3. Audit new reservations
DROP TRIGGER IF EXISTS trg_res_ai$$
CREATE TRIGGER trg_res_ai AFTER INSERT ON reservations
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, details, logged_by)
    VALUES ('reservations', 'INSERT', NEW.reservation_id,
            CONCAT('Room ', NEW.room_id, ' booked ', NEW.check_in_date, ' to ', NEW.check_out_date),
            CURRENT_USER());
END$$

-- B4. Keep rooms.status in sync with reservation status and audit changes.
DROP TRIGGER IF EXISTS trg_res_au$$
CREATE TRIGGER trg_res_au AFTER UPDATE ON reservations
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        IF NEW.status = 'Checked-In' THEN
            UPDATE rooms SET status = 'Occupied'  WHERE room_id = NEW.room_id;
        ELSEIF NEW.status = 'Checked-Out' THEN
            UPDATE rooms SET status = 'Available' WHERE room_id = NEW.room_id;
        END IF;

        INSERT INTO audit_log (table_name, action, record_id, details, logged_by)
        VALUES ('reservations', 'STATUS', NEW.reservation_id,
                CONCAT(OLD.status, ' -> ', NEW.status), CURRENT_USER());
    END IF;
END$$

-- B5. Payment rules: no payment on cancelled bookings, no over-payment.
DROP TRIGGER IF EXISTS trg_pay_bi$$
CREATE TRIGGER trg_pay_bi BEFORE INSERT ON payments
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);

    SELECT status INTO v_status FROM reservations WHERE reservation_id = NEW.reservation_id;

    IF v_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot accept payment for a cancelled reservation';
    END IF;

    IF fn_amount_paid(NEW.reservation_id) + NEW.amount > fn_bill_total(NEW.reservation_id) + 0.01 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment exceeds the outstanding bill amount';
    END IF;
END$$

-- B6. Snapshot the service price so later price changes do not alter old bills.
DROP TRIGGER IF EXISTS trg_rs_bi$$
CREATE TRIGGER trg_rs_bi BEFORE INSERT ON reservation_services
FOR EACH ROW
BEGIN
    SET NEW.unit_price = (SELECT price FROM services WHERE service_id = NEW.service_id);
END$$

-- B7. Only guests who have completed their stay may leave a review.
DROP TRIGGER IF EXISTS trg_rev_bi$$
CREATE TRIGGER trg_rev_bi BEFORE INSERT ON reviews
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    SELECT status INTO v_status FROM reservations WHERE reservation_id = NEW.reservation_id;
    IF v_status IS NULL OR v_status <> 'Checked-Out' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reviews are allowed only after check-out';
    END IF;
END$$

-- =====================================================================
--  C. STORED PROCEDURES  (each business operation is one ACID transaction)
-- =====================================================================

-- C1. Find rooms free for a date range (optionally of one type)
DROP PROCEDURE IF EXISTS sp_available_rooms$$
CREATE PROCEDURE sp_available_rooms(IN p_in DATE, IN p_out DATE, IN p_type TINYINT UNSIGNED)
BEGIN
    IF p_out <= p_in THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Check-out date must be after check-in date';
    END IF;

    SELECT r.room_id, r.room_number, t.type_name, r.floor_no,
           t.max_occupancy, t.base_price,
           DATEDIFF(p_out, p_in) * t.base_price AS estimated_room_cost
      FROM rooms r
      JOIN room_types t ON t.type_id = r.type_id
     WHERE r.status <> 'Maintenance'
       AND (p_type IS NULL OR r.type_id = p_type)
       AND NOT EXISTS (SELECT 1 FROM reservations x
                        WHERE x.room_id = r.room_id
                          AND x.status IN ('Booked','Checked-In')
                          AND p_in  < x.check_out_date
                          AND p_out > x.check_in_date)
     ORDER BY t.base_price, r.room_number;
END$$

-- C2. Create a reservation.  The room row is locked (FOR UPDATE) so two
--     receptionists cannot book the same room at the same moment.
DROP PROCEDURE IF EXISTS sp_make_reservation$$
CREATE PROCEDURE sp_make_reservation(
    IN  p_guest INT UNSIGNED, IN p_room INT UNSIGNED, IN p_staff INT UNSIGNED,
    IN  p_in DATE, IN p_out DATE, IN p_num TINYINT UNSIGNED,
    OUT p_res_id INT UNSIGNED)
BEGIN
    DECLARE v_lock INT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF p_in < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Check-in date cannot be in the past';
    END IF;

    SELECT room_id INTO v_lock FROM rooms WHERE room_id = p_room FOR UPDATE;
    IF v_lock IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room does not exist';
    END IF;

    INSERT INTO reservations (guest_id, room_id, staff_id, check_in_date, check_out_date, num_guests, status)
    VALUES (p_guest, p_room, p_staff, p_in, p_out, p_num, 'Booked');

    SET p_res_id = LAST_INSERT_ID();
    COMMIT;
END$$

-- C3. Check-in
DROP PROCEDURE IF EXISTS sp_check_in$$
CREATE PROCEDURE sp_check_in(IN p_res INT UNSIGNED)
BEGIN
    DECLARE v_status  VARCHAR(20);
    DECLARE v_in      DATE;
    DECLARE v_room    INT UNSIGNED;
    DECLARE v_rstatus VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status, check_in_date, room_id INTO v_status, v_in, v_room
      FROM reservations WHERE reservation_id = p_res FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reservation not found';
    END IF;
    IF v_status <> 'Booked' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only reservations in Booked status can be checked in';
    END IF;
    IF CURDATE() < v_in THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Too early: the check-in date has not arrived yet';
    END IF;

    SELECT status INTO v_rstatus FROM rooms WHERE room_id = v_room FOR UPDATE;
    IF v_rstatus <> 'Available' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room is currently occupied or under maintenance';
    END IF;

    UPDATE reservations
       SET status = 'Checked-In', actual_check_in = NOW()
     WHERE reservation_id = p_res;           -- trigger marks the room Occupied
    COMMIT;
END$$

-- C4. Add a service (food, laundry ...) to a checked-in stay
DROP PROCEDURE IF EXISTS sp_add_service$$
CREATE PROCEDURE sp_add_service(IN p_res INT UNSIGNED, IN p_service INT UNSIGNED, IN p_qty SMALLINT UNSIGNED)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT status INTO v_status FROM reservations WHERE reservation_id = p_res FOR UPDATE;
    IF v_status IS NULL OR v_status <> 'Checked-In' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Services can only be added to a checked-in reservation';
    END IF;

    INSERT INTO reservation_services (reservation_id, service_id, quantity, service_date)
    VALUES (p_res, p_service, p_qty, CURDATE());
    COMMIT;
END$$

-- C5. Record a payment
DROP PROCEDURE IF EXISTS sp_record_payment$$
CREATE PROCEDURE sp_record_payment(IN p_res INT UNSIGNED, IN p_amount DECIMAL(12,2), IN p_method VARCHAR(20))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    INSERT INTO payments (reservation_id, amount, method) VALUES (p_res, p_amount, p_method);
    COMMIT;
END$$

-- C6. Itemised bill (two result sets: summary + service lines)
DROP PROCEDURE IF EXISTS sp_generate_bill$$
CREATE PROCEDURE sp_generate_bill(IN p_res INT UNSIGNED)
BEGIN
    DECLARE v_room  DECIMAL(12,2);
    DECLARE v_srv   DECIMAL(12,2);
    DECLARE v_paid  DECIMAL(12,2);
    DECLARE v_total DECIMAL(12,2);

    IF NOT EXISTS (SELECT 1 FROM reservations WHERE reservation_id = p_res) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reservation not found';
    END IF;

    SELECT total_amount INTO v_room FROM reservations WHERE reservation_id = p_res;
    SELECT IFNULL(SUM(quantity * unit_price),0) INTO v_srv
      FROM reservation_services WHERE reservation_id = p_res;
    SET v_total = fn_bill_total(p_res);
    SET v_paid  = fn_amount_paid(p_res);

    SELECT r.reservation_id,
           CONCAT(g.first_name, ' ', g.last_name) AS guest,
           rm.room_number, t.type_name, r.status,
           r.check_in_date, r.check_out_date,
           DATEDIFF(r.check_out_date, r.check_in_date) AS nights,
           t.base_price      AS rate_per_night,
           v_room            AS room_charges,
           v_srv             AS service_charges,
           ROUND((v_room + v_srv) * 0.12, 2) AS gst_12_percent,
           v_total           AS grand_total,
           v_paid            AS amount_paid,
           v_total - v_paid  AS balance_due
      FROM reservations r
      JOIN guests g      ON g.guest_id = r.guest_id
      JOIN rooms rm      ON rm.room_id = r.room_id
      JOIN room_types t  ON t.type_id  = rm.type_id
     WHERE r.reservation_id = p_res;

    SELECT s.service_name, rs.service_date, rs.quantity, rs.unit_price,
           rs.quantity * rs.unit_price AS line_total
      FROM reservation_services rs
      JOIN services s ON s.service_id = rs.service_id
     WHERE rs.reservation_id = p_res
     ORDER BY rs.service_date, s.service_name;
END$$

-- C7. Check-out: only when the bill is fully settled
DROP PROCEDURE IF EXISTS sp_check_out$$
CREATE PROCEDURE sp_check_out(IN p_res INT UNSIGNED)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status INTO v_status FROM reservations WHERE reservation_id = p_res FOR UPDATE;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reservation not found';
    END IF;
    IF v_status <> 'Checked-In' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only checked-in reservations can be checked out';
    END IF;
    IF fn_bill_total(p_res) - fn_amount_paid(p_res) > 0.01 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Outstanding balance - settle the bill before check-out';
    END IF;

    UPDATE reservations
       SET status = 'Checked-Out', actual_check_out = NOW()
     WHERE reservation_id = p_res;           -- trigger frees the room
    COMMIT;

    CALL sp_generate_bill(p_res);
END$$

-- C8. Cancel a booking that has not started
DROP PROCEDURE IF EXISTS sp_cancel_reservation$$
CREATE PROCEDURE sp_cancel_reservation(IN p_res INT UNSIGNED)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT status INTO v_status FROM reservations WHERE reservation_id = p_res FOR UPDATE;
    IF v_status IS NULL OR v_status <> 'Booked' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only reservations in Booked status can be cancelled';
    END IF;

    UPDATE reservations SET status = 'Cancelled' WHERE reservation_id = p_res;
    INSERT INTO audit_log (table_name, action, record_id, details, logged_by)
    VALUES ('reservations', 'CANCEL', p_res, 'Cancelled by user request', CURRENT_USER());
    COMMIT;
END$$

-- C9. Occupancy by room type on a given date, built with an explicit CURSOR
DROP PROCEDURE IF EXISTS sp_occupancy_by_type$$
CREATE PROCEDURE sp_occupancy_by_type(IN p_date DATE)
BEGIN
    DECLARE done    INT DEFAULT 0;
    DECLARE v_type  TINYINT UNSIGNED;
    DECLARE v_name  VARCHAR(30);
    DECLARE v_total INT;
    DECLARE v_occ   INT;
    DECLARE cur CURSOR FOR SELECT type_id, type_name FROM room_types ORDER BY type_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_occupancy;
    CREATE TEMPORARY TABLE tmp_occupancy (
        type_name      VARCHAR(30),
        total_rooms    INT,
        occupied_rooms INT,
        occupancy_pct  DECIMAL(5,2)
    );

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_type, v_name;
        IF done = 1 THEN
            LEAVE read_loop;
        END IF;

        SELECT COUNT(*) INTO v_total FROM rooms WHERE type_id = v_type;
        SELECT COUNT(DISTINCT x.room_id) INTO v_occ
          FROM reservations x JOIN rooms r ON r.room_id = x.room_id
         WHERE r.type_id = v_type
           AND x.status IN ('Booked','Checked-In','Checked-Out')
           AND p_date >= x.check_in_date AND p_date < x.check_out_date;

        INSERT INTO tmp_occupancy VALUES (v_name, v_total, v_occ, ROUND(100 * v_occ / v_total, 2));
    END LOOP;
    CLOSE cur;

    SELECT * FROM tmp_occupancy;
    DROP TEMPORARY TABLE tmp_occupancy;
END$$

-- C10. Cancel no-shows (Booked, check-in date already passed)
DROP PROCEDURE IF EXISTS sp_cancel_no_shows$$
CREATE PROCEDURE sp_cancel_no_shows()
BEGIN
    UPDATE reservations SET status = 'Cancelled'
     WHERE status = 'Booked' AND check_in_date < CURDATE();
    SELECT ROW_COUNT() AS reservations_cancelled;
END$$

-- =====================================================================
--  D. SCHEDULED EVENT  (needs:  SET GLOBAL event_scheduler = ON;)
-- =====================================================================
DROP EVENT IF EXISTS ev_cancel_no_shows$$
CREATE EVENT ev_cancel_no_shows
    ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 2 HOUR)
    DO
        UPDATE reservations SET status = 'Cancelled'
         WHERE status = 'Booked' AND check_in_date < CURDATE()$$

DELIMITER ;

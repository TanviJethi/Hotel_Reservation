-- =====================================================================
--  HOTEL RESERVATION SYSTEM  |  MySQL 8.0.16+  |  01_schema.sql
--  Creates the database, tables, keys, constraints and indexes.
-- =====================================================================
DROP DATABASE IF EXISTS hotel_db;
CREATE DATABASE hotel_db CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE hotel_db;

-- ---------------------------------------------------------------------
-- 1. GUESTS
-- ---------------------------------------------------------------------
CREATE TABLE guests (
    guest_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    first_name    VARCHAR(50)   NOT NULL,
    last_name     VARCHAR(50)   NOT NULL,
    email         VARCHAR(100)  NOT NULL,
    phone         VARCHAR(15)   NOT NULL,
    address       VARCHAR(200),
    city          VARCHAR(60),
    id_proof_type ENUM('Aadhaar','Passport','Driving Licence','Voter ID') NOT NULL,
    id_proof_no   VARCHAR(30)   NOT NULL,
    created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_guests        PRIMARY KEY (guest_id),
    CONSTRAINT uq_guests_email  UNIQUE (email),
    CONSTRAINT uq_guests_idproof UNIQUE (id_proof_type, id_proof_no),
    CONSTRAINT ck_guests_phone  CHECK (phone REGEXP '^[0-9+ -]{10,15}$')
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. ROOM TYPES  (price and capacity depend on type, not on room -> 3NF)
-- ---------------------------------------------------------------------
CREATE TABLE room_types (
    type_id       TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    type_name     VARCHAR(30)   NOT NULL,
    description   VARCHAR(200),
    base_price    DECIMAL(10,2) NOT NULL,
    max_occupancy TINYINT UNSIGNED NOT NULL,
    CONSTRAINT pk_room_types PRIMARY KEY (type_id),
    CONSTRAINT uq_type_name  UNIQUE (type_name),
    CONSTRAINT ck_type_price CHECK (base_price > 0),
    CONSTRAINT ck_type_occ   CHECK (max_occupancy BETWEEN 1 AND 10)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. ROOMS
-- ---------------------------------------------------------------------
CREATE TABLE rooms (
    room_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    room_number VARCHAR(6)   NOT NULL,
    type_id     TINYINT UNSIGNED NOT NULL,
    floor_no    TINYINT UNSIGNED NOT NULL,
    status      ENUM('Available','Occupied','Maintenance') NOT NULL DEFAULT 'Available',
    CONSTRAINT pk_rooms        PRIMARY KEY (room_id),
    CONSTRAINT uq_room_number  UNIQUE (room_number),
    CONSTRAINT fk_rooms_type   FOREIGN KEY (type_id) REFERENCES room_types(type_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    INDEX idx_rooms_type (type_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. STAFF
-- ---------------------------------------------------------------------
CREATE TABLE staff (
    staff_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    full_name  VARCHAR(100)  NOT NULL,
    role       ENUM('Manager','Receptionist','Accountant','Housekeeping') NOT NULL,
    email      VARCHAR(100)  NOT NULL,
    phone      VARCHAR(15)   NOT NULL,
    hire_date  DATE          NOT NULL,
    salary     DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_staff        PRIMARY KEY (staff_id),
    CONSTRAINT uq_staff_email  UNIQUE (email),
    CONSTRAINT ck_staff_salary CHECK (salary > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. RESERVATIONS
-- ---------------------------------------------------------------------
CREATE TABLE reservations (
    reservation_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    guest_id         INT UNSIGNED NOT NULL,
    room_id          INT UNSIGNED NOT NULL,
    staff_id         INT UNSIGNED NOT NULL,           -- employee who made the booking
    check_in_date    DATE NOT NULL,
    check_out_date   DATE NOT NULL,
    num_guests       TINYINT UNSIGNED NOT NULL DEFAULT 1,
    status           ENUM('Booked','Checked-In','Checked-Out','Cancelled') NOT NULL DEFAULT 'Booked',
    total_amount     DECIMAL(12,2) NOT NULL DEFAULT 0.00,  -- room charges (set by trigger)
    actual_check_in  DATETIME NULL,
    actual_check_out DATETIME NULL,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservations PRIMARY KEY (reservation_id),
    CONSTRAINT fk_res_guest FOREIGN KEY (guest_id) REFERENCES guests(guest_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_res_room  FOREIGN KEY (room_id)  REFERENCES rooms(room_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_res_staff FOREIGN KEY (staff_id) REFERENCES staff(staff_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_res_dates  CHECK (check_out_date > check_in_date),
    CONSTRAINT ck_res_guests CHECK (num_guests > 0),
    INDEX idx_res_room_dates (room_id, check_in_date, check_out_date),
    INDEX idx_res_guest      (guest_id),
    INDEX idx_res_status     (status),
    INDEX idx_res_checkin    (check_in_date)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. SERVICES (catalogue) and RESERVATION_SERVICES (M:N bridge)
-- ---------------------------------------------------------------------
CREATE TABLE services (
    service_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    service_name VARCHAR(60)   NOT NULL,
    price        DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_services PRIMARY KEY (service_id),
    CONSTRAINT uq_service_name UNIQUE (service_name),
    CONSTRAINT ck_service_price CHECK (price >= 0)
) ENGINE=InnoDB;

CREATE TABLE reservation_services (
    rs_id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    reservation_id INT UNSIGNED  NOT NULL,
    service_id     INT UNSIGNED  NOT NULL,
    quantity       SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    unit_price     DECIMAL(10,2) NOT NULL DEFAULT 0.00,   -- price snapshot (set by trigger)
    service_date   DATE          NOT NULL,
    CONSTRAINT pk_res_services PRIMARY KEY (rs_id),
    CONSTRAINT fk_rs_res  FOREIGN KEY (reservation_id) REFERENCES reservations(reservation_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_rs_srv  FOREIGN KEY (service_id) REFERENCES services(service_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_rs_qty  CHECK (quantity > 0),
    INDEX idx_rs_res (reservation_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. PAYMENTS
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    payment_id     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    reservation_id INT UNSIGNED  NOT NULL,
    amount         DECIMAL(12,2) NOT NULL,
    method         ENUM('Cash','Card','UPI','Net Banking') NOT NULL,
    payment_date   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_payments PRIMARY KEY (payment_id),
    CONSTRAINT fk_pay_res  FOREIGN KEY (reservation_id) REFERENCES reservations(reservation_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_pay_amt  CHECK (amount > 0),
    INDEX idx_pay_res (reservation_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 8. REVIEWS  (1:1 with a completed reservation)
-- ---------------------------------------------------------------------
CREATE TABLE reviews (
    review_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    reservation_id INT UNSIGNED NOT NULL,
    rating         TINYINT UNSIGNED NOT NULL,
    comments       VARCHAR(500),
    review_date    DATE NOT NULL DEFAULT (CURRENT_DATE),
    CONSTRAINT pk_reviews PRIMARY KEY (review_id),
    CONSTRAINT uq_review_res UNIQUE (reservation_id),
    CONSTRAINT fk_rev_res FOREIGN KEY (reservation_id) REFERENCES reservations(reservation_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT ck_rating CHECK (rating BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 9. AUDIT LOG (filled by triggers)
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    log_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    table_name VARCHAR(40)  NOT NULL,
    action     VARCHAR(20)  NOT NULL,
    record_id  INT UNSIGNED NOT NULL,
    details    VARCHAR(255),
    logged_by  VARCHAR(100) NOT NULL DEFAULT 'system',
    logged_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_audit PRIMARY KEY (log_id)
) ENGINE=InnoDB;

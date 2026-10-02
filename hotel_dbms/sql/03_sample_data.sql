-- =====================================================================
--  03_sample_data.sql   (run AFTER 02; triggers validate every row)
--  Dates are relative to CURDATE() so the demo data is always current.
-- =====================================================================
USE hotel_db;

INSERT INTO room_types (type_name, description, base_price, max_occupancy) VALUES
 ('Standard',     'Compact room with queen bed and city view',        2500.00, 2),
 ('Deluxe',       'Spacious room with king bed and work desk',        4000.00, 3),
 ('Family',       'Two-bedroom family room with lounge',              5500.00, 5),
 ('Suite',        'Suite with living area and bathtub',               8000.00, 4),
 ('Presidential', 'Top-floor suite with private terrace and butler', 15000.00, 6);

INSERT INTO rooms (room_number, type_id, floor_no, status) VALUES
 ('101',1,1,'Available'),('102',1,1,'Available'),('103',1,1,'Available'),
 ('104',1,1,'Available'),('105',1,1,'Available'),('106',1,1,'Available'),
 ('201',2,2,'Available'),('202',2,2,'Available'),('203',2,2,'Available'),
 ('204',2,2,'Available'),('205',2,2,'Available'),('206',2,2,'Maintenance'),
 ('301',3,3,'Available'),('302',3,3,'Available'),('303',3,3,'Available'),('304',3,3,'Available'),
 ('401',4,4,'Available'),('402',4,4,'Available'),('403',4,4,'Available'),
 ('501',5,5,'Available');

INSERT INTO staff (full_name, role, email, phone, hire_date, salary) VALUES
 ('Rajesh Malhotra', 'Manager',       'rajesh.m@grandstay.in', '9810011001', '2018-04-01', 85000.00),
 ('Neha Sharma',     'Receptionist',  'neha.s@grandstay.in',   '9810011002', '2021-06-15', 32000.00),
 ('Amit Verma',      'Receptionist',  'amit.v@grandstay.in',   '9810011003', '2022-01-10', 30000.00),
 ('Sunita Rao',      'Accountant',    'sunita.r@grandstay.in', '9810011004', '2019-09-20', 45000.00),
 ('Deepak Yadav',    'Housekeeping',  'deepak.y@grandstay.in', '9810011005', '2020-03-05', 22000.00),
 ('Kavita Singh',    'Housekeeping',  'kavita.s@grandstay.in', '9810011006', '2023-02-14', 21000.00);

INSERT INTO guests (first_name, last_name, email, phone, address, city, id_proof_type, id_proof_no) VALUES
 ('Aarav',  'Gupta',    'aarav.gupta@mail.com',  '9876500001', '12 Sector 18',       'Noida',     'Aadhaar',         '4521 7788 1201'),
 ('Priya',  'Nair',     'priya.nair@mail.com',   '9876500002', '45 MG Road',         'Bengaluru', 'Passport',        'N1234567'),
 ('Rohan',  'Mehta',    'rohan.mehta@mail.com',  '9876500003', '7 Marine Drive',     'Mumbai',    'Aadhaar',         '3300 1122 8890'),
 ('Sneha',  'Iyer',     'sneha.iyer@mail.com',   '9876500004', '22 Anna Salai',      'Chennai',   'Driving Licence', 'TN0920190012345'),
 ('Vikram', 'Singh',    'vikram.singh@mail.com', '9876500005', '5 Civil Lines',      'Jaipur',    'Aadhaar',         '7812 0045 6623'),
 ('Ananya', 'Das',      'ananya.das@mail.com',   '9876500006', '88 Park Street',     'Kolkata',   'Passport',        'P7654321'),
 ('Karan',  'Kapoor',   'karan.kapoor@mail.com', '9876500007', '3 Connaught Place',  'Delhi',     'Voter ID',        'DL/01/123/456789'),
 ('Meera',  'Reddy',    'meera.reddy@mail.com',  '9876500008', '19 Banjara Hills',   'Hyderabad', 'Aadhaar',         '9021 5567 3340'),
 ('Arjun',  'Patel',    'arjun.patel@mail.com',  '9876500009', '31 CG Road',         'Ahmedabad', 'Driving Licence', 'GJ0120180098765'),
 ('Ishita', 'Joshi',    'ishita.joshi@mail.com', '9876500010', '14 FC Road',         'Pune',      'Aadhaar',         '6677 2210 4455'),
 ('Farhan', 'Khan',     'farhan.khan@mail.com',  '9876500011', '9 Hazratganj',       'Lucknow',   'Voter ID',        'UP/32/456/987654'),
 ('Tanvi',  'Bose',     'tanvi.bose@mail.com',   '9876500012', '60 Salt Lake',       'Kolkata',   'Aadhaar',         '1199 3344 7766');

INSERT INTO services (service_name, price) VALUES
 ('Breakfast Buffet',  400.00),   -- 1
 ('Lunch',             650.00),   -- 2
 ('Dinner',            800.00),   -- 3
 ('Laundry (per load)',250.00),   -- 4
 ('Airport Pickup',   1200.00),   -- 5
 ('Spa Session',      1800.00),   -- 6
 ('Room Service Snack',300.00),   -- 7
 ('Minibar',           350.00),   -- 8
 ('Extra Bed',         700.00);   -- 9

-- ---------------------------------------------------------------------
-- Reservations: (guest, room_id, staff, check-in, check-out, guests, status)
-- room_id: 1-6 =101-106, 7-12 =201-206, 13-16 =301-304, 17-19 =401-403, 20 =501
-- ---------------------------------------------------------------------
INSERT INTO reservations (guest_id, room_id, staff_id, check_in_date, check_out_date, num_guests, status) VALUES
 -- completed stays (res 1-10)
 (1,  1, 2, CURDATE() - INTERVAL 80 DAY, CURDATE() - INTERVAL 77 DAY, 2, 'Checked-Out'),
 (2,  7, 2, CURDATE() - INTERVAL 75 DAY, CURDATE() - INTERVAL 70 DAY, 2, 'Checked-Out'),
 (3, 13, 3, CURDATE() - INTERVAL 60 DAY, CURDATE() - INTERVAL 56 DAY, 4, 'Checked-Out'),
 (4, 17, 3, CURDATE() - INTERVAL 55 DAY, CURDATE() - INTERVAL 52 DAY, 3, 'Checked-Out'),
 (5,  2, 2, CURDATE() - INTERVAL 45 DAY, CURDATE() - INTERVAL 43 DAY, 1, 'Checked-Out'),
 (1,  8, 3, CURDATE() - INTERVAL 40 DAY, CURDATE() - INTERVAL 37 DAY, 2, 'Checked-Out'),
 (6, 20, 2, CURDATE() - INTERVAL 35 DAY, CURDATE() - INTERVAL 31 DAY, 4, 'Checked-Out'),
 (7,  3, 3, CURDATE() - INTERVAL 25 DAY, CURDATE() - INTERVAL 22 DAY, 2, 'Checked-Out'),
 (8, 14, 2, CURDATE() - INTERVAL 20 DAY, CURDATE() - INTERVAL 16 DAY, 5, 'Checked-Out'),
 (2, 18, 3, CURDATE() - INTERVAL 12 DAY, CURDATE() - INTERVAL  9 DAY, 3, 'Checked-Out'),
 -- guests currently in house (res 11-13)
 (9,  4, 2, CURDATE() - INTERVAL 2 DAY, CURDATE() + INTERVAL 1 DAY, 2, 'Checked-In'),
 (10, 9, 3, CURDATE() - INTERVAL 1 DAY, CURDATE() + INTERVAL 2 DAY, 3, 'Checked-In'),
 (11,15, 2, CURDATE() - INTERVAL 3 DAY, CURDATE() + INTERVAL 2 DAY, 4, 'Checked-In'),
 -- upcoming bookings (res 14-17)
 (12, 5, 3, CURDATE(),                   CURDATE() + INTERVAL 2 DAY,  2, 'Booked'),
 (3, 19, 2, CURDATE() + INTERVAL 5 DAY,  CURDATE() + INTERVAL 8 DAY,  2, 'Booked'),
 (4, 10, 3, CURDATE() + INTERVAL 10 DAY, CURDATE() + INTERVAL 14 DAY, 2, 'Booked'),
 (5, 16, 2, CURDATE() + INTERVAL 15 DAY, CURDATE() + INTERVAL 20 DAY, 5, 'Booked'),
 -- cancelled (res 18)
 (6,  6, 3, CURDATE() + INTERVAL 3 DAY,  CURDATE() + INTERVAL 5 DAY,  1, 'Cancelled');

-- actual arrival / departure times for stays already started or finished
UPDATE reservations
   SET actual_check_in  = TIMESTAMP(check_in_date,  '14:00:00'),
       actual_check_out = CASE WHEN status = 'Checked-Out'
                               THEN TIMESTAMP(check_out_date, '11:00:00') END
 WHERE status IN ('Checked-In','Checked-Out');

-- rooms of in-house guests are occupied
UPDATE rooms SET status = 'Occupied' WHERE room_id IN (4, 9, 15);

-- ---------------------------------------------------------------------
-- Services consumed (unit_price is filled by trigger trg_rs_bi)
-- ---------------------------------------------------------------------
INSERT INTO reservation_services (reservation_id, service_id, quantity, service_date)
SELECT reservation_id, 1, DATEDIFF(check_out_date, check_in_date) * num_guests, check_in_date
  FROM reservations
 WHERE status IN ('Checked-In','Checked-Out');          -- breakfast for every stay

INSERT INTO reservation_services (reservation_id, service_id, quantity, service_date) VALUES
 ( 3, 6, 2, CURDATE() - INTERVAL 59 DAY),
 ( 4, 3, 3, CURDATE() - INTERVAL 54 DAY),
 ( 6, 7, 3, CURDATE() - INTERVAL 39 DAY),
 ( 7, 5, 1, CURDATE() - INTERVAL 35 DAY),
 ( 7, 6, 4, CURDATE() - INTERVAL 34 DAY),
 ( 9, 4, 6, CURDATE() - INTERVAL 18 DAY),
 (10, 2, 3, CURDATE() - INTERVAL 11 DAY),
 (11, 4, 5, CURDATE() - INTERVAL  1 DAY),
 (12, 3, 3, CURDATE()),
 (13, 9, 1, CURDATE() - INTERVAL  2 DAY),
 (13, 2, 4, CURDATE() - INTERVAL  1 DAY);

-- ---------------------------------------------------------------------
-- Payments: completed stays fully paid; in-house and future = advances
-- ---------------------------------------------------------------------
INSERT INTO payments (reservation_id, amount, method, payment_date)
SELECT reservation_id,
       fn_bill_total(reservation_id),
       ELT(1 + MOD(reservation_id, 4), 'Cash', 'Card', 'UPI', 'Net Banking'),
       TIMESTAMP(check_out_date, '11:30:00')
  FROM reservations
 WHERE status = 'Checked-Out';

INSERT INTO payments (reservation_id, amount, method) VALUES
 (11, 3000.00, 'Card'),
 (12, 5000.00, 'UPI'),
 (13, 4000.00, 'Cash'),
 (14, 2000.00, 'UPI'),
 (15, 5000.00, 'Card'),
 (16, 8000.00, 'Net Banking');

-- ---------------------------------------------------------------------
-- Reviews (only for completed stays)
-- ---------------------------------------------------------------------
INSERT INTO reviews (reservation_id, rating, comments, review_date) VALUES
 (1, 4, 'Clean room and quick check-in.',                 CURDATE() - INTERVAL 76 DAY),
 (2, 5, 'Excellent service, loved the breakfast.',        CURDATE() - INTERVAL 69 DAY),
 (3, 5, 'Perfect for a family trip. Spa was great.',      CURDATE() - INTERVAL 55 DAY),
 (4, 4, 'Spacious suite, dinner was very good.',          CURDATE() - INTERVAL 51 DAY),
 (5, 3, 'Average stay, air conditioning was noisy.',      CURDATE() - INTERVAL 42 DAY),
 (6, 4, 'Comfortable and well located.',                  CURDATE() - INTERVAL 36 DAY),
 (7, 5, 'Presidential suite was outstanding.',            CURDATE() - INTERVAL 30 DAY),
 (8, 2, 'Long wait at check-in and slow room service.',   CURDATE() - INTERVAL 21 DAY),
 (9, 4, 'Good value for a big family.',                   CURDATE() - INTERVAL 15 DAY);

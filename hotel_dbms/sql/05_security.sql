-- =====================================================================
--  05_security.sql - Role-based access control (MySQL 8 roles)
--  Change the passwords before using outside a classroom.
-- =====================================================================
USE hotel_db;

CREATE ROLE IF NOT EXISTS 'hotel_manager', 'hotel_receptionist', 'hotel_accountant';

-- Manager: full control of the hotel schema
GRANT ALL PRIVILEGES ON hotel_db.* TO 'hotel_manager';

-- Receptionist: day-to-day front-desk work, no deletes, no payroll data
-- (table-level grants: the staff table, which holds salaries, is deliberately left out)
GRANT SELECT ON hotel_db.guests               TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.rooms                TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.room_types           TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.reservations         TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.services             TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.reservation_services TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.payments             TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.v_reservation_details TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.v_current_guests     TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.v_room_status_today  TO 'hotel_receptionist';
GRANT SELECT ON hotel_db.v_bill_summary       TO 'hotel_receptionist';
GRANT INSERT, UPDATE ON hotel_db.guests TO 'hotel_receptionist';
GRANT EXECUTE ON PROCEDURE hotel_db.sp_available_rooms     TO 'hotel_receptionist';
GRANT EXECUTE ON PROCEDURE hotel_db.sp_make_reservation    TO 'hotel_receptionist';
GRANT EXECUTE ON PROCEDURE hotel_db.sp_check_in            TO 'hotel_receptionist';
GRANT EXECUTE ON PROCEDURE hotel_db.sp_check_out           TO 'hotel_receptionist';
GRANT EXECUTE ON PROCEDURE hotel_db.sp_cancel_reservation  TO 'hotel_receptionist';
GRANT EXECUTE ON PROCEDURE hotel_db.sp_add_service         TO 'hotel_receptionist';
GRANT EXECUTE ON PROCEDURE hotel_db.sp_record_payment      TO 'hotel_receptionist';
GRANT EXECUTE ON PROCEDURE hotel_db.sp_generate_bill       TO 'hotel_receptionist';

-- Accountant: read financial data only
GRANT SELECT ON hotel_db.payments             TO 'hotel_accountant';
GRANT SELECT ON hotel_db.reservation_services TO 'hotel_accountant';
GRANT SELECT ON hotel_db.v_bill_summary       TO 'hotel_accountant';
GRANT SELECT ON hotel_db.v_monthly_revenue    TO 'hotel_accountant';

CREATE USER IF NOT EXISTS 'manager1'@'localhost'      IDENTIFIED BY 'Manager@123';
CREATE USER IF NOT EXISTS 'reception1'@'localhost'    IDENTIFIED BY 'Reception@123';
CREATE USER IF NOT EXISTS 'accountant1'@'localhost'   IDENTIFIED BY 'Account@123';

GRANT 'hotel_manager'      TO 'manager1'@'localhost';
GRANT 'hotel_receptionist' TO 'reception1'@'localhost';
GRANT 'hotel_accountant'   TO 'accountant1'@'localhost';

SET DEFAULT ROLE ALL TO 'manager1'@'localhost', 'reception1'@'localhost', 'accountant1'@'localhost';
FLUSH PRIVILEGES;

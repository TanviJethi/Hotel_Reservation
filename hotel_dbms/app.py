#!/usr/bin/env python3
"""
Hotel Reservation System - command-line front end for the MySQL `hotel_db`.
All business rules live in the database (procedures, triggers, constraints);
this program only collects input, calls them and prints the results.

Usage:
    pip install mysql-connector-python
    python app.py                      # prompts for the MySQL password
Environment variables (optional): HOTEL_DB_HOST, HOTEL_DB_USER, HOTEL_DB_PASSWORD, HOTEL_DB_NAME
"""
import os
import sys
from datetime import date, datetime
from decimal import Decimal
from getpass import getpass

import mysql.connector
from mysql.connector import Error


# ----------------------------------------------------------------------
# Connection and helpers
# ----------------------------------------------------------------------
def connect():
    cfg = {
        "host": os.getenv("HOTEL_DB_HOST", "localhost"),
        "user": os.getenv("HOTEL_DB_USER", "root"),
        "password": os.getenv("HOTEL_DB_PASSWORD") or getpass("MySQL password: "),
        "database": os.getenv("HOTEL_DB_NAME", "hotel_db"),
    }
    conn = mysql.connector.connect(**cfg)
    conn.autocommit = True          # procedures manage their own transactions
    return conn


def fmt(v):
    if v is None:
        return "-"
    if isinstance(v, Decimal):
        return f"{v:,.2f}"
    if isinstance(v, (date, datetime)):
        return str(v)
    return str(v)


def print_table(rows, title=None):
    """Print a list of dict rows as an aligned text table."""
    if title:
        print(f"\n=== {title} ===")
    if not rows:
        print("(no records)")
        return
    cols = list(rows[0].keys())
    data = [[fmt(r[c]) for c in cols] for r in rows]
    widths = [max(len(c), *(len(row[i]) for row in data)) for i, c in enumerate(cols)]
    line = "+-" + "-+-".join("-" * w for w in widths) + "-+"
    print(line)
    print("| " + " | ".join(c.ljust(w) for c, w in zip(cols, widths)) + " |")
    print(line)
    for row in data:
        print("| " + " | ".join(v.ljust(w) for v, w in zip(row, widths)) + " |")
    print(line)
    print(f"{len(rows)} row(s)")


def query(conn, sql, params=None):
    cur = conn.cursor(dictionary=True)
    cur.execute(sql, params or ())
    rows = cur.fetchall()
    cur.close()
    return rows


def execute(conn, sql, params=None):
    cur = conn.cursor()
    cur.execute(sql, params or ())
    last_id = cur.lastrowid
    cur.close()
    return last_id


def call(conn, name, args=()):
    """Call a stored procedure; return (result_sets, out_args)."""
    cur = conn.cursor(dictionary=True)
    out = cur.callproc(name, args)
    sets = [r.fetchall() for r in cur.stored_results()]
    cur.close()
    return sets, out


def ask(prompt, cast=str, default=None, allow_blank=False):
    while True:
        raw = input(f"{prompt}{f' [{default}]' if default is not None else ''}: ").strip()
        if not raw:
            if default is not None:
                return default
            if allow_blank:
                return None
        try:
            if raw:
                return cast(raw)
        except (ValueError, ArithmeticError):
            pass
        print("  Invalid input, please try again.")


def to_date(s):
    return datetime.strptime(s, "%Y-%m-%d").date()


def ask_date(prompt):
    return ask(f"{prompt} (YYYY-MM-DD)", to_date)


def guarded(fn):
    """Run a menu action and show database errors (raised by triggers/procedures) nicely."""
    def wrapper(conn):
        try:
            fn(conn)
        except Error as e:
            print(f"\n  [DATABASE ERROR] {e.msg}")
        except KeyboardInterrupt:
            print("\n  Cancelled.")
    return wrapper


# ----------------------------------------------------------------------
# Guests
# ----------------------------------------------------------------------
@guarded
def add_guest(conn):
    print("\n-- Register new guest --")
    first = ask("First name")
    last = ask("Last name")
    email = ask("Email")
    phone = ask("Phone (10-15 digits)")
    address = ask("Address", default="")
    city = ask("City", default="")
    print("ID proof types: Aadhaar, Passport, Driving Licence, Voter ID")
    id_type = ask("ID proof type")
    id_no = ask("ID proof number")
    gid = execute(conn,
        "INSERT INTO guests (first_name,last_name,email,phone,address,city,id_proof_type,id_proof_no) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
        (first, last, email, phone, address or None, city or None, id_type, id_no))
    print(f"  Guest registered with ID {gid}")


@guarded
def list_guests(conn):
    term = ask("Search name/email/phone (blank = all)", allow_blank=True)
    like = f"%{term or ''}%"
    rows = query(conn,
        "SELECT guest_id, CONCAT(first_name,' ',last_name) AS name, email, phone, city "
        "FROM guests WHERE CONCAT(first_name,' ',last_name) LIKE %s OR email LIKE %s OR phone LIKE %s "
        "ORDER BY guest_id", (like, like, like))
    print_table(rows, "Guests")


# ----------------------------------------------------------------------
# Rooms
# ----------------------------------------------------------------------
@guarded
def available_rooms(conn):
    cin = ask_date("Check-in date")
    cout = ask_date("Check-out date")
    types = query(conn, "SELECT type_id, type_name, base_price, max_occupancy FROM room_types")
    print_table(types, "Room types")
    t = ask("Room type ID (blank = any)", int, allow_blank=True)
    sets, _ = call(conn, "sp_available_rooms", (cin, cout, t))
    print_table(sets[0], f"Rooms available {cin} to {cout}")


@guarded
def room_board(conn):
    print_table(query(conn, "SELECT * FROM v_room_status_today ORDER BY room_number"), "Room status board")


# ----------------------------------------------------------------------
# Reservations
# ----------------------------------------------------------------------
@guarded
def make_reservation(conn):
    print("\n-- New reservation --")
    gid = ask("Guest ID", int)
    sid = ask("Staff ID (booking employee)", int)
    cin = ask_date("Check-in date")
    cout = ask_date("Check-out date")
    sets, _ = call(conn, "sp_available_rooms", (cin, cout, None))
    print_table(sets[0], "Available rooms")
    if not sets[0]:
        return
    room = ask("Room ID to book", int)
    n = ask("Number of guests", int, default=1)
    _, out = call(conn, "sp_make_reservation", (gid, room, sid, cin, cout, n, 0))
    print(f"  Reservation confirmed. Reservation ID = {out[6]}")


@guarded
def check_in(conn):
    rid = ask("Reservation ID to check in", int)
    call(conn, "sp_check_in", (rid,))
    print("  Guest checked in. Room is now Occupied.")


@guarded
def cancel_reservation(conn):
    rid = ask("Reservation ID to cancel", int)
    call(conn, "sp_cancel_reservation", (rid,))
    print("  Reservation cancelled.")


@guarded
def view_reservations(conn):
    status = ask("Filter by status (Booked/Checked-In/Checked-Out/Cancelled, blank = all)", allow_blank=True)
    if status:
        rows = query(conn, "SELECT * FROM v_reservation_details WHERE status=%s ORDER BY check_in_date DESC", (status,))
    else:
        rows = query(conn, "SELECT * FROM v_reservation_details ORDER BY check_in_date DESC")
    print_table(rows, "Reservations")


# ----------------------------------------------------------------------
# Services and billing
# ----------------------------------------------------------------------
@guarded
def add_service(conn):
    print_table(query(conn, "SELECT * FROM services ORDER BY service_id"), "Service catalogue")
    rid = ask("Reservation ID (must be checked in)", int)
    sid = ask("Service ID", int)
    qty = ask("Quantity", int, default=1)
    call(conn, "sp_add_service", (rid, sid, qty))
    print("  Service added to the bill.")


def show_bill(conn, rid):
    sets, _ = call(conn, "sp_generate_bill", (rid,))
    h = sets[0][0]
    print("\n" + "=" * 52)
    print("          GRAND STAY HOTEL - INVOICE")
    print("=" * 52)
    print(f" Reservation : {h['reservation_id']}   Status: {h['status']}")
    print(f" Guest       : {h['guest']}")
    print(f" Room        : {h['room_number']} ({h['type_name']})")
    print(f" Stay        : {h['check_in_date']} to {h['check_out_date']} ({h['nights']} nights)")
    print("-" * 52)
    print(f" Room charges  ({h['nights']} x {fmt(h['rate_per_night'])}) : {fmt(h['room_charges']):>12}")
    for s in sets[1]:
        label = f"{s['service_name']} x{s['quantity']}"
        print(f"   {label:<34}   {fmt(s['line_total']):>12}")
    print(f" Service charges{'':<19}: {fmt(h['service_charges']):>12}")
    print(f" GST @ 12%{'':<25}: {fmt(h['gst_12_percent']):>12}")
    print("-" * 52)
    print(f" GRAND TOTAL{'':<23}: {fmt(h['grand_total']):>12}")
    print(f" Amount paid{'':<23}: {fmt(h['amount_paid']):>12}")
    print(f" BALANCE DUE{'':<23}: {fmt(h['balance_due']):>12}")
    print("=" * 52)


@guarded
def view_bill(conn):
    show_bill(conn, ask("Reservation ID", int))


@guarded
def record_payment(conn):
    rid = ask("Reservation ID", int)
    show_bill(conn, rid)
    amt = ask("Amount to pay", Decimal)
    method = ask("Method (Cash/Card/UPI/Net Banking)")
    call(conn, "sp_record_payment", (rid, amt, method))
    print("  Payment recorded.")


@guarded
def check_out(conn):
    rid = ask("Reservation ID to check out", int)
    sets, _ = call(conn, "sp_check_out", (rid,))
    print("  Check-out complete. Room released.")
    show_bill(conn, rid)


@guarded
def add_review(conn):
    rid = ask("Reservation ID", int)
    rating = ask("Rating (1-5)", int)
    comment = ask("Comment", allow_blank=True)
    execute(conn, "INSERT INTO reviews (reservation_id, rating, comments) VALUES (%s,%s,%s)",
            (rid, rating, comment))
    print("  Thank you for the review!")


# ----------------------------------------------------------------------
# Reports
# ----------------------------------------------------------------------
@guarded
def reports(conn):
    while True:
        print("""
--- Reports ---
 1. Guests currently in house
 2. Outstanding balances
 3. Monthly revenue
 4. Occupancy by room type (today)
 5. Most popular services
 6. Average rating by room type
 7. Audit log (latest 20)
 0. Back""")
        c = input("Choose: ").strip()
        if c == "1":
            print_table(query(conn, "SELECT * FROM v_current_guests"), "In-house guests")
        elif c == "2":
            print_table(query(conn, "SELECT * FROM v_bill_summary WHERE balance_due>0 ORDER BY balance_due DESC"),
                        "Outstanding balances")
        elif c == "3":
            print_table(query(conn, "SELECT * FROM v_monthly_revenue ORDER BY month"), "Monthly revenue")
        elif c == "4":
            sets, _ = call(conn, "sp_occupancy_by_type", (date.today(),))
            print_table(sets[0], "Occupancy today")
        elif c == "5":
            print_table(query(conn,
                "SELECT s.service_name, SUM(rs.quantity) AS units, SUM(rs.quantity*rs.unit_price) AS income "
                "FROM reservation_services rs JOIN services s ON s.service_id=rs.service_id "
                "GROUP BY s.service_name ORDER BY income DESC"), "Popular services")
        elif c == "6":
            print_table(query(conn,
                "SELECT t.type_name, ROUND(AVG(v.rating),2) AS avg_rating, COUNT(*) AS reviews "
                "FROM reviews v JOIN reservations r ON r.reservation_id=v.reservation_id "
                "JOIN rooms rm ON rm.room_id=r.room_id JOIN room_types t ON t.type_id=rm.type_id "
                "GROUP BY t.type_name ORDER BY avg_rating DESC"), "Ratings")
        elif c == "7":
            print_table(query(conn, "SELECT * FROM audit_log ORDER BY log_id DESC LIMIT 20"), "Audit log")
        elif c == "0":
            return
        else:
            print("  Invalid choice.")


# ----------------------------------------------------------------------
# Main menu
# ----------------------------------------------------------------------
MENU = """
==========  GRAND STAY HOTEL - RESERVATION SYSTEM  ==========
  1. Register guest              8. Add service to stay
  2. Search guests               9. View bill
  3. Find available rooms       10. Record payment
  4. Room status board          11. Check-out
  5. Make reservation           12. Add review
  6. Check-in                   13. Reports
  7. Cancel reservation         14. View reservations
  0. Exit
"""

ACTIONS = {
    "1": add_guest, "2": list_guests, "3": available_rooms, "4": room_board,
    "5": make_reservation, "6": check_in, "7": cancel_reservation, "8": add_service,
    "9": view_bill, "10": record_payment, "11": check_out, "12": add_review,
    "13": reports, "14": view_reservations,
}


def main():
    try:
        conn = connect()
    except Error as e:
        sys.exit(f"Could not connect to MySQL: {e.msg}")
    print("Connected to", conn.database)
    try:
        while True:
            print(MENU)
            choice = input("Enter choice: ").strip()
            if choice == "0":
                break
            action = ACTIONS.get(choice)
            if action:
                action(conn)
            else:
                print("  Invalid choice.")
    finally:
        conn.close()
        print("Goodbye!")


if __name__ == "__main__":
    main()

python app.py# Hotel Reservation System (MySQL DBMS Project)

**Tech Stack:** MySQL 8.0.16+ (InnoDB) + Python 3 CLI (`mysql-connector-python`)

## Folder Layout
```
hotel_dbms/
├── docs/
│   ├── er_diagram.png
│   ├── er.dot                    ER diagram (Graphviz source included)
├── sql/
│   ├── 01_schema.sql             tables, keys, CHECK/UNIQUE constraints, indexes
│   ├── 02_routines_triggers.sql  3 functions, 10 procedures, 7 triggers, 1 event
│   ├── 03_sample_data.sql        20 rooms, 12 guests, 18 reservations, payments, reviews
│   ├── 04_views_queries.sql      5 views, 23 queries, trigger/transaction demos
│   ├── 05_security.sql           roles + users (manager / receptionist / accountant)
│   └── install_all.sql           runs all of the above in order
├── app.py                        menu-driven Python application

```              

## Run
```bash
cd sql
mysql -u root -p < install_all.sql
mysql -u root -p -e "SET GLOBAL event_scheduler = ON;"   # optional
cd ..
pip install mysql-connector-python
python app.py
```

## Demo script
1. Menu 3: find rooms for tomorrow -> Menu 5: book one.
2. Try booking the same room/dates again -> trigger blocks double booking.
3. Menu 6: check in reservation 14 (arrives today) -> room becomes Occupied.
4. Menu 8: add a service -> Menu 9: view bill with GST.
5. Menu 11: check-out fails until Menu 10 settles the balance.
6. Menu 12: add a review after check-out. Menu 13: reports.
7. Login as `reception1` / `accountant1` to show role restrictions.

Default demo passwords are in `05_security.sql`; change them for real use.

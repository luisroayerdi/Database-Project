# Database-Project

A MySQL schema for a music library (users, artists, songs, albums, playlists), with constraints and triggers that enforce its requirements, plus a test script that checks each one.

## Project structure

```
.
├── sql/
│   └── schema.sql   # Tables, constraints, index, triggers
└── tests/
    └── tests.sql    # Requirement tests (prints PASS/FAIL, rolls back)
```

## How to run

Requires MySQL 8.0.16+ (CHECK constraints are enforced from that version on).

```bash
mysql -u root -p -e "CREATE DATABASE music_db"
mysql -u root -p music_db < sql/schema.sql
mysql -u root -p music_db < tests/tests.sql
```

`tests.sql` rolls back its test data, so the database is left empty afterwards.

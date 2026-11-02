# Commons

Commons is a booking and billing system for a community that shares cars,
bicycles, trailers and other equipment. It runs in production at an income
sharing collective in Denmark. This repository is a copy of that system with
the community's names, domains and deployment details replaced by placeholders,
published so that other communities can try it and build on it.

## What it does

Members book shared resources on a calendar. A resource type decides how a
category of things is billed, for example by time and distance for cars or by
time alone for bicycles, and new kinds of resources are added through the admin
interface rather than in code.

A trip starts when the member scans the QR code on the vehicle, which records
the odometer reading, and ends with a second scan. Trips can also be closed from
a kiosk, from the member's own dashboard, or by an administrator on their
behalf. All of these go through the same code path, so a trip is priced the same
way regardless of how it was closed.

Charges are posted to the member's internal account. The ledger is append only.
A correction is a new entry that offsets the old one, together with a corrected
receipt, so the history can be audited later. At the end of each month an
administrator exports a summary sheet for the bookkeeper.

A wall mounted weekly schedule and a kiosk work without login. Administrators
set the rules for each resource type, such as how early a vehicle may be
collected and how late it may be returned, and they print QR labels for the
vehicles in batches.

The interface is in Danish and English.

## Stack

Ruby on Rails 8 on Ruby 3.4 with PostgreSQL. Pages are rendered on the server
and use Hotwire for interaction and Tailwind for styling. Background jobs, the
cache and websockets run on the Solid adapters, so PostgreSQL is the only
service the app depends on. PDFs and QR codes are generated in pure Ruby.
Members sign in through DiscourseConnect, so a Discourse forum acts as the
identity provider.

## Running it locally

You need Ruby 3.4.9 and a PostgreSQL server that your local user can connect to
without a password. On a Mac with Homebrew, `brew install postgresql@16` and
`brew services start postgresql@16` are enough. On Debian or Ubuntu, install
`postgresql` and `libpq-dev`, then run `sudo -u postgres createuser -s "$USER"`.

```bash
bin/setup --skip-server
bin/dev
```

The first command installs the gems, creates the databases and loads the sample
data. The second starts the app at http://localhost:3000. In development there
is no SSO, so opening the login page signs you in as the seeded administrator.
The seeds also create three members and a set of vehicles with bookings.

`bin/rails test` runs the test suite. `bin/ci` runs the linter and security
scanners as well, which is what the CI workflow does.

## Configuration

All installation specific settings come from environment variables.

`BOOKING_BASE_URL` is the public URL of the app. `DISCOURSE_BASE_URL` is the URL
of the Discourse forum, and `DISCOURSE_CONNECT_PROVIDER_SECRET` is the secret
shared with it. The forum groups that are allowed to sign in are listed in
`app/services/discourse_sso.rb`. The production database is configured with
`DATABASE_URL`, or with `POSTGRES_PASSWORD` and `DB_HOST` as in
`config/database.yml`. Outgoing email uses `SMTP_ADDRESS`, `SMTP_PORT`,
`SMTP_USER_NAME`, `SMTP_PASSWORD`, `SMTP_DOMAIN` and `SMTP_AUTHENTICATION`, and
no email is sent while `SMTP_ADDRESS` is unset.

The repository ships without credentials. Running `bin/rails credentials:edit`
once creates `config/master.key` and an encrypted credentials file.

## Deploying

The app is deployed as a Docker image with [Kamal](https://kamal-deploy.org).
`config/deploy.yml` is a working example with placeholder values, and
`.kamal/secrets.example` lists the secrets it expects. Copy that file to
`.kamal/secrets`, fill it in, adjust `config/deploy.yml`, and run `kamal setup`.
Migrations run when the container boots.

## Demo mode

Setting `DEMO_MODE=1` turns a deployment into a public playground. Every visitor
is signed in as a new guest with admin rights, no email is sent, and the data is
reloaded from the seeds on boot and every hour. A banner explains this and links
to a vehicle's QR page so the scan flow can be tried on a phone.

`render.yaml` deploys such a demo on Render's free tier. Create a Neon project
with the databases `commons`, `commons_cache`, `commons_queue` and
`commons_cable`, create a Blueprint on Render pointing at this repository, and
paste the four direct connection strings in when asked. The free instance sleeps
after fifteen idle minutes, so the first visit afterwards takes about a minute.

## License

AGPL-3.0. See `LICENSE`.

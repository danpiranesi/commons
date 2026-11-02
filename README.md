# Commons

This repository is a copy of software that runs in production at an income
sharing collective in Denmark, and it is published here for external demo
purposes. Identifying details about the community have been replaced with
placeholders, and a few integrations that only made sense for that one place
have been removed. The production code lives in a separate private repository.
This copy is not kept in sync with it and is not deployed anywhere.

## Why it exists

Commons is a resource sharing app that shares an identity layer with a
community forum. The software itself matters less to me than the question
underneath it, which is what happens when the people who live in a place, and
who know how that place actually runs, design technology that fits their own
rhythms instead of bending themselves around something prebuilt.

The collective it was built for has around 70 members who share their housing
and a common economy, along with the vehicles and tools that daily life depends
on.

## What a collective needs that a company does not

Off the shelf tooling assumes a business, where there are staff on one side and
customers on the other and somebody in an office owns the account. A collective
is not arranged that way. The people using a shared car are the same people who
bought it and who decide what it costs to borrow. Administration rotates, and
nobody is paid to be the gatekeeper.

For that reason the app is built around self service that does not need a
person in the middle, and around internal accounting that anyone can inspect.
Handing responsibility from one volunteer to the next is treated as a normal
event.

## How the pieces fit together

This repository is the booking portal. It handles shared resource booking,
usage tracking, internal billing and administration. In production it sits next
to a Discourse forum, which hosts discussion and governance and currently acts
as the identity provider. The collective also runs an intranet for member
information and an archive of its history.

The pieces are kept separable. They talk to each other over HTTP and share a
single sign on rather than a database, so any one of them can be replaced
without dragging the others along.

## What the portal does

Anything the community shares can be added as a resource. A resource type
decides how a category of things is billed. Some types charge for time and
distance, while others are free to use, and individual items are created under
the type they belong to.
Adding a new kind of shared thing is a matter of configuration and does not
require code.

A reservation moves from booked to collected, then to in use, and finally to
returned. Members start a trip by scanning a QR code on the vehicle itself,
which is the moment the real odometer reading is recorded, and they scan again
to finish. A trip can be closed from the QR page, from the kiosk on site, from a
member's own dashboard, or by an administrator acting on someone's behalf. All
of those routes go through one shared code path, so pricing and distance
arithmetic cannot quietly drift apart between them.

Usage is charged to a member's internal account. This is a ledger and not a
payment gateway. Entries are append only, and a correction is posted as an
offsetting entry together with a corrected receipt, which keeps the financial
history auditable instead of editable.

A wall mounted weekly schedule and an on site kiosk let people check
availability and close out trips without logging in. Both use idle timeouts that
suit a screen hanging in a shared hallway.

Administrators control the rules through the interface. They can set buffers
for collecting a vehicle early or bringing it back late, decide whether
extensions are allowed, put sanity limits on odometer entry, and change how
resources are displayed across the app. All of this is configured per resource
type, because the people running the collective should be able to adjust its
behaviour without waiting for a developer.

The portal also prints QR stickers for the vehicles in batches onto die cut
sheets. The label geometry is adjustable, since label stock varies between
suppliers and printers drift over time.

## Technical choices

The app is written in Ruby on Rails 8 on Ruby 3.4 and uses PostgreSQL. The
interface is server rendered HTML that uses Hotwire for its interactive parts,
and it is styled with Tailwind. There is no separate
frontend build and no single page app. Every screen is available in both Danish
and English.

All of the background infrastructure runs on the Solid adapters that ship with
Rails. These store their data in PostgreSQL, so there is no Redis
and no separate worker fleet, and jobs run inside the web process. A single
database is the entire stateful footprint of the app.

PDFs and QR codes are generated in pure Ruby with Prawn and rqrcode, which
avoids depending on a headless browser or a native image library. The tests are
written in Minitest and cover both the domain services and the full request
path.

Deployment uses Kamal to ship Docker images to a single host, where PostgreSQL
runs as a container beside the app. Migrations run on boot, and a deploy is a
single command. Sign in is handled by DiscourseConnect, with the forum holding
the accounts and the group memberships.

## Where it runs

The production system runs entirely on European infrastructure that is operated
by European companies and falls under European jurisdiction. The servers are
hosted in Germany, and outgoing mail is sent through a Danish provider.

This was a deliberate choice. The membership records and internal accounts of a
Danish collective have no business sitting with an American hyperscaler under a
foreign jurisdiction. Keeping everything in Europe makes data protection a
property of where the system runs instead of something delegated to a contract,
and it means the collective holds its own history instead of a vendor holding it.

The app has no managed database and no object storage. It uses no analytics or
tracking service, and it never calls a third party API while handling a
request.

## Built to be self hosted

The architecture was chosen so that moving the app onto the collective's own
hardware is a deployment detail and does not require a rewrite.

Nothing depends on a managed service. Every piece of background infrastructure
runs on PostgreSQL, and the whole runtime consists of the application image
plus a PostgreSQL container that Kamal ships over plain SSH. Any Linux machine
that can be reached with a key is a valid target, whether that is a rented
server or a machine in the community's own server room. Moving between them is
a change of address.

The requirements are kept modest on purpose. The app should be operable by a
volunteer who only checks on it occasionally, and it should run on hardware
that a community can afford to own and replace by itself.

The reasoning behind this is the same reasoning behind the identity work
described below. Tools that a community leans on should not depend on any
particular company continuing to exist or continuing to be affordable.

## Direction

Identity currently comes from the forum. That was the pragmatic choice, but it
means that a member's account and their standing in the community live inside
one application that the collective does not ultimately control. The direction
for the suite is to put [ATProto](https://atproto.com) underneath every app.

With ATProto, a member is a DID instead of a row in a Discourse database. Their
identity survives the collective replacing any part of its software or its
hosting, and the person keeps that identity if they leave.

Trips and contributions can then live in a personal data server that a member
hosts themselves or delegates to someone they trust. The collective's software
reads from and writes to that server, so it is no longer the only custodian of
a person's history.

Lexicons make it possible for separate collectives to agree on what a resource
or a reservation means without agreeing on software. Two communities running
completely different systems could still read each other's data.

Once identity and schemas can travel between communities, the most interesting
work stops being internal. A neighbouring community could borrow a vehicle and
have the trip settle against the right internal ledger, and a visitor could
book something using credentials that their home collective vouches for.

Identity says who somebody is, but it does not say what a community has decided
that person may do. Membership standing and the outcomes of governance
decisions belong to the collective and not to the individual, so they are meant
to live in their own layer of verifiable credentials. The community issues those
credentials and the member carries them, and any part of the suite or any other
community can check them without contacting a central server.

The order of these steps matters. Identity comes first and portable records
come second, while permission and federation between places build on top of
both. Each step is worth having on its own.

## Running it locally

You need Ruby 3.4.9, which is the version pinned in `.ruby-version`, and a
PostgreSQL server that your local user can connect to without a password. On a
Mac with Homebrew, `brew install postgresql@16` followed by
`brew services start postgresql@16` is enough. On Debian or Ubuntu, install
`postgresql` and `libpq-dev`, then create a database role for your login with
`sudo -u postgres createuser -s "$USER"`.

With those in place, the setup script installs the gems, creates the
development and test databases, loads the schema and seeds the sample data:

```bash
bin/setup --skip-server
```

Then start the app:

```bash
bin/dev
```

This runs the Rails server together with the Tailwind watcher, and the app is
available at http://localhost:3000.

Because no SSO secret is configured in development, visiting the login page
signs you straight in as the seeded administrator, Alice Admin. The seeds also
create three ordinary members and a handful of vehicles with sample bookings,
so the calendar has something on it from the first page load. Running
`bin/rails runner db/seeds/rideshare_demo.rb` adds a few upcoming trips for the
rideshare feature.

The test suite runs with:

```bash
bin/rails test
```

Running `bin/ci` performs the same checks as the CI workflow. It runs the linter
and the security scanners before the test suite, and it finishes by reseeding
the test database to make sure the seeds still load.

## Configuration

Everything that differs between installations is read from environment
variables, so there is nothing to edit in the repository to run your own copy.

`BOOKING_BASE_URL` is the public URL of this app. In production it sets the host
used in email links and the only request host the app will answer to.
`DISCOURSE_BASE_URL` is the URL of the Discourse forum that acts as the identity
provider, and `DISCOURSE_CONNECT_PROVIDER_SECRET` is the DiscourseConnect
provider secret shared with that forum. When the secret is blank in development
or test, the login bypass described above is used instead.

The production database is configured through `POSTGRES_PASSWORD` and `DB_HOST`,
as `config/database.yml` shows. Outgoing mail for receipts and the monthly
summary is configured with `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USER_NAME`,
`SMTP_PASSWORD`, `SMTP_DOMAIN` and `SMTP_AUTHENTICATION`, and no mail is sent at
all while `SMTP_ADDRESS` is unset. `RAILS_MASTER_KEY` decrypts the credentials
file in production.

The repository ships without credentials. Run `bin/rails credentials:edit` once
to generate `config/master.key` and an encrypted credentials file; the master
key stays out of git.

Single sign on is set up on the Discourse side under the setting
"enable discourse connect provider", with this app's `BOOKING_BASE_URL` as the
allowed return domain and the same secret in both places. Members are created
on their first login. Which forum groups are allowed in is decided in
`app/services/discourse_sso.rb`, and `bin/rails forum:import[export.csv]` can
pre-create accounts from a Discourse user export so an administrator can fill in
their billing details before they first log in.

## Deploying

Production runs as a Docker image shipped by [Kamal](https://kamal-deploy.org)
to a single host, with PostgreSQL as a Kamal accessory on the same machine.
`config/deploy.yml` is a complete example with placeholder hosts and
registry details, and `.kamal/secrets.example` lists the secrets Kamal expects.
Copy it to `.kamal/secrets`, fill in the values, adjust `config/deploy.yml` to
your host and registry, and run `kamal setup` for the first deploy and
`kamal deploy` after that. Migrations run automatically when the container
boots.

The image listens on port 80 behind Thruster, which handles asset caching and
compression. `config/deploy.yml` disables Kamal's built in proxy, so the host is
expected to run its own TLS termination in front of the container; delete the
`proxy: false` line and the `publish` option to use Kamal's proxy instead.

## Hosting a public demo

Setting `DEMO_MODE=1` turns any deployment into a playground that needs no
forum and no login. Every visitor is signed in automatically as a fresh guest
with admin rights, a banner tells them that other visitors can see what they do,
and a link in that banner opens the QR page for one of the cars so the scan flow
can be tried from a phone without printing a sticker. No email is sent in demo
mode. The database is reloaded from the seeds every time the app boots and once
an hour while it is running, so nothing a visitor does lasts long.

The repository includes a `render.yaml` for hosting such a demo on Render's
free tier, with the database on Neon's free tier, which together cost nothing
and need no card. Create a Neon project with four databases named `commons`,
`commons_cache`, `commons_queue` and `commons_cable`, then create a new
Blueprint on Render pointing at your copy of this repository. Render reads
`render.yaml`, asks for the four connection strings as `DATABASE_URL`,
`CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL` and `CABLE_DATABASE_URL`, and
generates the secret key itself. The free Render instance goes to sleep after
fifteen minutes without visitors, so the first request after a quiet spell takes
about a minute while it wakes up and reseeds.

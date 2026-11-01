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

The app is written in Ruby on Rails 8 on Ruby 3.2 and uses PostgreSQL. The
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

## Development

Run `bin/setup` to install dependencies and prepare the database. Run `bin/dev`
to start the app, which then listens on http://localhost:3002. Run
`bin/rails test` to run the full test suite.

When no SSO secret is configured, the app uses a development login bypass so
that it can be worked on offline.

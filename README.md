# Commons

This is the project I am currently working on finishing.

It is a new forum and a resource sharing app that share an
identity layer. The software matters less
to me than the question underneath it. People who live in one place, and who
know how that place actually runs, designing technology that fits their own
rhythms instead of bending themselves around something prebuilt.

Everything here comes out of an income sharing collective in Denmark, where
around 70 people share housing, vehicles, land, tools, meals and a common
economy.

The repo is not polished, yet.

---

## What a collective needs that a company does not

Off the shelf tooling assumes a business. There are staff, there are customers,
and somebody in an office owns the account. A collective is not arranged that
way. The people using a shared car are also the people who bought it, who
maintain it, and who decide what it costs to borrow. Administration rotates.
Nobody is paid to be the gatekeeper.

So the suite is built around self service that does not need a person in the
middle, and internal accounting that anyone can inspect. Handover between
volunteers is treated as a normal event rather than a crisis.

---

## The suite

| Component | Domain | Role |
|---|---|---|
| **Portal** (this repo) | `booking.example.org` | Shared resource booking, usage tracking, internal billing, administration |
| **Forum** | `forum.example.org` | Discussion and governance, and for now the identity provider |
| **Intranet** | `intranet.example.org` | Internal information and member facing pages |
| **Archive** | `archive.example.org` | Historical record of information at the collective |

The pieces are kept separable. They talk over HTTP and share a sign on rather
than a database, so one of them can be replaced without dragging the others
along.

---

## What the portal does

**Shared resources.** Cars, bicycles, trailers, tools, rooms. A resource type
defines how a category of thing is billed, whether by time, by time and
distance, or not at all. Individual items are resources under that type. Adding
a new kind of shared thing is configuration rather than code.

**The trip.** A reservation goes from booked, to collected, to in use, to
returned. Members scan a QR code on the vehicle itself to start a trip, which is
when the real odometer reading gets recorded, and scan again to finish. Every
route to finishing a trip, whether that is the QR page, the kiosk in the
courtyard, the member's own dashboard, or an administrator acting for somebody
else, goes through one shared code path. Pricing and distance arithmetic cannot
quietly diverge between them.

**Internal accounting.** Usage is charged to a member's internal account. This
is a ledger, not a payment gateway. Entries are append only, and a correction is
posted as an offsetting entry with a corrected receipt, so the financial history
stays auditable instead of editable.

**Unattended screens.** A wall mounted weekly schedule and an on site kiosk let
people read availability and close out trips without logging in, with idle
timeouts suited to a screen in a shared hallway.

**Rules and presentation that admins control.** Buffers for collecting a vehicle
early or bringing it back late, whether extensions are allowed, sanity limits on
odometer entry, and how resources are displayed across the app. All of it is set
per resource type through the interface. The people running the collective
should be able to adjust its behaviour without waiting for me.

**Printable labels.** QR stickers for the vehicles, generated in batches onto
die cut sheets, with adjustable geometry because label stock varies by supplier
and printers drift.

---

## Stack

Ruby on Rails 8 on Ruby 3.2, with PostgreSQL.

The interface is server rendered HTML with Hotwire for the interactive parts,
ViewComponent for structure, and Tailwind for styling. There is no separate
frontend build and no single page app. Everything is available in Danish and
English.

Background work runs on Solid Queue, with Solid Cache and Solid Cable alongside
it. All three sit on PostgreSQL, so there is no Redis and no separate worker
fleet. Jobs run inside the web process. One database is the entire stateful
footprint.

PDFs and QR codes are generated in pure Ruby with Prawn and rqrcode, avoiding a
headless browser or native image library. Tests are Minitest, covering the
domain services and the full request path.

Deployment is Docker images shipped by Kamal to a single host, with PostgreSQL
running as a container beside the app. Migrations run on boot and deploying is
one command.

Identity today comes from DiscourseConnect single sign on, with the forum
holding accounts and group membership.

---

## Where it runs

The whole thing sits on European infrastructure, operated by European
organisations, under European jurisdiction.

| Layer | Provider | Where |
|---|---|---|
| Compute and data | Hetzner | Germany |
| Outgoing mail | Simply.com | Denmark |
| Domains | `.dk` | Denmark |

This was a deliberate choice. A Danish collective's membership records and
internal accounts have no business sitting with a US hyperscaler under a foreign
jurisdiction. Keeping it in Europe makes data protection a
property of where things run rather than something delegated to a contract, and
it keeps the collective rather than a vendor holding its own history.

There is no managed database, no object storage, no analytics or tracking
service, and nothing calling a third party API while a request is in flight.

---

## Built to be self hosted

The architecture was picked so that moving onto the collective's own hardware is
a deployment detail instead of a rewrite.

Nothing depends on a managed service. Queue, cache and websockets all run on
PostgreSQL, so there is no Redis, no S3, no hosted search, no external job
runner. The runtime is the application image plus a PostgreSQL container, and
Kamal ships it over plain SSH. Any Linux machine reachable with a key is a valid
target, whether that is a rented server now or a box in the server room here
later. It is a change of address.

The requirements stay modest on purpose. Server rendered pages, no frontend
build step, no worker fleet, no autoscaling. It should be operable by a
volunteer who checks on it occasionally, and it should run on hardware a
community can afford to own and replace itself.

Still to do before it is genuinely self contained: publishing images from a
registry the collective runs, or building them on the host directly, a mail path
it controls, and a backup and restore routine it owns.

The reasoning is the same one that leads to the identity work below. Tools a
community leans on should not require any particular company to keep existing,
or to keep being affordable.

---

## Where this is going

Identity currently comes from the forum. That was the pragmatic move, but it
means a member's account and their standing in the community live inside one
application that the collective does not ultimately control.

The intended direction is [ATProto](https://atproto.com) underneath all apps.

**Portable identity.** A member is a DID rather than a row in a Discourse
database. Identity survives the collective swapping out its forum or its booking
system or its hosting, and a person keeps it when they leave.

**Records people own.** Trips and contributions live in a personal data server
that a member can host or delegate. The collective's
software reads and writes against that instead of being the only custodian of
somebody's history.

**Shared meaning between communities.** Lexicons let separate collectives agree
on what a resource or a reservation or a membership is, without agreeing on
software. Two communities running completely different systems could still read
each other's data.

**Federation.** Once identity and schema travel, the interesting part stops being
internal. Lending a vehicle to a neighbouring community and having the trip
settle against the right internal ledger. A visitor booking something with
credentials their home collective vouches for. Shared directories of tools and
skills across a network of collectives.

**A separate layer for permission.** Identity says who somebody is. It does not
say what a community has decided they may do. Membership standing and the outcome of a
governance decision belong to the collective rather than to the person, and are meant to sit in their own verifiable credential layer. Issued by
the community, carried by the member, checkable by any part of the suite or by
another community, without phoning home to a central server.

The order matters. Identity, then portable records, then permission, then
federation between places. Each step is worth having on its own.

---

## Development

```sh
bin/setup          # dependencies and database
bin/dev            # http://localhost:3002
bin/rails test     # full suite
```

With no SSO secret configured the app runs with a development login bypass, so
it can be worked on offline.

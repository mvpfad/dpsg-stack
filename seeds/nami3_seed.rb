# frozen_string_literal: true

# NaMi 3.0 – Testdaten für die lokale Entwicklungsumgebung
# =========================================================
#
# Dieser Seed ist die einzige Quelle für lokale Testdaten: Entwickler*innen bekommen
# damit dieselbe Datenbasis, auf der auch die Playwright-Screenshots für die Doku
# entstehen. Er wird von `start-dpsg-stack.sh --seed` im Rails-Container ausgeführt:
#
#   bin/rails runner /tmp/nami3_seed.rb
#
# Der Seed ist idempotent – mehrfaches Ausführen erzeugt keine Duplikate.
#
# Hinweis zu den Gruppentypen: Was in der Oberfläche „Diözesanverband" heißt, ist im
# Code `Group::Landesverband` – der DPSG-Wagon benennt die Ebene nur per Übersetzung um.

require HitobitoPfadiDe::Wagon.root.join("db", "seeds", "support", "fee_kinds_seeder")
require Rails.root.join("db", "seeds", "support", "person_seeder")

PASSWORD = "hito42bito"

# Festes TOTP-Secret für alle Benutzer, deren Rolle 2FA erzwingt. Nur lokal gültig,
# damit sich Menschen (und Playwright) ohne Ersteinrichtung anmelden können.
TOTP_SECRET = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"

# Sorgt dafür, dass auch die über PersonSeeder erzeugten Füllmitglieder ein Passwort haben.
ENV["HITOBITO_DEV_PASSWORD"] ||= PASSWORD

ENCRYPTED_PASSWORD = BCrypt::Password.create(PASSWORD, cost: 1)

# Adressen müssen zum Land passen: Hitobito prüft die Postleitzahl länderspezifisch,
# eine vierstellige Schweizer PLZ wird mit country "DE" abgelehnt.
GERMAN_ZIP = "50321"

def log(message)
  puts message
end

def section(title)
  log ""
  log "— #{title}"
end

# Geschlecht bleibt offen, wo es nichts zur Sache tut – in Screenshots fällt eine
# falsche Zuschreibung sonst auf. Erlaubt sind "m", "w" und "d".
def find_or_create_person(email, first_name:, last_name:,
  birthday: Date.new(1985, 4, 12), gender: nil)
  person = Person.find_or_initialize_by(email: email)
  person.assign_attributes(
    first_name: first_name,
    last_name: last_name,
    company: false,
    confirmed_at: Time.zone.now,
    encrypted_password: ENCRYPTED_PASSWORD,
    birthday: birthday,
    gender: gender,
    street: "Lagerplatz",
    housenumber: "1",
    zip_code: GERMAN_ZIP,
    town: "Silberbach",
    country: "DE",
    payment_method: "invoice"
  )
  person.save!
  person
end

def assign_role(person, group, role_type)
  Role.seed_once(:person_id, :group_id, :type,
    {person_id: person.id, group_id: group.id, type: role_type.sti_name})
  person
end

# Eine Zeile pro Testbenutzer, die `start-dpsg-stack.sh` einliest und als Tabelle ausgibt.
# Format: SEED_USER|key|email|rolle|gruppe|2fa|wofür geeignet
def announce_user(key, email, role_label, group_name, two_fa, purpose)
  puts "SEED_USER|#{key}|#{email}|#{role_label}|#{group_name}|#{two_fa ? "ja" : "nein"}|#{purpose}"
end

# ---------------------------------------------------------------------------
# 1. Grundlagen
# ---------------------------------------------------------------------------

section "Grundlagen"

# Die Bundesebene ist die Wurzel des Gruppenbaums und muss die ID 1 haben – einige
# Stellen in Hitobito setzen das voraus.
bundesebene = Group::Bundesebene.find_by(id: 1) ||
  Group::Bundesebene.create!(id: 1, name: "Bundesebene")
Group.connection.execute(
  "SELECT setval('groups_id_seq', (SELECT GREATEST(COALESCE(MAX(id), 1), 1) FROM groups));"
)
log "Wurzelgruppe: #{bundesebene.name} (ID #{bundesebene.id})"

# Der Stamper wird für Versionierung (PaperTrail) gebraucht; ohne ihn scheitern
# manche Updates im Seed.
root_person = find_or_create_person(Settings.root_email,
  first_name: "Hitobito", last_name: "Admin")
Person.stamper = root_person

# ---------------------------------------------------------------------------
# 2. Gruppenstruktur: Bundesebene → Diözesanverband → Bezirk → 2 Stämme
# ---------------------------------------------------------------------------

section "Gruppenstruktur"

def find_or_create_group(klass, name, parent, attrs = {})
  group = klass.find_by(name: name, parent_id: parent&.id)
  unless group
    group = klass.new(attrs.merge(name: name, parent: parent))
    group.save!
  end
  puts "  #{group.name} (#{group.type})"
  group
end

diozesanverband = find_or_create_group(
  Group::Landesverband, "Diözesanverband Sonnenstein", bundesebene,
  street: "Sonnenweg", housenumber: "1", zip_code: "50667", town: "Sonnenstein",
  country: "DE", email: "dv-sonnenstein@example.com"
)

bezirk = find_or_create_group(
  Group::Bezirk, "Bezirk Silberbach", diozesanverband,
  short_name: "Silberbach", street: "Bachstraße", housenumber: "7",
  zip_code: "50321", town: "Silberbach", country: "DE",
  email: "bezirk-silberbach@example.com"
)

stamm_fuchsbau = find_or_create_group(
  Group::Stamm, "Stamm Fuchsbau", bezirk,
  street: "Am Waldrand", housenumber: "12", zip_code: "50321", town: "Silberbach",
  country: "DE", email: "fuchsbau@example.com"
)

stamm_adlerhorst = find_or_create_group(
  Group::Stamm, "Stamm Adlerhorst", bezirk,
  street: "Hohe Straße", housenumber: "3", zip_code: "50322", town: "Adlerbach",
  country: "DE", email: "adlerhorst@example.com"
)

# `Group::Mitglieder` und `Group::Gruppen` legt Hitobito über default_children selbst an.
# Hier werden sie nur nachgeschlagen (bzw. ergänzt, falls der Baum von Hand verändert wurde).
def static_child(parent, klass)
  parent.children.find_by(type: klass.sti_name) ||
    klass.create!(parent: parent, name: klass.label)
end

STUFEN = {
  Group::StammGruppeBiber => "Biber",
  Group::StammGruppeWoelflinge => "Wölflinge",
  Group::StammGruppeJungpfadfinder => "Jungpfadfinder*innen",
  Group::StammGruppePfadfinder => "Pfadfinder*innen",
  Group::StammGruppeRover => "Rover*innen"
}.freeze

staemme = {}
[stamm_fuchsbau, stamm_adlerhorst].each do |stamm|
  kurzname = stamm.name.sub("Stamm ", "")
  mitglieder = static_child(stamm, Group::Mitglieder)
  gruppen = static_child(stamm, Group::Gruppen)

  stufen = STUFEN.each_with_object({}) do |(klass, bezeichnung), memo|
    memo[klass] = find_or_create_group(klass, "#{bezeichnung} #{kurzname}", gruppen)
  end

  staemme[stamm] = {mitglieder: mitglieder, gruppen: gruppen, stufen: stufen}
end

Group.rebuild!
log "Gruppenbaum neu berechnet."

# ---------------------------------------------------------------------------
# 3. Beitragsarten – ohne sie lassen sich keine Mitgliedschaftsrollen speichern
# ---------------------------------------------------------------------------

section "Beitragsarten"

srand(42) # reproduzierbare Namen und Beträge
if FeeKind.count.zero?
  FeeKindsSeeder.new.seed_fee_kinds
  log "#{FeeKind.count} Beitragsarten angelegt."
else
  log "#{FeeKind.count} Beitragsarten bereits vorhanden – übersprungen."
end

# ---------------------------------------------------------------------------
# 4. Testbenutzer
# ---------------------------------------------------------------------------

section "Testbenutzer"

fuchsbau = staemme[stamm_fuchsbau]

testbenutzer = [
  {
    key: "admin",
    email: Settings.root_email,
    first_name: "Hitobito",
    last_name: "Admin",
    roles: [[bundesebene, Group::Bundesebene::MVAdmin]],
    label: "Bundes-MV-Admin",
    group: bundesebene.name,
    purpose: "Vollzugriff, Systemeinstellungen"
  },
  {
    key: "bv-manager",
    email: "bv-verwaltung@example.com",
    first_name: "Bea",
    last_name: "Bundesverwaltung",
    roles: [[bundesebene, Group::Bundesebene::MVAdmin]],
    label: "Bundes-MV-Admin",
    group: bundesebene.name,
    purpose: "Alles sehen und ändern"
  },
  {
    key: "dv-manager",
    email: "dv-verwaltung@example.com",
    first_name: "Dana",
    last_name: "Diözesanverwaltung",
    roles: [
      [diozesanverband, Group::Landesverband::Landesmitgliederverwaltung],
      [diozesanverband, Group::Landesverband::ErfassungFuehrungszeugnis]
    ],
    label: "DV-Mitgliederverwaltung + eFZ",
    group: diozesanverband.name,
    purpose: "Ganzer DV, Führungszeugnisse"
  },
  {
    key: "bezirk-manager",
    email: "bezirk-verwaltung@example.com",
    first_name: "Ben",
    last_name: "Bezirkssprecher",
    roles: [[bezirk, Group::Bezirk::Bezirkssprecher]],
    label: "Bezirkssprecher*in",
    group: bezirk.name,
    purpose: "Bezirk lesen, Kontaktdaten"
  },
  {
    key: "stamm-manager",
    email: "stammesverwaltung@example.com",
    first_name: "Sina",
    last_name: "Stammesverwaltung",
    roles: [[stamm_fuchsbau, Group::Stamm::Stammesmitgliederverwaltung]],
    label: "Stammesmitgliederverwaltung",
    group: stamm_fuchsbau.name,
    purpose: "Mitglieder im Stamm pflegen"
  },
  {
    key: "stamm-fuehrung",
    email: "stammesfuehrung@example.com",
    first_name: "Finn",
    last_name: "Stammesführung",
    roles: [[stamm_fuchsbau, Group::Stamm::Stammesfuehrung]],
    label: "Stammesführung",
    group: stamm_fuchsbau.name,
    purpose: "Stamm lesen – Login ohne 2FA"
  },
  {
    key: "leader",
    email: "gruppenleitung@example.com",
    first_name: "Lea",
    last_name: "Gruppenleitung",
    birthday: Date.new(2004, 3, 9),
    roles: [[fuchsbau[:stufen][Group::StammGruppeWoelflinge],
      Group::StammGruppeWoelflinge::Leitung]],
    label: "Wölflingsleitung",
    group: "Wölflinge Fuchsbau",
    purpose: "Nur die eigene Stufengruppe"
  },
  {
    key: "member",
    email: "mitglied@example.com",
    first_name: "Mika",
    last_name: "Mitglied",
    birthday: Date.new(2012, 8, 21),
    roles: [[fuchsbau[:mitglieder], Group::Mitglieder::OrdentlicheMitgliedschaft]],
    label: "Ordentliche Mitgliedschaft",
    group: "Mitglieder (Stamm Fuchsbau)",
    purpose: "Self-Service-Ansicht ohne Rechte"
  }
]

testbenutzer.each do |entry|
  person = find_or_create_person(entry[:email],
    first_name: entry[:first_name], last_name: entry[:last_name],
    **entry.slice(:birthday, :gender))
  entry[:roles].each { |group, role_type| assign_role(person, group, role_type) }
  # Maßgeblich ist Hitobito selbst: der Root-Zugang ist von der Pflicht ausgenommen,
  # auch wenn seine Rolle sie grundsätzlich verlangt.
  entry[:two_fa] = person.reload.two_factor_authentication_enforced?
  entry[:person] = person
  log "  #{entry[:email]} – #{entry[:label]}"
end

# ---------------------------------------------------------------------------
# 5. Füllmitglieder, damit Listen und Screenshots nicht leer sind
# ---------------------------------------------------------------------------

section "Füllmitglieder"

seeder = PersonSeeder.new

# Füllt eine Gruppe auf die Zielanzahl auf. Der feste Zufallsstartwert sorgt dafür,
# dass bei jedem Lauf dieselben Namen entstehen – sonst wäre der Seed nicht idempotent.
def fill_group(seeder, group, role_type, target, random_seed)
  vorhanden = group.roles.with_inactive.where(type: role_type.sti_name).count
  fehlend = target - vorhanden
  return 0 if fehlend <= 0

  srand(random_seed)
  fehlend.times do
    attrs = seeder.standard_attributes(Faker::Name.first_name, Faker::Name.last_name)
      .merge(confirmed_at: Time.zone.now, country: "DE", zip_code: GERMAN_ZIP,
        payment_method: "invoice")
    # PersonSeeder vergibt Adressen unter hitobito.example.com. Diese Domain hat keinen
    # MX-Eintrag und wird von Hitobito beim Bearbeiten abgelehnt – example.com dagegen nicht.
    attrs[:email] = attrs[:email].sub("@hitobito.example.com", "@example.com")
    person = Person.seed(:email, attrs).first
    seeder.seed_role(person, group, role_type)
  end
  fehlend
end

staemme.each_with_index do |(stamm, teile), stamm_index|
  ergaenzt = fill_group(seeder, teile[:mitglieder],
    Group::Mitglieder::OrdentlicheMitgliedschaft, 8, 1312 + stamm_index)

  teile[:stufen].each_with_index do |(klass, stufengruppe), stufen_index|
    ergaenzt += fill_group(seeder, stufengruppe, klass::Mitglied, 4,
      4200 + stamm_index * 10 + stufen_index)
  end

  log "  #{stamm.name}: #{ergaenzt} Personen ergänzt."
end

# Beitragsart für alle Mitgliedschaftsrollen nachtragen, die über seed_once ohne
# Validierung angelegt wurden.
nachzutragen = Role.with_inactive
  .where(type: Role.types_with_fee_kind.map(&:sti_name), fee_kind_id: nil)
nachzutragen.find_each { |role| role.update(fee_kind: FeeKindChooser.new.default(role)) }
log "Beitragsart für #{nachzutragen.count} Rollen nachgetragen." if nachzutragen.any?

# ---------------------------------------------------------------------------
# 6. Zwei-Faktor-Authentisierung
# ---------------------------------------------------------------------------

section "Zwei-Faktor-Authentisierung"

testbenutzer.select { |entry| entry[:two_fa] }.each do |entry|
  person = entry[:person]
  person.two_fa_secret = TOTP_SECRET
  person.two_factor_authentication = :totp
  person.save!(validate: false)
  log "  #{entry[:email]}: gemeinsames Test-Secret gesetzt."
end

# ---------------------------------------------------------------------------
# 7. Ergebnis für das Startscript
# ---------------------------------------------------------------------------

testbenutzer.each do |entry|
  announce_user(entry[:key], entry[:email], entry[:label], entry[:group],
    entry[:two_fa], entry[:purpose])
end
# Tiefe aus der Eltern-Kette berechnen (awesome_nested_set kennt hier kein #depth).
# Bewusst über pluck statt über Modellinstanzen: in gewachsenen Entwicklungsdatenbanken
# stehen manchmal Gruppentypen aus anderen Wagons, die sich nicht mehr laden lassen.
depth_by_id = {}
Group.unscoped.order(:lft).pluck(:id, :parent_id, :name, :type).each do |id, parent_id, name, type|
  depth_by_id[id] = parent_id ? depth_by_id.fetch(parent_id, 0) + 1 : 0
  # Gruppen mit festem Namen (Mitglieder, Gruppen) haben in der Datenbank keinen Namen –
  # angezeigt wird die Bezeichnung des Gruppentyps.
  label = name.presence || type.safe_constantize&.label || type
  puts "SEED_TREE|#{"  " * depth_by_id[id]}#{label}"
end
puts "SEED_TOTP_SECRET|#{TOTP_SECRET}"
puts "SEED_PASSWORD|#{PASSWORD}"
puts "SEED_DONE|#{Group.count} Gruppen, #{Person.count} Personen, #{Role.with_inactive.count} Rollen"

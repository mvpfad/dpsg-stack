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
  # Der Setter vergleicht den neuen Wert mit dem alten und entschlüsselt diesen dafür.
  # Stammt die Datenbank aus einer Installation mit anderem Verschlüsselungsschlüssel –
  # der wird beim Klonen der Entwicklungsumgebung neu erzeugt –, schlägt das fehl.
  # Deshalb erst leeren, dann setzen.
  person.encrypted_two_fa_secret = nil
  person.two_fa_secret = TOTP_SECRET
  person.two_factor_authentication = :totp
  person.save!(validate: false)
  log "  #{entry[:email]}: gemeinsames Test-Secret gesetzt."
end

# ---------------------------------------------------------------------------
# 7. Qualifikationen, Kurskategorien und Kursarten
# ---------------------------------------------------------------------------

section "Qualifikationen und Kursarten"

# Bezeichnungen sind übersetzte Attribute und liegen in eigenen Tabellen. Gesucht wird
# deshalb über die Übersetzung, damit mehrfaches Ausführen nichts doppelt anlegt.
def find_or_build_translated(klass, attribute, value)
  klass.joins(:translations)
    .find_by(klass.translation_class.table_name => {attribute => value}) || klass.new
end

def seed_translated(klass, label, attrs = {})
  record = find_or_build_translated(klass, :label, label)
  record.assign_attributes(attrs.merge(label: label))
  record.save!
  record
end

quali_gruppenleitung = seed_translated(QualificationKind, "Gruppenleitung",
  description: "Abgeschlossene Ausbildung zur Gruppenleitung.",
  validity: nil)
quali_erste_hilfe = seed_translated(QualificationKind, "Erste Hilfe",
  description: "Erste-Hilfe-Ausbildung mit mindestens neun Unterrichtseinheiten.",
  validity: 3, reactivateable: 1)
quali_praevention = seed_translated(QualificationKind, "Präventionsschulung",
  description: "Schulung zur Prävention sexualisierter Gewalt.",
  validity: 5)
log "  Qualifikationsarten: Gruppenleitung, Erste Hilfe (3 Jahre), Präventionsschulung (5 Jahre)"

kategorie_ausbildung = seed_translated(Event::KindCategory, "Ausbildung", order: 1)
kategorie_erste_hilfe = seed_translated(Event::KindCategory, "Erste Hilfe", order: 2)
log "  Kurskategorien: Ausbildung, Erste Hilfe"

def seed_kind(label, attrs, qualifikationen)
  kind = seed_translated(Event::Kind, label, attrs)
  qualifikationen.each do |category, qualification_kind|
    Event::KindQualificationKind.find_or_create_by!(
      event_kind: kind, qualification_kind: qualification_kind,
      category: category.to_s, role: "participant"
    )
  end
  kind
end

kursart_gruppenleitung = seed_kind("Gruppenleitungskurs", {
  short_name: "GLK",
  kind_category: kategorie_ausbildung,
  minimum_age: 16,
  general_information: "Grundlagen der Gruppenarbeit: Methoden, Aufsicht, Spielpädagogik.",
  application_conditions: "Gültige Erste-Hilfe-Ausbildung."
}, qualification: quali_gruppenleitung, precondition: quali_erste_hilfe)

kursart_erste_hilfe = seed_kind("Erste-Hilfe-Kurs", {
  short_name: "EH",
  kind_category: kategorie_erste_hilfe,
  minimum_age: 14,
  general_information: "Neun Unterrichtseinheiten Erste Hilfe mit Outdoor-Teil.",
  application_conditions: nil
}, qualification: quali_erste_hilfe, prolongation: quali_erste_hilfe)

kursart_praevention = seed_kind("Präventionsschulung", {
  short_name: "PRÄ",
  kind_category: kategorie_ausbildung,
  minimum_age: 16,
  general_information: "Pflichtschulung für alle Leitenden.",
  application_conditions: nil
}, qualification: quali_praevention)
log "  Kursarten: GLK (Ausbildung), EH (Erste Hilfe), PRÄ (Ausbildung)"

# Qualifikationen für zwei Testbenutzer, damit Personenansichten und die App-Übersicht
# gültige, bald ablaufende und abgelaufene Einträge zeigen.
# Je Person und Art genau ein Eintrag; das Startdatum wird bei jedem Lauf nachgezogen,
# damit „läuft bald ab“ und „abgelaufen“ relativ zu heute stimmen.
def seed_qualification(person, kind, start_at, origin)
  qualification = Qualification.find_or_initialize_by(person: person, qualification_kind: kind)
  qualification.assign_attributes(start_at: start_at, finish_at: nil, origin: origin)
  qualification.save!
end

finn = Person.find_by!(email: "stammesfuehrung@example.com")
lea = Person.find_by!(email: "gruppenleitung@example.com")
heute = Time.zone.today
seed_qualification(finn, quali_gruppenleitung, Date.new(2019, 5, 12), "Gruppenleitungskurs")
seed_qualification(finn, quali_erste_hilfe, heute - 3.years + 2.months, "Erste-Hilfe-Kurs")
seed_qualification(finn, quali_praevention, Date.new(2023, 3, 4), "Präventionsschulung")
seed_qualification(lea, quali_erste_hilfe, heute - 3.years - 4.months, "Erste-Hilfe-Kurs")
log "  Finn: Gruppenleitung, Erste Hilfe (läuft in 2 Monaten ab), Prävention"
log "  Lea: Erste Hilfe (abgelaufen)"

# ---------------------------------------------------------------------------
# 8. Veranstaltungen und Kurse
# ---------------------------------------------------------------------------

section "Veranstaltungen und Kurse"

# Alle Termine liegen relativ zum Tag des Seedens, damit „kommende“ Events auch nach
# Wochen noch in der Zukunft liegen. Bei jedem Lauf werden die Termine neu gesetzt.
def um(tage, stunde, minute = 0)
  (Time.zone.today + tage).in_time_zone.change(hour: stunde, min: minute)
end

def seed_event(klass, name, group, attrs, termine)
  event = find_or_build_translated(klass, :name, name)
  event = klass.new if event.class != klass
  event.assign_attributes(attrs.merge(name: name))
  event.groups = [group]
  event.dates.destroy_all if event.persisted?
  termine.each { |termin| event.dates.build(termin) }
  event.save!
  event
end

def teilnehmen(event, person, role_type, active: true, application: nil)
  participation = Event::Participation.find_or_initialize_by(event: event, participant: person)
  if application && participation.application.nil?
    participation.application = Event::Application.create!(
      {priority_1_id: event.id}.merge(application)
    )
  end
  participation.active = active
  participation.save!
  unless participation.roles.exists?(type: role_type.sti_name)
    participation.roles.create!(type: role_type.sti_name)
  end
  participation.update_column(:active, active) # Rollen-Callback setzt sonst ggf. aktiv
  participation
end

dana = Person.find_by!(email: "dv-verwaltung@example.com")
bea = Person.find_by!(email: "bv-verwaltung@example.com")
mika = Person.find_by!(email: "mitglied@example.com")
adlerhorst = staemme[stamm_adlerhorst]

# Füllmitglieder in fester Reihenfolge als Kursteilnehmende.
testbenutzer_ids = testbenutzer.map { |entry| entry[:person].id }
fuellgruppen = [fuchsbau, adlerhorst].flat_map do |teile|
  [teile[:mitglieder].id] + teile[:stufen].values.map(&:id)
end
fuellmitglieder = Person.joins(:roles)
  .where(roles: {group_id: fuellgruppen})
  .where.not(id: testbenutzer_ids)
  .distinct.order(:id).to_a

# 1 – Stamm, eintägig, vollständig gepflegt
e1 = seed_event(Event, "Pfingstaktion Fuchsbau", stamm_fuchsbau, {
  motto: "Gemeinsam unterwegs",
  description: "Tagesaktion für alle Stufen mit Geländespiel und Grillen.",
  location: "Stammesheim Fuchsbau, Am Waldrand 12, 50321 Silberbach",
  cost: "5 €",
  contact: finn,
  application_opening_at: heute - 14,
  application_closing_at: heute + 10,
  applications_cancelable: true,
  globally_visible: true
}, [{label: "Aktionstag", start_at: um(14, 10), finish_at: um(14, 17), location: nil}])

# 2 – Stamm, mehrtägig mit zwei Terminen an verschiedenen Orten
e2 = seed_event(Event, "Sommerlager Fuchsbau", stamm_fuchsbau, {
  description: "Eine Woche Zeltlager für Wölflinge bis Rover*innen.",
  location: "Zeltplatz Silberwald",
  cost: "180 €",
  contact: finn,
  application_opening_at: heute - 30,
  application_closing_at: heute + 30,
  applications_cancelable: true,
  globally_visible: true
}, [
  {label: "Vorbereitungstreffen", start_at: um(21, 18), finish_at: um(21, 20),
   location: "Stammesheim Fuchsbau"},
  {label: "Lager", start_at: um(42, 14), finish_at: um(48, 12),
   location: "Zeltplatz Silberwald"}
])
teilnehmen(e2, mika, Event::Role::Participant)

# 3 – fremder Stamm, global sichtbar
seed_event(Event, "Kinoabend Adlerhorst", stamm_adlerhorst, {
  description: "Filmabend im Gemeindesaal, Gäste aus dem Bezirk willkommen.",
  location: "Gemeindesaal Adlerbach",
  application_opening_at: heute - 7,
  application_closing_at: heute + 18,
  globally_visible: true
}, [{label: "Kinoabend", start_at: um(20, 19), finish_at: um(20, 22), location: nil}])

# 4 – fremder Stamm, nicht global sichtbar
seed_event(Event, "Leiterrunde Adlerhorst", stamm_adlerhorst, {
  description: "Interne Planungsrunde der Leitenden.",
  location: "Stammesheim Adlerhorst",
  globally_visible: false
}, [{label: "Leiterrunde", start_at: um(9, 19, 30), finish_at: um(9, 21, 30), location: nil}])

# 5 – Bezirkskurs, Anmeldung offen, freie Plätze, Leitung und Anmeldefragen
e5 = seed_event(Event::Course, "Gruppenleitungskurs Bezirk Silberbach", bezirk, {
  kind: kursart_gruppenleitung,
  number: "GLK-SB-1",
  description: "Zwei Wochenenden Ausbildung für neue Leitende im Bezirk.",
  location: "Jugendhaus Silberbach",
  cost: "60 € inkl. Verpflegung",
  contact: finn,
  maximum_participants: 12,
  application_opening_at: heute - 20,
  application_closing_at: heute + 25,
  applications_cancelable: true,
  participations_visible: true,
  globally_visible: true
}, [
  {label: "Wochenende 1", start_at: um(35, 18), finish_at: um(37, 14), location: nil},
  {label: "Wochenende 2", start_at: um(49, 18), finish_at: um(51, 14), location: nil}
])
if e5.application_questions.none?
  e5.application_questions.create!(question: "Hast du Unverträglichkeiten oder Allergien?",
    required: false)
  e5.application_questions.create!(question: "Übernachtest du vor Ort?",
    choices: "Ja,Nein", required: true)
end
teilnehmen(e5, finn, Event::Role::Leader)
fuellmitglieder.first(4).each do |person|
  teilnehmen(e5, person, Event::Course::Role::Participant, application: {approved: true})
end
teilnehmen(e5, mika, Event::Course::Role::Participant, active: false, application: {})

# 6 – Diözesankurs, Anmeldung öffnet erst später
seed_event(Event::Course, "Erste-Hilfe-Kurs Diözese Sonnenstein", diozesanverband, {
  kind: kursart_erste_hilfe,
  number: "EH-DV-1",
  description: "Erste Hilfe mit Schwerpunkt Lager und Fahrt.",
  location: "Diözesanzentrum Sonnenstein",
  cost: "25 €",
  maximum_participants: 16,
  application_opening_at: heute + 21,
  application_closing_at: heute + 60,
  globally_visible: true
}, [{label: "Kurstag", start_at: um(75, 9), finish_at: um(75, 17), location: nil}])

# 7 – Diözesankurs, Anmeldeschluss vorbei, ausgebucht, Warteliste
e7 = seed_event(Event::Course, "Präventionsschulung Diözese Sonnenstein", diozesanverband, {
  kind: kursart_praevention,
  number: "PRÄ-DV-1",
  description: "Präventionsschulung für Leitende aller Stufen.",
  location: "Online",
  maximum_participants: 10,
  waiting_list: true,
  application_opening_at: heute - 60,
  application_closing_at: heute - 5,
  globally_visible: true
}, [{label: "Schulung", start_at: um(14, 10), finish_at: um(14, 16), location: nil}])
teilnehmen(e7, dana, Event::Role::Leader)
fuellmitglieder.drop(4).first(10).each do |person|
  teilnehmen(e7, person, Event::Course::Role::Participant, application: {approved: true})
end
fuellmitglieder.drop(14).first(2).each do |person|
  teilnehmen(e7, person, Event::Course::Role::Participant, active: false,
    application: {waiting_list: true})
end

# 8 – Bundeskurs mit externer Anmeldung
seed_event(Event::Course, "Bundeskurs Gruppenleitung", bundesebene, {
  kind: kursart_gruppenleitung,
  number: "GLK-BUND-1",
  description: "Bundesweiter Kurs, Anmeldung auch ohne bestehendes Konto möglich.",
  location: "Bundeszentrum Westernohe",
  cost: "120 €",
  contact: bea,
  maximum_participants: 20,
  external_applications: true,
  application_opening_at: heute - 10,
  application_closing_at: heute + 40,
  globally_visible: true
}, [{label: "Kurswoche", start_at: um(60, 15), finish_at: um(64, 13), location: nil}])

# 9 – Bezirk, nur Pflichtfelder (Leerzustände)
seed_event(Event, "Bezirksversammlung Silberbach", bezirk, {
  globally_visible: true
}, [{label: nil, start_at: um(28, 19), finish_at: um(28, 21, 30), location: nil}])

# 10 – Stamm, bereits vorbei
seed_event(Event, "Waldputzaktion Fuchsbau", stamm_fuchsbau, {
  description: "Müllsammeln im Silberwald.",
  location: "Parkplatz Silberwald",
  globally_visible: true
}, [{label: "Aktion", start_at: um(-30, 9), finish_at: um(-30, 13), location: nil}])

Event.find_each(&:refresh_participant_counts!)
log "  10 Events: 6 Veranstaltungen, 4 Kurse (Stamm, Bezirk, Diözese, Bund)"
log "  Mika: Teilnahme Sommerlager, offene Bewerbung Gruppenleitungskurs"

# ---------------------------------------------------------------------------
# 9. OAuth-Anwendung für lokale App-Entwicklung
# ---------------------------------------------------------------------------

section "OAuth-Anwendung"

# Feste Zugangsdaten, nur lokal gültig – wie das TOTP-Secret oben. Damit kann die
# NaMi-App ohne Einrichtung gegen http://localhost:3000 entwickelt werden.
OAUTH_UID = "nami-app-lokal"
OAUTH_SECRET = "nami-app-lokal-secret"

oauth_app = Oauth::Application.find_or_initialize_by(uid: OAUTH_UID)
oauth_app.assign_attributes(
  name: "NaMi App lokal",
  secret: OAUTH_SECRET,
  redirect_uri: "de.jlange.nami.app:/oauth/callback",
  scopes: "openid name email api with_roles",
  confidential: true,
  skip_consent_screen: true
)
oauth_app.save!
log "  #{oauth_app.name}: Client-ID #{OAUTH_UID}, Secret #{OAUTH_SECRET}"

# ---------------------------------------------------------------------------
# 10. Ergebnis für das Startscript
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
puts "SEED_DONE|#{Group.count} Gruppen, #{Person.count} Personen, #{Role.with_inactive.count} Rollen, " \
  "#{Event.count} Veranstaltungen"

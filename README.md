<!-- Inhaltsgleich mit dokumentation/dpsg/docs/entwicklung/hitobito-stack-aufsetzen.md
     im Repository mvpfad/dokumentation – Änderungen bitte dort nachziehen. -->

# NaMi 3.0 – Hitobito Stack lokal aufsetzen

Dieses Repository bringt dir die komplette Mitgliederverwaltung der DPSG (NaMi 3.0) auf deinen eigenen Rechner – mit Testdaten, verschiedenen Benutzer*innen und allen Funktionen. Du brauchst dafür **kein Ruby, kein Rails und keine Docker-Kenntnisse**. Ein Befehl genügt:

```sh
git clone https://github.com/mvpfad/dpsg-stack.git
cd dpsg-stack
./start-dpsg-stack.sh --seed
```

Danach kannst du gefahrlos ausprobieren, Fehler nachstellen, Screenshots für die Doku machen oder selbst entwickeln. Es ist deine eigene Spielwiese: Was du dort anstellst, hat keinerlei Auswirkung auf die echte Mitgliederverwaltung.

## Inhalt

- [Woraus besteht die Mitgliederverwaltung?](#woraus-besteht-die-mitgliederverwaltung)
- [Was du brauchst](#was-du-brauchst)
- [In drei Schritten starten](#in-drei-schritten-starten)
- [Was du danach siehst](#was-du-danach-siehst)
- [Die Testbenutzer](#die-testbenutzer)
- [Anmelden mit zweitem Faktor](#anmelden-mit-zweitem-faktor)
- [Die Testdatenstruktur](#die-testdatenstruktur)
- [Alle Befehle](#alle-befehle)
- [Auf einem neueren Stand arbeiten](#auf-einem-neueren-stand-arbeiten)
- [Mehrere Stacks nebeneinander](#mehrere-stacks-nebeneinander)
- [E-Mails anschauen](#e-mails-anschauen)
- [Wenn etwas nicht klappt](#wenn-etwas-nicht-klappt)
- [Eigene Testdaten ergänzen](#eigene-testdaten-ergänzen)
- [Den Stack woanders ablegen](#den-stack-woanders-ablegen)

## Woraus besteht die Mitgliederverwaltung?

Die Mitgliederverwaltung ist kein einzelnes Programm, sondern setzt sich aus drei Teilen zusammen. Sie werden beim Einrichten automatisch heruntergeladen und zusammengesetzt:

| Teil | Was drinsteckt |
|---|---|
| [Hitobito Core](https://github.com/hitobito/hitobito) | Die Kernsoftware: Personen, Gruppen, Rechte, Veranstaltungen, Rechnungen |
| [Pfadi-DE-Wagon](https://github.com/hitobito/hitobito_pfadi_de) | Alles, was deutsche Pfadfinder*innenverbände gemeinsam brauchen: Stämme, Stufen, Führungszeugnisse, Beiträge |
| [DPSG-Wagon](https://github.com/hitobito/hitobito_dpsg) | Das DPSG-Besondere: Biber und Jungpfadfinder*innen, unsere Bezeichnungen, unsere Testdaten |

„Wagon" ist dabei das Hitobito-Wort für eine Erweiterung – wie ein Waggon, der an den Zug angehängt wird.

## Was du brauchst

- **Docker Desktop** – das Programm, das die Mitgliederverwaltung in abgeschotteten Behältern („Containern") laufen lässt. [Herunterladen](https://www.docker.com/products/docker-desktop/) und einmal starten.
- **Git** – zum Herunterladen des Quellcodes. Auf macOS ist es nach `xcode-select --install` dabei, sonst [hier](https://git-scm.com/downloads).
- **Rund 20 GB freien Speicherplatz** und mindestens **8 GB Arbeitsspeicher**, die Docker nutzen darf.
- **macOS oder Linux.** Unter Windows funktioniert es über das Windows-Subsystem für Linux (WSL2).

> [!NOTE]
> **Wie lange dauert das?** Beim allerersten Mal 15 bis 30 Minuten. In dieser Zeit wird der Quellcode heruntergeladen und die Anwendung gebaut. Das läuft von allein – du kannst in der Zwischenzeit etwas anderes machen. Jeder weitere Start dauert dann nur noch ein bis zwei Minuten.
>
> Auf Macs mit Apple-Chip (M1 bis M4) laufen die Hitobito-Images über eine Übersetzungsschicht, weil es sie nur für Intel-Prozessoren gibt. Rechne dort eher mit dem oberen Ende der Zeitangabe.

## In drei Schritten starten

**1. Dieses Repository herunterladen**

```sh
git clone https://github.com/mvpfad/dpsg-stack.git
```

**2. In den Ordner wechseln**

```sh
cd dpsg-stack
```

**3. Starten**

```sh
./start-dpsg-stack.sh --seed
```

Das war's. `--seed` bedeutet: „und leg bitte gleich Testdaten an".

> [!WARNING]
> **Docker muss laufen.** Wenn die Meldung „Docker läuft nicht" erscheint, starte zuerst Docker Desktop und warte, bis das Wal-Symbol oben in der Menüleiste ruhig ist. Dann den Befehl erneut ausführen.

## Was du danach siehst

Am Ende steht alles Wichtige im Terminal:

```text
[1/5] Voraussetzungen prüfen
      ✓ Alles da.
[2/5] Hitobito herunterladen und einrichten (dauert einige Minuten)
      ✓ Quellen eingerichtet.
[3/5] Container starten
      ✓ Container laufen.
[4/5] Auf die Anwendung warten
      ✓ Anwendung ist erreichbar (nach 18 Minuten 4 Sekunden).
[5/5] Testdaten anlegen
      ✓ 27 Gruppen, 63 Personen, 64 Rollen

══════════════════════════════════════════════════════════════════════
  NaMi 3.0 – DPSG-Stack läuft
══════════════════════════════════════════════════════════════════════

  Mitgliederverwaltung  http://localhost:3000
  E-Mail-Postfach       http://localhost:1080

  Testdaten – Gruppenstruktur
    Bundesebene
      Arbeitsbereiche
      Bundesvorstand
      Diözesanverband Sonnenstein
        Arbeitsbereiche
        Diözesansvorstand
        Mitglieder
        Bezirk Silberbach
          Stamm Adlerhorst
            Gruppen
              Biber Adlerhorst
              …
            Mitglieder
          Stamm Fuchsbau
            Gruppen
              Biber Fuchsbau
              …
            Mitglieder
      Mitglieder
      Ombudsrat
      Projekte

  Testbenutzer – Passwort für alle: hito42bito

    E-Mail                            Rolle                           2FA  Ebene
    ────────────────────────────────────────────────────────────────────────────
    hitobito-dpsg@puzzle.ch           Bundes-MV-Admin                 nein Bundesebene
    bv-verwaltung@example.com         Bundes-MV-Admin                 ja   Bundesebene
    dv-verwaltung@example.com         DV-Mitgliederverwaltung + eFZ   ja   Diözesanverband Sonnenstein
    …

  Anmeldung mit zweitem Faktor
    Gerade gültig: 412 905  (noch 18 Sekunden)
```

Öffne jetzt **http://localhost:3000** im Browser.

## Die Testbenutzer

Alle Testbenutzer haben dasselbe Passwort: **`hito42bito`**. Sie unterscheiden sich in dem, was sie sehen und dürfen – damit du jede Perspektive ausprobieren kannst.

| E-Mail | Rolle | Sieht und darf | 2FA |
|---|---|---|---|
| `hitobito-dpsg@puzzle.ch` | Bundes-MV-Admin | Alles, inklusive Systemeinstellungen | – |
| `bv-verwaltung@example.com` | Bundes-MV-Admin | Alles sehen und ändern | ja |
| `dv-verwaltung@example.com` | DV-Mitgliederverwaltung + eFZ-Erfassung | Den ganzen Diözesanverband bearbeiten, Führungszeugnisse eintragen | ja |
| `bezirk-verwaltung@example.com` | Bezirkssprecher*in | Den Bezirk und alle Stämme darunter lesen | ja |
| `stammesverwaltung@example.com` | Stammesmitgliederverwaltung | Mitglieder im Stamm Fuchsbau anlegen und bearbeiten | ja |
| `stammesfuehrung@example.com` | Stammesführung | Den Stamm Fuchsbau lesen | – |
| `gruppenleitung@example.com` | Wölflingsleitung | Nur die eigene Stufengruppe | – |
| `mitglied@example.com` | Ordentliche Mitgliedschaft | Nur die eigenen Daten (Self-Service-Sicht) | – |

> [!TIP]
> **Nur kurz reinschauen?** Nimm `hitobito-dpsg@puzzle.ch` (sieht alles) oder `stammesfuehrung@example.com` (Sicht einer Stammesführung). Beide verlangen keinen zweiten Faktor, du kommst also mit E-Mail und Passwort direkt hinein. Der Hauptzugang `hitobito-dpsg@puzzle.ch` ist in Hitobito grundsätzlich von der 2FA-Pflicht ausgenommen.

## Anmelden mit zweitem Faktor

Rollen mit weitreichenden Rechten verlangen zusätzlich einen sechsstelligen Code, der sich alle 30 Sekunden ändert – genau wie in der echten Mitgliederverwaltung. Lokal teilen sich alle diese Testbenutzer denselben Code. Du hast zwei Möglichkeiten:

**Schnell:** Code im Terminal anzeigen lassen und abtippen.

```sh
./start-dpsg-stack.sh --code
```

**Dauerhaft:** einmal in einer Authenticator-App einrichten (zum Beispiel Google Authenticator, Microsoft Authenticator, 1Password oder iOS-Passwörter). Trage dort diese Adresse ein beziehungsweise scanne sie als QR-Code:

```text
otpauth://totp/NaMi3-Lokal?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=NaMi3
```

> [!WARNING]
> **Nur für lokal.** Dieser geheime Schlüssel steht öffentlich in diesem Repository und ist damit bewusst unsicher. Er gilt ausschließlich für deine lokale Spielwiese – niemals für echte Zugänge.

## Die Testdatenstruktur

Die Testdaten bilden eine kleine, aber vollständige DPSG-Struktur ab. Alle Namen sind frei erfunden:

```text
Bundesebene
└─ Diözesanverband Sonnenstein
   └─ Bezirk Silberbach
      ├─ Stamm Fuchsbau
      │  ├─ Mitglieder
      │  └─ Gruppen
      │     ├─ Biber Fuchsbau
      │     ├─ Wölflinge Fuchsbau
      │     ├─ Jungpfadfinder*innen Fuchsbau
      │     ├─ Pfadfinder*innen Fuchsbau
      │     └─ Rover*innen Fuchsbau
      └─ Stamm Adlerhorst
         ├─ Mitglieder
         └─ Gruppen
            └─ (dieselben fünf Stufen)
```

In jedem Stamm liegen ein paar erfundene Mitglieder, damit Listen und Übersichten nicht leer aussehen.

Zusätzlich legt Hitobito auf jeder Ebene von sich aus die üblichen Standardgruppen an – auf Bundesebene etwa *Bundesvorstand*, *Ombudsrat*, *Projekte* und *Arbeitsbereiche*. Sie tauchen in der Oberfläche auf, sind aber leer.

> [!NOTE]
> **Verwirrend beim Blick in den Code:** Was in der Oberfläche **Diözesanverband** heißt, trägt im Programmcode den Namen `Group::Landesverband`. Der Pfadi-DE-Wagon ist für mehrere Verbände gedacht, der DPSG-Wagon benennt die Ebene nur in der Anzeige um. Wenn du also im Code nach `Diozesanverband` suchst, findest du nichts – such nach `Landesverband`.

## Alle Befehle

| Befehl | Was er macht |
|---|---|
| `./start-dpsg-stack.sh --seed` | Einrichten, starten und Testdaten anlegen |
| `./start-dpsg-stack.sh --start` | Nur starten, vorhandene Daten bleiben unberührt |
| `./start-dpsg-stack.sh --update` | Hitobito auf eine neuere Version heben, Daten behalten |
| `./start-dpsg-stack.sh --reset` | Datenbank leeren und Testdaten frisch anlegen |
| `./start-dpsg-stack.sh --reinstall` | Alles löschen und von vorn herunterladen |
| `./start-dpsg-stack.sh --stop` | Container anhalten |
| `./start-dpsg-stack.sh --status` | Zeigt Versionen, Container und Testbenutzer |
| `./start-dpsg-stack.sh --logs` | Protokoll mitlesen (beenden mit `Strg+C`) |
| `./start-dpsg-stack.sh --code` | Aktuellen Code für die Zwei-Faktor-Anmeldung |

Ohne Angabe zeigt das Programm diese Übersicht und den aktuellen Zustand.

## Auf einem neueren Stand arbeiten

An Hitobito wird laufend weiterentwickelt. Mit einem Befehl holst du dir den neuen Stand, **ohne deine Testdaten zu verlieren**:

```sh
./start-dpsg-stack.sh --update
```

Dabei passiert Folgendes: Zuerst wird automatisch eine Sicherung deiner Datenbank unter `hitobito_testing/dumps/` abgelegt. Dann werden Core und beide Wagons aktualisiert, die Datenbank wird auf den neuen Stand gebracht und die Anwendung neu gestartet. Am Ende siehst du, welche Version sich geändert hat.

Manchmal passt eine neue Hitobito-Version nicht mehr zu alten Testdaten – dann startet die Anwendung nicht sauber. In dem Fall hilft:

```sh
./start-dpsg-stack.sh --reset
```

Kurz zum Merken:

- **`--update`** – neuer Programmstand, alte Daten
- **`--reset`** – gleicher Programmstand, frische Daten
- **`--reinstall`** – alles auf Anfang

## Mehrere Stacks nebeneinander

Die Container dieses Stacks heißen alle `nami3-dpsg-…`, zum Beispiel `nami3-dpsg-rails-1`. Dadurch kommen sie keiner anderen Hitobito-Installation auf demselben Rechner in die Quere – auch nicht bei der Datenbank.

> [!WARNING]
> **Gleichzeitig laufen geht trotzdem nicht.** Zwei Stacks können zwar nebeneinander *liegen*, aber nicht gleichzeitig *laufen*: Sie würden sich um dieselben Ports streiten. Halte den einen an, bevor du den anderen startest.

Brauchst du einen abweichenden Namen, etwa für einen zweiten Stack zum Vergleich:

```sh
DPSG_STACK_PROJECT=nami3-test DPSG_STACK_DIR=/pfad/zum/zweiten ./start-dpsg-stack.sh --seed
```

## E-Mails anschauen

Die lokale Mitgliederverwaltung verschickt keine echten E-Mails. Alles, was sie versenden würde – Einladungen, Passwort-Links, Benachrichtigungen – landet in einem Postfach im Browser:

**http://localhost:1080**

Praktisch, um zum Beispiel den Ablauf „Passwort vergessen" komplett durchzuspielen.

## Wenn etwas nicht klappt

**„Docker läuft nicht"**
Starte Docker Desktop und warte, bis es vollständig hochgefahren ist. Prüfen kannst du es mit `docker info`.

**„Diese Ports sind schon belegt"**
Ein anderes Programm benutzt bereits einen der benötigten Anschlüsse: 3000 (Anwendung), 1025 und 1080 (E-Mail-Postfach), 5432 (Datenbank) und 6379 (Zwischenspeicher). Finde heraus welches – zum Beispiel für Port 3000 mit `lsof -i :3000` – und beende es. Oft ist es ein zweiter Hitobito-Stack, den du mit `docker compose down` in dessen Ordner anhältst.

**„Die vorhandenen Datenbankdateien passen nicht zur geforderten PostgreSQL-Version"**
Hitobito hat die PostgreSQL-Version gewechselt. Alte Datenbankdateien lassen sich damit nicht weiterverwenden. Da es ohnehin nur Testdaten sind, baust du sie einfach neu auf:

```sh
./start-dpsg-stack.sh --reset
```

**Der erste Start dauert ewig**
Das ist normal: Gems und Oberfläche werden einmalig gebaut. Mit `./start-dpsg-stack.sh --logs` siehst du in einem zweiten Terminal, woran gerade gearbeitet wird. Reicht die Zeit nicht, gib mehr davon:

```sh
DPSG_STACK_TIMEOUT=5400 ./start-dpsg-stack.sh --seed
```

**„Die Testdaten konnten nicht angelegt werden"**
Meist ist die Datenbank in einem halben Zustand. `./start-dpsg-stack.sh --reset` baut sie sauber neu auf. Beachte außerdem: Hitobito prüft beim Speichern jeder E-Mail-Adresse, ob die Domain überhaupt Mails empfangen kann. Dafür braucht der Rechner beim Seeden eine Internetverbindung.

**Die Anwendung ist weiß oder zeigt einen Fehler**
Häufig fehlt noch die gebaute Oberfläche. Schau mit `--logs`, ob der Asset-Build durchgelaufen ist, und warte gegebenenfalls noch etwas.

**Rechteprobleme unter Linux**
Wenn Dateien im Ordner `hitobito_testing` dem falschen Benutzer gehören, hilft:

```sh
sudo chown -R "$USER" hitobito_testing
```

**Ich will einfach von vorn anfangen**

```sh
./start-dpsg-stack.sh --reinstall
```

Das löscht alles Heruntergeladene und baut es neu auf – inklusive Rückfrage, damit das nicht aus Versehen passiert.

## Eigene Testdaten ergänzen

Die Testdaten entstehen aus einer einzigen Datei:

```text
seeds/nami3_seed.rb
```

Sie ist in Ruby geschrieben und so aufgebaut, dass du Gruppen, Personen und Rollen leicht ergänzen kannst. Nach einer Änderung:

```sh
./start-dpsg-stack.sh --seed
```

Die Datei ist so geschrieben, dass mehrfaches Ausführen nichts doppelt anlegt. Wer stattdessen einen völlig sauberen Stand will, nimmt `--reset`.

> [!NOTE]
> **Eine Datei für alle.** Dieselben Testdaten werden auch für die automatisch erzeugten Screenshots der Nutzerdokumentation genutzt. Wenn du Gruppen umbenennst oder Benutzer entfernst, kann das die Screenshot-Automatisierung betreffen.

## Den Stack woanders ablegen

Standardmäßig legt das Programm die Hitobito-Quellen neben sich selbst ab, in `hitobito_testing/`. Hast du sie schon an anderer Stelle liegen, verweise einfach darauf:

```sh
DPSG_STACK_DIR=/pfad/zu/hitobito_testing ./start-dpsg-stack.sh --seed
```

So sparst du dir das erneute Herunterladen mehrerer Gigabyte.

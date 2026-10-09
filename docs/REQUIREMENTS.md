# Cluster-Anforderungen

Was dieser Cluster leisten soll, welche Entscheidungen fest sind, und wo
die Grenzen bewusst gezogen wurden. Alles hier ist eine Entscheidung —
nicht nur eine Beschreibung des aktuellen Zustands. Wenn etwas im
Betrieb anders aussieht als hier beschrieben, dann ist entweder das Doc
oder der Cluster falsch; beides zu ignorieren ist nicht die Antwort.

Für Betriebsanleitungen siehe `CLAUDE.md` und die Runbooks in `docs/`.

---

## 1. Zweck

Ein Single-Cluster-Homelab für einen kleinen, geschlossenen Nutzerkreis
(Familie, ~5–10 Personen). Es muss drei Dinge leisten:

- **Daten unter eigener Kontrolle**: Fotos, Dateien, Passwörter, Medien,
  Dokumente, Finanzdaten liegen hier, nicht bei Dritten.
- **Ein Login für alles**: Benutzer werden einmal in Authentik angelegt
  und melden sich damit an jeder App an. Separate App-Konten sind der
  Notfall-Zugang, nicht der primäre.
- **Deklarativ betrieben**: der komplette Cluster-Zustand liegt in
  diesem Repo. Jede Änderung geht durch Git → Flux. Direkter
  `kubectl apply` ist für Troubleshooting, nicht für Konfiguration.

Netzwerk: Betrieb primär im LAN unter `*.passer.lan`, Fernzugriff
ausschließlich über Tailscale. Keine Dienste direkt im öffentlichen
Internet.

---

## 2. Nicht-Ziele

- Keine Hochverfügbarkeit. Ein Worker-Reboot darf einzelne Apps
  vorübergehend offline nehmen; das wird nicht durch Replikas
  kompensiert.
- Keine Multi-Tenant-Trennung über Namespaces hinaus — ein
  Nutzerkreis, ein Vertrauensbereich.
- Keine Compliance-Anforderungen (SOC2, DSGVO-Audit-Trail,
  Nachweispflichten). Die rechtliche Verantwortung bleibt beim
  Betreiber.
- Kein Reverse-Proxy ins öffentliche Internet. Dienste erreichen
  Nicht-LAN-Nutzer nur über Tailscale.
- Keine automatische Cloud-Replikation. Backups liegen auf dem
  lokalen MinIO (`passer`, 192.168.178.2).

---

## 3. Dienste-Katalog

| Dienst            | Zweck                       | Priorität | Verlust tolerierbar?                     |
|-------------------|-----------------------------|-----------|------------------------------------------|
| Authentik         | Identity Provider           | kritisch  | nein — alles hängt davon ab              |
| Nextcloud         | Dateien, Kalender, Kontakte | hoch      | nein (Velero daily)                      |
| Immich            | Foto-Backup, Bibliothek     | hoch      | nein (Velero daily)                      |
| Paperless-ngx     | Dokumenten-Archiv           | hoch      | nein (Velero daily)                      |
| Vaultwarden       | Passwort-Manager            | hoch      | nein (zusätzlich eigenes Export-Backup)  |
| Finance (Findash) | Finanz-Dashboard            | mittel    | nein (Velero daily, sobald real)         |
| Jellyfin          | Medien-Streaming            | mittel    | ja — Medien, nicht Nutzerdaten           |
| Longhorn UI       | Storage-Administration      | mittel    | — (reines Admin-Tool)                    |
| passer-home       | Landing-Seite + Doc-Browser | niedrig   | — (statisch, aus Repo generiert)         |
| Podinfo           | Routing-/TLS-Smoketest      | niedrig   | — (demo)                                 |

Was gehostet wird, ändert sich. Diese Tabelle sagt was heute
dazugehört, nicht was in Zukunft nie dazukommen darf. Neue Dienste
müssen hier eingetragen werden, bevor sie als „produktiv" gelten.

---

## 4. Authentifizierung mit Authentik

### 4.1 Prinzip

Authentik ist die **einzige** Quelle für Benutzer-Identitäten. Jede App,
die SSO beherrscht, bekommt es. Jede App, die es nicht beherrscht,
wird so gestellt, dass der Login im Betrieb trotzdem über Authentik
geht — mit genau einer Ausnahme (siehe §4.4).

**Login-Faktor: WebAuthn mit Hardware-Security-Key (YubiKey), ohne
Passwort.** Nutzer tippen ihren Benutzernamen ein und tappen den
YubiKey; das ist der einzige Faktor. Es gibt keine Passwort-Felder,
keine TOTP-Secrets, keine Recovery-Codes. Siehe §4.5 für die
Faktoren-Policy und §4.6 für die Flow-Konfiguration.

### 4.2 Integrations-Pfade

Drei Pfade, nach abfallender Präferenz:

1. **Native OIDC/OAuth**: Die App redet direkt mit Authentik als IdP.
   Berechtigung über Authentik-Gruppen; die App bekommt den User und
   seine Gruppen im Token.
2. **Forward-Auth über Envoy + Authentik Proxy-Outpost**: Envoy
   delegiert jeden Request vor Erreichen der App an einen
   Authentik-Outpost. Die App sieht nur authentifizierte Requests und
   bekommt User-Infos als Header geliefert. Für Admin-UIs und Apps
   ohne OIDC, die *kein* separates native Login-UI brauchen.
3. **Native-only**: Die App regelt Login selbst, Authentik ist nicht
   davor. Explizit zu vermeiden; einzige Ausnahme in §4.4.

### 4.3 Status pro App

| App           | Pfad          | Hinweis                                                       |
|---------------|---------------|---------------------------------------------------------------|
| Authentik     | —             | *ist* der IdP                                                 |
| Nextcloud     | native OIDC   | `user_oidc` App, Konfig siehe `docs/AUTHENTIK-SSO.md`; + app-pw für CalDAV/WebDAV und Desktop-Sync |
| Immich        | native OIDC   | Admin-UI-Paste bei Erstsetup (CLAUDE.md §12); Mobile nutzt eingebetteten Browser → WebAuthn direkt |
| Paperless-ngx | native OIDC   | Chart-Values + Blueprint                                      |
| Findash       | native OIDC   | muss im Image implementiert werden                            |
| Jellyfin      | native OIDC   | SSO-Auth Plugin (CLAUDE.md §12); Mobile-Apps + app-pw         |
| Longhorn UI   | Forward-Auth  | Admin-Tool, nur `admins`-Gruppe                               |
| Vaultwarden   | **Native-only** | siehe §4.4                                                  |
| passer-home   | öffentlich    | reine Landing-Seite                                           |
| Podinfo       | öffentlich    | Smoketest                                                     |

### 4.4 Die Ausnahme: Vaultwarden

Vaultwarden hat keinen nativen OIDC-Support, und ein Forward-Auth
davor würde die Mobile-App, die Browser-Extension und die
Desktop-Clients brechen — die können kein ForwardAuth sprechen und
wären damit unbenutzbar. Ein Passwort-Manager ohne Mobile ist kein
Passwort-Manager.

**Entscheidung**: Vaultwarden läuft ohne Authentik davor. Jeder
Nutzer braucht dort einmalig ein eigenes Konto. Die Admin-Rolle
registriert neue Nutzer, Self-Signup bleibt aus. Das Vaultwarden-
Master-Passwort ist das einzige Passwort, das ein Nutzer sich
merken muss; mit ihm liegen die App-Passwörter aus §4.7 im Tresor.

Wenn upstream Vaultwarden irgendwann natives OIDC/SAML bekommt oder
der `timshel/vaultwarden`-Fork fest etabliert ist, wird diese
Entscheidung neu bewertet.

### 4.5 Faktoren-Policy

- **Einziger Faktor für den Browser-Login**: WebAuthn-Credential auf
  einem Hardware-Security-Key (YubiKey). Modus: **non-resident**
  (klassisches WebAuthn), nicht Passkey/resident. Der Nutzer tippt
  seinen Benutzernamen, Authentik fordert den Tap an, fertig.
- **Zwei Keys pro Nutzer, verpflichtend.** Der zweite Key bleibt
  offline aufbewahrt (Schublade zuhause, Safe, Bankfach). Enrollment
  eines Users gilt erst als abgeschlossen, wenn zwei verschiedene
  WebAuthn-Credentials registriert sind.
- **Kein Passwort-Fallback und keine Recovery-Codes.** Beide wären
  langlebige Geheimnisse, die den Vorteil der Hardware wieder
  aushebeln.
- **Kein TOTP, kein SMS, kein E-Mail-Code.** Die Kette ist nur so
  stark wie ihr schwächstes Glied.
- **Verlust beider Keys = Konto-Wiederherstellung durch Admin aus
  Backup bzw. Neu-Enrollment nach persönlicher Identitäts­prüfung.**
  Es gibt keinen Self-Service-Reset.

Für die `admins`-Gruppe gilt zusätzlich: Admins haben ihre YubiKeys
getrennt von ihren User-YubiKeys. Ein Admin-Login erfolgt in einem
dedizierten Browser-Profil oder einer Inkognito-Session; der normale
`users`-Login teilt sich keine Session mit `admins`-Rechten.

### 4.6 Authentik Flow-Konfiguration

Der eigentliche Login-Flow in Authentik hat drei Stages:

1. **Identification Stage** — Username only, kein Passwort-Feld.
   `password_stage` NICHT verbunden.
2. **Authenticator Validation Stage** — WebAuthn als einziges
   zugelassenes `device_classes`. TOTP, Static, Email, SMS, Duo
   explizit deaktiviert.
3. **User Login Stage** — setzt die Session.

Der Enrollment-Flow (für neue Nutzer oder zweites Device) hat:

1. **Authenticator WebAuthn Stage** — mit `user_verification: preferred`
   und ohne Resident-Key-Flag.
2. **Policy** nach dem Enrollment, die prüft, dass der User
   mindestens zwei WebAuthn-Devices hat; sonst wird der Flow nicht
   als abgeschlossen markiert.

Der `akadmin`-Bootstrap-User bekommt ebenfalls zwei YubiKeys. Nach
Erst-Login mit dem Bootstrap-Passwort (CLAUDE.md §12) werden die
Keys registriert und das Passwort unmittelbar deaktiviert
(`password` auf einen Zufallswert, der nirgends gespeichert wird).

### 4.7 App-Passwörter für Nicht-Browser-Clients

Protokoll-gebundene Clients (CalDAV/CardDAV/WebDAV in
Nextcloud-Sync, SMTP, IMAP, Immich-Mobile-Upload, Jellyfin-Native-
Apps, Nextcloud-Desktop-Sync wenn deren OIDC-Flow nicht greift)
können keinen WebAuthn-Dialog rendern. Für diese Fälle:

- Der Nutzer legt im jeweiligen App-Profil (Authentik-Account oder
  App-eigenes Account-Panel) ein App-Passwort pro Gerät an.
- Jedes App-Passwort ist lang, zufällig, nicht wiederverwendet und
  wird direkt in Vaultwarden abgelegt. Der Nutzer merkt sich keines
  davon.
- App-Passwörter sind pro Dienst, pro Gerät, pro Nutzer eindeutig.
  Verlust eines Geräts → Admin oder Nutzer widerruft genau dieses
  App-Passwort, nicht alle.
- Welche Dienste App-Passwörter ausgeben, wird pro App in der
  Status-Tabelle §4.3 markiert (`+ app-pw`).

Dort wo der Mobile-OIDC-Flow über eingebetteten Browser läuft
(Immich, Jellyfin SSO-Plugin, Nextcloud Mobile-App), wird WebAuthn
*direkt* benutzt — kein App-Passwort nötig. Die Policy für
App-Passwörter ist „nur, wenn OIDC über Browser nicht funktioniert".

### 4.8 Session-Policy

- **SSO-Session**: 12 Stunden Rolling-Renewal bei Aktivität. Nach
  12 h ohne Aktivität läuft die Session ab, der Nutzer wird zum
  Login-Flow umgeleitet.
- **App-Sessions** (die Cookie-Sessions in Nextcloud, Immich usw.):
  gelten so lange die SSO-Session gilt. Ablauf einer App-Session
  triggert einen stillen OIDC-Refresh gegen Authentik, der ohne
  neue User-Interaktion klappt, solange die SSO-Session noch da ist.
- **Logout**: ein Logout in Authentik beendet alle App-Sessions
  (Front-Channel-Logout, soweit die App es unterstützt — Nextcloud,
  Immich, Paperless tun das).
- **Admin-Session**: 2 Stunden, kein Rolling-Renewal. Admin-Zugriff
  muss aktiv wiederhergestellt werden.

---

## 5. Benutzer & Gruppen

- Nutzer werden **nur** in Authentik angelegt. Nicht in den Apps.
- Bootstrap-Admins jeder App (Nextcloud-Admin, Immich-Admin,
  Paperless-Superuser, Jellyfin-Admin, Authentik `akadmin`) existieren
  als Notfall-Zugang, werden nicht für Alltag genutzt und ihre
  Credentials liegen im Vaultwarden-Tresor der `admins`-Gruppe
  (nicht im normalen User-Tresor).
- **Enrollment-Prozess** für neue Nutzer:
  1. Admin legt User in Authentik an, Flag „Enrollment required".
  2. Nutzer bekommt einen einmaligen Enrollment-Link, zeitlich
     begrenzt (max. 24 h).
  3. Nutzer registriert zwei YubiKeys im Browser.
  4. Enrollment-Policy aus §4.6 markiert den User erst dann als
     aktiv, wenn beide Keys da sind.
  5. Admin fügt User den passenden Gruppen hinzu.
  6. Nutzer registriert sich einmalig in Vaultwarden mit einem
     starken Master-Passwort und speichert dort die App-Passwörter
     aus §4.7.
- Gruppen in Authentik, mindestens:
  - `admins` — Zugriff auf Longhorn UI, Authentik-Admin, administrative
    Flächen der Apps.
  - `users` — Nextcloud, Immich, Paperless, Jellyfin, Findash.
  - `family` — nur Jellyfin (und ggf. explizit freigeschaltete
    Nextcloud-Ordner).
- Jede OIDC- und Forward-Auth-Integration prüft auf die passende
  Gruppe. „In Authentik existieren" allein reicht nicht.

---

## 6. Netzwerk & Zugang

- Alle Services unter `*.passer.lan`. DNS: Pi-Hole forwarded nach
  CoreDNS (`192.168.178.241`), CoreDNS antwortet mit der Gateway-IP
  (`192.168.178.240`).
- TLS: ein selbstsigniertes Wildcard-Zertifikat
  (`passer-lan-tls`). LAN-Nutzer importieren die CA einmal in ihren
  Trust-Store, danach keine Browser-Warnungen mehr.
- **Externer Zugriff über Tailscale / Headscale.** Das Tailnet
  läuft selbst-gehostet auf dem VPS `aquila` (Headscale,
  `vpn.schloschi.com`), nicht gegen tailscale.com. Base-Domain für
  MagicDNS: `tail.schloschi.com`. Keine Portfreigaben am Heim-Router,
  keine öffentlichen DNS-Einträge für Services.
- **Findash** ist der erste Dienst, der *außerhalb des LAN*
  erreichbar ist — nicht als öffentlicher Hostname, sondern als
  Tailnet-Service `findash.tail.schloschi.com`. Siehe
  `docs/FINDASH-DEPLOY.md`. Netzwerk-Zugriff selbst ist der
  Zugangsschutz; Findash hat deshalb bewusst keine Auth-Schicht.
- Admin-Flächen (Longhorn UI, Authentik-Admin) sind nicht separat
  vom LAN abgeschottet — die Zugriffskontrolle läuft über Authentik
  und die `admins`-Gruppe, nicht über Netzwerk-Topologie.

---

## 7. Storage & Backups

- Primärstorage: Longhorn, Node-Pinning per Tags und StorageClasses
  (CLAUDE.md §7, `infrastructure/configs/longhorn-storage-classes.yaml`).
  Hintergrund: SSD-/NVMe-Workloads getrennt von Capacity-Workloads;
  Cross-Node-Replication kostet mehr, als sie bei Replica=1 bringt.
- Replica-Faktor: **1**. Verlust eines Workers bedeutet Verlust
  der dort gepinnten Volumes, bis zum nächsten Velero-Restore.
- Backups: Velero → MinIO auf `passer` (192.168.178.2). Täglich 03:00
  für die kritischen Namespaces (`nextcloud`, `immich`,
  `paperless-ngx`, `vaultwarden`, `authentik`). Vaultwarden
  zusätzlich: regelmäßiger Export des Vaults als zweite
  unabhängige Kopie.
- Medien-Daten (Jellyfin): kein Backup. Falls weg, lassen sich die
  Dateien neu rippen; es gibt keine Nutzerdaten in diesem Volume.

---

## 8. Betrieb

- Flux ist die einzige Quelle, die den Cluster-Zustand verändert.
  Entscheidungen werden als Git-Commit sichtbar.
- Direktes `kubectl apply`, `kubectl delete` oder Hand-Editieren von
  CRs ist für Notfälle (Flux blockiert, Longhorn-Admission-Webhook
  weigert sich, Pod stuck Terminating). Nach einem solchen Eingriff
  muss die Manifest-Lage so angepasst werden, dass Flux den
  gewünschten Zustand ohne Hand-Eingriff herstellen würde.
- Node-Verluste müssen aktiv aus den Manifesten entfernt werden
  (`infrastructure/configs/longhorn-node-labels.yaml`,
  betroffene StorageClasses, Node-Pinning in App-Values), sonst
  blockiert der Longhorn-Admission-Webhook die gesamte
  infra-configs-Kustomization (siehe CLAUDE.md §12).
- Secrets: SOPS mit age. Private Key liegt nur auf dem
  Betreiber-Rechner und im Cluster (`flux-system/sops-age`).

---

## 9. Grenzen & bekannte Risiken

- **Verlust beider YubiKeys** eines Nutzers: Nutzer kommt nicht
  mehr rein. Admin reaktiviert manuell nach Identitäts­prüfung,
  Nutzer enrollt neu. Verlust eines Admin-Keypaars: der zweite
  `admins`-User kann den ersten freischalten; wenn alle `admins`-
  Keys verloren sind, hilft nur der direkte Zugriff auf den
  `authentik`-Pod und ein manueller `set_password`-Reset auf
  `akadmin` (CLAUDE.md §12), danach Neuaufbau der Admin-Keys.
- **Vaultwarden ohne SSO**: akzeptiert, siehe §4.4.
- **Immich OAuth-Config nur im Admin-UI** pastebar — das OIDC-Secret
  liegt zwar als Secret im Manifest, aber der Admin muss es einmal
  im UI eintragen. Infrastructure-as-Code deckt diesen letzten
  Schritt nicht ab.
- **Jellyfin SSO-Plugin manuell** zu installieren.
- **Replica=1**: Verlust eines Workers mit dedizierten Daten = Daten
  weg, bis Velero-Restore. Praktisch passiert mit Verlust von
  `talos-8bp-pih` 2026-10-02 (Capacity/Media/Backup-Tier) — Medien
  und Vaultwarden-Volume sind daher aktuell nicht am gewohnten
  Platz; Wiederanlauf siehe Betriebs-Runbook.
- **Longhorn-Admission-Webhook**: empfindlich bei NotReady-Nodes und
  Ghost-CRs. Erfordert disziplinierte Pflege der Node-Manifeste.
- **Authentik `akadmin`-Bootstrap-Passwort** steht nur in den
  Server-Pod-Logs beim allerersten Install. Danach manuell neu
  setzen (CLAUDE.md §12) und ablegen.

---

## 10. Wenn etwas neu dazukommen soll

Vor jeder neuen App-Aufnahme sind drei Fragen zu beantworten, und die
Antwort ist Teil des PRs, der die App einführt:

1. **Welchen Pfad zur Authentik-Integration geht sie?** (§4.2)
2. **Welche Gruppe darf sie benutzen?** (`admins`, `users`, `family`
   oder neu)
3. **Was passiert bei Verlust?** (Datenverlust tolerierbar, Backup
   nötig, Node-Pinning erforderlich)

Keine App ohne diese drei Antworten in Produktion.

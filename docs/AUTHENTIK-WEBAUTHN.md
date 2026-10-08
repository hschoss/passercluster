# Authentik WebAuthn-only Login (passercluster)

Dieses Runbook führt den Umbau von Authentik auf die
WebAuthn-only-Login-Policy aus `docs/REQUIREMENTS.md §4.5–§4.8` durch.
Teilweise GitOps-Konfig (Groups + WebAuthn-Stage), die
Flow-Umstellung macht man einmal in der UI und exportiert sie
anschließend als Blueprint zurück ins Repo.

## Vorbedingungen

- Authentik läuft (`https://auth.passer.lan`).
- Zwei YubiKeys (FIDO2) liegen bereit, mindestens einer am Rechner.
- Browser mit WebAuthn-Support (Chrome, Firefox, Safari aktuell).
- Die `passer-lan` CA ist im Browser-Trust-Store (siehe `README.md`),
  sonst scheitert WebAuthn an der TLS-Warnung.

## Schritt 1 — Erst-Login als akadmin

Nach einem CNPG-Rebuild (wie zuletzt am 2026-10-09) wird `akadmin`
mit dem Passwort aus dem `authentik-credentials` Secret neu angelegt.
Hole dir das Passwort:

```bash
sops --decrypt apps/base/authentik/authentik-credentials.secret.yaml \
  | grep -E 'bootstrap-password|AUTHENTIK_BOOTSTRAP_PASSWORD'
```

Dann `https://auth.passer.lan` → Login:
- Username: `akadmin`
- Password: Wert aus Secret

**Lege das Password sofort im Vaultwarden-Tresor der `admins`-Gruppe
ab.** Es ist der einzige Weg zurück, falls alles schiefläuft.

## Schritt 2 — Zwei YubiKeys bei akadmin registrieren

In Authentik:
1. Oben rechts auf den User-Avatar → *User settings*.
2. Reiter *MFA Devices* → *Enroll* → *WebAuthn (passercluster)*.
3. Browser öffnet den WebAuthn-Dialog → YubiKey anstecken, Tap, PIN
   festlegen (falls erstes Mal), Namen vergeben (z. B.
   `akadmin-primary`).
4. Zweiten YubiKey anstecken, Vorgang wiederholen, Namen z. B.
   `akadmin-backup`.
5. Beide Keys in der Liste prüfen. Backup-Key kommt an einen sicheren
   Offline-Platz.

Das Blueprint `passercluster-webauthn-enroll` wird automatisch über
GitOps angelegt und erscheint hier als Enrollment-Option. Falls
nicht: Admin → *Flows & Stages* → *Stages* → sollte `passercluster-
webauthn-enroll` enthalten; Admin → *Directory* → *Users* → `akadmin`
→ Reiter *MFA Devices*.

## Schritt 3 — WebAuthn als einzigen Login-Faktor erzwingen

Hier wird die Default-Login-Flow-Konfiguration überschrieben.
**Nicht in einem anonymen Browser-Fenster machen, sonst sperrst du
dich aus, wenn ein Zwischenschritt scheitert.** Nebenbei im zweiten
Browser-Tab eingeloggt bleiben.

### 3.1 Authenticator-Validation-Stage auf WebAuthn-only

Admin → *Flows & Stages* → *Stages* → `default-authentication-mfa-
validation` (oder wie euer MFA-Validate-Stage heißt) → *Edit*:
- **Device classes**: nur `WebAuthn Authenticator` angehakt lassen.
  Alles andere (TOTP, Static, Email, SMS, Duo) abhaken.
- **Not configured action**: `configure` (leitet User mit 0 Devices
  auf den Enrollment-Flow um).
- **Configuration stages**: `passercluster-webauthn-enroll`.

### 3.2 Password-Stage aus dem Default-Login-Flow entfernen

Admin → *Flows & Stages* → *Flows* → `default-authentication-flow`
→ Reiter *Stage Bindings*:
- Finde das Binding für `default-authentication-password` (Password
  Stage).
- *Delete*. Oder, falls Löschen zu riskant: Policy
  "immer-ablehnen" dran binden, so dass der Pfad nie läuft.

Der Identification-Stage `default-authentication-identification`
bleibt stehen (`User fields: username, email` → okay). Das
`password_stage` dort auf *Keins* setzen (sonst zeigt die
Identifikation ein inline Password-Feld).

### 3.3 Enrollment-Policy für ≥ 2 Devices

Admin → *Customization* → *Policies* → `passercluster-require-two-
webauthn` (vom Blueprint angelegt) existiert bereits. An den
Enrollment-Flow binden:

Admin → *Flows & Stages* → *Flows* → `default-user-settings-flow`
oder `default-source-enrollment` → *Stage Bindings* → beim WebAuthn-
Enroll-Binding → *Edit* → Policies → `passercluster-require-two-
webauthn` auswählen → Save.

Wirkung: der Enrollment-Flow verlässt den WebAuthn-Stage erst,
wenn der Nutzer zwei bestätigte Devices hat.

### 3.4 Session-Dauer setzen

Admin → *Flows & Stages* → *Stages* → `default-authentication-login`
(User-Login-Stage) → *Edit*:
- **Session duration**: `hours=12`.
- **Terminate other sessions**: deaktiviert lassen (sonst kickt
  jeder neue Login die anderen Browser raus).

Für den Admin-Flow analog einen eigenen Stage anlegen mit
`hours=2` und *Terminate other sessions = on*.

## Schritt 4 — Flow als Blueprint exportieren und ins Repo

Nachdem die Konfig funktioniert:

Admin → *Flows & Stages* → *Flows* → `default-authentication-flow`
→ *Export* → speichern als `default-authentication-flow.yaml`.
Dasselbe für den Enrollment-Flow und die betroffenen Stages.

Dann:
1. In das Repo kopieren als
   `apps/base/authentik/webauthn-flow-blueprint.yaml` (plain, kein
   SOPS — ist keine Credential).
2. In `apps/base/authentik/kustomization.yaml` einfügen.
3. In `apps/base/authentik/release.yaml` als `subPath`-Mount neben
   `webauthn-policy-blueprint.yaml` hinzufügen.
4. Commit, push, Flux reconcile.

Danach kann die Konfig jederzeit durch Blueprint-Reload
wiederhergestellt werden; die UI-Klicks dürfen dann weg.

## Schritt 5 — Admin-Account trennen vom User-Account

- Lege einen zweiten Authentik-User für den Alltag an (eigener
  Browser-Profil, nicht `admins`-Gruppe).
- Benutze `akadmin` nur noch über ein dediziertes Browser-Profil
  oder eine Inkognito-Session (siehe REQUIREMENTS §4.5).
- Admin-Session-Dauer kurz halten.

## Rollback

Falls du dich ausgesperrt hast: Password-Stage zurück an den
Default-Flow binden und mit `akadmin`-Passwort einloggen.

Wenn `akadmin`-Passwort nicht mehr geht, der harte Reset über die
Pod-Shell:

```bash
kubectl -n authentik exec deploy/authentik-worker -- ak shell -c \
  "from authentik.core.models import User
u=User.objects.get(username='akadmin')
u.set_password('EIN-NEUES-STARKES-PASSWORT')
u.save()"
```

Danach erneut Schritt 1 beginnen.

## Known limits

- WebAuthn über Browser setzt eine Hostname + TLS-Session voraus,
  die dem WebAuthn RP ID genügt. Für `*.passer.lan` muss das
  RP ID der Authentik-Instanz `auth.passer.lan` sein — Default der
  Chart.
- Mobile-Clients, die keinen eingebetteten Browser für ihren
  OIDC-Flow haben (Vaultwarden-Mobile, teils Nextcloud-Sync-Clients
  mit DAV), nutzen App-Passwörter — siehe REQUIREMENTS §4.7.
- WebAuthn-Device-Export für Backup ist nicht möglich; deshalb der
  zweite physische Key.

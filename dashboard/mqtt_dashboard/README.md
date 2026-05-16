# ORION Ground Station — Flutter App

```
 ██████╗ ██████╗ ██╗ ██████╗ ███╗   ██╗
██╔═══██╗██╔══██╗██║██╔═══██╗████╗  ██║
██║   ██║██████╔╝██║██║   ██║██╔██╗ ██║
██║   ██║██╔══██╗██║██║   ██║██║╚██╗██║
╚██████╔╝██║  ██║██║╚██████╔╝██║ ╚████║
 ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝
        CUBESAT  GROUND  STATION
```

Application Flutter de monitoring temps-réel d'un CubeSat embarquant un ESP32, un capteur BMP180 (température / pression / altitude) et un potentiomètre simulant la batterie. Communication via MQTT over TLS (HiveMQ Cloud) et persistance dans Firebase Firestore.

---

## Sommaire

1. [Architecture](#architecture)
2. [Structure des fichiers](#structure-des-fichiers)
3. [Dépendances](#dépendances)
4. [Configuration Firebase](#configuration-firebase)
5. [Gestion d'état — Riverpod](#gestion-détat--riverpod)
6. [Layout responsive](#layout-responsive)
7. [Side Panel](#side-panel)
8. [Topics MQTT](#topics-mqtt)
9. [Firestore — schéma des données](#firestore--schéma-des-données)
10. [Sécurité et règles Firestore](#sécurité-et-règles-firestore)
11. [Lancer l'application](#lancer-lapplication)
12. [Problèmes connus et solutions](#problèmes-connus-et-solutions)

---

## Architecture

```
ProviderScope (main.dart)
│
├── mqttClientProvider      NotifierProvider<MqttServerClient?>
│     └─ connectionProvider  Provider<bool>  (dérivé)
│
├── telemetryProvider       NotifierProvider<TelemetryState>
│     • latest packet
│     • 4 séries historiques (60 pts max)
│     • historyMode flag
│
├── beaconProvider          NotifierProvider<BeaconState>
│     • mode / alive / remoteHold / packetCount
│
├── alertsProvider          NotifierProvider<List<AlertEntry>>
│     • alertes ESP + seuils Flutter
│
├── logProvider             NotifierProvider<List<String>>
│     • event log horodaté (max 100 lignes)
│
├── thresholdsProvider      NotifierProvider<AlertThresholds>
│     • seuils modifiables depuis le Side Panel
│
├── sessionsProvider        NotifierProvider<List<GroundSession>>
│     • sessions in-memory (incr. Firestore)
│
├── firestoreSessionsProvider   FutureProvider<List<Map>>
│     • 20 dernières sessions depuis Firestore
│
├── sessionPacketsProvider  FutureProvider.family<List<TelemetryPacket>, String>
│     • paquets d'une session spécifique
│
└── mqttListenerProvider    Provider<MqttListenerService>
      • orchestre tous les providers ci-dessus
      • publie les commandes MQTT
      • écrit dans Firestore
```

Flux d'un paquet HK :
```
ESP32 → HiveMQ (TLS 8883) → MqttListenerService._handleHK()
    ├─ telemetryProvider.addPacket()
    ├─ sessionsProvider.addPacketCount()
    ├─ _checkThresholds()  → alertsProvider si dépassement
    ├─ logProvider.add()
    └─ Firestore: sessions/{id}/packets/{auto}
```

---

## Structure des fichiers

```
lib/
├── main.dart                  ← Firebase init + ProviderScope + runApp
├── firebase_options.dart      ← Généré par flutterfire configure (NE PAS éditer)
├── app_colors.dart            ← Design tokens partagés (palette Grafana dark)
├── login_page.dart            ← Connexion MQTT + animation orbitale
├── mission_control_page.dart  ← Dashboard principal, layout responsive 3 modes
├── side_panel.dart            ← Panneau latéral (Drawer mobile / colonne desktop)
└── telemetry_service.dart     ← Providers Riverpod + MqttListenerService + Firestore
```

---

## Dépendances

```yaml
dependencies:
  flutter:
    sdk: flutter
  mqtt_client:       ^10.0.0   # MQTT TLS
  flutter_riverpod:  ^2.5.1    # Gestion d'état
  firebase_core:     ^2.27.0   # Firebase bootstrap
  cloud_firestore:   ^4.15.0   # Base de données
  fl_chart:          ^0.67.0   # Graphiques
  intl:              ^0.19.0   # Formatage dates
```

Installer :
```bash
flutter pub get
```

---

## Configuration Firebase

### Étape 1 — Créer le projet Firebase

1. Aller sur **https://console.firebase.google.com**
2. **Add project** → nom `orion-gs` → désactiver Google Analytics → **Create**

### Étape 2 — Ajouter Android

1. Cliquer l'icône **Android** dans la console
2. Renseigner le **package name** (trouvé dans `android/app/build.gradle` → `applicationId`)
   - Exemple : `com.votreprenom.orion_gs`
3. Télécharger **`google-services.json`**
4. Placer le fichier dans `android/app/google-services.json`
5. Dans `android/build.gradle` → bloc `dependencies {}` :
   ```gradle
   classpath 'com.google.gms:google-services:4.4.1'
   ```
6. En bas de `android/app/build.gradle` :
   ```gradle
   apply plugin: 'com.google.gms.google-services'
   ```

### Étape 3 — FlutterFire CLI (génère firebase_options.dart)

```bash
# Installer une seule fois
dart pub global activate flutterfire_cli

# Dans le dossier du projet Flutter
flutterfire configure
```

Sélectionner `orion-gs` et les plateformes voulues. Le fichier `lib/firebase_options.dart` est généré automatiquement. **Ne jamais l'éditer manuellement.**

### Étape 4 — Activer Firestore

1. Firebase console → **Firestore Database** → **Create database**
2. Mode **Test** (lecture/écriture libre pendant 30 jours)
3. Région : `europe-west1` (Belgique, la plus proche pour la Tunisie)
4. **Enable**

### Étape 5 — Index Firestore requis

La requête par plage de dates sur `packets` utilise un collection group query. Créer l'index :

1. Firebase console → **Firestore** → **Indexes** → **Composite** → **Add index**
2. Collection ID : `packets`
3. Field : `timestamp` → Ascending
4. Query scope : **Collection group**
5. **Create**

> **Astuce** : Flutter affichera un lien direct dans la console debug la première fois que la requête échoue — cliquer dessus crée l'index automatiquement.

---

## Gestion d'état — Riverpod

### Pourquoi Riverpod ?

- Pas de `BuildContext` nécessaire pour lire/écrire l'état depuis les services
- `ref.watch()` déclenche des rebuilds ciblés — seuls les widgets concernés se reconstruisent
- Providers dérivés (`connectionProvider`) sans boilerplate
- Testable unitairement sans l'arbre de widgets

### Règle d'usage

| Situation | Utiliser |
|---|---|
| Lire l'état et rebuilder quand il change | `ref.watch(provider)` |
| Lire l'état une seule fois (action) | `ref.read(provider)` |
| Modifier l'état | `ref.read(provider.notifier).method()` |
| Provider asynchrone (Firestore) | `FutureProvider` + `.when(loading, error, data)` |

### Exemple — réagir aux nouvelles données

```dart
// Dans un ConsumerWidget ou ConsumerStatefulWidget
final telem = ref.watch(telemetryProvider);
Text('${telem.latest?.temp.toStringAsFixed(1)} °C');
```

### Exemple — publier une commande

```dart
// Pas besoin de BuildContext
ref.read(mqttListenerProvider).forceSafeMode();
```

---

## Layout responsive

Le dashboard détecte automatiquement la taille d'écran et adapte le layout :

| Largeur | Mode | Description |
|---|---|---|
| `< 600px` | **Mobile portrait** | 5 onglets TabBar : TEMP / PRESSURE / ALTITUDE / BATTERY / STATUS |
| `600–900px` | **Tablette / paysage** | 2 graphiques côte à côte, barre de statut en bas |
| `≥ 900px` | **Desktop** | Layout 2/3 + 1/3, side panel fixe à gauche |

```dart
// Breakpoints définis dans mission_control_page.dart
const double _kTablet  = 600;
const double _kDesktop = 900;
```

**Side panel :**
- Desktop → colonne fixe 264px intégrée dans le Row
- Mobile/Tablet → `Drawer` Flutter accessible via le bouton hamburger

---

## Side Panel

Quatre sections collapsibles :

### 1. Connection
- Statut du broker (couleur selon le mode satellite)
- Nombre de paquets reçus
- Info port TLS
- Bouton **DISCONNECT** (ferme la session Firestore, navigue vers login)

### 2. Commands
Chaque commande passe par une confirmation en 2 étapes (affiche le payload exact avant envoi) :

| Bouton | Topic MQTT | Payload |
|---|---|---|
| FORCE SAFE MODE | `cubesat/cmd` | `{"cmd":"safe"}` |
| FORCE NOMINAL | `cubesat/cmd` | `{"cmd":"nominal"}` |
| REBOOT SEQUENCE | `cubesat/cmd` | `{"cmd":"reboot"}` |
| ENVOYER | custom topic | custom JSON |

### 3. History

Deux onglets :
- **EN MÉMOIRE** — sessions de la connexion courante (in-memory)
- **FIREBASE** — sessions Firestore avec sélecteur de plage de dates

Le bouton **RETOUR LIVE** remet les graphiques en mode temps-réel.

### 4. Settings
Sliders pour les seuils d'alerte (appliqués immédiatement) :
- Temp max / min (°C)
- Batterie min (%)
- Altitude max (m)

---

## Topics MQTT

| Topic | Direction | Publisher | Contenu |
|---|---|---|---|
| `cubesat/hk` | ESP → Flutter | ESP32 | `{"temp":24.5,"pressure":101325,"altitude":12.3,"battery":72,"mode":"NOMINAL"}` |
| `cubesat/beacon` | ESP → Flutter | ESP32 | `{"alive":true,"mode":"NOMINAL","battery":72}` |
| `cubesat/alert` | ESP → Flutter | ESP32 | `{"alert":"FDIR: Safe mode","mode":"SAFE","battery":18,"temp":47.2}` |
| `cubesat/cmd` | Flutter → ESP | Ground station | `{"cmd":"safe"}` / `{"cmd":"nominal"}` / `{"cmd":"reboot"}` |
| `cubesat/ack` | ESP → Flutter | ESP32 | `{"ack":"safe","success":true,"mode":"SAFE"}` |
| `esp/led` | Flutter → ESP | Ground station | `"ON"` / `"OFF"` (legacy) |

---

## Firestore — schéma des données

```
sessions/
  {sessionId}/                    ← créé à chaque connexion MQTT
    startTime:   Timestamp
    endTime:     Timestamp | null
    packetCount: Number
    packets/
      {auto-id}/                  ← un document par paquet HK
        timestamp:  Timestamp
        temp:       Number
        pressure:   Number        ← en Pa (diviser par 100 pour hPa)
        altitude:   Number        ← en mètres
        battery:    Number        ← en %
        mode:       String

alerts/
  {auto-id}/                      ← alertes ESP + seuils Flutter
    timestamp:   Timestamp
    message:     String
    mode:        String
    isThreshold: Boolean
```

---

## Sécurité et règles Firestore

Règles de développement (test mode, valables 30 jours) :
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

Règles de production recommandées :
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /sessions/{sessionId} {
      allow read, write;
      match /packets/{packetId} { allow read, write; }
    }
    match /alerts/{alertId} { allow read, write; }
  }
}
```

---

## Lancer l'application

```bash
# 1. Installer les dépendances
flutter pub get

# 2. Configurer Firebase (si pas encore fait)
dart pub global activate flutterfire_cli
flutterfire configure

# 3. Lancer
flutter run

# Lancer sur un device spécifique
flutter run -d <device_id>

# Lancer en release (performances optimales)
flutter run --release
```

---

## Problèmes connus et solutions

### `parentDataDirty` assertion en boucle (Status tab mobile)

**Cause** : `SizedBox.expand()` ou `ListView` imbriqué dans un `ListView` parent sans contrainte de hauteur.

**Solution** : Utiliser `LayoutBuilder` pour donner des contraintes finies au `CustomPaint`, et remplacer les `ListView` imbriqués par des `Column` avec éléments `.map()`.

### Connexion MQTT échoue (rc=-4 ou timeout)

**Causes possibles** :
- Mauvaises credentials (`mqtt_user` / `mqtt_pass`)
- Le téléphone est sur un réseau qui bloque le port 8883
- `espClient.setInsecure()` non appelé sur l'ESP → certificat non validé

**Solution** : Vérifier le réseau, tester avec un autre Wi-Fi, vérifier les credentials HiveMQ.

### Firestore — index manquant

**Symptôme** : Exception dans la console avec un lien Firebase.

**Solution** : Cliquer le lien — il crée l'index composite automatiquement en 1–2 minutes.

### `firebase_options.dart` manquant

**Solution** :
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

### Données altitude = 0 sur les graphiques

**Cause** : Le payload SAFE mode de l'ESP ne contient pas `altitude`.

**Solution** : Le champ est optionnel dans `TelemetryPacket.fromJson` avec fallback à `0.0`. Pour corriger, ajouter `altitude` dans le payload SAFE côté ESP.
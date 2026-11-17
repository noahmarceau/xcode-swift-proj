# Forma

An offline-first, native iPhone app for meals, strength training, and progress. Built for iPhone 15 Pro on **iOS 17 or newer**. Open `Forma.xcodeproj` in **Xcode 16 or newer**. No Swift packages, backend, account, or API keys are required.

## Build and preview

1. Unzip this folder on a Mac. Open `Forma.xcodeproj` (not an individual Swift file).
2. Select the **Forma Local** scheme and an installed iPhone Simulator. Press **Run**. Simulator runs do not require an Apple signing team.
3. To run directly on an iPhone, set your team in Signing & Capabilities for **both Forma and FormaLive**. If changing bundle IDs, the extension must retain the app's prefix: e.g. `com.yourname.forma` and `com.yourname.forma.live`.
4. For Health access, select **Forma Health**. This configuration adds the HealthKit entitlement and compiles the Health reader. Your provisioning/signing profile must support that entitlement. The Local scheme deliberately contains no HealthKit entitlement.

Xcode 26's SDK is not required. The app uses rounded SwiftUI material tiles, rather than the iOS-26-only Liquid Glass APIs, to run on iOS 17+.

## Make an IPA for Sideloadly

On the Mac, from this folder:

```sh
bash Tools/build-ipa.sh
# Optional, only when your signing setup supports HealthKit:
bash Tools/build-ipa.sh --health
```

The script compiles an **unsigned device build**, packages it into `build/Forma-unsigned.ipa`, and leaves signing to Sideloadly. This is source code, not a precompiled or signed IPA. A Simulator `.app` cannot be used for sideloading.

Transfer the IPA to the computer running Sideloadly. Connect/unlock the iPhone, trust the computer, choose the device and your Apple ID, load the IPA, and install. Follow the device's signing trust / Developer Mode prompts if requested. Keep the bundle identifier stable for updates. Export a backup before changing identifiers or uninstalling.

**Preserve the `FormaLive.appex` extension** when re-signing if you want Live Activities. Sideloadly can remove extensions; doing so removes the Lock Screen / Dynamic Island interface. The ordinary app remains usable. Health access depends on the final re-signed entitlement and profile, not just the Xcode checkbox. If unsupported, use Local and enter weight manually. Free-account installs require periodic renewal; consult Sideloadly's instructions for the account you're using.

## The four tabs

### Fuel

- Date-specific diary, welcome summary, calories and macro targets.
- Foods logged by date/time and meal group. Fractional servings supported.
- Tap a diary entry to change food, servings, meal, time, or delete it.
- Macronutrient bars; fiber, sugar, saturated fat, sodium, potassium, calcium, iron, vitamin D, vitamin C, and cholesterol when the source provides them.
- Missing nutrients display as unavailable. Partial micronutrient totals explicitly report incomplete coverage.
- Nutrition is stored as a snapshot in each log: editing the catalog does not alter historical meals.

### Train

- Editable Push / Pull / Legs starter routines, plus unlimited custom routines.
- Sets, target reps, rest duration, load increment and notes per exercise; notes per workout.
- Reorder exercises with Edit in the routine editor; add/remove exercises and sets.
- Session loads/reps start from the last completed session; each row also labels the last result. Warm-up and failure flags are independent.
- Tap **Start** immediately before a set if you want a measured rest interval. Tap the circle to log the set. Without Start, rest is unknown, not inferred from completion-to-completion time.
- Optional rest countdown and opt-in local notification. Timers can be disabled entirely. Countdown state survives backgrounding and relaunch.
- Minimize a workout to visit another tab. The active session is saved locally after edits and can be resumed after relaunch.
- Finish to save and review volume, duration, logged sets and records. Unfinished rows remain explicitly unlogged and do not count toward statistics. Saved sessions can be deleted from their summary.
- Live Activity: current set/load/reps, progress, Lock Screen rest countdown, load and rep adjustments, Start and Log buttons. Tapping the activity opens the Train tab; tap Resume for detailed editing, flags and notes. On a locked phone, Apple may require authentication for actions. No remote push server is needed.

### Trends

- Search/select an exercise and view best load, reps, estimated 1RM, volume or measured rest over 30 / 90 / 365 days.
- Compare against daily calories, protein, body weight, sleep, Health energy, or another exercise metric.
- Two time-series charts use the same date range and separate labeled scales; a scatter plot pairs days with both values.
- Weekly training volume, daily check-in and same-day workout links.
- Missing observations are not fabricated or filled with zero. Lines connect recorded observations. Selecting All exercises combines different movements, so select one exercise for interpretable strength trends.
- Sleep is entered for the night ending on the selected date. Manual weight overrides Health weight for that date; clearing manual weight reveals a Health value if one exists.

### Settings

- Calorie goal, macro percentages, lb/kg, name, dark/light/system appearance, accent color.
- Food catalog editing, meal group editing/reordering, CSV import with preview.
- UMass source refresh, Health authorization/sync, JSON export and restore.
- Restore validates the file before replacing data and retains an on-device pre-restore recovery copy.

## Nutrition data

`Resources/common-foods.csv` includes ten **approximate starter foods**, not a laboratory-verified database. Check packaging/USDA or your preferred source and import your own foods. Values are per the written serving, not automatically per 100 g. Imported foods are searchable immediately.

Required CSV header:

```csv
name,serving,calories,protein_g,carbs_g,fat_g
"Rice, cooked",1 cup,205,4.3,44.5,0.4
```

Optional columns:

```text
fiber_g,sugar_g,saturated_fat_g,sodium_mg,potassium_mg,calcium_mg,
iron_mg,vitamin_d_mcg,vitamin_c_mg,cholesterol_mg,source
```

Use UTF-8, a period as the decimal separator, nonnegative numeric values with no unit suffix, and blank cells for unknown optional nutrients. Quoted commas, quoted newlines, CRLF, escaped quotes and a UTF-8 BOM are supported. Required macros must all be present. Imports match on name + serving + source and preview before committing. Editing an imported food manually makes it a Custom source.

### UMass Dining status and scope

The provided FoodPro directory was reachable during development. It exposed the dining location IDs and `shortmenu.aspx` links. However, multiple short-menu and long-menu requests returned **HTTP 500**. A complete live nutrition catalog could therefore **not** be downloaded or the live recipe parser verified end-to-end. No fabricated UMass nutrition is bundled.

The app implements a best-effort on-device importer which:

1. Discovers locations from the public directory.
2. Requests the selected location and menu date, follows published long-menu links, and discovers nutrition links.
3. Imports only recipes with a recognizable serving and all four calorie/macro values. It retains absolute micronutrient quantities only, not percent daily values.
4. Caches successful records and their retrieval date/source link. A failed refresh preserves the existing catalog. Partial refreshes disclose skipped pages.

This is a **menu-based importer**, not an undocumented API or guaranteed full-catalog mirror. It caps a refresh at 250 unique recipe links and eight expanded menu pages, with a short delay between requests. UMass HTML changes may require changes to `Services/UMassDining.swift`. The parser has a synthetic fixture test; that does not substitute for live-site verification. Daily refresh runs when the app opens/returns to the foreground, not at an exact scheduled background time. CSV import remains available offline.

## Health and energy

The Health build requests read-only body mass, active energy and basal/resting energy. Settings → Authorize & sync reads up to 90 days. Re-sync replaces daily Health totals rather than adding them, and uses HealthKit's cumulative statistics for energy. It does not write workouts, food or energy samples, avoiding duplicate workout calories. Manual weight remains intact.

A missing Health value can mean absent samples or denied access; Apple intentionally does not disclose read-denial status. Today's totals are incomplete. The app compares logged calories to active + resting energy only when both exist. It does not add exercise calories to your fixed food goal or claim an exact weight-gain forecast. Body-weight trends are measured observations.

## Progression and records

Suggestions use an optional performance-based rule inspired by the ACSM 2–10% progression guidance. The app requires all working sets to reach target + 2 reps on the last two sessions, with no failure flag and at least the planned number of sets. It applies your selected percentage, rounds down to the exercise's load increment, and holds the load when the next increment is too large. This exact implementation is a conservative app heuristic, not a personalized training prescription. No automatic week-by-week increase occurs.

Estimated 1RM uses Epley (`load × (1 + reps/30)`) for 2–12 reps, actual load for a single rep, and excludes higher reps. Records compare a workout against earlier workouts with the same exercise name. Warm-ups and unlogged sets are excluded. A first session establishes a baseline. Keep naming and equipment/load conventions consistent; dumbbell load is whatever per-hand or total convention you choose.

## Storage and privacy

The app uses a versioned Codable JSON database in Application Support. Writes are atomic and use iOS file protection until first device unlock. The app's Application Support directory is excluded from automatic backups; there is no CloudKit/iCloud sync or remote database. Make explicit exports regularly. Exported JSON is plaintext personal data; place it somewhere you control.

Only UMass refresh sends network requests, containing the menu location/date/recipe URLs, never your diary or workout data. Health remains on-device. No tracking SDKs are included. If reading the local database fails, the original is preserved and automatic writes are blocked; use Settings to export the original or restore a valid backup.

## Validation and limits

**Completed here:** Swift syntax-tree parsing of all source files, OpenStep Xcode project parsing, target/source/resource reference checks, plist and scheme XML checks, starter CSV validation, and shell syntax checking. The public UMass directory and failing menu requests were inspected.

**Not completed here:** Xcode compilation, XCTest execution, Simulator visual testing, device Health authorization, Sideloadly signing/install, and actual Live Activity interactions. The build environment was Linux and did not have Xcode/iOS SDKs. These are verification limits, not claims that a Simulator or device test passed.

On a Mac:

```sh
xcodebuild -list -project Forma.xcodeproj
xcodebuild -showdestinations -scheme 'Forma Local' -project Forma.xcodeproj
# Replace the simulator ID below with one listed by the previous command:
xcodebuild test -project Forma.xcodeproj -scheme 'Forma Local' \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' CODE_SIGNING_ALLOWED=NO
```

`Tests/FormaTests.swift` covers CSV quoting/validation, missing nutrients, serving scaling, progression gates, warm-up PR exclusion, energy completeness, nutrition parsing, historical snapshots and JSON round trips. See `DEVICE_CHECKLIST.md` for device verification. Run both schemes' builds before relying on the Health configuration.

## Project layout

- `App/`: entry point, tab navigation, reusable material tiles.
- `Core/`: value models, persistence, progression/PR calculations.
- `Features/`: diary, catalog, routines, active logging, charts and settings.
- `Services/`: CSV import, UMass scraping, Health reads, local notifications, Live Activity lifecycle.
- `LiveActivity/`: shared attributes and intents, widget presentation.
- `Resources/`: starter CSV and privacy manifest.
- `Config/`: app/extension plist files and optional HealthKit entitlement.
- `Tools/`: reproducible Xcode project generator and unsigned IPA build script.
- `Tests/`: XCTest cases included in both schemes.

## Technical references

- UMass directory: https://af-foodpro1.campus.ads.umass.edu/foodpro.net/location.aspx
- Apple HealthKit setup: https://developer.apple.com/documentation/xcode/configuring-healthkit-access
- Health privacy/authorization: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Activity interactivity: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- ACSM progression statement (2009): https://pubmed.ncbi.nlm.nih.gov/19204579/
- Sideloadly: https://sideloadly.io/

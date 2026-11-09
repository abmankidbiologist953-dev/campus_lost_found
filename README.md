# KASU Campus Lost & Found

On web and Android, students create accounts with a KASU matriculation number,
email address, and password. They sign in with their matriculation number and
password; the email is used for password recovery, not for login. Firebase
Authentication stores the account, and a private Cloud Function securely
resolves the matriculation number without exposing the email address to other
users.

Reports and profile pictures are still stored locally on the device using
SQLite; they are not shared across devices or backed up online. Other platforms
continue to use local-only accounts.

Use a password of at least eight characters, including letters and numbers.
Firebase sends password-reset links to the signup email. Accounts created in
the previous local-only version are not migrated to Firebase; create a Firebase
account with the same matriculation number to continue using the locally saved
profile on that device.

Firebase project: `kasu-campus-lf-20261108-x7`. The matriculation-number login
uses the `africa-south1` Cloud Functions region and a Firestore collection whose
client access is denied by `firestore.rules`. Deploying the backend requires a
Firestore database and Firebase Functions billing enabled. When deploying,
provide the Firebase web API key from `lib/firebase_options.dart` as the
`FIREBASE_WEB_API_KEY` function parameter. Web deployments must use a domain
authorized in Firebase Authentication settings.

## Run and test

Run the app with `flutter run` and the test suite with `flutter test`.

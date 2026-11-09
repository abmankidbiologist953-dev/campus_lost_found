const {createHash} = require("node:crypto");

const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {defineString} = require("firebase-functions/params");
const {HttpsError, onCall} = require("firebase-functions/v2/https");

initializeApp();

const firebaseWebApiKey = defineString("FIREBASE_WEB_API_KEY");
const firestore = getFirestore();

function normalizeMatricNumber(value) {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Enter a valid matriculation number.");
  }

  const matricNumber = value.trim().toUpperCase();
  if (!/^[A-Z0-9/-]{5,64}$/.test(matricNumber)) {
    throw new HttpsError("invalid-argument", "Enter a valid matriculation number.");
  }
  return matricNumber;
}

function matricDocumentId(matricNumber) {
  return createHash("sha256").update(matricNumber).digest("hex");
}

function requireAuthenticatedUser(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in before registering an account.");
  }
  return request.auth;
}

exports.registerStudentMatricNumber = onCall(
    {region: "africa-south1"},
    async (request) => {
      const auth = requireAuthenticatedUser(request);
      if (typeof auth.token.email !== "string" || auth.token.email.length === 0) {
        throw new HttpsError(
            "failed-precondition",
            "An email address is required for password recovery.",
        );
      }

      const matricNumber = normalizeMatricNumber(request.data?.matricNumber);
      const matricRef = firestore
          .collection("studentMatricIndex")
          .doc(matricDocumentId(matricNumber));

      await firestore.runTransaction(async (transaction) => {
        const existing = await transaction.get(matricRef);
        if (existing.exists && existing.get("uid") !== auth.uid) {
          throw new HttpsError(
              "already-exists",
              "An account already exists for this matriculation number.",
          );
        }
        transaction.set(matricRef, {
          uid: auth.uid,
          matricNumber,
          createdAt: existing.exists ?
            existing.get("createdAt") :
            FieldValue.serverTimestamp(),
        });
      });

      return {registered: true};
    },
);

exports.signInWithMatricNumber = onCall(
    {region: "africa-south1"},
    async (request) => {
      const matricNumber = normalizeMatricNumber(request.data?.matricNumber);
      const password = request.data?.password;
      if (typeof password !== "string" || password.length === 0) {
        throw new HttpsError("invalid-argument", "Enter your password.");
      }

      const matricSnapshot = await firestore
          .collection("studentMatricIndex")
          .doc(matricDocumentId(matricNumber))
          .get();
      const uid = matricSnapshot.get("uid");
      if (typeof uid !== "string" || matricSnapshot.get("matricNumber") !== matricNumber) {
        throw new HttpsError(
            "unauthenticated",
            "Incorrect matriculation number or password.",
        );
      }

      let user;
      try {
        user = await getAuth().getUser(uid);
      } catch (error) {
        if (error.code === "auth/user-not-found") {
          throw new HttpsError(
              "unauthenticated",
              "Incorrect matriculation number or password.",
          );
        }
        throw error;
      }
      if (user.disabled || !user.email) {
        throw new HttpsError(
            "unauthenticated",
            "Incorrect matriculation number or password.",
        );
      }

      const response = await fetch(
          `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${firebaseWebApiKey.value()}`,
          {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify({
              email: user.email,
              password,
              returnSecureToken: true,
            }),
          },
      );

      if (response.status === 400 || response.status === 401) {
        throw new HttpsError(
            "unauthenticated",
            "Incorrect matriculation number or password.",
        );
      }
      if (response.status === 429) {
        throw new HttpsError(
            "resource-exhausted",
            "Too many sign-in attempts. Please try again later.",
        );
      }
      if (!response.ok) {
        throw new HttpsError(
            "unavailable",
            "The authentication service is temporarily unavailable.",
        );
      }

      const result = await response.json();
      if (result.localId !== uid) {
        throw new HttpsError(
            "unauthenticated",
            "Incorrect matriculation number or password.",
        );
      }

      return {customToken: await getAuth().createCustomToken(uid)};
    },
);

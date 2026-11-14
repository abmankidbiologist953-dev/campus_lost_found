// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:campus_lost_found/campus_database.dart';
import 'package:campus_lost_found/campus_auth.dart';
import 'package:campus_lost_found/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await CampusDatabase.close();
    final databasePath = join(
      await databaseFactory.getDatabasesPath(),
      'campus_lost_found.db',
    );
    await databaseFactory.deleteDatabase(databasePath);
  });

  testWidgets('KASU logo is available as an app asset', (tester) async {
    final logo = await rootBundle.load('assets/images/kasu_logo.png');

    expect(logo.lengthInBytes, greaterThan(0));
  });

  test('accounts are stored with a verifiable password hash', () async {
    await CampusDatabase.createAccount('KASU/23/1234', 'studentpass1');

    expect(
      await CampusDatabase.verifyPassword('KASU/23/1234', 'studentpass1'),
      isTrue,
    );
    expect(
      await CampusDatabase.verifyPassword('KASU/23/1234', 'wrongpass1'),
      isFalse,
    );
  });

  test('local accounts can sign up and sign in without a backend', () async {
    final gateway = LocalCampusAuthGateway();
    await gateway.signUp(
      matricNumber: 'kasU/23/1234',
      email: 'student@example.com',
      password: 'studentpass1',
    );

    expect(
      await gateway.signIn(
        identifier: 'KASU/23/1234',
        password: 'studentpass1',
      ),
      'KASU/23/1234',
    );
    await expectLater(
      gateway.signIn(identifier: 'KASU/23/1234', password: 'wrongpass1'),
      throwsA(isA<StateError>()),
    );
  });

  test('profile picture is persisted with the student account', () async {
    await CampusDatabase.createAccount('KASU/23/1234', 'studentpass1');
    final picture = Uint8List.fromList([0, 1, 2, 3, 4, 5]);

    await CampusDatabase.saveProfilePhoto('KASU/23/1234', picture);

    expect(await CampusDatabase.loadProfilePhoto('KASU/23/1234'), picture);
    await CampusDatabase.saveProfilePhoto('KASU/23/1234', null);
    expect(await CampusDatabase.loadProfilePhoto('KASU/23/1234'), isNull);
  });

  test(
    'profile picture migration preserves existing student accounts',
    () async {
      const matricNumber = 'KASU/23/1234';
      final databasePath = join(
        await databaseFactory.getDatabasesPath(),
        'campus_lost_found.db',
      );
      final previousDatabase = await databaseFactory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, version) async {
            await database.execute('''
            CREATE TABLE student_accounts (
              matric_number TEXT PRIMARY KEY,
              password_salt TEXT NOT NULL,
              password_hash TEXT NOT NULL
            )
          ''');
            await database.execute('''
            CREATE TABLE campus_items (
              id INTEGER PRIMARY KEY,
              title TEXT NOT NULL,
              description TEXT NOT NULL,
              category TEXT NOT NULL,
              location TEXT NOT NULL,
              contact TEXT NOT NULL,
              item_date INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              type TEXT NOT NULL,
              returned INTEGER NOT NULL DEFAULT 0
            )
          ''');
            await database.insert('student_accounts', {
              'matric_number': matricNumber,
              'password_salt': 'c2FsdA==',
              'password_hash': 'existing-hash',
            });
          },
        ),
      );
      await previousDatabase.close();

      expect(await CampusDatabase.accountExists(matricNumber), isTrue);
      expect(await CampusDatabase.loadProfilePhoto(matricNumber), isNull);
    },
  );

  testWidgets('student must create an account before entering the app', (
    tester,
  ) async {
    await tester.pumpWidget(const LostFoundApp());
    expect(find.text('Sign In'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('create-account-mode')));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsWidgets);
    expect(find.text('LOGIN'), findsNothing);
    await tester.ensureVisible(find.byType(FilledButton).first);
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    expect(find.text('Please enter your matric number'), findsOneWidget);
    expect(find.text('Please enter your email address'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
    expect(find.text('Please confirm your password'), findsOneWidget);

    expect(find.text('Create Account'), findsWidgets);
    expect(find.text('LOGIN'), findsNothing);
  });

  testWidgets('student signs in with email and password only', (tester) async {
    final gateway = _FakeCampusAuthGateway();
    gateway.rejectSignIn = true;
    await tester.pumpWidget(LostFoundApp(authGateway: gateway));

    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Matriculation number'), findsNothing);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'student@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'studentpass1');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gateway.signedInIdentifier, 'student@example.com');
    expect(gateway.signedInPassword, 'studentpass1');
    expect(find.text('Incorrect credentials'), findsOneWidget);
  });

  testWidgets('account creation sends the recovery email to auth', (
    tester,
  ) async {
    final gateway = _FakeCampusAuthGateway();
    gateway.rejectSignUp = true;
    await tester.pumpWidget(LostFoundApp(authGateway: gateway));
    await tester.tap(find.byKey(const ValueKey('create-account-mode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'KASU/23/1234');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'student@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'studentpass1');
    await tester.enterText(find.byType(TextFormField).at(3), 'studentpass1');
    tester.widget<Checkbox>(find.byType(Checkbox)).onChanged!(true);
    await tester.pump();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Create Account'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gateway.signUpCalled, isTrue);
    expect(gateway.signedUpMatricNumber, 'KASU/23/1234');
    expect(gateway.signedUpEmail, 'student@example.com');
  });

  testWidgets('new passwords require both letters and numbers', (tester) async {
    await tester.pumpWidget(const LostFoundApp());
    await tester.tap(find.byKey(const ValueKey('create-account-mode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'KASU/23/1234');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'student@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'onlyletters');
    await tester.enterText(find.byType(TextFormField).at(3), 'onlyletters');
    await tester.ensureVisible(find.byType(FilledButton).first);
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(
      find.text('Include at least one letter and one number'),
      findsOneWidget,
    );
  });

  testWidgets('account creation requires KASU student confirmation', (
    tester,
  ) async {
    final gateway = _FakeCampusAuthGateway();
    await tester.pumpWidget(LostFoundApp(authGateway: gateway));
    await tester.tap(find.byKey(const ValueKey('create-account-mode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'KASU/23/1234');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'student@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'studentpass1');
    await tester.enterText(find.byType(TextFormField).at(3), 'studentpass1');
    await tester.ensureVisible(find.byType(FilledButton).first);
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(
      find.text('Please confirm your student status to continue.'),
      findsOneWidget,
    );
    expect(gateway.signUpCalled, isFalse);
  });

  testWidgets('password recovery sends a reset email request', (tester) async {
    tester.view.physicalSize = const Size(400, 350);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gateway = _FakeCampusAuthGateway();
    await tester.pumpWidget(LostFoundApp(authGateway: gateway));
    await tester.tap(find.byKey(const ValueKey('sign-in-mode')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('reset-email-field')),
      'student@example.com',
    );
    await tester.ensureVisible(find.text('Send reset link'));
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(gateway.resetEmail, 'student@example.com');
    expect(
      find.textContaining('a password reset link has been sent.'),
      findsOneWidget,
    );
  });

  testWidgets('student can report an item and search its description', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomePage(matricNumber: 'KASU/23/1234')),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report Item'));
    await tester.pumpAndSettle();
    expect(find.text('Report an Item'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Found').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Lost keys');
    await tester.enterText(find.byType(TextFormField).at(1), 'Silver keys');
    await tester.enterText(find.byType(TextFormField).at(2), 'Main Library');
    await tester.enterText(find.byType(TextFormField).at(3), '08012345678');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Report'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lost keys'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'silver keys');
    await tester.pumpAndSettle();

    expect(find.text('Lost keys'), findsOneWidget);
    expect(find.text('Black School Bag'), findsNothing);
    expect(find.text('Student Notebook'), findsNothing);
  });

  testWidgets('lost item reports require a photo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ItemFormPage()));

    await tester.enterText(find.byType(TextFormField).at(0), 'Lost keys');
    await tester.enterText(find.byType(TextFormField).at(1), 'Silver keys');
    await tester.enterText(find.byType(TextFormField).at(2), 'Main Library');
    await tester.enterText(find.byType(TextFormField).at(3), '08012345678');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit Report'));
    await tester.tap(find.text('Submit Report'));
    await tester.pump();

    expect(
      find.text('A photo is required for lost item reports.'),
      findsOneWidget,
    );
    expect(find.text('Upload photo'), findsOneWidget);
  });

  test('item photo is persisted with the report', () async {
    final now = DateTime.now();
    final photo = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
    final item = CampusItem(
      id: 5,
      title: 'Lost keys',
      description: 'Silver keys',
      category: 'Keys',
      location: 'Main Library',
      contact: '08012345678',
      date: now,
      createdAt: now,
      type: 'Lost',
      photo: photo,
    );

    await CampusDatabase.saveItem(item);

    final savedItems = await CampusDatabase.loadItems();
    expect(savedItems.singleWhere((saved) => saved.id == item.id).photo, photo);
  });

  testWidgets('student profile offers picture upload', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfilePage(
          matricNumber: 'KASU/23/1234',
          initialPhoto: null,
          onPhotoChanged: _ignoreProfilePhoto,
        ),
      ),
    );

    expect(find.text('Student Profile'), findsOneWidget);
    expect(find.text('Upload picture'), findsOneWidget);
  });

  test(
    'reports expire only after they have been stored for fourteen days',
    () async {
      final now = DateTime.now();
      final withinFourteenDays = CampusItem(
        id: 3,
        title: 'Recent report',
        description: 'Still within the retention period',
        category: 'Other',
        location: 'Library',
        contact: '08000000003',
        date: now,
        createdAt: now
            .subtract(const Duration(days: 14))
            .add(const Duration(seconds: 30)),
        type: 'Lost',
      );
      final olderThanFourteenDays = CampusItem(
        id: 4,
        title: 'Expired report',
        description: 'Older than the retention period',
        category: 'Other',
        location: 'Library',
        contact: '08000000004',
        date: now,
        createdAt: now.subtract(const Duration(days: 14, seconds: 1)),
        type: 'Lost',
      );

      await CampusDatabase.saveItem(withinFourteenDays);
      await CampusDatabase.saveItem(olderThanFourteenDays);
      final items = await CampusDatabase.loadItems();

      expect(items.any((item) => item.title == 'Recent report'), isTrue);
      expect(items.any((item) => item.title == 'Expired report'), isFalse);
    },
  );
}

Future<void> _ignoreProfilePhoto(Uint8List? photo) async {}

class _FakeCampusAuthGateway implements CampusAuthGateway {
  String? signedInIdentifier;
  String? signedInPassword;
  String? signedUpMatricNumber;
  String? signedUpEmail;
  String? resetEmail;
  bool signUpCalled = false;
  bool rejectSignIn = false;
  bool rejectSignUp = false;

  @override
  bool get usesEmailForSignIn => true;

  @override
  Future<String> signIn({
    required String identifier,
    required String password,
  }) async {
    signedInIdentifier = identifier;
    signedInPassword = password;
    if (rejectSignIn) {
      throw StateError('Incorrect credentials');
    }
    return 'KASU/23/1234';
  }

  @override
  Future<void> signUp({
    required String password,
    required String matricNumber,
    required String email,
  }) async {
    signUpCalled = true;
    signedUpMatricNumber = matricNumber;
    signedUpEmail = email;
    if (rejectSignUp) {
      throw StateError('Test registration captured');
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    resetEmail = email;
  }
}

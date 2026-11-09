// campus_database.dart
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class CampusItem {
  final int id;
  String title;
  String description;
  String category;
  String location;
  String contact;
  DateTime date;
  DateTime createdAt;
  String type;
  bool returned;

  CampusItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.location,
    required this.contact,
    required this.date,
    required this.createdAt,
    required this.type,
    this.returned = false,
  });

  factory CampusItem.fromMap(Map<String, Object?> map) {
    return CampusItem(
      id: map['id']! as int,
      title: map['title']! as String,
      description: map['description']! as String,
      category: map['category']! as String,
      location: map['location']! as String,
      contact: map['contact']! as String,
      date: DateTime.fromMillisecondsSinceEpoch(map['item_date']! as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      type: map['type']! as String,
      returned: (map['returned']! as int) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'location': location,
      'contact': contact,
      'item_date': date.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'type': type,
      'returned': returned ? 1 : 0,
    };
  }
}

class CampusDatabase {
  CampusDatabase._();

  static const _databaseName = 'campus_lost_found.db';
  static const maxProfilePhotoBytes = 5 * 1024 * 1024;
  static const _passwordIterations = 120000;
  static Database? _database;

  static Future<Database> get _instance async {
    if (_database != null) {
      return _database!;
    }

    final databasePath = join(await getDatabasesPath(), _databaseName);
    _database = await openDatabase(
      databasePath,
      version: 3,
      onCreate: _createSchema,
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE student_accounts ADD COLUMN profile_photo BLOB',
          );
        }
        if (oldVersion < 3) {
          await database.execute('''
            CREATE TABLE student_profiles (
              matric_number TEXT PRIMARY KEY,
              profile_photo BLOB
            )
          ''');
          await database.execute('''
            INSERT OR IGNORE INTO student_profiles (matric_number, profile_photo)
            SELECT matric_number, profile_photo FROM student_accounts
          ''');
        }
      },
    );
    return _database!;
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE student_accounts (
        matric_number TEXT PRIMARY KEY,
        password_salt TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        profile_photo BLOB
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
    await database.execute('''
      CREATE TABLE student_profiles (
        matric_number TEXT PRIMARY KEY,
        profile_photo BLOB
      )
    ''');

    final now = DateTime.now();
    final samples = [
      CampusItem(
        id: 1,
        title: 'Black School Bag',
        description: 'A black bag containing some books.',
        category: 'Bags',
        location: 'University Library',
        contact: '08000000001',
        date: now,
        createdAt: now,
        type: 'Lost',
      ),
      CampusItem(
        id: 2,
        title: 'Student Notebook',
        description: 'A blue notebook found in a classroom.',
        category: 'Books',
        location: 'Lecture Hall',
        contact: '08000000002',
        date: now,
        createdAt: now,
        type: 'Found',
      ),
    ];
    final batch = database.batch();
    for (final item in samples) {
      batch.insert('campus_items', item.toMap());
    }
    await batch.commit(noResult: true);
  }

  static Future<bool> accountExists(String matricNumber) async {
    final database = await _instance;
    final rows = await database.query(
      'student_accounts',
      columns: ['matric_number'],
      where: 'matric_number = ?',
      whereArgs: [matricNumber],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<Uint8List?> loadProfilePhoto(String matricNumber) async {
    final database = await _instance;
    final accounts = await database.query(
      'student_profiles',
      columns: ['profile_photo'],
      where: 'matric_number = ?',
      whereArgs: [matricNumber],
      limit: 1,
    );
    if (accounts.isEmpty) {
      return null;
    }

    final photo = accounts.single['profile_photo'];
    return photo == null
        ? null
        : Uint8List.fromList(List<int>.from(photo as List));
  }

  static Future<void> saveProfilePhoto(
    String matricNumber,
    Uint8List? photo,
  ) async {
    if (photo != null && photo.lengthInBytes > maxProfilePhotoBytes) {
      throw ArgumentError.value(
        photo.lengthInBytes,
        'photo',
        'Profile pictures must be 5 MB or smaller.',
      );
    }

    final database = await _instance;
    await database.insert('student_profiles', {
      'matric_number': matricNumber,
      'profile_photo': photo,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> ensureStudentProfile(String matricNumber) async {
    final database = await _instance;
    await database.insert('student_profiles', {
      'matric_number': matricNumber,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> createAccount(
    String matricNumber,
    String password,
  ) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = await _hashPassword(password, salt);
    final database = await _instance;
    await database.insert('student_accounts', {
      'matric_number': matricNumber,
      'password_salt': base64Encode(salt),
      'password_hash': hash,
    });
  }

  static Future<bool> verifyPassword(
    String matricNumber,
    String password,
  ) async {
    final database = await _instance;
    final accounts = await database.query(
      'student_accounts',
      columns: ['password_salt', 'password_hash'],
      where: 'matric_number = ?',
      whereArgs: [matricNumber],
      limit: 1,
    );
    if (accounts.isEmpty) {
      return false;
    }

    final account = accounts.single;
    final salt = base64Decode(account['password_salt']! as String);
    final expectedHash = account['password_hash']! as String;
    final actualHash = await _hashPassword(password, salt);
    return _constantTimeEquals(actualHash, expectedHash);
  }

  static Future<String> _hashPassword(String password, List<int> salt) {
    if (kIsWeb) {
      return _hashPasswordWithWebCrypto(password, salt);
    }

    return Isolate.run(() {
      final hmac = Hmac(sha256, utf8.encode(password));
      var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
      final derivedKey = List<int>.from(u);
      for (var iteration = 1; iteration < _passwordIterations; iteration++) {
        u = hmac.convert(u).bytes;
        for (var index = 0; index < derivedKey.length; index++) {
          derivedKey[index] ^= u[index];
        }
      }
      return base64Encode(derivedKey);
    });
  }

  static Future<String> _hashPasswordWithWebCrypto(
    String password,
    List<int> salt,
  ) async {
    final algorithm = cryptography.Pbkdf2(
      macAlgorithm: cryptography.Hmac.sha256(),
      iterations: _passwordIterations,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: cryptography.SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return base64Encode(await key.extractBytes());
  }

  static bool _constantTimeEquals(String first, String second) {
    if (first.length != second.length) {
      return false;
    }

    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
    }
    return difference == 0;
  }

  static Future<List<CampusItem>> loadItems() async {
    final database = await _instance;
    final expiryCutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    await database.delete(
      'campus_items',
      where: 'created_at < ?',
      whereArgs: [expiryCutoff],
    );
    final rows = await database.query(
      'campus_items',
      orderBy: 'created_at DESC',
    );
    return rows.map(CampusItem.fromMap).toList();
  }

  static Future<void> saveItem(CampusItem item) async {
    final database = await _instance;
    await database.insert(
      'campus_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteItem(int id) async {
    final database = await _instance;
    await database.delete('campus_items', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> setItemReturned(int id, bool returned) async {
    final database = await _instance;
    await database.update(
      'campus_items',
      {'returned': returned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }
}

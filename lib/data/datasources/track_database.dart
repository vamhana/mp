// |D.2.01.03|Data|Datasource|Dart|lib/data/datasources/track_database.dart|D.2.02.01|v.0.0.01|Draft|—|
import 'package:sqflite/sqflite.dart';

import '../models/track.dart';

class TrackDatabase {
  static const _dbName = 'mp_tracks.db';
  static const _dbVersion = 1;
  static const _table = 'tracks';

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      '$dir/$_dbName',
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mediaStoreId INTEGER NOT NULL UNIQUE,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT,
            durationMs INTEGER NOT NULL,
            filePath TEXT NOT NULL,
            coverPath TEXT,
            orderIndex INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<Track>> getAll() async {
    final db = await _database;
    final rows = await db.query(_table, orderBy: 'orderIndex ASC');
    return rows.map(Track.fromMap).toList();
  }

  Future<int> nextOrderIndex() async {
    final db = await _database;
    final rows = await db.rawQuery('SELECT MAX(orderIndex) AS mx FROM $_table');
    final mx = rows.first['mx'] as int?;
    return (mx ?? -1) + 1;
  }

  Future<bool> exists(int mediaStoreId) async {
    final db = await _database;
    final rows = await db.query(
      _table,
      where: 'mediaStoreId = ?',
      whereArgs: [mediaStoreId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insert(Track track) async {
    final db = await _database;
    return db.insert(_table, track.toMap());
  }

  Future<void> deleteById(int id) async {
    final db = await _database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// Перезаписывает orderIndex согласно переданному порядку (0,1,2,...).
  Future<void> rewriteOrder(List<Track> ordered) async {
    final db = await _database;
    final batch = db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(
        _table,
        {'orderIndex': i},
        where: 'id = ?',
        whereArgs: [ordered[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

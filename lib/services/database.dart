// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// Project imports:
import 'package:openlib/services/files.dart';

class MyBook {
  final String id;
  final String title;
  final String? author;
  final String? thumbnail;
  final String link;
  final String? publisher;
  final String? info;
  final String? description;
  final String? format;
  final String? fileName;

  MyBook(
      {required this.id,
      required this.title,
      required this.author,
      required this.thumbnail,
      required this.link,
      required this.publisher,
      required this.info,
      required this.format,
      required this.description,
      this.fileName});

  // Getter for compatibility with BookInfoWidget which expects 'md5'
  String get md5 => id;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'thumbnail': thumbnail,
      'link': link,
      'publisher': publisher,
      'info': info,
      'format': format,
      'description': description,
      'fileName': fileName
    };
  }

  @override
  String toString() {
    return 'MyBook{id: $id,title: $title,author: $author,thumbnail: $thumbnail,link: $link,publisher: $publisher,info: $info,format: $format,description:$description,fileName:$fileName}';
  }

  // Get actual filename - uses fileName if available, otherwise falls back to id.format
  String getFileName() {
    if (fileName != null && fileName!.isNotEmpty) {
      return fileName!;
    }
    return "$id.$format";
  }
}

class MyLibraryDb {
  static final MyLibraryDb instance = MyLibraryDb._internal();
  static Database? _database;
  MyLibraryDb._internal();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String databasePath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final directory = await getApplicationSupportDirectory();
      databasePath = directory.path;
      try {
        await Directory(databasePath).create(recursive: true);
      } catch (_) {}
    } else {
      databasePath = await getDatabasesPath();
    }
    final path = join(databasePath, 'mylibrary.db');

    return await openDatabase(
      path,
      version: 7,
      onCreate: (Database db, int version) async {
        await db.execute(
            'CREATE TABLE mybooks (id TEXT PRIMARY KEY, title TEXT,author TEXT,thumbnail TEXT,link TEXT,publisher TEXT,info TEXT,format TEXT,description TEXT,fileName TEXT)');
        await db.execute(
            'CREATE TABLE preferences (name TEXT PRIMARY KEY,value TEXT)');
        // Create these tables for all platforms (both mobile and desktop)
        await db.execute(
            'CREATE TABLE bookposition (fileName TEXT PRIMARY KEY,position TEXT,completed INTEGER DEFAULT 0)');
        await db.execute(
            'CREATE TABLE browserOptions (name TEXT PRIMARY KEY,value TEXT)');
        await db.execute(
            'CREATE TABLE booktags (bookId TEXT,tag TEXT,PRIMARY KEY (bookId,tag))');
        await db.execute(_createGenreTable);
        for (final sql in _createActivityTables) {
          await db.execute(sql);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        List<dynamic> isTableExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['bookposition']);
        List<dynamic> isPreferenceTableExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['preferences']);
        List<dynamic> isbrowserOptionsExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['browserOptions']);
        if (isPreferenceTableExist.isEmpty) {
          await db.execute(
              'CREATE TABLE preferences (name TEXT PRIMARY KEY,value TEXT)');
        }
        // Create bookposition table on all platforms if not exists
        if (isTableExist.isEmpty) {
          await db.execute(
              'CREATE TABLE bookposition (fileName TEXT PRIMARY KEY,position TEXT)');
        }
        // Create browserOptions table on all platforms if not exists
        if (isbrowserOptionsExist.isEmpty) {
          await db.execute(
              'CREATE TABLE browserOptions (name TEXT PRIMARY KEY,value TEXT)');
        }
        // Add fileName column if upgrading from version < 6
        if (oldVersion < 6) {
          try {
            await db.execute('ALTER TABLE mybooks ADD COLUMN fileName TEXT');
          } catch (_) {
            // Column might already exist
          }
        }
        // Tags and reading completion arrive with schema v7
        if (oldVersion < 7) {
          final hasTags = await db.query('sqlite_master',
              where: 'name = ?', whereArgs: ['booktags']);
          if (hasTags.isEmpty) {
            await db.execute(
                'CREATE TABLE booktags (bookId TEXT,tag TEXT,PRIMARY KEY (bookId,tag))');
          }
          try {
            await db.execute(
                'ALTER TABLE bookposition ADD COLUMN completed INTEGER DEFAULT 0');
          } catch (_) {
            // Column might already exist
          }
        }
      },
      onOpen: (db) async {
        // Genres, search history and reading activity arrived without a
        // schema bump: create on any version.
        await db.execute(_createGenreTable);
        for (final sql in _createActivityTables) {
          await db.execute(sql);
        }
        final bookStorageDefaultDirectory =
            await getBookStorageDefaultDirectory;
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('darkMode', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('themeMode', 'system')");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('openPdfwithExternalApp', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('openEpubwithExternalApp', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('bookStorageDirectory', '$bookStorageDefaultDirectory')");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('showManualDownloadButton', 0)");
      },
    );
  }

  static const _createGenreTable =
      'CREATE TABLE IF NOT EXISTS bookgenre (bookId TEXT PRIMARY KEY,genre TEXT)';

  static const _createActivityTables = [
    'CREATE TABLE IF NOT EXISTS searchhistory (query TEXT PRIMARY KEY,searchedAt INTEGER)',
    'CREATE TABLE IF NOT EXISTS readingdays (day TEXT PRIMARY KEY,hits INTEGER DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS completions (fileName TEXT PRIMARY KEY,completedAt INTEGER)',
  ];

  /// Most recent searches kept; older ones drop off.
  static const searchHistoryLimit = 50;

  // Database dbInstance;
  String tableName = 'mybooks';

  Future<void> insert(MyBook book) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      tableName,
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'booktags',
      where: 'bookId = ?',
      whereArgs: [id],
    );
    await dbInstance.delete(
      'bookgenre',
      where: 'bookId = ?',
      whereArgs: [id],
    );
    await dbInstance.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<MyBook?> getId(String id) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data =
        await dbInstance.query(tableName, where: 'id = ?', whereArgs: [id]);
    List<MyBook> book = listMapToMyBook(data);
    if (book.isNotEmpty) {
      return book.first;
    }
    return null;
  }

  Future<bool> checkIdExists(String id) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data =
        await dbInstance.query(tableName, where: 'id = ?', whereArgs: [id]);
    List<MyBook> book = listMapToMyBook(data);
    if (book.isNotEmpty) {
      return true;
    }
    return false;
  }

  Future<List<MyBook>> getAll() async {
    final dbInstance = await instance.database;
    final List<Map<String, dynamic>> maps = await dbInstance.query(tableName);
    return listMapToMyBook(maps);
  }

  List<MyBook> listMapToMyBook(List<Map<String, dynamic>> maps) {
    List<MyBook> myBookList = List.generate(maps.length, (i) {
      return MyBook(
          id: maps[i]['id'],
          title: maps[i]['title'],
          author: maps[i]['author'],
          thumbnail: maps[i]['thumbnail'],
          link: maps[i]['link'],
          publisher: maps[i]['publisher'],
          info: maps[i]['info'],
          format: maps[i]['format'],
          description: maps[i]['description'],
          fileName: maps[i]['fileName']);
    });
    return myBookList.reversed.toList();
  }

  Future<void> saveBookState(String fileName, String position) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'bookposition',
      {'fileName': fileName, 'position': position},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Saving a position means the book was read today.
    await recordReadingDay().catchError((_) {});
  }

  // ------------------------------------------------------------------
  // Reading activity: one row per local day a book was read (hits =
  // position saves that day), and when each book was finished.
  // ------------------------------------------------------------------

  static String dayKey(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  Future<void> recordReadingDay([DateTime? now]) async {
    final dbInstance = await instance.database;
    final day = dayKey(now ?? DateTime.now());
    // Two statements instead of an UPSERT: Android's system SQLite
    // predates ON CONFLICT ... DO UPDATE on older releases.
    await dbInstance.rawInsert(
        'INSERT OR IGNORE INTO readingdays (day, hits) VALUES (?, 0)', [day]);
    await dbInstance.rawUpdate(
        'UPDATE readingdays SET hits = hits + 1 WHERE day = ?', [day]);
  }

  /// Map of 'yyyy-MM-dd' to how much reading happened that day.
  Future<Map<String, int>> getReadingDays() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('readingdays');
    return {
      for (final row in rows)
        row['day'].toString(): int.tryParse('${row['hits']}') ?? 0
    };
  }

  /// Map of fileName to when it was marked finished.
  Future<Map<String, DateTime>> getCompletionDates() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('completions');
    final result = <String, DateTime>{};
    for (final row in rows) {
      final ms = int.tryParse('${row['completedAt']}');
      if (ms != null) {
        result[row['fileName'].toString()] =
            DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return result;
  }

  // ------------------------------------------------------------------
  // Search history: newest first, one row per distinct query.
  // ------------------------------------------------------------------

  Future<void> addSearchHistory(String query, [DateTime? now]) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    final dbInstance = await instance.database;
    // Same query typed with different case or spacing is one entry.
    await dbInstance.delete('searchhistory',
        where: 'lower(query) = ?', whereArgs: [clean.toLowerCase()]);
    await dbInstance.insert(
      'searchhistory',
      {
        'query': clean,
        'searchedAt': (now ?? DateTime.now()).millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await dbInstance.rawDelete(
      'DELETE FROM searchhistory WHERE query NOT IN '
      '(SELECT query FROM searchhistory ORDER BY searchedAt DESC LIMIT ?)',
      [searchHistoryLimit],
    );
  }

  Future<List<String>> getSearchHistory({int? limit}) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('searchhistory',
        orderBy: 'searchedAt DESC', limit: limit);
    return [for (final row in rows) row['query'].toString()];
  }

  Future<void> deleteSearchHistory(String query) async {
    final dbInstance = await instance.database;
    await dbInstance
        .delete('searchhistory', where: 'query = ?', whereArgs: [query]);
  }

  Future<void> clearSearchHistory() async {
    final dbInstance = await instance.database;
    await dbInstance.delete('searchhistory');
  }

  // ------------------------------------------------------------------
  // Tags: user-defined collections a book can belong to ('Favorites',
  // 'Sci-Fi', 'To Read', ...). One book, many tags; one tag, many books.
  // ------------------------------------------------------------------

  /// Assigns one tag to a book. Adding an existing pair is a no-op.
  Future<void> addTag(String bookId, String tag) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'booktags',
      {'bookId': bookId, 'tag': tag.trim()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Removes one tag from a book.
  Future<void> removeTag(String bookId, String tag) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'booktags',
      where: 'bookId = ? AND tag = ?',
      whereArgs: [bookId, tag],
    );
  }

  /// All tags of one book.
  Future<Set<String>> getTags(String bookId) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance
        .query('booktags', where: 'bookId = ?', whereArgs: [bookId]);
    return rows.map((r) => r['tag'].toString()).toSet();
  }

  /// Every distinct tag in use, sorted alphabetically.
  Future<List<String>> getAllTags() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('booktags',
        columns: ['tag'], groupBy: 'tag', orderBy: 'tag COLLATE NOCASE');
    return rows.map((r) => r['tag'].toString()).toList();
  }

  /// Map of bookId to its tag set, in one query - used to enrich the
  /// whole library without N+1 lookups.
  Future<Map<String, Set<String>>> getTagsForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('booktags');
    final map = <String, Set<String>>{};
    for (final row in rows) {
      map
          .putIfAbsent(row['bookId'].toString(), () => {})
          .add(row['tag'].toString());
    }
    return map;
  }

  // ------------------------------------------------------------------
  // Genre: one per book, chosen by the user; no row means "no genre".
  // ------------------------------------------------------------------

  /// Sets [bookId]'s genre key, or clears it when [genre] is null.
  Future<void> setGenre(String bookId, String? genre) async {
    final dbInstance = await instance.database;
    if (genre == null || genre.isEmpty) {
      await dbInstance
          .delete('bookgenre', where: 'bookId = ?', whereArgs: [bookId]);
      return;
    }
    await dbInstance.insert(
      'bookgenre',
      {'bookId': bookId, 'genre': genre},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getGenre(String bookId) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance
        .query('bookgenre', where: 'bookId = ?', whereArgs: [bookId]);
    return rows.isEmpty ? null : rows.first['genre'] as String?;
  }

  /// Map of bookId to genre key, in one query.
  Future<Map<String, String>> getGenresForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('bookgenre');
    return {
      for (final row in rows) row['bookId'].toString(): row['genre'].toString()
    };
  }

  // ------------------------------------------------------------------
  // Reading status: a book is completed when its position row is
  // flagged; in progress when a position exists but is not flagged.
  // ------------------------------------------------------------------

  /// Marks (or unmarks) a book as finished. The fileName key matches
  /// the bookposition table.
  Future<void> setCompleted(String fileName, bool completed,
      [DateTime? now]) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'bookposition',
      {'fileName': fileName, 'position': '', 'completed': completed ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (completed) {
      await dbInstance.insert(
        'completions',
        {
          'fileName': fileName,
          'completedAt': (now ?? DateTime.now()).millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await dbInstance
          .delete('completions', where: 'fileName = ?', whereArgs: [fileName]);
    }
  }

  /// True when the book is flagged completed.
  Future<bool> isCompleted(String fileName) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance
        .query('bookposition', where: 'fileName = ?', whereArgs: [fileName]);
    if (rows.isEmpty) return false;
    return rows.first['completed'] == 1;
  }

  /// Map of fileName to saved position for the whole library - used
  /// to derive reading status without N+1 lookups.
  Future<Map<String, String?>> getPositionsForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('bookposition');
    return {
      for (final row in rows)
        row['fileName'].toString(): row['position']?.toString()
    };
  }

  /// Map of fileName to completed flag for the whole library.
  Future<Map<String, bool>> getCompletedForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('bookposition');
    return {
      for (final row in rows) row['fileName'].toString(): row['completed'] == 1
    };
  }

  Future<void> deleteBookState(String fileName) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'bookposition',
      where: 'fileName = ?',
      whereArgs: [fileName],
    );
    await dbInstance.delete(
      'completions',
      where: 'fileName = ?',
      whereArgs: [fileName],
    );
  }

  Future<String?> getBookState(String fileName) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('bookposition', where: 'fileName = ?', whereArgs: [fileName]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'fileName': data[i]['fileName'], 'position': data[i]['position']};
    });
    if (dataList.isNotEmpty) {
      return dataList[0]['position'];
    } else {
      return null;
    }
  }

  Future<void> savePreference(String name, dynamic value) async {
    switch (value) {
      case bool _:
        value = value ? 1 : 0;
        break;
      case int _ || String _:
        break;
      default:
        throw 'Invalid type';
    }
    Database dbInstance = await instance.database;
    await dbInstance.insert(
      'preferences',
      {'name': name, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getPreference(String name) async {
    Database dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('preferences', where: 'name = ?', whereArgs: [name]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'name': data[i]['name'], 'value': data[i]['value']};
    });
    if (dataList.isNotEmpty) {
      // Convert to int if possible
      int? preference = int.tryParse(dataList[0]['value']);
      if (preference != null) {
        return preference;
      }
      // Return string value if not int
      return dataList[0]['value'];
    }
    throw "Preference $name not found";
  }

  Future<void> setBrowserOptions(String name, String value) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'browserOptions',
      {'name': name, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> getBrowserOptions(String name) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('browserOptions', where: 'name = ?', whereArgs: [name]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'name': data[i]['name'], 'value': data[i]['value']};
    });
    if (dataList.isNotEmpty) {
      return dataList[0]['value'];
    } else {
      return "";
    }
  }
}

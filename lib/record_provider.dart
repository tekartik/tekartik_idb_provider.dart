library tekartik_idb_provider.record_provider;

import 'package:tekartik_idb_provider/provider.dart';
import 'package:idb_shim/idb_client.dart' as idb;
import 'dart:async';
import 'package:collection/collection.dart';

abstract class DbField {
  static const String syncVersion = "syncVersion";
  static const String version = "version";

  // local version (incremented)
  static const String dirty = "dirty";
  static const String deleted = "deleted";
  static const String syncId = "syncId";
  static const String kind = "kind";
}

abstract class DbRecordBase {
  get id;
  set id(var id);

  fillDbEntry(Map entry);

  fillFromDbEntry(Map entry);

  Map toDbEntry() {
    Map entry = new Map();
    fillDbEntry(entry);

    return entry;
  }

  set(Map map, String key, value) {
    if (value != null) {
      map[key] = value;
    } else {
      map.remove(key);
    }
  }

  @override
  toString() {
    Map map = new Map();
    fillDbEntry(map);
    if (id != null) {
      map['_id'] = id.toString();
    }
    return map.toString();
  }

  @override
  int get hashCode => const MapEquality().hash(toDbEntry()) + id.hashCode ?? 0;

  @override
  bool operator ==(o) {
    if (o == null) {
      return false;
    }
    return (o.runtimeType == runtimeType) &&
        (const MapEquality().equals(toDbEntry(), o.toDbEntry())) &&
        id == o.id;
  }
}

abstract class DbRecord extends DbRecordBase {
  /*
  get id;

  set id(var id);

  @override
  bool operator ==(o) {
    return (super == (o) && id == o.id);
  }
  */
}

abstract class StringIdMixin {
  String _id;

  String get id => _id;

  set id(String id) => _id = id;
}

abstract class IntIdMixin {
  int _id;

  int get id => _id;

  set id(int id) => _id = id;
}

abstract class DbSyncedRecordBase extends DbRecordBase {
  //String get kind;

  int _version;

  int get version => _version;

  // updated on each modification
  set version(int version) => _version = version;

  String _syncId;
  String _syncVersion;

  String get syncId => _syncId;

  // will match the tag when synced
  String get syncVersion => _syncVersion;

  void setSyncInfo(String syncId, String syncVersion) {
    _syncId = syncId;
    _syncVersion = syncVersion;
  }

  bool _deleted;

  bool get deleted => _deleted == true;

  // true or false
  set deleted(bool deleted) => _deleted = deleted;

  bool _dirty;

  bool get dirty => _dirty == true;

  // true or false
  set dirty(bool dirty) => _dirty = dirty;

  DbSyncedRecord() {
    _version = 0;
  }

  fillFromDbEntry(Map entry) {
    // type = entry[FIELD_TYPE]; already done
    _version = entry[DbField.version];
    _syncId = entry[DbField.syncId];
    _syncVersion = entry[DbField.syncVersion];
    _deleted = entry[DbField.deleted];
    _dirty = entry[DbField.dirty] == 1;
  }

  fillDbEntry(Map entry) {
    set(entry, DbField.version, version);
    set(entry, DbField.syncId, syncId);
    set(entry, DbField.syncVersion, syncVersion);
    set(entry, DbField.deleted, deleted ? true : null);
    set(entry, DbField.dirty, dirty ? 1 : null);
    //set(entry, DbField.kind, kind);
  }
}

abstract class DbSyncedRecord extends DbSyncedRecordBase with IntIdMixin {}

class DbRecordProviderPutEvent extends DbRecordProviderEvent {
  DbRecordBase record;
}

class DbRecordProviderDeleteEvent extends DbRecordProviderEvent {
  var key;
}

// not tested
class DbRecordProviderClearEvent extends DbRecordProviderEvent {}

class DbRecordProviderEvent {
  bool _syncing;

  bool get syncing => _syncing;

  set syncing(bool syncing) => _syncing = syncing == true;
}

// only for writable transaction
abstract class DbRecordProviderTransaction<K>
    extends ProviderStoreTransaction<Map, K> {
  DbRecordBaseProvider _provider;
  factory DbRecordProviderTransaction(
      DbRecordBaseProvider provider, String storeName,
      [bool readWrite = false]) {
    if (readWrite == true) {
      return new DbRecordProviderWriteTransaction(provider, storeName);
    } else {
      return new DbRecordProviderReadTransaction(provider, storeName);
    }
  }

  @deprecated // discouraged
  Future<Map> get(K key) => super.get(key);

  DbRecordProviderTransaction._fromList(
      this._provider, ProviderTransactionList list, String storeName)
      : super.fromList(list, storeName) {}

  DbRecordProviderTransaction._(DbRecordBaseProvider provider, String storeName,
      [bool readWrite = false])
      : super(provider.provider, storeName, readWrite),
        _provider = provider;
}

class DbRecordProviderReadTransaction<T extends DbRecordBase, K>
    extends DbRecordProviderTransaction<K> {
  DbRecordProviderReadTransaction(
      DbRecordBaseProvider provider, String storeName)
      : super._(provider, storeName, false) {}

  DbRecordProviderReadTransaction.fromList(DbRecordBaseProvider _provider,
      ProviderTransactionList list, String storeName)
      : super._fromList(_provider, list, storeName) {}
}

class DbRecordProviderWriteTransaction<T extends DbRecordBase, K>
    extends DbRecordProviderTransaction<K> {
  bool get _hasListener => _provider._hasListener;

  List<DbRecordProviderEvent> changes = [];

  DbRecordProviderWriteTransaction(
      DbRecordBaseProvider provider, String storeName)
      : super._(provider, storeName, true) {}

  DbRecordProviderWriteTransaction.fromList(DbRecordBaseProvider provider,
      ProviderTransactionList list, String storeName)
      : super._fromList(provider, list, storeName) {}

  Future<T> putRecord(T record, {bool syncing}) {
    return super.put(record.toDbEntry(), record.id).then((K key) {
      record.id = key;
      if (_hasListener) {
        changes.add(new DbRecordProviderPutEvent()
          ..record = record
          ..syncing = syncing);
      }
      return record;
    });
  }

  _throwError() async => throw new UnsupportedError(
      "use putRecord, deleteRecord and clearRecords API");

  @deprecated
  @override
  Future<K> add(Map value, [K key]) => _throwError();

  @deprecated
  @override
  Future<K> put(Map value, [K key]) => _throwError();

  @deprecated
  @override
  delete(K key) => _throwError();

  @deprecated
  @override
  Future clear() => _throwError();

  Future deleteRecord(K key, {bool syncing}) {
    return super.delete(key).then((_) {
      if (_hasListener) {
        changes.add(new DbRecordProviderDeleteEvent()
          ..key = key
          ..syncing = syncing);
      }
    });
  }

  Future clearRecords({bool syncing}) {
    return super.clear().then((_) {
      if (_hasListener) {
        changes.add(new DbRecordProviderClearEvent()..syncing = syncing);
      }
    });
  }

  @override
  Future get completed {
    // delayed notification
    return super.completed.then((_) {
      if (_hasListener && changes.isNotEmpty) {
        for (StreamController ctlr in _provider._onChangeCtlrs) {
          ctlr.add(changes);
        }
      }
    });
  }
}

///
/// A record provider is a provider of a given object type
/// in one store
///
abstract class DbRecordBaseProvider<T extends DbRecordBase, K> {
  Provider provider;

  String get store;

  DbRecordProviderReadTransaction get readTransaction =>
      new DbRecordProviderReadTransaction(this, store);
  DbRecordProviderWriteTransaction get writeTransaction =>
      new DbRecordProviderWriteTransaction(this, store);
  DbRecordProviderReadTransaction get storeReadTransaction => readTransaction;

  DbRecordProviderWriteTransaction get storeWriteTransaction =>
      writeTransaction;

  DbRecordProviderTransaction storeTransaction(bool readWrite) =>
      new DbRecordProviderTransaction(this, store, readWrite);

  Future<T> get(K id) async {
    var txn = provider.storeTransaction(store);
    T record = await txnGet(txn, id);
    await txn.completed;
    return record;
  }

  T fromEntry(Map entry, K id);

  Future<T> txnGet(ProviderStoreTransaction txn, K id) {
    return txn.get(id).then((Map entry) {
      return fromEntry(entry, id);
    });
  }

  Future<T> indexGet(ProviderIndexTransaction txn, dynamic id) {
    return txn.get(id).then((Map entry) {
      return txn.getKey(id).then((K primaryId) {
        return fromEntry(entry, primaryId);
      });
    });
  }

  // transaction from a transaction list
  DbRecordProviderReadTransaction txnListReadTransaction(
          DbRecordProviderTransactionList txnList) =>
      new DbRecordProviderReadTransaction.fromList(this, txnList, store);

  DbRecordProviderWriteTransaction txnListWriteTransaction(
          DbRecordProviderWriteTransactionList txnList) =>
      new DbRecordProviderWriteTransaction.fromList(this, txnList, store);

  // Listener
  final List<StreamController> _onChangeCtlrs = [];

  Stream<List<DbRecordProviderEvent>> get onChange {
    StreamController ctlr = new StreamController(sync: true);
    _onChangeCtlrs.add(ctlr);
    return ctlr.stream;
  }

  void close() {
    for (StreamController ctlr in _onChangeCtlrs) {
      ctlr.close();
    }
  }

  bool get _hasListener => _onChangeCtlrs.isNotEmpty;
}

abstract class DbRecordProvider<T extends DbRecord, K>
    extends DbRecordBaseProvider<T, K> {
  Future<T> put(T record) async {
    var txn = storeTransaction(true);
    record = await txnPut(txn, record);
    await txn.completed;
    return record;
  }

  Future<T> txnPut(DbRecordProviderWriteTransaction txn, T record) =>
      txn.putRecord(record);

  Future delete(K key) async {
    var txn = storeTransaction(true);
    await txnDelete(txn, key);
    await txn.completed;
  }

  Future txnDelete(DbRecordProviderWriteTransaction txn, K key) =>
      txn.deleteRecord(key);

  Future clear() async {
    var txn = storeTransaction(true);
    await txnClear(txn);
    return txn.completed;
  }

  // Future txnClear(DbRecordProviderWriteTransaction txn) async { await txn.clearRecords(); }
  Future txnClear(DbRecordProviderWriteTransaction txn) => txn.clearRecords();
}

abstract class DbSyncedRecordProvider<T extends DbSyncedRecordBase, K>
    extends DbRecordBaseProvider<T, K> {
  static const String dirtyIndex = DbField.dirty;

  // must be int for indexing
  static const String syncIdIndex = DbField.syncId;

  ProviderIndexTransaction<dynamic, T> indexTransaction(String indexName,
          [bool readWrite]) =>
      new ProviderIndexTransaction.fromStoreTransaction(
          storeTransaction(readWrite), indexName);

  Future delete(K id, {bool syncing}) async {
    var txn = storeTransaction(true);
    await txnDelete(txn, id, syncing: syncing);
    await txn.completed;
  }

  Future txnRawDelete(DbRecordProviderWriteTransaction txn, K id) =>
      txn.deleteRecord(id);

  Future txnDelete(DbRecordProviderWriteTransaction txn, K id, {bool syncing}) {
    return txnGet(txn, id).then((T existing) {
      if (existing != null) {
        // Not synced yet or from sync adapter
        if (existing.syncId == null || (syncing == true)) {
          return txnRawDelete(txn, id);
        } else if (existing.deleted != true) {
          existing.deleted = true;
          existing.dirty = true;
          existing.version++;
          return txnRawPut(txn, existing);
        }
      }
    });
  }

  Future<T> getBySyncId(String syncId) async {
    ProviderIndexTransaction<String, T> txn = indexTransaction(syncIdIndex);
    K id = await txn.getKey(syncId);
    T record;
    if (id != null) {
      record = await txnGet(txn.store, id);
    }
    await txn.completed;
    return record;
  }

  Future<T> txnRawPut(DbRecordProviderWriteTransaction txn, T record) {
    return txn.putRecord(record);
  }

  Future<T> txnPut(DbRecordProviderWriteTransaction txn, T record,
      {bool syncing}) {
    syncing = syncing == true;
    // remove deleted if set
    record.deleted = false;
    // never update sync info
    // dirty for not sync only
    if (syncing == true) {
      record.dirty = false;
    } else {
      // try to retrieve existing sync info
      // list.setSyncInfo(null, null);
      record.setSyncInfo(null, null);
      record.dirty = true;
    }
    _insert() {
      record.version = 1;
      return txnRawPut(txn, record);
    }
    if (record.id != null) {
      return txnGet(txn, record.id).then((T existingRecord) {
        if (existingRecord != null) {
          record.setSyncInfo(existingRecord.syncId, existingRecord.syncVersion);
          record.version = existingRecord.version + 1;
          return txnRawPut(txn, record);
        } else {
          return _insert();
        }
      });
    } else {
      return _insert();
    }
  }

  Future clear({bool syncing}) async {
    if (syncing != true) {
      throw new UnimplementedError("force the syncing field to true");
    }
    var txn = storeTransaction(true);
    await txnClear(txn, syncing: syncing);
    return txn.completed;
  }

  Future txnClear(DbRecordProviderWriteTransaction txn, {bool syncing}) {
    if (syncing != true) {
      throw new UnimplementedError("force the syncing field to true");
    }
    return txn.clearRecords();
  }

  ///
  /// TODO: Put won't change data (which one) if local version has changed
  ///
  Future<T> put(T record, {bool syncing}) async {
    var txn = storeTransaction(true);

    record = await txnPut(txn, record, syncing: syncing);
    await txn.completed;
    return record;
  }

  ///
  /// during sync, update the sync version
  /// if the local version has changed since, keep the dirty flag
  /// other data is not touched
  /// the dirty flag is only cleared if the local version has not changed
  ///
  Future updateSyncInfo(T record, String syncId, String syncVersion) async {
    var txn = storeTransaction(true);
    DbSyncedRecordBase existingRecord = await txnGet(txn, record.id);
    if (existingRecord != null) {
      // Check version before changing the dirty flag
      if (record.version == existingRecord.version) {
        existingRecord.dirty = false;
      }
      record = existingRecord;
    }
    record.setSyncInfo(syncId, syncVersion);
    await txnRawPut(txn, record);
    await txn.completed;
  }

  Future<T> getFirstDirty() async {
    var txn = indexTransaction(dirtyIndex);
    var id = await txn.getKey(1); // 1 is dirty
    DbSyncedRecordBase record;
    if (id != null) {
      record = await txnGet(txn.store, id);
    }
    await txn.completed;
    return record;
  }

  // Delete all records with synchronisation information
  txnDeleteSyncedRecord(DbRecordProviderWriteTransaction txn) {
    ProviderIndexTransaction index =
        new ProviderIndexTransaction.fromStoreTransaction(txn, syncIdIndex);
    index.openCursor().listen((idb.CursorWithValue cwv) {
      //print("deleting: ${cwv.primaryKey}");
      cwv.delete();
    });
  }
}

// only for writable transaction
abstract class DbRecordProviderTransactionList extends ProviderTransactionList {
  DbRecordProvidersMixin _provider;
  factory DbRecordProviderTransactionList(
      DbRecordProvidersMixin provider, List<String> storeNames,
      [bool readWrite = false]) {
    if (readWrite == true) {
      return new DbRecordProviderWriteTransactionList(provider, storeNames);
    } else {
      return new DbRecordProviderReadTransactionList(provider, storeNames);
    }
  }

//  DbRecordBaseProvider getRecordProvider(String storeName) =>      _provider.getRecordProvider(storeName);

  DbRecordProviderTransactionList._(
      DbRecordProvidersMixin provider, List<String> storeNames,
      [bool readWrite = false])
      : super(provider as Provider, storeNames, readWrite),
        _provider = provider;
}

class DbRecordProviderReadTransactionList
    extends DbRecordProviderTransactionList {
  DbRecordProviderReadTransactionList(
      DbRecordProvidersMixin provider, List<String> storeNames)
      : super._(provider, storeNames, false) {}

  DbRecordProviderReadTransaction store(String storeName) {
    return new DbRecordProviderReadTransaction.fromList(
        _provider.getRecordProvider(storeName), this, storeName);
  }
}

class DbRecordProviderWriteTransactionList
    extends DbRecordProviderTransactionList {
  DbRecordProviderWriteTransactionList(
      DbRecordProvidersMixin provider, List<String> storeNames)
      : super._(provider, storeNames, true) {}

  DbRecordProviderTransaction store(String storeName) {
    return new DbRecordProviderWriteTransaction.fromList(
        _provider.getRecordProvider(storeName), this, storeName);
  }
}

abstract class DbRecordProvidersMapMixin {
  Map<String, DbRecordBaseProvider> _providerMap;
  Map<String, DbRecordBaseProvider> get providerMap => _providerMap;
  set providerMap(Map<String, DbRecordBaseProvider> providerMap) {
    _providerMap = providerMap;
  }

  initAll(Provider provider) {
    for (DbRecordBaseProvider recordProvider in _providerMap.values) {
      recordProvider.provider = provider;
    }
  }

  DbRecordBaseProvider getRecordProvider(String storeName) =>
      providerMap[storeName];

  closeAll() {
    for (DbRecordBaseProvider recordProvider in recordProviders) {
      recordProvider.close();
    }
  }

  Iterable<DbRecordBaseProvider> get recordProviders => providerMap.values;
}

abstract class DbRecordProvidersMixin {
  DbRecordProviderReadTransactionList dbRecordProviderReadTransactionList(
          List<String> storeNames) =>
      new DbRecordProviderReadTransactionList(this, storeNames);

  DbRecordProviderWriteTransactionList writeTransactionList(
          List<String> storeNames) =>
      new DbRecordProviderWriteTransactionList(this, storeNames);

  DbRecordProviderWriteTransactionList dbRecordProviderWriteTransactionList(
          List<String> storeNames) =>
      writeTransactionList(storeNames);

  @deprecated // 2016-02-12
  DbRecordProviderTransactionList dbRecordProviderTransactionList(
      List<String> storeNames,
      [bool readWrite = false]) {
    return new DbRecordProviderTransactionList(this, storeNames, readWrite);
  }

  // to implement
  DbRecordBaseProvider getRecordProvider(String storeName);
  Iterable<DbRecordBaseProvider> get recordProviders;
}
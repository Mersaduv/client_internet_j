import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// یک صف برای فایل ویندوز `flutter_secure_storage.dat`.
///
/// خواندن و نوشتن هم‌زمان این فایل را برای حذف قفل می‌کند و
/// `errno = 32` می‌دهد. همهٔ دسترسی‌ها از همین‌جا یکی‌یکی رد می‌شوند.
class AppSecureStorage {
  AppSecureStorage._();
  static final AppSecureStorage instance = AppSecureStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> _tail = Future<void>.value();

  Future<String?> read({required String key}) {
    return _run(() => _storage.read(key: key));
  }

  Future<void> write({required String key, required String value}) {
    return _run(() => _storage.write(key: key, value: value));
  }

  Future<void> delete({required String key}) {
    return _run(() => _storage.delete(key: key));
  }

  Future<T> _run<T>(Future<T> Function() action) {
    final done = Completer<T>();
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    previous.whenComplete(() async {
      try {
        done.complete(await _attempt(action));
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        gate.complete();
      }
    });
    return done.future;
  }

  Future<T> _attempt<T>(Future<T> Function() action) async {
    Object? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await action();
      } on FileSystemException catch (error) {
        last = error;
        if (!_isSharingViolation(error) || attempt == 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
      }
    }
    throw last!;
  }

  bool _isSharingViolation(FileSystemException error) {
    final text = error.toString().toLowerCase();
    return error.osError?.errorCode == 32 ||
        text.contains('errno = 32') ||
        text.contains('being used by another process');
  }
}

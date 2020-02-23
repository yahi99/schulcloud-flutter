import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_cached/flutter_cached.dart';
import 'package:get_it/get_it.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:schulcloud/app/app.dart';
import 'package:schulcloud/generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/network.dart';
import 'services/storage.dart';

extension FancyContext on BuildContext {
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  ThemeData get theme => Theme.of(this);
  NavigatorState get navigator => Navigator.of(this);
  NavigatorState get rootNavigator => Navigator.of(this, rootNavigator: true);
  S get s => S.of(this);
}

final services = GetIt.instance;

/// Converts a hex string (like, '#ffdd00') to a [Color].
Color hexStringToColor(String hex) =>
    Color(int.parse('ff${hex.substring(1)}', radix: 16));

/// Limits a string to a certain amount of characters.
String limitString(String string, int maxLength) =>
    string.length > maxLength ? '${string.substring(0, maxLength)}…' : string;

/// Prints a file size given in [bytes] as a [String].
String formatFileSize(int bytes) {
  const units = ['B', 'kB', 'MB', 'GB', 'TB', 'YB'];

  var index = 0;
  var power = 1;
  while (bytes > 1000 * power && index < units.length - 1) {
    power *= 1000;
    index++;
  }

  return '${(bytes / power).toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}

extension HtmlString on String {
  /// Removes html tags from a string.
  String get withoutHtmlTags => parse(this).documentElement.text;
}

/// Tries launching a url.
Future<bool> tryLaunchingUrl(String url) async {
  if (await canLaunch(url)) {
    await launch(url);
    return true;
  }
  return false;
}

extension ImmutableMap<K, V> on Map<K, V> {
  Map<K, V> clone() => Map.of(this);

  Map<K, V> copyWith(K key, V value) {
    final newMap = clone();
    newMap[key] = value;
    return newMap;
  }
}

/// An error indicating that a permission wasn't granted by the user.
class PermissionNotGranted<T> implements Exception {
  @override
  String toString() => "A permission wasn't granted by the user.";
}

class Id<T> {
  const Id(this.id);

  final String id;

  Id<S> cast<S>() => Id<S>(id);

  @override
  bool operator ==(other) => other is Id<T> && other.id == id;
  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

/// A special kind of item that also carries its id.
abstract class Entity {
  const Entity();

  Id get id;
}

class LazyMap<K, V> {
  LazyMap(this.createValueForKey) : assert(createValueForKey != null);

  final Map<K, V> _map = {};
  final V Function(K key) createValueForKey;

  V operator [](K key) => _map.putIfAbsent(key, () => createValueForKey(key));
}

typedef NetworkCall = Future<Response> Function(NetworkService network);
typedef JsonParser<T> = T Function(Map<String, dynamic> data);

CacheController<T> fetchSingle<T extends Entity>({
  @required NetworkCall makeNetworkCall,
  @required JsonParser<T> parser,
  Id<dynamic> parent,
}) {
  final storage = services.get<StorageService>();
  final network = services.get<NetworkService>();

  return CacheController<T>(
    saveToCache: (item) => storage.cache.putChildrenOfType<T>(parent, [item]),
    loadFromCache: () async {
      return (await storage.cache.getChildrenOfType<T>(parent)).singleWhere(
        (_) => true,
        orElse: () => throw NotInCacheException(),
      );
    },
    fetcher: () async {
      final response = await makeNetworkCall(network);
      final data = json.decode(response.body);
      return parser(data);
    },
  );
}

CacheController<T> fetchSingleOfList<T extends Entity>({
  @required NetworkCall makeNetworkCall,
  @required JsonParser<T> parser,
  Id<dynamic> parent,
}) {
  final storage = services.get<StorageService>();
  final network = services.get<NetworkService>();

  return CacheController<T>(
    saveToCache: (item) => storage.cache.putChildrenOfType<T>(parent, [item]),
    loadFromCache: () async {
      return (await storage.cache.getChildrenOfType<T>(parent)).singleWhere(
        (_) => true,
        orElse: () => throw NotInCacheException(),
      );
    },
    fetcher: () async {
      final response = await makeNetworkCall(network);
      final data = json.decode(response.body);
      // Multiple items can be returned when only one is expected, e.g. multiple
      // submissions to one assignment by one person (demo student):
      // https://api.schul-cloud.org/submissions?homeworkId=59a662f6a2049554a93fed43&studentId=599ec14d8e4e364ec18ff46d
      final items = data['data'];
      if (items.isEmpty) {
        return null;
      }
      return parser(items.first);
    },
  );
}

CacheController<List<T>> fetchList<T extends Entity>({
  @required NetworkCall makeNetworkCall,
  @required JsonParser<T> parser,
  Id<dynamic> parent,
  // Surprise: The Calendar API's response is different from all others! Would
  // be too easy otherwise ;)
  bool serviceIsPaginated = true,
}) {
  final storage = services.get<StorageService>();
  final network = services.get<NetworkService>();

  return CacheController<List<T>>(
    saveToCache: (items) => storage.cache.putChildrenOfType<T>(parent, items),
    loadFromCache: () => storage.cache.getChildrenOfType<T>(parent),
    fetcher: () async {
      final response = await makeNetworkCall(network);
      final body = json.decode(response.body);
      final dataList = serviceIsPaginated ? body['data'] : body;
      return [for (final data in dataList) parser(data)];
    },
  );
}

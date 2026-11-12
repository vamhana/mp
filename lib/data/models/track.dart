// |D.2.02.01|Data|Model|Dart|lib/data/models/track.dart|—|v.0.0.01|Draft|—|
import 'dart:io';

class Track {
  final int? id;                // ID в нашей БД
  final int mediaStoreId;       // исходный ID в MediaStore
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String filePath;        // путь к скопированному MP3
  final String? coverPath;      // путь к сохранённой обложке (JPG/PNG)
  final int orderIndex;

  const Track({
    this.id,
    required this.mediaStoreId,
    required this.title,
    required this.artist,
    this.album,
    required this.durationMs,
    required this.filePath,
    this.coverPath,
    required this.orderIndex,
  });

  String get displayArtist => artist.trim().isEmpty ? 'Неизвестный исполнитель' : artist;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title;
    var name = filePath.split(Platform.pathSeparator).last;
    name = name.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
    name = name.replaceFirst(RegExp(r'^-?\d+__'), '');
    return name;
  }

  Duration get duration => Duration(milliseconds: durationMs);

  Track copyWith({
    int? id,
    int? mediaStoreId,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? filePath,
    String? coverPath,
    int? orderIndex,
  }) {
    return Track(
      id: id ?? this.id,
      mediaStoreId: mediaStoreId ?? this.mediaStoreId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      filePath: filePath ?? this.filePath,
      coverPath: coverPath ?? this.coverPath,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'mediaStoreId': mediaStoreId,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'filePath': filePath,
        'coverPath': coverPath,
        'orderIndex': orderIndex,
      };

  factory Track.fromMap(Map<String, dynamic> map) => Track(
        id: map['id'] as int?,
        mediaStoreId: map['mediaStoreId'] as int,
        title: map['title'] as String? ?? '',
        artist: map['artist'] as String? ?? '',
        album: map['album'] as String?,
        durationMs: map['durationMs'] as int? ?? 0,
        filePath: map['filePath'] as String,
        coverPath: map['coverPath'] as String?,
        orderIndex: map['orderIndex'] as int? ?? 0,
      );
}

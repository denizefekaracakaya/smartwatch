enum TrackKind { song, podcast }

TrackKind _kind(String value) => value == 'podcast' ? TrackKind.podcast : TrackKind.song;

class User {
  User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.emailVerified,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        email: json['email'] as String,
        displayName: json['display_name'] as String,
        emailVerified: json['email_verified'] as bool,
      );

  final int id;
  final String email;
  final String displayName;
  final bool emailVerified;
}

class TokenPair {
  TokenPair({required this.accessToken, required this.refreshToken, required this.user});

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String accessToken;
  final String refreshToken;
  final User user;
}

class Track {
  Track({
    required this.id,
    required this.kind,
    required this.title,
    required this.artist,
    this.album,
    this.genre,
    this.year,
    required this.durationSeconds,
    this.description,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as int,
        kind: _kind(json['kind'] as String),
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        genre: json['genre'] as String?,
        year: json['year'] as int?,
        durationSeconds: json['duration_seconds'] as int,
        description: json['description'] as String?,
      );

  final int id;
  final TrackKind kind;
  final String title;
  final String artist;
  final String? album;
  final String? genre;
  final int? year;
  final int durationSeconds;
  final String? description;

  Duration get duration => Duration(seconds: durationSeconds);
}

class TrackPage {
  TrackPage({required this.items, required this.total});

  factory TrackPage.fromJson(Map<String, dynamic> json) => TrackPage(
        items: (json['items'] as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
        total: json['total'] as int,
      );

  final List<Track> items;
  final int total;
}

class PlaylistSummary {
  PlaylistSummary({
    required this.id,
    required this.name,
    this.description,
    required this.trackCount,
  });

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) => PlaylistSummary(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String?,
        trackCount: json['track_count'] as int,
      );

  final int id;
  final String name;
  final String? description;
  final int trackCount;
}

class PlaylistDetail extends PlaylistSummary {
  PlaylistDetail({
    required super.id,
    required super.name,
    super.description,
    required this.tracks,
  }) : super(trackCount: tracks.length);

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) => PlaylistDetail(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String?,
        tracks: (json['tracks'] as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final List<Track> tracks;
}

class StreamInfo {
  StreamInfo({required this.url, required this.mimeType});

  factory StreamInfo.fromJson(Map<String, dynamic> json) =>
      StreamInfo(url: json['url'] as String, mimeType: json['mime_type'] as String);

  final String url;
  final String mimeType;
}

class AssistantMatch {
  AssistantMatch({required this.track, this.reason});

  final Track track;
  final String? reason;
}

class AssistantResult {
  AssistantResult({required this.matches, required this.message, required this.aiUsed});

  factory AssistantResult.fromJson(Map<String, dynamic> json) => AssistantResult(
        matches: (json['matches'] as List).map((e) {
          final m = e as Map<String, dynamic>;
          return AssistantMatch(
            track: Track.fromJson(m['track'] as Map<String, dynamic>),
            reason: m['reason'] as String?,
          );
        }).toList(),
        message: json['message'] as String,
        aiUsed: json['ai_used'] as bool,
      );

  final List<AssistantMatch> matches;
  final String message;
  final bool aiUsed;
}

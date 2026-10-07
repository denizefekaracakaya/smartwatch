# R8 rules for release builds.
#
# just_audio's ObserverRenderer extends media3's NoSampleRenderer. With R8 optimisation, release builds
# crashed on the first track with "NullPointerException ... ExoPlayerImplInternal: Unexpected runtime
# error" (debug builds, which are not minified, played fine). Keep the player stack intact.
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audio_session.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

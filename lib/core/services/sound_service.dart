
import 'package:audioplayers/audioplayers.dart';

class SoundService {
  SoundService._();

  static final SoundService instance = SoundService._();

  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> playScanSound() async {
    await _audioPlayer.play(
      AssetSource('sound/scan.mp3'),
    );
  }

  Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}

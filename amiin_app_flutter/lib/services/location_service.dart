import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Les services de localisation sont désactivés.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Permissions de localisation refusées.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Permissions de localisation refusées définitivement.');
    }

    return await Geolocator.getCurrentPosition();
  }
}

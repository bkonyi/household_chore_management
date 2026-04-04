import 'dart:convert';
import 'package:http/http.dart' as http;

/// A service to fetch current weather information.
class WeatherService {
  /// The location to fetch weather for.
  final String location;

  /// Creates a [WeatherService] with a default [location].
  WeatherService({this.location = 'Waterloo, Ontario'});

  /// Fetches the current weather for the configured [location].
  Future<String> fetchCurrentWeather() async {
    try {
      final encodedLocation = Uri.encodeComponent(location);
      final response = await http.get(
        Uri.parse('https://wttr.in/$encodedLocation?format=j1'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data case {
          'current_condition': [
            {
              'temp_C': String temp,
              'weatherDesc': [
                {'value': String desc}
              ]
            }
          ]
        }) {
          return 'It is currently $temp°C and $desc in $location.';
        } else {
          return 'Unknown weather (Failed to parse data).';
        }
      } else {
        return 'Unknown weather (Status \${response.statusCode}).';
      }
    } catch (e) {
      return 'Unknown weather (Exception: \$e).';
    }
  }
}

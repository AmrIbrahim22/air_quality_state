import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Adding MVN (Model-View-ViewModel) implementation that was missing
abstract class MVNViewModel extends ChangeNotifier {
  void dispose() {
    super.dispose();
  }
}

class MVNProvider<T extends MVNViewModel> extends InheritedWidget {
  final T viewModel;

  const MVNProvider({
    super.key,
    required this.viewModel,
    required super.child,
  });

  static MVNProvider<T> of<T extends MVNViewModel>(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<MVNProvider<T>>();
    if (provider == null) {
      throw Exception('No MVNProvider<$T> found in widget tree');
    }
    return provider;
  }

  @override
  bool updateShouldNotify(MVNProvider<T> oldWidget) {
    return viewModel != oldWidget.viewModel;
  }
}

class MVNConsumer<T extends MVNViewModel> extends StatefulWidget {
  final Widget Function(BuildContext context, T viewModel, Widget? child) builder;
  final Widget? child;

  const MVNConsumer({
    super.key,
    required this.builder,
    this.child,
  });

  @override
  State<MVNConsumer<T>> createState() => _MVNConsumerState<T>();
}

class _MVNConsumerState<T extends MVNViewModel> extends State<MVNConsumer<T>> {
   T? viewModel;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // First remove listener from old viewModel if it exists
    if (viewModel != null) {
      viewModel?.removeListener(_onViewModelChanged);
    }
    
    // Get the new viewModel from the provider
    viewModel = MVNProvider.of<T>(context).viewModel;
    viewModel?.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    viewModel?.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, viewModel!, widget.child);
  }
}
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  
  runApp(MVNProvider(
    viewModel: AppViewModel(
      timeService: TimeService(),
      weatherService: WeatherService(),
      locationRepository: LocationRepository(prefs),
    ),
    child: const ClockApp(),
  ));
}

// App Entry Point
class ClockApp extends StatelessWidget {
  const ClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MVNConsumer<AppViewModel>(
      builder: (context, viewModel, _) {
        return MaterialApp(
          title: 'Finland Clock',
          theme: ThemeData(
            primarySwatch: Colors.blue,
            brightness: viewModel.isDarkMode ? Brightness.dark : Brightness.light,
            fontFamily: 'Roboto',
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.indigo,
            fontFamily: 'Roboto',
          ),
          themeMode: viewModel.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const HomeScreen(),
        );
      },
    );
  }
}

// MVVM ViewModel - Central state management
class AppViewModel extends MVNViewModel {
  final TimeService timeService;
  final WeatherService weatherService;
  final LocationRepository locationRepository;
  
  String _selectedCity = 'Helsinki';
  bool _isDarkMode = false;
  DateTime _now = DateTime.now();
  WeatherData? _weatherData;
  SeasonInfo? _seasonInfo;
  LightInfo? _lightInfo;
  bool _isLoading = true;
  
  AppViewModel({
    required this.timeService, 
    required this.weatherService,
    required this.locationRepository,
  }) {
    _init();
  }
  
  // Getters
  DateTime get now => _now;
  bool get isDarkMode => _isDarkMode;
  String get selectedCity => _selectedCity;
  WeatherData? get weatherData => _weatherData;
  SeasonInfo? get seasonInfo => _seasonInfo;
  LightInfo? get lightInfo => _lightInfo;
  bool get isLoading => _isLoading;
  
  Future<void> _init() async {
    // Load saved preferences
    _selectedCity = await locationRepository.getLocation() ?? 'Helsinki';
    _isDarkMode = await locationRepository.getDarkModePreference() ?? false;
    
    // Setup time updates
    timeService.getTimeStream().listen((time) {
      _now = time;
      notifyListeners();
    });
    
    // Initial data fetch
    await _fetchAllData();
    
    // Setup periodic data refresh
    Timer.periodic(const Duration(minutes: 15), (_) => _fetchAllData());
  }
  
  Future<void> _fetchAllData() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _weatherData = await weatherService.getWeather(_selectedCity);
      _seasonInfo = timeService.getCurrentSeasonInfo(_now);
      _lightInfo = timeService.getDayLightInfo(_selectedCity, _now);
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  void toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    await locationRepository.saveDarkModePreference(_isDarkMode);
    notifyListeners();
  }
  
  void setLocation(String city) async {
    _selectedCity = city;
    await locationRepository.saveLocation(city);
    _fetchAllData();
  }
}

// Services and Repositories

/// Time Service - Handles time calculations and streams
class TimeService {
  Stream<DateTime> getTimeStream() {
    return Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
  }
  
  /// Calculate season information based on current date
  SeasonInfo getCurrentSeasonInfo(DateTime date) {
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
    
    // Approximate Finnish seasons
    if (dayOfYear < 60 || dayOfYear >= 334) { // Winter: Dec-Feb
      return SeasonInfo(
        season: Season.winter,
        description: 'Winter in Finland',
        tips: 'Layer clothing, watch for slippery roads',
        daysLeft: dayOfYear < 60 ? 60 - dayOfYear : 425 - dayOfYear,
      );
    } else if (dayOfYear < 151) { // Spring: Mar-May
      return SeasonInfo(
        season: Season.spring,
        description: 'Spring in Finland',
        tips: 'Weather can change rapidly, dress accordingly',
        daysLeft: 151 - dayOfYear,
      );
    } else if (dayOfYear < 243) { // Summer: Jun-Aug
      return SeasonInfo(
        season: Season.summer,
        description: 'Summer in Finland',
        tips: 'Enjoy the midnight sun in northern Finland',
        daysLeft: 243 - dayOfYear,
      );
    } else { // Fall: Sep-Nov
      return SeasonInfo(
        season: Season.fall,
        description: 'Fall in Finland',
        tips: 'Prepare for decreasing daylight hours',
        daysLeft: 334 - dayOfYear,
      );
    }
  }
  
  /// Calculate daylight information based on location and date
  LightInfo getDayLightInfo(String city, DateTime date) {
    // Simplified calculation for demo purposes
    // In a real app, use astronomical calculations based on latitude
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
    final latitude = _getCityLatitude(city);
    
    // Calculate daylight hours based on latitude and day of year
    // This is a simplified sinusoidal approximation
    final midpoint = 172; // June 21st
    final amplitude = latitude * 0.133;
    final baseline = 12.0;
    
    final daylightHours = baseline + amplitude * cos(2 * pi * (dayOfYear - midpoint) / 365);
    
    // Calculate sunrise and sunset times
    final midDayTime = DateTime(date.year, date.month, date.day, 12, 0);
    final sunriseTime = midDayTime.subtract(Duration(minutes: (daylightHours * 30).round()));
    final sunsetTime = midDayTime.add(Duration(minutes: (daylightHours * 30).round()));
    
    String specialCondition = '';
    if (daylightHours > 20 && (dayOfYear > 152 && dayOfYear < 212)) {
      specialCondition = 'Midnight Sun';
    } else if (daylightHours < 4 && (dayOfYear < 31 || dayOfYear > 334)) {
      specialCondition = 'Polar Night';
    }
    
    return LightInfo(
      sunriseTime: sunriseTime, 
      sunsetTime: sunsetTime,
      daylightHours: daylightHours,
      specialCondition: specialCondition,
    );
  }
  
  double _getCityLatitude(String city) {
    // Simplified mapping of Finnish cities to latitude
    final latitudes = {
      'Helsinki': 60.17,
      'Tampere': 61.50,
      'Oulu': 65.01,
      'Rovaniemi': 66.50,
      'Utsjoki': 69.91,
    };
    
    return latitudes[city] ?? 60.17; // Default to Helsinki
  }
}

/// Weather Service - Handles weather API interactions
class WeatherService {
  /// Get weather data for the specified city
  /// In a real app, this would connect to a weather API
  Future<WeatherData> getWeather(String city) async {
    // Simulated API delay
    await Future.delayed(const Duration(milliseconds: 700));
    
    // In a real app, replace with actual API call:
    // final response = await http.get(Uri.parse('https://api.weather.com/v1/$city'));
    
    // Simulated weather data
    final temperature = 5 + Random().nextInt(20);
    final conditions = ['Sunny', 'Cloudy', 'Rainy', 'Snowy'][Random().nextInt(4)];
    
    return WeatherData(
      temperature: temperature.toDouble(),
      conditions: conditions,
      humidity: 40 + Random().nextInt(50),
      lastUpdated: DateTime.now(),
    );
  }
}

/// Location Repository - Handles persistent storage
class LocationRepository {
  final SharedPreferences _prefs;
  
  LocationRepository(this._prefs);
  
  Future<void> saveLocation(String city) async {
    await _prefs.setString('selectedCity', city);
  }
  
  Future<String?> getLocation() async {
    return _prefs.getString('selectedCity');
  }
  
  Future<void> saveDarkModePreference(bool isDarkMode) async {
    await _prefs.setBool('isDarkMode', isDarkMode);
  }
  
  Future<bool?> getDarkModePreference() async {
    return _prefs.getBool('isDarkMode');
  }
}

// Models

/// Weather data model
class WeatherData {
  final double temperature;
  final String conditions;
  final int humidity;
  final DateTime lastUpdated;
  
  WeatherData({
    required this.temperature,
    required this.conditions,
    required this.humidity,
    required this.lastUpdated,
  });
}

/// Season enumeration
enum Season { winter, spring, summer, fall }

/// Season information model
class SeasonInfo {
  final Season season;
  final String description;
  final String tips;
  final int daysLeft;
  
  SeasonInfo({
    required this.season,
    required this.description,
    required this.tips,
    required this.daysLeft,
  });
}

/// Day light information model
class LightInfo {
  final DateTime sunriseTime;
  final DateTime sunsetTime;
  final double daylightHours;
  final String specialCondition;
  
  LightInfo({
    required this.sunriseTime,
    required this.sunsetTime,
    required this.daylightHours,
    required this.specialCondition,
  });
}

// UI Screens and Components

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MVNConsumer<AppViewModel>(
      builder: (context, viewModel, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Finland Clock - ${viewModel.selectedCity}'),
            actions: [
              IconButton(
                icon: Icon(viewModel.isDarkMode ? Icons.light_mode : Icons.dark_mode),
                onPressed: viewModel.toggleDarkMode,
              ),
              IconButton(
                icon: const Icon(Icons.location_on),
                onPressed: () => _showLocationPicker(context, viewModel),
              ),
            ],
          ),
          body: viewModel.isLoading
              ? const Center(child: CircularProgressIndicator())
              : const ClockScreenContent(),
        );
      },
    );
  }
  
  void _showLocationPicker(BuildContext context, AppViewModel viewModel) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Select Location', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              for (final city in ['Helsinki', 'Tampere', 'Oulu', 'Rovaniemi', 'Utsjoki'])
                ListTile(
                  title: Text(city),
                  trailing: viewModel.selectedCity == city 
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                  onTap: () {
                    viewModel.setLocation(city);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class ClockScreenContent extends StatelessWidget {
  const ClockScreenContent({super.key});

  @override
@override
Widget build(BuildContext context) {
  return MVNConsumer<AppViewModel>(
    builder: (context, viewModel, _) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Tappable clock face
            GestureDetector(
              onTap: () {
                // Navigate to detail view when clock is tapped
                (context.findAncestorWidgetOfExactType<HomeScreen>() as HomeScreen)
                    .navigateToDetailScreen(context, viewModel.now);
              },
              child: SizedBox(
                width: 300,
                height: 300,
                child: Hero(
                  tag: 'clockFace',
                  child: _buildAnimatedClockFace(viewModel.now),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Digital time
            Text(
              _formatTime(viewModel.now),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              _formatDate(viewModel.now),
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 30),
            // Weather and season info cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildWeatherCard(context, viewModel),
                  const SizedBox(height: 16),
                  _buildSeasonCard(context, viewModel),
                  const SizedBox(height: 16),
                  _buildLightInfoCard(context, viewModel),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      );
    },
  );
}  
  Widget _buildAnimatedClockFace(DateTime now) {
    // Extract time components with smooth transitions
    final seconds = now.second + now.millisecond / 1000;
    final minutes = now.minute + seconds / 60;
    final hours = now.hour % 12 + minutes / 60;
    
    return AnimatedClockFace(
      hourAngle: (hours / 12) * 2 * pi,
      minuteAngle: (minutes / 60) * 2 * pi,
      secondAngle: (seconds / 60) * 2 * pi,
    );
  }
  
  Widget _buildWeatherCard(BuildContext context, AppViewModel viewModel) {
    final weather = viewModel.weatherData;
    if (weather == null) return const SizedBox.shrink();
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wb_sunny, size: 24),
                SizedBox(width: 8),
                Text(
                  'Current Weather',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      '${weather.temperature.toStringAsFixed(1)}°C',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(weather.conditions),
                  ],
                ),
                Column(
                  children: [
                    const Text('Humidity'),
                    const SizedBox(height: 4),
                    Text(
                      '${weather.humidity}%',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Updated: ${_formatTime(weather.lastUpdated)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSeasonCard(BuildContext context, AppViewModel viewModel) {
    final season = viewModel.seasonInfo;
    if (season == null) return const SizedBox.shrink();
    
    final seasonIcons = {
      Season.winter: Icons.ac_unit,
      Season.spring: Icons.local_florist,
      Season.summer: Icons.wb_sunny,
      Season.fall: Icons.eco,
    };
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(seasonIcons[season.season], size: 24),
                const SizedBox(width: 8),
                Text(
                  'Season: ${season.season.name.capitalize()}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(season.description),
            const SizedBox(height: 8),
            Text('Tip: ${season.tips}'),
            const SizedBox(height: 8),
            Text(
              '${season.daysLeft} days until next season',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLightInfoCard(BuildContext context, AppViewModel viewModel) {
    final light = viewModel.lightInfo;
    if (light == null) return const SizedBox.shrink();
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wb_twilight, size: 24),
                SizedBox(width: 8),
                Text(
                  'Daylight Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildLightTimeInfo(Icons.wb_sunny, 'Sunrise', _formatTime(light.sunriseTime)),
                _buildLightTimeInfo(Icons.nightlight, 'Sunset', _formatTime(light.sunsetTime)),
              ],
            ),
            const SizedBox(height: 16),
            Text('Daylight hours: ${light.daylightHours.toStringAsFixed(1)}h'),
            if (light.specialCondition.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[300]!),
                  ),
                  child: Text(
                    light.specialCondition,
                    style: TextStyle(color: Colors.amber[900], fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLightTimeInfo(IconData icon, String label, String time) {
    return Column(
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 4),
        Text(label),
        const SizedBox(height: 2),
        Text(
          time,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  
  String _formatDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    
    return '$weekday, $month ${date.day}, ${date.year}';
  }
}

/// Animated clock face with optimized rendering using CustomMultiChildLayout
class AnimatedClockFace extends StatelessWidget {
  final double hourAngle;
  final double minuteAngle;
  final double secondAngle;

  const AnimatedClockFace({
    super.key,
    required this.hourAngle,
    required this.minuteAngle,
    required this.secondAngle,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Stack(
        children: [
          // Clock face with hour markers
          ClockMarkers(isDarkMode: isDarkMode),
          
          // Clock hands using CustomMultiChildLayout for optimal positioning
          CustomMultiChildLayout(
            delegate: ClockLayoutDelegate(),
            children: [
              // Hour hand with TweenAnimationBuilder for smooth transitions
              LayoutId(
                id: 'hour',
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: hourAngle, end: hourAngle),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return ClockHand(
                      angle: value,
                      color: isDarkMode ? Colors.white : Colors.black,
                      thickness: 8,
                      length: 60,
                    );
                  },
                ),
              ),
              
              // Minute hand with TweenAnimationBuilder
              LayoutId(
                id: 'minute',
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: minuteAngle, end: minuteAngle),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return ClockHand(
                      angle: value,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      thickness: 5,
                      length: 80,
                    );
                  },
                ),
              ),
              
              // Second hand with direct update for crisp ticking
              LayoutId(
                id: 'second',
                child: ClockHand(
                  angle: secondAngle,
                  color: Colors.red,
                  thickness: 2,
                  length: 90,
                ),
              ),
              
              // Center dot
              LayoutId(
                id: 'center',
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Clock markers widget for hour indicators
class ClockMarkers extends StatelessWidget {
  final bool isDarkMode;
  
  const ClockMarkers({super.key, required this.isDarkMode});
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ClockFacePainter(isDarkMode: isDarkMode),
      size: const Size(300, 300),
    );
  }
}

/// Custom painter for clock face with hour markers
class ClockFacePainter extends CustomPainter {
  final bool isDarkMode;
  
  ClockFacePainter({required this.isDarkMode});
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    final markerColor = isDarkMode ? Colors.white70 : Colors.black87;
    final paint = Paint()
      ..color = markerColor
      ..style = PaintingStyle.fill;
    
    // Draw hour markers
    for (int i = 0; i < 12; i++) {
      final angle = i * pi / 6; // 2π/12 = π/6
      final markerRadius = i % 3 == 0 ? 8.0 : 4.0; // Larger markers for 12, 3, 6, 9
      
      final markerX = center.dx + (radius - 15) * cos(angle - pi/2);
      final markerY = center.dy + (radius - 15) * sin(angle - pi/2);
      
      canvas.drawCircle(Offset(markerX, markerY), markerRadius / 2, paint);
    }
  }
  
  @override
  bool shouldRepaint(ClockFacePainter oldDelegate) => 
      oldDelegate.isDarkMode != isDarkMode;
}

/// Clock hand widget with optimized rendering
class ClockHand extends StatelessWidget {
  final double angle;
  final Color color;
  final double thickness;
  final double length;

  const ClockHand({
    super.key,
    required this.angle,
    required this.color,
    required this.thickness,
    required this.length,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      alignment: Alignment.bottomCenter,
      child: Container(
        width: thickness,
        height: length,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(thickness / 2),
        ),
      ),
    );
  }
}

/// Custom layout delegate for optimal clock hand positioning
class ClockLayoutDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    layoutHand('hour', center);
    layoutHand('minute', center);
    layoutHand('second', center);
    layoutCenter('center', center);
  }

  void layoutHand(String id, Offset center) {
    if (hasChild(id)) {
      final handSize = layoutChild(
        id,
        BoxConstraints.loose(const Size(100, 300)),
      );
      
      // Position the hand with its bottom at the center of the clock
      positionChild(
        id,
        Offset(
          center.dx - handSize.width / 2,
          center.dy - handSize.height,
        ),
      );
    }
  }

  void layoutCenter(String id, Offset center) {
    if (hasChild(id)) {
      final centerSize = layoutChild(id, BoxConstraints.loose(const Size(16, 16)));
      
      // Position the center dot precisely in the middle
      positionChild(
        id,
        Offset(
          center.dx - centerSize.width / 2,
          center.dy - centerSize.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(ClockLayoutDelegate oldDelegate) => false;
}

// Utility extensions
extension StringExtensions on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

// Complete the ClockDetailScreen class that was cut off
class ClockDetailScreen extends StatelessWidget {
  final DateTime initialTime;

  const ClockDetailScreen({super.key, required this.initialTime});

  @override
  Widget build(BuildContext context) {
    return MVNConsumer<AppViewModel>(
      builder: (context, viewModel, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Clock Detail'),
            elevation: 0,
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Large clock display using Hero animation
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.width * 0.9,
                  child: Hero(
                    tag: 'clockFace',
                    child: _buildDetailClockFace(viewModel.now),
                  ),
                ),
                const SizedBox(height: 40),
                // Additional clock information
                Text(
                  _formatDetailTime(viewModel.now),
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  _formatDetailDate(viewModel.now),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 30),
                // Time zone information
                _buildTimeZoneInfo(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailClockFace(DateTime now) {
    // Extract time components with smooth transitions
    final seconds = now.second + now.millisecond / 1000;
    final minutes = now.minute + seconds / 60;
    final hours = now.hour % 12 + minutes / 60;
    
    return DetailedClockFace(
      hourAngle: (hours / 12) * 2 * pi,
      minuteAngle: (minutes / 60) * 2 * pi,
      secondAngle: (seconds / 60) * 2 * pi,
    );
  }
  
  String _formatDetailTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
  
  String _formatDetailDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    
    return '$weekday, $month ${date.day}, ${date.year}';
  }
  
  Widget _buildTimeZoneInfo() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.language),
                SizedBox(width: 8),
                Text(
                  'Finland Time Zone',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'EET - Eastern European Time (UTC+2)',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Summer: EEST - Eastern European Summer Time (UTC+3)',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// Add a more detailed clock face for the detail screen
class DetailedClockFace extends StatelessWidget {
  final double hourAngle;
  final double minuteAngle;
  final double secondAngle;

  const DetailedClockFace({
    super.key,
    required this.hourAngle,
    required this.minuteAngle,
    required this.secondAngle,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 15,
            spreadRadius: 3,
          )
        ],
        border: Border.all(
          color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
          width: 4,
        ),
      ),
      child: Stack(
        children: [
          // Detailed clock face with minute markers
          DetailedClockMarkers(isDarkMode: isDarkMode),
          
          // Clock hands using CustomMultiChildLayout for optimal positioning
          CustomMultiChildLayout(
            delegate: DetailedClockLayoutDelegate(),
            children: [
              // Hour hand with TweenAnimationBuilder for smooth transitions
              LayoutId(
                id: 'hour',
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: hourAngle, end: hourAngle),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return DetailedClockHand(
                      angle: value,
                      color: isDarkMode ? Colors.white : Colors.black,
                      thickness: 10,
                      length: 70,
                      isDarkMode: isDarkMode,
                    );
                  },
                ),
              ),
              
              // Minute hand with TweenAnimationBuilder
              LayoutId(
                id: 'minute',
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: minuteAngle, end: minuteAngle),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return DetailedClockHand(
                      angle: value,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      thickness: 6,
                      length: 100,
                      isDarkMode: isDarkMode,
                    );
                  },
                ),
              ),
              
              // Second hand with direct update for crisp ticking
              LayoutId(
                id: 'second',
                child: DetailedClockHand(
                  angle: secondAngle,
                  color: Colors.red,
                  thickness: 3,
                  length: 110,
                  isDarkMode: isDarkMode,
                  hasCounterweight: true,
                ),
              ),
              
              // Center dot
              LayoutId(
                id: 'center',
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDarkMode ? Colors.white : Colors.black,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Detailed clock markers widget for hour and minute indicators
class DetailedClockMarkers extends StatelessWidget {
  final bool isDarkMode;
  
  const DetailedClockMarkers({super.key, required this.isDarkMode});
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DetailedClockFacePainter(isDarkMode: isDarkMode),
      size: const Size(300, 300),
    );
  }
}

// Custom painter for detailed clock face with hour and minute markers
class DetailedClockFacePainter extends CustomPainter {
  final bool isDarkMode;
  
  DetailedClockFacePainter({required this.isDarkMode});
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    final markerColor = isDarkMode ? Colors.white70 : Colors.black87;
    final paint = Paint()
      ..color = markerColor
      ..style = PaintingStyle.fill;
    
    // Draw hour markers
    for (int i = 0; i < 12; i++) {
      final angle = i * pi / 6; // 2π/12 = π/6
      
      // Draw hour numbers
      final textPainter = TextPainter(
        text: TextSpan(
          text: i == 0 ? '12' : i.toString(),
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      
      final hourNumberX = center.dx + (radius - 30) * cos(angle - pi/2) - textPainter.width / 2;
      final hourNumberY = center.dy + (radius - 30) * sin(angle - pi/2) - textPainter.height / 2;
      
      textPainter.paint(canvas, Offset(hourNumberX, hourNumberY));
      
      // Draw hour markers
      final hourMarkerX = center.dx + (radius - 15) * cos(angle - pi/2);
      final hourMarkerY = center.dy + (radius - 15) * sin(angle - pi/2);
      
      canvas.drawCircle(Offset(hourMarkerX, hourMarkerY), 4, paint);
    }
    
    // Draw minute markers
    final minutePaint = Paint()
      ..color = markerColor.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    
    for (int i = 0; i < 60; i++) {
      // Skip positions where hour markers are
      if (i % 5 == 0) continue;
      
      final angle = i * pi / 30; // 2π/60 = π/30
      
      final minuteMarkerX = center.dx + (radius - 10) * cos(angle - pi/2);
      final minuteMarkerY = center.dy + (radius - 10) * sin(angle - pi/2);
      
      canvas.drawCircle(Offset(minuteMarkerX, minuteMarkerY), 1.5, minutePaint);
    }
  }
  
  @override
  bool shouldRepaint(DetailedClockFacePainter oldDelegate) => 
      oldDelegate.isDarkMode != isDarkMode;
}

// Enhanced clock hand with shadow and optional counterweight
class DetailedClockHand extends StatelessWidget {
  final double angle;
  final Color color;
  final double thickness;
  final double length;
  final bool isDarkMode;
  final bool hasCounterweight;

  const DetailedClockHand({
    super.key,
    required this.angle,
    required this.color,
    required this.thickness,
    required this.length,
    required this.isDarkMode,
    this.hasCounterweight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      alignment: hasCounterweight ? Alignment.center : Alignment.bottomCenter,
      child: Container(
        width: thickness,
        height: hasCounterweight ? length * 1.2 : length,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(thickness / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: const Offset(1, 1),
            ),
          ],
        ),
        alignment: hasCounterweight ? Alignment.topCenter : Alignment.center,
        child: hasCounterweight
            ? Container(
                width: thickness * 3,
                height: thickness * 3,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                margin: EdgeInsets.only(bottom: length * 0.15),
              )
            : null,
      ),
    );
  }
}

// Custom layout delegate for detailed clock hand positioning
class DetailedClockLayoutDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Layout hands with consideration for counterweight
    if (hasChild('hour')) {
      final hourSize = layoutChild(
        'hour',
        BoxConstraints.loose(const Size(100, 300)),
      );
      positionChild(
        'hour',
        Offset(
          center.dx - hourSize.width / 2,
          center.dy - hourSize.height / 2,
        ),
      );
    }

    if (hasChild('minute')) {
      final minuteSize = layoutChild(
        'minute',
        BoxConstraints.loose(const Size(100, 300)),
      );
      positionChild(
        'minute',
        Offset(
          center.dx - minuteSize.width / 2,
          center.dy - minuteSize.height / 2,
        ),
      );
    }

    if (hasChild('second')) {
      final secondSize = layoutChild(
        'second',
        BoxConstraints.loose(const Size(100, 300)),
      );
      positionChild(
        'second',
        Offset(
          center.dx - secondSize.width / 2,
          center.dy - secondSize.height / 2,
        ),
      );
    }

    if (hasChild('center')) {
      final centerSize = layoutChild(
        'center',
        BoxConstraints.loose(const Size(20, 20)),
      );
      positionChild(
        'center',
        Offset(
          center.dx - centerSize.width / 2,
          center.dy - centerSize.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(DetailedClockLayoutDelegate oldDelegate) => false;
}

// Extension method to navigate to the detail screen
extension ClockNavigation on HomeScreen {
  void navigateToDetailScreen(BuildContext context, DateTime time) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClockDetailScreen(initialTime: time),
      ),
    );
  }
}


// Add these additional utility functions for Finnish time zone handling
class FinnishTimeZone {
  // Check if current date is in Finnish Daylight Saving Time
  static bool isInDaylightSavingTime(DateTime date) {
    // Finnish DST generally starts on last Sunday of March
    // and ends on last Sunday of October
    final int year = date.year;
    
    // Find last Sunday of March
    DateTime lastSundayMarch = _findLastSundayOfMonth(year, 3);
    
    // Find last Sunday of October
    DateTime lastSundayOctober = _findLastSundayOfMonth(year, 10);
    
    // Check if date is between these two dates
    return date.isAfter(lastSundayMarch) && date.isBefore(lastSundayOctober);
  }
  
  // Find the last Sunday of a given month and year
  static DateTime _findLastSundayOfMonth(int year, int month) {
    // Get the last day of the month
    final daysInMonth = DateTime(year, month + 1, 0).day;
    
    // Start from the last day and go backward until we find a Sunday
    for (int day = daysInMonth; day > 0; day--) {
      final date = DateTime(year, month, day);
      if (date.weekday == DateTime.sunday) {
        return date;
      }
    }
    
    // This should never happen as every month has at least one Sunday
    return DateTime(year, month, 1);
  }
  
  // Get current Finnish time offset from UTC
  static String getCurrentOffset(DateTime date) {
    return isInDaylightSavingTime(date) ? 'UTC+3 (EEST)' : 'UTC+2 (EET)';
  }
}

// Add this function to TimeService to correctly handle Finnish time zones
extension TimeServiceExtension on TimeService {
  String getTimeZoneDescription(DateTime date) {
    final isDST = FinnishTimeZone.isInDaylightSavingTime(date);
    if (isDST) {
      return 'EEST - Eastern European Summer Time (UTC+3)';
    } else {
      return 'EET - Eastern European Time (UTC+2)';
    }
  }
}

// Add a seasonal background effect to the clock detail screen
class SeasonalBackground extends StatelessWidget {
  final Season season;
  
  const SeasonalBackground({super.key, required this.season});
  
  @override
  Widget build(BuildContext context) {
    // Define colors and patterns based on season
    Color primaryColor;
    Color secondaryColor;
    IconData patternIcon;
    
    switch (season) {
      case Season.winter:
        primaryColor = Colors.blue.shade100;
        secondaryColor = Colors.white;
        patternIcon = Icons.ac_unit;
        break;
      case Season.spring:
        primaryColor = Colors.green.shade100;
        secondaryColor = Colors.yellow.shade100;
        patternIcon = Icons.local_florist;
        break;
      case Season.summer:
        primaryColor = Colors.yellow.shade100;
        secondaryColor = Colors.orange.shade100;
        patternIcon = Icons.wb_sunny;
        break;
      case Season.fall:
        primaryColor = Colors.orange.shade100;
        secondaryColor = Colors.brown.shade100;
        patternIcon = Icons.eco;
        break;
    }
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, secondaryColor],
        ),
      ),
      child: CustomPaint(
        painter: SeasonalPatternPainter(
          season: season,
          patternIcon: patternIcon,
          patternColor: primaryColor.darker(20),
        ),
        size: Size.infinite,
      ),
    );
  }
}

// Custom painter for seasonal patterns
class SeasonalPatternPainter extends CustomPainter {
  final Season season;
  final IconData patternIcon;
  final Color patternColor;
  
  SeasonalPatternPainter({
    required this.season,
    required this.patternIcon,
    required this.patternColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final iconSize = size.width / 20;
    final iconSpacing = size.width / 10;
    
    // Create a pattern of icons
    for (double x = 0; x < size.width; x += iconSpacing) {
      for (double y = 0; y < size.height; y += iconSpacing) {
        // Add some randomness to position
        final offsetX = (x + Random().nextDouble() * 10) % size.width;
        final offsetY = (y + Random().nextDouble() * 10) % size.height;
        
        // Draw the icon with a random rotation
        final textPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(patternIcon.codePoint),
            style: TextStyle(
              color: patternColor.withOpacity(0.2),
              fontSize: iconSize,
              fontFamily: 'MaterialIcons',
              package: 'material_icons_one',
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        
        textPainter.layout();
        
        canvas.save();
        canvas.translate(offsetX, offsetY);
        canvas.rotate(Random().nextDouble() * pi / 2);
        textPainter.paint(
          canvas,
          Offset(-textPainter.width / 2, -textPainter.height / 2),
        );
        canvas.restore();
      }
    }
  }
  
  @override
  bool shouldRepaint(SeasonalPatternPainter oldDelegate) =>
      oldDelegate.season != season ||
      oldDelegate.patternIcon != patternIcon ||
      oldDelegate.patternColor != patternColor;
}

// Add this extension method to darken colors
extension ColorExtension on Color {
  Color darker(int percent) {
    assert(1 <= percent && percent <= 100);
    final factor = 1 - percent / 100;
    return Color.fromARGB(
      alpha,
      (red * factor).round(),
      (green * factor).round(),
      (blue * factor).round(),
    );
  }
}

// Add this to integrate the seasonal background with the detail screen
class SeasonalClockDetailScreen extends StatelessWidget {
  final DateTime initialTime;

  const SeasonalClockDetailScreen({super.key, required this.initialTime});

  @override
  Widget build(BuildContext context) {
    return MVNConsumer<AppViewModel>(
      builder: (context, viewModel, _) {
        final season = viewModel.seasonInfo?.season ?? Season.winter;
        
        return Scaffold(
          body: Stack(
            children: [
              // Seasonal background
              SeasonalBackground(season: season),
              
              // Content with app bar and clock
              Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  title: const Text('Finland Clock Detail'),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                ),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Large clock display using Hero animation
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.width * 0.9,
                        child: Hero(
                          tag: 'clockFace',
                          child: _buildDetailClockFace(viewModel.now),
                        ),
                      ),
                      // Rest of the content as in ClockDetailScreen
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  // Same as in ClockDetailScreen
  Widget _buildDetailClockFace(DateTime now) {
    // Extract time components with smooth transitions
    final seconds = now.second + now.millisecond / 1000;
    final minutes = now.minute + seconds / 60;
    final hours = now.hour % 12 + minutes / 60;
    
    return DetailedClockFace(
      hourAngle: (hours / 12) * 2 * pi,
      minuteAngle: (minutes / 60) * 2 * pi,
      secondAngle: (seconds / 60) * 2 * pi,
    );
  }
}

// Additional widget for weather forecast in the main screen
class WeatherForecastWidget extends StatelessWidget {
  final String city;
  
  const WeatherForecastWidget({super.key, required this.city});
  
  @override
  Widget build(BuildContext context) {
    // Simulated forecast data
    final forecast = [
      _generateForecastDay(DateTime.now(), city),
      _generateForecastDay(DateTime.now().add(const Duration(days: 1)), city),
      _generateForecastDay(DateTime.now().add(const Duration(days: 2)), city),
    ];
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_today, size: 24),
                SizedBox(width: 8),
                Text(
                  '3-Day Forecast',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: forecast.map((day) => _buildForecastDay(day)).toList(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildForecastDay(Map<String, dynamic> forecast) {
    // Icons for different weather conditions
    final weatherIcons = {
      'Sunny': Icons.wb_sunny,
      'Cloudy': Icons.cloud,
      'Rainy': Icons.grain,
      'Snowy': Icons.ac_unit,
    };
    
    return Column(
      children: [
        Text(
          forecast['day'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Icon(
          weatherIcons[forecast['condition']] ?? Icons.question_mark,
          size: 28,
          color: _getWeatherColor(forecast['condition']),
        ),
        const SizedBox(height: 8),
        Text(
          '${forecast['temp']}°C',
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }
  
  Color _getWeatherColor(String condition) {
    switch (condition) {
      case 'Sunny': return Colors.orange;
      case 'Cloudy': return Colors.grey;
      case 'Rainy': return Colors.blue;
      case 'Snowy': return Colors.lightBlue;
      default: return Colors.black;
    }
  }
  
  Map<String, dynamic> _generateForecastDay(DateTime date, String city) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final conditions = ['Sunny', 'Cloudy', 'Rainy', 'Snowy'];
    
    // Use city and date to create somewhat deterministic "random" forecast
    final cityHash = city.hashCode;
    final dateHash = date.day + date.month;
    final combinedHash = (cityHash + dateHash) % 100;
    
    final conditionIndex = combinedHash % 4;
    final temperature = (combinedHash % 30) - 5; // -5 to 24 degrees
    
    return {
      'day': weekdays[date.weekday - 1],
      'condition': conditions[conditionIndex],
      'temp': temperature,
    };
  }
}
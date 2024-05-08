import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> initializeNotification() async {
  /// OPTIONAL, using custom notification channel id
  AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'background_handle', // id
    'MY SERVICE', // title
    'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isIOS || Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: IOSInitializationSettings(),
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,
      // auto start service
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'background_handle',
      initialNotificationTitle: 'AWESOME SERVICE',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,
      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,
      // you have to enable background fetch capability on xcode project
      onBackground: onIosBackground,
    ),
  );
  FlutterBackgroundService().invoke("setAsBackground");
}

// to ensure this is executed
// run app from xcode, then from xcode menu, select Simulate Background Fetch
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp(); //firebase initialize
  CollectionReference users = FirebaseFirestore.instance
      .collection('backgroundservice'); //Firebase collection

  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  int value = 1;
  // bring to foreground
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    value++;
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        /// OPTIONAL for use custom notification
        /// the notification id must be equals with AndroidConfiguration when you call configure() method.
        flutterLocalNotificationsPlugin.show(
            888,
            'COOL SERVICE',
            'Awesome ${DateTime.now()}',
            const NotificationDetails(
                android: AndroidNotificationDetails(
                    'background_handle', 'MY SERVICE', 'ic_bg_service_small',
                    ongoing: true)));

        // if you don't using custom notification, uncomment this
        service.setForegroundNotificationInfo(
          title: "My App Service $value",
          content: "Updated at ${DateTime.now()}",
        );
      }
    }

    /// you can see this log in logcat
    print('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');
    final serviceCheck = FlutterBackgroundService();
    if (await serviceCheck.isRunning()) {
      users
          .doc('currentTime')
          .update({
            'timestamp': DateTime.now().toIso8601String(),
            'value': value.toString()
          })
          .then((value) => print("Added"))
          .catchError((error) => print("Failed to add data: $error"));
      service.invoke(
        'update',
        {
          "current_date": DateTime.now().toIso8601String(),
          "device": Platform.isAndroid ? 'Android' : 'IOS',
          "value": value.toString()
        },
      );
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
          options: const FirebaseOptions(
              apiKey: "AIzaSyCAQuV9NxYB76UwM1J1UR0ND7DwSJq-6g0",
              appId: "1:455891089327:android:854492b1a9e14ca237a15a",
              messagingSenderId: "455891089327",
              projectId: "mystore-6d10c"))
      .whenComplete(() {
    print("firebase initial complete completed");
  });
  await initializeNotification();
  await initializeService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late IconData icon;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    icon = Icons.play_arrow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setIcon();
    });
  }

  Future<void> setIcon() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (isRunning) {
      icon = Icons.stop;
    } else {
      icon = Icons.play_arrow;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            StreamBuilder<Map<String, dynamic>?>(
              stream: FlutterBackgroundService().on('update'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                final data = snapshot.data!;
                String? device = data["device"];
                String? value = data["value"];

                DateTime? date = DateTime.tryParse(data["current_date"]);
                return Column(
                  children: [
                    Text(value ?? 'Unknown'),
                    Text(device ?? 'Unknown'),
                    Text(date.toString()),
                  ],
                );
              },
            ),
            ElevatedButton(
              child: const Text("Foreground Mode"),
              onPressed: () {
                FlutterBackgroundService().invoke("setAsForeground");
              },
            ),
            ElevatedButton(
              child: const Text("Background Mode"),
              onPressed: () {
                FlutterBackgroundService().invoke("setAsBackground");
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          try {
            final service = FlutterBackgroundService();
            var isRunning = await service.isRunning();
            if (isRunning) {
              service.invoke("stopService");
            } else {
              service.startService();
            }

            if (!isRunning) {
              icon = Icons.stop;
            } else {
              icon = Icons.play_arrow;
            }
            setState(() {});
          } catch (e) {
            print('Catch ---> ${e.toString()}');
          }
        },
        tooltip: 'Start',
        child: Icon(icon),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
